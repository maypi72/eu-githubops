#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Config
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
CERT_MANAGER_CHART_VERSION="${CERT_MANAGER_CHART_VERSION:-1.14.5}"
HELM_REPO_NAME="jetstack"
HELM_REPO_URL="https://charts.jetstack.io"
RELEASE_NAME="cert-manager"

# Get the script directory and construct the values file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_MANAGER_VALUES="${SCRIPT_DIR}/../values/cert_manager_values.yaml"

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

is_cert_manager_installed() {
  # Verificar si el release de Helm existe
  if ! helm list -n "$CERT_MANAGER_NAMESPACE" 2>/dev/null | grep -q "^$RELEASE_NAME\s"; then
    return 1
  fi
  
  # Verificar si los pods están ready
  local pod_count
  pod_count=$(kubectl get pods -n "$CERT_MANAGER_NAMESPACE" \
    -l app.kubernetes.io/instance=cert-manager \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items | length}' 2>/dev/null || echo "0")
  
  if [ "$pod_count" -gt 0 ]; then
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

echo "::group::Verificando si cert-manager ya está instalado"
if is_cert_manager_installed; then
  echo "✓ cert-manager ya está instalado y operativo en el namespace '$CERT_MANAGER_NAMESPACE'"
  echo "::endgroup::"
  exit 0
fi
echo "cert-manager no está instalado o no está completamente operativo"
echo "::endgroup::"

echo "::group::Comprobando fichero de values"
if [ ! -f "$CERT_MANAGER_VALUES" ]; then
  echo "ERROR: Fichero de values no existe en: $CERT_MANAGER_VALUES"
  exit 1
fi
echo "✓ Fichero de values encontrado: $CERT_MANAGER_VALUES"
echo "::endgroup::"

echo "::group::Añadiendo repositorio de Helm: $HELM_REPO_NAME"
# Verificar si el repositorio ya existe
if helm repo list | grep -q "^$HELM_REPO_NAME\s"; then
    echo "✓ Repositorio '$HELM_REPO_NAME' ya existe"
else
    echo "Añadiendo repositorio '$HELM_REPO_NAME'..."
    retry helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
fi
echo "::endgroup::" 

echo "::group::Actualizando repositorios de Helm"
retry helm repo update
echo "::endgroup::" 

echo "::group::Instalando cert-manager con Helm"
if helm list -n "$CERT_MANAGER_NAMESPACE" | awk '{print $1}' | grep -qx "$RELEASE_NAME"; then
    echo "✓ Release '$RELEASE_NAME' ya instalada en el namespace '$CERT_MANAGER_NAMESPACE'"
else
    echo "Instalando release '$RELEASE_NAME' en el namespace '$CERT_MANAGER_NAMESPACE'..."
    retry helm install "$RELEASE_NAME" "$HELM_REPO_NAME/cert-manager" \
        --namespace "$CERT_MANAGER_NAMESPACE" \
        --create-namespace \
        --version "$CERT_MANAGER_CHART_VERSION" \
        -f "$CERT_MANAGER_VALUES"
fi
echo "✓ Cert-manager instalado"
echo "::endgroup::"

