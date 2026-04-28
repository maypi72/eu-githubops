#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Script: bootstrap_localstack.sh
# Descripción: Instala LocalStack con AWS S3 en Kubernetes usando Helm,
#              configura credenciales con Sealed Secrets, crea Ingress,
#              y ejecuta Terraform.
# Flujo: Namespace → Secrets → LocalStack → Ingress → Health Check
#        → Terraform/AWS CLI → Terraform Init → Terraform Apply
# Requisitos: kubectl, helm, kubeseal, sealed-secrets instalado en cluster
# ============================================================================

# Configuración
LOCALSTACK_NAMESPACE="${LOCALSTACK_NAMESPACE:-localstack}"
LOCALSTACK_HELM_REPO_NAME="${LOCALSTACK_HELM_REPO_NAME:-localstack}"
LOCALSTACK_HELM_REPO_URL="${LOCALSTACK_HELM_REPO_URL:-https://localstack.github.io/helm-charts}"
LOCALSTACK_RELEASE_NAME="${LOCALSTACK_RELEASE_NAME:-localstack}"
LOCALSTACK_CHART="${LOCALSTACK_CHART:-localstack/localstack}"
LOCALSTACK_CHART_VERSION="${LOCALSTACK_CHART_VERSION:-2.0.0}"
SEALED_SECRETS_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
SEALED_SECRETS_RELEASE="${SEALED_SECRETS_RELEASE:-sealed-secrets}"

# AWS Credenciales
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
AWS_SECRET_NAME="localstack-aws-credentials"

# Terraform
TERRAFORM_DIR="${TERRAFORM_DIR:-infra/terraform/localstak}"

# Health Check
HEALTH_PATH="/_localstack/health"
LS_HOST="localstack.local"
LOCALSTACK_WAIT_SECONDS=${LOCALSTACK_WAIT_SECONDS:-60}
TRY_MAX=${TRY_MAX:-12}

# Script dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colores
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

is_command_available() {
  command -v "$1" &>/dev/null
}

is_namespace_exists() {
  kubectl get namespace "$1" &>/dev/null
}

# ============================================================================
# Verificaciones previas
# ============================================================================

echo "::group::Verificando KUBECONFIG"
log_info "Verificando KUBECONFIG..."

KUBECONFIG="${KUBECONFIG:-$HOME/kubeconfig}"
export KUBECONFIG

if [ ! -f "$KUBECONFIG" ]; then
  log_error "KUBECONFIG no existe en: $KUBECONFIG"
  echo ""
  echo "Por favor:"
  echo "1. Ejecutar bootstrap_k3s.sh primero"
  echo "2. O configurar KUBECONFIG manualmente"
  exit 1
fi

log_success "KUBECONFIG disponible: $KUBECONFIG"
echo "::endgroup::"

# ============================================================================
# Crear namespace (si no existe)
# ============================================================================

echo "::group::Creando/Verificando namespace $LOCALSTACK_NAMESPACE"

if is_namespace_exists "$LOCALSTACK_NAMESPACE"; then
  log_success "Namespace '$LOCALSTACK_NAMESPACE' ya existe"
else
  log_info "Creando namespace '$LOCALSTACK_NAMESPACE'..."
  kubectl create namespace "$LOCALSTACK_NAMESPACE"
  log_success "Namespace creado"
fi

echo "::endgroup::"

# ============================================================================
# Configurar Sealed Secret para credenciales AWS
# ============================================================================

echo "::group::Configurando Sealed Secret para credenciales AWS"

log_info "Creando secret con credenciales AWS..."

TEMP_SECRET=$(mktemp)
cat > "$TEMP_SECRET" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: $AWS_SECRET_NAME
  namespace: $LOCALSTACK_NAMESPACE
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "$AWS_ACCESS_KEY_ID"
  AWS_SECRET_ACCESS_KEY: "$AWS_SECRET_ACCESS_KEY"
  AWS_REGION: "$AWS_REGION"
EOF

