# Packer -- golden image

Builds the Ubuntu 24.04 LTS template that Terraform clones into the 5 k3s VMs.

    packer init .
    packer build .

`scripts/prep.sh` bakes in the k3s prerequisites (qemu-guest-agent, swap off,
kernel modules, sysctls, time sync) and generalises the image (machine-id,
SSH host keys, logs) so every clone is unique. See `../docs/image-prep.md`.
