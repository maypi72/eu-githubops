# ClusterIssuer Autofirmado de cert-manager para ArgoCD

## Resumen

Se ha configurado un **ClusterIssuer autofirmado** que genera certificados SSL/TLS internamente para ArgoCD usando cert-manager, sin depender de autoridades externas como Let's Encrypt.

## Estructura de Archivos

```
infra/
├── cert-manager/
│   └── clusterissuer.yaml          # Definición de Certificate + ClusterIssuer autofirmado
├── bootstrap/
│   ├── bootstrap_clusterissuer.sh   # Script para crear CA y ClusterIssuer
│   ├── bootstrap_all.sh             # Orquestador (actualizado)
│   └── ...
└── values/
    └── argocd_values.yaml           # Values con configuración de TLS autofirmado
```

## Flujo de Ejecución

El `bootstrap_all.sh` ejecuta los scripts en este orden:

1. ✅ **bootstrap_k3s.sh** - Instala K3s
2. ✅ **bootstrap_helm.sh** - Instala Helm
3. ✅ **bootstrap_ingress.sh** - Instala Ingress Controller (NGINX)
4. ✅ **bootstrap_certmanager.sh** - Instala cert-manager
5. ✅ **bootstrap_clusterissuer.sh** - Crea CA y ClusterIssuer autofirmados (nuevo)
6. ✅ **bootstrap_sealed_secrets.sh** - Instala Sealed Secrets
7. ✅ **bootstrap_argocd.sh** - Instala ArgoCD (usa el certificado autofirmado)

## Componentes del ClusterIssuer Autofirmado

### Archivo: `infra/cert-manager/clusterissuer.yaml`

El archivo contiene 3 recursos:

#### 1. **Certificate (CA Raíz Autofirmada)**

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mygitops-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: mygitops-ca
  secretName: mygitops-ca-key
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
```

**Características:**
- ✅ Crea una Autoridad Certificadora (CA) autofirmada
- ✅ Almacena la clave privada en Secret: `selfsigned-ca-key`
- ✅ Válida para toda la vida del cluster

#### 2. **Issuer (Emisor Autofirmado)**

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: cert-manager
spec:
  selfSigned: {}
```

**Características:**
- ✅ Issuer namespaced para crear la CA raíz
- ✅ Usa el método `selfSigned` (más seguro que SelfSignedIssuer deprecated)

#### 3. **ClusterIssuer (Usar la CA para firmar certificados)**

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: mygitops-ca
spec:
  ca:
    secretName: mygitops-ca-key
```

**Características:**
- ✅ ClusterIssuer que usa la CA para firmar certificados en todo el cluster
- ✅ Referenciado por Ingress de ArgoCD
- ✅ Genera certificados "confiables internamente"

### Script: `infra/bootstrap/bootstrap_clusterissuer.sh`

**Características de idempotencia:**
- ✅ Verifica si el ClusterIssuer ya existe (no falla si ya está creado)
- ✅ Valida que cert-manager está instalado antes de proceder
- ✅ **Espera a que el Certificate (CA) esté Ready primero**
- ✅ Luego verifica que el ClusterIssuer esté Ready
- ✅ Manejo robusto de errores

**Validaciones:**
```bash
✓ Comprueba que KUBECONFIG existe
✓ Verifica que cert-manager está instalado
✓ Valida que el archivo clusterissuer.yaml existe
✓ Espera a que Certificate esté Ready (max 60 seg)
✓ Espera a que ClusterIssuer esté Ready (max 30 seg)
```

## Configuración de ArgoCD

### Archivo: `infra/values/argocd_values.yaml`

Se ha configurado Ingress para usar el ClusterIssuer autofirmado:

```yaml
server:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: "mygitops-ca"  # ← ClusterIssuer autofirmado
    hosts:
      - argocd.local
    tls:
      - secretName: argocd-tls
        hosts:
          - argocd.local
```

**Cómo funciona:**
1. La anotación `cert-manager.io/cluster-issuer: selfsigned-ca` indica al webhook de cert-manager que debe procesar este Ingress
2. cert-manager **automáticamente** crea un recurso `Certificate` para este Ingress
3. El `Certificate` es firmado por el `ClusterIssuer selfsigned-ca`
4. El certificado se almacena en el Secret `argocd-tls`
5. El Ingress usa este Secret para servir HTTPS

## Ventajas de Certificados Autofirmados

| Aspecto | Autofirmado | Let's Encrypt |
|---------|-------------|-----------------|
| **Validez Externa** | ⚠️ No confiable externamente | ✅ Confiable globalmente |
| **Configuración** | ✅ Muy simple | ❌ Requiere DNS/email |
| **Rate Limiting** | ✅ Sin límites | ⚠️ Límite de solicitudes |
| **Renovación** | ✅ Automática inmediata | ⚠️ Solo 90 días válidos |
| **Uso Ideal** | 🏢 Habientes privadas/lab | 🌐 Producción pública |
| **Acceso Externo** | ⚠️ Advertencia SSL | ✅ SSL confiable |

## Ejecutar Todo

### Opción 1: Script completo (Recomendado)

```bash
cd /path/to/eu-githubops/infra/bootstrap
chmod +x bootstrap_all.sh
./bootstrap_all.sh
```

### Opción 2: Script individual (Solo ClusterIssuer)

```bash
cd /path/to/eu-githubops/infra/bootstrap
chmod +x bootstrap_clusterissuer.sh
./bootstrap_clusterissuer.sh
```

## Verificar el Estado

### Ver componentes creados

```bash
# Ver el Issuer (namespaced)
kubectl get issuer -n cert-manager

