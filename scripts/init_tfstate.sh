#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Script: init_tfstate.sh
# Descripción: Inicializa Terraform con el state remoto en LocalStack S3
# Requisitos: terraform, aws cli, kubeconfig, LocalStack disponible
# ============================================================================

TERRAFORM_DIR="${TERRAFORM_DIR:-infra/terraform/localstak}"
AWS_REGION="${AWS_REGION:-eu-west-1}"

# Variables de credenciales (deben estar en el entorno)
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# ============================================================================
# Verificaciones previas
# ============================================================================

echo "::group::Verificando requisitos"

if [ ! -d "$TERRAFORM_DIR" ]; then
  log_error "Directorio Terraform no encontrado: $TERRAFORM_DIR"
  exit 1
fi

if ! command -v terraform &>/dev/null; then
  log_error "Terraform no está instalado"
  exit 1
fi

if ! command -v aws &>/dev/null; then
  log_error "AWS CLI no está instalado"
  exit 1
fi

log_success "Verificaciones completadas"
echo "::endgroup::"

# ============================================================================
# Cambiar a directorio Terraform
# ============================================================================

log_info "Cambiando a directorio: $TERRAFORM_DIR"
cd "$TERRAFORM_DIR"

# ============================================================================
# Inicializar Terraform
# ============================================================================

echo "::group::Inicializando Terraform"

log_info "Ejecutando: terraform init"
log_info "Backend S3 en LocalStack: http://localstack.local"
log_info "Bucket: la-huella-remote-state"
log_info "Key: global/terraform.tfstate"
log_info "Región: $AWS_REGION"

# Exportar credenciales para terraform (con valores reales, no enmascarados)
export TF_VAR_aws_access_key="$AWS_ACCESS_KEY_ID"
export TF_VAR_aws_secret_key="$AWS_SECRET_ACCESS_KEY"
export TF_VAR_aws_region="$AWS_REGION"

if terraform init \
  -backend-config="bucket=la-huella-remote-state" \
  -backend-config="key=global/terraform.tfstate" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="endpoint=http://localstack.local" \
  -backend-config="use_path_style=true" \
  -backend-config="skip_credentials_validation=true" \
  -backend-config="skip_metadata_api_check=true" \
  -backend-config="skip_region_validation=true" \
  -backend-config="skip_requesting_account_id=true" \
  -backend-config="access_key=$AWS_ACCESS_KEY_ID" \
  -backend-config="secret_key=$AWS_SECRET_ACCESS_KEY"; then
  log_success "Terraform inicializado correctamente"
else
  log_error "Falló la inicialización de Terraform"
  exit 1
fi

echo "::endgroup::"

# ============================================================================
# Validar configuración de Terraform
# ============================================================================

echo "::group::Validando configuración de Terraform"

log_info "Ejecutando: terraform validate"

if terraform validate; then
  log_success "Configuración validada"
else
  log_error "Error en la configuración de Terraform"
  exit 1
fi

echo "::endgroup::"

# ============================================================================
# Resumen
# ============================================================================

echo "::group::Resumen"
log_success "Terraform state inicializado correctamente"
echo ""
log_info "Backend configurado:"
echo "  S3 Bucket: la-huella-remote-state"
echo "  S3 Key: global/terraform.tfstate"
echo "  Endpoint: http://localstack.local"
echo "  Región: $AWS_REGION"
echo ""
log_info "Variables de Terraform configuradas:"
echo "  TF_VAR_aws_access_key: (enmascarada)"
echo "  TF_VAR_aws_secret_key: (enmascarada)"
echo "  TF_VAR_aws_region: $AWS_REGION"
echo ""
log_info "Próximos pasos:"
echo "  terraform plan"
echo "  terraform apply"
echo "::endgroup::"

exit 0