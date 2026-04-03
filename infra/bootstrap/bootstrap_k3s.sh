#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

K3S_VERSION="${K3S_VERSION:-v1.30.0+k3s1}"
K3S_CHANNEL="${K3S_CHANNEL:-stable}"
K3S_INSTALL_SCRIPT_URL="https://get.k3s.io"
CALICO_MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml"

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
sudo apt-get update -y
sudo apt-get install -y curl jq ca-certificates
sudo swapoff -a || true
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true
echo "::endgroup::"

echo "::group::Comprobando si k3s ya está instalado"
if command -v k3s >/dev/null 2>&1; then
  echo "k3s ya instalado: $(k3s --version)"
else
  echo "::endgroup::"
  echo "::group::Instalando k3s"
  curl -sfL "${K3S_INSTALL_SCRIPT_URL}" | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_CHANNEL="${K3S_CHANNEL}" \
    INSTALL_K3S_EXEC="server \
      --disable traefik \
      --flannel-backend=none \
      --cluster-cidr=10.42.0.0/16 \
      --service-cidr=10.43.0.0/16" \
    sh -s -
fi
echo "::endgroup::"

echo "::group::Preparando kubeconfig para el runner"
KUBECONFIG="${KUBECONFIG:-$HOME/kubeconfig}"
sudo cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG"
sudo chown $USER:$USER "$KUBECONFIG"
export KUBECONFIG
echo "✓ KUBECONFIG preparado en $KUBECONFIG"
echo "::endgroup::"

echo "::group::Esperando a que el nodo esté Ready"
retry kubectl get nodes
retry kubectl wait --for=condition=Ready node --all --timeout=300s
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
