#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Config
ARGOCD_NAMESPACE="argocd"
ARGOCD_CHART_VERSION="9.4.17"
ARGOCD_VERSION="v3.3.6"
HELM_REPO_NAME="argo"
HELM_REPO_URL="https://argoproj.github.io/argo-helm"
RELEASE_NAME="argocd"

# Get the script directory and construct the values file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_VALUES="${SCRIPT_DIR}/../values/argocd_values.yaml"

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

is_argocd_installed() {
  # Verificar si el release de Helm existe
  if helm list -n "$ARGOCD_NAMESPACE" 2>/dev/null | grep -q "^$RELEASE_NAME\s"; then
    return 0
  fi
  return 1
}

echo "::group::Configurando kubeconfig desde artefacto"

# Buscar kubeconfig descargado desde el artefacto o en ubicación estándar
KUBECONFIG_PATHS=(
  "${RUNNER_TEMP}/kubeconfig-artifact/kubeconfig"  # Desde artefacto de Actions
  "/etc/rancher/k3s/k3s.yaml"                       # k3s generado automáticamente
  "${HOME}/kubeconfig"                              # Ubicación estándar
  "${HOME}/.kube/config"                            # Ubicación por defecto
)

KUBECONFIG_FOUND=false
for kb_path in "${KUBECONFIG_PATHS[@]}"; do
  if [ -f "$kb_path" ]; then
    export KUBECONFIG="$kb_path"
    echo -e "${GREEN}✓ KUBECONFIG encontrado: $KUBECONFIG${NC}"
    KUBECONFIG_FOUND=true
    break
  fi
done

if [ "$KUBECONFIG_FOUND" = false ]; then
  echo -e "${RED}ERROR: No se encontró KUBECONFIG${NC}"
  echo "Se buscó en:"
  for kb_path in "${KUBECONFIG_PATHS[@]}"; do
    echo "  - $kb_path"
  done
  exit 1
fi

echo "::endgroup::"

echo "::group::Comprobando recursos necesarios"

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

# Comprobar helm
if ! command -v helm >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Helm no está instalado. Ejecuta bootstrap_helm.sh primero${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Helm disponible: $(helm version -c 2>/dev/null | grep '^version' | awk '{print $2}' || echo 'versión desconocida')${NC}"

echo "::endgroup::"

echo "::group::Creando namespace de ArgoCD"
if kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo -e "${YELLOW}! Namespace $ARGOCD_NAMESPACE ya existe${NC}"
else
  if ! kubectl create namespace "$ARGOCD_NAMESPACE"; then
    echo -e "${RED}ERROR: Falló la creación del namespace${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ Namespace $ARGOCD_NAMESPACE creado${NC}"
fi
echo "::endgroup::"

echo "::group::Agregando repositorio Helm de ArgoCD"

# Actualizar lista de repos
helm repo update

# Agregar repositorio si no existe
if helm repo list | grep -q "^${HELM_REPO_NAME}"; then
  echo -e "${YELLOW}! Repositorio $HELM_REPO_NAME ya agregado${NC}"
  helm repo update "$HELM_REPO_NAME"
else
  if ! helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"; then
    echo -e "${RED}ERROR: Falló la adición del repositorio${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ Repositorio $HELM_REPO_NAME agregado${NC}"
fi

echo "::endgroup::"

echo "::group::Verificando si ArgoCD ya está instalado"

if is_argocd_installed; then
  echo -e "${YELLOW}! ArgoCD ya está instalado${NC}"
  UPGRADE=true
else
  echo -e "${GREEN}✓ ArgoCD no está instalado, procederá con instalación${NC}"
  UPGRADE=false
fi

echo "::endgroup::"

echo "::group::Instalando/Actualizando ArgoCD"

# Verificar que el archivo de values existe
if [ ! -f "$ARGOCD_VALUES" ]; then
  echo -e "${RED}ERROR: Archivo de configuración no encontrado: $ARGOCD_VALUES${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Archivo de valores encontrado: $ARGOCD_VALUES${NC}"

# Preparar comando helm
HELM_CMD=(
  helm
  "upgrade"
  "--install"
  "$RELEASE_NAME"
  "argo/argo-cd"
  "--namespace"
  "$ARGOCD_NAMESPACE"
  "--version"
  "$ARGOCD_CHART_VERSION"
  "--values"
  "$ARGOCD_VALUES"
  "--wait"
  "--timeout"
  "5m"
)

echo "Ejecutando: ${HELM_CMD[*]}"

if ! retry "${HELM_CMD[@]}"; then
  echo -e "${RED}ERROR: Falló la instalación/actualización de ArgoCD${NC}"
  exit 1
fi

echo -e "${GREEN}✓ ArgoCD instalado/actualizado correctamente${NC}"

echo "::endgroup::"

echo "::group::Verificando instalación"

# Esperar a que los pods estén listos
MAX_RETRIES=30
RETRY_DELAY=5
PODS_READY=false

for i in $(seq 1 $MAX_RETRIES); do
  READY_PODS=$(kubectl get pods -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | wc -l)
  if [ "$READY_PODS" -gt 0 ]; then
    if kubectl get pods -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
      echo -e "${GREEN}✓ ArgoCD server está ready${NC}"
      PODS_READY=true
      break
    fi
  fi

  if [ $i -lt $MAX_RETRIES ]; then
    echo "Esperando a que los pods de ArgoCD estén listos... Intento $i/$MAX_RETRIES"
    sleep $RETRY_DELAY
  fi
done

if [ "$PODS_READY" = false ]; then
  echo -e "${YELLOW}! ArgoCD no está listo aún. Estado actual:${NC}"
  kubectl get pods -n "$ARGOCD_NAMESPACE"
else
  echo -e "${GREEN}✓ ArgoCD está operacional${NC}"
fi

# Mostrar información de acceso
echo ""
echo "ArgoCD ha sido instalado en el namespace: $ARGOCD_NAMESPACE"
echo ""
echo "Para acceder a ArgoCD:"
echo "  kubectl port-forward svc/$RELEASE_NAME-server -n $ARGOCD_NAMESPACE 8080:443"
echo ""
echo "Luego accede a: https://localhost:8080"
echo ""
echo "Para obtener la contraseña inicial:"
echo "  kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo ""

echo "::endgroup::"

echo "════════════════════════════════════════════════"
echo -e "${GREEN}[✓] ArgoCD instalado correctamente${NC}"
echo "════════════════════════════════════════════════"

