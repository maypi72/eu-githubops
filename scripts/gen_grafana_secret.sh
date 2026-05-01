#!/usr/bin/env bash
# Script para generar el SealedSecret de Grafana
# Genera una contraseña bcrypt para el usuario admin de Grafana
# y la sella usando Sealed Secrets
#
# Requisitos previos:
#   1. sealed-secrets debe estar instalado en el cluster
#   2. El certificado público debe estar disponible en: infra/sealed-secrets/pub-cert.pem
#   3. Herramientas necesarias: kubeseal, kubectl, openssl, base64
#
# Uso:
#   # Generar secret (requiere GRAFANA_ADMIN_PASSWORD)
#   GRAFANA_ADMIN_PASSWORD="tu-contraseña" ./scripts/gen_grafana_secret.sh
#
#   # O descargar certificado del cluster y generar
#   FETCH_CERT=true GRAFANA_ADMIN_PASSWORD="tu-contraseña" ./scripts/gen_grafana_secret.sh
#
# Variables de Entorno:
#   GRAFANA_ADMIN_PASSWORD    (REQUERIDO) Contraseña del admin de Grafana
#   FETCH_CERT                (OPCIONAL)  Si es "true", descarga certificado del cluster
#   SKIP_GIT_PUSH             (OPCIONAL)  Si es "true", no hace push automático
#

set -euo pipefail
IFS=$'\n\t'

# ============================================================
# GENERATE GRAFANA SECRET - Crea secreto sellado para Grafana
# ============================================================

# Configuración de rutas y valores
NAMESPACE="monitoring"
SECRET_NAME="grafana-admin"
OUT_DIR="infra/grafana/sealed-secrets"
CERT_PATH="infra/sealed-secrets/pub-cert.pem"

# Detectar si se ejecuta desde GitHub Actions
CI_ENVIRONMENT="${CI:-false}"
SKIP_GIT_PUSH="${SKIP_GIT_PUSH:-${CI_ENVIRONMENT}}"
FETCH_CERT="${FETCH_CERT:-false}"

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Función de reintentos
retry() {
  local -r max=${RETRY_MAX:-5}
  local -r delay=${RETRY_DELAY:-2}
  local i=0
  until "$@"; do
    i=$((i+1))
    if [ $i -ge $max ]; then
      echo -e "${RED}✗ Comando falló después de $i intentos: $*${NC}"
      return 1
    fi
    echo -e "${YELLOW}🔄 Reintentando ($i/$max): $*${NC}"
    sleep $((delay * i))
  done
}

echo "::group::Verificando configuración"

# Detectar y validar KUBECONFIG
echo "[i] Buscando KUBECONFIG..."
KUBECONFIG_PATHS=(
  "${RUNNER_TEMP}/kubeconfig-artifact/kubeconfig"  # Desde artefacto de Actions
  "/etc/rancher/k3s/k3s.yaml"                       # k3s instalado
  "${HOME}/kubeconfig"                              # Ubicación estándar
  "${HOME}/.kube/config"                            # Ubicación por defecto
)

KUBECONFIG_FOUND=false
for kb_path in "${KUBECONFIG_PATHS[@]}"; do
  if [ -f "$kb_path" ]; then
    export KUBECONFIG="$kb_path"
    echo -e "${GREEN}✓ KUBECONFIG encontrado: $KUBECONFIG${NC}"
    KUBECONFIG_FOUND=true
    break
  fi
done

if [ "$KUBECONFIG_FOUND" = false ]; then
  echo -e "${RED}✗ ERROR: No se encontró KUBECONFIG${NC}"
  echo "Se buscó en:"
  for kb_path in "${KUBECONFIG_PATHS[@]}"; do
    echo "  - $kb_path"
  done
  exit 1
fi

# Crear directorio si no existe
mkdir -p "$(dirname "$CERT_PATH")"

# IMPORTANTE: Limpiar certificado inválido si existe
if [ -f "$CERT_PATH" ]; then
  if ! openssl x509 -in "$CERT_PATH" -noout &>/dev/null; then
    echo "[!] Certificado inválido detectado y será regenerado"
    rm -f "$CERT_PATH"
  fi
fi

