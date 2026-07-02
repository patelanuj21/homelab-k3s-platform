# Provisions the 5 k3s VMs by cloning the Packer-built template.
# Provider: bpg/proxmox (~> 0.66)
#
# Run order: packer build → terraform apply → ansible-playbook site.yml

resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  name          = each.key
  node_name     = each.value.proxmox_host
  vm_id         = each.value.vm_id
  on_boot       = true
  started       = true
  scsi_hardware = "virtio-scsi-single" # matches Packer template; required for iothread
  # Auto-tags: k3s, the host name, server/agent. To add per-node custom tags:
  #   1. Add `extra_tags = optional(list(string), [])` to the nodes object in variables.tf
  #   2. Replace the line below with:
  #      tags = sort(concat(["k3s", each.value.proxmox_host], startswith(each.key, "k3s-server") ? ["k3s-server"] : ["k3s-agent"], each.value.extra_tags))
  tags          = sort(concat(["k3s", each.value.proxmox_host], startswith(each.key, "k3s-server") ? ["k3s-server"] : ["k3s-agent"]))

  clone {
    vm_id     = coalesce(each.value.template_id, var.template_id)
    node_name = coalesce(each.value.template_node, var.template_node)  # use node's own template when available to avoid cross-node clone
    full      = true  # linked clones share the base disk; full clones are independent
  }

  agent { enabled = true } # qemu-guest-agent baked in by prep.sh; needed for IP reporting + graceful shutdown

  cpu {
    cores = each.value.cores
    type  = "host" # pass-through CPU flags; best perf + required for any AVX workloads
  }

  memory { dedicated = each.value.memory_mb }

  # Declare the disk so Terraform owns it and avoids perpetual diffs.
  # Size matches the template (32 GB); cloud-init injects per-VM identity, not the disk.
  disk {
    datastore_id = each.value.disk_storage_pool
    interface    = "scsi0"
    iothread     = true # virtio-scsi-single enables one thread per disk; better perf
    size         = each.value.disk_size
    ssd          = each.value.ssd
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    datastore_id = "local"  # must be a datastore with Snippets content type; local-lvm is block-only and won't work
    dns { servers = var.dns }
    ip_config {
      ipv4 {
        address = each.value.ip # CIDR, e.g. "192.168.10.41/24"
        gateway = var.gateway
      }
    }
    user_account {
      username = var.vm_user
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    # If the Packer template is rebuilt the vm_id changes. Without this,
    # Terraform would destroy and re-clone every running node.
    ignore_changes = [clone]
  }
}
