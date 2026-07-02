#!/usr/bin/env bash
# Golden-image prep for k3s nodes. Run by Packer (shell provisioner) during the
# template build -- bakes in the k3s prerequisites and generalises the image.
set -euo pipefail

echo "[prep] updating the OS"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y full-upgrade

echo "[prep] installing base packages + qemu-guest-agent"
apt-get -y install qemu-guest-agent curl ca-certificates open-iscsi nfs-common
# qemu-guest-agent is statically enabled by the hypervisor; no systemctl enable needed
systemctl enable open-iscsi          # needed by Longhorn (Phase 3)

echo "[prep] disabling swap (kubelet expects swap off)"
swapoff -a || true
sed -i.bak '/\bswap\b/d' /etc/fstab
rm -f /swap.img /swapfile || true

echo "[prep] kernel modules for Kubernetes networking"
cat > /etc/modules-load.d/k8s.conf <<'MODS'
overlay
br_netfilter
MODS

echo "[prep] sysctl for Kubernetes networking"
cat > /etc/sysctl.d/99-k8s.conf <<'SYS'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYS

echo "[prep] enabling time sync (embedded etcd is sensitive to clock skew)"
systemctl enable systemd-timesyncd || true

echo "[prep] disabling SSH password auth (keys only; cloud-init injects per-clone)"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
# Also drop in an override file so it survives sshd_config rewrites by cloud-init
echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/99-no-password-auth.conf

echo "[prep] generalising the image for templating"
cloud-init clean --logs || true
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id || true
rm -f /etc/ssh/ssh_host_*            # each clone regenerates unique host keys
apt-get clean
rm -rf /var/lib/apt/lists/*
find /var/log -type f -exec truncate -s 0 {} \; || true
rm -f /root/.bash_history

echo "[prep] done -- safe to convert the VM to a Proxmox template"
