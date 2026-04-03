#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Config
INGRESS_NAMESPACE="ingress-nginx"
INGRESS_RELEASE="ingress-nginx"
INGRESS_CHART="ingress-nginx/ingress-nginx"
INGRESS_REPO="https://kubernetes.github.io/ingress-nginx"

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

echo "::group::Comprobando KUBECONFIG"
KUBECONFIG="${KUBECONFIG:-$HOME/kubeconfig}"
export KUBECONFIG

if [ ! -f "$KUBECONFIG" ]; then
  echo "ERROR: KUBECONFIG no existe en: $KUBECONFIG"
  exit 1
fi
echo "✓ Usando KUBECONFIG: $KUBECONFIG"
echo "::endgroup::"

echo "::group::Añadiendo repositorio Helm"
retry helm repo add ingress-nginx "$INGRESS_REPO"
retry helm repo update
echo "::endgroup::"

echo "::group::Instalando NGINX Ingress Controller"
if helm status "$INGRESS_RELEASE" -n "$INGRESS_NAMESPACE" >/dev/null 2>&1; then
  echo "Ingress ya instalado, ejecutando upgrade --install"
else
  echo "Ingress no instalado, procediendo a instalar"
fi

retry helm upgrade --install "$INGRESS_RELEASE" "$INGRESS_CHART" \
  --namespace "$INGRESS_NAMESPACE" \
  --create-namespace \
  --atomic --wait --timeout 10m \
  --set controller.watchIngressWithoutClass=true \
  --set controller.ingressClassResource.default=true

echo "::endgroup::"

echo "::group::Esperando a que el Ingress Controller esté listo"
retry kubectl rollout status deployment/ingress-nginx-controller \
  -n "$INGRESS_NAMESPACE" --timeout=300s
echo "::endgroup::"

echo "bootstrap_ingress.sh completado correctamente"