# Opción 1: Descargar certificado del cluster si FETCH_CERT=true
if [ "$FETCH_CERT" = "true" ]; then
  echo "[i] FETCH_CERT=true: Intentando descargar certificado público del cluster..."
  
  DOWNLOAD_SUCCESS=false
  
  # Intento 1: Usar kubeseal --fetch-cert (método oficial y más simple)
  if timeout 10 kubeseal --fetch-cert \
    --controller-name=sealed-secrets \
    --controller-namespace=kube-system \
    > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
    echo "  [✓] Certificado descargado con kubeseal --fetch-cert"
    DOWNLOAD_SUCCESS=true
  fi
  
  # Intento 2: Descargar usando etiqueta de kubectl (fallback si kubeseal falla)
  if [ "$DOWNLOAD_SUCCESS" = "false" ] && timeout 10 kubectl get secret \
    -n kube-system \
    -l sealedsecrets.bitnami.com/status=active \
    -o jsonpath='{.items[0].data.tls\.crt}' 2>/dev/null | \
    base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
    echo "  [✓] Certificado descargado desde secret con etiqueta"
    DOWNLOAD_SUCCESS=true
  fi
  
  # Intento 3: Descargar desde sealed-secrets-key (fallback adicional)
  if [ "$DOWNLOAD_SUCCESS" = "false" ] && timeout 10 kubectl get secret \
    -n kube-system sealed-secrets-key \
    -o jsonpath='{.data.tls\.crt}' 2>/dev/null | \
    base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
    echo "  [✓] Certificado descargado desde sealed-secrets-key"
    DOWNLOAD_SUCCESS=true
  fi
  
  # Si descarga falló, intentar usar certificado local existente
  if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
    echo "  [!] No se pudo descargar del cluster (sealed-secrets podría no estar instalado)"
    
    if [ -f "$CERT_PATH" ]; then
      # Validar que el certificado local es válido
      if openssl x509 -in "$CERT_PATH" -noout &>/dev/null; then
        echo "  [✓] Usando certificado local existente (válido)"
        echo "      Para actualizar con el del cluster, ejecuta nuevamente después de instalar Grafana"
        DOWNLOAD_SUCCESS=true
      else
        echo "  [⚠] Certificado local existe pero NO ES VÁLIDO"
        echo "      Regenerando certificado auto-firmado nuevo..."
        rm -f "$CERT_PATH"
        
        # Generar certificado auto-firmado temporal
        openssl req -x509 -newkey rsa:2048 -nodes \
          -keyout /tmp/temp-key.pem \
          -out "$CERT_PATH" \
          -days 365 \
          -subj "/CN=sealed-secrets-temp" 2>/dev/null || {
          echo "  [✗] ERROR: No se pudo generar certificado auto-firmado"
          exit 1
        }
        
        # Verificar que el certificado se generó correctamente
        if [ ! -f "$CERT_PATH" ] || [ ! -s "$CERT_PATH" ]; then
          echo "  [✗] ERROR: Certificado generado pero no existe o está vacío"
          exit 1
        fi
        
        if ! openssl x509 -in "$CERT_PATH" -noout &>/dev/null; then
          echo "  [✗] ERROR: Certificado generado pero no es válido"
          exit 1
        fi
        
        echo "  [✓] Certificado nuevo generado y validado"
        DOWNLOAD_SUCCESS=true
      fi
    else
      echo "  [!] Certificado local no encontrado en $CERT_PATH"
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
      
      # Verificar que el certificado se generó correctamente
      if [ ! -f "$CERT_PATH" ] || [ ! -s "$CERT_PATH" ]; then
        echo "  [✗] ERROR: Certificado generado pero no existe o está vacío"
        exit 1
      fi
      
      if ! openssl x509 -in "$CERT_PATH" -noout &>/dev/null; then
        echo "  [✗] ERROR: Certificado generado pero no es válido"
        exit 1
      fi
      
      echo "  [✓] Certificado temporal generado y validado"
      echo "      ⚠️  ADVERTENCIA: Usando certificado auto-firmado temporal"
      echo "      Después de instalar Grafana:"
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
  # Opción 2: Verificar que la clave pública existe en ruta local o descargar del cluster
  if [ ! -f "$CERT_PATH" ]; then
    echo "[!] Certificado público no encontrado en $CERT_PATH"
    echo "    Intentando descargar del cluster..."
    
    DOWNLOAD_SUCCESS=false
    
    # Intento 1: Usar kubeseal --fetch-cert (método oficial)
    if timeout 10 kubeseal --fetch-cert \
      --controller-name=sealed-secrets \
      --controller-namespace=kube-system \
      > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
      echo "[✓] Certificado descargado con kubeseal"
      DOWNLOAD_SUCCESS=true
    # Intento 2: Descargar usando etiqueta
    elif timeout 10 kubectl get secret \
      -n kube-system \
      -l sealedsecrets.bitnami.com/status=active \
      -o jsonpath='{.items[0].data.tls\.crt}' 2>/dev/null | \
      base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
      echo "[✓] Certificado descargado del cluster"
      DOWNLOAD_SUCCESS=true
    # Intento 3: Descargar desde sealed-secrets-key
    elif timeout 10 kubectl get secret \
      -n kube-system sealed-secrets-key \
      -o jsonpath='{.data.tls\.crt}' 2>/dev/null | \
      base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
      echo "[✓] Certificado descargado del cluster"
      DOWNLOAD_SUCCESS=true
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
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
    # Certificado local existe, validarlo
    echo "[i] Certificado local encontrado: $CERT_PATH"
    
    # Verificar que el archivo tiene contenido
    if [ ! -s "$CERT_PATH" ]; then
      echo "[✗] ERROR: Certificado local existe pero está VACÍO"
      echo "    Intentando descargar del cluster..."
      
      DOWNLOAD_SUCCESS=false
      
      # Intento 1: Usar kubeseal --fetch-cert
      if timeout 10 kubeseal --fetch-cert \
        --controller-name=sealed-secrets \
        --controller-namespace=kube-system \
        > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
        echo "[✓] Certificado descargado y reemplazó al vacío"
        DOWNLOAD_SUCCESS=true
      # Intento 2: Descargar usando etiqueta
      elif timeout 10 kubectl get secret \
        -n kube-system \
        -l sealedsecrets.bitnami.com/status=active \
        -o jsonpath='{.items[0].data.tls\.crt}' 2>/dev/null | \
        base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
        echo "[✓] Certificado descargado y reemplazó al vacío"
        DOWNLOAD_SUCCESS=true
      # Intento 3: Descargar desde sealed-secrets-key
      elif timeout 10 kubectl get secret \
        -n kube-system sealed-secrets-key \
        -o jsonpath='{.data.tls\.crt}' 2>/dev/null | \
        base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
        echo "[✓] Certificado descargado y reemplazó al vacío"
        DOWNLOAD_SUCCESS=true
      fi
      
      if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
        echo "[✗] ERROR: No se pudo descargar certificado válido del cluster"
        echo "    Opciones:"
        echo "    1. Usar: FETCH_CERT=true $0"
        echo "    2. O instalar sealed-secrets: bootstrap-cluster.yml"
        exit 1
      fi
    elif ! openssl x509 -in "$CERT_PATH" -noout &>/dev/null; then
      echo "[✗] ERROR: Certificado local existe pero NO ES VÁLIDO"
      echo "    Intentando descargar del cluster..."
      
      DOWNLOAD_SUCCESS=false
      
      # Intento 1: Usar kubeseal --fetch-cert
      if timeout 10 kubeseal --fetch-cert \
        --controller-name=sealed-secrets \
        --controller-namespace=kube-system \
        > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
        echo "[✓] Certificado descargado y reemplazó al inválido"
        DOWNLOAD_SUCCESS=true
      # Intento 2: Descargar usando etiqueta
      elif timeout 10 kubectl get secret \
        -n kube-system \
        -l sealedsecrets.bitnami.com/status=active \
        -o jsonpath='{.items[0].data.tls\.crt}' 2>/dev/null | \
        base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
        echo "[✓] Certificado descargado y reemplazó al inválido"
        DOWNLOAD_SUCCESS=true
      # Intento 3: Descargar desde sealed-secrets-key
      elif timeout 10 kubectl get secret \
        -n kube-system sealed-secrets-key \
        -o jsonpath='{.data.tls\.crt}' 2>/dev/null | \
        base64 -d > "$CERT_PATH" 2>/dev/null && [ -s "$CERT_PATH" ]; then
        echo "[✓] Certificado descargado y reemplazó al inválido"
        DOWNLOAD_SUCCESS=true
      fi
      
      if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
        echo "[✗] ERROR: No se pudo descargar certificado válido del cluster"
        echo "    Opciones:"
        echo "    1. Usar: FETCH_CERT=true $0"
        echo "    2. O instalar sealed-secrets: bootstrap-cluster.yml"
        exit 1
      fi
    else
      echo "[✓] Certificado local válido"
    fi
  fi
