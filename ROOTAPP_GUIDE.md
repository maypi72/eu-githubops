# Guía: Aplicar Root Application de ArgoCD

## Descripción

La **Root Application** es el punto de entrada para que **ArgoCD** gestione toda la plataforma. Una vez aplicada, ArgoCD sincronizará automáticamente todos los componentes y aplicaciones definidas en el repositorio.

## Requisitos

Antes de aplicar la Root Application, debes haber completado:

1. ✓ **Cluster Kubernetes**: k3s instalado y funcionando
2. ✓ **Helm**: Instalado en el cluster
3. ✓ **ArgoCD**: Instalado en el namespace `argocd` (ejecutar `bootstrap-argocd.yml`)
4. ✓ **Archivo**: `platform/root-application.yaml` debe existir en el repositorio

## Métodos de Aplicación

### Opción 1: Usar el Script Localmente

Si tienes acceso directo al cluster con `kubectl` configurado:

```bash
# Navega al directorio raíz del repositorio
cd /path/to/eu-githubops

# Executa el script
./scripts/gen_root_app.sh
```

**Lo que hace el script:**
- ✓ Valida que `kubectl` está disponible
- ✓ Configura `KUBECONFIG` automáticamente si es necesario
- ✓ Verifica que el cluster es accesible
- ✓ Comprueba que el namespace `argocd` existe
- ✓ Comprueba que ArgoCD está instalado
- ✓ Valida que el archivo YAML existe
- ✓ Comprueba si la Application ya existe
- ⚠️ **Si ya existe**: te pide confirmación antes de actualizar
- ✓ Aplica el archivo YAML
- ✓ Espera a que ArgoCD registre la Application
- ✓ Muestra estado e instrucciones para monitoreo

**Ejemplo de ejecución exitosa:**

```
[INFO] ====================================================
[INFO] Aplicar Root Application de ArgoCD
[INFO] ====================================================
[✓] kubectl disponible
[✓] KUBECONFIG encontrado: /etc/rancher/k3s/k3s.yaml
[✓] Cluster Kubernetes accesible
[✓] Namespace 'argocd' existe
[✓] ArgoCD está instalado en 'argocd'
[✓] Archivo encontrado: platform/root-application.yaml
[INFO] Aplicando: platform/root-application.yaml
[✓] Root Application aplicado correctamente
...
```

### Opción 2: Usar el Workflow de GitHub Actions

Si el cluster está configurado como `self-hosted` runner en GitHub:

1. **Ir a**: `Actions` > `Apply Root Application` > `Run workflow`
2. **Configurar opciones** (opcional):
   - `force_update`: Actualizar incluso si ya existe (default: `false`)
   - `verify_only`: Solo hacer dry-run sin aplicar (default: `false`)
3. **Hacer clic**: ▶️ `Run workflow`

**El workflow:**
- Descarga el repositorio
- Busca `kubeconfig` automáticamente
- Valida todos los prerrequisitos
- Valida la sintaxis YAML
- Comprueba si la Application existe
- Aplica el YAML (o salta si ya existe, a menos que `force_update=true`)
- Verifica el despliegue
- Proporciona instrucciones de monitoreo
- En caso de error: genera diagnóstico detallado

## Contenido del Archivo YAML

La Root Application típicamente contiene:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/upcdevops/eu-githubops
    targetRevision: main
    path: platform/  # o la ruta donde están las aplicaciones
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Después de Aplicar

### Monitorear la Sincronización

```bash
# Ver estado en tiempo real
kubectl get application platform-root -n argocd -w

# Ver detalles de la Application
kubectl describe application platform-root -n argocd

# Ver logs de ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f
```

### Verificar Componentes Instalados

```bash
# Ver aplicaciones gestionadas por ArgoCD
kubectl get applications -n argocd

# Ver recursos desplegados por ArgoCD
kubectl get all -n argocd

# Acceder a la UI de ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Luego: https://localhost:8080
```

## Solución de Problemas

### La Application ya existe

**Problema**: El script dice que la Application ya existe

**Solución**:
- Opción 1: Ejecutar nuevamente y responder `s` para actualizar
- Opción 2: Usar el flag `force_update=true` en el workflow
- Opción 3: Eliminar manualmente:
  ```bash
  kubectl delete application platform-root -n argocd
  kubectl delete crd applications.argoproj.io  # Si no hay otros app
  ```

### ArgoCD no está instalado

**Problema**: Error "ArgoCD no está instalado"

