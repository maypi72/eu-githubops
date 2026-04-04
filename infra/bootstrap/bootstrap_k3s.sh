#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Configuración de K3s
K3S_VERSION="${K3S_VERSION:-v1.34.4+k3s1}"
K3S_CHANNEL="${K3S_CHANNEL:-stable}"
K3S_INSTALL_SCRIPT_URL="https://get.k3s.io"

# Opciones fijas de instalación para deshabilitar componentes y usar Calico
K3S_EXEC_OPTS="--disable traefik --disable servicelb --flannel-backend=none --disable-network-policy --write-kubeconfig-mode 644"

# Configuración de Calico (usando Operator, CRDs y Custom Resources)
CALICO_VERSION="${CALICO_VERSION:-3.30.7}"
CALICO_BASE_URL="https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests"
CALICO_CRDS_URL="${CALICO_BASE_URL}/operator-crds.yaml"
CALICO_OPERATOR_URL="${CALICO_BASE_URL}/tigera-operator.yaml"
CALICO_CUSTOM_RESOURCES_URL="${CALICO_BASE_URL}/custom-resources.yaml"

retry() {
  local -r max=${RETRY_MAX:-5}
  local -r delay=${RETRY_DELAY:-2}
  local i=0
  until "$@"; do
    i=$((i+1))
    if [ $i -ge $max ]; then
      echo "Command failed after $i attempts: $*"
      return 1
    fi
    echo "Retry $i/$max: $*"
    sleep $((delay * i))
  done
}

install_dependencies() {
  echo "::group::Preparando sistema"
  echo "Verificando requisitos previos..."

  # Verificar puertos disponibles
  echo "Verificando puertos disponibles:"
  netstat -tuln 2>/dev/null | grep -E ":6443|:10250" || echo "⚠ Puerto 6443 (API) disponible"

  # Verificar conectividad DNS
  echo ""
  echo "Verificando DNS:"
  if nslookup kubernetes.default.svc.cluster.local 8.8.8.8 >/dev/null 2>&1 || true; then
    echo "✓ DNS funcional"
  fi

  # Limpiar instalación antigua si existe
  if [ -d "/var/lib/rancher/k3s" ]; then
    echo "⚠ Directorio /var/lib/rancher/k3s ya existe"
    echo "  Si hay problemas, considera: sudo rm -rf /var/lib/rancher/k3s"
  fi

  echo ""
  sudo apt-get update -y
  sudo apt-get install -y curl jq ca-certificates
  sudo swapoff -a || true
  sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true
  echo "::endgroup::"
}

install_k3s() {
  echo "::group::Comprobando si k3s ya está instalado"
  if command -v k3s >/dev/null 2>&1; then
    echo "k3s ya instalado: $(k3s --version)"
    echo "::endgroup::"
    return 0
  fi
  echo "k3s no instalado, procediendo..."
  echo ""
  echo "Opciones de instalación:"
  echo "  Versión: ${K3S_VERSION}"
  echo "  Canal: ${K3S_CHANNEL}"
  echo "  Opciones: ${K3S_EXEC_OPTS}"
  echo "::endgroup::"

  echo "::group::Instalando k3s"

  # Ejecutar instalación de k3s
  if ! curl -sfL "${K3S_INSTALL_SCRIPT_URL}" | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_CHANNEL="${K3S_CHANNEL}" \
    INSTALL_K3S_EXEC="server ${K3S_EXEC_OPTS}" \
    sh -s -; then
    echo "ERROR: Falló la ejecución del script de instalación de k3s"
    exit 1
  fi

  # Esperar a que el servicio k3s esté listo
  echo "Esperando a que k3s.service inicie..."
  sleep 5

  # Verificar que el servicio está activo
  if ! systemctl is-active --quiet k3s; then
    echo "ERROR: k3s.service no está activo"
    echo ""
    echo "Estado del servicio k3s:"
    systemctl status k3s || true
    echo ""
    echo "Últimos logs de k3s:"
    journalctl -xeu k3s.service -n 50 || true
    exit 1
  fi

  echo "✓ k3s instalado y servicio activo"
  echo "::endgroup::"
}

wait_for_openapi_ready() {
  echo "::group::Esperando a que el API server esté plenamente disponible"
  echo "⏳ Esperando a que OpenAPI esté listo..."
  retry kubectl cluster-info
  echo "✓ API server está disponible"
  echo "::endgroup::"
}

install_calico() {
  echo "::group::Instalando Calico CNI"
  echo "📦 Instalando CRDs de Calico..."
  retry kubectl apply -f "${CALICO_CRDS_URL}" --validate=false

  echo "📦 Instalando Tigera Operator..."
  retry kubectl apply -f "${CALICO_OPERATOR_URL}" --validate=false

  echo "📦 Esperando a que el Operator esté listo..."
  sleep 10
  retry kubectl wait --for=condition=Ready pod -l k8s-app=tigera-operator -n tigera-operator --timeout=300s

  echo "📦 Aplicando Custom Resources de Calico..."
  retry kubectl apply -f "${CALICO_CUSTOM_RESOURCES_URL}" --validate=false

  echo "✓ Calico instalado correctamente"
  echo "::endgroup::"
}