fi
echo "::endgroup::"

echo "::group::Validando conectividad al cluster"
if ! retry kubectl cluster-info >/dev/null 2>&1; then
  echo -e "${RED}✗ ERROR: No se puede conectar al cluster${NC}"
  echo ""
  echo "Verifica:"
  echo "1. Que K3s está corriendo: sudo systemctl status k3s"
  echo "2. Que KUBECONFIG es correcto: echo \$KUBECONFIG"
  echo "3. Que tienes acceso de lectura: ls -la \$KUBECONFIG"
  exit 1
fi
echo -e "${GREEN}✓ Cluster Kubernetes accesible${NC}"
echo "::endgroup::"

echo "::group::Comprobando directorio de salida"
if [ ! -d "${OUT_DIR}" ]; then
  mkdir -p "${OUT_DIR}"
  echo -e "${GREEN}✓ Directorio creado: ${OUT_DIR}${NC}"
else
  echo -e "${GREEN}✓ Directorio ya existe: ${OUT_DIR}${NC}"
fi
echo "::endgroup::"

echo "::group::Validando variables de entorno"
if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
  echo -e "${RED}✗ ERROR: Variable de entorno GRAFANA_ADMIN_PASSWORD no configurada${NC}"
  echo ""
  echo "Solución: Exporta la variable antes de ejecutar este script:"
  echo "  export GRAFANA_ADMIN_PASSWORD='tu-contraseña-segura'"
  echo ""
  echo "O pásala como variable de entorno:"
  echo "  GRAFANA_ADMIN_PASSWORD='tu-contraseña-segura' $0"
  exit 1
