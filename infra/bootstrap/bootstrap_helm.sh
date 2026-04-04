#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Config
HELM_VERSION="${HELM_VERSION:-v3.14.0}"
HELM_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"

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
      echo "Command failed after $i attempts: $*"
      return 1
    fi
    echo "Retry $i/$max: $*"
    sleep $((delay * i))
  done
}

echo "::group::Comprobando recursos necesarios"
# Comprobar KUBECONFIG con reintentos
KUBECONFIG="${KUBECONFIG:-${HOME}/kubeconfig}"
export KUBECONFIG

echo "Comprobando KUBECONFIG en: $KUBECONFIG"

# Reintentos para esperar a que KUBECONFIG esté disponible
MAX_RETRIES=30
RETRY_DELAY=2
for i in $(seq 1 $MAX_RETRIES); do
  if [ -f "$KUBECONFIG" ]; then
    echo -e "${GREEN}✓ KUBECONFIG disponible: $KUBECONFIG${NC}"
    break
  fi
  
  if [ $i -eq $MAX_RETRIES ]; then
    echo -e "${RED}ERROR: KUBECONFIG no existe en: $KUBECONFIG${NC}"
    echo ""
    echo "Diagnosis:"
    echo "1. Verificar que bootstrap_k3s.sh se ejecutó correctamente"
    echo "2. Verificar estado de k3s: sudo systemctl status k3s"
    echo "3. Verificar archivos en /etc/rancher/k3s/: ls -la /etc/rancher/k3s/"
    exit 1
  fi
  
  echo "Intento $i/$MAX_RETRIES: esperando a que KUBECONFIG esté disponible..."
  sleep $RETRY_DELAY
done

# Comprobar kubectl
if ! command -v kubectl >/dev/null 2>&1; then
  echo -e "${RED}ERROR: kubectl no está instalado${NC}"
  exit 1
fi
echo -e "${GREEN}✓ kubectl disponible: $(kubectl version --client 2>/dev/null | cut -d' ' -f3 || echo 'versión desconocida')${NC}"

# Comprobar conectividad al cluster
if ! retry kubectl cluster-info >/dev/null 2>&1; then
  echo -e "${RED}ERROR: No se puede conectar al cluster${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Cluster Kubernetes accesible${NC}"
echo "::endgroup::"

echo "::group::Comprobando si Helm ya está instalado"
if command -v helm >/dev/null 2>&1; then
  HELM_INSTALLED_VERSION=$(helm version -c 2>/dev/null | grep '^version' | awk '{print $2}' || echo 'versión desconocida')
  echo -e "${GREEN}✓ Helm ya instalado: $HELM_INSTALLED_VERSION${NC}"
  echo "::endgroup::"
else
  echo "Helm no está instalado, procediendo con instalación..."
  echo "::endgroup::"
  echo "::group::Instalando Helm"
  
  if ! curl -fsSL "${HELM_INSTALL_SCRIPT_URL}" | bash; then
    echo -e "${RED}ERROR: Falló la instalación de Helm${NC}"
    exit 1
  fi
  
  if ! command -v helm >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Helm no se instaló correctamente${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ Helm instalado correctamente${NC}"
  echo "::endgroup::"
fi

echo "::group::Actualizando repositorios de Helm"
# Verificar si hay repositorios configurados
REPOS_COUNT=$(helm repo list 2>/dev/null | tail -n +2 | wc -l)

if [ "$REPOS_COUNT" -gt 0 ]; then
  retry helm repo update
  echo -e "${GREEN}✓ Repositorios actualizados${NC}"
else
  echo -e "${YELLOW}⚠ No hay repositorios de Helm configurados${NC}"
  echo "  (Se configurarán cuando se instalen los charts)"
fi
echo "::endgroup::"

echo "::group::Verificando estado de Helm"
HELM_VERSION_OUTPUT=$(helm version --short)
echo "Versión de Helm: $HELM_VERSION_OUTPUT"
HELM_REPOS_COUNT=$(helm repo list | tail -n +2 | wc -l)
echo "Repositorios configurados: $HELM_REPOS_COUNT"
echo "::endgroup::"

echo -e "${GREEN}bootstrap_helm.sh completado correctamente${NC}"
