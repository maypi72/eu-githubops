# LocalStack Bootstrap Guide

Esta guía explica cómo instalar y configurar LocalStack para desarrollo local con AWS S3 en Kubernetes.

## 📋 Requisitos Previos

Antes de ejecutar el bootstrap de LocalStack, asegúrate de que tienes instalado:

1. **Kubernetes (k3s)** - Ejecuta `bootstrap_k3s.sh`
2. **Helm** - Ejecuta `bootstrap_helm.sh`
3. **Cert-Manager** - Ejecuta `bootstrap_certmanager.sh`
4. **ClusterIssuer** - Ejecuta `bootstrap_clusterissuer.sh`
5. **Ingress NGINX** - Ejecuta `bootstrap_ingress.sh`
6. **Sealed Secrets** - Ejecuta `bootstrap_sealed_secrets.sh`

## 🚀 Instalación Automática (Recomendado)

### Opción 1: Workflow de GitHub Actions

La forma más fácil es usar el workflow de GitHub Actions:

1. Ve a **Actions** > **Bootstrap LocalStack**
2. Click en **Run workflow**
3. Completa los parámetros:
   - `AWS_ACCESS_KEY_ID`: "test" (para desarrollo)
   - `AWS_SECRET_ACCESS_KEY`: "test" (para desarrollo)
   - `AWS_REGION`: "eu-west-1"
   - `Auto Apply Terraform`: true/false

El workflow ejecutará automáticamente:
- Verificación de dependencias
- Instalación de LocalStack
- Configuración de credenciales con Sealed Secrets
- Creación del Ingress
- Ejecución de Terraform

### Opción 2: Ejecución Manual del Script

```bash
# Desde la raíz del repositorio
chmod +x infra/bootstrap/bootstrap_localstack.sh

# Ejecutar con variables de entorno
AWS_ACCESS_KEY_ID=test \
AWS_SECRET_ACCESS_KEY=test \
AWS_REGION=eu-west-1 \
./infra/bootstrap/bootstrap_localstack.sh
```

## 📝 Variables de Entorno

Puedes personalizar la instalación con estas variables:

```bash
# LocalStack
LOCALSTACK_NAMESPACE=localstack              # Namespace donde se instala
LOCALSTACK_RELEASE_NAME=localstack           # Nombre del release de Helm
LOCALSTACK_CHART_VERSION=2.0.0               # Versión del chart

# Sealed Secrets
SEALED_SECRETS_NAMESPACE=kube-system         # Namespace de sealed-secrets
SEALED_SECRETS_RELEASE=sealed-secrets        # Nombre del release de sealed-secrets

# AWS Credenciales
AWS_ACCESS_KEY_ID=test                       # Access Key ID
AWS_SECRET_ACCESS_KEY=test                   # Secret Access Key
AWS_REGION=eu-west-1                         # Región AWS

# Terraform
TERRAFORM_DIR=infra/terraform/localstak      # Directorio de Terraform
AUTO_APPLY=false                             # Aplicar automáticamente en CI

# Herramientas
RETRY_MAX=5                                  # Máximo de reintentos
RETRY_DELAY=2                                # Segundos entre reintentos
```

## ✅ Verificación de la Instalación

Una vez completado el bootstrap, verifica que todo esté funcionando:

```bash
# Verificar namespace
kubectl get namespace localstack

# Verificar pods
kubectl -n localstack get pods

# Verificar servicios
kubectl -n localstack get svc

# Verificar ingress
kubectl -n localstack get ingress

# Verificar secrets sellados
kubectl -n localstack get sealedsecrets
```

## 🔐 Credenciales AWS

Las credenciales se almacenan en un Sealed Secret en el cluster:

```bash
# Ver el secret (encriptado)
kubectl -n localstack get sealedsecrets

# El archivo sellado está guardado en:
infra/localstack/sealed-secrets/localstack-aws-credentials.yaml

# Para usarlo en otros pods, referencia el secret:
env:
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: localstack-aws-credentials
        key: AWS_ACCESS_KEY_ID
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: localstack-aws-credentials
        key: AWS_SECRET_ACCESS_KEY
```

## 🌐 Acceso a LocalStack

LocalStack está disponible en:

- **Endpoint S3**: `http://localstack.local`
- **Puerto**: 4566 (dentro del cluster)
- **DNS**: `localstack.local` (configurable en Ingress)

### Crear un bucket S3

```bash
# Configurar AWS CLI para LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=eu-west-1

# Crear bucket
aws s3 mb s3://mi-bucket \
  --endpoint-url=http://localstack.local \
  --region eu-west-1

# Listar buckets
aws s3 ls --endpoint-url=http://localstack.local
```

## 🏗️ Terraform

El script ejecuta Terraform automáticamente para:
- Crear buckets S3 definidos en `infra/terraform/localstak/main.tf`
- Configurar el estado de Terraform en LocalStack

