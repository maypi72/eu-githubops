# 🏗️ EU-GitHubOps: Laboratorio de GitOps con ArgoCD y Argo Rollouts

**Un repositorio completo de infraestructura como código (IaC) para desplegar aplicaciones cloud-native en Kubernetes usando GitOps con ArgoCD y estrategias de deployment avanzadas con Argo Rollouts.**

---

## 📌 Descripción General

`eu-githubops` es un **laboratorio práctico de GitOps** que automatiza completamente:

- ✅ **Bootstrapping de clusters K3s** con herramientas cloud-native
- ✅ **Gestión declarativa** de aplicaciones mediante ArgoCD
- ✅ **Deployments avanzados** con Argo Rollouts (Blue-Green, Canary)
- ✅ **Seguridad** mediante Sealed Secrets y Cert-Manager
- ✅ **Observabilidad** con Prometheus + Grafana
- ✅ **CI/CD** integrado con GitHub Actions

El repositorio demuestra un flujo **Production-Ready** donde la infraestructura y aplicaciones son completamente gitopsificadas: **toda configuración vive en git** y GitHub Actions orquesta el despliegue.

### 🎯 Stack Tecnológico

| Componente | Versión | Propósito |
|---|---|---|
| **K3s** | v1.30.x | Kubernetes ligero y eficiente |
| **ArgoCD** | v3.3.6 | GitOps controller declarativo |
| **Argo Rollouts** | Latest | Deployment avanzados con análisis |
| **Sealed Secrets** | Latest | Secretos cifrados en git |
| **Cert-Manager** | Latest | TLS automático con CA privada |
| **NGINX Ingress** | Latest | Ingress controller |
| **Prometheus + Grafana** | Latest | Monitoreo y métricas |

---

## 📋 Licencias

### ListMonk - Licencia AGPL v3

