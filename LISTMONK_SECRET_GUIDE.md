#!/bin/bash

# Este archivo documenta cómo usar el sistema de secretos para ListMonk

# ============================================================================
# SETUP INICIAL - Crear GitHub Actions Secrets
# ============================================================================

# 1. Ve a tu repositorio en GitHub
# 2. Settings → Secrets and variables → Actions
# 3. Crea estos secrets:

# Secret 1: LISTMONK_DB_USER
# Valor: dbuser

# Secret 2: LISTMONK_DB_PASSWORD
# Valor: dbpassword (o una contraseña segura)

# ============================================================================
# GENERAR EL SEALEDSECRET
# ============================================================================

# Opción 1: Manual (desde tu máquina)
# ========================================

export LISTMONK_DB_USER="dbuser"
export LISTMONK_DB_PASSWORD="dbpassword"
bash scripts/gen_listmonk_secret.sh

# Resultado: apps/applications/listmonk/sealed-secrets/listmonk-db-secret.yaml

# ============================================================================

# Opción 2: Automático via GitHub Actions
# ========================================

# Ir a: Actions → Generate ListMonk Secret
# Hacer click en "Run workflow"
# Seleccionar "fetch_cert" si necesitas descargar el certificado del cluster
# Click "Run workflow"

# ============================================================================
# VERIFICAR EL SECRETO
# ============================================================================

# Ver el SealedSecret:
kubectl get sealedsecrets -n listmonk

# Ver el Secret desellado (solo funciona en el cluster):
kubectl get secrets -n listmonk listmonk-db -o yaml

# Ver los valores:
kubectl get secret listmonk-db -n listmonk -o jsonpath='{.data.user}' | base64 -d
kubectl get secret listmonk-db -n listmonk -o jsonpath='{.data.password}' | base64 -d

# ============================================================================
# ESTRUCTURA DE ARCHIVOS
# ============================================================================

# apps/applications/listmonk/
# ├── application.yaml
# ├── rollout.yaml
# ├── service.yaml
# ├── service-preview.yaml
# ├── ingress.yaml
# ├── analysis.yaml
# └── sealed-secrets/
#     └── listmonk-db-secret.yaml  ← SealedSecret generado aquí

# ============================================================================
# CÓMO FUNCIONA
# ============================================================================

# 1. El script gen_listmonk_secret.sh:
#    • Lee LISTMONK_DB_USER y LISTMONK_DB_PASSWORD
#    • Crea un Secret local
#    • Lo sella con kubeseal usando el certificado del cluster
#    • Lo guarda en sealed-secrets/listmonk-db-secret.yaml

# 2. ArgoCD:
#    • Detecta el cambio en git
#    • Sincroniza el SealedSecret
#    • El controlador sealed-secrets lo desella automáticamente
#    • Crea un Secret desencriptado en el cluster

# 3. ListMonk:
#    • El Rollout monta el Secret como variables de entorno
#    • Usa LISTMONK_db__user y LISTMONK_db__password para conectarse

# ============================================================================
# TROUBLESHOOTING
# ============================================================================

# ❌ "Failed to unseal secret"
# → El certificado de sealed-secrets cambió
# → Solución: Ejecutar con --fetch_cert=true

# ❌ "Secret not found"
# → El namespace no existe
# → Solución: kubectl create namespace listmonk

# ❌ "kubeseal: command not found"
# → kubeseal no está instalado
# → Solución: sudo apt install kubeseal

# ============================================================================