# Crear directorio si no existe
SEALED_SECRETS_DIR="$SCRIPT_DIR/../localstack/sealed-secrets"
mkdir -p "$SEALED_SECRETS_DIR"

# Sellar el secret
SEALED_SECRET_FILE="$SEALED_SECRETS_DIR/${AWS_SECRET_NAME}.yaml"

log_info "Sellando secret con kubeseal..."
if kubeseal \
  --controller-name="$SEALED_SECRETS_RELEASE" \
  --controller-namespace="$SEALED_SECRETS_NAMESPACE" \
  --format yaml < "$TEMP_SECRET" > "$SEALED_SECRET_FILE"; then
  log_success "Secret sellado correctamente: $SEALED_SECRET_FILE"
else
  log_error "Falló al sellar el secret con kubeseal"
  rm -f "$TEMP_SECRET"
  exit 1
fi

# Aplicar el sealed secret
log_info "Aplicando Sealed Secret en el cluster..."
if kubectl apply -f "$SEALED_SECRET_FILE"; then
  log_success "Sealed Secret aplicado correctamente"
else
  log_error "Falló al aplicar Sealed Secret"
  rm -f "$TEMP_SECRET"
  exit 1
fi

rm -f "$TEMP_SECRET"
echo "::endgroup::"

# ============================================================================
# Verificar kubeseal (REQUERIDO)
# ============================================================================

echo "::group::Verificando kubeseal"

if ! is_command_available kubeseal; then
  log_error "kubeseal no está instalado. Por favor instálalo primero:"
  echo "  https://github.com/bitnami-labs/sealed-secrets/releases"
  exit 1
else
  log_success "kubeseal disponible: $(kubeseal --version)"
fi

echo "::endgroup::"

# ============================================================================
# Configurar Helm
# ============================================================================

echo "::group::Configurando Helm"

log_info "Verificando repositorio de Helm: $LOCALSTACK_HELM_REPO_NAME"

# Verificar si el repositorio ya existe
if helm repo list | grep -q "^$LOCALSTACK_HELM_REPO_NAME\s"; then
  log_success "Repositorio de Helm '$LOCALSTACK_HELM_REPO_NAME' ya existe"
else
  log_info "Añadiendo repositorio de Helm: $LOCALSTACK_HELM_REPO_NAME"
  if helm repo add "$LOCALSTACK_HELM_REPO_NAME" "$LOCALSTACK_HELM_REPO_URL"; then
    log_success "Repositorio añadido correctamente"
  else
    log_error "Falló al añadir repositorio de Helm"
    exit 1
  fi
fi

# Actualizar repositorios
log_info "Actualizando repositorios de Helm..."
if helm repo update; then
  log_success "Repositorios actualizados"
else
  log_error "Falló al actualizar repositorios"
  exit 1
fi

echo "::endgroup::"

# ============================================================================
# Instalar LocalStack
# ============================================================================

echo "::group::Instalando LocalStack con Helm"

VALUES_FILE="$SCRIPT_DIR/../values/localstack_values.yaml"

if [ ! -f "$VALUES_FILE" ]; then
  log_warning "Archivo de valores no encontrado en: $VALUES_FILE"
  log_info "Usando valores por defecto..."
  VALUES_FILE=""
fi

log_info "Instalando chart $LOCALSTACK_CHART versión $LOCALSTACK_CHART_VERSION..."

HELM_ARGS=(
  "upgrade" "--install"
  "$LOCALSTACK_RELEASE_NAME"
  "$LOCALSTACK_CHART"
  "--namespace" "$LOCALSTACK_NAMESPACE"
  "--version" "$LOCALSTACK_CHART_VERSION"
  "--wait"
  "--timeout" "5m"
)

# Agregar valores si existen
if [ -n "$VALUES_FILE" ] && [ -f "$VALUES_FILE" ]; then
  HELM_ARGS+=("--values" "$VALUES_FILE")
fi

# Agregar valores inline para configuración
HELM_ARGS+=(
  "--set" "startServices=s3"
)

if helm "${HELM_ARGS[@]}"; then
  log_success "LocalStack instalado correctamente"
