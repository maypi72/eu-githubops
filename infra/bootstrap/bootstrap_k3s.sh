#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Configuración de K3s
K3S_VERSION="${K3S_VERSION:-v1.34.4+k3s1}"
K3S_CHANNEL="${K3S_CHANNEL:-stable}"
K3S_INSTALL_SCRIPT_URL="https://get.k3s.io"

# Opciones fijas de instalación para deshabilitar componentes innecesarios
# K3s usa Flannel como CNI por defecto (no se requiere instalación adicional)
K3S_EXEC_OPTS="--disable traefik --disable servicelb --write-kubeconfig-mode 644"

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

retry() {
  local -r max=${RETRY_MAX:-5}
  local -r delay=${RETRY_DELAY:-2}
  local i=0
  until "$@"; do
    i=$((i+1))
    if [ $i -ge $max ]; then
      echo -e "${RED}Command failed after $i attempts: $*${NC}"
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
  netstat -tuln 2>/dev/null | grep -E ":6443|:10250" || echo -e "${YELLOW}⚠ Puerto 6443 (API) disponible${NC}"

  # Verificar conectividad DNS
  echo ""
  echo "Verificando DNS:"
  if nslookup kubernetes.default.svc.cluster.local 8.8.8.8 >/dev/null 2>&1 || true; then
    echo -e "${GREEN}✓ DNS funcional${NC}"
  fi

  # Limpiar instalación antigua si existe
  if [ -d "/var/lib/rancher/k3s" ]; then
    echo -e "${YELLOW}⚠ Directorio /var/lib/rancher/k3s ya existe${NC}"
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
    echo -e "${RED}ERROR: Falló la ejecución del script de instalación de k3s${NC}"
    exit 1
  fi

  # Esperar a que el servicio k3s esté listo
  echo "Esperando a que k3s.service inicie..."
  sleep 5

  # Verificar que el servicio está activo
  if ! systemctl is-active --quiet k3s; then
    echo -e "${RED}ERROR: k3s.service no está activo${NC}"
    echo ""
    echo "Estado del servicio k3s:"
    systemctl status k3s || true
    echo ""
    echo "Últimos logs de k3s:"
    journalctl -xeu k3s.service -n 50 || true
    exit 1
  fi

  echo -e "${GREEN}✓ k3s instalado y servicio activo${NC}"
  echo "::endgroup::"
}

wait_for_openapi_ready() {
  echo "::group::Esperando a que el API server esté plenamente disponible"
  echo "⏳ Esperando a que OpenAPI esté listo..."
  retry kubectl cluster-info
  echo -e "${GREEN}✓ API server está disponible${NC}"
  echo "::endgroup::"
}

wait_for_flannel_ready() {
  echo "::group::Esperando a que Flannel esté completamente listo"
  echo "⏳ Esperando a que Flannel esté listo..."
  retry kubectl -n kube-flannel wait --for=condition=Available deployment --all --timeout=180s
  echo -e "${GREEN}✓ Flannel está listo${NC}"
  echo "::endgroup::"
}

wait_for_node_ready() {
  echo "::group::Esperando a que el nodo esté Ready"
  retry kubectl wait --for=condition=Ready node --all --timeout=300s
  echo -e "${GREEN}✓ Nodo está Ready${NC}"
  echo "::endgroup::"
}


# ============================================================
# Ejecución principal del bootstrap en orden correcto
# ============================================================

# Primero verificar si k3s ya está instalado
echo "::group::Comprobando si k3s ya está instalado"
if command -v k3s >/dev/null 2>&1; then
  echo -e "${GREEN}✓ k3s ya está instalado: $(k3s --version)${NC}"
  echo "::endgroup::"
else
  echo "k3s no está instalado, procediendo con instalación..."
  echo "::endgroup::"
  # Solo instalar dependencias si k3s no está presente
  install_dependencies
fi

install_k3s

# Copiar kubeconfig temprano para que esté disponible para sus scripts
echo "::group::Configurando KUBECONFIG"
KUBECONFIG="${KUBECONFIG:-${HOME}/kubeconfig}"
export KUBECONFIG
mkdir -p "$(dirname "$KUBECONFIG")"

echo "Copiando kubeconfig de /etc/rancher/k3s/k3s.yaml a $KUBECONFIG..."
if ! sudo cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG"; then
  echo -e "${RED}ERROR: No se pudo copiar el kubeconfig${NC}"
  exit 1
fi
sudo chmod 600 "$KUBECONFIG"
sudo chown "$(id -u):$(id -g)" "$KUBECONFIG"
echo -e "${GREEN}✓ KUBECONFIG disponible: $KUBECONFIG${NC}"
echo "::endgroup::"

wait_for_openapi_ready

echo "::group::Verificando CNI (Flannel)"
echo -e "${GREEN}✓ Flannel está incluido por defecto en K3s${NC}"
echo "  Flannel proporciona red superpuesta simple y eficiente"
echo "::endgroup::"

wait_for_flannel_ready
wait_for_node_ready

echo "::group::Verificando kubeconfig"
if [ ! -f "$KUBECONFIG" ]; then
  echo -e "${RED}ERROR: kubeconfig no disponible en $KUBECONFIG${NC}"
  exit 1
fi
echo -e "${GREEN}✓ KUBECONFIG disponible en $KUBECONFIG${NC}"
echo -e "${GREEN}✓ Tamaño: $(du -h "$KUBECONFIG" | cut -f1)${NC}"
echo -e "${GREEN}✓ Permisos: $(stat -c '%a' "$KUBECONFIG" 2>/dev/null || echo 'desconocidos')${NC}"
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
  
  echo -e "${GREEN}✓${NC} Pods en kube-system: Running=$RUNNING_PODS | Succeeded=$SUCCEEDED_PODS | Otros=$NOT_READY | Total=$TOTAL | Tiempo: ${ELAPSED}s"
  
  # Si todos los pods estén listos, salir
  if [ $NOT_READY -eq 0 ] && [ $TOTAL -gt 0 ]; then
    echo -e "${GREEN}✓ ¡Todos los pods de K3s están Running o Succeeded!${NC}"
    break
  fi
  
  sleep $CHECK_INTERVAL
  ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $NOT_READY -gt 0 ]; then
  echo -e "${YELLOW}⚠ Algunos pods aún no están Ready, continuando...${NC}"
  echo ""
  echo "Pods no listos en kube-system:"
  kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded || true
fi
echo "::endgroup::"

echo -e "${GREEN}✓ ¡Bootstrap completado exitosamente!${NC}"

