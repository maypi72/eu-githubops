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
  echo "✓ Ingress Controller ya está instalado en el namespace '$INGRESS_NAMESPACE'"
  echo "::endgroup::"
  
  echo "::group::Verificando que el Ingress Controller está listo"
else
  echo "Ingress Controller no instalado, procediendo a instalar"
  
  retry helm install "$INGRESS_RELEASE" "$INGRESS_CHART" \
    --namespace "$INGRESS_NAMESPACE" \
    --create-namespace \
    --atomic --wait --timeout 10m \
    -f "$INGRESS_VALUES"

  echo "✓ NGINX Ingress Controller instalado"
  echo "::endgroup::"
  
  echo "::group::Verificando que el Ingress Controller está listo"
fi

echo "::group::Verificando que el Ingress Controller está listo"

# El ingress-nginx puede desplegarse como Deployment o DaemonSet según la configuración
# Intentar esperar al daemonset primero
if kubectl get daemonset ingress-nginx-controller -n "$INGRESS_NAMESPACE" >/dev/null 2>&1; then
  echo "Esperando que el DaemonSet ingress-nginx-controller esté listo..."
  MAX_WAIT=300
  ELAPSED=0
  INTERVAL=5
  
  while [ $ELAPSED -lt $MAX_WAIT ]; do
    DESIRED=$(kubectl get daemonset ingress-nginx-controller -n "$INGRESS_NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}')
    READY=$(kubectl get daemonset ingress-nginx-controller -n "$INGRESS_NAMESPACE" -o jsonpath='{.status.numberReady}')
    
    echo "  DaemonSet: $READY/$DESIRED pods listos (${ELAPSED}s)"
    
    if [ "$DESIRED" -eq "$READY" ] && [ "$READY" -gt 0 ]; then
      echo -e "✓ Ingress Controller DaemonSet está listo"
      break
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done
  
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠ Timeout esperando al DaemonSet (pero continuando)"
  fi

# Si no es DaemonSet, intentar con Deployment
elif kubectl get deployment ingress-nginx-controller -n "$INGRESS_NAMESPACE" >/dev/null 2>&1; then
  echo "Esperando que el Deployment ingress-nginx-controller esté listo..."
  if ! kubectl rollout status deployment/ingress-nginx-controller \
    -n "$INGRESS_NAMESPACE" --timeout=300s 2>/dev/null; then
    echo "⚠ Timeout esperando al Deployment (pero continuando)"
  else
    echo "✓ Ingress Controller Deployment está listo"
  fi

# Si no encuentra ni Deployment ni DaemonSet, esperar a los pods directamente
else
  echo "Deployment/DaemonSet no encontrado, esperando pods del ingress controller..."
  echo ""
  echo "Resources en namespace $INGRESS_NAMESPACE:"
  kubectl get all -n "$INGRESS_NAMESPACE" || true
  echo ""
  
  # Esperar a que al menos un pod del ingress esté Running
  MAX_WAIT=300
  ELAPSED=0
  INTERVAL=5
  
  while [ $ELAPSED -lt $MAX_WAIT ]; do
    RUNNING_PODS=$(kubectl get pods -n "$INGRESS_NAMESPACE" \
      -l app.kubernetes.io/name=ingress-nginx \
      --field-selector=status.phase=Running \
      --no-headers 2>/dev/null | wc -l)
    
    echo "  Pods corriendo: $RUNNING_PODS (${ELAPSED}s)"
    
    if [ "$RUNNING_PODS" -gt 0 ]; then
      echo "✓ Ingress Controller pods están en estado Running"
      break
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done
  
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠ Timeout esperando los pods del ingress (pero continuando)"
  fi
fi

echo "::endgroup::"

echo "bootstrap_ingress.sh completado correctamente"
