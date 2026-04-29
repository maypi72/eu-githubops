# Guía: Generación de LocalStack Secret Sellado

Este documento explica cómo usar el sistema de generación automática de secretos para LocalStack, siguiendo el mismo patrón que el sistema de secretos de Grafana.

## 📋 Descripción General

Se ha creado un sistema completo para generar y mantener credenciales AWS selladas para LocalStack:

- **Workflow de GitHub Actions**: `/.github/workflows/gen-localstack-secret.yml`
- **Script de Generación**: `/scripts/gen_localstack_secret.sh`
- **Salida**: `infra/localstack/sealed-secrets/localstack-credentials.yaml`

## 🔧 Requisitos Previos

### 1. Secrets en GitHub
Define estos secrets en tu repositorio (Settings > Secrets and variables > Actions):

```
AWS_ACCESS_KEY_ID          # Tu Access Key para AWS/LocalStack
AWS_SECRET_ACCESS_KEY      # Tu Secret Access Key para AWS/LocalStack
```

### 2. Herramientas Requeridas
El sistema necesita estas herramientas instaladas:

- `kubeseal` - Para sellar secretos
- `kubectl` - Para acceder al cluster
- `yq` - Para validar YAML
- `openssl` - Para validar certificados
- `base64` - Para codificar credenciales
- `git` - Para commits y pushes automáticos

En k3s generalmente vienen preinstaladas o disponibles.

### 3. Certificado de Sealed Secrets
El script necesita el certificado público de sealed-secrets. Hay varias formas de obtenerlo:

**Opción A: Automático desde el cluster (recomendado)**
```bash
FETCH_CERT=true AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..." \
  ./scripts/gen_localstack_secret.sh
```

**Opción B: Manual (si sealed-secrets está instalado)**
```bash
# Extraer certificado del cluster
kubeseal -f - --fetch-cert > infra/sealed-secrets/pub-cert.pem

# Luego ejecutar el script
AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..." \
  ./scripts/gen_localstack_secret.sh
```

**Opción C: Usar certificado existente**
El script automáticamente usará `infra/sealed-secrets/pub-cert.pem` si existe.

## 🚀 Uso

### Opción 1: Usar el Workflow de GitHub Actions (recomendado)

1. **Ir a Actions** en tu repositorio GitHub
2. **Seleccionar**: "Generate LocalStack Secret" workflow
3. **Click**: "Run workflow"
4. **Configurar** (opcional):
   - `fetch_cert`: Marcar si necesitas descargar certificado del cluster
5. **Click**: "Run workflow"

El workflow automáticamente:
- ✓ Obtiene credenciales de GitHub Secrets
- ✓ Descarga kubeconfig si está disponible
- ✓ Genera el SealedSecret
- ✓ Valida el YAML
- ✓ Hace commit automático a git
- ✓ Pushea a la rama principal

### Opción 2: Ejecutar Localmente

```bash
# Con certificado existente
AWS_ACCESS_KEY_ID="your-access-key" \
AWS_SECRET_ACCESS_KEY="your-secret-key" \
./scripts/gen_localstack_secret.sh

# O descargar certificado del cluster
AWS_ACCESS_KEY_ID="your-access-key" \
AWS_SECRET_ACCESS_KEY="your-secret-key" \
FETCH_CERT=true \
./scripts/gen_localstack_secret.sh
```

## 📂 Estructura de Archivos

```
.github/workflows/
├── gen-localstack-secret.yml     ← Workflow de GitHub Actions
└── gen-grafana-secret.yml        ← Patrón de referencia

scripts/
├── gen_localstack_secret.sh      ← Script principal
├── gen_grafana_secret.sh         ← Patrón de referencia
└── ...

infra/
├── sealed-secrets/
│   └── pub-cert.pem              ← Certificado público (generado/descargado)
└── localstack/
    └── sealed-secrets/
        ├── .gitkeep              ← Marcador para git
        └── localstack-credentials.yaml  ← SealedSecret generado
```

## 🔐 Cómo Funciona

### 1. Obtención de Credenciales
Las credenciales vienen de GitHub Secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### 2. Creación del Secret
Se crea un Secret de Kubernetes con los datos:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: localstack-credentials
  namespace: localstack
type: Opaque
data:
  AWS_ACCESS_KEY_ID: <base64 encoded>
  AWS_SECRET_ACCESS_KEY: <base64 encoded>
