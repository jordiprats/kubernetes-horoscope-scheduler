# 🪐 Kubernetes Horoscope Scheduler

An **astrology-driven** Kubernetes scheduler written in **bash**. Pods are assigned to nodes based on zodiac sign compatibility – no labels, no resource constraints, just fate.

## How it works

1. The scheduler watches for pending pods that specify `schedulerName: horoscopeScheduler`.
2. It reads the pod's `creationTimestamp` and computes its **zodiac sign** (Aries, Taurus, …).
3. It looks up the **compatible sign** (e.g., Aries pods get Leo nodes).
4. It reads **every node's** `creationTimestamp` and computes each node's zodiac sign.
5. It selects a node whose zodiac matches the compatible sign.
6. It binds the pod to that node via the Kubernetes API.

## How Kubernetes discovers this scheduler

There is **no global scheduler registration** needed. Kubernetes allows multiple schedulers – each pod simply declares which scheduler to use via the `schedulerName` field in its spec. The default scheduler ignores pods that don't belong to it.

This scheduler watches for pods with `schedulerName: horoscopeScheduler` and binds them. No changes to the cluster control plane are required.

## Prerequisites

- A Kubernetes cluster (minikube, kind, k3s, or any real cluster)
- `kubectl` installed and configured
- `curl` installed

## Installation

### Quick start (development)

1. Expose the Kubernetes API:
   ```bash
   kubectl proxy &
   ```

2. Run the scheduler:
   ```bash
   ./horoscope-scheduler.sh
   ```

3. Deploy a pod with `schedulerName: horoscopeScheduler` (see below).

### ⚡ Production deployment (Helm chart) [someone might recommend this, but not me]

> **Disclaimer:** Using this scheduler in production is cosmically inadvisable. Your pods will be scheduled by the stars, not by resource availability. You have been warned. 🔮

That said, the included **Helm chart** makes it easy to deploy the scheduler inside your cluster so it runs as a proper pod with RBAC.

```bash
# Install from source
cd helm/horoscope-scheduler
helm install horoscope-scheduler . --namespace default
```

Or with custom values:

```bash
helm install horoscope-scheduler . \
  --namespace default \
  --set scheduler.server=kubernetes.default.svc \
  --set scheduler.name=horoscopeScheduler
```

The chart will conjure up:
- A `ServiceAccount` with a `ClusterRole` granting `get/list/watch` on pods and nodes, plus `create` on pods/binding.
- A `ConfigMap` containing the sacred scheduler script.
- A `Deployment` to run the scheduler as a cluster pod, forever gazing at the stars.

### 🏭 Production deployment (manual – for non-believers in Helm)

If you reject the Helm way and prefer a sacrifice to the YAML god:

#### 1. Create a service account and RBAC

Give the scheduler the permissions it needs to peer into the cluster's destiny:

```yaml
# rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: horoscope-scheduler
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: horoscope-scheduler
rules:
- apiGroups: [""]
  resources: ["pods", "nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/binding"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: horoscope-scheduler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: horoscope-scheduler
subjects:
- kind: ServiceAccount
  name: horoscope-scheduler
  namespace: default
```

Apply your incantation:

```bash
kubectl apply -f rbac.yaml
```

#### 2. Deploy the scheduler as a pod

Create a ConfigMap that holds the ancient script, then a Deployment to run it:

```yaml
# scheduler.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: horoscope-scheduler-script
data:
  scheduler.sh: |
    (paste the contents of horoscope-scheduler.sh here)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: horoscope-scheduler
  labels:
    app: horoscope-scheduler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: horoscope-scheduler
  template:
    metadata:
      labels:
        app: horoscope-scheduler
    spec:
      serviceAccountName: horoscope-scheduler
      containers:
      - name: scheduler
        image: bash:latest
        command:
        - bash
        - /scripts/scheduler.sh
        env:
        - name: SERVER
          value: "kubernetes.default.svc"
        - name: SCHEDULER
          value: "horoscopeScheduler"
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: horoscope-scheduler-script
```

Apply your summoning:

```bash
kubectl apply -f scheduler.yaml
```

The scheduler will rise as a pod inside the cluster and automatically discover pending pods by reading the cosmic alignment of their creation timestamps.

> **Note:** The in-cluster API endpoint is `kubernetes.default.svc` (port 443). The script uses HTTP by default – if your cluster requires HTTPS, set `SERVER=https://kubernetes.default.svc:443` or use `kubectl proxy` as a sidecar.

#### 3. Deploy a pod that uses this scheduler

Set `schedulerName: horoscopeScheduler` in your pod spec so the stars know to guide it:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-horoscope-pod
spec:
  schedulerName: horoscopeScheduler
  containers:
  - name: main
    image: nginx:latest
```

The pod will remain in `Pending` state until this scheduler reads its horoscope **and** a compatible node exists. If no node with a matching zodiac exists yet, the scheduler patiently waits for the stars to align – it will keep checking until a node with the right zodiac sign appears. No fallback, no compromise. Astrology is absolute.

## Configuration

| Environment Variable | Default | Description |
|----------------------|---------|-------------|
| `SERVER`             | `localhost:8001` | API server address |
| `SCHEDULER`          | `horoscopeScheduler` | Scheduler name to match in pod specs |

Override them:

```bash
SERVER=https://kubernetes.default.svc:443 SCHEDULER=my-custom-scheduler ./horoscope-scheduler.sh
```

## Compatibility Matrix

Each zodiac sign is paired with a compatible partner using a circular offset of +4:

| Pod Sign    | → Node Sign     |
|-------------|----------------|
| Aries       | Leo            |
| Taurus      | Virgo          |
| Gemini      | Libra          |
| Cancer      | Scorpio        |
| Leo         | Sagittarius    |
| Virgo       | Capricorn      |
| Libra       | Aquarius       |
| Scorpio     | Pisces         |
| Sagittarius | Aries          |
| Capricorn   | Taurus         |
| Aquarius    | Gemini         |
| Pisces      | Cancer         |

## How to stop

- If running locally: `Ctrl+C` or `kill $(pgrep -f horoscope-scheduler.sh)`.
- If running as a Deployment: `kubectl delete deployment horoscope-scheduler`.
