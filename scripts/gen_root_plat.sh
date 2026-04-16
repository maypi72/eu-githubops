#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Script: gen_root_plat.sh
# Descripción: Aplica el proyecto de ArgoCD y la root Application de la 
#              plataforma completa (primero projects, luego root)
# Requisitos: kubectl configurado, acceso al cluster Kubernetes
# ============================================================================

# Configuración
NAMESPACE="argocd"
PROJECT_NAME="platform-proyect"
ROOT_APP_NAME="platform-root"
PROJECTS_FILE="argocd-projects/platform_proyect.yaml"
ROOT_APP_FILE="platform/root-platform.yaml"

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Funciones de utilidad
# ============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[!]${NC} $*"
}

log_error() {
  echo -e "${RED}[✗]${NC} $*"
}

# Función retry para operaciones que puedan fallar
retry() {
  local max=${RETRY_MAX:-5}
  local delay=${RETRY_DELAY:-2}
  local attempt=1
  
  until "$@"; do
    if [ $attempt -ge $max ]; then
      log_error "Comando falló después de $attempt intentos: $*"
      return 1
    fi
    log_warning "Reintentando ($attempt/$max en ${delay}s): $*"
    sleep $((delay * attempt))
    attempt=$((attempt + 1))
  done
}

# ============================================================================
# Validaciones previas
# ============================================================================

echo "::group::Validación inicial"
log_info "===================================================="
log_info "Aplicar Root Application de ArgoCD"
log_info "===================================================="

# Comprobar que kubectl está disponible
if ! command -v kubectl >/dev/null 2>&1; then
  log_error "kubectl no está instalado o no está en PATH"
  exit 1
fi
log_success "kubectl disponible"

# Comprobar kubeconfig
if [ -z "${KUBECONFIG:-}" ]; then
  KUBECONFIG_PATHS=(
    "/etc/rancher/k3s/k3s.yaml"
    "${HOME}/.kube/config"
    "${HOME}/kubeconfig"
  )
  
  KUBECONFIG_FOUND=false
  for kb_path in "${KUBECONFIG_PATHS[@]}"; do
    if [ -f "$kb_path" ]; then
      export KUBECONFIG="$kb_path"
      log_success "KUBECONFIG encontrado: $KUBECONFIG"
      KUBECONFIG_FOUND=true
      break
    fi
  done
  
  if [ "$KUBECONFIG_FOUND" = false ]; then
    log_error "No se encontró KUBECONFIG en ubicaciones estándar"
    exit 1
  fi
else
  log_success "KUBECONFIG: $KUBECONFIG"
fi

# Comprobar conectividad al cluster
if ! retry kubectl cluster-info >/dev/null 2>&1; then
  log_error "No se puede conectar al cluster Kubernetes"
  exit 1
fi
log_success "Cluster Kubernetes accesible"

# Comprobar que el namespace de ArgoCD existe
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  log_error "Namespace '$NAMESPACE' no existe. Ejecuta bootstrap_argocd.sh primero"
  exit 1
fi
log_success "Namespace '$NAMESPACE' existe"

# Comprobar que ArgoCD está instalado
if ! kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=argocd-server >/dev/null 2>&1; then
  log_error "ArgoCD no está instalado en el namespace '$NAMESPACE'"
  exit 1
fi
log_success "ArgoCD está instalado en '$NAMESPACE'"

# Comprobar que los archivos YAML existen
if [ ! -f "$REPO_ROOT/$PROJECTS_FILE" ]; then
  log_error "Archivo no encontrado: $PROJECTS_FILE"
  exit 1
fi
log_success "Archivo encontrado: $PROJECTS_FILE"

if [ ! -f "$REPO_ROOT/$ROOT_APP_FILE" ]; then
  log_error "Archivo no encontrado: $ROOT_APP_FILE"
  exit 1
fi
log_success "Archivo encontrado: $ROOT_APP_FILE"

