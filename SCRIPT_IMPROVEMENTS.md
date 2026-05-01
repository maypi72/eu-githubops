# Recomendaciones de Mejora - gen_argocd_secret.sh

## Compatibilidad con Cambios en bootstrap-argocd.sh

### 1. Cambios Detectados en bootstrap-argocd.sh
El nuevo `bootstrap-argocd.sh` tiene varias mejoras importantes:
- ✅ Mejor manejo de KUBECONFIG (múltiples rutas)
- ✅ Colores ANSI en outputs
- ✅ Mejor gestión de reintentos con retry()
- ✅ Validaciones más robustas de recursos

### 2. Cambios Recomendados para gen_argocd_secret.sh

#### A. Mejorar Manejo de KUBECONFIG (CRÍTICO)
**Problema:** El script no verifica KUBECONFIG antes de ejecutar kubectl
**Solución:** Agregar lógica similar a bootstrap-argocd.sh

```bash
# Agregar al inicio del script:
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
    echo "[✓] KUBECONFIG encontrado: $KUBECONFIG"
    KUBECONFIG_FOUND=true
    break
  fi
done

if [ "$KUBECONFIG_FOUND" = false ]; then
  echo "[✗] ERROR: No se encontró KUBECONFIG"
  echo "Se buscó en:"
  for kb_path in "${KUBECONFIG_PATHS[@]}"; do
    echo "  - $kb_path"
  done
  exit 1
fi
```

#### B. Usar Función retry() Consistente
**Problema:** Los comandos usan timeout directo sin reintentos sistemáticos
**Solución:** Usar la misma función retry() que bootstrap-argocd.sh

```bash
# Reemplazar:
if timeout 10 kubeseal --fetch-cert ...

# Por:
if retry timeout 10 kubeseal --fetch-cert ...
```

#### C. Mejorar Mensaje de Variables de Entorno Faltantes
**Problema:** El mensaje es genérico
**Solución:** Proporcionar instrucciones claras de cómo configurar

```bash
# Reemplazar:
if [ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]; then
  echo "ERROR: Debes exportar ARGOCD_ADMIN_PASSWORD"
  exit 1
fi

# Por:
if [ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]; then
  echo "[✗] ERROR: Variable de entorno ARGOCD_ADMIN_PASSWORD no configurada"
  echo ""
  echo "Solución: Exporta la variable antes de ejecutar este script:"
  echo "  export ARGOCD_ADMIN_PASSWORD='tu-contraseña-segura'"
  echo ""
  echo "O pásala como variable de entorno:"
  echo "  ARGOCD_ADMIN_PASSWORD='tu-contraseña-segura' $0"
  exit 1
fi
```

#### D. Mejorar Validación de Dependencias
**Problema:** Las validaciones no son consistentes
**Solución:** Crear función helper para validar herramientas

```bash
check_command() {
  local cmd="$1"
  local install_cmd="$2"
  
  if ! command -v "$cmd" &>/dev/null; then
    echo "[!] $cmd no encontrado. Instalando..."
    if [ -n "$install_cmd" ]; then
      eval "$install_cmd" || {
        echo "[✗] ERROR: No se pudo instalar $cmd"
        return 1
      }
    fi
  fi
  echo "[✓] $cmd disponible"
  return 0
}

# Uso:
check_command "htpasswd" "sudo apt-get update && sudo apt-get install -y apache2-utils" || exit 1
check_command "yq" "sudo curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq" || exit 1
```

#### E. Agregar Colores Consistentes
**Problema:** Inconsistencia con bootstrap-argocd.sh
**Solución:** Usar las mismas variables de color

```bash
# Agregar al inicio:
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Reemplazar prints:
echo "✓ Certificado descargado"
# Por:
echo -e "${GREEN}✓ Certificado descargado${NC}"

echo "ERROR: Certificado no encontrado"
# Por:
echo -e "${RED}✗ ERROR: Certificado no encontrado${NC}"
```

#### F. Mejorar Manejo de Errores en Instalación de Herramientas
**Problema:** Si wget falla, no hay fallback a curl
**Solución:** Agregar fallback alternativo

```bash
# Reemplazar:
if ! wget -qO - https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz | tar xfz - -C "$KUBESEAL_TMP"; then
  echo "ERROR: No se pudo descargar e instalar kubeseal"
  exit 1
fi

# Por:
if ! wget -qO - https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz | tar xfz - -C "$KUBESEAL_TMP" 2>/dev/null; then
  if ! curl -fsSL https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz | tar xfz - -C "$KUBESEAL_TMP"; then
    echo -e "${RED}✗ ERROR: No se pudo descargar kubeseal${NC}"
    exit 1
  fi
fi
```