else
  log_error "Falló la instalación de LocalStack"
  exit 1
fi

# Esperar a que el pod esté listo
log_info "Esperando a que LocalStack pod esté listo..."
if kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=localstack \
  -n "$LOCALSTACK_NAMESPACE" \
  --timeout=300s; then
  log_success "LocalStack pod está listo"
else
  log_warning "Timeout esperando a LocalStack pod, continuando de todas formas..."
fi

echo "::endgroup::"

# ============================================================================
# Verificar Ingress (creado automáticamente via Helm values)
# ============================================================================

echo "::group::Verificando Ingress para LocalStack"

log_info "El Ingress se creó automáticamente mediante Helm values..."
log_info "Esperando a que el Ingress esté disponible..."

sleep 3

if kubectl -n "$LOCALSTACK_NAMESPACE" get ingress localstack &>/dev/null; then
  log_success "Ingress 'localstack' está disponible"
  kubectl -n "$LOCALSTACK_NAMESPACE" get ingress localstack -o wide
else
  log_warning "Ingress 'localstack' aún no está disponible"
fi

echo "::endgroup::"

# ============================================================================
# Verificar que LocalStack es accesible via HTTP
# ============================================================================

echo "::group::Verificando salud de LocalStack via HTTP"

log_info "Esperando ${LOCALSTACK_WAIT_SECONDS}s a que LocalStack esté healthy..."
log_info "Endpoint: http://${LS_HOST}${HEALTH_PATH}"

# Dar tiempo a que el Ingress se estabilice
sleep 10

for i in $(seq 1 $TRY_MAX); do
  if curl -sSf "http://${LS_HOST}${HEALTH_PATH}" >/dev/null 2>&1; then
    log_success "LocalStack está healthy y accesible"
    break
  fi
  
  if [ $i -lt $TRY_MAX ]; then
    log_warning "LocalStack no está listo aún... (intento $i/$TRY_MAX)"
    sleep 5
  else
    log_error "LocalStack no respondió como healthy después de $TRY_MAX intentos"
    echo ""
    echo "Diagnóstico:"
    echo "1. Pods en namespace localstack:"
    kubectl -n "$LOCALSTACK_NAMESPACE" get pods
    echo ""
    echo "2. Servicios en namespace localstack:"
    kubectl -n "$LOCALSTACK_NAMESPACE" get svc
    echo ""
    echo "3. Ingress en namespace localstack:"
    kubectl -n "$LOCALSTACK_NAMESPACE" get ingress
    echo ""
    echo "4. Logs del pod LocalStack:"
    kubectl -n "$LOCALSTACK_NAMESPACE" logs -l app.kubernetes.io/name=localstack --tail=50 || true
    echo ""
    echo "Intenta lo siguiente manualmente:"
    echo "  # Port-forward al servicio"
    echo "  kubectl -n $LOCALSTACK_NAMESPACE port-forward svc/localstack 4566:4566"
    echo "  # Luego en otra terminal:"
    echo "  curl -v http://localhost:4566/_localstack/health"
    exit 1
  fi
done

echo "::endgroup::"

# ============================================================================
# Instalar Terraform y AWS CLI (DESPUÉS de LocalStack)
# ============================================================================

echo "::group::Instalando Terraform y AWS CLI"

# Instalar Terraform
if ! is_command_available terraform; then
  log_warning "Terraform no está instalado. Instalando con apt-get..."
  log_info "Necesita privilegios de administrador..."
  
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
  sudo apt-add-repository "deb [arch=$(dpkg --print-architecture)] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  sudo apt-get update && sudo apt-get install -y terraform
  
  log_success "Terraform instalado"
else
  log_success "Terraform ya está instalado: $(terraform version | head -n1)"
fi

# Instalar AWS CLI
if ! is_command_available aws; then
  log_warning "AWS CLI no está instalado. Instalando con apt-get..."
  log_info "Necesita privilegios de administrador..."
  
  sudo apt-get update && sudo apt-get install -y awscli
  
  log_success "AWS CLI instalado"