fi
echo -e "${GREEN}✓ GRAFANA_ADMIN_PASSWORD configurada${NC}"
echo "::endgroup::"

echo "::group::Verificando dependencias"

# Instalar htpasswd si falta
if ! command -v htpasswd &> /dev/null; then
  echo -e "${YELLOW}[!] htpasswd no encontrado. Instalando...${NC}"
  if ! sudo apt-get update && sudo apt-get install -y apache2-utils; then
    echo -e "${RED}✗ ERROR: No se pudo instalar apache2-utils${NC}"
    exit 1
  fi
fi
echo -e "${GREEN}✓ htpasswd disponible${NC}"

# Instalar yq si falta
if ! command -v yq &> /dev/null; then
  echo -e "${YELLOW}[!] yq no encontrado. Instalando...${NC}"
  if ! sudo curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq; then
    echo -e "${RED}✗ ERROR: No se pudo descargar yq${NC}"
    exit 1
  fi
  if ! sudo chmod +x /usr/local/bin/yq; then
    echo -e "${RED}✗ ERROR: No se pudo hacer ejecutable yq${NC}"
    exit 1
  fi
fi
echo -e "${GREEN}✓ yq disponible${NC}"

# Instalar jq si falta
if ! command -v jq &> /dev/null; then
  echo -e "${YELLOW}[!] jq no encontrado. Instalando...${NC}"
  if ! sudo apt-get update && sudo apt-get install -y jq; then
    echo -e "${RED}✗ ERROR: No se pudo instalar jq${NC}"
    exit 1
  fi
fi
echo -e "${GREEN}✓ jq disponible${NC}"

# Instalar kubeseal si falta
if ! command -v kubeseal &> /dev/null; then
  echo -e "${YELLOW}[!] kubeseal no encontrado. Instalando...${NC}"
  KUBESEAL_TMP=$(mktemp -d)
  trap "rm -rf $KUBESEAL_TMP" EXIT
  
  # Intentar con wget primero
  if ! wget -qO - https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz 2>/dev/null | tar xfz - -C "$KUBESEAL_TMP"; then
    # Fallback a curl si wget falla
    if ! curl -fsSL https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz 2>/dev/null | tar xfz - -C "$KUBESEAL_TMP"; then
      echo -e "${RED}✗ ERROR: No se pudo descargar kubeseal (wget y curl fallaron)${NC}"
      exit 1
    fi
  fi
  
  if ! sudo mv "$KUBESEAL_TMP/kubeseal" /usr/local/bin/; then
    echo -e "${RED}✗ ERROR: No se pudo mover kubeseal a /usr/local/bin${NC}"
    exit 1
  fi
  
  if ! sudo chmod +x /usr/local/bin/kubeseal; then
    echo -e "${RED}✗ ERROR: No se pudo hacer ejecutable kubeseal${NC}"
    exit 1
  fi
fi
echo -e "${GREEN}✓ kubeseal disponible${NC}"
echo "::endgroup::"

