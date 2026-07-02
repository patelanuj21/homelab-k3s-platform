# Homelab k3s Platform — one-command operations.
.DEFAULT_GOAL := help
SHELL := /bin/bash

PACKER_DIR ?= packer
TF_DIR     ?= terraform
ANSIBLE    ?= ansible

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## --- image (Packer) ---
.PHONY: image
image: ## Build the Ubuntu 24.04 golden-image template
	cd $(PACKER_DIR) && packer init . && packer build .

## --- VMs (Terraform) ---
.PHONY: deploy
deploy: ## Clone the template into the 5 k3s VMs
	cd $(TF_DIR) && terraform init && terraform apply

.PHONY: destroy
destroy: ## Destroy the 5 VMs
	cd $(TF_DIR) && terraform destroy

## --- cluster (Ansible) ---
.PHONY: k3s
k3s: ## Install k3s (HA embedded etcd) + kube-vip + MetalLB
	cd $(ANSIBLE) && ansible-playbook site.yml

.PHONY: destroy-k3s
destroy-k3s: ## Uninstall k3s from the VMs (keeps the VMs themselves)
	cd $(ANSIBLE) && ansible-playbook vendor/k3s-ansible/playbooks/reset.yml

.PHONY: kubeconfig
kubeconfig: ## Extract the k3s-ansible kubeconfig context into ./kubeconfig
	# k3s-ansible already merges a VIP-addressed "k3s-ansible" context into
	# ~/.kube/config during `make k3s` -- no need to scp anything off a node
	# (the raw /etc/rancher/k3s/k3s.yaml there is root-only and still points
	# at 127.0.0.1 anyway).
	kubectl --context=k3s-ansible config view --minify --flatten > kubeconfig
	@echo "run: export KUBECONFIG=$$(pwd)/kubeconfig"

## --- platform ---
.PHONY: argocd-password
argocd-password: ## Print the Argo CD admin password
	kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' | base64 -d; echo

.PHONY: grafana
grafana: ## Port-forward Grafana to http://localhost:3000
	kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

.PHONY: argocd-ui
argocd-ui: ## Port-forward the Argo CD UI to https://localhost:8080
	kubectl -n argocd port-forward svc/argocd-server 8080:443

.PHONY: status
status: ## Show cluster nodes and Argo CD apps
	kubectl get nodes -o wide
	kubectl -n argocd get applications
