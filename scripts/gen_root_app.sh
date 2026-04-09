#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Script: gen_root_app.sh
# Descripción: Aplica la root Application de ArgoCD para gestionar la 
#              plataforma completa
# Requisitos: kubectl configurado, acceso al cluster Kubernetes
# ============================================================================

# Configuración
APP_NAME="platform-root"
NAMESPACE="argocd"
ROOT_APP_FILE="platform/root-application.yaml"

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

# Comprobar que el archivo root-application.yaml existe
if [ ! -f "$REPO_ROOT/$ROOT_APP_FILE" ]; then
  log_error "Archivo no encontrado: $ROOT_APP_FILE"
  exit 1
fi
log_success "Archivo encontrado: $ROOT_APP_FILE"

echo "::endgroup::"

# ============================================================================
# Comprobar si la Application ya existe
# ============================================================================

echo "::group::Verificar estado de Application"

if kubectl get application "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_warning "Application '$APP_NAME' ya existe"
  
  # Obtener información de la Application actual
  echo ""
  log_info "Estado actual de la Application:"
  kubectl get application "$APP_NAME" -n "$NAMESPACE" -o wide
  
  echo ""
  log_info "Sincronización:"
  kubectl get application "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Desconocido"
  echo ""
  
  echo ""
  read -p "¿Actualizar Application existente? (s/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    log_success "Operación cancelada por el usuario"
    exit 0
  fi
else
  log_info "Application '$APP_NAME' no existe - se creará"
fi

echo "::endgroup::"

# ============================================================================
# Aplicar root Application
# ============================================================================

echo "::group::Aplicar root Application"

log_info "Aplicando: $ROOT_APP_FILE"
if retry kubectl apply -f "$REPO_ROOT/$ROOT_APP_FILE"; then
  log_success "Root Application aplicado correctamente"
else
  log_error "Falló al aplicar root Application"
  exit 1
fi

# Esperar a que la Application se cree en ArgoCD
log_info "Esperando a que ArgoCD reconozca la Application..."
if retry kubectl get application "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
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

log_success "Root Application aplicada exitosamente"
echo ""
log_info "Detalles de la Application:"
kubectl get application "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.destination.server}' 2>/dev/null && \
  echo " (Servidor de destino: $(kubectl get application "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.destination.server}'))"

echo ""
log_info "Para revisar el estado de sincronización, ejecuta:"
echo "  kubectl get application $APP_NAME -n $NAMESPACE -w"
echo ""
log_info "Para ver los detalles completos:"
echo "  kubectl describe application $APP_NAME -n $NAMESPACE"
echo ""

echo "::endgroup::"

exit 0