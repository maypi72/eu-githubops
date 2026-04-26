#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

NAMESPACE="argocd"
SECRET_NAME="argocd-secret"
OUT_DIR="infra/argocd/sealed-secrets"
CERT_PATH="infra/sealed-secrets/pub-cert.pem"

# Detectar si se ejecuta desde GitHub Actions
# Si la variable CI está definida, no hacemos git push automático
CI_ENVIRONMENT="${CI:-false}"
SKIP_GIT_PUSH="${SKIP_GIT_PUSH:-${CI_ENVIRONMENT}}"

# Nueva variable para forzar la actualización del certificado público si es necesario
FETCH_CERT="${FETCH_CERT:-false}"

echo "::group::Verificando configuración"

# Crear directorio si no existe
mkdir -p "$(dirname "$CERT_PATH")"

# Opción 1: Descargar certificado del cluster si FETCH_CERT=true
if [ "$FETCH_CERT" = "true" ]; then
  echo "[i] FETCH_CERT=true: Intentando descargar certificado público del cluster..."
  
  DOWNLOAD_SUCCESS=false
  
  # Intento 1: Descargar usando etiqueta (forma preferida)
  if timeout 10 kubectl get secret \
    -n kube-system \
    -l sealedsecrets.bitnami.com/status=active \
    -o jsonpath='{.items[0].data.tls\.crt}' 2>/dev/null | \
    base64 -d > "$CERT_PATH" 2>/dev/null; then
    
    if [ -s "$CERT_PATH" ]; then
      echo "  [✓] Certificado descargado desde secret con etiqueta"
      DOWNLOAD_SUCCESS=true
    fi
  fi
  
  # Intento 2: Descargar desde sealed-secrets-key (fallback)
  if [ "$DOWNLOAD_SUCCESS" = "false" ] && timeout 10 kubectl get secret \
    -n kube-system sealed-secrets-key \
    -o jsonpath='{.data.tls\.crt}' 2>/dev/null | \
    base64 -d > "$CERT_PATH" 2>/dev/null; then
    
    if [ -s "$CERT_PATH" ]; then
      echo "  [✓] Certificado descargado desde sealed-secrets-key"
      DOWNLOAD_SUCCESS=true
    fi
  fi
  
  # Si descarga falló, intentar usar certificado local existente
  if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
    echo "  [!] No se pudo descargar del cluster (sealed-secrets podría no estar instalado)"
    
    if [ -f "$CERT_PATH" ]; then
      echo "  [⚠] Usando certificado local existente"
      echo "      Para actualizar con el del cluster, ejecuta nuevamente después de bootstrap-cluster.yml"
    else
      echo "  [!] Certificado local tampoco encontrado en $CERT_PATH"
      echo "      Generando certificado auto-firmado temporal..."
      
      # Generar certificado auto-firmado temporal
      openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /tmp/temp-key.pem \
        -out "$CERT_PATH" \
        -days 365 \
        -subj "/CN=sealed-secrets-temp" 2>/dev/null || {
        echo "  [✗] ERROR: No se pudo generar certificado auto-firmado"
        exit 1
      }
      
      echo "  [✓] Certificado temporal generado"
      echo "      ⚠️  ADVERTENCIA: Usando certificado auto-firmado temporal"
      echo "      Después de instalar sealed-secrets via bootstrap-cluster.yml:"
      echo "      $ FETCH_CERT=true $0"
      echo "      para reemplazarlo con el certificado del cluster real"
      
      DOWNLOAD_SUCCESS=true
    fi
  fi
  
  if [ "$DOWNLOAD_SUCCESS" = "true" ]; then
    echo "✓ Certificado disponible: $CERT_PATH"
  else
    echo "[✗] ERROR: No se pudo obtener certificado"
    exit 1
  fi
