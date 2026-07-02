# Ansible -- k3s install & node config

Installs k3s in HA mode (3 embedded-etcd servers + 2 agents) using the official
`k3s-io/k3s-ansible` roles, with kube-vip for the control-plane VIP, then
bootstraps MetalLB and Argo CD.

Prerequisites on the control node (this machine):

    git submodule update --init
    ansible-galaxy collection install -r requirements.yml
    pip install kubernetes   # required by the kubernetes.core.helm/.k8s modules
                              # used to bootstrap Argo CD via Helm

    ansible-playbook site.yml

After Argo CD is up, GitOps (../gitops) manages everything else in-cluster --
Traefik, the observability stack, and any apps.
