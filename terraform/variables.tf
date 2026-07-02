variable "proxmox_endpoint" { type = string }
variable "template_id"   { type = number }
variable "template_node" { type = string }  # Proxmox node where the Packer template lives
variable "ssh_public_key" { type = string }
variable "gateway" { type = string }

# token auth: token_id = "user@realm!tokenid", token_secret = the UUID only.
# Same convention as packer/ubuntu-2404.pkr.hcl.
variable "proxmox_token_id" {
  type      = string
  sensitive = true
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}
variable "dns" {
  type    = list(string)
  default = ["192.168.10.1"]
}

# The 5 nodes: 3 servers + 2 agents, all on the one Proxmox host.
variable "vm_user" {
  type    = string
  default = "ubuntu"
}

variable "nodes" {
  type = map(object({
    proxmox_host      = string
    cores             = number
    memory_mb         = number
    ip                = string # CIDR, e.g. "192.168.10.41/24"
    vm_id             = number
    disk_storage_pool = string                # Proxmox storage pool name, e.g. "local-lvm"
    disk_size         = optional(number, 32)    # GB; override for nodes needing more local storage
    ssd               = optional(bool, false)   # set true when backed by NVMe/SSD so guest enables SSD optimisations
    template_id       = optional(number)        # overrides var.template_id; use when the node has its own local template
    template_node     = optional(string)        # overrides var.template_node; set to the node's own name when using a local template
  }))
  # see terraform.tfvars.example
}