```

### 3. Sellado con kubeseal
El Secret se sella con kubeseal:
```bash
kubeseal -f - --scope strict -n localstack > localstack-credentials.yaml
```

### 4. Validación
Se valida:
- ✓ YAML es válido
- ✓ Tiene apiVersion correcto
- ✓ Tiene kind: SealedSecret
- ✓ Certificado es válido

### 5. Commit Automático
Se hace commit y push automáticamente:
```bash
git add infra/localstack/sealed-secrets/
git commit -m "chore: update localstack credentials"
git push
```

## 📤 Despliegue en el Cluster

Una vez que el SealedSecret está en git, ArgoCD lo sincronizará automáticamente:

1. **ArgoCD** sincroniza desde git
2. **Sealed Secrets Controller** desella el SealedSecret
3. **Secret desellado** está disponible en el namespace `localstack`
4. **LocalStack** puede acceder a las credenciales

Verificar sincronización:
```bash
# Ver si el SealedSecret está en el cluster
kubectl get sealedsecrets -n localstack

# Ver si fue sellado correctamente
kubectl get secrets -n localstack
kubectl describe secret localstack-credentials -n localstack
```

## 🐛 Solución de Problemas

### Error: "kubeseal: command not found"
```bash
# Instalar kubeseal
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Error: "Certificado no encontrado"
```bash
# Opción A: Descargar desde cluster
FETCH_CERT=true AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..." \
  ./scripts/gen_localstack_secret.sh

# Opción B: Generar certificado temporal (si sealed-secrets no está instalado)
# El script lo creará automáticamente
```

### Error: "Secret no sincronizado en el cluster"
```bash
# Verificar que sealed-secrets está instalado
kubectl get pods -n kube-system | grep sealed-secrets

# Verificar logs del controller
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets -f

# Verificar que ArgoCD está sincronizando
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f
```

### Error: "Certificado inválido o expirado"
```bash
# Verificar fecha de expiración
openssl x509 -in infra/sealed-secrets/pub-cert.pem -noout -enddate

# Si está expirado, eliminar y regenerar
rm -f infra/sealed-secrets/pub-cert.pem
FETCH_CERT=true AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..." \
  ./scripts/gen_localstack_secret.sh
```

## 🔄 Actualizar Credenciales

Si necesitas cambiar las credenciales AWS de LocalStack:

1. **Actualizar GitHub Secrets**:
   - Settings > Secrets and variables > Actions
   - Editar `AWS_ACCESS_KEY_ID`
   - Editar `AWS_SECRET_ACCESS_KEY`

2. **Generar nuevo SealedSecret**:
   - Ejecutar el workflow nuevamente
   - O ejecutar el script localmente

3. **ArgoCD sincronizará automáticamente**:
   - El SealedSecret será actualizado
   - Sealed Secrets lo desellará
   - LocalStack usará las nuevas credenciales

## 📋 Pasos de Implementación Completa

### Primera vez:

1. **Agregar GitHub Secrets**:
   ```
   Settings > Secrets and variables > Actions
   - AWS_ACCESS_KEY_ID: <tu-access-key>
   - AWS_SECRET_ACCESS_KEY: <tu-secret-key>
   ```

2. **Ejecutar Workflow**:
   - GitHub Actions > "Generate LocalStack Secret"
   - "Run workflow" con fetch_cert=true (si sealed-secrets está instalado)

3. **Verificar en cluster**:
   ```bash
   kubectl get sealedsecrets -n localstack
   kubectl get secrets -n localstack
   ```

4. **Usar en LocalStack**:
   - LocalStack app/chart debe referenciar el secret
   - Las credenciales se inyectarán automáticamente

### Actualizaciones futuras:

1. **Cambiar credenciales**: Actualizar GitHub Secrets
2. **Generar nuevo secret**: Ejecutar workflow
3. **Sincronización automática**: ArgoCD actualiza el cluster

## ✅ Validación de Éxito

El proceso es exitoso cuando:

- ✓ El workflow termina sin errores
- ✓ El archivo `infra/localstack/sealed-secrets/localstack-credentials.yaml` existe
- ✓ El YAML del SealedSecret es válido: `yq eval '.' infra/localstack/sealed-secrets/localstack-credentials.yaml`
- ✓ El commit fue realizado automáticamente en git
- ✓ En el cluster: `kubectl get sealedsecrets -n localstack` muestra el secret
- ✓ En el cluster: `kubectl get secrets -n localstack` muestra el secret desellado

## 📚 Referencias

- [gen-localstack-secret.yml](.github/workflows/gen-localstack-secret.yml) - Workflow completo
- [gen_localstack_secret.sh](scripts/gen_localstack_secret.sh) - Script de generación
- [LOCALSTACK_GUIDE.md](LOCALSTACK_GUIDE.md) - Guía general de LocalStack
- [gen-grafana-secret.yml](.github/workflows/gen-grafana-secret.yml) - Patrón de referencia
