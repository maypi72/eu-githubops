# Guía: Aplicar Root Platform (Project + Application de ArgoCD)

## Descripción

La **Root Platform** es el punto de entrada completo para que **ArgoCD** gestione toda la plataforma. Consiste en:

1. **ArgoCD Project** (`platfrom_proyect.yaml`): Define el proyecto y permisos para ArgoCD
2. **Root Application** (`root-platform.yaml`): La aplicación raíz que sincroniza todo

Una vez aplicados, ArgoCD sincronizará automáticamente todos los componentes y aplicaciones definidas en el repositorio.

**Orden de aplicación**: Primero Project, luego Root Application

## Requisitos

Antes de aplicar la Root Platform, debes haber completado:

1. ✓ **Cluster Kubernetes**: k3s instalado y funcionando
2. ✓ **Helm**: Instalado en el cluster
3. ✓ **ArgoCD**: Instalado en el namespace `argocd` (ejecutar `bootstrap-argocd.yml`)
4. ✓ **Archivos**: 
   - `argocd-proyects/platfrom_proyect.yaml` debe existir
   - `platform/root-platform.yaml` debe existir

## Métodos de Aplicación

### Opción 1: Usar el Script Localmente

Si tienes acceso directo al cluster con `kubectl` configurado:

```bash
# Navega al directorio raíz del repositorio
cd /path/to/eu-githubops

# Ejecuta el script (aplica primero Project, luego Root Application)
./scripts/gen_root_plat.sh
```

**Lo que hace el script:**
- ✓ Valida que `kubectl` está disponible
- ✓ Configura `KUBECONFIG` automáticamente si es necesario
- ✓ Verifica que el cluster es accesible
- ✓ Comprueba que el namespace `argocd` existe
- ✓ Comprueba que ArgoCD está instalado
- ✓ Valida que ambos archivos YAML existen:
  - `argocd-proyects/platfrom_proyect.yaml`
  - `platform/root-platform.yaml`
- ✓ **Primero**: Aplica el ArgoCD Project
- ✓ **Luego**: Aplica la Root Application
- ✓ Comprueba si ya existen
- ⚠️ **Si ya existen**: te pide confirmación antes de actualizar
- ✓ Espera a que se registren en ArgoCD
- ✓ Muestra estado e instrucciones para monitoreo

**Ejemplo de ejecución exitosa:**

```
[INFO] ====================================================
[INFO] Aplicar Root Platform (Project + Application)
[INFO] ====================================================
[✓] kubectl disponible
[✓] KUBECONFIG encontrado: /etc/rancher/k3s/k3s.yaml
[✓] Cluster Kubernetes accesible
[✓] Namespace 'argocd' existe
[✓] ArgoCD está instalado en 'argocd'
[✓] Archivo encontrado: argocd-proyects/platfrom_proyect.yaml
[✓] Archivo encontrado: platform/root-platform.yaml
...
[✓] ArgoCD Project aplicado correctamente
[✓] Root Application aplicado correctamente
```

### Opción 2: Usar el Workflow de GitHub Actions

Si el cluster está configurado como `self-hosted` runner en GitHub:

1. **Ir a**: `Actions` > `Apply Root Platform` > `Run workflow`
2. **Configurar opciones** (opcional):
   - `force_update`: Actualizar incluso si ya existen (default: `false`)
   - `verify_only`: Solo hacer dry-run sin aplicar (default: `false`)
3. **Hacer clic**: ▶️ `Run workflow`

**El workflow:**
- Descarga el repositorio
- Busca `kubeconfig` automáticamente
- Valida todos los prerrequisitos
- Valida la sintaxis YAML de ambos archivos
- Comprueba si Project y Application existen
- Aplica el Project primero (o salta si existe, a menos que `force_update=true`)
- Aplica la Root Application (o salta si existe, a menos que `force_update=true`)
- Verifica los despliegues
- Proporciona instrucciones de monitoreo
- En caso de error: genera diagnóstico detallado

## Contenido de los Archivos YAML

### 1. ArgoCD Project (`argocd-proyects/platfrom_proyect.yaml`)

Define el proyecto de ArgoCD y sus permisos:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-project
  namespace: argocd
spec:
  description: Platform Project
  sourceNamespaces:
    - argocd
  destinations:
    - namespace: '*'
      server: '*'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