wait_for_calico_ready() {
  echo "::group::Esperando a que Calico esté completamente listo"
  echo "⏳ Esperando a que Calico esté listo..."
  retry kubectl -n calico-system wait --for=condition=Available deployment --all --timeout=180s
  echo "✓ Calico está listo"
  echo "::endgroup::"
}

wait_for_node_ready() {
  echo "::group::Esperando a que el nodo esté Ready"
  retry kubectl wait --for=condition=Ready node --all --timeout=300s
  echo "✓ Nodo está Ready"
  echo "::endgroup::"
}


# ============================================================
# Ejecución principal del bootstrap en orden correcto
# ============================================================

install_dependencies
install_k3s
wait_for_openapi_ready
install_calico
wait_for_calico_ready
wait_for_node_ready

echo "::group::Preparando kubeconfig para el runner"
KUBECONFIG="${KUBECONFIG:-$HOME/kubeconfig}"

# Comprobar que el archivo fuente existe
if [ ! -f "/etc/rancher/k3s/k3s.yaml" ]; then
  echo "ERROR: /etc/rancher/k3s/k3s.yaml no encontrado"
  echo ""
  echo "Diagnosis:"
  echo "1. Verificar que k3s está activo:"
  systemctl status k3s || true
  echo ""
  echo "2. Verificar logs de k3s:"
  journalctl -xeu k3s.service -n 30 || true
  echo ""
  echo "3. Verificar que el servicio está corriendo:"
  ps aux | grep -i k3s | grep -v grep || echo "No k3s process found"
  echo ""
  echo "Para reinstalar, ejecuta: sudo /usr/local/bin/k3s-uninstall.sh && rm -rf /etc/rancher"
  exit 1
fi

# Crear directorio si no existe
mkdir -p "$(dirname "$KUBECONFIG")"

# Copiar kubeconfig (ahora readable gracias a --write-kubeconfig-mode 644)
echo "Copiando kubeconfig desde /etc/rancher/k3s/k3s.yaml..."
if ! cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG"; then
  echo "ERROR: No se pudo copiar kubeconfig"
  echo "Intentando con sudo..."
  if ! sudo cat /etc/rancher/k3s/k3s.yaml > "$KUBECONFIG"; then
    echo "ERROR: No se pudo copiar kubeconfig (permiso denegado)"
    exit 1
  fi
fi

# Cambiar permisos para que solo el owner pueda leer/escribir (más seguro)
echo "Estableciendo permisos restrictivos..."
if ! chmod 600 "$KUBECONFIG"; then
  echo "⚠ Advertencia: No se pudo cambiar permisos a 600"
  echo "  Continuando con permisos actuales"
fi

# Verificar que el archivo se copió correctamente
if [ ! -f "$KUBECONFIG" ]; then
  echo "ERROR: kubeconfig no existe después de copiar"
  exit 1
fi

export KUBECONFIG
echo "✓ KUBECONFIG preparado en $KUBECONFIG"
echo "✓ Tamaño: $(du -h "$KUBECONFIG" | cut -f1)"
echo "✓ Permisos: $(stat -c '%a' "$KUBECONFIG" 2>/dev/null || echo 'desconocidos')"
echo "::endgroup::"

echo "::group::Esperando a que el nodo sea visible en el cluster"
retry kubectl get nodes
echo "::endgroup::"

echo "::group::Verificando estado final del cluster"
echo "Esperando a que todos los pods del sistema estén en estado Running o Succeeded..."

TIMEOUT_SECONDS=300  # 5 minutos
ELAPSED=0
CHECK_INTERVAL=5

while [ $ELAPSED -lt $TIMEOUT_SECONDS ]; do
  # Contar pods en estado Running o Succeeded en kube-system
  RUNNING_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  SUCCEEDED_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase=Succeeded --no-headers 2>/dev/null | wc -l)
  
  # Contar pods NO en estado Running o Succeeded (Pending, Failed, CrashLoopBackOff, etc.)
  NOT_READY=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
  
  TOTAL=$((RUNNING_PODS + SUCCEEDED_PODS + NOT_READY))
  
  echo "✓ Pods en kube-system: Running=$RUNNING_PODS | Succeeded=$SUCCEEDED_PODS | Otros=$NOT_READY | Total=$TOTAL | Tiempo: ${ELAPSED}s"
  
  # Si todos los pods estén listos, salir
  if [ $NOT_READY -eq 0 ] && [ $TOTAL -gt 0 ]; then
    echo "✓ ¡Todos los pods de K3s están Running o Succeeded!"
    break
  fi
  
  sleep $CHECK_INTERVAL
  ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $NOT_READY -gt 0 ]; then
  echo "⚠ Algunos pods aún no están Ready, continuando..."
  echo ""
  echo "Pods no listos en kube-system:"
  kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded || true
fi
echo "::endgroup::"

echo "✓ ¡Bootstrap completado exitosamente!"

