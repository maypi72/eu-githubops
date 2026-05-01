# Análisis de Permisos Sudoers para gha-runner

## Estado Actual
El usuario `gha-runner` tiene los siguientes permisos en `/etc/sudoers.d/gha-runner`:
```
gha-runner ALL=(ALL) NOPASSWD: \
  /usr/bin/apt, \
  /usr/bin/apt-get, \
  /usr/bin/dpkg, \
  /bin/systemctl, \
  /usr/local/bin/k3s*, \
  /usr/bin/kubectl, \
  /bin/mount, \
  /bin/umount, \
  /bin/bash
```

## Análisis de Scripts - Comandos que Requieren Sudo

### Scripts Identificados con Necesidad de Permisos Sudo

#### 1. `scripts/gen_argocd_secret.sh`
**Comandos encontrados:**
- ✅ `sudo apt-get` → YA PERMITIDO
- ❌ `sudo curl` → NO PERMITIDO (línea 288)
- ❌ `sudo chmod` → NO PERMITIDO (línea 292)
- ❌ `sudo mv` → NO PERMITIDO (línea 308)

**Ubicación de problemas:**
```bash
# Línea 288: Descarga yq
sudo curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq

# Línea 292: Hace ejecutable
sudo chmod +x /usr/local/bin/yq

# Línea 308: Mueve kubeseal
sudo mv "$KUBESEAL_TMP/kubeseal" /usr/local/bin/
sudo chmod +x /usr/local/bin/kubeseal
```

#### 2. `scripts/gen_grafana_secret.sh`
**Mismos problemas que gen_argocd_secret.sh:**
- ❌ `sudo curl` (línea 326)
- ❌ `sudo chmod` (línea 330)
- ❌ `sudo mv` (línea 350)

#### 3. `scripts/gen_localstack_secret.sh`
**Mismos problemas que gen_argocd_secret.sh:**
- ❌ `sudo curl` (línea 328)
- ❌ `sudo chmod` (línea 332)
- ❌ `sudo mv` (línea 345)

#### 4. `infra/bootstrap/bootstrap_k3s.sh`
**Comandos encontrados:**
- ❌ `sudo chmod` → NO PERMITIDO (línea 176)
- ❌ `sudo chown` → NO PERMITIDO (línea 177)

```bash
# Línea 176-177: Ajusta permisos del kubeconfig
sudo chmod 600 "$KUBECONFIG"
sudo chown "$(id -u):$(id -g)" "$KUBECONFIG" || true
```

#### 5. `infra/bootstrap/bootstrap_localstack.sh`
**Comandos encontrados:**
- ❌ `apt-key` → NO PERMITIDO (línea 354)
- ❌ `apt-add-repository` → NO PERMITIDO (línea 355)
- ✅ `apt-get` → YA PERMITIDO

## Permisos Faltantes Requeridos

### Críticos (Necesarios para que funcionen los scripts)

1. **`/usr/bin/curl`** - Descargar herramientas (yq, kubeseal)
   - Usado en: gen_argocd_secret.sh, gen_grafana_secret.sh, gen_localstack_secret.sh
   - Impacto: ALTO - Sin esto no se pueden descargar dependencias

2. **`/bin/chmod`** - Cambiar permisos de archivos ejecutables
   - Usado en: gen_argocd_secret.sh, gen_grafana_secret.sh, gen_localstack_secret.sh, bootstrap_k3s.sh
   - Impacto: ALTO - Sin esto no se puede hacer ejecutables los binarios

3. **`/bin/mv`** - Mover archivos a directorios de sistema
   - Usado en: gen_argocd_secret.sh, gen_grafana_secret.sh, gen_localstack_secret.sh
   - Impacto: ALTO - Sin esto no se pueden instalar binarios en /usr/local/bin/

4. **`/usr/bin/chown`** - Cambiar propietario de archivos
   - Usado en: bootstrap_k3s.sh
   - Impacto: MEDIO - Afecta la correcta configuración del kubeconfig

### Secundarios (Mejoran compatibilidad)

5. **`/usr/bin/apt-key`** - Gestionar claves GPG de repositorios
   - Usado en: bootstrap_localstack.sh
   - Impacto: BAJO-MEDIO - Solo necesario si se usan repositorios adicionales

6. **`/usr/bin/apt-add-repository`** - Agregar repositorios PPA
   - Usado en: bootstrap_localstack.sh
   - Impacto: BAJO-MEDIO - Solo necesario si se usan repositorios adicionales

7. **`/usr/bin/wget`** (Alternativa a curl)
   - Impacto: BAJO - Proporciona alternativa si curl falla

## Problemas Detectados

### Problema 1: Instalación de Binarios en /usr/local/bin/
El script intenta:
1. Descargar con `sudo curl` a /usr/local/bin/
2. Cambiar permisos con `sudo chmod`
3. Mover con `sudo mv`

**Sin los permisos:** Fallarán silenciosamente o con errores de permiso.

### Problema 2: Configuración de Kubeconfig
El script `bootstrap_k3s.sh` intenta:
1. Cambiar permisos a 600 con `sudo chmod`
2. Cambiar propietario con `sudo chown`

**Sin los permisos:** El kubeconfig no será accesible correctamente por kubectl.

### Problema 3: Gestión de Repositorios APT
Bootstrap_localstack.sh intenta agregar repositorios nuevos.

**Sin los permisos:** No se pueden instalar herramientas de repositorios no estándar como Terraform.

## Recomendaciones

### Opción 1: Restrictiva (Mínimo requerido)
Agregar estos permisos específicos:
```
gha-runner ALL=(ALL) NOPASSWD: \
  /usr/bin/curl, \
  /bin/chmod, \
  /bin/mv
```

### Opción 2: Moderada (Incluye alternativas)
```
gha-runner ALL=(ALL) NOPASSWD: \
  /usr/bin/curl, \
  /usr/bin/wget, \
  /bin/chmod, \
  /bin/mv, \
  /usr/bin/chown
```

### Opción 3: Completa (Todos los necesarios)
```
gha-runner ALL=(ALL) NOPASSWD: \
  /usr/bin/curl, \
  /usr/bin/wget, \
  /bin/chmod, \
  /bin/mv, \
  /usr/bin/chown, \
  /usr/bin/apt-key, \
  /usr/bin/apt-add-repository
```

## Paso a Paso para Actualizar Sudoers

```bash
# Editar sudoers de forma segura
sudo visudo -f /etc/sudoers.d/gha-runner

# Reemplazar la línea actual con (Opción 2 recomendada):
gha-runner ALL=(ALL) NOPASSWD: \
  /usr/bin/apt, \
  /usr/bin/apt-get, \
  /usr/bin/dpkg, \
  /bin/systemctl, \
  /usr/local/bin/k3s*, \
  /usr/bin/kubectl, \
  /bin/mount, \
  /bin/umount, \
  /bin/bash, \
  /usr/bin/curl, \
  /usr/bin/wget, \
  /bin/chmod, \
  /bin/mv, \
  /usr/bin/chown
```

## Verificación
```bash
# Verificar que sudoers es válido
sudo visudo -c -f /etc/sudoers.d/gha-runner

# Verificar permisos específicos
sudo -u gha-runner -l
```

## Seguridad
- ✅ Estos comandos son seguros con `NOPASSWD` en el contexto de un runner
- ✅ Solo aplican a herramientas necesarias para la automatización
- ✅ No se da acceso a shells sin restricciones (ya permitido /bin/bash)
- ✅ Los comandos están limitados a rutas específicas
