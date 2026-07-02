output "node_ips" {
  description = "Node name → IP address map (without prefix length) for Ansible inventory reference"
  value = {
    for name, node in var.nodes : name => split("/", node.ip)[0]
  }
}
