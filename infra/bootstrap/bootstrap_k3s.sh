#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================
# BOOTSTRAP K3S - Instalación limpia de K3s con Flannel
# ============================================================

# Configuración de K3s
K3S_VERSION="${K3S_VERSION:-v1.34.4+k3s1}"
K3S_CHANNEL="${K3S_CHANNEL:-stable}"
K3S_INSTALL_SCRIPT_URL="https://get.k3s.io"

# Opciones de instalación: Flannel incluido por defecto, sin traefik ni servicelb
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
      echo -e "${RED}❌ Comando falló después de $i intentos: $*${NC}"
      return 1
    fi
    echo "🔄 Reintentando ($i/$max): $*"
    sleep $((delay * i))
  done
}

check_prerequisites() {
  echo "::group::Verificando requisitos previos"
  echo "📋 Validando sistema y dependencias..."
  echo ""

  # Verificar SO
  OS=$(uname -s)
  echo "Sistema operativo: $OS"
  
  if [[ "$OS" != "Linux" && "$OS" != "Darwin" ]]; then
    echo -e "${RED}❌ Sistema operativo no soportado: $OS${NC}"
    echo "K3s solo funciona en Linux y macOS"
    exit 1
  fi

  if [[ "$OS" == "Darwin" ]]; then
    echo -e "${YELLOW}⚠️  En macOS, K3s requiere Docker Desktop o Rancher Desktop${NC}"
    echo "Alternativas recomendadas:"
    echo "  • Minikube: brew install minikube && minikube start"
    echo "  • OrbStack: https://orbstack.dev/"
    echo "  • Docker Desktop: Activar Kubernetes en preferencias"
    echo ""
  fi

  # Verificar curl
  if ! command -v curl &>/dev/null; then
    echo -e "${RED}❌ curl no está instalado${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ curl${NC}"

  # Verificar puertos disponibles (solo en Linux)
  if [[ "$OS" == "Linux" ]]; then
    echo ""
    echo "Verificando puertos:"
    if command -v netstat &>/dev/null; then
      if netstat -tuln 2>/dev/null | grep -qE ":6443|:10250"; then
        echo -e "${YELLOW}⚠️  Puertos 6443 o 10250 ya en uso${NC}"
      else
        echo -e "${GREEN}✓ Puertos 6443 (API) y 10250 disponibles${NC}"
      fi
    fi
  fi

  echo ""
  echo -e "${GREEN}✓ Requisitos OK${NC}"
  echo "::endgroup::"
}

install_k3s() {
  echo "::group::Estado de K3s"
  
  if command -v k3s >/dev/null 2>&1; then
    CURRENT_VERSION=$(k3s --version)
    echo -e "${YELLOW}⚠️  K3s ya está instalado${NC}"
    echo "Versión actual: $CURRENT_VERSION"
    echo "Versión solicitada: ${K3S_VERSION}"
    echo ""
    echo "ℹ️  Para reinstalar, ejecuta:"
    echo "  sudo /usr/local/bin/k3s-uninstall.sh"
    echo "  sudo rm -rf /var/lib/rancher/k3s /etc/rancher"
    echo ""
    echo "En entorno CI/CD: continuando con instalación existente..."
    echo "::endgroup::"
    return 0
  fi
  
  echo "K3s no está instalado, procediendo con instalación..."
  echo ""
  echo "Configuración:"
  echo "  📦 Versión: ${K3S_VERSION}"
  echo "  🔀 Canal: ${K3S_CHANNEL}"
  echo "  ⚙️  Opciones: ${K3S_EXEC_OPTS}"
  echo "  🌐 CNI: Flannel (incluido por defecto)"
  echo "::endgroup::"

  echo "::group::Instalando K3s"
  echo "📥 Descargando e instalando desde ${K3S_INSTALL_SCRIPT_URL}..."
  
  if ! curl -sfL "${K3S_INSTALL_SCRIPT_URL}" | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_CHANNEL="${K3S_CHANNEL}" \
    INSTALL_K3S_EXEC="server ${K3S_EXEC_OPTS}" \
    sh -s -; then
    echo -e "${RED}❌ Error: Falló la instalación de K3s${NC}"
    exit 1
  fi

  echo "⏳ Esperando a que k3s.service esté listo..."
  sleep 5

  # Verificar que el servicio está activo
  if ! systemctl is-active --quiet k3s; then
    echo -e "${RED}❌ Error: k3s.service no está activo${NC}"
    echo ""
    echo "Estado del servicio:"
    systemctl status k3s || true
    echo ""
    echo "Últimos logs:"
    journalctl -xeu k3s.service -n 50 || true
    exit 1
  fi

  echo -e "${GREEN}✓ K3s instalado correctamente${NC}"
  echo "Versión: $(k3s --version)"
  echo "::endgroup::"
}


