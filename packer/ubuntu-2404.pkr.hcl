# Packer template for k3s nodes -- Ubuntu 24.04 LTS on Proxmox.
# Build:  packer init . && packer build .
#
# Uses the proxmox-iso builder + Ubuntu autoinstall (see http/user-data).
# After install, scripts/prep.sh bakes in the k3s prerequisites and generalises
# the image, then the VM is converted to a Proxmox template Terraform clones.

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1.2"
    }
  }
}

# Pass secrets via env vars (PKR_VAR_*) or a gitignored *.auto.pkrvars.hcl file.
# See docs/proxmox-setup.md for how to create the service account and token.
variable "proxmox_url"  { type = string }
variable "proxmox_node" { type = string }

# token auth: username = "user@realm!tokenid", token = the UUID secret only.
# See: https://github.com/hashicorp/packer-plugin-proxmox docs.
variable "proxmox_token_id" {
  type      = string
  sensitive = true
  # Full format: "terraform@pve!homelab"  (user@realm!tokenid)
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
  # The UUID secret only -- NOT "tokenid=uuid"
}

# Storage pool names -- match what Proxmox shows under Datacenter → Storage.
# Defaults suit a fresh Proxmox install on local storage.

# Two ISO modes -- set exactly one in your *.pkrvars.hcl:
#
#   iso_file  = "local:iso/ubuntu-24.04.4-live-server-amd64.iso"   # ISO already on Proxmox (fastest)
#   iso_url   = "https://..."                                        # Packer downloads + uploads (first run)
#
# iso_file takes priority. Leave it empty to fall back to iso_url.
variable "iso_file" {
  type    = string
  default = ""
  # Format: "<storage-pool>:iso/<filename>"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
}

variable "iso_storage_pool" {
  type    = string
  default = "local"
  # Only used when iso_file is empty and Packer uploads the ISO itself.
}

variable "disk_storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "template_vm_id" {
  type    = number
  default = 9000
}

variable "template_name" {
  type    = string
  default = "ubuntu-2404-k3s"
}

variable "build_cores" {
  type    = number
  default = 2
}

variable "build_memory" {
  type    = number
  default = 4096
}

variable "disk_size" {
  type    = string
  default = "32G"
}

source "proxmox-iso" "ubuntu" {
  proxmox_url              = var.proxmox_url
  node                     = var.proxmox_node
  username                 = var.proxmox_token_id      # "user@realm!tokenid"
  token                    = var.proxmox_token_secret  # UUID secret only
  insecure_skip_tls_verify = true  # homelab self-signed cert

  # iso_file (already on Proxmox) takes priority over iso_url.
  # Set iso_file in your pkrvars.hcl once the ISO is uploaded to skip re-uploads.
  boot_iso {
    iso_file         = var.iso_file != "" ? var.iso_file : null
    iso_url          = var.iso_file == "" ? var.iso_url : null
    iso_checksum     = var.iso_file == "" ? var.iso_checksum : null
    iso_storage_pool = var.iso_file == "" ? var.iso_storage_pool : null
    unmount          = true
  }

  # Build VM -- only used during the Packer build.
  # Terraform sets the real per-node sizes (cores/memory/disk) when cloning.
  vm_id                = var.template_vm_id
  vm_name              = var.template_name
  template_description = "Ubuntu 24.04 LTS golden image -- k3s prerequisites baked in by prep.sh"
  cores                = var.build_cores
  memory               = var.build_memory

  # virtio-scsi-single required for io_thread on individual disks
  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = var.disk_size
    storage_pool = var.disk_storage_pool
    type         = "scsi"
    io_thread    = true
  }

  network_adapters {
    model  = "virtio"
    bridge = var.network_bridge
  }

  # Cloud-init drive: Terraform uses this to inject per-VM identity at clone time
  # (hostname, static IP, SSH key). Must be on the same pool as the disk.
  cloud_init              = true
  cloud_init_storage_pool = var.disk_storage_pool

  # Packer starts an HTTP server to serve the http/ directory.
  # The boot command tells the Ubuntu installer to fetch the autoinstall seed from it.
  http_directory = "http"
  boot_wait      = "5s"

  # Drop to the GRUB command line and boot with autoinstall parameters.
  # The semicolon in `ds=nocloud-net;seedfrom=...` must be escaped in HCL.
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud-net\\;seedfrom=http://{{.HTTPIP}}:{{.HTTPPort}}/<enter><wait5>",
    "initrd /casper/initrd<enter><wait5>",
    "boot<enter>"
  ]

  # Packer SSHes in after install to run prep.sh.
  # The `ubuntu` user + password are set by the autoinstall user-data.
  # This credential is build-time only -- cloud-init injects SSH keys per clone
  # and password auth is not used on the running nodes.
  ssh_username = "ubuntu"
  ssh_password = "ubuntu"
  ssh_timeout  = "30m"
}

build {
  sources = ["source.proxmox-iso.ubuntu"]

  # Bake in the k3s prerequisites and generalise the image.
  provisioner "shell" {
    execute_command = "sudo -S bash '{{.Path}}'"
    script          = "scripts/prep.sh"
  }
}
