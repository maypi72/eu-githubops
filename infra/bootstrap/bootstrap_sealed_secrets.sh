#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SEALED_SECRETS_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
SEALED_SECRETS_RELEASE_NAME="${SEALED_SECRETS_RELEASE_NAME:-sealed-secrets}"
HELM_REPO_NAME="${SEALED_SECRETS_HELM_REPO_NAME:-sealed-secrets}"
HELM_REPO_URL="${SEALED_SECRETS_HELM_REPO_URL:-https://bitnami-labs.github.io/sealed-secrets}"
SEALED_SECRETS_CHART="${SEALED_SECRETS_CHART:-sealed-secrets/sealed-secrets}"
SEALED_SECRETS_CHART_VERSION="${SEALED_SECRETS_CHART_VERSION:-}"

# Get the script directory and construct the values file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEALED_SECRETS_VALUES="${SCRIPT_DIR}/../values/sealed_secrets_values.yaml"  

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

is_sealed_secrets_installed() {
  # Verificar si el release de Helm existe
  if helm list -n "$SEALED_SECRETS_NAMESPACE" 2>/dev/null | grep -q "^$SEALED_SECRETS_RELEASE_NAME\s"; then
    return 0
  fi
  return 1
}

echo "::group::Comprobando KUBECONFIG"
KUBECONFIG="${KUBECONFIG:-$HOME/kubeconfig}"
export KUBECONFIG

echo "Comprobando KUBECONFIG en: $KUBECONFIG"

# Reintentos para esperar a que KUBECONFIG esté disponible
MAX_RETRIES=30
RETRY_DELAY=2
for i in $(seq 1 $MAX_RETRIES); do
  if [ -f "$KUBECONFIG" ]; then
    echo "✓ Usando KUBECONFIG: $KUBECONFIG"
    break
  fi
  
  if [ $i -eq $MAX_RETRIES ]; then
    echo "ERROR: KUBECONFIG no existe en: $KUBECONFIG"
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
echo "::endgroup::"

echo "::group::Verificando si Sealed Secrets ya está instalado"
if is_sealed_secrets_installed; then
  echo "✓ Sealed Secrets ya está instalado y operativo en el namespace '$SEALED_SECRETS_NAMESPACE'"
  echo "::endgroup::"
  exit 0
fi
echo "Sealed Secrets no está instalado o no está completamente operativo"
echo "::endgroup::"

# Función para instalar kubeseal
install_kubeseal() {
  echo "::group::Verificando e instalando kubeseal"
  echo "  [i] Verificando kubeseal..."

  if command -v kubeseal >/dev/null 2>&1; then
    echo "    [✓] kubeseal ya está instalado"
    echo "::endgroup::"
    return 0
  fi

  # Versión esperada desde el workflow
  VERSION="${KUBESEAL_VERSION:-v0.36.6}"
  BASE_VERSION="${VERSION#v}"

  echo "  [i] kubeseal no encontrado, instalando..."
  echo "    Versión: $VERSION"

  # Detectar arquitectura
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)   ARCH_DL="amd64" ;;
    aarch64)  ARCH_DL="arm64" ;;
    *) echo "    [✗] Arquitectura no soportada: $ARCH"; echo "::endgroup::"; exit 1 ;;
  esac

  # Construir URL correcta (binario directo, no tar.gz)
  URL="https://github.com/bitnami-labs/sealed-secrets/releases/download/${VERSION}/kubeseal-${BASE_VERSION}-linux-${ARCH_DL}"

  echo "    URL: $URL"

  # Validar que el asset existe
  if ! curl --head --fail -s "$URL" >/dev/null; then
    echo "    [✗] No existe el asset en GitHub Releases"
    echo "::endgroup::"
    exit 1
  fi

  # Descargar e instalar
  curl -L -o /tmp/kubeseal "$URL"
  chmod +x /tmp/kubeseal
  sudo mv /tmp/kubeseal /usr/local/bin/

  echo "    [✓] kubeseal instalado correctamente"
  echo "::endgroup::"
}

# Instalar kubeseal
install_kubeseal

echo "::group::Comprobando fichero de values"
if [ ! -f "$SEALED_SECRETS_VALUES" ]; then
  echo "ERROR: Fichero de values no existe en: $SEALED_SECRETS_VALUES"
  exit 1
fi
echo "✓ Fichero de values encontrado: $SEALED_SECRETS_VALUES"
echo "::endgroup::" 

echo "::group::Añadiendo repositorio de Helm: $HELM_REPO_NAME"
# Verificar si el repositorio ya existe
if helm repo list | grep -q "^$HELM_REPO_NAME\s"; then
  echo "✓ Repositorio de Helm '$HELM_REPO_NAME' ya existe"
else
  if helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"; then
    echo "✓ Repositorio de Helm '$HELM_REPO_NAME' añadido correctamente"
  else
    echo "ERROR: No se pudo añadir el repositorio de Helm '$HELM_REPO_NAME'"
    exit 1
  fi
fi
echo "::endgroup::"

echo "::group::Actualizando repositorios de Helm"
retry helm repo update
echo "::endgroup::" 

echo "::group::Instalando Sealed Secrets con Helm"
if helm upgrade --install "$SEALED_SECRETS_RELEASE_NAME" "$SEALED_SECRETS_CHART" \
  --namespace "$SEALED_SECRETS_NAMESPACE" \
  --create-namespace \
  --values "$SEALED_SECRETS_VALUES" \
  $( [ -n "$SEALED_SECRETS_CHART_VERSION" ] && echo "--version $SEALED_SECRETS_CHART_VERSION" ) \
  --wait; then
  echo "✓ Sealed Secrets instalado correctamente"
else
  echo "ERROR: Falló la instalación de Sealed Secrets"
  exit 1
fi
echo "::endgroup::" 