#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Script para crear ClusterIssuer autofirmado con cert-manager
# Idempotente: se ejecuta solo una vez, no falla si ya existe

CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
CLUSTERISSUER_NAME="mygitops-ca"
CA_CERTIFICATE_NAME="mygitops-ca"

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERISSUER_FILE="${SCRIPT_DIR}/../cert-manager/clusterissuer.yaml"

# Configurar kubeconfig
KUBECONFIG="${KUBECONFIG:-${HOME}/kubeconfig}"
export KUBECONFIG

echo "::group::Validando KUBECONFIG"
if [ ! -f "$KUBECONFIG" ]; then
  echo "ERROR: KUBECONFIG no existe en: $KUBECONFIG"
  exit 1
fi
echo "✓ KUBECONFIG disponible: $KUBECONFIG"
echo "::endgroup::"

echo "::group::Verificando que cert-manager está instalado"
# Intentar contactar el webhook de cert-manager (indica que está listo)
if ! kubectl get crd certificaterequests.cert-manager.io &>/dev/null; then
  echo "ERROR: cert-manager no está instalado o no está listo"
  echo "Ejecutar bootstrap_certmanager.sh primero"
  exit 1
fi
echo "✓ cert-manager está instalado y operativo"
echo "::endgroup::"

echo "::group::Verificando si ClusterIssuer ya existe"
if kubectl get clusterissuer "$CLUSTERISSUER_NAME" &>/dev/null; then
  echo "ℹ ClusterIssuer '$CLUSTERISSUER_NAME' ya existe"
  echo "Saltando creación para evitar cambios innecesarios"
  echo "::endgroup::"
  exit 0
fi
echo "✓ ClusterIssuer no existe, procederá a crearlo"
echo "::endgroup::"

echo "::group::Validando archivo de definición"
if [ ! -f "$CLUSTERISSUER_FILE" ]; then
  echo "ERROR: Archivo de ClusterIssuer no encontrado: $CLUSTERISSUER_FILE"
  exit 1
fi
echo "✓ Archivo de definición encontrado: $CLUSTERISSUER_FILE"
echo "::endgroup::"

echo "::group::Aplicando Certificate y ClusterIssuer autofirmados"
kubectl apply -f "$CLUSTERISSUER_FILE"
echo "::endgroup::"

echo "::group::Esperando a que el Certificate (CA) esté listo"
MAX_RETRIES=60
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  CERT_READY=$(kubectl get certificate -n "$CERT_MANAGER_NAMESPACE" "$CA_CERTIFICATE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
  
  if [ "$CERT_READY" = "True" ]; then
    echo "✓ Certificate CA '$CA_CERTIFICATE_NAME' está listo"
    kubectl get certificate -n "$CERT_MANAGER_NAMESPACE" "$CA_CERTIFICATE_NAME" -o wide
    break
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "Intento $RETRY_COUNT/$MAX_RETRIES: Esperando a que CA esté lista..."
    sleep 1
  fi
done

if [ "$CERT_READY" != "True" ]; then
  echo "⚠ Timeout esperando a que el Certificate esté listo"
  echo "Verificando estado:"
  kubectl describe certificate -n "$CERT_MANAGER_NAMESPACE" "$CA_CERTIFICATE_NAME" || true
  exit 1
fi
echo "::endgroup::"

echo "::group::Verificando que ClusterIssuer está listo"
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  ISSUER_READY=$(kubectl get clusterissuer "$CLUSTERISSUER_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
  
  if [ "$ISSUER_READY" = "True" ]; then
    echo "✓ ClusterIssuer '$CLUSTERISSUER_NAME' está listo"
    kubectl get clusterissuer "$CLUSTERISSUER_NAME" -o wide
    echo "::endgroup::"
    exit 0
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "Intento $RETRY_COUNT/$MAX_RETRIES: Esperando a que ClusterIssuer esté listo..."
    sleep 1
  fi
done

echo "⚠ Timeout esperando a que ClusterIssuer esté listo"
echo "Verificando estado:"
kubectl describe clusterissuer "$CLUSTERISSUER_NAME" || true
echo "::endgroup::"
exit 0
