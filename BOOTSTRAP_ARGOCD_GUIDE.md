# Guía: Bootstrap de ArgoCD Integrado (v3.3.6)

## Resumen de Cambios

Se ha integrado completamente la generación del SealedSecret en el workflow `bootstrap-argocd.yaml`. El script `gen_argocd_secret.sh` ahora se ejecuta automáticamente como parte del proceso de instalación.

**Versión Actual:**
- ArgoCD: **v3.3.6**
- Helm Chart: **9.4.17**
- Configuración optimizada para K3s en laboratorio

### Archivos Modificados

- **`.github/workflows/bootstrap-argocd.yaml`**
  - Agregado paso: "Generate ArgoCD Sealed Secret"
  - Agregado paso: "Verify Dependencies for Secret Generation"
  - Agregado paso: "Push Generated Changes"
  - Actualizado paso: "Apply Sealed Secret" con validaciones

- **`scripts/gen_argocd_secret.sh`**
  - Detección automática de CI environment
  - Skip de git push automático en CI (lo hace el workflow)
  - Mejor manejo de errores y validaciones

---

## Prerequisitos

### 1. GitHub Secrets (Configuración única)

Crear un secret en el repositorio:

**Pasos:**
1. Ve a: Settings → Secrets and variables → Actions
2. Haz clic en "New repository secret"
3. Nombre: `ARGOCD_ADMIN_PASSWORD`
4. Valor: Tu contraseña segura para admin de ArgoCD (mínimo 12 caracteres recomendado)
5. Guarda

**Ejemplo de contraseña fuerte:**
```
MySecure@Passw0rd2024!
```

### 2. Certificado Público de Sealed-Secrets

Debe existir antes de ejecutar el workflow:
```
infra/sealed-secrets/pub-cert.pem
```

Este archivo se genera al ejecutar `bootstrap_sealed_secrets.sh`

### 3. K3s Cluster

Debe estar operacional y accesible.

---

## Flujo de Ejecución

### Paso 1: Ejecución Automática del Workflow

```bash
# Ir a GitHub → Actions → Bootstrap ArgoCD → Run workflow
```

El workflow ejecutará automáticamente los siguientes pasos:

### Paso 2: Validación de Requisitos
- ✓ Verifica kubectl y helm
- ✓ Verifica herramientas: htpasswd, yq, kubeseal (instala si es necesario)

### Paso 3: Generación del SealedSecret
```
"Generate ArgoCD Sealed Secret"
├─ Lee ARGOCD_ADMIN_PASSWORD desde GitHub Secrets
├─ Ejecuta: scripts/gen_argocd_secret.sh
├─ Genera: infra/argocd/sealed-secrets/argocd-secret.yaml
├─ Valida:
│  ├─ YAML válido
│  ├─ apiVersion = bitnami.com/v1alpha1
│  ├─ kind = SealedSecret
│  └─ Estructura completa
└─ Git: commit (sin push, lo hace el workflow después)
```

### Paso 4: Instalación de ArgoCD
```
"Execute Bootstrap ArgoCD"
├─ Crea namespace: argocd
├─ Agrega repo Helm
└─ Instala ArgoCD con Helm
```

### Paso 5: Verificación
```
"Verify ArgoCD Installation"
├─ Verifica namespace
├─ Verifica Helm release
└─ Muestra estado de pods
```

### Paso 6: Aplicación del SealedSecret
```
"Apply Sealed Secret"
├─ kubectl apply: argocd-secret.yaml
├─ Espera desellado del secreto (máx 30s)
└─ Reinicia todos los pods de ArgoCD
```

### Paso 7: Git Push
```
"Push Generated Changes"
├─ Detecta cambios en el secreto
└─ Hace git push automáticamente (si hay cambios)
```

---

## Validaciones Incorporadas

El workflow verifica automáticamente:

### Durante Generación del Secreto
- ✓ `ARGOCD_ADMIN_PASSWORD` está configurada en Secrets
- ✓ Script `gen_argocd_secret.sh` existe y es ejecutable
- ✓ Certificado público existe: `infra/sealed-secrets/pub-cert.pem`
- ✓ Archivo YAML generado es válido
- ✓ Estructura de SealedSecret es correcta
- ✓ Todos los campos obligatorios presentes

