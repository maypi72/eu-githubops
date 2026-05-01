# Plan de Acción Inmediato

## 1️⃣ PASO URGENTE: Actualizar /etc/sudoers.d/gha-runner

El usuario `gha-runner` **NO PUEDE** ejecutar los scripts correctamente sin estos permisos.

### Comandos a ejecutar en el servidor (máquina con el runner):

```bash
# Verificar sudoers actual
sudo cat /etc/sudoers.d/gha-runner

# Editar de forma segura
sudo visudo -f /etc/sudoers.d/gha-runner
```

### Reemplazar el contenido con:

```sudoers
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

### Validar que la sintaxis es correcta:

```bash
sudo visudo -c -f /etc/sudoers.d/gha-runner
```

Si dice "parsed OK", está correcto.

---

## 2️⃣ VERIFICAR: Comandos que fallarán sin los permisos

| Script | Línea | Comando | Razón |
|--------|-------|---------|-------|
| gen_argocd_secret.sh | 288 | `sudo curl` | Descarga yq desde GitHub |
| gen_argocd_secret.sh | 292 | `sudo chmod +x` | Hace ejecutable a yq |
| gen_argocd_secret.sh | 308 | `sudo mv` + `sudo chmod` | Instala kubeseal |
| bootstrap_k3s.sh | 176 | `sudo chmod 600` | Configura kubeconfig |
| bootstrap_k3s.sh | 177 | `sudo chown` | Cambia propietario de kubeconfig |

**Impacto:** SIN estos permisos, los scripts fallarán en GitHub Actions.

---

## 3️⃣ VALIDACIÓN: Test de Permisos

Después de actualizar sudoers, desde el usuario `gha-runner` ejecutar:

```bash
# Probar cada permiso
sudo curl --version                    # ✓ Debe funcionar
sudo chmod --help                      # ✓ Debe funcionar
sudo mv --help                         # ✓ Debe funcionar
sudo wget --version                    # ✓ Debe funcionar
sudo chown --help                      # ✓ Debe funcionar

# Verificar que todos se ejecutan SIN pedir contraseña
```

---

## 4️⃣ COMPATIBILIDAD: gen_argocd_secret.sh vs bootstrap-argocd.sh

### Problemas Detectados:

1. **KUBECONFIG** - gen_argocd_secret.sh no busca en múltiples rutas
   - ❌ Problema: Si kubeconfig está en `/etc/rancher/k3s/k3s.yaml`, puede fallar
   - ✅ Solución: Agregar búsqueda multi-ruta (ver SCRIPT_IMPROVEMENTS.md)

2. **Validación de Cluster** - No verifica conectividad antes de usar kubectl
   - ❌ Problema: Errores vagos si no puede conectar
   - ✅ Solución: Agregar `kubectl cluster-info` check

3. **Colores/Output** - Inconsistente con bootstrap-argocd.sh
   - ⚠️ Menor: Pero afecta legibilidad en GitHub Actions

### Mejora Recomendada:

Aplicar las mejoras del archivo `SCRIPT_IMPROVEMENTS.md` al script.

---

## 5️⃣ GUÍA DE EJECUCIÓN EN GITHUB ACTIONS

El workflow debería ejecutar en este orden:

```yaml
- name: 🔧 Bootstrap K3s
  run: ./infra/bootstrap/bootstrap_k3s.sh

- name: 📦 Bootstrap Helm  
  run: ./infra/bootstrap/bootstrap_helm.sh

- name: 🔐 Bootstrap Sealed Secrets
  run: ./infra/bootstrap/bootstrap_sealed_secrets.sh

- name: 🔑 Generate ArgoCD Secret
  env:
    ARGOCD_ADMIN_PASSWORD: ${{ secrets.ARGOCD_PASSWORD }}
    FETCH_CERT: "true"
  run: ./scripts/gen_argocd_secret.sh

- name: 🚀 Bootstrap ArgoCD
  run: ./infra/bootstrap/bootstrap_argocd.sh
```

**Nota:** `FETCH_CERT=true` asegura que descargue el certificado real del cluster.

---

## 6️⃣ TESTING LOCAL (Antes de GitHub Actions)

Para probar localmente como usuario gha-runner:

```bash
# Simular el usuario gha-runner (si existe)
sudo su - gha-runner -c '
  export ARGOCD_ADMIN_PASSWORD="test-password"
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  cd /path/to/repo
  ./scripts/gen_argocd_secret.sh
'
```

O simplemente test individual:

```bash
# Test 1: Permisos de curl
sudo -u gha-runner -n sudo curl --version

# Test 2: Permisos de chmod
sudo -u gha-runner -n sudo chmod +x /tmp/test.txt

# Test 3: Permisos de mv
sudo -u gha-runner -n sudo mv /tmp/test.txt /tmp/test2.txt
```

---

## ✅ CHECKLIST DE VALIDACIÓN

- [ ] Sudoers actualizado con nuevos permisos
- [ ] `visudo -c` valida la sintaxis correctamente
- [ ] Probé cada permiso con `sudo` como gha-runner
- [ ] gen_argocd_secret.sh encuentra KUBECONFIG correctamente
- [ ] bootstrap_argocd.sh se ejecuta sin errores
- [ ] El secret sellado se genera correctamente
- [ ] El certificado se descarga del cluster (FETCH_CERT=true)

---

## 🆘 TROUBLESHOOTING

### Si gen_argocd_secret.sh falla en GitHub Actions:

```bash
# 1. Ver logs detallados
git push && gh run view -l <run-id>

# 2. Verificar KUBECONFIG
echo $KUBECONFIG
ls -la $KUBECONFIG

# 3. Verificar conectividad al cluster
kubectl cluster-info
kubectl get namespace

# 4. Verificar sealed-secrets está instalado
kubectl get deploy sealed-secrets -n kube-system

# 5. Re-generar certificate si es necesario
FETCH_CERT=true ./scripts/gen_argocd_secret.sh
```

### Si error de permisos (Permission denied):

El usuario no tiene el permiso en sudoers. Volver a step 1️⃣.

### Si kubeconfig no se encuentra:

Actualizar bootstrap-argocd.sh o gen_argocd_secret.sh con búsqueda multi-ruta (ver SCRIPT_IMPROVEMENTS.md).

---

## 📋 RESUMEN DE CAMBIOS NECESARIOS

| Componente | Acción | Urgencia |
|-----------|--------|----------|
| /etc/sudoers.d/gha-runner | Agregar permisos curl, chmod, mv, wget, chown | 🔴 CRÍTICA |
| gen_argocd_secret.sh | Mejorar manejo de KUBECONFIG | 🟡 ALTA |
| gen_argocd_secret.sh | Agregar validación de cluster | 🟡 ALTA |
| gen_argocd_secret.sh | Alinear colores con bootstrap-argocd.sh | 🟢 BAJA |
| bootstrap_k3s.sh | Validar permisos chmod/chown disponibles | 🟡 MEDIA |