echo "::group::Generando hash bcrypt para Grafana"
# Generar hash bcrypt de la contraseña usando htpasswd
# htpasswd genera un hash en formato bcrypt que Grafana entiende
htpasswd_hash=$(htpasswd -bnBC 10 "" "$GRAFANA_ADMIN_PASSWORD" | tr -d ':\n')
echo "✓ Hash bcrypt generado para contraseña de admin"
echo "::endgroup::"

echo "::group::Creando Secret local"

# Crear el Secret de Grafana con las credenciales
cat <<EOF > "${OUT_DIR}/${SECRET_NAME}.raw.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: grafana
    meta.helm.sh/release-namespace: monitoring
    argocd.argoproj.io/sync-wave: "0"
type: Opaque
data:
  admin-password: $(echo -n "$GRAFANA_ADMIN_PASSWORD" | base64 -w0)
  admin-user: $(echo -n "admin" | base64 -w0)
EOF

echo "✓ Secret creado en ${OUT_DIR}/${SECRET_NAME}.raw.yaml"
echo "::endgroup::"

echo "::group::Sellando Secret con kubeseal"

# Verificar que el certificado existe y es válido
if [ ! -f "$CERT_PATH" ]; then
  echo "[✗] ERROR: Certificado no encontrado en $CERT_PATH"
  echo "    Comprueba que el archivo .pem existe en la ruta especificada"
  exit 1
fi

# Verificar que el archivo tiene contenido
if [ ! -s "$CERT_PATH" ]; then
  echo "[✗] ERROR: Certificado vacío en $CERT_PATH"
  echo "    El archivo existe pero no tiene contenido"
  exit 1
fi

# Verificar que el certificado es válido X509
if ! openssl x509 -in "$CERT_PATH" -noout &>/dev/null; then
  echo "[✗] ERROR: Certificado inválido en $CERT_PATH"
  echo "    El archivo existe pero no es un certificado X509 válido"
  echo ""
  echo "    Intenta:"
  echo "    1. Verificar con: openssl x509 -in \"$CERT_PATH\" -text -noout"
  echo "    2. O descargar nuevo: FETCH_CERT=true $0"
  exit 1
fi

echo "[i] Certificado validado correctamente"
echo ""

# Ejecutar kubeseal para sellar el Secret
if ! kubeseal \
  --cert "$CERT_PATH" \
  --format yaml \
  --scope strict \
  < "${OUT_DIR}/${SECRET_NAME}.raw.yaml" \
  > "${OUT_DIR}/${SECRET_NAME}.yaml" 2>/tmp/kubeseal.err; then
  
  echo "[✗] ERROR: kubeseal falló al sellar el secreto"
  echo ""
  echo "Detalles del error:"
  cat /tmp/kubeseal.err
  echo ""
  echo "Debug: Contenido del Secret raw:"
  head -20 "${OUT_DIR}/${SECRET_NAME}.raw.yaml"
  
  exit 1
fi

# Eliminar archivo de error
rm -f /tmp/kubeseal.err

# Validar que el archivo sellado se generó y tiene contenido
if [ ! -s "${OUT_DIR}/${SECRET_NAME}.yaml" ]; then
  echo "[✗] ERROR: El archivo sellado está vacío o no fue creado"
  exit 1
fi

# Validar que es YAML válido
if ! yq eval '.' "${OUT_DIR}/${SECRET_NAME}.yaml" > /dev/null 2>&1; then
  echo "[✗] ERROR: El archivo sellado no es YAML válido"
  echo "Contenido:"
  cat "${OUT_DIR}/${SECRET_NAME}.yaml"
  exit 1
fi

# Validar estructura de SealedSecret
if ! yq eval '.kind' "${OUT_DIR}/${SECRET_NAME}.yaml" 2>/dev/null | grep -q "SealedSecret"; then
  echo "[✗] ERROR: El archivo no contiene un SealedSecret válido"
  echo "Kind encontrado:"
  yq eval '.kind' "${OUT_DIR}/${SECRET_NAME}.yaml" || echo "No hay kind definido"
  echo ""
  echo "Contenido completo:"
  cat "${OUT_DIR}/${SECRET_NAME}.yaml"
  exit 1
fi

echo "[✓] SealedSecret válido generado"
echo "✓ Secret sellado en ${OUT_DIR}/${SECRET_NAME}.yaml"
echo "::endgroup::"

echo "::group::Limpieza"
rm -f "${OUT_DIR}/${SECRET_NAME}.raw.yaml"
echo "✓ Archivo raw eliminado"
echo "::endgroup::"