```

### 2. Root Application (`platform/root-platform.yaml`)

La aplicación raíz que sincroniza todo:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root
  namespace: argocd
spec:
  project: platform-project  # Referencia al project anterior
  source:
    repoURL: https://github.com/upcdevops/eu-githubops
    targetRevision: main
    path: platform/
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Nota**: El orden es importante. El Project debe existir antes que la Application que lo referencia.

## Después de Aplicar

### Monitorear la Sincronización

```bash
# Ver estado del Project
kubectl get appproject -n argocd

# Ver detalles del Project
kubectl describe appproject platform-project -n argocd

# Ver estado en tiempo real de la Application
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

### Project o Application ya existen

**Problema**: El script dice que Project/Application ya existe

**Solución**:
- Opción 1: Ejecutar nuevamente y responder `s` para actualizar
- Opción 2: Usar el flag `force_update=true` en el workflow
- Opción 3: Eliminar manualmente:
  ```bash
  kubectl delete application platform-root -n argocd
  kubectl delete appproject platform-project -n argocd
  # Esperar a que se eliminen
  sleep 10
  # Ejecutar el script nuevamente
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
./scripts/gen_root_plat.sh
```

### Archivos YAML no encontrados

**Problema**: Error "platform/root-platform.yaml no encontrado" o "argocd-proyects/platfrom_proyect.yaml no encontrado"

**Solución**:
1. Crear los archivos YAML:
   ```bash
   mkdir -p platform
   mkdir -p argocd-proyects
   # Crear platform/root-platform.yaml con contenido correcto
   # Crear argocd-proyects/platfrom_proyect.yaml con contenido correcto
   ```
2. Commitear y verificar que están en el repositorio
3. Ejecutar nuevamente el script

### Timeout esperando Project/Application

**Problema**: El script espera demasiado tiempo para que se registren

**Solución**:
- Verificar los logs de ArgoCD:
  ```bash
  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f
  ```
- Comprobar si hay errores de validación YAML:
  ```bash
  kubectl apply -f argocd-proyects/platfrom_proyect.yaml --dry-run=client -v=9
  kubectl apply -f platform/root-platform.yaml --dry-run=client -v=9
  ```
- Verificar que el Project existe antes que la Application:
  ```bash
  kubectl get appproject platform-project -n argocd
  kubectl get application platform-root -n argocd
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

- 📄 `scripts/gen_root_plat.sh` - Script de aplicación manual
- 🔧 `.github/workflows/apply_rootplat.yaml` - Workflow de GitHub Actions
- 📋 `argocd-proyects/platfrom_proyect.yaml` - Manifiesto del ArgoCD Project
- 📋 `platform/root-platform.yaml` - Manifiesto de la Root Application
- 📖 `BOOTSTRAP_ARGOCD_GUIDE.md` - Cómo instalar ArgoCD
- 📖 `README.md` - Resumen general del proyecto

## Referencia Rápida

```bash
# Aplicar Root Platform (Project + Application)
./scripts/gen_root_plat.sh

# Verificar estado del Project
kubectl get appproject platform-project -n argocd

# Verificar estado de la Application
kubectl get application platform-root -n argocd

# Actualizar forzadamente
./scripts/gen_root_plat.sh  # y responder 's'

# Eliminar recursos (para reinstalar)
kubectl delete application platform-root -n argocd
kubectl delete appproject platform-project -n argocd

# Ver todos los componentes desplegados por ArgoCD
kubectl get all --all-namespaces
```

## Preguntas Frecuentes

**P: ¿Por qué necesitamos un AppProject separado?**
A: El AppProject define permisos y alcance. Es una buena práctica de seguridad separarlos de la Application.

**P: ¿Cuál es el orden de aplicación?**
A: Primero Project, luego Application. La Application referencia el Project, así que debe existir primero.

**P: ¿Puedo aplicar la Root Platform varias veces?**
A: Sí, es seguro. El script comprueba si ya existen y te pide confirmación.

**P: ¿Qué pasa si actualizo los archivos YAML en el repositorio?**
A: Si están configurados con `syncPolicy.automated`, ArgoCD aplicará los cambios automáticamente. De lo contrario, ejecuta el script nuevamente con `force_update=true`.

**P: ¿Necesito aplicar la Root Platform en cada nodo?**
A: No. Solo se aplica una vez en el cluster. ArgoCD gestiona el despliegue en todos los nodos.

**P: ¿Puedo tener múltiples Root Applications?**
A: No recomendado. Usa una sola Root Application que apunte a todas tus aplicaciones.

**P: ¿Qué pasa si el Project ya existe pero la Application no?**
A: El script aplicará solo la Application. Puedes usar `force_update=true` para forzar la actualización de ambas.

---

**Última actualización**: 2026-04-09  
**Versión**: 2.0 (con support para Project + Application)
