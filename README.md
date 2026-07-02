# Homelab k3s Platform

A 5-node, highly-available Kubernetes cluster (k3s with embedded etcd) on bare
metal — a single Proxmox host. The self-managed counterpart to the **AWS
Reference Platform**: that project proves managed cloud infrastructure (EKS);
this one proves a self-managed HA cluster, virtualization, config management,
and bare-metal networking. It can run always-on as a live demo.

See [`PROJECT_SPEC.md`](PROJECT_SPEC.md) for the full phased build spec.

## What it shows

- **Self-managed HA Kubernetes** — k3s, 3 embedded-etcd servers + 2 agents.
- **Virtualization** — Proxmox, a Packer-built golden image, cloud-init.
- **IaC + config management** — Terraform provisions the VMs; Ansible installs k3s.
- **Bare-metal networking** — kube-vip (API VIP), MetalLB (service IPs), Traefik (ingress).
- **Observability** — Prometheus, Grafana, Loki, Tempo (same stack as the AWS project).

## Hardware

| Host | Spec | Role |
|---|---|---|
| Proxmox host | 96 GB RAM, multi-core Xeon | control plane + observability |
| 2× additional hosts | not yet purchased | Phase 3 — true host-level HA |

## Cluster topology

| VM | Role |
|---|---|
| k3s-server-1/2/3 | control plane + embedded etcd |
| k3s-agent-1 | workloads + observability |
| k3s-agent-2 | lightweight workloads |

All 5 VMs currently live on the one Proxmox host. etcd is fsync- and
latency-sensitive, so all 3 servers get SSD-backed storage. Observability runs
on `k3s-agent-1`, which is sized with enough RAM/cores to comfortably carry
Prometheus + Loki + Tempo.

## The build pipeline

```
Packer ──▶ golden image (Ubuntu 24.04 + k3s prereqs baked in)
              │
Terraform ──▶ clones it into 5 VMs on the Proxmox host
              │
Ansible ───▶ installs k3s HA (embedded etcd) + kube-vip + MetalLB
              │
Argo CD ───▶ owns everything in-cluster, synced from gitops/
```

## Quick start

Prerequisites: Proxmox on the host, plus `packer`, `terraform`, `ansible`,
`kubectl`, `make`.

```bash
# 1. build the golden-image template
make image

# 2. clone it into the 5 VMs
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # then edit
make deploy

# 3. install k3s (HA embedded etcd) + kube-vip + MetalLB
make k3s
make kubeconfig
```

Run `make help` for all targets.

## Layout

```
packer/      golden-image build (Packer + the prep script)
terraform/   the 5 VMs (bpg/proxmox provider)
ansible/     k3s install (k3s-ansible) + inventory
gitops/      Argo CD app-of-apps + manifests
apps/        sample/demo workloads, packaged as containers
docs/        architecture, networking, image-prep, HA notes
```

## Build phases

See [`PROJECT_SPEC.md`](PROJECT_SPEC.md). Phase 0 (Proxmox + golden image) →
Phase 1 (the HA cluster) → Phase 2 (GitOps, observability) →
Phase 3 (additional hosts, true host-level HA). Build one phase per session, and
be able to defend every file.