# ============================================================
# EJECUCIÓN PRINCIPAL
# ============================================================

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🚀 BOOTSTRAP K3S - Instalación con Flannel CNI${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""

# 1. Verificar requisitos
check_prerequisites

# 2. Verificar/Instalar K3s
install_k3s

# 3. Configurar kubeconfig
echo "::group::Configurando acceso al cluster"
KUBECONFIG="${KUBECONFIG:-${HOME}/kubeconfig}"
export KUBECONFIG
mkdir -p "$(dirname "$KUBECONFIG")"

echo "📄 Copiando kubeconfig a ${KUBECONFIG}..."
if ! sudo cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG"; then
  echo -e "${RED}❌ Error: No se pudo copiar kubeconfig${NC}"
  exit 1
fi

# Ajustar permisos
sudo chmod 600 "$KUBECONFIG"
sudo chown "$(id -u):$(id -g)" "$KUBECONFIG" || true

echo -e "${GREEN}✓ KUBECONFIG configurado${NC}"
echo "  Ubicación: $KUBECONFIG"
echo "  Tamaño: $(du -h "$KUBECONFIG" | cut -f1)"
echo "  Permisos: $(stat -c '%a' "$KUBECONFIG" 2>/dev/null || echo '600')"
echo "::endgroup::"

# 4. Esperar a API server
echo "::group::Esperando API server"
echo "⏳ Aguardando disponibilidad del API server..."
retry kubectl cluster-info
echo -e "${GREEN}✓ API server disponible${NC}"
echo "::endgroup::"

# 5. Verificar Flannel
echo "::group::Verificando Flannel CNI"
echo "✓ Flannel está incluido por defecto en K3s"
echo "  • Red superpuesta: simple y eficiente"
echo "  • CIDR por defecto: 10.42.0.0/16"
echo "  • Pods namespace: kube-flannel"
echo ""
echo "⏳ Aguardando a que Flannel esté listo..."

# Verificar que hay pods de Flannel running
TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  FLANNEL_RUNNING=$(kubectl get pods -n kube-flannel --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  
  if [ "$FLANNEL_RUNNING" -gt 0 ]; then
    echo -e "${GREEN}✓ Flannel listo ($FLANNEL_RUNNING pods running)${NC}"
    break
  fi
  
  echo "  ⏳ Esperando pods de Flannel... ($ELAPSED/$TIMEOUT segundos)"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo -e "${YELLOW}⚠️  Timeout esperando Flannel (continuando con verificación de nodo)${NC}"
fi

echo "::endgroup::"

# 6. Esperar nodo Ready
echo "::group::Verificando estado del nodo"
echo "⏳ Aguardando a que el nodo esté Ready..."
retry kubectl wait --for=condition=Ready node --all --timeout=300s
echo -e "${GREEN}✓ Nodo en estado Ready${NC}"
echo ""
echo "Nodos del cluster:"
kubectl get nodes -o wide
echo "::endgroup::"

# 7. Verificación final de pods
echo "::group::Verificación final del cluster"
echo "📊 Estado de pods en kube-system:"
echo ""

TIMEOUT_SECONDS=300
ELAPSED=0
CHECK_INTERVAL=5

while [ $ELAPSED -lt $TIMEOUT_SECONDS ]; do
  RUNNING=$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  SUCCEEDED=$(kubectl get pods -n kube-system --field-selector=status.phase=Succeeded --no-headers 2>/dev/null | wc -l)
  NOT_READY=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
  TOTAL=$((RUNNING + SUCCEEDED + NOT_READY))
  
  printf "  [%3ds] Running: %d | Succeeded: %d | Otros: %d | Total: %d\n" $ELAPSED $RUNNING $SUCCEEDED $NOT_READY $TOTAL
  
  if [ $NOT_READY -eq 0 ] && [ $TOTAL -gt 0 ]; then
    echo -e "${GREEN}✓ Todos los pods de K3s están listos${NC}"
    break
  fi
  
  sleep $CHECK_INTERVAL
  ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $NOT_READY -gt 0 ]; then
  echo -e "${YELLOW}⚠️  Algunos pods pendientes (continuando...)${NC}"
  echo ""
  kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded || true
fi

echo "::endgroup::"

# 8. Resumen final
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ BOOTSTRAP COMPLETADO EXITOSAMENTE${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "📋 Información de acceso:"
echo "  • KUBECONFIG: $KUBECONFIG"
echo "  • Versión: $(kubectl version --client --short 2>/dev/null || echo 'N/A')"
echo ""
echo "🌐 Configuración de la red:"
echo "  • CNI: Flannel"
echo "  • Pods CIDR: 10.42.0.0/16"
echo "  • Services CIDR: 10.43.0.0/16"
echo ""
echo "📖 Próximos pasos:"
echo "  1. Verificar acceso: kubectl get nodes"
echo "  2. Ver pods: kubectl get pods -A"
echo "  3. Ejecutar siguiente script: ./infra/bootstrap/bootstrap_helm.sh"
echo ""
echo "ℹ️  Para usar kubeconfig en otra máquina:"
echo "  export KUBECONFIG=${KUBECONFIG}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""

