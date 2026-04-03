#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Config
INGRESS_NAMESPACE="ingress-nginx"
INGRESS_RELEASE="ingress-nginx"
INGRESS_CHART="ingress-nginx/ingress-nginx"
INGRESS_REPO="https://kubernetes.github.io/ingress-nginx"

# Get the script directory and construct the values file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGRESS_VALUES="${SCRIPT_DIR}/../values/ingress_values.yaml"

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

echo "::group::Comprobando fichero de values"
if [ ! -f "$INGRESS_VALUES" ]; then
  echo "ERROR: Fichero de values no existe en: $INGRESS_VALUES"
  exit 1
fi
echo "✓ Fichero de values encontrado: $INGRESS_VALUES"
echo "::endgroup::"

echo "::group::Añadiendo repositorio Helm"
# Verificar si el repositorio ya existe
if helm repo list 2>/dev/null | grep -q "^ingress-nginx"; then
  echo "✓ Repositorio ingress-nginx ya existe"
else
  echo "Agregando repositorio ingress-nginx..."
  retry helm repo add ingress-nginx "$INGRESS_REPO"
fi

# Actualizar repositorios si hay alguno configurado
REPOS_COUNT=$(helm repo list 2>/dev/null | tail -n +2 | wc -l)
if [ "$REPOS_COUNT" -gt 0 ]; then
  retry helm repo update
  echo "✓ Repositorios actualizados"
fi
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
  -f "$INGRESS_VALUES"

echo "✓ NGINX Ingress Controller instalado"
echo "::endgroup::"

echo "::group::Verificando que el Ingress Controller está listo"

# Verificar que el deployment existe
if ! kubectl get deployment ingress-nginx-controller -n "$INGRESS_NAMESPACE" >/dev/null 2>&1; then
  echo "⚠ Deployment 'ingress-nginx-controller' no encontrado"
  echo ""
  echo "Listando resources en namespace $INGRESS_NAMESPACE:"
  kubectl get all -n "$INGRESS_NAMESPACE" || true
  echo ""
  echo "Verificando si el deployment tiene un nombre diferente:"
  kubectl get deployments -n "$INGRESS_NAMESPACE" || true
  exit 1
fi

# Hacer rollout status si el deployment existe
if kubectl rollout status deployment/ingress-nginx-controller \
  -n "$INGRESS_NAMESPACE" --timeout=300s >/dev/null 2>&1; then
  echo "✓ Ingress Controller está listo"
else
  echo "⚠ Ingress Controller no llegó a estado Ready dentro del timeout"
  echo ""
  echo "Estado del deployment:"
  kubectl describe deployment ingress-nginx-controller -n "$INGRESS_NAMESPACE" || true
  echo ""
  echo "Estado de los pods:"
  kubectl get pods -n "$INGRESS_NAMESPACE" || true
  exit 1
fi
echo "::endgroup::"

echo "bootstrap_ingress.sh completado correctamente"
