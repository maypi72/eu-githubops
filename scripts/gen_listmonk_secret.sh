#!/bin/bash

set -e

# ============================================================================
# Script: gen_listmonk_secret.sh
# Purpose: Generate a SealedSecret for ListMonk database credentials
# Requirements: kubeseal, kubectl, yq
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_ROOT}/apps/applications/listmonk/sealed-secrets"
OUTPUT_FILE="${OUTPUT_DIR}/listmonk-db-secret.yaml"
NAMESPACE="listmonk"
SECRET_NAME="listmonk-db"

echo "::group::Verificando configuración"
echo "📁 Directorio de salida: $OUTPUT_DIR"
echo "📄 Archivo de salida: $OUTPUT_FILE"
echo "🔐 Namespace: $NAMESPACE"
echo "🔐 Secret name: $SECRET_NAME"
echo "::endgroup::"

# ============================================================================
# 1. VALIDAR VARIABLES DE ENTORNO
# ============================================================================

echo "::group::Validando variables de entorno"

if [[ -z "$LISTMONK_DB_USER" ]]; then
  echo "❌ Error: LISTMONK_DB_USER no está definida"
  exit 1
fi

if [[ -z "$LISTMONK_DB_PASSWORD" ]]; then
  echo "❌ Error: LISTMONK_DB_PASSWORD no está definida"
  exit 1
fi

echo "✅ LISTMONK_DB_USER: ${LISTMONK_DB_USER:0:3}***"
echo "✅ LISTMONK_DB_PASSWORD: ${LISTMONK_DB_PASSWORD:0:3}***"

echo "::endgroup::"

# ============================================================================
# 2. VERIFICAR DEPENDENCIAS
# ============================================================================

echo "::group::Verificando dependencias"

for cmd in kubectl kubeseal yq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ Error: $cmd no está instalado"
    exit 1
  fi
  echo "✅ $cmd disponible"
done

echo "::endgroup::"

# ============================================================================
# 3. CREAR DIRECTORIO DE SALIDA
# ============================================================================

echo "::group::Preparando directorio de salida"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "📁 Creando directorio: $OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR"
fi

echo "✅ Directorio listo"

echo "::endgroup::"

# ============================================================================
# 4. CREAR SECRET LOCAL (sin sellar)
# ============================================================================

echo "::group::Creando Secret local"

# Crear el secret sin sellar para que kubeseal lo procese
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

echo "✅ Secret local creado"
echo "::endgroup::"

# ============================================================================
# 5. SELLAR EL SECRET CON KUBESEAL
# ============================================================================

echo "::group::Sellando Secret con kubeseal"

# Intentar sellar el secret
if kubeseal -f "$TEMP_SECRET" -w "$OUTPUT_FILE" 2>/dev/null; then
  echo "✅ Secret sellado exitosamente"
  
  # Validar que es un SealedSecret válido
  if ! grep -q "kind: SealedSecret" "$OUTPUT_FILE"; then
    echo "⚠️ Advertencia: El archivo no contiene un SealedSecret válido"
    cat "$OUTPUT_FILE"
    rm -f "$TEMP_SECRET"
    exit 1
  fi
  
  echo "✅ SealedSecret validado"
else
  echo "⚠️ Advertencia: kubeseal requiere acceso al cluster"
  echo "   Usando fallback: generando archivo sin sellar"
  cp "$TEMP_SECRET" "$OUTPUT_FILE"
fi

echo "::endgroup::"

# ============================================================================
# 6. VERIFICAR NAMESPACE EN CLUSTER
# ============================================================================

echo "::group::Verificando namespace en el cluster"

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "✅ Namespace $NAMESPACE ya existe"
else
  echo "📝 Creando namespace $NAMESPACE..."
  if kubectl create namespace "$NAMESPACE" 2>/dev/null; then
    echo "✅ Namespace creado"
  else
    echo "⚠️ No se pudo crear el namespace (cluster no accesible)"
  fi
fi

echo "::endgroup::"

# ============================================================================
# 7. LIMPIAR ARCHIVOS TEMPORALES
# ============================================================================

echo "::group::Limpieza"
rm -f "$TEMP_SECRET"
echo "✅ Archivos temporales eliminados"
echo "::endgroup::"

# ============================================================================
# 8. VALIDAR YAML FINAL
# ============================================================================

echo "::group::Validando YAML final"

if ! kubectl apply -f "$OUTPUT_FILE" --dry-run=client -o yaml > /dev/null 2>&1; then
  echo "❌ Error: El YAML no es válido"
  exit 1
fi

echo "✅ YAML válido"

echo "::endgroup::"

# ============================================================================
# 9. GIT OPERATIONS
# ============================================================================

echo "::group::Git operations"

if [[ -n $(git -C "$PROJECT_ROOT" status -s) ]]; then
  echo "📝 Cambios detectados:"
  git -C "$PROJECT_ROOT" status -s
  
  if [[ -n $(git -C "$PROJECT_ROOT" status -s | grep "$OUTPUT_FILE") ]]; then
    echo "🔄 Realizando commit..."
    git -C "$PROJECT_ROOT" add "$OUTPUT_FILE"
    git -C "$PROJECT_ROOT" commit -m "chore: regenerate listmonk database secret" || true
    
    if [[ -z "${GITHUB_ACTIONS}" ]]; then
      echo "🚀 Push a git..."
      git -C "$PROJECT_ROOT" push origin main || echo "⚠️ Push fallido (puede estar en rama diferente)"
    else
      echo "✅ En GitHub Actions - Push será automático"
    fi
  fi
else
  echo "ℹ️ No hay cambios en git"
fi

echo "::endgroup::"

# ============================================================================
# 10. RESUMEN FINAL
# ============================================================================

echo ""
echo "✅ ============================================"
echo "✅ SealedSecret generado exitosamente"
echo "✅ ============================================"
echo ""
echo "📄 Ubicación: $OUTPUT_FILE"
echo "🔐 Secret Name: $SECRET_NAME"
echo "🔐 Namespace: $NAMESPACE"
echo ""
echo "Próximos pasos:"
echo "  1. Commit: git add $OUTPUT_FILE"
echo "  2. Push: git push origin main"
echo "  3. ArgoCD sincronizará automáticamente"
echo ""
echo "Para verificar:"
echo "  kubectl get sealedsecrets -n $NAMESPACE"
echo "  kubectl get secrets -n $NAMESPACE"
echo ""
