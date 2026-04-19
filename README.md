# eu-githubops

Repository para automatizar el bootstrap y configuración de clusters Kubernetes con K3s, Helm e Ingress Controller.

## Índice

- [Instalación y Uso](#instalación-y-uso)
- [Componentes Core](#componentes-core)
  - [K3s](#configuración-de-k3s)
  - [Helm](#helm)
  - [NGINX Ingress Controller](#nginx-ingress-controller)
- [Componentes de Operaciones](#componentes-de-operaciones)
  - [Cert-Manager](#cert-manager)
  - [Sealed Secrets](#sealed-secrets)
  - [ArgoCD](#argocd)
  - [Argo-Rollouts](#argo-rollouts)
- [Seguridad del Workflow Bootstrap](#seguridad-del-workflow-bootstrap)
  - [Kubeconfig](#kubeconfig)
  - [Artifacts](#artifacts)
  - [Protecciones de Environment](#protecciones-de-environment)
  - [Checklist de Seguridad](#checklist-de-seguridad)
  - [Mejores Prácticas](#mejores-prácticas-adicionales)

---

## Instalación y Uso

### Estructura del Proyecto

```
infra/
├── bootstrap/
│   ├── bootstrap_all.sh                    # Script principal que ejecuta todos los pasos
│   ├── bootstrap_k3s.sh                    # Instalación de K3s base
│   ├── bootstrap_helm.sh                   # Instalación de gestor de paquetes Helm
│   ├── bootstrap_ingress.sh                # Instalación de NGINX Ingress Controller
│   ├── bootstrap_certmanager.sh            # Instalación de Cert-Manager
│   ├── bootstrap_sealed_secrets.sh         # Instalación de Sealed Secrets
│   ├── bootstrap_argocd.sh                 # Instalación de ArgoCD
│   └── bootstrap_clusterissuer.sh          # Configuración de ClusterIssuers
└── values/
    ├── argocd_values.yaml                  # Configuración para ArgoCD
    ├── cert_manager_values.yaml            # Configuración para Cert-Manager
    ├── ingress_values.yaml                 # Configuración para NGINX Ingress
    └── sealed_secrets_values.yaml          # Configuración para Sealed Secrets

platform/
├── root-platform.yaml                      # Aplicación raíz de ArgoCD
├── apps/                                   # Aplicaciones de la plataforma
└── argo-rollouts/
    ├── application.yaml                    # Configuración de Argo-Rollouts
    └── argo-rollouts-app/
        ├── kustomization.yaml              # Definición Kustomize
        └── values.yaml                     # Valores para Argo-Rollouts

argocd-projects/
└── platform_project.yaml                   # Proyecto de ArgoCD para plataforma
```

### Ejecutar Workflow

1. Ve a **Actions → Bootstrap Cluster**
2. Click **"Run workflow"**
3. Configura los inputs si es necesario:
   - `k3s_version`: Versión de K3s (default: `v1.30.0+k3s1`)
   - `helm_repos`: Repositorios de Helm (default: vacío)
   - `dry_run`: Ejecutar sin cambios (default: `false`)
4. El workflow ejecutará mediante `bootstrap_all.sh` todos los pasos:
   - ✅ K3s base
   - ✅ Helm
   - ✅ NGINX Ingress
   - ✅ Cert-Manager
   - ✅ Sealed Secrets
   - ✅ ArgoCD
   - ✅ ClusterIssuers (opcional)

### Instalación Manual

También puedes ejecutar cada script manualmente en el orden especificado:

```bash
# 1. K3s y dependencias base
./infra/bootstrap/bootstrap_k3s.sh
./infra/bootstrap/bootstrap_helm.sh
./infra/bootstrap/bootstrap_ingress.sh

# 2. Componentes de operaciones
./infra/bootstrap/bootstrap_certmanager.sh
./infra/bootstrap/bootstrap_sealed_secrets.sh
./infra/bootstrap/bootstrap_argocd.sh

# 3. Configuración de ClusterIssuers (opcional)
./infra/bootstrap/bootstrap_clusterissuer.sh
```

---

## Configuración de K3s

### Opciones de Instalación

K3s se instala con las siguientes opciones deshabilitando componentes innecesarios y configurando Calico como CNI:

```bash
K3S_EXEC_OPTS="--disable traefik --disable servicelb --flannel-backend=none --disable-network-policy --write-kubeconfig-mode 644"
```

#### Significado de cada opción:

| Opción | Descripción |
|--------|-------------|
| `--disable traefik` | No instala Traefik (Ingress Controller integrado). Usamos NGINX via Helm |
| `--disable servicelb` | No instala klipper-lb (LoadBalancer simple). Mejor control con Calico |
| `--flannel-backend=none` | Desactiva Flannel CNI para usar Calico en su lugar |
| `--disable-network-policy` | Sin política de red integrada. Calico proporciona versión más robusta |
| `--write-kubeconfig-mode 644` | Genera kubeconfig con permisos 644 (legible sin `sudo`) |

### Flujo de Instalación

1. **K3s Core**: Instala K3s sin CNI
2. **Calico**: Se instala después como CNI con manifests oficial
3. **Helm**: Se instala para gestionar otros componentes
4. **NGINX Ingress**: Se despliega via Helm usando `infra/values/ingress_values.yaml`

### Verificación post-instalación

El script `bootstrap_k3s.sh` verifica:
- ✅ Puertos disponibles (6443, 10250)
- ✅ Conectividad DNS
- ✅ Servicio k3s activo
- ✅ Pods del sistema en estado Running (máximo 5 minutos)
- ✅ Kubeconfig accesible y con permisos correctos

### Troubleshooting

Si K3s falla al iniciar:

```bash
# Ver estado del servicio
sudo systemctl status k3s

# Ver logs detallados
sudo journalctl -xeu k3s.service -n 50

# Desinstalar completamente
sudo /usr/local/bin/k3s-uninstall.sh
sudo rm -rf /etc/rancher /var/lib/rancher
```

---

## Componentes de Operaciones

### Helm

Helm es el gestor de paquetes para Kubernetes utilizado para instalar y configurar todos los componentes adicionales.

#### Variables de Configuración

```bash
HELM_REPO_NAME="nombre-del-repo"
HELM_REPO_URL="https://example.com/charts"
```

#### Verificar Instalación

```bash
# Listar repositorios configurados
helm repo list

# Actualizar repositorios
helm repo update

# Buscar charts disponibles
helm search repo <chart-name>
```

### NGINX Ingress Controller

NGINX Ingress controla el acceso externo a los servicios del cluster.

#### Instalación

Se instala via Helm usando configuración en `infra/values/ingress_values.yaml`:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f infra/values/ingress_values.yaml
```

#### Verificar Instalación

```bash
# Ver pods de ingress
kubectl get pods -n ingress-nginx

# Ver services
kubectl get svc -n ingress-nginx

# Ver IP externa (LoadBalancer)
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Cert-Manager

Cert-Manager automatiza la gestión y renovación de certificados SSL/TLS en Kubernetes.

#### Configuración

| Variable | Valor | Descripción |
|----------|-------|-------------|
| Namespace | `cert-manager` | Espacio de nombres dedicado |
| Chart Version | `1.14.5` | Versión del Helm chart |
| Repository | `https://charts.jetstack.io` | Repositorio Helm oficial |

#### Instalación

```bash
# El script bootstrap_certmanager.sh realiza:
./infra/bootstrap/bootstrap_certmanager.sh

# Pasos internos:
# 1. Añade repositorio Helm de Jetstack
helm repo add jetstack https://charts.jetstack.io

# 2. Crea namespace cert-manager
kubectl create namespace cert-manager

# 3. Instala via Helm
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version 1.14.5 \
  -f infra/values/cert_manager_values.yaml
```

#### Verificar Instalación

```bash
# Ver pods de cert-manager
kubectl get pods -n cert-manager

# Ver recursos disponibles (CertificateIssuer, Certificate, etc.)
kubectl api-resources | grep cert

# Ver ClusterIssuers configurados
kubectl get clusterissuer
```

#### Crear Certificados

Los certificados se definen usando recursos de Kubernetes:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: miapp-cert
  namespace: default
spec:
  secretName: miapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - miapp.example.com
    - www.miapp.example.com
```

#### ClusterIssuers

Los ClusterIssuers definen autoridades que pueden emitir certificados (Let's Encrypt, etc.):

```bash
# Ver configuración en:
cat infra/cert-manager/clusterissuer.yaml

# Aplicar ClusterIssuers
kubectl apply -f infra/cert-manager/clusterissuer.yaml

# Verificar estado
kubectl describe clusterissuer letsencrypt-prod
```

### Sealed Secrets

Sealed Secrets permite encriptar secrets de Kubernetes de forma segura en Git.

#### Configuración

| Variable | Valor | Descripción |
|----------|-------|-------------|
| Namespace | `kube-system` | Instalado en namespace del sistema |
| Release Name | `sealed-secrets` | Nombre del release Helm |
| Repository | `https://bitnami-labs.github.io/sealed-secrets` | Repositorio oficial |

#### Instalación

```bash
# El script bootstrap_sealed_secrets.sh realiza:
./infra/bootstrap/bootstrap_sealed_secrets.sh

# Pasos internos:
# 1. Añade repositorio Helm de Bitnami
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets

# 2. Instala en kube-system
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  -f infra/values/sealed_secrets_values.yaml
```

#### Verificar Instalación

```bash
# Ver pods de sealed-secrets
kubectl get pods -n kube-system | grep sealed-secrets

# Ver claves de encriptación
kubectl get secret -n kube-system seq | grep sealed-secrets-key
```

#### Generar Secrets Encriptados

```bash
# 1. Instalar kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# 2. Crear secret normal
kubectl create secret generic mi-secret \
  --from-literal=username=admin \
  --from-literal=password=secreto123 \
  --dry-run=client -o yaml > secret.yaml

# 3. Encriptar con kubeseal
kubeseal -f secret.yaml -w sealed-secret.yaml --scope cluster-wide

# 4. Aplicar secret encriptado (seguro en Git)
kubectl apply -f sealed-secret.yaml
```

#### Obtener Clave Pública

```bash
# Exportar clave pública para descifrar en CI/CD
kubeseal --fetch-cert > public-key.crt
```

### ArgoCD

ArgoCD es un GitOps controller que sincroniza aplicaciones definidas en Git con el cluster Kubernetes.

#### Configuración

| Variable | Valor | Descripción |
|----------|-------|-------------|
| Namespace | `argocd` | Espacio de nombres dedicado |
| Chart Version | `9.5.0` | Versión del Helm chart |
| App Version | `v3.3.6` | Versión de ArgoCD |
| Repository | `https://argoproj.github.io/argo-helm` | Repositorio oficial |

#### Instalación

```bash
# El script bootstrap_argocd.sh realiza:
./infra/bootstrap/bootstrap_argocd.sh

# Pasos internos:
# 1. Añade repositorio Helm de ArgoProg
helm repo add argo https://argoproj.github.io/argo-helm

# 2. Crea namespace argocd
kubectl create namespace argocd

# 3. Instala/actualiza via Helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 9.5.0 \
  -f infra/values/argocd_values.yaml
```

#### Verificar Instalación

```bash
# Ver pods de ArgoCD
kubectl get pods -n argocd

# Ver servicios
kubectl get svc -n argocd

# Acceder a la UI (port-forward)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# URL: https://localhost:8080
```

#### Login en ArgoCD

```bash
# Obtener contraseña admin inicial
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Login con CLI
argocd login localhost:8080 --username admin --password <contraseña>

# Cambiar contraseña
argocd account update-password
```

#### Crear Proyectos y Aplicaciones

**Proyecto:**

El proyecto `platform` está definido en `argocd-projects/platform_project.yaml`:

```bash
kubectl apply -f argocd-projects/platform_project.yaml
```

**Aplicación Raíz:**

La aplicación raíz se define en `platform/root-platform.yaml`:

```bash
kubectl apply -f platform/root-platform.yaml

# Ver sincronización
argocd app get root-platform
argocd app wait root-platform --sync
```

#### Sincronizar Aplicaciones

```bash
# Ver aplicaciones
argocd app list

# Sincronizar una aplicación
argocd app sync myapp

# Sincronizar automáticamente (auto-sync)
argocd app set myapp --sync-policy automated

# Ver estado
argocd app get myapp
```

### Argo-Rollouts

Argo-Rollouts proporciona estrategias avanzadas de despliegue (Canary, Blue-Green, A/B Testing).

#### Configuración

```
platform/argo-rollouts/
├── application.yaml           # Recurso Rollout de Argo
└── argo-rollouts-app/
    ├── kustomization.yaml     # Personalización Kustomize
    └── values.yaml            # Configuración de valores
```

#### Instalación

Argo-Rollouts debe instalarse como dependencia en el cluster. Se recomienda desplegar via ArgoCD:

```bash
# Crear namespace para argo-rollouts
kubectl create namespace argo-rollouts

# Desplegar Argo-Rollouts controller
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/download/v1.6.0/install.yaml
```

#### Definir un Rollout

Un Rollout en lugar de Deployment permite más control:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: miapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: miapp
  template:
    metadata:
      labels:
        app: miapp
    spec:
      containers:
      - name: miapp
        image: miapp:v1.0
  strategy:
    canary:
      steps:
      - weight: 20  # 20% del tráfico a v2
        duration: 5m
      - weight: 50  # 50% del tráfico a v2
        duration: 5m
      - weight: 100 # 100% del tráfico a v2
```

#### Estrategias Soportadas

| Estrategia | Descripción | Caso de Uso |
|-----------|-------------|-----------|
| Rolling | Actualización gradual de pods | Despliegues seguros pero sin control fino |
| Canary | Traslado gradual de tráfico a nueva versión | Testing de nuevas versiones con tráfico real |
| Blue-Green | Mantiene dos versiones simultaneously | Cambio instantáneo entre versiones |
| A/B Testing | Enruta usuarios específicos a versiones | Experimentos con segmentos de usuarios |

#### Gestionar Rollouts

```bash
# Ver rollouts
kubectl get rollout -n default

# Ver estado detallado
kubectl describe rollout miapp -n default

# Avanzar al siguiente paso
argocd-rollouts promote miapp -n default

# Abortar rollout
argocd-rollouts abort miapp -n default

# Revertir a versión anterior
argocd-rollouts undo miapp -n default
```

---

## Seguridad del Workflow Bootstrap

Esta sección describe las medidas de seguridad implementadas en el workflow `bootstrap-cluster.yml`.

### Kubeconfig

#### Copia y Cambio de Propietario

El workflow implementa los siguientes pasos de seguridad:

```bash
# 1. Copiar kubeconfig desde k3s (requiere sudo)
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/kubeconfig

# 2. Cambiar propietario para evitar sudo posterior
sudo chown $(id -u):$(id -g) $HOME/kubeconfig

# 3. Establecer permisos restrictivos
chmod 600 $HOME/kubeconfig
```

**Beneficio**: Después de la copia inicial, el runner puede acceder al kubeconfig sin permisos elevados en pasos posteriores.

#### Permisos del Archivo

```
-rw------- (600)  Solo el propietario puede leer/escribir
```

### Artifacts

#### Configuración Actual

- **Nombre**: `kubeconfig`
- **Retención**: `30 días` (configurable)
- **Compresión**: Nivel 9 (máxima)
- **Ubicación**: `$HOME/bootstrap-artifacts/`

#### Descarga en Otros Workflows

Para descargar el kubeconfig en otro workflow:

```yaml
- name: Download kubeconfig Artifact
  uses: actions/download-artifact@v4
  with:
    name: kubeconfig
    path: $HOME

- name: Usar kubeconfig
  env:
    KUBECONFIG: $HOME/kubeconfig
  run: |
    kubectl get nodes
```

#### Reducir Retención

Para menor exposición, cambia `retention-days` en el workflow:

```yaml
retention-days: 7  # Más corto si quieres menor exposición
```

### Protecciones de Environment

El workflow usa `environment: lab` para requerir aprobaciones **ANTES** de ejecutar el bootstrap.

#### Configurar en GitHub

1. **Ir a Settings del repositorio**
   ```
   Settings → Environments
   ```

2. **Crear nuevo environment "lab"**
   - Click "New environment"
   - Nombre: `lab`

3. **Configurar protecciones** (en el environment "lab"):

   **a) Required reviewers**
   - Habilitar: "Require reviewers"
   - Seleccionar usuarios que deben aprobar

   **b) Wait timer**
   - Habilitar: "Required wait timer"
   - Establece minutos antes de permitir ejecución (ej: 0 para inmediato)

   **c) Deployment branches**
   - Habilitar: "Deployment branches"
   - Restringe a ramas específicas:
     ```
     main
     develop
     ```

   **d) Environment secrets** (Opcional)
   - Credenciales únicas para este environment
   - Más seguros que secrets globales del repo

#### Flujo con Protecciones

```
1. Usuario dispara workflow_dispatch
   ↓
2. GitHub requiere aprobación de un reviewer
   ↓
3. Reviewer revisa y aprueba en GitHub UI
   ↓
4. El job "bootstrap" se ejecuta
```

### Checklist de Seguridad

- [ ] El workflow copia `/etc/rancher/k3s/k3s.yaml` a `$HOME/kubeconfig`
- [ ] El propietario se cambia con `chown` para evitar `sudo` posterior
- [ ] Permisos del kubeconfig son `600` (solo lectura para owner)
- [ ] El artifact se sube con `actions/upload-artifact`
- [ ] Retención de days es apropiada (30 = default, 7 = más restrictivo)
- [ ] Environment `lab` está creado en Settings → Environments
- [ ] Required reviewers están configurados en el environment
- [ ] Deployment branches están restringidas a las ramas apropiadas
- [ ] Solo usuarios de confianza pueden acceder a artifacts

### Mejores Prácticas Adicionales

#### Limpieza de kubeconfig antiguo

Considera agregar un step que limpie artifacts muy antiguos:

```yaml
- name: Cleanup old kubeconfig artifacts
  uses: geekyeggo/delete-artifact@v2
  with:
    name: kubeconfig
    failOnError: false
```

#### Auditoría de acceso

- Los artifacts se registran en el histórico del workflow
- Revisa quién descargó qué artifact
- Considera alertas si se descarga un artifact sensible

#### Rotación de credenciales

- Cambia regularmente las credenciales del kubeconfig
- Invalida acceso antiguo en el cluster

#### Logging

Al descargar el kubeconfig, **no logs el contenido**:

```bash
# ✓ BIEN: Solo confirmar que se descargó
echo "✓ kubeconfig descargado"

# ✗ MAL: Nunca hacer esto
cat $KUBECONFIG
```

#### Variables de Environment

Configurables en el workflow:

```yaml
env:
  KUBECONFIG: $HOME/kubeconfig          # Ruta al kubeconfig
  RETRY_MAX: 5                           # Intentos de reintento
  RETRY_DELAY: 2                         # Segundos entre reintentos
  ARTIFACT_DIR: $HOME/bootstrap-artifacts  # Directorio de artifacts
```

---

## Referencias

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub Environment Protection Rules](https://docs.github.com/en/actions/deployment/targeting-different-environments)
- [K3s Documentation](https://docs.k3s.io/)
- [Helm Documentation](https://helm.sh/docs/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Argo-Rollouts Documentation](https://argo-rollouts.readthedocs.io/)

## Guías Detalladas

Este repositorio incluye guías específicas para componentes:

- [Bootstrap Guide](BOOTSTRAP_ARGOCD_GUIDE.md) - Guía de bootstrap de ArgoCD
- [ClusterIssuer Guide](CLUSTERISSUER_GUIDE.md) - Configuración de ClusterIssuers para Let's Encrypt
- [Root Application Guide](ROOTAPP_GUIDE.md) - Configuración de aplicación raíz en ArgoCD
