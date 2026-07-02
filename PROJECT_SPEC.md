# PROJECT_SPEC.md — Homelab k3s Platform

> A 5-node HA Kubernetes cluster (k3s + embedded etcd) on bare metal — two
> Proxmox hosts. The self-managed counterpart to the AWS Reference Platform.
>
> **This file is context for Claude Code.** Build phase by phase. Understand and
> be able to defend every file — interviewers will probe the HA and etcd choices.

## Locked decisions

- **5 nodes:** 3 servers (HA embedded etcd) + 2 agents.
- **All server/etcd nodes on the one Proxmox host**, on SSD-backed Proxmox
  storage. etcd is fsync- and latency-sensitive, so server nodes need
  SSD-backed storage and stable, low-latency access to the host CPU.
- **Observability runs on the Proxmox host** (`k3s-agent-1`), locked, sized
  with enough RAM/cores to carry Prometheus + Loki + Tempo.
- **Pipeline:** Packer (golden image) → Terraform (VMs) → Ansible (k3s) → Argo CD.
- Can run **always-on** as a live demo; the AWS project stays ephemeral.

## Hardware

| Host | Spec | Role |
|---|---|---|
| Proxmox host | 96 GB RAM, multi-core Xeon | control plane + observability; node name `pve`; vmbr0 = 192.168.10.3 (LAN), vmbr1 = 192.168.10.4 |
| 2× additional hosts | not yet purchased | Phase 3 — future nodes / true host-level HA |

## Cluster topology

| VM | Role | vCPU | RAM |
|---|---|---|---|
| k3s-server-1/2/3 | control plane + embedded etcd | 2 | 4–6 GB |
| k3s-agent-1 | workloads + observability | 4–6 | 16–24 GB |
| k3s-agent-2 | lightweight workloads | 2 | ~6 GB |

**HA — be honest about it:** 3 embedded-etcd servers give a real HA control plane
(reboot one server, the cluster stays up). But all 3 are VMs on one physical host
— if that host dies, the cluster is down. That is *node-level* HA, not
*host-level* HA. True host-level HA needs a third physical machine (Phase 3).

## Tech stack

| Layer | Choice |
|---|---|
| Hypervisor | Proxmox VE on both hosts |
| Golden image | Packer, `proxmox-iso` builder, Ubuntu 24.04 LTS |
| VM IaC | Terraform, `bpg/proxmox` provider |
| Config management | Ansible — the `k3s-io/k3s-ansible` playbook |
| Kubernetes | k3s, HA with embedded etcd (3 servers) |
| Control-plane VIP | kube-vip |
| Load balancer | MetalLB |
| Ingress | Traefik (deployed via Argo CD; k3s built-in disabled with `--disable traefik`) |
| Storage | local-path-provisioner (Phase 1–2); Longhorn later |
| GitOps | Argo CD (app-of-apps) |
| Observability | kube-prometheus-stack + Loki + Tempo |

## VM image & template prep

**Base image:** Ubuntu Server 24.04 LTS cloud image (`noble-server-cloudimg-amd64.img`).

**Division of labor:**
- **Packer** bakes the golden image — everything identical on every node.
- **Terraform** clones it 5×, sets per-VM identity (hostname, static IP, SSH key,
  CPU/RAM/disk) via cloud-init.
- **Ansible** does role-specific config (server vs agent) and installs k3s.

**What `packer/scripts/prep.sh` bakes in:**
- Full OS update; `qemu-guest-agent` installed + enabled (Proxmox/Terraform need
  it for IP reporting and graceful shutdown).
- Swap disabled (`swapoff -a`, fstab entry removed, swapfile deleted).
- Kernel modules `overlay` + `br_netfilter`; k8s sysctls (`bridge-nf-call-iptables`,
  `bridge-nf-call-ip6tables`, `ip_forward`).
- Time sync enabled — embedded etcd is intolerant of clock skew across the 3 servers.
- Base packages: `curl`, `ca-certificates`, `open-iscsi`, `nfs-common`.

**Generalize before templating** (skipping this causes duplicate-identity bugs):
`cloud-init clean`, truncate `/etc/machine-id`, delete SSH host keys, clear logs
and caches.

**Do not bake in:** SSH keys, hostnames, static IPs (cloud-init injects per
clone), or k3s itself (Ansible installs it so the version is explicit).

Full detail in `docs/image-prep.md`.

## Networking model — three layers

On bare metal you provide what the cloud gives you for free. See `docs/networking.md`.

- **kube-vip** — an HA virtual IP for the Kubernetes API. Floats one VIP across
  the 3 servers so `kubectl` and the agents have a single stable control-plane
  address. Cluster-management traffic only.
- **MetalLB** — gives `LoadBalancer` Services external IPs from a LAN pool (the
  L4 job the cloud normally does).
- **Traefik** — L7 HTTP ingress: hostname/path routing + TLS.

They layer, they don't compete: Traefik runs as a `LoadBalancer` Service, so
MetalLB hands Traefik its external IP. Disable k3s's built-in ServiceLB
(`--disable servicelb`) in favor of MetalLB.

## Build phases

### Phase 0 — Proxmox foundation
- Install / update Proxmox VE on the host.
- **LAN IP plan — locked** (subnet 192.168.10.0/24, gateway 192.168.10.1):

  | IP | Purpose |
  |---|---|
  | 192.168.10.40 | kube-vip control-plane VIP |
  | 192.168.10.41 | k3s-server-1 |
  | 192.168.10.42 | k3s-server-2 |
  | 192.168.10.43 | k3s-server-3 |
  | 192.168.10.44 | k3s-agent-1 (observability) |
  | 192.168.10.45 | k3s-agent-2 |
  | 192.168.10.50–59 | MetalLB pool (LoadBalancer services) |

  IPs are set statically via cloud-init — VMs do not use DHCP. UniFi fixed-IP
  records are optional but useful for network visibility. Keep `.10`–`.39`
  outside the UniFi DHCP range.
- Build the golden-image template with Packer (`make image`).

### Phase 1 — The HA cluster
- Terraform clones the template into the 5 VMs (`make deploy`).
- Ansible installs k3s — 3 HA embedded-etcd servers + 2 agents, kube-vip for the
  API VIP (`make k3s`).
- Install MetalLB with a LAN IP pool.
- Verify HA: reboot one server node — the cluster stays up.

### Phase 2 — GitOps, observability
- Install Argo CD; adopt the app-of-apps pattern.
- ArgoCD-manage kube-prometheus-stack + Loki + Tempo, pinned to `k3s-agent-1`.
- Define SLIs/SLOs and one alert.

### Phase 3 — Scale & true HA
- Add 2 additional physical hosts; rebalance one etcd server per physical host
  for true host-level HA. Longhorn for replicated storage.

## What NOT to build

- No Longhorn yet — local-path is fine until there are more nodes.
- No service mesh, no multi-cluster.
- Don't hand-roll the k3s install — use the `k3s-ansible` playbook (and read it).

## Working method with Claude Code

Build one phase per session, commit per logical chunk, and make at least one
change yourself in every generated file. You must be able to defend every line —
especially the HA, etcd, and networking choices.
