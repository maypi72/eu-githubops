# 🔐 ArgoCD TLS Configuration Guide

## Problema: UI Error - "Unable to load data"

### Síntoma
```
Unable to load data: Request has been terminated
Possible causes: the network is offline, Origin is not allowed by Access-Control-Allow-Origin, the page is being unloaded, etc.
```

Las solicitudes XHR a ArgoCD fallan con errores CORS o conexión rechazada cuando accedes a `https://argocd.local`.

---

## Causa Raíz: TLS Mismatch

ArgoCD tiene un **mecanismo automático de detección de TLS** que busca específicamente el secret `argocd-server-tls`. Si lo encuentra, **activa HTTPS automáticamente** sin importar la configuración.

### El Conflicto

```
┌─────────────────────────────────────────────────────────────┐
│                  NAVEGADOR (HTTPS)                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ HTTPS request
                     ↓
┌─────────────────────────────────────────────────────────────┐
│         NGINX INGRESS (mygitops-ca cert)                    │
│                                                              │
│  Listening: HTTPS (443)                                     │
│  Forwarding to backend: http://argocd-server:80             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ HTTP request
                     ↓
┌─────────────────────────────────────────────────────────────┐
│              ArgoCD Server Pod                              │
│                                                              │
│  If argocd-server-tls exists:                              │
│    ├─ HTTPS listening on :8083 ✅                          │
│    └─ Expecting: HTTP://localhost:443 from ingress ❌     │
│                                                              │
│  If argocd-server-tls NOT found:                           │
│    ├─ HTTP listening on :8080 ✅                           │
│    └─ Expecting: HTTP from ingress ✅                       │
└─────────────────────────────────────────────────────────────┘
```

**Cuando `argocd-server-tls` existe**:
- ArgoCD activa HTTPS en puerto 8083
- Ingress intenta conectar por HTTP a puerto 8080
- **Conexión rechazada** → CORS error en UI

---

## TLS Decision Cascade in ArgoCD

ArgoCD busca certificados en este **orden de prioridad**:

### 1. `argocd-server-tls` Secret (Recomendado)
```yaml
Kind: Secret
apiVersion: v1
metadata:
  name: argocd-server-tls
  namespace: argocd
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-certificate>
  tls.key: <base64-encoded-key>
```

**Si existe**: ArgoCD **automáticamente** activa HTTPS en puerto 8083
- Hot-reload soportado (sin reinicio)
- Cambios de certificado se aplican en vivo

### 2. `argocd-secret` Secret (Deprecated)
```yaml
Kind: Secret
apiVersion: v1
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
data:
  tls.crt: <base64-encoded-certificate>
  tls.key: <base64-encoded-key>
```

**Si existe**: ArgoCD usa este certificado
- Requiere reinicio para cambios

### 3. Auto-generated Self-signed
```
Si NO existe ninguno de los anteriores:
  ├─ ArgoCD genera auto-signed certificate
  ├─ Guarda en: argocd-secret
  └─ Respeta: server.insecure parameter
```

**Parámetro `server.insecure: true`**:
```yaml
params:
  server.insecure: "true"
```

**Comportamiento**:
- Solo se respeta si NO existe `argocd-server-tls`
- Desactiva TLS completamente → HTTP en puerto 8080
- No genera certificados automáticos

---

## Solución Correcta: Nombres Diferentes

La solución es usar **un nombre de secret diferente a `argocd-server-tls`** en el ingress:

### Paso 1: Actualizar argocd_values.yaml

```yaml
# infra/values/argocd_values.yaml

server:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: mygitops-ca
      nginx.ingress.kubernetes.io/backend-protocol: "HTTP"  # ← HTTP interno
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    hosts:
      - argocd.local
    paths:
      - /
    pathType: Prefix
    tls:
      - secretName: argocd-tls  # ← ⭐ DIFERENTE a argocd-server-tls
        hosts:
          - argocd.local

params:
  server.insecure: "true"  # ← HTTP en puerto 8080
```

**¿Por qué `argocd-tls`?**
- cert-manager crea `argocd-tls` (porque el ingress lo pide)
- ArgoCD busca `argocd-server-tls` → no lo encuentra
- ArgoCD respeta `server.insecure: true` → HTTP puro

### Paso 2: Parchear el Ingress (si ya está creado)

El Helm chart tiene hardcodeado `argocd-server-tls`. Si no se actualiza automáticamente:

```bash
# Sobrescribir el nombre del secret en el ingress
kubectl patch ingress argocd-server -n argocd --type='json' \
  -p='[{"op": "replace", "path": "/spec/tls/0/secretName", "value": "argocd-tls"}]'

# Verificar el cambio
kubectl get ingress argocd-server -n argocd -o yaml | grep -A 5 "tls:"
```

