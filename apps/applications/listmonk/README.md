# ListMonk - Argo Rollouts Blue-Green Deployment

## 📋 Descripción

Este despliegue configura **ListMonk** con:
- ✅ **Argo Rollouts**: Estrategia Blue-Green
- ✅ **Cert-Manager**: TLS con mygitops-ca
- ✅ **GHCR**: Imagen desde GitHub Container Registry
- ✅ **Análisis Automático**: Promoción basada en métricas

## 📁 Archivos

```
listmonk/
├── application.yaml      # Aplicación ArgoCD
├── deployment.yaml       # Rollout con estrategia blue-green
├── service.yaml          # Servicio para Rollout
├── ingress.yaml          # Ingress con cert-manager (mygitops-ca)
├── analysis.yaml         # AnalysisTemplate para validaciones
├── secret.yaml           # Secret para credenciales DB
└── README.md             # Este archivo
```

## 🚀 Características

### Blue-Green Deployment
- **2 replicas** activas
- Promoción automática después de **30 segundos**
- Análisis de **success rate** desde Prometheus
- **Rollback automático** si falla validación

### Probes
- **Readiness**: HTTP GET a `/` (10s delay)
- **Liveness**: HTTP GET a `/` (30s delay)

### Networking
- **Service**: ClusterIP en puerto 80 → 9000
- **Ingress**: `listmonk.local` con TLS (cert-manager)
- **TLS**: Certificado automático con mygitops-ca

### Imagen
- **Imagen**: `ghcr.io/maypi72/listmonk:latest`
- **Pull Policy**: `Always` (siempre obtiene latest)

## 🔧 Configuración

### 1. Actualizar Secret (IMPORTANTE)

Editar `secret.yaml` y cambiar la contraseña:

```bash
# Opción 1: Secret normal (no recomendado para producción)
kubectl apply -f secret.yaml

# Opción 2: SealedSecret (recomendado)
echo -n 'tu-password' | kubeseal -f - -n listmonk > secret.yaml
```

### 2. Base de Datos

El deployment espera una PostgreSQL en `postgres.default.svc.cluster.local`.

Si no tienes DB:
```bash
# Instalar Postgres (ejemplo con Helm)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgres bitnami/postgresql -n default
```

### 3. Desplegar

ArgoCD sincronizará automáticamente una vez committed a git:

```bash
git add apps/applications/listmonk/
git commit -m "feat: add listmonk with blue-green deployment"
git push origin main
```

O desplegar manualmente:
```bash
kubectl apply -f apps/applications/listmonk/
```

## 📊 Monitoreo

### Ver estado de Rollout
```bash
kubectl get rollout -n listmonk
kubectl describe rollout listmonk -n listmonk
```

### Ver Ingress
```bash
kubectl get ingress -n listmonk
# Debería tener certificado TLS automático
```

### Ver análisis automático
```bash
kubectl get analysisrun -n listmonk
```

### Logs
```bash
kubectl logs -n listmonk -l app=listmonk -f
```

## 🔄 Blue-Green Workflow

1. **Nueva versión** se despliega en slot "green"
2. **Espera 30 segundos** (autoPromotionSeconds)
3. **Ejecuta análisis** (success rate desde Prometheus)
4. Si **success rate > 95%**: promociona green → blue
5. Si **falla**: mantiene blue activo, elimina green

## 🔐 Cert-Manager

El Ingress usa `mygitops-ca` ClusterIssuer:
- Certificado: `/etc/nginx/secrets/listmonk-tls`
- Auto-renovación: cada 90 días
- Hostname: `listmonk.local`

## ⚠️ Configuración Recomendada

### Para Producción
1. **Usar SealedSecret** para la contraseña DB
2. **Aumentar replicas** a 3-4
3. **Aumentar autoPromotionSeconds** a 5m
4. **Agregar métricas reales** en `analysis.yaml`
5. **Usar hostname real** (no `.local`)

### Para Desarrollo
- 1-2 replicas está bien
- Secret normal es aceptable
- autoPromotionSeconds = 30s es rápido

## 📝 Ejemplo: Agregar Secrets Sellados

```bash
# Crear secret normal
kubectl create secret generic listmonk-db \
  --from-literal=password='tu-password' \
  -n listmonk --dry-run=client -o yaml > secret-raw.yaml

# Sellar con kubeseal
kubeseal -f secret-raw.yaml > secret.yaml

# Eliminar raw
rm secret-raw.yaml
```

## 🔗 Referencias

- [Argo Rollouts Blue-Green](https://argoproj.github.io/argo-rollouts/features/bluegreen/)
- [ListMonk](https://listmonk.app/)
- [Cert-Manager](https://cert-manager.io/)
