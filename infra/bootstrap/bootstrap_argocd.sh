#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Config
ARGOCD_NAMESPACE="argocd"
ARGOCD_CHART_VERSION="9.5.0"
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

# Agregar repositorio si no existe
if helm repo list 2>/dev/null | grep -q "^${HELM_REPO_NAME}"; then
  echo -e "${YELLOW}! Repositorio $HELM_REPO_NAME ya agregado${NC}"
else
  if ! helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"; then
    echo -e "${RED}ERROR: Falló la adición del repositorio${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ Repositorio $HELM_REPO_NAME agregado${NC}"
fi

# Actualizar lista de repos
helm repo update

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

echo "::endgroup::"

echo "::group::Configurando secreto de admin de ArgoCD"

# Verificar si ARGOCD_ADMIN_PASSWORD está configurada
if [ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]; then
  echo -e "${YELLOW}! Variable ARGOCD_ADMIN_PASSWORD no encontrada${NC}"
  echo ""
  echo "El secreto NO será actualizado. Opciones:"
  echo "1. Exportar la variable: export ARGOCD_ADMIN_PASSWORD='tu-password'"
  echo "2. O pasar como variable de entorno: ARGOCD_ADMIN_PASSWORD='tu-password' $0"
  echo ""
  echo "Si deseas actualizar el secreto manualmente después, ejecuta:"
  echo "  cd $(dirname "$SCRIPT_DIR")/../.."
  echo "  ARGOCD_ADMIN_PASSWORD='tu-password' bash scripts/gen_argocd_secret.sh"
  echo ""
  CONFIGURE_SECRET=false
else
  echo -e "${GREEN}✓ ARGOCD_ADMIN_PASSWORD configurada${NC}"
  CONFIGURE_SECRET=true
fi

if [ "$CONFIGURE_SECRET" = true ]; then
  # Encontrar script de generación de secretos
  SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
  GEN_SECRET_SCRIPT="${SCRIPTS_DIR}/gen_argocd_secret.sh"
  
  if [ ! -f "$GEN_SECRET_SCRIPT" ]; then
    echo -e "${RED}✗ Script gen_argocd_secret.sh no encontrado en $GEN_SECRET_SCRIPT${NC}"
    echo "  Saltando generación de secreto"
  else
    echo "Ejecutando generación de secreto..."
    
    # Exportar ARGOCD_ADMIN_PASSWORD para el script
    export ARGOCD_ADMIN_PASSWORD
    
    # Ejecutar el script generador
    if bash "$GEN_SECRET_SCRIPT"; then
      echo -e "${GREEN}✓ Secreto generado exitosamente${NC}"
      
      # Aplicar el secreto sellado al cluster
      echo ""
      echo "Aplicando secreto sellado al cluster..."
      SEALED_SECRET_FILE="${SCRIPTS_DIR}/../infra/argocd/sealed-secrets/argocd-secret.yaml"
      
      if [ -f "$SEALED_SECRET_FILE" ]; then
        if kubectl apply -f "$SEALED_SECRET_FILE" -n "$ARGOCD_NAMESPACE"; then
          echo -e "${GREEN}✓ Secreto sellado aplicado${NC}"
          
          # Esperar a que sealed-secrets descifre el secreto
          echo "Esperando descifrado del secreto..."
          sleep 3
          
          # Reiniciar los pods de argocd-server para que lean el nuevo secreto
          echo "Reiniciando pod de ArgoCD server..."
          kubectl rollout restart deployment/$RELEASE_NAME-server -n "$ARGOCD_NAMESPACE" --timeout=2m
          
          if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Pod reiniciado. Esperando readiness...${NC}"
            kubectl rollout status deployment/$RELEASE_NAME-server -n "$ARGOCD_NAMESPACE" --timeout=2m
            
            if [ $? -eq 0 ]; then
              echo -e "${GREEN}✓ ArgoCD server actualizado con nueva contraseña de admin${NC}"
            else
              echo -e "${YELLOW}! Timeout esperando readiness del pod, pero el secreto fue aplicado${NC}"
            fi
          else
            echo -e "${YELLOW}! No se pudo reiniciar el pod, pero el secreto fue aplicado${NC}"
          fi
        else
          echo -e "${RED}✗ Error al aplicar el secreto sellado${NC}"
        fi
      else
        echo -e "${RED}✗ Archivo de secreto sellado no encontrado: $SEALED_SECRET_FILE${NC}"
      fi
    else
      echo -e "${RED}✗ Error al generar el secreto${NC}"
    fi
  fi
fi

echo "::endgroup::"

# Mostrar información de acceso
echo "::group::Información de acceso a ArgoCD"
echo ""
echo "ArgoCD ha sido instalado en el namespace: $ARGOCD_NAMESPACE"
echo ""
echo "Para acceder a ArgoCD (localmente):"
echo "  kubectl port-forward svc/$RELEASE_NAME-server -n $ARGOCD_NAMESPACE 8080:443"
echo ""
echo "Luego accede a: https://localhost:8080"
echo ""
if [ "$CONFIGURE_SECRET" = true ]; then
  echo "Usuario: admin"
  echo "Contraseña: La que configuraste en ARGOCD_ADMIN_PASSWORD"
else
  echo "Para obtener la contraseña inicial:"
  echo "  kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
fi
echo ""

echo "::endgroup::"

echo "════════════════════════════════════════════════"
echo -e "${GREEN}[✓] ArgoCD instalado y configurado${NC}"
echo "════════════════════════════════════════════════"

