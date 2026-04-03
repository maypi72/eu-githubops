#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Config
HELM_VERSION="${HELM_VERSION:-v3.14.0}"
HELM_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"
HELM_REPOS=(
  "bitnami:https://charts.bitnami.com/bitnami"
  "jetstack:https://charts.jetstack.io"
  "prometheus-community:https://prometheus-community.github.io/helm-charts"
)

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
# Comprobar KUBECONFIG
if [ -z "${KUBECONFIG:-}" ] || [ ! -f "$KUBECONFIG" ]; then
  echo "ERROR: KUBECONFIG no está definido o no existe"
  exit 1
fi
echo "✓ KUBECONFIG disponible: $KUBECONFIG"

# Comprobar kubectl
if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl no está instalado"
  exit 1
fi
echo "✓ kubectl disponible: $(kubectl version --client --short)"

# Comprobar conectividad al cluster
if ! retry kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: No se puede conectar al cluster"
  exit 1
fi
echo "✓ Cluster Kubernetes accesible"
echo "::endgroup::"

echo "::group::Comprobando si Helm ya está instalado"
if command -v helm >/dev/null 2>&1; then
  HELM_INSTALLED_VERSION=$(helm version --short | cut -d: -f2 | xargs)
  echo "✓ Helm ya instalado: $HELM_INSTALLED_VERSION"
else
  echo "::endgroup::"
  echo "::group::Instalando Helm"
  curl -fsSL "${HELM_INSTALL_SCRIPT_URL}" | bash
  
  if ! command -v helm >/dev/null 2>&1; then
    echo "ERROR: Helm installation failed"
    exit 1
  fi
  echo "✓ Helm instalado correctamente: $(helm version --short | cut -d: -f2 | xargs)"
fi
echo "::endgroup::"

echo "::group::Actualizando repositorios de Helm"
retry helm repo update
echo "✓ Repositorios actualizados"
echo "::endgroup::"

echo "::group::Añadiendo repositorios de Helm necesarios"
for repo in "${HELM_REPOS[@]}"; do
  REPO_NAME="${repo%%:*}"
  REPO_URL="${repo##*:}"
  
  if helm repo list | grep -q "^${REPO_NAME}"; then
    echo "✓ Repositorio $REPO_NAME ya existe, omitiendo"
  else
    echo "Añadiendo repositorio $REPO_NAME desde $REPO_URL"
    retry helm repo add "$REPO_NAME" "$REPO_URL"
    echo "✓ Repositorio $REPO_NAME añadido"
  fi
done
retry helm repo update
echo "::endgroup::"

echo "::group::Verificando estado de Helm"
HELM_VERSION_OUTPUT=$(helm version --short)
echo "Versión de Helm: $HELM_VERSION_OUTPUT"
HELM_REPOS_COUNT=$(helm repo list | wc -l)
echo "Repositorios configurados: $HELM_REPOS_COUNT"
echo "::endgroup::"

echo "bootstrap_helm.sh completado correctamente"
