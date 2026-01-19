
---

#  Kubernetes kubeadm Cluster Setup – 
---

##  What kubeadm Actually Does

`kubeadm` is **NOT Kubernetes itself**.

It is:

> A **bootstrap tool** that initializes and joins nodes to a Kubernetes cluster.

### kubeadm responsibilities:

* Generates TLS certificates
* Configures kubelet
* Bootstraps control-plane components
* Creates secure join workflow for workers

### kubeadm does **NOT**:

* Configure OS
* Install container runtime
* Configure networking
* Manage lifecycle after bootstrap

➡️ **That’s why prerequisites are mandatory.**

---

# 🧱 Architecture Overview

```
┌────────────┐
│   kubectl  │
└─────┬──────┘
      │
┌─────▼──────┐        ┌────────────────────┐
│ API Server │◄──────►│  etcd (key-value)  │
└─────┬──────┘        └────────────────────┘
      │
┌─────▼───────────┐
│ Controller Mgr  │
└─────┬───────────┘
      │
┌─────▼───────────┐
│ Scheduler       │
└─────────────────┘

Workers:
kubelet → containerd → pods
```

---

# 🔹 STEP 1: Disable Swap

### 🔧 What we do

```bash
swapoff -a
```

---

### ❓ What is Swap?

Swap is **disk-based memory extension**.
When RAM is full, Linux moves memory pages to disk.

---

### ❌ Why Kubernetes Does NOT Allow Swap

Kubernetes **assumes memory behavior is deterministic**.

Problems with swap:

* Pods appear to have memory but are actually swapped out
* Scheduler makes wrong decisions
* OOM killer behavior becomes unpredictable
* Performance degradation under pressure

👉 kubelet enforces:

```text
failSwapOn = true
```

If swap exists → kubelet **refuses to start**.

---

### 🧠 Interview Answer

> Kubernetes disables swap to ensure predictable memory management and reliable scheduling decisions.

---

# 🔹 STEP 2: Kernel Modules (`overlay`, `br_netfilter`)

### 🔧 What we do

```bash
modprobe overlay
modprobe br_netfilter
```

---

## 🧩 `overlay` Module

### What it is

* Filesystem driver used by **container images**
* Enables **layered filesystem**

### Why needed

* containerd uses overlayfs to manage image layers
* Without it, containers may fail to start

📦 Example:

```
base-image
  └── app-layer
      └── runtime-layer
```

---

## 🌉 `br_netfilter` Module

### What it is

* Allows **iptables to see bridged traffic**

### Why Kubernetes needs it

* Pod-to-pod traffic flows through Linux bridges
* iptables rules (NetworkPolicy, Service routing) must inspect that traffic

Without it:

* Network policies don’t work
* Service routing breaks

---

### 🧠 Interview Answer

> `br_netfilter` allows Kubernetes networking rules to apply to bridged pod traffic.

---

# 🔹 STEP 3: sysctl Networking Parameters

### 🔧 What we do

```bash
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
```

---

## 🌐 Why `ip_forward` is Needed

### What it does

* Allows Linux to forward packets between interfaces

### Why disabled by default

* Linux defaults to **host-only routing** (security-first)
* Not intended to act as router by default

### Why Kubernetes needs it

* Pods live on **different virtual networks**
* Node must forward traffic between:

  * Pod ↔ Pod
  * Pod ↔ Service
  * Pod ↔ External world

Without it:

* Pods cannot reach outside network
* Services break

---

## 🔥 `bridge-nf-call-iptables`

### What it does

* Forces bridged traffic through iptables chains

### Why Kubernetes needs it

* kube-proxy uses iptables
* NetworkPolicy enforcement relies on iptables
* Service routing depends on it

---

### 🧠 Interview Answer

> Kubernetes nodes must behave like routers, not just hosts, hence IP forwarding is enabled.

---

# 🔹 STEP 4: Container Runtime (containerd)

### ❓ What is containerd?

containerd is the **container runtime** that:

* Pulls images
* Creates containers
* Manages lifecycle

Docker was:

```
Docker CLI → dockerd → containerd → runc
```

Now Kubernetes talks **directly to containerd**.

---

## 🔥 Why systemd cgroups?

### What are cgroups?

* Linux resource isolation mechanism
* CPU, memory, pids control

### systemd vs cgroupfs

| systemd            | cgroupfs    |
| ------------------ | ----------- |
| OS-native          | legacy      |
| Stable             | error-prone |
| kubelet-compatible | deprecated  |

If mismatched:

* kubelet crashloops
* pods fail under load

---

### 🧠 Interview Answer

> Kubernetes requires the container runtime and kubelet to use the same cgroup driver for stability.

---

# 🔹 STEP 5: kubelet, kubeadm, kubectl

### kubeadm

* Bootstraps cluster
* Manages certificates
* Generates join tokens

### kubelet

* Node agent
* Talks to API server
* Manages pods on node

### kubectl

* CLI client
* Communicates with API server

---

## 🔒 Why Version Pinning?

```bash
apt-mark hold kubelet kubeadm kubectl
```

### Reason

* Kubernetes has **strict version skew rules**
* Auto-upgrades can:

  * Break cluster
  * Cause API incompatibilities

Production rule:

> **Upgrades must be deliberate, not automatic**

---

# 🔹 STEP 6: kubeadm init (Master)

### What happens internally

1. Generates CA certificates
2. Creates static pod manifests:

   * API server
   * Scheduler
   * Controller Manager
3. Starts etcd
4. Writes kubeconfig
5. Creates bootstrap tokens

---

### Why `--apiserver-advertise-address`

This tells cluster:

* “This is how nodes reach the API server”

Wrong IP → cluster unreachable.

---

### Why `--pod-network-cidr`

Each CNI requires:

* Predefined pod IP range
* Prevents IP conflicts

Calico standard:

```
192.168.0.0/16
```

---

# 🔹 STEP 7: CNI (Calico)

### Why CNI is required

Kubernetes **does NOT ship networking**.

CNI provides:

* Pod IP allocation
* Pod-to-pod routing
* Network policies

Without CNI:

```
Node = NotReady
```

---

### Why Calico

* Widely used
* Supports NetworkPolicy
* Production proven
* Interview-safe choice

---

# 🔹 STEP 8: kubeadm join (Workers)

### What happens during join

1. Worker validates CA hash
2. Secure TLS bootstrap
3. kubelet registers node
4. Control plane approves CSR
5. Node becomes schedulable

---

# 🔐 Security Model Behind kubeadm

* Mutual TLS everywhere
* Short-lived join tokens
* CA pinning via hash
* No plaintext trust


---

# 🧠 Summary: Why Each Step Exists

| Step           | Why                    |
| -------------- | ---------------------- |
| Disable swap   | Predictable memory     |
| Kernel modules | Container + networking |
| Sysctl         | Routing + firewall     |
| containerd     | CRI runtime            |
| systemd cgroup | Stability              |
| kubeadm init   | Bootstrap              |
| CNI            | Pod networking         |
| Join token     | Secure node onboarding |

---



