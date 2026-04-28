#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Script: bootstrap_localstack.sh
# Descripción: Instala LocalStack con AWS S3 en Kubernetes usando Helm,
#              configura credenciales con Sealed Secrets, crea Ingress,
#              y ejecuta Terraform.
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
TERRAFORM_VERSION="${TERRAFORM_VERSION:-latest}"
AWS_CLI_VERSION="${AWS_CLI_VERSION:-latest}"

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

retry() {
  local -r max=${RETRY_MAX:-5}
  local -r delay=${RETRY_DELAY:-2}
  local i=0
  until "$@"; do
    i=$((i+1))
    if [ $i -ge $max ]; then
      log_error "Command failed after $i attempts: $*"
      return 1
    fi
    log_warning "Retry $i/$max: $*"
    sleep $((delay * i))
  done
}

is_command_available() {
  command -v "$1" &>/dev/null
}

is_namespace_exists() {
  kubectl get namespace "$1" &>/dev/null
}

is_localstack_installed() {
  helm list -n "$LOCALSTACK_NAMESPACE" 2>/dev/null | grep -q "^$LOCALSTACK_RELEASE_NAME\s" || return 1
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
# Crear namespace
# ============================================================================

echo "::group::Creando namespace $LOCALSTACK_NAMESPACE"

if is_namespace_exists "$LOCALSTACK_NAMESPACE"; then
  log_success "Namespace '$LOCALSTACK_NAMESPACE' ya existe"
else
  log_info "Creando namespace '$LOCALSTACK_NAMESPACE'..."
  kubectl create namespace "$LOCALSTACK_NAMESPACE"
  log_success "Namespace creado"
fi

echo "::endgroup::"

# ============================================================================
# Configurar Sealed Secret para credenciales AWS (PRIMERO)
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
# Verificar herramientas requeridas (SIN INSTALAR)
# ============================================================================

echo "::group::Verificando herramientas requeridas"

# Verificar Terraform
if ! is_command_available terraform; then
  if [ "${CI:-false}" = "true" ]; then
    log_error "Terraform no está instalado en el runner de CI"
    echo "Por favor instala Terraform en el runner self-hosted o en la imagen base"
    exit 1
  fi
  
  log_warning "Terraform no está instalado. Intentando instalar..."
  
  if is_command_available brew; then
    brew install terraform
    log_success "Terraform instalado con brew"
  elif is_command_available apt-get; then
    log_info "Necesita privilegios de administrador para instalar Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update && sudo apt-get install -y terraform
    log_success "Terraform instalado con apt"
  else
    log_error "No se pudo instalar Terraform. Instálalo manualmente desde:"
    echo "  https://www.terraform.io/downloads"
    exit 1
  fi
else
  log_success "Terraform ya está instalado: $(terraform version | head -n1)"
fi

# Verificar AWS CLI
if ! is_command_available aws; then
  if [ "${CI:-false}" = "true" ]; then
    log_error "AWS CLI no está instalado en el runner de CI"
    echo "Por favor instala AWS CLI en el runner self-hosted o en la imagen base"
    exit 1
  fi
  
  log_warning "AWS CLI no está instalado. Intentando instalar..."
  
  if is_command_available brew; then
    brew install awscli
    log_success "AWS CLI instalado con brew"
  elif is_command_available apt-get; then
    log_info "Necesita privilegios de administrador para instalar AWS CLI..."
    sudo apt-get update && sudo apt-get install -y awscli
    log_success "AWS CLI instalado con apt"
  else
    log_error "No se pudo instalar AWS CLI. Instálalo manualmente desde:"
    echo "  https://aws.amazon.com/cli/"
    exit 1
  fi
else
  log_success "AWS CLI ya está instalado: $(aws --version)"
fi

# Verificar kubeseal
if ! is_command_available kubeseal; then
  log_error "kubeseal no está instalado. Por favor instálalo primero:"
  echo "  https://github.com/bitnami-labs/sealed-secrets/releases"
  exit 1
else
  log_success "kubeseal ya está instalado: $(kubeseal --version)"
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
if retry helm repo update; then
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

# Construir valores
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

# Agregar valores inline para credenciales y configuración
HELM_ARGS+=(
  "--set" "localstack.services=s3"
  "--set" "localstack.env.AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
  "--set" "localstack.env.AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
  "--set" "localstack.env.AWS_REGION=$AWS_REGION"
)

if helm "${HELM_ARGS[@]}"; then
  log_success "LocalStack instalado correctamente"
else
  log_error "Falló la instalación de LocalStack"
  exit 1
fi

# Esperar a que el pod esté listo
log_info "Esperando a que LocalStack esté completamente listo..."
if kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=localstack \
  -n "$LOCALSTACK_NAMESPACE" \
  --timeout=300s; then
  log_success "LocalStack está listo"
else
  log_warning "Timeout esperando a LocalStack, continuando de todas formas..."
fi

echo "::endgroup::"

# ============================================================================
# Crear Ingress
# ============================================================================

echo "::group::Creando Ingress para LocalStack"

log_info "Creando Ingress en localstack.local..."

INGRESS_FILE=$(mktemp)
cat > "$INGRESS_FILE" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: localstack
  namespace: localstack
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
    - host: localstack.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: localstack
                port:
                  number: 4566
EOF

if kubectl apply -f "$INGRESS_FILE"; then
  log_success "Ingress creado correctamente"
else
  log_error "Falló al crear Ingress"
  rm -f "$INGRESS_FILE"
  exit 1
fi

rm -f "$INGRESS_FILE"
echo "::endgroup::"

# ============================================================================
# Verificar que LocalStack es accesible via HTTP
# ============================================================================

echo "::group::Verificando salud de LocalStack via HTTP"

HEALTH_PATH="/_localstack/health"
LS_HOST="localstack.local"
LOCALSTACK_WAIT_SECONDS=${LOCALSTACK_WAIT_SECONDS:-60}
TRY_MAX=${TRY_MAX:-12}

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

echo "::group::Ejecutando Terraform"

if [ ! -d "$REPO_ROOT/$TERRAFORM_DIR" ]; then
  log_error "Directorio Terraform no encontrado: $REPO_ROOT/$TERRAFORM_DIR"
  exit 1
fi

cd "$REPO_ROOT/$TERRAFORM_DIR"
log_info "Cambio a directorio: $(pwd)"

# Inicializar Terraform
log_info "Inicializando Terraform..."
if terraform init \
  -backend-config="access_key=$AWS_ACCESS_KEY_ID" \
  -backend-config="secret_key=$AWS_SECRET_ACCESS_KEY"; then
  log_success "Terraform inicializado"
else
  log_error "Falló la inicialización de Terraform"
  exit 1
fi

# Plan
log_info "Generando plan de Terraform..."
if terraform plan \
  -var="aws_access_key=$AWS_ACCESS_KEY_ID" \
  -var="aws_secret_key=$AWS_SECRET_ACCESS_KEY" \
  -var="aws_region=$AWS_REGION" \
  -out=tfplan; then
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
log_success "LocalStack instalado y configurado exitosamente"
echo ""
log_info "Detalles:"
echo "  Namespace: $LOCALSTACK_NAMESPACE"
echo "  Release Helm: $LOCALSTACK_RELEASE_NAME"
echo "  Ingress: localstack.local"
echo "  Endpoint S3: http://localstack.local"
echo ""
log_info "Verificar estado:"
echo "  kubectl -n $LOCALSTACK_NAMESPACE get pods"
echo "  kubectl -n $LOCALSTACK_NAMESPACE get svc"
echo "  kubectl -n $LOCALSTACK_NAMESPACE get ingress"
echo ""
log_info "Credenciales (desde secret sellado):"
echo "  kubectl -n $LOCALSTACK_NAMESPACE get secret $AWS_SECRET_NAME -o yaml"
echo ""
log_info "Sealed Secret file guardado en:"
echo "  $SEALED_SECRETS_DIR/${AWS_SECRET_NAME}.yaml"
echo "::endgroup::"

exit 0