else
  log_success "AWS CLI ya está instalado: $(aws --version)"
fi

echo "::endgroup::"

# ============================================================================
# Inicializar Terraform State
# ============================================================================

echo "::group::Inicializando Terraform State"

log_info "Ejecutando: scripts/init_tfstate.sh"
log_info "Esto inicializará Terraform con S3 remoto en LocalStack"

if [ ! -f "$REPO_ROOT/scripts/init_tfstate.sh" ]; then
  log_error "Script init_tfstate.sh no encontrado"
  exit 1
fi

if chmod +x "$REPO_ROOT/scripts/init_tfstate.sh" && \
   AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
   AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
   AWS_REGION="$AWS_REGION" \
   TERRAFORM_DIR="$TERRAFORM_DIR" \
   "$REPO_ROOT/scripts/init_tfstate.sh"; then
  log_success "Terraform state inicializado correctamente"
else
  log_error "Falló la inicialización de Terraform state"
  exit 1
fi

echo "::endgroup::"

# ============================================================================
# Ejecutar Terraform Plan y Apply
# ============================================================================

echo "::group::Ejecutando Terraform"

if [ ! -d "$REPO_ROOT/$TERRAFORM_DIR" ]; then
  log_error "Directorio Terraform no encontrado: $REPO_ROOT/$TERRAFORM_DIR"
  exit 1
fi

cd "$REPO_ROOT/$TERRAFORM_DIR"
log_info "Cambio a directorio: $(pwd)"

# Exportar variables para terraform (usando TF_VAR_* para enmascarar en logs)
export TF_VAR_aws_access_key="$AWS_ACCESS_KEY_ID"
export TF_VAR_aws_secret_key="$AWS_SECRET_ACCESS_KEY"
export TF_VAR_aws_region="$AWS_REGION"

# Plan
log_info "Generando plan de Terraform..."
if terraform plan -out=tfplan; then
  log_success "Plan de Terraform generado"
else
  log_error "Falló la generación del plan de Terraform"
  exit 1
fi

# Apply (solo si está en CI o si se confirma manualmente)
if [ "${CI:-false}" = "true" ] || [ "${AUTO_APPLY:-false}" = "true" ]; then
  log_info "Aplicando Terraform..."
  if terraform apply -auto-approve tfplan; then
    log_success "Terraform aplicado correctamente"
  else
    log_error "Falló la aplicación de Terraform"
    exit 1
  fi
else
  log_warning "Terraform plan generado pero no aplicado"
  log_info "Para aplicar, ejecuta:"
  echo "  cd $REPO_ROOT/$TERRAFORM_DIR"
  echo "  terraform apply tfplan"
fi

cd "$REPO_ROOT"
echo "::endgroup::"

# ============================================================================
# Resumen
# ============================================================================

echo ""
echo "::group::Resumen de la instalación"
log_success "LocalStack bootstrap completado exitosamente"
echo ""
log_info "Detalles:"
echo "  Namespace: $LOCALSTACK_NAMESPACE"
echo "  Release Helm: $LOCALSTACK_RELEASE_NAME"
echo "  Ingress (vía Helm): localstack.local"
echo "  Endpoint S3: http://localstack.local"
echo ""
log_info "Verificar estado:"
echo "  kubectl -n $LOCALSTACK_NAMESPACE get pods"
echo "  kubectl -n $LOCALSTACK_NAMESPACE get svc"
echo "  kubectl -n $LOCALSTACK_NAMESPACE get ingress"
echo ""
log_info "Para ver detalles del Ingress:"
echo "  kubectl -n $LOCALSTACK_NAMESPACE describe ingress localstack"
echo ""
log_info "Sealed Secret file guardado en:"
echo "  $SEALED_SECRETS_DIR/${AWS_SECRET_NAME}.yaml"
echo ""
log_info "Terraform state:"
echo "  Location: S3 en LocalStack"
echo "  Bucket: la-huella-remote-state"
echo "  Key: global/terraform.tfstate"
echo "::endgroup::"

exit 0