echo "::group::Git operations"

# Configurar git
git config user.name "github-actions[bot]" 2>/dev/null || true
git config user.email "github-actions[bot]@users.noreply.github.com" 2>/dev/null || true

# Agregar el secreto sellado
git add "${OUT_DIR}/${SECRET_NAME}.yaml"

# IMPORTANTE: Siempre agregar el certificado si existe
if [ -f "$CERT_PATH" ]; then
  echo "[i] Certificado detectado - incluyendo en git"
  git add "$CERT_PATH"
  CERT_INCLUDED="true"
else
  CERT_INCLUDED="false"
fi

# Crear commit si hay cambios
if ! git diff --cached --quiet; then
  # Determinar mensaje del commit
  if [ "$CERT_INCLUDED" = "true" ] && [ "$FETCH_CERT" = "true" ]; then
    COMMIT_MSG="chore: update Grafana sealed secret and cluster certificate"
  elif [ "$CERT_INCLUDED" = "true" ]; then
    COMMIT_MSG="chore: update Grafana sealed secret with temporary certificate"
  else
    COMMIT_MSG="chore: update Grafana sealed secret"
  fi
  
  git commit -m "$COMMIT_MSG"
  
  # Hacer push
  if git push origin $(git rev-parse --abbrev-ref HEAD); then
    echo "✓ Commit y push realizados"
  else
    echo "[!] Push falló (podría estar en CI sin permisos)"
  fi
else
  echo "[!] Sin cambios para hacer commit"
fi

echo "::endgroup::"

echo ""
echo "════════════════════════════════════════════════"
echo "[✓] Secreto sellado de Grafana generado correctamente"
echo ""
echo "Archivos actualizados:"
echo "  📄 infra/grafana/sealed-secrets/grafana-admin.yaml"
if [ "$CERT_INCLUDED" = "true" ]; then
  if [ "$FETCH_CERT" = "true" ]; then
    echo "  📄 $CERT_PATH (✓ Descargado del cluster)"
  else
    echo "  📄 $CERT_PATH (⚠️  Temporal - regenerar con FETCH_CERT=true)"
  fi
fi
echo ""
echo "🚀 Próximos pasos:"
if [ "$FETCH_CERT" != "true" ] && [ "$CERT_INCLUDED" = "true" ]; then
  echo "  • ⚠️  Se usó certificado temporal (no es del cluster real)"
  echo "  • Después de instalar sealed-secrets en el cluster:"
  echo "    $ FETCH_CERT=true GRAFANA_ADMIN_PASSWORD='tu-contraseña' $0"
  echo "  • Esto reemplazará el certificado con el del cluster real"
fi
echo "  • Secreto listo para ser aplicado al cluster"
echo "  • El namespace 'grafana' será creado automáticamente al desplegar"
echo "════════════════════════════════════════════════"

# Aplicar el secret al cluster si es entorno local y kubectl está disponible
echo ""
echo "::group::Aplicando SealedSecret al cluster"

if [ "$CI_ENVIRONMENT" = "true" ]; then
  echo "[i] En CI: El SealedSecret será aplicado por ArgoCD"
  echo "    (No aplicar automáticamente en GitHub Actions)"
else
  # En entorno local, intentar aplicar si kubectl está disponible
  if command -v kubectl &> /dev/null; then
    echo "[i] kubectl disponible, intentando aplicar SealedSecret..."
    
    if kubectl apply -f "${OUT_DIR}/${SECRET_NAME}.yaml"; then
      echo "✓ SealedSecret aplicado correctamente al cluster"
      
      # Verificar que se desselló
      if kubectl get secret grafana-admin -n monitoring &>/dev/null 2>&1; then
        echo "✓ Secret desellado correctamente en namespace 'monitoring'"
        echo "  Puedes verificar con: kubectl get secret grafana-admin -n monitoring"
      else
        echo "[!] Secret aún no aparece (sealed-secrets podría estar procesando)"
      fi
    else
      echo "[!] No se pudo aplicar el SealedSecret"
      echo "    Aplícalo manualmente con:"
      echo "    kubectl apply -f ${OUT_DIR}/${SECRET_NAME}.yaml"
    fi
  else
    echo "[!] kubectl no está disponible"
    echo "    Aplica manualmente el SealedSecret con:"
    echo "    kubectl apply -f ${OUT_DIR}/${SECRET_NAME}.yaml"
  fi
fi

echo "::endgroup::"
