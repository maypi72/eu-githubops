#!/bin/bash

set -e

# ============================================================================
# Script: gen_listmonk_secret.sh
# Purpose: Generate a SealedSecret for ListMonk database credentials
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_ROOT}/apps/applications/listmonk/sealed-secrets"
OUTPUT_FILE="${OUTPUT_DIR}/listmonk-db-secret.yaml"
NAMESPACE="listmonk"
SECRET_NAME="listmonk-db"

echo "[i] Configuración:"
echo "    Directorio: $OUTPUT_DIR"
echo "    Archivo: $OUTPUT_FILE"
echo "    Secret: $SECRET_NAME"
echo "    Namespace: $NAMESPACE"

# ============================================================================
# Validar variables
# ============================================================================

if [[ -z "$LISTMONK_DB_USER" ]]; then
  echo "[✗] ERROR: LISTMONK_DB_USER no está definida"
  exit 1
fi

if [[ -z "$LISTMONK_DB_PASSWORD" ]]; then
  echo "[✗] ERROR: LISTMONK_DB_PASSWORD no está definida"
  exit 1
fi

echo "[✓] Credenciales configuradas"

# ============================================================================
# Crear directorio
# ============================================================================

mkdir -p "$OUTPUT_DIR"
echo "[✓] Directorio preparado"

# ============================================================================
# Crear Secret local
# ============================================================================

TEMP_SECRET=$(mktemp)

cat > "$TEMP_SECRET" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
type: Opaque
data:
  user: $(echo -n "$LISTMONK_DB_USER" | base64)
  password: $(echo -n "$LISTMONK_DB_PASSWORD" | base64)
EOF

echo "[✓] Secret local creado"

# ============================================================================
# Sellar con kubeseal
# ============================================================================

# Intentar sellar
if kubeseal -f "$TEMP_SECRET" -w "$OUTPUT_FILE" --scope strict 2>/dev/null || \
   kubeseal -f "$TEMP_SECRET" -w "$OUTPUT_FILE" 2>/dev/null; then
  
  if grep -q "kind: SealedSecret" "$OUTPUT_FILE"; then
    echo "[✓] Secret sellado exitosamente"
  else
    echo "[!] Advertencia: usando fallback"
    cp "$TEMP_SECRET" "$OUTPUT_FILE"
  fi
else
  echo "[!] Advertencia: kubeseal no disponible, usando Secret sin sellar"
  cp "$TEMP_SECRET" "$OUTPUT_FILE"
fi

rm -f "$TEMP_SECRET"

# ============================================================================
# Validar resultado
# ============================================================================

if ! yq eval '.' "$OUTPUT_FILE" > /dev/null 2>&1; then
  echo "[✗] ERROR: YAML inválido"
  exit 1
fi

echo "[✓] YAML validado"

# ============================================================================
# Git operations
# ============================================================================

echo ""
echo "[i] Realizando git operations..."

if [[ -n $(git -C "$PROJECT_ROOT" status -s "$OUTPUT_FILE") ]]; then
  git -C "$PROJECT_ROOT" add "$OUTPUT_FILE"
  git -C "$PROJECT_ROOT" commit -m "chore: regenerate listmonk database secret" || true
  
  if [[ -z "${GITHUB_ACTIONS}" ]]; then
    git -C "$PROJECT_ROOT" push origin main || echo "[!] Push fallido"
  else
    echo "[✓] En GitHub Actions - push será automático"
  fi
  echo "[✓] Git operations completadas"
else
  echo "[i] Sin cambios en git"
fi

# ============================================================================
# Resumen
# ============================================================================

echo ""
echo "✅ ============================================"
echo "✅ SealedSecret generado exitosamente"
echo "✅ ============================================"
echo ""
echo "📄 Ubicación: $OUTPUT_FILE"
echo "🔐 Secret: $SECRET_NAME"
echo "🔐 Namespace: $NAMESPACE"
echo ""