echo "::endgroup::"

# ============================================================================
# Comprobar si Project y Application ya existen
# ============================================================================

echo "::group::Verificar estado de Project y Application"

# Verificar Project
PROJECT_EXISTS=false
if kubectl get appproject "$PROJECT_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_warning "AppProject '$PROJECT_NAME' ya existe"
  PROJECT_EXISTS=true
  
  echo ""
  log_info "Estado actual del AppProject:"
  kubectl get appproject "$PROJECT_NAME" -n "$NAMESPACE" -o wide
  echo ""
else
  log_info "AppProject '$PROJECT_NAME' no existe - se creará"
fi

echo ""

# Verificar Application
APP_EXISTS=false
if kubectl get application "$ROOT_APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_warning "Application '$ROOT_APP_NAME' ya existe"
  APP_EXISTS=true
  
  echo ""
  log_info "Estado actual de la Application:"
  kubectl get application "$ROOT_APP_NAME" -n "$NAMESPACE" -o wide
  
  echo ""
  log_info "Sincronización:"
  kubectl get application "$ROOT_APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Desconocido"
  echo ""
else
  log_info "Application '$ROOT_APP_NAME' no existe - se creará"
fi

echo ""

# Si ambos existen, preguntar para actualizar
if [ "$PROJECT_EXISTS" = true ] && [ "$APP_EXISTS" = true ]; then
  read -p "¿Actualizar Project y Application existentes? (s/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    log_success "Operación cancelada por el usuario"
    exit 0
  fi
fi

echo "::endgroup::"

# ============================================================================
# Aplicar ArgoCD Project primero
# ============================================================================

echo "::group::Aplicar ArgoCD Project"

log_info "Aplicando Project: $PROJECTS_FILE"
if retry kubectl apply -f "$REPO_ROOT/$PROJECTS_FILE" -n "$NAMESPACE"; then
  log_success "ArgoCD Project aplicado correctamente"
else
  log_error "Falló al aplicar ArgoCD Project"
  exit 1
fi

# Esperar a que el Project se cree en ArgoCD
log_info "Esperando a que ArgoCD reconozca el Project..."
if retry kubectl get appproject "$PROJECT_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_success "AppProject registrado en ArgoCD"
else
  log_error "Timeout esperando a que AppProject se registre"
  exit 1
fi

echo "::endgroup::"

# ============================================================================
# Aplicar root Application
# ============================================================================

echo "::group::Aplicar root Platform Application"

log_info "Aplicando Root Application: $ROOT_APP_FILE"
if retry kubectl apply -f "$REPO_ROOT/$ROOT_APP_FILE" -n "$NAMESPACE"; then
  log_success "Root Application aplicado correctamente"
else
  log_error "Falló al aplicar root Application"
  exit 1
fi

# Esperar a que la Application se cree en ArgoCD
log_info "Esperando a que ArgoCD reconozca la Application..."
if retry kubectl get application "$ROOT_APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_success "Application registrada en ArgoCD"
else
  log_error "Timeout esperando a que Application se registre"
  exit 1
fi

echo "::endgroup::"

# ============================================================================
# Información de estado final
# ============================================================================

echo "::group::Estado final"

log_success "Project y Root Application aplicados exitosamente"
echo ""
log_info "Detalles del Project:"
kubectl get appproject "$PROJECT_NAME" -n "$NAMESPACE" -o wide
echo ""

log_info "Detalles de la Application:"
kubectl get application "$ROOT_APP_NAME" -n "$NAMESPACE" -o wide
echo ""

log_info "Para revisar el estado de sincronización, ejecuta:"
echo "  kubectl get application $ROOT_APP_NAME -n $NAMESPACE -w"
echo ""
log_info "Para ver los detalles completos:"
echo "  kubectl describe application $ROOT_APP_NAME -n $NAMESPACE"
echo ""

echo "::endgroup::"

exit 0