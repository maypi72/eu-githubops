#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

NAMESPACE="argocd"
SECRET_NAME="argocd-secret"
OUT_DIR="infra/argocd/sealed-secrets"

# Configurar KUBECONFIG
KUBECONFIG="${KUBECONFIG:-${HOME}/kubeconfig}"
export KUBECONFIG

echo "::group::Verificando configuración de Kubernetes"
if [ ! -f "$KUBECONFIG" ]; then
  echo "ERROR: KUBECONFIG no encontrado en $KUBECONFIG"
  exit 1
fi
echo "✓ KUBECONFIG: $KUBECONFIG"

# Verificar conectividad con el cluster
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: No se puede conectar al cluster"
  echo "Verificar KUBECONFIG y cluster status"
  exit 1
fi
echo "✓ Cluster accesible"
echo "::endgroup::"

echo "::group::Comprobando directorio de salida"
if [ ! -d "${OUT_DIR}" ]; then
  mkdir -p "${OUT_DIR}"
  echo "✓ Directorio creado: ${OUT_DIR}"
else
  echo "✓ Directorio ya existe: ${OUT_DIR}"
fi
echo "::endgroup::"

echo "::group::Validando variables de entorno"
if [ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]; then
  echo "ERROR: Debes exportar ARGOCD_ADMIN_PASSWORD"
  exit 1
fi
echo "✓ ARGOCD_ADMIN_PASSWORD configurada"
echo "::endgroup::"

echo "::group::Verificando dependencias"

if ! command -v htpasswd &> /dev/null; then
  echo "[!] htpasswd no encontrado. Instalando..."
  sudo apt-get update && sudo apt-get install -y apache2-utils
fi
echo "✓ htpasswd disponible"

if ! command -v yq &> /dev/null; then
  echo "[!] yq no encontrado. Instalando..."
  if ! sudo curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq; then
    echo "ERROR: No se pudo descargar yq"
    exit 1
  fi
  sudo chmod +x /usr/local/bin/yq
fi
echo "✓ yq disponible"

if ! command -v kubeseal &> /dev/null; then
  echo "[!] kubeseal no encontrado. Instalando..."
  KUBESEAL_TMP=$(mktemp -d)
  trap "rm -rf $KUBESEAL_TMP" EXIT
  if ! wget -qO - https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz | tar xfz - -C "$KUBESEAL_TMP"; then
    echo "ERROR: No se pudo descargar e instalar kubeseal"
    exit 1
  fi
  if ! sudo mv "$KUBESEAL_TMP/kubeseal" /usr/local/bin/ || ! sudo chmod +x /usr/local/bin/kubeseal; then
    echo "ERROR: No se pudo mover kubeseal a /usr/local/bin"
    exit 1
  fi
fi
echo "✓ kubeseal disponible"

echo ""
echo "Verificando que kubeseal puede acceder al controller..."
if ! kubeseal --kubeconfig "$KUBECONFIG" --print-sealed-secret < /dev/null &>/dev/null; then
  echo "[!] kubeseal conectando al controller: $(kubeseal --kubeconfig "$KUBECONFIG" --print-sealed-secret < /dev/null 2>&1 || true)"
fi

echo "::endgroup::"

echo "::group::Generando hash bcrypt"
htpasswd=$(htpasswd -bnBC 10 "" "$ARGOCD_ADMIN_PASSWORD" | tr -d ':\n')
echo "✓ Hash bcrypt generado"
echo "::endgroup::"

echo "::group::Creando Secret local"
cat <<EOF > "${OUT_DIR}/${SECRET_NAME}.raw.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
data:
  admin.password: $(echo -n "$htpasswd" | base64 -w0)
  admin.passwordMtime: $(date +%s | base64 -w0)
EOF
echo "✓ Secret creado en ${OUT_DIR}/${SECRET_NAME}.raw.yaml"
echo "::endgroup::"

echo "::group::Sellando Secret con kubeseal"
kubeseal \
  --kubeconfig "$KUBECONFIG" \
  --format yaml \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  < "${OUT_DIR}/${SECRET_NAME}.raw.yaml" \
  > "${OUT_DIR}/${SECRET_NAME}.yaml"
echo "✓ Secret sellado en ${OUT_DIR}/${SECRET_NAME}.yaml"
echo "::endgroup::"

echo "::group::Añadiendo sync-wave"
yq e '.metadata.annotations."argocd.argoproj.io/sync-wave" = "0"' -i "${OUT_DIR}/${SECRET_NAME}.yaml"
echo "✓ sync-wave añadido"
echo "::endgroup::"

echo "::group::Limpieza"
rm -f "${OUT_DIR}/${SECRET_NAME}.raw.yaml"
echo "✓ Archivo raw eliminado"
echo "::endgroup::"

echo "::group::Git operations"
git add "${OUT_DIR}/${SECRET_NAME}.yaml"
if git diff --cached --quiet; then
  echo "[!] Sin cambios para hacer commit"
else
  git commit -m "chore: update ArgoCD sealed secret"
  git push origin $(git rev-parse --abbrev-ref HEAD)
  echo "✓ Commit y push realizados"
fi
echo "::endgroup::"

echo ""
echo "════════════════════════════════════════════════"
echo "[✓] Secret sellado correctamente"
echo "════════════════════════════════════════════════"