[**ListMonk**](https://github.com/knadh/listmonk) es una plataforma de gestión de newsletters **libre y de código abierto** bajo licencia **AGPLv3**.

- **Licencia**: GNU Affero General Public License v3.0
- **Repositorio oficial**: https://github.com/knadh/listmonk
- **Características**: Gestión de suscriptores, campañas, automatización
- **¿Qué significa AGPL v3?**: 
  - ✅ Libre para usar, modificar y distribuir
  - ✅ Código fuente debe ser accesible a usuarios
  - ✅ Cambios al código deben compartirse
  - ⚠️ Si modificas ListMonk y lo despliegas, debes proporcionar acceso al código fuente

---

## 🗂️ Estructura del Repositorio

```
eu-githubops/
│
├── 📄 README.md                              # Este archivo
├── 📄 BOOTSTRAP_ARGOCD_GUIDE.md              # Guía detallada de bootstrap de ArgoCD
├── 📄 ROOTAPP_GUIDE.md                       # Guía: Aplicar root app de ArgoCD
├── 📄 CLUSTERISSUER_GUIDE.md                 # Guía: Configurar ClusterIssuer para TLS
├── 📄 LISTMONK_SECRET_GUIDE.md               # Guía: Generar secretos de ListMonk
├── 📄 LOCALSTACK_GUIDE.md                    # Guía: Configurar LocalStack (AWS local)
├── 📄 LOCALSTACK_SECRET_GUIDE.md             # Guía: Secretos de LocalStack
├── 📄 LOCALSTACK_BOOTSTRAP_CHANGES.md        # Cambios en bootstrap para LocalStack
│
├── 🔧 infra/                                 # Infraestructura como código (IaC)
│   ├── bootstrap/                            # Scripts de bootstrap del cluster
│   │   ├── bootstrap_all.sh                  # ⭐ Ejecuta todos los pasos
│   │   ├── bootstrap_k3s.sh                  # Instala K3s base
│   │   ├── bootstrap_helm.sh                 # Instala Helm package manager
│   │   ├── bootstrap_ingress.sh              # Instala NGINX Ingress Controller
│   │   ├── bootstrap_certmanager.sh          # Instala Cert-Manager
│   │   ├── bootstrap_sealed_secrets.sh       # Instala Sealed Secrets
│   │   ├── bootstrap_argocd.sh               # Instala ArgoCD
│   │   └── bootstrap_clusterissuer.sh        # Configura ClusterIssuer para TLS
│   │
│   ├── argocd/                               # Configuración de ArgoCD
│   │   └── sealed-secrets/                   # Secretos sellados de ArgoCD
│   │       └── argocd-secret.yaml            # Credenciales admin (selladas)
│   │
│   ├── cert-manager/                         # Configuración de Cert-Manager
│   │   └── clusterissuer.yaml                # ClusterIssuer para CA privada
│   │
│   ├── grafana/                              # Configuración de Grafana
│   │   └── sealed-secrets/
│   │       └── grafana-admin.yaml            # Credenciales admin de Grafana (selladas)
│   │
│   ├── localstack/                           # Configuración de LocalStack (AWS local)
│   │   └── sealed-secrets/                   # Credenciales AWS (selladas)
│   │
│   ├── sealed-secrets/                       # Certificado público de Sealed Secrets
│   │   └── pub-cert.pem                      # Certificado para sellar secretos
│   │
│   ├── terraform/                            # IaC con Terraform (opcional)
│   │   └── localstack/
│   │       ├── main.tf                       # Recursos principales
│   │       ├── provider.tf                   # Proveedor (Terraform + LocalStack)
│   │       ├── remote_state.tf               # Estado remoto
│   │       └── variables.tf                  # Variables
│   │
│   └── values/                               # Valores de Helm para componentes
│       ├── argocd_values.yaml                # Configuración de ArgoCD
│       ├── cert_manager_values.yaml          # Configuración de Cert-Manager
│       ├── ingress_values.yaml               # Configuración de NGINX Ingress
│       ├── localstack_values.yaml            # Configuración de LocalStack
│       └── sealed_secrets_values.yaml        # Configuración de Sealed Secrets
│
├── 🎯 platform/                              # Aplicaciones de PLATAFORMA (gestionadas por ArgoCD)
│   ├── root-platform.yaml                    # ⭐ Root Application de plataforma
│   └── apps/                                 # Aplicaciones de infraestructura
│       ├── argo-rollouts/                    # Argo Rollouts controller
│       │   ├── application.yaml              # Aplicación ArgoCD
│       │   ├── ingress.yaml                  # Ingress (acceso Web UI)
│       │   └── values.yaml                   # Configuración Helm
│       │
│       ├── localstack/                       # AWS local para testing
│       │   ├── application.yaml              # Aplicación ArgoCD
│       │   ├── ingress.yaml                  # Ingress (acceso Web UI)
│       │   └── values.yaml                   # Configuración Helm
│       │
│       └── monitoring/                       # Stack de observabilidad
│           ├── alertmanager/                 # Gestor de alertas
│           ├── crds/                         # Custom Resource Definitions
│           ├── grafana/                      # Dashboards y visualización
│           ├── prometheus/                   # Recolector de métricas
│           └── */application.yaml y values.yaml
│
├── 📦 apps/                                  # Aplicaciones de USUARIO (gestionadas por ArgoCD)
│   ├── root-apps.yaml                        # ⭐ Root Application de apps usuario
│   └── applications/                         # Aplicaciones de usuario
│       └── listmonk/                         # 🎯 ListMonk: gestor de newsletters
│           ├── application.yaml              # Aplicación ArgoCD
│           ├── rollout.yaml                  # ⭐ Argo Rollout (Blue-Green)
│           ├── analysis.yaml                 # AnalysisTemplate para métricas
│           ├── service.yaml                  # Servicio principal
│           ├── service-preview.yaml          # Servicio preview (slot inactivo)
│           ├── ingress.yaml                  # Ingress con TLS (listmonk.local)
│           ├── secret.yaml                   # Secret para credenciales DB
│           └── README.md                     # Documentación de ListMonk
│
├── 🏛️ argocd-projects/                       # Proyectos de ArgoCD (RBAC)
│   ├── app_proyect.yaml                      # Proyecto para aplicaciones usuario
│   └── platform_proyect.yaml                 # Proyecto para aplicaciones plataforma
│
└── 🔨 scripts/                               # Scripts de utilidad
    ├── gen_root_plat.sh                      # Aplica root-platform.yaml
    ├── gen_argocd_secret.sh                  # Genera SealedSecret de ArgoCD
    ├── gen_grafana_secret.sh                 # Genera SealedSecret de Grafana
    ├── gen_listmonk_secret.sh                # Genera SealedSecret de ListMonk
    ├── gen_localstack_secret.sh              # Genera SealedSecret de LocalStack
    └── init_tfstate.sh                       # Inicializa estado de Terraform
```

---

## 🏗️ Arquitectura: Dos Capas de GitOps

Este repositorio implementa un **modelo de dos aplicaciones raíz** (multi-root):

### Capa 1: PLATFORM (Infraestructura)
```
root-platform.yaml
    ↓
    Sincroniza: platform/apps/
        ├── Argo Rollouts (deployment controller)
        ├── LocalStack (AWS local)
        └── Monitoring (Prometheus + Grafana + AlertManager)
```

**Responsabilidad**: Componentes de infraestructura y operaciones necesarios para que la plataforma funcione.

**Acceso**: `https://argo-rollouts.local` | `https://localstack.local` | Grafana en `monitoring` namespace

---

### Capa 2: APPS (Aplicaciones de Usuario)
```
root-apps.yaml
    ↓
    Sincroniza: apps/applications/
        └── listmonk/
            ├── Rollout (Blue-Green deployment)
            ├── AnalysisTemplate (validaciones automáticas)
            ├── Services + Ingress
            └── Secrets (credenciales DB)
```

**Responsabilidad**: Aplicaciones de negocio desplegadas y gestionadas por el usuario.

**Acceso**: `https://listmonk.local` (con TLS automático)

---

## 🚀 Flujo de Despliegue: Workflow Completo

El despliegue sigue un **flujo orquestado por GitHub Actions**. El orden es **crítico**:

### Paso 1️⃣: **Bootstrap del Cluster** (`bootstrap-cluster.yml`)
```bash
GitHub Actions Workflow "Bootstrap Cluster"
    ↓
    Ejecuta: infra/bootstrap/bootstrap_all.sh
        │
        ├─ bootstrap_k3s.sh
        │  └─ Instala: K3s, kubelet, kube-proxy, containerd
        │
        ├─ bootstrap_helm.sh
        │  └─ Instala: Helm package manager
        │
        ├─ bootstrap_ingress.sh
        │  └─ Instala: NGINX Ingress Controller (para enrutar tráfico HTTP/HTTPS)
        │
        ├─ bootstrap_certmanager.sh
        │  └─ Instala: Cert-Manager (para TLS automático)
        │
        ├─ bootstrap_sealed_secrets.sh
        │  └─ Instala: Sealed Secrets (para cifrar secretos en git)
        │  └─ Genera: infra/sealed-secrets/pub-cert.pem
        │
        └─ bootstrap_argocd.sh
           └─ Instala: ArgoCD v3.3.6
              └─ ArgoCD está listo para sincronizar aplicaciones
```

**Duración**: ~5-10 minutos  
**Salida**: Cluster K3s funcional con ArgoCD operativo

**Validar**:
```bash
kubectl get nodes
kubectl get pods -n argocd
# ArgoCD accesible en: https://localhost:8080 (port-forward requerido)
```

---

### Paso 2️⃣: **Bootstrap de ArgoCD** (`bootstrap-argocd.yml` - MANUAL)
```bash
GitHub Actions Workflow "Bootstrap ArgoCD"
    ├─ Prerequisites
    │  └─ Verifica: kubectl, helm, kubeseal, yq, htpasswd
    │
    ├─ Generate ArgoCD Sealed Secret
    │  ├─ Lee: ARGOCD_ADMIN_PASSWORD (desde GitHub Secrets)
    │  ├─ Ejecuta: scripts/gen_argocd_secret.sh
    │  ├─ Genera: infra/argocd/sealed-secrets/argocd-secret.yaml
    │  └─ Valida: YAML correcto, es un SealedSecret válido
    │
    ├─ Execute Bootstrap ArgoCD
    │  ├─ Crea namespace: argocd
    │  ├─ Agrega helm repo: https://argoproj.github.io/argo-helm
    │  └─ Instala: ArgoCD v3.3.6 con valores personalizados
    │
    ├─ Apply Sealed Secret
    │  └─ Aplica: infra/argocd/sealed-secrets/argocd-secret.yaml
    │     (Sealed Secrets controller lo desencripta automáticamente)
    │
    └─ Verify ArgoCD Installation
       ├─ Verifica: Namespace argocd existe
       ├─ Verifica: Helm release instalada
       └─ Salida: URL de acceso + instrucciones de login
```

**Requisitos previos**:
- ✅ Cluster K3s con `bootstrap_all.sh` completado
- ✅ Secret en GitHub: `ARGOCD_ADMIN_PASSWORD`
- ✅ Certificado Sealed Secrets: `infra/sealed-secrets/pub-cert.pem` generado

**Validar**:
```bash
# Port-forward para acceder a ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Acceder: https://localhost:8080
# Usuario: admin
# Contraseña: (la que creaste en ARGOCD_ADMIN_PASSWORD)
```

---

### Paso 3️⃣: **Aplicar Root Platform** (Manual: `./scripts/gen_root_plat.sh`)
```bash
Script: scripts/gen_root_plat.sh
    │
    ├─ Validaciones
    │  ├─ kubectl disponible
    │  ├─ Cluster accesible
    │  ├─ Namespace argocd existe
    │  └─ ArgoCD instalado
    │
    ├─ Aplicar: argocd-projects/platform_proyect.yaml
    │  └─ Crea: Proyecto de ArgoCD con RBAC para plataforma
    │
    ├─ Aplicar: platform/root-platform.yaml
    │  └─ ArgoCD comienza a sincronizar: platform/apps/
    │
    └─ Resultado:
       ├─ ✅ Argo Rollouts instalado
       ├─ ✅ LocalStack instalado
       ├─ ✅ Monitoring (Prometheus, Grafana, AlertManager) sincronizado
       └─ ArgoCD monitorea cambios en platform/ y sincroniza automáticamente
```

**Ejecutar**:
```bash
./scripts/gen_root_plat.sh
```

**Validar**:
```bash
kubectl get applications -n argocd
# Deberías ver: platform-root (Synced)
kubectl get pods -n argo-rollouts
kubectl get pods -n monitoring
```

---

### Paso 4️⃣: **Generar Secretos Sellados** (GitHub Actions o Manual)

#### 4a. Secret de ListMonk
```bash
GitHub Actions Workflow o Manual
    ├─ Requiere: GitHub Secret LISTMONK_DB_PASSWORD
    ├─ Ejecuta: scripts/gen_listmonk_secret.sh
    ├─ Genera: apps/applications/listmonk/secret.yaml (SealedSecret)
    └─ Commit+Push: Cambios a git
```

#### 4b. Secret de Grafana
```bash
GitHub Actions Workflow o Manual
    ├─ Requiere: GitHub Secret GRAFANA_ADMIN_PASSWORD
    ├─ Ejecuta: scripts/gen_grafana_secret.sh
    ├─ Genera: infra/grafana/sealed-secrets/grafana-admin.yaml
    └─ Commit+Push: Cambios a git
```

#### 4c. Secret de LocalStack (Opcional)
```bash
GitHub Actions Workflow o Manual
    ├─ Requiere: GitHub Secrets AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY
    ├─ Ejecuta: scripts/gen_localstack_secret.sh
    ├─ Genera: infra/localstack/sealed-secrets/localstack-credentials.yaml
    └─ Commit+Push: Cambios a git
```

**Ejecutar manualmente**:
```bash
# ListMonk
export LISTMONK_DB_PASSWORD="tu-contraseña-db"
./scripts/gen_listmonk_secret.sh

# Grafana
export GRAFANA_ADMIN_PASSWORD="tu-contraseña-grafana"
./scripts/gen_grafana_secret.sh
```

---

### Paso 5️⃣: **Aplicar Aplicaciones de Usuario** (Automático con ArgoCD)
```bash
Cuando platform/root-platform.yaml está sincronizado:
    
Script: scripts/gen_root_plat.sh (aplicación de apps)
    │
    ├─ Aplicar: argocd-projects/app_proyect.yaml
    │  └─ Crea: Proyecto de ArgoCD para aplicaciones usuario
    │
    ├─ Aplicar: apps/root-apps.yaml
    │  └─ ArgoCD comienza a sincronizar: apps/applications/
    │
    └─ Resultado:
       ├─ ✅ ListMonk Rollout creado
       ├─ ✅ AnalysisTemplate para métricas listo
       ├─ ✅ Blue-Green deployment activo
       └─ ArgoCD monitorea cambios en apps/ y sincroniza automáticamente
```

**Validar**:
```bash
kubectl get applications -n argocd
# Deberías ver: app-root (Synced)

kubectl get rollouts -n listmonk
# Deberías ver: listmonk (Healthy)

kubectl get ingress -n listmonk
# Deberías ver: listmonk con TLS automático
```

---

## 🌐 Acceso a Servicios y URLs

**⚠️ IMPORTANTE: Editar `/etc/hosts` con la IP del nodo K3s**

Obtén la IP del nodo K3s:
```bash
kubectl get nodes -o wide
# Copia la INTERNAL-IP o EXTERNAL-IP del nodo
```

Edita `/etc/hosts` (Linux/macOS) o `C:\Windows\System32\drivers\etc\hosts` (Windows):
```
<IP-DEL-NODO-K3S>  listmonk.local
<IP-DEL-NODO-K3S>  argo-rollouts.local
<IP-DEL-NODO-K3S>  localstack.local
<IP-DEL-NODO-K3S>  grafana.local
<IP-DEL-NODO-K3S>  prometheus.local
<IP-DEL-NODO-K3S>  argocd.local
```

### URLs de Servicios

| Servicio | URL | Namespace | Tipo |
|---|---|---|---|
| **ListMonk** | `https://listmonk.local` | listmonk | Ingress + TLS |
| **Argo Rollouts** | `https://argo-rollouts.local` | argo-rollouts | Ingress + TLS |
| **LocalStack** | `https://localstack.local` | localstack | Ingress + TLS |
| **Prometheus** | `https://prometheus.local` | monitoring | Ingress + TLS |
| **Grafana** | `https://grafana.local` | monitoring | Ingress + TLS |
| **ArgoCD** | `https://argocd.local` | argocd | Service (port-forward) |

### Acceso a ArgoCD (Port-Forward)
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Acceder: https://localhost:8080
# Usuario: admin
# Contraseña: (la que definiste en ARGOCD_ADMIN_PASSWORD)
```

---

## 🎯 ListMonk: Blue-Green Deployment con Argo Rollouts

ListMonk es desplegado con **estrategia Blue-Green** automática:

### Características

```yaml
Replicas: 2 (Blue) + 2 (Green) = 4 total

Blue Slot (Activo):
  └─ Service: listmonk (puerto 80 → 9000)
  └─ Recibe tráfico en: https://listmonk.local

Green Slot (Staging):
  └─ Service: listmonk-preview
  └─ Usado para análisis automático pre-promoción

Flujo de Despliegue:
  1. Nueva imagen llega a Green slot
  2. AnalysisTemplate ejecuta por 5 minutos
     ├─ Métrica: success-rate >= 95%
     ├─ Intervalo: 30 segundos
     ├─ Muestras requeridas: 10
     └─ Fallos permitidos: 3
  3. Si PASA análisis: Promoción automática a Blue
     └─ Green → Blue (tráfico redirigido)
  4. Si FALLA análisis: Rollback automático
     └─ Green descartado, Blue mantiene versión anterior
```

### Archivo: [rollout.yaml](apps/applications/listmonk/rollout.yaml)

```yaml
kind: Rollout
metadata:
  name: listmonk
  namespace: listmonk
spec:
  replicas: 2
  strategy:
    blueGreen:
      activeService: listmonk           # Blue (activo)
      previewService: listmonk-preview  # Green (staging)
      autoPromotionEnabled: true
      autoPromotionSeconds: 30          # Promover si análisis pasa
      prePromotionAnalysis:
        templates:
          - templateName: listmonk-success-rate
            args:
              duration: 5m
```

### Archivo: [analysis.yaml](apps/applications/listmonk/analysis.yaml)

```yaml
kind: AnalysisTemplate
metadata:
  name: listmonk-success-rate
spec:
  metrics:
    - name: success-rate
      interval: 30s
      count: 10                  # 10 muestras × 30s = 5 minutos
      failureLimit: 3            # Máximo 3 fallos permitidos
      successCriteria: result >= 95  # Éxito si rate >= 95%
      provider:
        prometheus:
          address: http://prometheus-monitoring:9090
          query: |
            sum(rate(http_requests_total{job="listmonk",status=~"2.."}[5m])) /
            sum(rate(http_requests_total{job="listmonk"}[5m])) * 100
```

### Monitorear Rollout

```bash
# Ver estado
kubectl get rollouts -n listmonk
kubectl describe rollout listmonk -n listmonk

# Ver análisis en tiempo real
kubectl describe analysisrun -n listmonk

# Logs de Argo Rollouts controller
kubectl logs -n argo-rollouts deployment/argo-rollouts -f
```

---

## 🔒 Seguridad: Secretos Sellados (Sealed Secrets)

Todos los secretos en git están **encriptados**:

```
infra/
├── argocd/sealed-secrets/argocd-secret.yaml          ← Encriptado
├── grafana/sealed-secrets/grafana-admin.yaml         ← Encriptado
└── localstack/sealed-secrets/localstack-creds.yaml   ← Encriptado

apps/
└── applications/listmonk/secret.yaml                  ← Encriptado
```

### Cómo Funciona

1. **Generación**: Script `gen_*_secret.sh` genera un `SealedSecret`
   ```bash
   echo -n 'password-secreto' | kubeseal -f - -n namespace > secret.yaml
   ```

2. **Git**: El `SealedSecret` se comitea (está encriptado, seguro)

3. **ArgoCD**: ArgoCD aplica el `SealedSecret`

4. **Sealed Secrets Controller**: Desencripta automáticamente en el cluster
   ```
   SealedSecret (encriptado en git)
        ↓
   Sealed Secrets Controller (en cluster)
        ↓
   Secret normal (desencriptado en memoria)
   ```

### GitHub Secrets Requeridos

Configura estos en: **Settings → Secrets and variables → Actions**

```
ARGOCD_ADMIN_PASSWORD           # Contraseña admin de ArgoCD
LISTMONK_DB_PASSWORD            # Contraseña de PostgreSQL para ListMonk
GRAFANA_ADMIN_PASSWORD          # Contraseña admin de Grafana
AWS_ACCESS_KEY_ID               # (Opcional) Para LocalStack
AWS_SECRET_ACCESS_KEY           # (Opcional) Para LocalStack
```

---

## 📊 Stack de Observabilidad

El repositorio incluye **Prometheus + Grafana + AlertManager**:

### Componentes

- **Prometheus** (`platform/apps/monitoring/prometheus/`)
  - Recolecta métricas de Kubernetes y aplicaciones
  - URL: `https://prometheus.local`
  - Consultas PromQL para análisis de ListMonk

- **Grafana** (`platform/apps/monitoring/grafana/`)
  - Dashboards de visualización
  - URL: `https://grafana.local`
  - Usuario: `admin`
  - Contraseña: (GitHub Secret `GRAFANA_ADMIN_PASSWORD`)

- **AlertManager** (`platform/apps/monitoring/alertmanager/`)
  - Gestión de alertas
  - Integración con webhooks, email, Slack, etc.

### Metrica de ListMonk

El AnalysisTemplate de ListMonk consulta Prometheus:
```promql
sum(rate(http_requests_total{job="listmonk",status=~"2.."}[5m])) /
sum(rate(http_requests_total{job="listmonk"}[5m])) * 100
```

Esto calcula el **porcentaje de requests exitosos** (status 2xx).

---

## ⚙️ Instalación Manual (Paso a Paso)

Si prefieres no usar los workflows de GitHub Actions:

### 1. Clonar Repositorio
```bash
git clone https://github.com/maypi72/eu-githubops.git
cd eu-githubops
```

### 2. Configurar Kubectl
```bash
# Asegúrate que KUBECONFIG apunta al cluster correcto
export KUBECONFIG=/path/to/k3s/kubeconfig.yaml
kubectl cluster-info
```

### 3. Ejecutar Bootstrap
```bash
# Opción A: Todo de una vez
./infra/bootstrap/bootstrap_all.sh

# Opción B: Paso a paso
./infra/bootstrap/bootstrap_k3s.sh
./infra/bootstrap/bootstrap_helm.sh
./infra/bootstrap/bootstrap_ingress.sh
./infra/bootstrap/bootstrap_certmanager.sh
./infra/bootstrap/bootstrap_sealed_secrets.sh
./infra/bootstrap/bootstrap_argocd.sh
```

### 4. Generar Secrets
```bash
# ListMonk
export LISTMONK_DB_PASSWORD="tu-password"
./scripts/gen_listmonk_secret.sh

# Grafana
export GRAFANA_ADMIN_PASSWORD="tu-password"
./scripts/gen_grafana_secret.sh

# ArgoCD (manual si no está generado)
export ARGOCD_ADMIN_PASSWORD="tu-password"
./scripts/gen_argocd_secret.sh
```

### 5. Aplicar Root Apps
```bash
# Platform
./scripts/gen_root_plat.sh

# Apps (modificar script si es necesario para app-root)
kubectl apply -f argocd-projects/app_proyect.yaml
kubectl apply -f apps/root-apps.yaml
```

### 6. Verificar Despliegue
```bash
kubectl get applications -n argocd
kubectl get rollouts -n listmonk
kubectl get ingress -A
```

---

## 🐛 Troubleshooting

### ArgoCD no sincroniza
```bash
# Verificar Application status
kubectl describe application platform-root -n argocd

# Verificar ArgoCD controller logs
kubectl logs -n argocd deployment/argocd-application-controller -f

# Forzar sincronización
argocd app sync platform-root
```

### ListMonk Rollout no promociona
```bash
# Ver análisis
kubectl describe analysisrun -n listmonk

# Ver logs de Argo Rollouts
kubectl logs -n argo-rollouts deployment/argo-rollouts -f

# Ver métricas en Prometheus
# Navega a: https://prometheus.local/graph?query=...
```

### Sealed Secrets: "cannot decrypt seal"
```bash
# Verificar certificado
kubectl get sealedsecrets -A
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Regenerar si es necesario
./infra/bootstrap/bootstrap_sealed_secrets.sh
```

### TLS certificate errors
```bash
# Verificar ClusterIssuer
kubectl describe clusterissuer mygitops-ca

# Verificar cert-manager
kubectl logs -n cert-manager deployment/cert-manager -f

# Ver certificados
kubectl get certificates -A
```

### ⚠️ ArgoCD UI: "Unable to load data - CORS/TLS Mismatch"

**Síntoma**: ArgoCD UI muestra error:
```
Unable to load data: Request has been terminated
Possible causes: the network is offline, Origin is not allowed by Access-Control-Allow-Origin, the page is being unloaded, etc.
```

**Causa raíz**: Mismatch entre protocolo del navegador → ingress → ArgoCD

ArgoCD automáticamente **activa HTTPS en puerto 8083** si detecta el secret `argocd-server-tls`, aunque tengas `server.insecure: true` configurado.

**Cascada de decisión de TLS en ArgoCD**:

1. ¿Existe secret `argocd-server-tls` con `tls.crt` + `tls.key`?
   - **SÍ** → ArgoCD activa HTTPS en 8083 automáticamente
   - **NO** → va al paso 2

2. ¿Existe secret `argocd-secret` con `tls.crt` + `tls.key`?
   - **SÍ** → ArgoCD activa HTTPS en 8083
   - **NO** → va al paso 3

3. ¿No hay certificados?
   - ArgoCD genera self-signed y respeta `server.insecure: true` → HTTP en 8080

**Solución**: Usar un nombre diferente para el secret del ingress

En [infra/values/argocd_values.yaml](infra/values/argocd_values.yaml):

```yaml
server:
  ingress:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: mygitops-ca
      nginx.ingress.kubernetes.io/backend-protocol: "HTTP"  # ← Conexión interna por HTTP
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
    tls:
      - secretName: argocd-tls  # ← ⭐ Nombre diferente a argocd-server-tls
        hosts:
          - argocd.local

params:
  server.insecure: "true"  # ← HTTP interno en 8080
```

**Por qué funciona**:
- **ingress** pide `argocd-tls` → cert-manager crea ese secret
- **ArgoCD busca** `argocd-server-tls` → no lo encuentra
- **ArgoCD respeta** `server.insecure: true` → usa HTTP
- **Resultado**: 
  - Cliente → Ingress: HTTPS ✅
  - Ingress → ArgoCD: HTTP ✅
  - Sin conflicto de protocolos → Sin CORS errors ✅

**Si el secret `argocd-server-tls` sigue recreándose**:

El Helm chart tiene hardcodeado ese nombre en el ingress. Sobrescribir con `kubectl patch`:

```bash
# Cambiar el nombre del secret en el ingress
kubectl patch ingress argocd-server -n argocd --type='json' \
  -p='[{"op": "replace", "path": "/spec/tls/0/secretName", "value": "argocd-tls"}]'

# Eliminar el secret antiguo
kubectl delete secret argocd-server-tls -n argocd

# cert-manager detectará el cambio y creará argocd-tls
kubectl get secrets -n argocd | grep argocd-tls
```

**Reference**: [Argo CD TLS Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/tls/)

---

## 📚 Documentación Adicional

- [ARGOCD_TLS_GUIDE.md](ARGOCD_TLS_GUIDE.md) - ⭐ **Solución TLS mismatch en ArgoCD UI**
- [BOOTSTRAP_ARGOCD_GUIDE.md](BOOTSTRAP_ARGOCD_GUIDE.md) - Guía detallada de ArgoCD
- [ROOTAPP_GUIDE.md](ROOTAPP_GUIDE.md) - Aplicar root-platform.yaml y root-apps.yaml
- [CLUSTERISSUER_GUIDE.md](CLUSTERISSUER_GUIDE.md) - Configurar TLS automático
- [LISTMONK_SECRET_GUIDE.md](LISTMONK_SECRET_GUIDE.md) - Generar secretos de ListMonk
- [LOCALSTACK_GUIDE.md](LOCALSTACK_GUIDE.md) - AWS local para testing
- [LOCALSTACK_SECRET_GUIDE.md](LOCALSTACK_SECRET_GUIDE.md) - Secretos de LocalStack

---

## 🤝 Contribuciones

Este es un laboratorio educativo. Siéntete libre de:
- ✅ Hacer fork y experimentar
- ✅ Reportar issues
- ✅ Sugerir mejoras

---

## 📄 Licencia

Este repositorio está bajo licencia **MIT**.

ListMonk (aplicación incluida) está bajo licencia **AGPL v3** (ver https://github.com/knadh/listmonk/blob/master/LICENSE)

---

**Hecho con ❤️ para laboratorios de GitOps y Cloud-Native**

# 3. Configuración de ClusterIssuers (opcional)
./infra/bootstrap/bootstrap_clusterissuer.sh
```

---

## Configuración de K3s

### Opciones de Instalación

K3s se instala con las siguientes opciones deshabilitando componentes innecesarios. Flannel está configurado como CNI por defecto:

```bash
K3S_EXEC_OPTS="--disable traefik --disable servicelb --write-kubeconfig-mode 644"
```

#### Significado de cada opción:

| Opción | Descripción |
|--------|-------------|
| `--disable traefik` | No instala Traefik (Ingress Controller integrado). Usamos NGINX via Helm |
| `--disable servicelb` | No instala klipper-lb (LoadBalancer simple) |
| `--write-kubeconfig-mode 644` | Genera kubeconfig con permisos 644 (legible sin `sudo`) |

### CNI: Flannel

**Flannel** es el Container Network Interface (CNI) incluido por defecto en K3s. Proporciona una red superpuesta simple y eficiente para la comunicación entre pods.

#### Características de Flannel

- ✅ Incluido por defecto en K3s (sin instalación adicional)
- ✅ Simple y ligero (ideal para clusters pequeños y medianos)
- ✅ Bajo overhead de recursos
- ✅ Fácil de configurar y mantener

#### Flujo de Instalación

1. **K3s Core**: Instala K3s con Flannel como CNI por defecto
2. **Helm**: Se instala para gestionar otros componentes
3. **NGINX Ingress**: Se despliega via Helm usando `infra/values/ingress_values.yaml`

#### Verificar instalación de Flannel

```bash
# Ver pods de Flannel
kubectl get pods -n kube-flannel

# Ver estado de nodos
kubectl get nodes

# Ver configuración de red
kubectl get pods -A -o wide
```

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

#### ⚠️ Certificado Público Requerido

**IMPORTANTE:** Para que ArgoCD y otros componentes funcionen correctamente con SealedSecrets, **debe existir** el certificado público del cluster en:

```
infra/sealed-secrets/pub-cert.pem
```

Este archivo contiene la clave pública de Sealed-Secrets y es **necesario para**:
- ✅ Sellar nuevos secrets en CI/CD (GitHub Actions)
- ✅ Generar el SealedSecret de ArgoCD (`infra/argocd/sealed-secrets/argocd-secret.yaml`)
- ✅ Que Sealed-Secrets pueda desencriptar los secretos en el cluster

##### Cómo crear el certificado

**Opción 1: Descargarlo del cluster (RECOMENDADO)**

```bash
# Desde tu máquina local con acceso al cluster:
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml  # o tu kubeconfig

# Descargar certificado
kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=kube-system \
  > infra/sealed-secrets/pub-cert.pem

# Verifyar que es válido
openssl x509 -in infra/sealed-secrets/pub-cert.pem -text -noout | head -10

# Hacer commit
git add infra/sealed-secrets/pub-cert.pem
git commit -m "chore: add sealed-secrets public certificate"
git push
```

**Opción 2: Generar automáticamente (desde el workflow)**

El workflow `bootstrap-argocd.yaml` intenta descargar automáticamente el certificado cuando:
- Se ejecuta con `fetch_cert = true` (es el valor por defecto)
- Sealed-Secrets está instalado en el cluster

```yaml
# En el workflow, se ejecutará automáticamente:
- name: Fetch Sealed-Secrets Certificate
  # Descargará: infra/sealed-secrets/pub-cert.pem
```

##### Verificar que el certificado es correcto

```bash
# 1. Verificar que existe
ls -lah infra/sealed-secrets/pub-cert.pem

# 2. Verificar que es un certificado X509 válido
openssl x509 -in infra/sealed-secrets/pub-cert.pem -noout

# 3. Ver información del certificado
openssl x509 -in infra/sealed-secrets/pub-cert.pem -text -noout | grep -A 2 "Subject:"

# 4. Verificar que coincide con el del cluster
kubectl get secret -n kube-system sealed-secrets-key -o jsonpath='{.data.tls\.crt}' | \
  base64 -d > /tmp/cluster-cert.pem && \
  diff infra/sealed-secrets/pub-cert.pem /tmp/cluster-cert.pem && \
  echo "✓ Certificados coinciden"
```

##### ¿Qué pasa si el certificado no existe o es inválido?

- ❌ El workflow `bootstrap-argocd.yaml` fallará al sellar el secreto
- ❌ ArgoCD no podrá desencriptar su contraseña de administrador
- ❌ El SealedSecret nunca se convertirá a un Secret normal

**Solución:** Ejecutar:
```bash
kubeseal --fetch-cert > infra/sealed-secrets/pub-cert.pem
git add infra/sealed-secrets/pub-cert.pem
git commit -m "chore: update sealed-secrets certificate"
git push
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

### Trivy-Operator

Trivy-Operator es un operador de seguridad para escanear vulnerabilidades y realizar auditorías de configuración en imágenes de contenedor y recursos del cluster.

#### Configuración Minimalista

**Scanners Activados**:
- ✅ **Vulnerability Scanning**: Escaneo de vulnerabilidades en imágenes de contenedor
- ✅ **Config Audit**: Auditoría de configuraciones de Kubernetes
- ❌ **Exposed Secrets**: Desactivado (optimización de recursos)
- ❌ **RBAC Assessment**: Desactivado
- ❌ **Infrastructure Assessment**: Desactivado
- ❌ **Cluster Compliance Report**: Desactivado

**Límites de Recursos**:

```yaml
# Operador
operator:
  resources:
    requests:
      cpu: 50m
      memory: 32Mi
    limits:
      cpu: 100m
      memory: 64Mi

# Scans de Trivy
trivy:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

#### Configuración de Escaneos

| Parámetro | Valor | Descripción |
|-----------|-------|-------------|
| **Severidades** | HIGH, CRITICAL | Ignora LOW y MEDIUM para reducir ruido |
| **Concurrencia** | 2 jobs | Máximo de escaneos simultáneos |
| **Revisiones** | Solo actuales | Evita escanear versiones antiguas |
| **Timeout** | 5m | Límite de tiempo por escaneo |
| **Modo** | Standalone | No requiere base de datos centralizada |

**Namespaces Excluidos**: 
```
kube-system, trivy-system, kube-public, kube-node-lease
```

#### Despliegue via ArgoCD

**Configuración**:
```yaml
Chart: aquasecurity.github.io/helm-charts/trivy-operator
Versión: 0.30.1
Namespace: trivy-system
Sincronización: Automática
```

**Archivos**:
- `platform/apps/trivy-operator/application.yaml` - Definición de la aplicación ArgoCD
- `platform/apps/trivy-operator/values.yaml` - Valores de Helm (referencia)

#### Acceder a Reportes de Escaneo

```bash
# Ver todos los reports de vulnerabilidades
kubectl get vulnerabilityreports -n trivy-system

# Ver detalles de un report específico
kubectl describe vulnerabilityreports -n trivy-system <pod-name>

# Ver reportes de auditoría de configuración
kubectl get configauditreports -n trivy-system

# Ver detalles de auditoría
kubectl describe configauditreports -n trivy-system <resource-name>

# Filtrar por namespace
kubectl get vulnerabilityreports --all-namespaces

# Exportar reportes en JSON
kubectl get vulnerabilityreports -n trivy-system -o json > vuln-reports.json
```

#### Ejemplos de Queries

```bash
# Ver vulnerabilidades críticas
kubectl get vulnerabilityreports -n trivy-system -o json | \
  jq '.items[].report.vulnerabilities[] | select(.severity == "CRITICAL")'

# Ver imágenes con vulnerabilidades
kubectl get vulnerabilityreports -n trivy-system -o json | \
  jq '.items[] | {name: .metadata.name, image: .report.artifact.ref}'

# Contar vulnerabilidades por severidad
kubectl get vulnerabilityreports -n trivy-system -o json | \
  jq '[.items[].report.vulnerabilities[].severity] | group_by(.) | map({severity: .[0], count: length})'
```

#### Personalización Adicional

Para cambiar la configuración después del despliegue, edita los valores inline en:

```bash
# Editar la aplicación de ArgoCD
kubectl patch application trivy-operator -n argocd --type merge -p '{
  "spec": {
    "source": {
      "helm": {
        "values": "..."
      }
    }
  }
}'
```

O modifica directamente en `platform/apps/trivy-operator/application.yaml` y sincroniza con ArgoCD.

---
## Stack de Observabilidad

Esta sección cubre la configuración e instalación de componentes de observabilidad para monitoreo y visualización del cluster.

### Grafana

**Grafana** es una plataforma de visualización de datos de código abierto que proporciona dashboards para monitorear métricas, logs y trazas del cluster Kubernetes.

#### Preparación Previa al Despliegue

Antes de desplegar el stack de observabilidad, es necesario generar y configurar el SealedSecret de Grafana con las credenciales del usuario administrador.

##### Paso 1: Generar el SealedSecret de Grafana

El script `scripts/gen_grafana_secret.sh` crea un SealedSecret encriptado con las credenciales de Grafana. Este script:

1. Requiere que **Sealed Secrets esté instalado** en el cluster
2. Descarga o utiliza el certificado público de Sealed Secrets
3. Genera un hash bcrypt de la contraseña del admin
4. Crea un SealedSecret encriptado

**Prerrequisitos**:
- ✅ `kubectl` configurado y funcionando
- ✅ Cluster Kubernetes con **sealed-secrets** instalado (ejecutar `bootstrap_sealed_secrets.sh` primero)
- ✅ Herramientas instaladas: `kubeseal`, `openssl`, `base64`, `htpasswd`
- ✅ Variable de entorno `GRAFANA_ADMIN_PASSWORD` configurada

##### Paso 2: Opción A - Ejecutar el Script Localmente

```bash
# Desde la raíz del repositorio:
export GRAFANA_ADMIN_PASSWORD="tu-contraseña-segura"
./scripts/gen_grafana_secret.sh

# O con descarga de certificado del cluster:
export GRAFANA_ADMIN_PASSWORD="tu-contraseña-segura"
FETCH_CERT=true ./scripts/gen_grafana_secret.sh
```

**Salida esperada**:
```
✓ Secreto sellado de Grafana generado correctamente

Archivos actualizados:
  📄 infra/grafana/sealed-secrets/grafana-admin.yaml
  📄 infra/sealed-secrets/pub-cert.pem

🚀 Próximos pasos:
  • Secreto listo para ser aplicado al cluster
  • El namespace 'grafana' será creado automáticamente al desplegar
```

##### Paso 3: Opción B - Usar Workflow de GitHub Actions (Recomendado)

Se proporciona un workflow independiente para generar el SealedSecret de forma remota y automatizada:

**Archivo**: [.github/workflows/gen-grafana-secret.yml](.github/workflows/gen-grafana-secret.yml)

**Requisitos previos**:
- El secreto `GRAFANA_ADMIN_PASSWORD` debe estar configurado en GitHub
  - Ve a **Settings → Secrets and variables → Actions**
  - Crea un nuevo secreto llamado `GRAFANA_ADMIN_PASSWORD`
  - Ingresa la contraseña de admin para Grafana

**Procedimiento**:

1. **Configurar el secreto en GitHub** (una sola vez):
   - Ve a **Settings → Secrets and variables → Actions**
   - Click en **"New repository secret"**
   - Nombre: `GRAFANA_ADMIN_PASSWORD`
   - Valor: Tu contraseña de admin para Grafana
   - Click **"Add secret"**

2. **Ejecutar el workflow**:
   - Ve a **Actions → Generate Grafana Secret**
   - Click en **"Run workflow"**
   - Aparecerá un formulario con solo una opción:
     - **📥 Descargar certificado del cluster** (checkbox):
       - ☐ No marcar si sealed-secrets ya está instalado (usará certificado local)
       - ☑ Marcar si quieres descargar el certificado del cluster (recomendado después de instalar)

3. **Dejar que se ejecute**:
   - El workflow:
     - Obtiene automáticamente la contraseña del secreto de GitHub Actions
     - Descarga el kubeconfig del último artifact de bootstrap
     - Ejecuta `scripts/gen_grafana_secret.sh` automáticamente
     - Verifica que el SealedSecret se generó correctamente
     - Hace commit y push de los cambios
     - Actualiza el certificado público si es necesario

**Ventajas del Workflow**:
- ✅ No requiere escribir contraseña cada vez
- ✅ Usa secreto de GitHub de forma segura (no visible en logs)
- ✅ No requiere ejecutar scripts localmente
- ✅ Ejecuta en el runner de GitHub (ambiente controlado)
- ✅ Usa kubeconfig del último bootstrap automáticamente
- ✅ Commit y push automático
- ✅ Auditado en GitHub Actions logs
- ✅ Protegido por environment rules

#### Estructura de Archivos

```
infra/
└── grafana/
    ├── sealed-secrets/
    │   └── grafana-admin.yaml              # SealedSecret (encriptado)
    └── values.yaml                         # Valores de Helm para Grafana (por crear)

platform/
└── apps/
    └── grafana/                            # (por crear)
        ├── application.yaml                # Definición de ArgoCD
        └── values.yaml                     # Configuración de Grafana
```

#### Configuración de Grafana

**Parámetros Principales**:

| Parámetro | Valor | Descripción |
|-----------|-------|-------------|
| **Namespace** | `grafana` | Espacio dedicado para Grafana |
| **Replicas** | 1 | Una instancia de Grafana |
| **Persistencia** | PVC | Almacenamiento persistente para dashboards |
| **Ingress** | Habilitado | Acceso HTTP/HTTPS externo |
| **Resources** | Límites | CPU: 200m, RAM: 256Mi |

**Admin Credentials**:
- **Usuario**: `admin` (almacenado en SealedSecret)
- **Contraseña**: Encriptada en `grafana-admin.yaml`

#### Acceder a Grafana

```bash
# 1. Ver el servicio
kubectl get svc -n grafana

# 2. Portforward (si no tiene Ingress)
kubectl port-forward -n grafana svc/grafana 3000:80

# 3. Acceder en el navegador
# http://localhost:3000
# Usuario: admin
# Contraseña: (la que configuraste en GRAFANA_ADMIN_PASSWORD)
```

#### Dashboards Recomendados

Grafana viene con dashboards preconfigurados:

1. **Kubernetes Cluster Monitoring** - Métricas generales del cluster
2. **Pod Monitoring** - Detalles de pods individuales
3. **Node Exporter** - Métricas de nodos
4. **Prometheus Stats** - Estado de Prometheus

#### Fuentes de Datos

Grafana se conecta automáticamente a:

1. **Prometheus** - Métricas del cluster
2. **Loki** (opcional) - Agregación de logs
3. **Jaeger** (opcional) - Tracing distribuido

#### Troubleshooting

```bash
# Ver logs de Grafana
kubectl logs -n grafana -f deployment/grafana

# Verificar SealedSecret
kubectl get sealedsecret -n grafana

# Verificar Secret desencriptado
kubectl get secret -n grafana grafana-admin -o yaml

# Resetear contraseña de admin
kubectl exec -n grafana deployment/grafana -- grafana-cli admin reset-admin-password nueva-contraseña
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
