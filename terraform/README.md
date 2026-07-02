# Terraform -- the 5 VMs

Clones the Packer template into 3 server + 2 agent VMs on the Proxmox host,
and sets per-VM identity (hostname, static IP, SSH key) via cloud-init.

    cp terraform.tfvars.example terraform.tfvars   # then edit
    terraform init && terraform apply

Terraform = infrastructure (the VMs). Ansible = configuration (k3s). See PROJECT_SPEC.md.
