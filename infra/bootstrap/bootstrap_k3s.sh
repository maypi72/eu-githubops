#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Configuración de K3s
K3S_VERSION="${K3S_VERSION:-v1.34.4+k3s1}"
K3S_CHANNEL="${K3S_CHANNEL:-stable}"
K3S_INSTALL_SCRIPT_URL="https://get.k3s.io"

# Opciones fijas de instalación para deshabilitar componentes y usar Calico
K3S_EXEC_OPTS="--disable traefik --disable servicelb --flannel-backend=none --disable-network-policy --write-kubeconfig-mode 644"

# Configuración de Calico
CALICO_VERSION="${CALICO_VERSION:-v3.27.2}"
CALICO_MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml"

retry() {
  local -r max=${RETRY_MAX:-5}
  local -r delay=${RETRY_DELAY:-2}
  local i=0
  until "$@"; do
    i=$((i+1))
    if [ $i -ge $max ]; then
      echo "Command failed after $i attempts: $*"
      return 1
    fi
    echo "Retry $i/$max: $*"
    sleep $((delay * i))
  done
}

echo "::group::Preparando sistema"
echo "Verificando requisitos previos..."

# Verificar puertos disponibles
echo "Verificando puertos disponibles:"
netstat -tuln 2>/dev/null | grep -E ":6443|:10250" || echo "⚠ Puerto 6443 (API) disponible" 

# Verificar conectividad DNS
echo ""
echo "Verificando DNS:"
if nslookup kubernetes.default.svc.cluster.local 8.8.8.8 >/dev/null 2>&1 || true; then
  echo "✓ DNS funcional"
fi

# Limpiar instalación antigua si existe
if [ -d "/var/lib/rancher/k3s" ]; then
  echo "⚠ Directorio /var/lib/rancher/k3s ya existe"
  echo "  Si hay problemas, considera: sudo rm -rf /var/lib/rancher/k3s"
fi

echo ""
sudo apt-get update -y
sudo apt-get install -y curl jq ca-certificates
sudo swapoff -a || true
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true
echo "::endgroup::"

echo "::group::Comprobando si k3s ya está instalado"
if command -v k3s >/dev/null 2>&1; then
  echo "k3s ya instalado: $(k3s --version)"
  echo "::endgroup::"
else
  echo "k3s no instalado, procediendo..."
  echo ""
  echo "Opciones de instalación:"
  echo "  Versión: ${K3S_VERSION}"
  echo "  Canal: ${K3S_CHANNEL}"
  echo "  Opciones: ${K3S_EXEC_OPTS}"
  echo "::endgroup::"
  
  echo "::group::Instalando k3s"
  
  # Ejecutar instalación de k3s
  if ! curl -sfL "${K3S_INSTALL_SCRIPT_URL}" | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_CHANNEL="${K3S_CHANNEL}" \
    INSTALL_K3S_EXEC="server ${K3S_EXEC_OPTS}" \
    sh -s -; then
    echo "ERROR: Falló la ejecución del script de instalación de k3s"
    exit 1
  fi
  
  # Esperar a que el servicio k3s esté listo
  echo "Esperando a que k3s.service inicie..."
  sleep 5
  
  # Verificar que el servicio está activo
  if ! systemctl is-active --quiet k3s; then
    echo "ERROR: k3s.service no está activo"
    echo ""sudo kubectl describe pod coredns-695cbbfcb9-95j65 -n kube-system
Name:                 coredns-695cbbfcb9-95j65
Namespace:            kube-system
Priority:             2000000000
Priority Class Name:  system-cluster-critical
Service Account:      coredns
Node:                 upcdevops9/192.168.0.22
Start Time:           Fri, 03 Apr 2026 20:33:15 +0200
Labels:               k8s-app=kube-dns
                      pod-template-hash=695cbbfcb9