### Durante Instalación
- ✓ kubectl y helm disponibles
- ✓ Cluster Kubernetes accesible
- ✓ Namespace se crea exitosamente
- ✓ Pods de ArgoCD se inician correctamente

### Durante Aplicación del Secreto
- ✓ sealed-secrets controller está running
- ✓ SealedSecret se aplica sin errores
- ✓ Secreto se desesella correctamente (máx 30s)
- ✓ Pods de ArgoCD se reinician con la nueva contraseña

---

## Troubleshooting

### Error: "ARGOCD_ADMIN_PASSWORD no está definida"

**Solución:**
1. Ve a Settings → Secrets and variables → Actions
2. Verifica que existe `ARGOCD_ADMIN_PASSWORD`
3. Si no existe, créalo

### Error: "sealed-secrets controller no está running"

**Solución:**
1. Ejecuta primero: `bootstrap_sealed_secrets.sh`
2. Verifica: `kubectl get pods -n kube-system | grep sealed-secrets`

### Error: "El secreto no fue desellado dentro del tiempo límite"

**Solución:**
1. Verifica logs del sealed-secrets controller:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets -f
   ```
2. Verifica que el certificado es el correcto:
   ```bash
   kubectl get secret -n kube-system sealed-secrets-key
   ```

### El secreto se generó pero no se aplicó

**Verificar manualmente:**
```bash
# Revisar si el archivo existe
ls -la infra/argocd/sealed-secrets/argocd-secret.yaml

# Validar YAML
yq eval '.' infra/argocd/sealed-secrets/argocd-secret.yaml

# Aplicar manualmente
kubectl apply -f infra/argocd/sealed-secrets/argocd-secret.yaml

# Verificar si se deseilló
kubectl get secret -n argocd argocd-secret
```

---

## Acceso a ArgoCD

Después de una ejecución exitosa:

### 1. Port-Forward
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 2. Abrir en Navegador
```
https://localhost:8080
```

### 3. Credenciales
- **Usuario:** `admin`
- **Contraseña:** (la que configuraste en `ARGOCD_ADMIN_PASSWORD`)

Alternativamente, obtener desde el cluster:
```bash
kubectl -n argocd get secret argocd-secret -o jsonpath="{.data.admin\.password}" | base64 -d
```

---

## Ejecución Manual Local

Si necesitas generar el secreto manualmente:

```bash
export ARGOCD_ADMIN_PASSWORD="tu-contraseña"
bash scripts/gen_argocd_secret.sh
```

**Nota:** En ejecución local, el script hará push automático a Git.
Para evitarlo (en CI): `export SKIP_GIT_PUSH=true`

---

## Seguridad

### Buenas Prácticas
- ✓ La contraseña se almacena en GitHub Secrets (cifrada)
- ✓ El SealedSecret solo se puede desciframb en el cluster (con su clave)
- ✓ Los logs del GitHub Actions NO muestran la contraseña
- ✓ El certificado público puede estar en el repositorio (seguro)
- ✓ La clave privada está solo en el cluster

### Cambio de Contraseña
Para cambiar la contraseña de admin:
1. Actualiza el secret en GitHub: `Settings → Secrets → ARGOCD_ADMIN_PASSWORD`
2. Ejecuta el workflow: `Bootstrap ArgoCD`
3. El archivo y el cluster se actualizarán automáticamente

---

## Archivos Generados

Ubicación después de la ejecución:
```
infra/argocd/sealed-secrets/
└── argocd-secret.yaml          ← SealedSecret (válido para kubectl apply)
```

Contenido del SealedSecret:
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: argocd-secret
  namespace: argocd
spec:
  encryptedData:
    admin.password: <cifrado-base64>
    admin.passwordMtime: <timestamp-cifrado>
  template:
    metadata:
      name: argocd-secret
      namespace: argocd
    type: Opaque
```

---

## Próximos Pasos

1. ✓ Configurar `ARGOCD_ADMIN_PASSWORD` en GitHub Secrets
2. ✓ Ejecutar workflow: `Bootstrap ArgoCD`
3. ✓ Esperar a que todas las verificaciones pasen
4. ✓ Acceder a ArgoCD con `kubectl port-forward`
5. ✓ Cambiar contraseña en ArgoCD (optional pero recomendado)

---

## Referencias

- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