### Aplicar manualmente cambios en Terraform

```bash
cd infra/terraform/localstak

# Mostrar plan actual
terraform show tfplan

# Aplicar cambios
terraform apply tfplan

# O crear un nuevo plan
terraform plan \
  -var="aws_access_key=test" \
  -var="aws_secret_key=test" \
  -var="aws_region=eu-west-1" \
  -out=tfplan
```

### Variables de Terraform

Archivo: `infra/terraform/localstak/variables.tf`

```hcl
variable "aws_access_key" {
  description = "AWS Access Key"
}

variable "aws_secret_key" {
  description = "AWS Secret Key"
}

variable "aws_region" {
  default = "eu-west-1"
  description = "AWS Region"
}
```

## 📦 Estructura de Archivos

```
infra/
├── bootstrap/
│   └── bootstrap_localstack.sh          # Script de instalación
├── localstack/
│   └── sealed-secrets/
│       └── localstack-aws-credentials.yaml  # Secret sellado (autogenerado)
├── terraform/
│   └── localstak/
│       ├── main.tf                      # Recursos S3
│       ├── provider.tf                  # Configuración de provider AWS
│       ├── variables.tf                 # Variables de Terraform
│       └── remote_state.tf              # Configuración de estado en S3
└── values/
    └── localstack_values.yaml           # Valores de Helm para LocalStack
```

## 🔧 Configuración de Helm

El chart de LocalStack se configura a través de:

1. **infra/values/localstack_values.yaml** - Valores predeterminados
2. **Variables de entorno** - Valores en tiempo de ejecución
3. **--set flags** - Argumentos adicionales durante la instalación

Ejemplo de personalización:

```bash
helm upgrade --install localstack localstack/localstack \
  --namespace localstack \
  --values infra/values/localstack_values.yaml \
  --set startServices=s3,dynamodb \
  --set persistence.size=10Gi
```

## 🌍 Ingress Configuration

El Ingress se crea automáticamente con:

- **Host**: `localstack.local`
- **Puerto**: 4566
- **TLS**: Habilitado (con ClusterIssuer)
- **Annotations**: Configuradas para cert-manager y nginx

Personaliza el host editando el script o creando un Ingress adicional.

## 📊 Monitoreo

### Logs de LocalStack

```bash
kubectl -n localstack logs -f deployment/localstack
```

### Eventos del cluster

```bash
kubectl -n localstack get events --sort-by='.lastTimestamp'
```

### Descripción de recursos

```bash
kubectl -n localstack describe pod <pod-name>
kubectl -n localstack describe svc localstack
kubectl -n localstack describe ingress localstack
```

## 🐛 Troubleshooting

### LocalStack no inicia

```bash
# Verificar logs
kubectl -n localstack logs -f deployment/localstack

# Describir el pod
kubectl describe pod -n localstack -l app=localstack

# Verificar recursos disponibles
kubectl top nodes
kubectl top pods -n localstack
```

### No puedo conectar a localstack.local

1. Verifica que el Ingress está en running:
   ```bash
   kubectl -n localstack get ingress
   ```

2. Verifica que cert-manager creó el certificado:
   ```bash
   kubectl -n localstack get certificate
   ```

3. Prueba conectar al servicio directamente:
   ```bash
   kubectl -n localstack port-forward svc/localstack 4566:4566
   curl http://localhost:4566/_localstack/health
   ```

### Sealed Secret no funciona

1. Verifica que Sealed Secrets está instalado:
   ```bash
   kubectl -n kube-system get pods -l app=sealed-secrets
   ```

2. Verifica que el secret existe:
   ```bash
   kubectl -n localstack get secret localstack-aws-credentials -o yaml
   ```

3. Regenera el secret sellado:
   ```bash
   # El script bootstrap_localstack.sh regenera automáticamente
   ```

### Terraform plan fails

1. Verifica que LocalStack está listo:
   ```bash
   curl http://localstack.local/_localstack/health
   ```

2. Verifica las credenciales:
   ```bash
   export AWS_ACCESS_KEY_ID=test
   export AWS_SECRET_ACCESS_KEY=test
   aws s3 ls --endpoint-url=http://localstack.local
   ```

3. Intenta inicializar manualmente:
   ```bash
   cd infra/terraform/localstak
   terraform init -reconfigure \
     -backend-config="access_key=test" \
     -backend-config="secret_key=test"
   ```

## 📚 Referencias

- [LocalStack Documentation](https://docs.localstack.cloud/)
- [LocalStack Helm Chart](https://github.com/localstack/helm-charts)
- [AWS S3 API Reference](https://docs.aws.amazon.com/AmazonS3/latest/API/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)

## 🤝 Contribuciones

Si encuentras problemas o tienes sugerencias para mejorar este bootstrap:

1. Abre un issue describiendo el problema
2. O envía un pull request con la solución

---

**Última actualización**: Abril 2026