Salida esperada:
```yaml
tls:
- hosts:
  - argocd.local
  secretName: argocd-tls  # ✅ Correcto
```

### Paso 3: Eliminar Secret Antiguo

```bash
# Eliminar argocd-server-tls si existe
kubectl delete secret argocd-server-tls -n argocd 2>/dev/null || true

# cert-manager detectará que falta y creará argocd-tls automáticamente
sleep 5
kubectl get secrets -n argocd | grep argocd-tls
```

Salida esperada:
```
argocd-tls                     kubernetes.io/tls    3      10s
```

### Paso 4: Redeploy ArgoCD

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Desinstalar
helm uninstall argocd -n argocd

# Reinstalar con valores actualizados
./infra/bootstrap/bootstrap_argocd.sh

# O si ya está instalado, upgrade
helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --values infra/values/argocd_values.yaml \
  --wait
```

### Paso 5: Reiniciar Pods

```bash
# Reiniciar ArgoCD server para aplicar cambios
kubectl rollout restart deployment/argocd-server -n argocd

# Esperar a que esté ready
kubectl get pods -n argocd -w
```

---

## Flujo de Conexión Resultante

```
┌─────────────────────────────────────────────────────────────┐
│                  NAVEGADOR (HTTPS)                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ HTTPS request
                     │ (usando cert: argocd-tls)
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  NGINX INGRESS (cert-manager: mygitops-ca)                 │
│                                                              │
│  Listening: HTTPS 443                                       │
│  TLS Secret: argocd-tls ✅                                 │
│  Forwarding: HTTP → argocd-server:80                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ HTTP request
                     ↓
┌─────────────────────────────────────────────────────────────┐
│              ArgoCD Server Pod                              │
│                                                              │
│  server.insecure: true ✅                                   │
│  No argocd-server-tls found ✅                             │
│  Listening: HTTP on :8080 ✅                               │
│                                                              │
│  ✅ CONEXIÓN EXITOSA                                       │
└─────────────────────────────────────────────────────────────┘

UI available at: https://argocd.local ✅
```

---

## Alternativa: TLS Completo (Más Seguro)

Si quieres **HTTPS en todas partes** (navegador → ingress → ArgoCD):

```yaml
# infra/values/argocd_values.yaml

server:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"  # ← HTTPS interno
      # ... resto de anotaciones
    tls:
      - secretName: argocd-server-tls  # ← DEBE ser este nombre exacto
        hosts:
          - argocd.local

params:
  server.insecure: "false"  # ← HTTPS en puerto 8083
```

**Ventajas**:
- ✅ Encriptación end-to-end
- ✅ Mayor seguridad
- ✅ ArgoCD detecta automáticamente `argocd-server-tls`

**Desventajas**:
- ⚠️ Requiere validación de certificados auto-firmados
- ⚠️ Más complejo de debuggear
- ⚠️ Necesitas configurar `strictTLS: false` si usas self-signed

---

## Debugging: Verificar Estado Actual

### Ver qué secrets existen
```bash
kubectl get secrets -n argocd | grep -E "tls|secret"
```

### Ver configuración de Helm aplicada
```bash
helm get values argocd -n argocd | grep -B 5 -A 5 "secretName"
```

### Ver configuración del ingress actual
```bash
kubectl get ingress argocd-server -n argocd -o yaml
```

### Ver qué parámetros tiene ArgoCD
```bash
kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml | grep -i insecure
```

### Ver logs de ArgoCD server
```bash
kubectl logs -n argocd deployment/argocd-server -f | grep -i "tls\|insecure\|port"
```

### Ver logs de cert-manager
```bash
kubectl logs -n cert-manager deployment/cert-manager -f | grep argocd
```

---

## Tabla de Configuraciones

| Config | Backend Protocol | server.insecure | argocd-server-tls | Resultado |
|--------|------------------|-----------------|-------------------|-----------|
| ✅ HTTP Puro | HTTP | true | NO | HTTP 8080 ✅ |
| ✅ HTTPS Externo | HTTP | true | `argocd-tls` | HTTPS→HTTP ✅ |
| ⚠️ Mismatch | HTTP | true | `argocd-server-tls` | HTTP→HTTPS ❌ |
| ✅ HTTPS Completo | HTTPS | false | `argocd-server-tls` | HTTPS→HTTPS ✅ |

---

## Reference

- **Official Docs**: https://argo-cd.readthedocs.io/en/stable/operator-manual/tls/
- **Secret Types**: https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets
- **cert-manager**: https://cert-manager.io/
- **NGINX Annotations**: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/

---

**Última actualización**: May 4, 2026
**Estado**: ✅ Verified and working
