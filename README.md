# eu-githubops

Repository para automatizar el bootstrap y configuración de clusters Kubernetes con K3s, Helm e Ingress Controller.

## Índice

- [Instalación y Uso](#instalación-y-uso)
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
│   ├── bootstrap_all.sh          # Script principal que ejecuta todos los pasos
│   ├── bootstrap_k3s.sh          # Instalación de K3s
│   ├── bootstrap_helm.sh         # Instalación de Helm
│   └── bootstrap_ingress.sh      # Instalación de NGINX Ingress Controller
└── values/
    └── ingress_values.yaml       # Configuración para Helm (Ingress)
```

### Ejecutar Workflow

1. Ve a **Actions → Bootstrap Cluster**
2. Click **"Run workflow"**
3. Configura los inputs si es necesario:
   - `k3s_version`: Versión de K3s (default: `v1.30.0+k3s1`)
   - `helm_repos`: Repositorios de Helm sin configurar por ahora
   - `dry_run`: Ejecutar sin cambios (default: `false`)

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
