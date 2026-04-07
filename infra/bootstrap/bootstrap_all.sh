#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Script orquestador para bootstrap completo
# Orden de ejecución:
# 1. bootstrap_k3s.sh
# 2. bootstrap_helm.sh
# 3. bootstrap_ingress.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_K3S="${SCRIPT_DIR}/bootstrap_k3s.sh"
BOOTSTRAP_HELM="${SCRIPT_DIR}/bootstrap_helm.sh"
BOOTSTRAP_INGRESS="${SCRIPT_DIR}/bootstrap_ingress.sh"
BOOTSTRAP_CERT_MANAGER="${SCRIPT_DIR}/bootstrap_certmanager.sh"

# Variables globales
KUBECONFIG="${KUBECONFIG:-${HOME}/kubeconfig}"
export KUBECONFIG

echo "::group::Validación inicial"
echo "================================================"
echo "BOOTSTRAP COMPLETO - Orquestador"
echo "================================================"

# Comprobar que todos los scripts existen
for script in "$BOOTSTRAP_K3S" "$BOOTSTRAP_HELM" "$BOOTSTRAP_INGRESS"; do
  if [ ! -f "$script" ]; then
    echo "ERROR: Script no encontrado: $script"
    exit 1
  fi
  if [ ! -x "$script" ]; then
    echo "ERROR: Script no tiene permisos de ejecución: $script"
    exit 1
  fi
done

echo "✓ Todos los scripts del bootstrap encontrados y ejecutables"
echo "✓ KUBECONFIG se utilizará: $KUBECONFIG"
echo "::endgroup::"

# Función para ejecutar bootstrap con manejo de errores
run_bootstrap() {
  local script_name="$1"
  local script_path="$2"
  
  echo "::group::Ejecutando $script_name"
  echo "================================================"
  
  # Asegurar que KUBECONFIG está disponible para el subproceso
  env KUBECONFIG="$KUBECONFIG" bash "$script_path"
  bootstrap_exit=$?
  
  if [ $bootstrap_exit -eq 0 ]; then
    echo "================================================"
    echo "✓ $script_name completado exitosamente"
    echo "::endgroup::"
    return 0
  else
    echo "================================================"
    echo "✗ ERROR: $script_name falló con código $bootstrap_exit"
    echo "::endgroup::"
    return $bootstrap_exit
  fi
}

# Ejecutar bootstrap en orden
echo "::group::Iniciando secuencia de bootstrap"
FAILED=0

# 1. Instalar k3s
if ! run_bootstrap "bootstrap_k3s.sh" "$BOOTSTRAP_K3S"; then
  FAILED=1
  echo "::error::Falló la instalación de k3s. Abortando bootstrap."
  exit 1
fi

# Verificar que KUBECONFIG está disponible antes de continuar
echo ""
echo "Verificando disponibilidad de KUBECONFIG..."
if [ ! -f "$KUBECONFIG" ]; then
  echo "::error::KUBECONFIG no disponible en $KUBECONFIG después de bootstrap_k3s.sh"
  echo ""
  echo "Diagnosis:"
  echo "1. Verificar estado de k3s:"
  sudo systemctl status k3s || true
  echo ""
  echo "2. Verificar logs de k3s:"
  sudo journalctl -xeu k3s.service -n 50 || true
  echo ""
  echo "3. Verificar archivos en /etc/rancher/k3s/:"
  ls -la /etc/rancher/k3s/ || echo "Directorio no existe"
  echo ""
  echo "4. Verificar permisos del directorio:"
  ls -la "$(dirname "$KUBECONFIG")" || echo "Directorio no existe"
  exit 1
fi

echo "✓ KUBECONFIG disponible en: $KUBECONFIG"
echo ""

# 2. Instalar Helm
if ! run_bootstrap "bootstrap_helm.sh" "$BOOTSTRAP_HELM"; then
  FAILED=1
  echo "::warning::Falló la instalación de Helm, pero continuando..."
fi
echo ""

# 3. Instalar Ingress Controller
if ! run_bootstrap "bootstrap_ingress.sh" "$BOOTSTRAP_INGRESS"; then
  FAILED=1
  echo "::warning::Falló la instalación de Ingress, pero bootstrap parcial completado"
fi

#4. Instalar cert-manager
if ! run_bootstrap "bootstrap_certmanager.sh" "$BOOTSTRAP_CERT_MANAGER"; then
  FAILED=1
  echo "::warning::Falló la instalación de cert-manager, pero bootstrap parcial completado"
fi  

#5. Instalar sealed-secrets
if ! run_bootstrap "bootstrap_sealed_secrets.sh" "$BOOTSTRAP_SEALED_SECRETS"; then
  FAILED=1
  echo "::warning::Falló la instalación de sealed-secrets, pero bootstrap parcial completado"
fi
echo "::endgroup::"

# Resumen final
echo "::group::Resumen del bootstrap"
echo "================================================"

if [ $FAILED -eq 0 ]; then
  echo "✓ BOOTSTRAP COMPLETADO EXITOSAMENTE"
  echo ""
  echo "Estado del cluster:"
  if kubectl get nodes >/dev/null 2>&1; then
    echo "Nodos disponibles:"
    kubectl get nodes
  fi
  echo ""
  if helm list --all-namespaces >/dev/null 2>&1; then
    echo "Releases de Helm instalados:"
    helm list --all-namespaces
  fi
  echo "================================================"
  echo "::endgroup::"
  exit 0
else
  echo "✗ BOOTSTRAP CON ERRORES"
  echo "Revisa los logs anteriores para detalles"
  echo "================================================"
  echo "::endgroup::"
  exit 1
fi