**Solución**:
```bash
# Primero, ejecutar bootstrap de ArgoCD
./infra/bootstrap/bootstrap_argocd.sh

# Esperar a que esté listo
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Luego ejecutar el script
./scripts/gen_root_app.sh
```

### Archivo YAML no encontrado

**Problema**: Error "platform/root-application.yaml no encontrado"

**Solución**:
1. Crear el archivo YAML:
   ```bash
   mkdir -p platform
   # Crear platform/root-application.yaml con el contenido correcto
   ```
2. Commitear y verificar que está en el repositorio
3. Ejecutar nuevamente el script

### Timeout esperando Application

**Problema**: El script espera demasiado tiempo

**Solución**:
- Aumentar el timeout en el script (línea con `retry`)
- Verificar los logs de ArgoCD:
  ```bash
  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
  ```
- Comprobar si hay errores de validación YAML:
  ```bash
  kubectl apply -f platform/root-application.yaml --dry-run=client -v=9
  ```

### Fallo de conectividad con el cluster

**Problema**: "No se puede conectar al cluster"

**Solución**:
```bash
# Verificar KUBECONFIG
echo $KUBECONFIG
kubectl cluster-info

# Comprobar acceso
kubectl auth can-i get applications --as=system:serviceaccount:argocd:argocd-server -n argocd

# Si es necesario, copiar kubeconfig:
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config
```

## Integración con CI/CD

### GitHub Actions

El workflow `apply_rootapp.yaml` se ejecuta automáticamente cuando:
- Se dispara manualmente desde la pestaña Actions
- Puedes programarla en el archivo si lo deseas:
  ```yaml
  on:
    schedule:
      - cron: '0 0 * * 0'  # Cada domingo a medianoche
  ```

### Ejecutar después de bootstrap-argocd

Opcional: Configurar que el workflow `apply_rootapp.yaml` se ejecute automáticamente después de `bootstrap-argocd.yaml`:

```yaml
# En apply_rootapp.yaml
on:
  workflow_run:
    workflows: ["bootstrap-argocd.yaml"]
    types:
      - completed
    branches: [main]
```

## Verificación de Éxito

La Application está correctamente aplicada cuando:

1. ✓ La Application aparece en ArgoCD:
   ```bash
   kubectl get application platform-root -n argocd
   ```

2. ✓ El estado de sincronización es `Synced`:
   ```bash
   kubectl get application platform-root -n argocd -o jsonpath='{.status.sync.status}'
   ```

3. ✓ El estado de salud no es `Unknown`:
   ```bash
   kubectl get application platform-root -n argocd -o jsonpath='{.status.health.status}'
   ```

4. ✓ Los pods de aplicaciones se están deployando:
   ```bash
   kubectl get pods --all-namespaces
   ```

## Archivos Relacionados

- 📄 `scripts/gen_root_app.sh` - Script de aplicación manual
- 🔧 `.github/workflows/apply_rootapp.yaml` - Workflow de GitHub Actions
- 📋 `platform/root-application.yaml` - Manifiesto de la Application
- 📖 `BOOTSTRAP_ARGOCD_GUIDE.md` - Cómo instalar ArgoCD
- 📖 `README.md` - Resumen general del proyecto

## Referencia Rápida

```bash
# Aplicar Root Application
./scripts/gen_root_app.sh

# Verificar estado
kubectl get application platform-root -n argocd

# Actualizar forzadamente
./scripts/gen_root_app.sh  # y responder 's'

# Eliminar Application (para reinstalar)
kubectl delete application platform-root -n argocd

# Ver todos los componentes desplegados
kubectl get all --all-namespaces
```

## Preguntas Frecuentes

**P: ¿Puedo aplicar la Root Application varias veces?**
A: Sí, es seguro. El script comprueba si ya existe y te pide confirmación.

**P: ¿Qué pasa si actualizo el archivo YAML en el repositorio?**
A: ArgoCD no aplicará los cambios automáticamente a menos que esté configurada con `syncPolicy.automated`. Ejecuta el script nuevamente con `force_update=true`.

**P: ¿Necesito aplicar la Root Application en cada nodo?**
A: No. Solo se aplica una vez en el cluster. ArgoCD gestiona el despliegue en todos los nodos.

**P: ¿Puedo tener múltiples Root Applications?**
A: No recomendado. Usa una sola Root Application que apunte a todas tus aplicaciones.

---

**Última actualización**: 2026-04-09  
**Versión**: 1.0