# Ver el ClusterIssuer
kubectl get clusterissuer

# Ver el Certificate (CA)
kubectl get certificate -n cert-manager
```

### Ver la CA que se creó

```bash
# Ver detalles de la CA
kubectl describe certificate -n cert-manager mygitops-ca

# Ver el Secret donde se almacena la CA
kubectl get secret -n cert-manager mygitops-ca-key -o yaml
```

### Ver Certificado Generado para ArgoCD

```bash
# Ver el Certificate generado automáticamente para Ingress
kubectl get certificate -n argocd

# Ver detalles
kubectl describe certificate -n argocd argocd-tls

# Ver el Secret TLS
kubectl get secret -n argocd argocd-tls -o yaml
```

### Ver Información del Certificado

```bash
# Extraer y ver el certificado en formato legible
kubectl get secret -n argocd argocd-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout

# Ver solo las fechas de validez
kubectl get secret -n argocd argocd-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates
```

### Ver Ingress de ArgoCD

```bash
# Ver Ingress
kubectl get ingress -n argocd

# Ver detalles completos
kubectl describe ingress -n argocd argocd-server
```

## Solución de Problemas

### El Certificate (CA) no está en estado "Ready"

```bash
# Ver logs de cert-manager
kubectl logs -n cert-manager -l app=cert-manager -f

# Ver eventos
kubectl describe certificate -n cert-manager selfsigned-ca
```

**Causas comunes:**
- ❌ cert-manager no está completamente listo
- ❌ Permisos insuficientes

### El ClusterIssuer no está en estado "Ready"

```bash
# Verificar estado
kubectl describe clusterissuer mygitops-ca

# Ver logs de cert-manager
kubectl logs -n cert-manager -l app=cert-manager -f
```

### El Certificado de ArgoCD no se crea automáticamente

```bash
# Verificar que la anotación está presente
kubectl get ingress -n argocd argocd-server -o yaml | grep cert-manager

# Ver eventos del Ingress
kubectl describe ingress -n argocd argocd-server
```

**Causas comunes:**
- ❌ El ClusterIssuer no está en Ready
- ❌ La anotación no es exacta
- ❌ El webhook de cert-manager no está activado

### Advertencia SSL al acceder a https://argocd.local

Esto es **NORMAL** con certificados autofirmados. El navegador muestra advertencia porque:
- ✓ El certificado es válido técnicamente
- ⚠️ No está firmado por una autoridad confiable del sistema

**Soluciones:**
1. 🧪 En laboratorio: Hacer clic en "Avanzado" → "Continuar"
2. 🏢 En navegadores corporativos: Importar la CA a la tienda de certificados

### Cómo obtener y confiar en la CA

```bash
# Extraer el certificado CA
kubectl get secret -n cert-manager mygitops-ca-key -o jsonpath='{.data.tls\.crt}' | \
  base64 -d > /tmp/argocd-ca.crt

# Ver el certificado
cat /tmp/argocd-ca.crt

# Linux (Debian/Ubuntu): Copiar a ubicación confiable
sudo cp /tmp/argocd-ca.crt /usr/local/share/ca-certificates/argocd-ca.crt
sudo update-ca-certificates

# macOS: Agregar a Keychain
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/argocd-ca.crt
```

## Renovación de Certificados

Los certificados autofirmados creados por cert-manager se renuevan **automáticamente**:

```bash
# Ver cuándo expira el certificado
kubectl get secret -n argocd argocd-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates
```

**Características:**
- ✅ cert-manager renueva certificados automáticamente 30 días antes de expirar
- ✅ No requiere intervención
- ✅ No hay límites de renovación

## Notas Importantes

⚠️ **Configuración Actual: Autofirmado (Privado)**

La configuración actual:
- ✅ Usa certificados autofirmados (internos)
- ✅ No requiere conexión a servicios externos
- ✅ Ideal para laboratorio y ambientes privados
- ⚠️ No confiable para acceso público

**Cambiar a Let's Encrypt (si es necesario):**
1. Editar `infra/cert-manager/clusterissuer.yaml`
2. Reemplazar contenido con versión ACME
3. Editar `infra/values/argocd_values.yaml`
4. Cambiar la anotación a `letsencrypt-prod` o `letsencrypt-staging`
5. Ejecutar nuevamente

## Próximos Pasos

- [ ] Ejecutar `./bootstrap_all.sh` completo
- [ ] Verificar que ArgoCD tiene certificado autofirmado válido
- [ ] Acceder a https://argocd.local (puede haber advertencia SSL)
- [ ] Importar CA en navegador (opcional, solo si se accede frecuentemente)
- [ ] (Opcional) Migrar a Let's Encrypt cuando sea necesario acceso público