else
  # Opción 2: Verificar que la clave pública existe en ruta local
  if [ ! -f "$CERT_PATH" ]; then
    echo "[!] Certificado público no encontrado en $CERT_PATH"
    echo "    Intentando descargar del cluster..."
    
    # Intento 1: Descargar usando etiqueta
    if timeout 10 kubectl get secret \
      -n kube-system \
      -l sealedsecrets.bitnami.com/status=active \
      -o jsonpath='{.items[0].data.tls\.crt}' 2>/dev/null | \
      base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
      echo "✓ Certificado descargado del cluster"
    # Intento 2: Descargar desde sealed-secrets-key
    elif timeout 10 kubectl get secret \
      -n kube-system sealed-secrets-key \
      -o jsonpath='{.data.tls\.crt}' 2>/dev/null | \
      base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
      echo "✓ Certificado descargado del cluster"
    else
      echo "[✗] ERROR: Certificado no encontrado en:"
      echo "    • Ruta local: $CERT_PATH"
      echo "    • Cluster: sealed-secrets en kube-system"
      echo ""
      echo "    Soluciones:"
      echo "    1. Ejecutar bootstrap-cluster.yml para instalar sealed-secrets"
      echo "    2. O usar: FETCH_CERT=true $0"
      exit 1
    fi
  else
    echo "✓ Certificado público: $CERT_PATH"
  fi
fi
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

if ! command -v jq &> /dev/null; then
  echo "[!] jq no encontrado. Instalando..."
  sudo apt-get update && sudo apt-get install -y jq
fi
echo "✓ jq disponible"

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

echo "::endgroup::"

echo "::group::Generando hash bcrypt"
htpasswd=$(htpasswd -bnBC 10 "" "$ARGOCD_ADMIN_PASSWORD" | tr -d ':\n')
echo "✓ Hash bcrypt generado"
echo "::endgroup::"

echo "::group::Creando Secret local (con merge de campos existentes)"

# Generar una clave de servidor aleatoria
SERVER_SECRET_KEY=$(openssl rand -base64 32)

# Intentar obtener el Secret existente para hacer merge
EXISTING_DATA="{}"
PERFORM_MERGE=false

if [ "$CI_ENVIRONMENT" != "true" ]; then
  # Solo en entorno local intentamos obtener el secret actual
  echo "[i] Intentando obtener Secret actual para hacer merge..."
  
  # Intentar extraer el Secret desencriptado del cluster
  if timeout 5 kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json 2>/dev/null | \
    jq '.data' 2>/dev/null > /tmp/existing_data.json; then
    
    if [ -s /tmp/existing_data.json ] && grep -q "." /tmp/existing_data.json; then
      # Convertir los datos base64 existentes a un objeto JSON decodificado
      EXISTING_DATA=$(jq 'to_entries | map({(.key): (.value | @base64d)}) | add' /tmp/existing_data.json 2>/dev/null || echo "{}")
      
      if [ "$EXISTING_DATA" != "{}" ] && [ "$EXISTING_DATA" != "null" ]; then
        echo "  [✓] Secret actual encontrado - realizando merge"
        PERFORM_MERGE=true
        
        # Preservar campos que no vamos a actualizar (excepto admin.password y admin.passwordMtime)
        echo "  [i] Campos a preservar (no se actualizan):"
        echo "$EXISTING_DATA" | jq 'keys[]' 2>/dev/null | grep -v "admin.password" | grep -v "admin.passwordMtime" || true
      else
        echo "  [i] Secret actual vacío o no válido - creando nuevo"
      fi
    else
      echo "  [i] Secret actual no encontrado - creando nuevo"
    fi
  else
    echo "  [i] No se pudo obtener Secret actual - creando nuevo"
  fi
  rm -f /tmp/existing_data.json 2>/dev/null || true
else
  echo "[i] En CI environment - creando Secret sin merge"
fi

# Crear base de datos con los valores nuevos
cat <<EOF > "${OUT_DIR}/${SECRET_NAME}.raw.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  annotations:
    argocd.argoproj.io/sync-wave: "0"
type: Opaque
data:
  admin.password: $(echo -n "$htpasswd" | base64 -w0)
  admin.passwordMtime: $(date -u +"%Y-%m-%dT%H:%M:%SZ" | base64 -w0)
  server.secretkey: $(echo -n "$SERVER_SECRET_KEY" | base64 -w0)
EOF

