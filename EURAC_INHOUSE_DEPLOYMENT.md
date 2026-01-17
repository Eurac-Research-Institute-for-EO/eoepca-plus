# EURAC In-House OpenEO Deployment Guide

Complete guide to deploy OpenEO infrastructure on EURAC's own servers.

**Target Environment:** EURAC VMs (on-premise)  
**Timeline:** 2-4 weeks  
**Expertise Required:** Kubernetes, Linux, Networking  

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Phase 1: Infrastructure Setup](#phase-1-infrastructure-setup)
4. [Phase 2: Kubernetes Cluster](#phase-2-kubernetes-cluster)
5. [Phase 3: Core Services](#phase-3-core-services)
6. [Phase 4: Storage Configuration](#phase-4-storage-configuration)
7. [Phase 5: Networking & Ingress](#phase-5-networking--ingress)
8. [Phase 6: ArgoCD Setup](#phase-6-argocd-setup)
9. [Phase 7: OpenEO Deployment](#phase-7-openeo-deployment)
10. [Phase 8: Monitoring & Logging](#phase-8-monitoring--logging)
11. [Phase 9: Backup & Disaster Recovery](#phase-9-backup--disaster-recovery)
12. [Operations & Maintenance](#operations--maintenance)
13. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Hardware Requirements

**Minimum 3 VMs for Production:**

| Role | CPU | RAM | Disk | Network |
|------|-----|-----|------|---------|
| Master Node 1 | 4 cores | 8 GB | 100 GB SSD | 1 Gbps |
| Master Node 2 | 4 cores | 8 GB | 100 GB SSD | 1 Gbps |
| Master Node 3 | 4 cores | 8 GB | 100 GB SSD | 1 Gbps |
| Worker Node 1 | 8 cores | 32 GB | 200 GB SSD | 1 Gbps |
| Worker Node 2 | 8 cores | 32 GB | 200 GB SSD | 1 Gbps |
| Worker Node 3 | 8 cores | 32 GB | 200 GB SSD | 1 Gbps |
| NFS Storage | 4 cores | 8 GB | 2 TB HDD | 1 Gbps |

**Optional (Recommended):**
- Load Balancer VM: 2 cores, 4 GB RAM
- Jump/Bastion Host: 2 cores, 4 GB RAM

**Total Minimum:**
- 7 VMs
- 44 CPU cores
- 124 GB RAM
- 2.6 TB storage

### Software Requirements

**Operating System:**
- Ubuntu 22.04 LTS (recommended)
- Rocky Linux 9 (alternative)
- Debian 12 (alternative)

**Network Requirements:**
- Static IP addresses for all nodes
- DNS name: `openeo.eurac.edu` (or subdomain)
- Ports open between nodes (see networking section)
- Internet access for pulling images (or private registry)

### Access Requirements

- Root/sudo access on all VMs
- SSH key-based authentication
- DNS management access
- Firewall configuration access
- SSL certificate (or ability to use Let's Encrypt)

### Knowledge Requirements

- Linux system administration
- Kubernetes fundamentals
- YAML configuration
- Networking (DNS, load balancing, firewalls)
- Git and GitOps concepts

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet/Users                           │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                          HTTPS (443)
                                 │
┌────────────────────────────────▼────────────────────────────────┐
│                      Load Balancer / HAProxy                     │
│                   openeo.eurac.edu (Public IP)                   │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
         ┌──────────▼───┐  ┌────▼─────┐  ┌──▼──────────┐
         │  Master 1    │  │ Master 2 │  │  Master 3   │
         │ (Control)    │  │(Control) │  │ (Control)   │
         └──────────────┘  └──────────┘  └─────────────┘
                    │            │            │
              ┌─────┴────────────┴────────────┴─────┐
              │        Kubernetes API Server         │
              └─────┬────────────┬────────────┬──────┘
                    │            │            │
         ┌──────────▼───┐  ┌────▼─────┐  ┌──▼──────────┐
         │  Worker 1    │  │ Worker 2 │  │  Worker 3   │
         │              │  │          │  │             │
         │ ┌──────────┐ │  │┌────────┐│  │┌──────────┐ │
         │ │OpenEO API│ │  ││Dask    ││  ││Argo      │ │
         │ │PostgreSQL│ │  ││Workers ││  ││Workflows │ │
         │ │Redis     │ │  ││        ││  ││          │ │
         │ └──────────┘ │  │└────────┘│  │└──────────┘ │
         └──────┬───────┘  └────┬─────┘  └──────┬──────┘
                │               │               │
                └───────────────┼───────────────┘
                                │
                    ┌───────────▼────────────┐
                    │    NFS Storage Server   │
                    │  - Job data             │
                    │  - User workspaces      │
                    │  - Results              │
                    └─────────────────────────┘
```

**Key Components:**
1. **Load Balancer** - Routes traffic to Kubernetes ingress
2. **Control Plane** - 3 master nodes (HA)
3. **Worker Nodes** - Run application workloads
4. **Storage** - NFS for persistent data
5. **Ingress** - NGINX or Traefik for routing
6. **ArgoCD** - GitOps deployment
7. **OpenEO Stack** - API, PostgreSQL, Redis, Argo Workflows, Dask

---

## Phase 1: Infrastructure Setup

### Step 1.1: Prepare VMs

**On each VM:**

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Set hostname (adjust for each node)
sudo hostnamectl set-hostname k8s-master-1
# k8s-master-2, k8s-master-3, k8s-worker-1, k8s-worker-2, k8s-worker-3, nfs-server

# Configure /etc/hosts on ALL nodes
cat <<EOF | sudo tee -a /etc/hosts
192.168.1.10  k8s-master-1
192.168.1.11  k8s-master-2
192.168.1.12  k8s-master-3
192.168.1.20  k8s-worker-1
192.168.1.21  k8s-worker-2
192.168.1.22  k8s-worker-3
192.168.1.30  nfs-server
192.168.1.100 k8s-lb  # Load balancer VIP
EOF

# Disable swap (required for Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Install essential tools
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Configure firewall (if using UFW)
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 6443/tcp  # Kubernetes API (masters only)
sudo ufw allow 2379:2380/tcp  # etcd (masters only)
sudo ufw allow 10250/tcp # Kubelet API
sudo ufw allow 10251/tcp # kube-scheduler (masters only)
sudo ufw allow 10252/tcp # kube-controller-manager (masters only)
sudo ufw allow 30000:32767/tcp  # NodePort Services
```

### Step 1.2: Install Container Runtime (containerd)

**On all Kubernetes nodes:**

```bash
# Install containerd
sudo apt install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Enable systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verify
sudo systemctl status containerd
```

### Step 1.3: Install Kubernetes Tools

**On all Kubernetes nodes:**

```bash
# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubernetes components
sudo apt update
sudo apt install -y kubelet kubeadm kubectl

# Hold versions (prevent auto-upgrade)
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
sudo systemctl enable kubelet
```

---

## Phase 2: Kubernetes Cluster

### Step 2.1: Initialize First Master Node

**On k8s-master-1:**

```bash
# Create kubeadm config
cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.1.10  # Master 1 IP
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.29.0
controlPlaneEndpoint: "k8s-lb:6443"  # Load balancer
networking:
  podSubnet: 10.244.0.0/16  # For Flannel/Calico
  serviceSubnet: 10.96.0.0/12
apiServer:
  certSANs:
  - k8s-lb
  - openeo.eurac.edu
  - 192.168.1.100  # LB IP
  - 192.168.1.10   # Master 1
  - 192.168.1.11   # Master 2
  - 192.168.1.12   # Master 3
EOF

# Initialize cluster
sudo kubeadm init --config kubeadm-config.yaml --upload-certs

# Save the output! You'll need:
# 1. kubeadm join command for master nodes
# 2. kubeadm join command for worker nodes
# 3. Certificate key for HA setup

# Configure kubectl for root user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl get nodes
kubectl get pods -A
```

### Step 2.2: Install Pod Network (CNI)

**Choose one: Calico (recommended) or Flannel**

**Option A: Calico (Recommended)**

```bash
# Install Calico operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# Install Calico custom resources
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

# Wait for pods to be ready
watch kubectl get pods -n calico-system
```

**Option B: Flannel (Simpler)**

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for pods
watch kubectl get pods -n kube-flannel
```

### Step 2.3: Join Additional Master Nodes

**On k8s-master-2 and k8s-master-3:**

```bash
# Use the join command from step 2.1 output
# It should look like:
sudo kubeadm join k8s-lb:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <cert-key> \
  --apiserver-advertise-address <this-node-ip>

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl get nodes
```

### Step 2.4: Join Worker Nodes

**On k8s-worker-1, k8s-worker-2, k8s-worker-3:**

```bash
# Use the worker join command from step 2.1 output
sudo kubeadm join k8s-lb:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# From any master node, verify:
kubectl get nodes

# Label worker nodes
kubectl label node k8s-worker-1 node-role.kubernetes.io/worker=worker
kubectl label node k8s-worker-2 node-role.kubernetes.io/worker=worker
kubectl label node k8s-worker-3 node-role.kubernetes.io/worker=worker
```

### Step 2.5: Setup Load Balancer (HAProxy)

**On separate LB VM or master-1:**

```bash
# Install HAProxy
sudo apt install -y haproxy

# Configure HAProxy
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend k8s-api
    bind *:6443
    mode tcp
    option tcplog
    default_backend k8s-api-backend

backend k8s-api-backend
    mode tcp
    balance roundrobin
    option tcp-check
    server master1 192.168.1.10:6443 check
    server master2 192.168.1.11:6443 check
    server master3 192.168.1.12:6443 check

frontend http-ingress
    bind *:80
    mode tcp
    default_backend http-ingress-backend

backend http-ingress-backend
    mode tcp
    balance roundrobin
    server worker1 192.168.1.20:80 check
    server worker2 192.168.1.21:80 check
    server worker3 192.168.1.22:80 check

frontend https-ingress
    bind *:443
    mode tcp
    default_backend https-ingress-backend

backend https-ingress-backend
    mode tcp
    balance roundrobin
    server worker1 192.168.1.20:443 check
    server worker2 192.168.1.21:443 check
    server worker3 192.168.1.22:443 check

listen stats
    bind *:9000
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s
EOF

# Restart HAProxy
sudo systemctl restart haproxy
sudo systemctl enable haproxy

# Check status
sudo systemctl status haproxy

# Test
curl http://k8s-lb:9000/stats
```

---

## Phase 3: Core Services

### Step 3.1: Install Helm

**On master-1 (or workstation):**

```bash
# Install Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version

# Add common repositories
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### Step 3.2: Install cert-manager

```bash
# Install cert-manager CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml

# Create namespace
kubectl create namespace cert-manager

# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.14.0

# Verify
kubectl get pods -n cert-manager

# Create ClusterIssuer for Let's Encrypt
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@eurac.edu  # Change this
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### Step 3.3: Install MetalLB (Load Balancer for bare metal)

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.0/config/manifests/metallb-native.yaml

# Wait for pods
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

# Configure IP address pool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.250  # Adjust for your network
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF
```

---

## Phase 4: Storage Configuration

### Step 4.1: Setup NFS Server

**On nfs-server VM:**

```bash
# Install NFS server
sudo apt install -y nfs-kernel-server

# Create export directories
sudo mkdir -p /export/openeo/data
sudo mkdir -p /export/openeo/postgresql
sudo mkdir -p /export/openeo/redis

# Set permissions
sudo chown -R nobody:nogroup /export/openeo
sudo chmod -R 755 /export/openeo

# Configure exports
cat <<EOF | sudo tee /etc/exports
/export/openeo *(rw,sync,no_subtree_check,no_root_squash)
EOF

# Apply configuration
sudo exportfs -ra

# Restart NFS server
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server

# Verify
showmount -e localhost
```

### Step 4.2: Install NFS CSI Driver

**On master-1:**

```bash
# Install NFS CSI driver
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

kubectl create namespace kube-system  # Likely already exists

helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set kubeletDir=/var/lib/kubelet

# Verify
kubectl get pods -n kube-system -l app=csi-nfs-controller
kubectl get pods -n kube-system -l app=csi-nfs-node

# Create StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-client
provisioner: nfs.csi.k8s.io
parameters:
  server: nfs-server  # or IP: 192.168.1.30
  share: /export/openeo
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
  - nfsvers=4.1
EOF

# Set as default
kubectl patch storageclass nfs-client -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Test with PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  storageClassName: nfs-client
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
EOF

# Verify
kubectl get pvc test-pvc

# Clean up test
kubectl delete pvc test-pvc
```

---

## Phase 5: Networking & Ingress

### Step 5.1: Install NGINX Ingress Controller

```bash
# Install NGINX Ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalIPs="{192.168.1.100}" \
  --set controller.ingressClassResource.default=true

# Wait for deployment
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Verify
kubectl get svc -n ingress-nginx
kubectl get pods -n ingress-nginx
```

### Step 5.2: Configure DNS

**Update DNS records:**

```
# Add to your DNS server (bind, PowerDNS, or external)
openeo.eurac.edu.  A  192.168.1.100  # Load balancer IP
*.openeo.eurac.edu.  CNAME  openeo.eurac.edu.

# Or edit /etc/hosts on client machines for testing
192.168.1.100  openeo.eurac.edu
```

**Test DNS:**

```bash
# From any machine
nslookup openeo.eurac.edu
ping openeo.eurac.edu

# Test ingress
curl http://openeo.eurac.edu
# Should return 404 (no backend yet) - that's OK
```

---

## Phase 6: ArgoCD Setup

### Step 6.1: Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# Save this password!

# Expose ArgoCD UI via Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.eurac.edu  # Change subdomain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
  tls:
  - hosts:
    - argocd.eurac.edu
    secretName: argocd-tls
EOF

# Install ArgoCD CLI (optional)
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd
rm argocd

# Login via CLI
argocd login argocd.eurac.edu --username admin --password <password-from-above>

# Change admin password
argocd account update-password
```

### Step 6.2: Configure ArgoCD for EURAC Repo

```bash
# Add Git repository
argocd repo add https://github.com/Eurac-Research-Institute-for-EO/eoepca-plus.git \
  --username <github-username> \
  --password <github-token>

# Create ArgoCD project
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: eurac-openeo
  namespace: argocd
spec:
  description: EURAC OpenEO Project
  sourceRepos:
  - https://github.com/Eurac-Research-Institute-for-EO/eoepca-plus.git
  destinations:
  - namespace: '*'
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
EOF

# Create main application
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: eoepca-eurac
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: eurac-openeo
  source:
    repoURL: https://github.com/Eurac-Research-Institute-for-EO/eoepca-plus.git
    targetRevision: deploy-develop
    path: argocd
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# Check sync status
argocd app get eoepca-eurac
argocd app sync eoepca-eurac
```

---

## Phase 7: OpenEO Deployment

### Step 7.1: Create OpenEO Namespace

```bash
# Create namespace
kubectl create namespace openeo

# Label namespace
kubectl label namespace openeo name=openeo
```

### Step 7.2: Customize OpenEO Configuration

**Update values in your fork:**

```bash
# Clone your fork
git clone https://github.com/Eurac-Research-Institute-for-EO/eoepca-plus.git
cd eoepca-plus

# Edit OpenEO configuration
vim argocd/eoepca/openeo-argoworkflows/parts/helm-openeo-argoworkflows.yaml
```

**Key changes for in-house deployment:**

```yaml
# argocd/eoepca/openeo-argoworkflows/parts/helm-openeo-argoworkflows.yaml

spec:
  source:
    repoURL: https://github.com/Eurac-Research-Institute-for-EO/charts
    targetRevision: main
    path: openeo-argoworkflows
    helm:
      values: |
        api:
          replicas: 2  # Adjust based on load
          
          apiDns: openeo.eurac.edu  # Your domain
          
          oidc:
            apiUrl: "https://openeo.eurac.edu/openeo/1.1.0"
            oidcUrl: "https://edp-portal.eurac.edu/auth/realms/edp"
            oidcOrganisation: "eurac-keycloak"
            oidcProviderTitle: "EURAC Keycloak"
          
          image:
            repository: yuvraj1989/openeo-argoworkflows-api
            pullPolicy: IfNotPresent
            tag: "eurac-custom-oidc"
        
        postgresql:
          enabled: true
          persistence:
            enabled: true
            storageClass: nfs-client
            size: 50Gi
          auth:
            username: "openeo"
            password: "CHANGE_ME_STRONG_PASSWORD"  # Change!
            database: "openeo"
        
        redis:
          enabled: true
          master:
            persistence:
              enabled: true
              storageClass: nfs-client
              size: 10Gi
        
        dask:
          enabled: true
          scheduler:
            replicas: 1
          worker:
            replicas: 3  # Adjust based on workload
            resources:
              limits:
                memory: 8Gi
                cpu: 4
              requests:
                memory: 4Gi
                cpu: 2
        
        argoWorkflows:
          enabled: true
```

**Commit and push:**

```bash
git add argocd/eoepca/openeo-argoworkflows/
git commit -m "Configure OpenEO for EURAC in-house deployment"
git push origin deploy-develop
```

### Step 7.3: Configure Ingress Route

**Update or create APISIX/NGINX route:**

```yaml
# argocd/eoepca/openeo-argoworkflows/parts/ingress-openeo.yaml

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: openeo-ingress
  namespace: openeo
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
spec:
  ingressClassName: nginx
  rules:
  - host: openeo.eurac.edu
    http:
      paths:
      - path: /openeo/1.1.0(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: openeo-argoworkflows-api
            port:
              number: 80
      - path: /.well-known(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: openeo-argoworkflows-api
            port:
              number: 80
  tls:
  - hosts:
    - openeo.eurac.edu
    secretName: openeo-tls
```

**Commit and push:**

```bash
git add argocd/eoepca/openeo-argoworkflows/parts/ingress-openeo.yaml
git commit -m "Add NGINX ingress for OpenEO"
git push origin deploy-develop
```

### Step 7.4: Deploy via ArgoCD

```bash
# Sync ArgoCD (it should auto-sync)
argocd app sync eoepca-eurac

# Watch deployment
kubectl get pods -n openeo -w

# Check application status
argocd app get eoepca-eurac

# View logs
kubectl logs -n openeo -l app=openeo-argoworkflows-api
```

### Step 7.5: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n openeo

# Check services
kubectl get svc -n openeo

# Check ingress
kubectl get ingress -n openeo

# Test endpoints
curl https://openeo.eurac.edu/openeo/1.1.0/
curl https://openeo.eurac.edu/openeo/1.1.0/collections
curl https://openeo.eurac.edu/openeo/1.1.0/processes

# Test OIDC configuration
curl https://openeo.eurac.edu/openeo/1.1.0/credentials/oidc | jq
```

---

## Phase 8: Monitoring & Logging

### Step 8.1: Install Prometheus & Grafana

```bash
# Add Prometheus repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=nfs-client \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.storageClassName=nfs-client \
  --set grafana.persistence.size=10Gi

# Wait for pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s

# Get Grafana password
kubectl get secret --namespace monitoring kube-prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode

# Expose Grafana
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  rules:
  - host: grafana.eurac.edu
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-grafana
            port:
              number: 80
  tls:
  - hosts:
    - grafana.eurac.edu
    secretName: grafana-tls
EOF
```

### Step 8.2: Configure Grafana Dashboards

```bash
# Access Grafana
open https://grafana.eurac.edu
# Username: admin
# Password: (from step 8.1)

# Import dashboards (via UI):
# 1. Kubernetes Cluster Monitoring: Dashboard ID 7249
# 2. Node Exporter Full: Dashboard ID 1860
# 3. PostgreSQL Database: Dashboard ID 9628
# 4. Redis Dashboard: Dashboard ID 11835
```

### Step 8.3: Install Loki for Logging (Optional)

```bash
# Add Grafana repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Loki
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set loki.persistence.enabled=true \
  --set loki.persistence.storageClassName=nfs-client \
  --set loki.persistence.size=50Gi \
  --set promtail.enabled=true

# Add Loki data source in Grafana
# URL: http://loki:3100
```

---

## Phase 9: Backup & Disaster Recovery

### Step 9.1: Install Velero

```bash
# Install Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xvf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# Setup backup location (using NFS)
mkdir -p /export/openeo/backups

# Install Velero server
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket openeo-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.default:9000

# Or use restic for volume backups
velero install \
  --provider restic \
  --use-restic \
  --default-volumes-to-restic
```

### Step 9.2: Configure Backup Schedule

```bash
# Create backup schedule
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces openeo,argocd,monitoring

# Create on-demand backup
velero backup create manual-backup-$(date +%Y%m%d) \
  --include-namespaces openeo

# List backups
velero backup get

# Restore from backup
velero restore create --from-backup <backup-name>
```

### Step 9.3: Database Backups

```bash
# PostgreSQL backup script
cat <<'EOF' > /usr/local/bin/backup-openeo-db.sh
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
NAMESPACE=openeo
POD=$(kubectl get pod -n $NAMESPACE -l app=postgresql -o jsonpath='{.items[0].metadata.name}')
BACKUP_DIR=/export/openeo/backups/postgresql

mkdir -p $BACKUP_DIR

kubectl exec -n $NAMESPACE $POD -- pg_dump -U openeo openeo | gzip > $BACKUP_DIR/openeo_$DATE.sql.gz

# Keep last 7 days
find $BACKUP_DIR -name "openeo_*.sql.gz" -mtime +7 -delete
EOF

chmod +x /usr/local/bin/backup-openeo-db.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "0 1 * * * /usr/local/bin/backup-openeo-db.sh") | crontab -
```

---

## Operations & Maintenance

### Daily Operations

**Health Checks:**

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running

# Check OpenEO services
kubectl get pods -n openeo
kubectl get svc -n openeo
kubectl get ingress -n openeo

# Check logs
kubectl logs -n openeo -l app=openeo-argoworkflows-api --tail=100

# Test endpoints
curl -s https://openeo.eurac.edu/openeo/1.1.0/ | jq
```

**Monitoring:**

```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n openeo

# Check disk space
df -h /export/openeo

# Check ArgoCD sync status
argocd app get eoepca-eurac
```

### Scaling

**Scale OpenEO API:**

```bash
# Scale replicas
kubectl scale deployment openeo-argoworkflows-api -n openeo --replicas=3

# Or update in Helm values and sync via ArgoCD
```

**Scale Dask Workers:**

```bash
# Scale Dask workers
kubectl scale deployment dask-worker -n openeo --replicas=5
```

**Add Worker Nodes:**

```bash
# On new worker VM, join cluster
sudo kubeadm join k8s-lb:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# Label new node
kubectl label node k8s-worker-4 node-role.kubernetes.io/worker=worker
```

### Updates & Upgrades

**Update OpenEO Image:**

```bash
# Edit values in git repo
# Update image tag in helm-openeo-argoworkflows.yaml
git commit -m "Update OpenEO image to version X.Y.Z"
git push

# Sync via ArgoCD
argocd app sync eoepca-eurac
```

**Upgrade Kubernetes:**

```bash
# Upgrade master nodes one by one
# On each master:
sudo apt update
sudo apt-cache madison kubeadm
sudo apt-mark unhold kubeadm
sudo apt install -y kubeadm=1.29.1-00
sudo apt-mark hold kubeadm

sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.29.1

sudo apt-mark unhold kubelet kubectl
sudo apt install -y kubelet=1.29.1-00 kubectl=1.29.1-00
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Upgrade worker nodes
# On each worker:
kubectl drain k8s-worker-1 --ignore-daemonsets --delete-emptydir-data

# On worker node:
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt install -y kubeadm=1.29.1-00 kubelet=1.29.1-00 kubectl=1.29.1-00
sudo apt-mark hold kubeadm kubelet kubectl

sudo kubeadm upgrade node

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Uncordon
kubectl uncordon k8s-worker-1
```

---

## Troubleshooting

### Common Issues

**1. Pods Not Starting**

```bash
# Check pod status
kubectl describe pod <pod-name> -n openeo

# Check logs
kubectl logs <pod-name> -n openeo

# Check events
kubectl get events -n openeo --sort-by='.lastTimestamp'

# Check resource constraints
kubectl top nodes
kubectl top pods -n openeo
```

**2. Storage Issues**

```bash
# Check PVC status
kubectl get pvc -n openeo

# Check NFS server
showmount -e nfs-server

# Check NFS mounts on worker nodes
mount | grep nfs

# Test NFS manually
sudo mount -t nfs nfs-server:/export/openeo /mnt
ls -la /mnt
sudo umount /mnt
```

**3. Network/Ingress Issues**

```bash
# Check ingress
kubectl get ingress -n openeo
kubectl describe ingress openeo-ingress -n openeo

# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Test from pod
kubectl run test-pod --image=curlimages/curl -it --rm -- sh
# Inside pod:
curl http://openeo-argoworkflows-api.openeo/openeo/1.1.0/
```

**4. Database Connection Issues**

```bash
# Check PostgreSQL pod
kubectl get pods -n openeo -l app=postgresql
kubectl logs -n openeo -l app=postgresql

# Connect to database
kubectl exec -it -n openeo <postgresql-pod> -- psql -U openeo

# Inside psql:
\l  # List databases
\dt  # List tables
SELECT count(*) FROM jobs;
```

**5. Authentication Issues**

```bash
# Check Keycloak connectivity from cluster
kubectl run test-curl --image=curlimages/curl -it --rm -- sh
# Inside pod:
curl https://edp-portal.eurac.edu/auth/realms/edp/.well-known/openid-configuration

# Check OpenEO OIDC config
curl https://openeo.eurac.edu/openeo/1.1.0/credentials/oidc | jq
```

### Logs Collection

```bash
# Collect all OpenEO logs
kubectl logs -n openeo -l app=openeo-argoworkflows-api > openeo-api.log

# Collect system logs
journalctl -u kubelet > kubelet.log

# Create support bundle
kubectl cluster-info dump --output-directory=/tmp/cluster-dump
```

### Performance Tuning

**PostgreSQL:**

```yaml
# Tune PostgreSQL settings in values
postgresql:
  primary:
    extendedConfiguration: |
      max_connections = 100
      shared_buffers = 2GB
      effective_cache_size = 6GB
      work_mem = 20MB
      maintenance_work_mem = 512MB
```

**Dask Workers:**

```yaml
# Tune Dask workers
dask:
  worker:
    resources:
      limits:
        memory: 16Gi
        cpu: 8
    env:
      - name: DASK_DISTRIBUTED__WORKER__MEMORY__TARGET
        value: "0.8"
      - name: DASK_DISTRIBUTED__WORKER__MEMORY__SPILL
        value: "0.9"
```

---

## Security Hardening

### Network Policies

```bash
# Create network policy for OpenEO namespace
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openeo-network-policy
  namespace: openeo
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  - from:
    - podSelector: {}
  egress:
  - to:
    - podSelector: {}
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
  - ports:
    - port: 443
    - port: 80
EOF
```

### RBAC

```bash
# Create read-only user
kubectl create serviceaccount openeo-readonly -n openeo

# Create role
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: openeo-readonly
  namespace: openeo
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
EOF

# Bind role
kubectl create rolebinding openeo-readonly-binding \
  --role=openeo-readonly \
  --serviceaccount=openeo:openeo-readonly \
  --namespace=openeo
```

---

## Documentation & Resources

### Useful Commands Reference

```bash
# Quick health check
kubectl get nodes && kubectl get pods -A | grep -v Running

# Get external IPs
kubectl get svc -A | grep LoadBalancer

# Watch pod status
watch kubectl get pods -n openeo

# Follow logs
kubectl logs -f -n openeo <pod-name>

# Shell into pod
kubectl exec -it -n openeo <pod-name> -- /bin/bash

# Port forward for debugging
kubectl port-forward -n openeo svc/openeo-argoworkflows-api 8080:80

# Get resource usage
kubectl top nodes && kubectl top pods -n openeo
```

### Configuration Files

All configuration files are managed in Git:
- Helm values: `argocd/eoepca/openeo-argoworkflows/parts/helm-openeo-argoworkflows.yaml`
- Ingress: `argocd/eoepca/openeo-argoworkflows/parts/ingress-openeo.yaml`
- ArgoCD app: Managed via ArgoCD UI or CLI

### External Documentation

- Kubernetes: https://kubernetes.io/docs/
- Helm: https://helm.sh/docs/
- ArgoCD: https://argo-cd.readthedocs.io/
- OpenEO: https://openeo.org/documentation/
- cert-manager: https://cert-manager.io/docs/
- NGINX Ingress: https://kubernetes.github.io/ingress-nginx/

---

## Support & Contacts

**EURAC Team:**
- Infrastructure: Juraj Zvolensky
- OpenEO Development: Yuvraj Adagale
- General: IT Team

**External Support:**
- EOEPCA Community: https://github.com/EOEPCA
- OpenEO Community: https://openeo.org/community/

**Monitoring:**
- Grafana: https://grafana.eurac.edu
- ArgoCD: https://argocd.eurac.edu
- Prometheus: Access via Grafana

---

## Appendix

### A. Quick Start Checklist

- [ ] 7 VMs provisioned with Ubuntu 22.04
- [ ] Static IP addresses assigned
- [ ] DNS records configured
- [ ] SSH access configured
- [ ] Kubernetes cluster initialized
- [ ] CNI (Calico/Flannel) installed
- [ ] HAProxy load balancer configured
- [ ] NFS server setup
- [ ] NFS CSI driver installed
- [ ] cert-manager installed
- [ ] NGINX ingress controller installed
- [ ] MetalLB configured
- [ ] ArgoCD installed and configured
- [ ] OpenEO deployed via ArgoCD
- [ ] Monitoring stack installed
- [ ] Backup solution configured
- [ ] Test endpoints verified
- [ ] Documentation updated

### B. Estimated Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Infrastructure Setup | 2-3 days | VM provisioning |
| Kubernetes Cluster | 1-2 days | Infrastructure |
| Core Services | 2-3 days | Kubernetes |
| Storage | 1 day | NFS server |
| Networking | 1 day | DNS, LB |
| ArgoCD | 1 day | Git repo |
| OpenEO | 2-3 days | All above |
| Monitoring | 1-2 days | Kubernetes |
| Testing & Tuning | 3-5 days | OpenEO |
| **Total** | **2-4 weeks** | |

### C. Resource Requirements Summary

**Hardware:**
- 7 VMs (3 masters, 3 workers, 1 NFS)
- 44 CPU cores total
- 124 GB RAM total
- 2.6 TB storage total

**Network:**
- 1 public IP for load balancer
- Internal network for cluster communication
- DNS domain (openeo.eurac.edu)

**Software:**
- Ubuntu 22.04 LTS
- Kubernetes 1.29
- Docker/containerd
- Helm 3
- Various Kubernetes operators and controllers

---

**Document Version:** 1.0  
**Last Updated:** January 15, 2026  
**Author:** Yuvraj Adagale  
**Contact:** yadagale@eosao42.eurac.edu

---

**End of In-House Deployment Guide**