#### G. Agregar Validación de Conectividad al Cluster
**Problema:** No valida que kubectl pueda conectar al cluster
**Solución:** Agregar check similar a bootstrap-argocd.sh

```bash
# Agregar en sección de validación:
echo "::group::Validando conectividad al cluster"
if ! retry kubectl cluster-info >/dev/null 2>&1; then
  echo -e "${RED}✗ ERROR: No se puede conectar al cluster${NC}"
  echo ""
  echo "Verifica:"
  echo "1. Que K3s está corriendo: sudo systemctl status k3s"
  echo "2. Que KUBECONFIG es correcto: echo \$KUBECONFIG"
  exit 1
fi
echo -e "${GREEN}✓ Cluster Kubernetes accesible${NC}"
echo "::endgroup::"
```

#### H. Mejorar Mensajes de Logs Estructurados
**Problema:** Mezcla de estilos de output
**Solución:** Usar ::group:: de GitHub Actions consistentemente

```bash
# Todos los echo deberían estar dentro de grupos:
echo "::group::Grupo de operaciones"
echo "[✓] Paso 1"
echo "[✓] Paso 2"
echo "::endgroup::"
```

### 3. Problemas de Permisos Sudoers (Bloqueantes)

El script fallará sin estos permisos en sudoers:

```
❌ BLOQUEANTES:
- /usr/bin/curl (línea 288) - Descarga yq
- /bin/chmod (línea 292) - Hace ejecutable yq  
- /bin/mv (línea 308) - Instala kubeseal
- /usr/bin/curl (en mv) (línea 308) - Descarga kubeseal

✅ YA PERMITIDOS:
- /usr/bin/apt-get (instalación de apache2-utils y jq)
```

### 4. Recomendación Final de Orden de Ejecución

Para que todo funcione correctamente en GitHub Actions:

```bash
# 1. Primero ejecutar bootstrap scripts en orden:
./infra/bootstrap/bootstrap_k3s.sh              # Instala K3s
./infra/bootstrap/bootstrap_helm.sh             # Instala Helm
./infra/bootstrap/bootstrap_sealed_secrets.sh   # Instala Sealed Secrets

# 2. Luego ejecutar script de secrets:
export ARGOCD_ADMIN_PASSWORD="tu-password"
./scripts/gen_argocd_secret.sh
```

### 5. Script de Validación Sugerido

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Validando que todo está listo para gen_argocd_secret.sh..."
echo ""

# Verificar KUBECONFIG
if [ -z "${KUBECONFIG:-}" ] || [ ! -f "$KUBECONFIG" ]; then
  echo "✗ KUBECONFIG no configurado o no existe"
  exit 1
fi
echo "✓ KUBECONFIG: $KUBECONFIG"

# Verificar kubectl
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "✗ No se puede conectar al cluster"
  exit 1
fi
echo "✓ Kubectl conecta al cluster"

# Verificar sealed-secrets
if ! kubectl get namespace kube-system >/dev/null 2>&1; then
  echo "✗ Namespace kube-system no accesible"
  exit 1
fi
if ! kubectl get deploy sealed-secrets -n kube-system >/dev/null 2>&1; then
  echo "⚠ Sealed Secrets no está instalado - será generado certificado temporal"
else
  echo "✓ Sealed Secrets disponible"
fi

# Verificar variable ARGOCD_ADMIN_PASSWORD
if [ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]; then
  echo "✗ ARGOCD_ADMIN_PASSWORD no configurada"
  exit 1
fi
echo "✓ ARGOCD_ADMIN_PASSWORD configurada"

echo ""
echo "✓ Todo validado - listo para ejecutar gen_argocd_secret.sh"
```

## Resumen Ejecutivo

| Aspecto | Estado | Acción |
|--------|--------|--------|
| **Permisos Sudoers** | ❌ Crítico | Agregar /usr/bin/curl, /bin/chmod, /bin/mv |
| **KUBECONFIG** | ⚠️ Mejorable | Agregar lógica de búsqueda multi-ruta |
| **Colores/Output** | ⚠️ Inconsistente | Alinear con bootstrap-argocd.sh |
| **Reintentos** | ⚠️ Ad-hoc | Usar función retry() consistente |
| **Validación Cluster** | ❌ Falta | Agregar check de conectividad |
| **Mensajes de Error** | ⚠️ Genéricos | Mejorar instrucciones |