# Si hay datos existentes para mergeado, agregarlos al Secret (excepto los que ya actualizamos)
if [ "$PERFORM_MERGE" = "true" ] && [ "$EXISTING_DATA" != "{}" ] && [ "$EXISTING_DATA" != "null" ]; then
  echo "  [✓] Fusionando campos existentes..."
  
  # Usar yq para agregar los campos existentes que no estamos actualizando
  TEMP_YAML="/tmp/${SECRET_NAME}.merge.yaml"
  cp "${OUT_DIR}/${SECRET_NAME}.raw.yaml" "$TEMP_YAML"
  
  # Para cada campo del Secret existente que no sea admin.password o admin.passwordMtime
  echo "$EXISTING_DATA" | jq -r 'to_entries[] | select(.key != "admin.password" and .key != "admin.passwordMtime") | .key + "=" + (.value | @base64)' | while IFS='=' read -r key value; do
    echo "  • Preservando: $key"
    yq eval ".data.\"$key\" = \"$value\"" -i "$TEMP_YAML"
  done
  
  # Reemplazar el archivo raw con la versión mergeada
  mv "$TEMP_YAML" "${OUT_DIR}/${SECRET_NAME}.raw.yaml"
  echo "  [✓] Merge completado"
else
  if [ "$PERFORM_MERGE" = "true" ]; then
    echo "  [!] No se pudo realizar merge, usando nuevos valores"
  fi
fi

echo "✓ Secret creado en ${OUT_DIR}/${SECRET_NAME}.raw.yaml"
echo "::endgroup::"

echo "::group::Sellando Secret con kubeseal (usando clave pública)"
kubeseal \
  --cert "$CERT_PATH" \
  --format yaml \
  --scope strict \
  < "${OUT_DIR}/${SECRET_NAME}.raw.yaml" \
  > "${OUT_DIR}/${SECRET_NAME}.yaml"

# Eliminar cualquier contenido malformado después del SealedSecret válido
sed -i '/^---$/d' "${OUT_DIR}/${SECRET_NAME}.yaml"

echo "✓ Secret sellado en ${OUT_DIR}/${SECRET_NAME}.yaml"
echo "::endgroup::"

echo "::group::Limpieza"
rm -f "${OUT_DIR}/${SECRET_NAME}.raw.yaml"
echo "✓ Archivo raw eliminado"
echo "::endgroup::"

echo "::group::Git operations"

# Preparar git (en caso de que no esté configurado)
if [ "$CI_ENVIRONMENT" = "true" ]; then
  echo "[i] Ambiente CI detectado (GitHub Actions)"
  # Configurar git en CI
  git config user.name "github-actions[bot]" 2>/dev/null || true
  git config user.email "github-actions[bot]@users.noreply.github.com" 2>/dev/null || true
fi

# Agregar el secreto sellado
git add "${OUT_DIR}/${SECRET_NAME}.yaml"

# Si se descargó certificado del cluster, también agregarlo
if [ "$FETCH_CERT" = "true" ] && [ -f "$CERT_PATH" ]; then
  echo "[i] Certificado descargado - incluyendo en commit"
  git add "$CERT_PATH"
fi

# Crear commit si hay cambios
if git diff --cached --quiet; then
  echo "[!] Sin cambios para hacer commit"
else
  # Determinar mensaje del commit
  if [ "$FETCH_CERT" = "true" ]; then
    COMMIT_MSG="chore: update ArgoCD sealed secret and cluster certificate"
  else
    COMMIT_MSG="chore: update ArgoCD sealed secret"
  fi
  
  git commit -m "$COMMIT_MSG"
  
  if [ "$SKIP_GIT_PUSH" = "true" ]; then
    echo "[i] Push skipped (ejecutándose en CI environment)"
    echo "    El workflow de GitHub Actions hará el push después"
  else
    git push origin $(git rev-parse --abbrev-ref HEAD)
    echo "✓ Commit y push realizados"
  fi
fi
echo "::endgroup::"

echo ""
echo "════════════════════════════════════════════════"
echo "[✓] Secreto sellado generado correctamente"
echo ""
echo "Archivos actualizados:"
echo "  📄 infra/argocd/sealed-secrets/argocd-secret.yaml"

if [ "$FETCH_CERT" = "true" ]; then
  echo "  📄 $CERT_PATH (descargado del cluster)"
fi

echo ""
echo "🚀 Próximos pasos:"
if [ "$FETCH_CERT" = "true" ]; then
  echo "  • Certificado descargado y subido al repo ✓"
fi
echo "  • Secreto listo para ser aplicado al cluster"
echo "  • En CI: bootstrap-argocd.yaml hará push automáticamente"
echo "════════════════════════════════════════════════"
echo "════════════════════════════════════════════════"