Annotations:          <none>
Status:               Pending
IP:                   
IPs:                  <none>
Controlled By:        ReplicaSet/coredns-695cbbfcb9
Containers:
  coredns:
    Container ID:  
    Image:         rancher/mirrored-coredns-coredns:1.14.1
    Image ID:      
    Ports:         53/UDP (dns), 53/TCP (dns-tcp), 9153/TCP (metrics)
    Host Ports:    0/UDP (dns), 0/TCP (dns-tcp), 0/TCP (metrics)
    Args:
      -conf
      /etc/coredns/Corefile
    State:          Waiting
      Reason:       ContainerCreating
    Ready:          False
    Restart Count:  0
    Limits:
      memory:  170Mi
    Requests:
      cpu:        100m
      memory:     70Mi
    Liveness:     http-get http://:8080/health delay=60s timeout=1s period=10s #success=1 #failure=3
    Readiness:    http-get http://:8181/ready delay=0s timeout=1s period=2s #success=1 #failure=3
    Environment:  <none>
    Mounts:
      /etc/coredns from config-volume (ro)
      /etc/coredns/custom from custom-config-volume (ro)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-kmpxn (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   False 
  Initialized                 True 
  Ready                       False 
  ContainersReady             False 
  PodScheduled                True 
Volumes:
  config-volume:
    Type:      ConfigMap (a volume populated by a ConfigMap)
    Name:      coredns
    Optional:  false
  custom-config-volume:
    Type:      ConfigMap (a volume populated by a ConfigMap)
    Name:      coredns-custom
    Optional:  true
  kube-api-access-kmpxn:
    Type:                     Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:   3607
    ConfigMapName:            kube-root-ca.crt
    Optional:                 false
    DownwardAPI:              true
QoS Class:                    Burstable
Node-Selectors:               kubernetes.io/os=linux
Tolerations:                  CriticalAddonsOnly op=Exists
                              node-role.kubernetes.io/control-plane:NoSchedule op=Exists
                              node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                              node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Topology Spread Constraints:  kubernetes.io/hostname:DoNotSchedule when max skew 1 is exceeded for selector k8s-app=kube-dns
                              topology.kubernetes.io/zone:ScheduleAnyway when max skew 1 is exceeded for selector k8s-app=kube-dns
Events:
  Type     Reason                  Age   From               Message
  ----     ------                  ----  ----               -------
  Normal   Scheduled               85s   default-scheduler  Successfully assigned kube-system/coredns-695cbbfcb9-95j65 to upcdevops9
  Warning  FailedCreatePodSandBox  84s   kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "042b10a02c7f9751f89bd3471f9048455030599aa5abe7260ef20c54b77d3df8": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.43.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": tls: failed to verify certificate: x509: certificate signed by unknown authority
  Warning  FailedCreatePodSandBox  69s   kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "893c9068f0671a58d9220f0c3c2916abff03b4cb0acfeecddaaa926376aaa933": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.43.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": tls: failed to verify certificate: x509: certificate signed by unknown authority
  Warning  FailedCreatePodSandBox  57s   kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "05849f16b79800c5501d9c10348af4bc2d7d959297959e55719f21707ca2e81f": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.43.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": tls: failed to verify certificate: x509: certificate signed by unknown authority
  Warning  FailedCreatePodSandBox  42s   kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "0bc7773809d3b936e7f4a6c38399bf2f4a68dc9b3e670d1835b1b677cd5524c0": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.43.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": tls: failed to verify certificate: x509: certificate signed by unknown authority
  Warning  FailedCreatePodSandBox  28s   kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "fc9e2f20f7561c6b1ddf7f8070452714a5dce906172102f4db57319f8f32e9b3": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.43.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": tls: failed to verify certificate: x509: certificate signed by unknown authority
  Warning  FailedCreatePodSandBox  13s   kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "7526552a5680bb237e5b563ddd545e4745492ed6a2b0ce0ec7931330ff37709c": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.43.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": tls: failed to verify certificate: x509: certificate signed by unknown authority

    echo "Estado del servicio k3s:"
    systemctl status k3s || true
    echo ""
    echo "Últimos logs de k3s:"
    journalctl -xeu k3s.service -n 50 || true
    exit 1
  fi
  
  echo "✓ k3s instalado y servicio activo"
  echo "::endgroup::"
fi

echo "::group::Preparando kubeconfig para el runner"
KUBECONFIG="${KUBECONFIG:-$HOME/kubeconfig}"

# Comprobar que el archivo fuente existe
if [ ! -f "/etc/rancher/k3s/k3s.yaml" ]; then
  echo "ERROR: /etc/rancher/k3s/k3s.yaml no encontrado"
  echo ""
  echo "Diagnosis:"
  echo "1. Verificar que k3s está activo:"
  systemctl status k3s || true
  echo ""
  echo "2. Verificar logs de k3s:"
  journalctl -xeu k3s.service -n 30 || true
  echo ""
  echo "3. Verificar que el servicio está corriendo:"
  ps aux | grep -i k3s | grep -v grep || echo "No k3s process found"
  echo ""
  echo "Para reinstalar, ejecuta: sudo /usr/local/bin/k3s-uninstall.sh && rm -rf /etc/rancher"
  exit 1
fi

# Crear directorio si no existe
mkdir -p "$(dirname "$KUBECONFIG")"

# Copiar kubeconfig (ahora readable gracias a --write-kubeconfig-mode 644)
echo "Copiando kubeconfig desde /etc/rancher/k3s/k3s.yaml..."
if ! cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG"; then
  echo "ERROR: No se pudo copiar kubeconfig"
  echo "Intentando con sudo..."
  if ! sudo cat /etc/rancher/k3s/k3s.yaml > "$KUBECONFIG"; then
    echo "ERROR: No se pudo copiar kubeconfig (permiso denegado)"
    exit 1
  fi
fi

# Cambiar permisos para que solo el owner pueda leer/escribir (más seguro)
echo "Estableciendo permisos restrictivos..."
if ! chmod 600 "$KUBECONFIG"; then
  echo "⚠ Advertencia: No se pudo cambiar permisos a 600"
  echo "  Continuando con permisos actuales"
fi

# Verificar que el archivo se copió correctamente
if [ ! -f "$KUBECONFIG" ]; then
  echo "ERROR: kubeconfig no existe después de copiar"
  exit 1
fi

export KUBECONFIG
echo "✓ KUBECONFIG preparado en $KUBECONFIG"
echo "✓ Tamaño: $(du -h "$KUBECONFIG" | cut -f1)"
echo "✓ Permisos: $(stat -c '%a' "$KUBECONFIG" 2>/dev/null || echo 'desconocidos')"
echo "::endgroup::"

echo "::group::Esperando a que el nodo esté Ready"
retry kubectl get nodes
retry kubectl wait --for=condition=Ready node --all --timeout=300s
echo "::endgroup::"

echo "::group::Esperando a que los pods de K3s estén running"
echo "Esperando a que todos los pods del sistema estén en estado Running o Succeeded..."

TIMEOUT_SECONDS=300  # 5 minutos
ELAPSED=0
CHECK_INTERVAL=5

while [ $ELAPSED -lt $TIMEOUT_SECONDS ]; do
  # Contar pods en estado Running o Succeeded en kube-system
  RUNNING_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  SUCCEEDED_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase=Succeeded --no-headers 2>/dev/null | wc -l)
  
  # Contar pods NO en estado Running o Succeeded (Pending, Failed, CrashLoopBackOff, etc.)
  NOT_READY=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
  
  TOTAL=$((RUNNING_PODS + SUCCEEDED_PODS + NOT_READY))
  
  echo "✓ Pods en kube-system: Running=$RUNNING_PODS | Succeeded=$SUCCEEDED_PODS | Otros=$NOT_READY | Total=$TOTAL | Tiempo: ${ELAPSED}s"
  
  # Si todos los pods estén listos, salir
  if [ $NOT_READY -eq 0 ] && [ $TOTAL -gt 0 ]; then
    echo "✓ ¡Todos los pods de K3s estén Running o Succeeded!"
    echo "::endgroup::"
    break
  fi
  
  sleep $CHECK_INTERVAL
  ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $NOT_READY -gt 0 ]; then
  echo "⚠ Algunos pods aún no estén Ready, continuando con cautela..."
  echo ""
  echo "Pods no listos en kube-system:"
  kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded || true
fi
echo "::endgroup::"

echo "::group::Instalando Calico"
if ! kubectl get ns calico-system >/dev/null 2>&1; then
  retry kubectl apply -f "${CALICO_MANIFEST_URL}"
else
  echo "Calico ya desplegado, omitiendo instalación"
fi
retry kubectl rollout status ds/calico-node -n kube-system --timeout=300s
echo "::endgroup::"

echo "bootstrap_k3s.sh completado correctamente"
