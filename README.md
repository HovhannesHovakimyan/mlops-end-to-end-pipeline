# End-to-End MLOps Pipeline with Kubernetes

<a id="executive-summary"></a>
## Executive Summary

This project provides a practical blueprint for running machine learning in production, not just in experiments. It combines training, testing, deployment, and monitoring into one repeatable workflow on Kubernetes.

Why it matters:

- Reduces risk when promoting models from development to production.
- Improves delivery speed by automating build, train, test, and release steps.
- Increases traceability with model versioning, experiment tracking, and artifacts.
- Supports self-managed environments where teams need operational control.

Bottom line: if your team needs a credible, end-to-end MLOps reference that can be adapted to real workloads, this project is a strong starting point.

A production-grade MLOps platform demonstrating complete ML lifecycle management on-premises using Kubernetes, MLflow, KServe, MinIO, GitHub (repository), and GitLab (on-prem CI/CD).

This hybrid setup is intentional for portfolio impact: it showcases practical integration across diverse products (GitHub for collaboration and visibility, GitLab on-prem for enterprise CI/CD execution).

<a id="project-in-plain-english"></a>
## Project In Plain English

This project is a reusable template for teams that want to move an AI model from notebook experimentation into a reliable service that can be trained, tested, deployed, and monitored in a controlled way.

What problem it solves:

- Many AI projects work in demos but fail in production because training, deployment, and monitoring are disconnected.
- Teams struggle to reproduce results, track model versions, and safely roll out model updates.
- Manual operations increase delivery time and operational risk.

What you get from this project:

- A repeatable model lifecycle: train, validate, deploy, and monitor.
- Better governance: model history, metrics, and artifacts are tracked.
- Faster delivery: CI/CD automates common operational steps.
- Lower rollout risk: health checks and monitoring catch problems earlier.

Who should use it:

- Platform teams standardizing ML operations.
- ML engineers who need production-grade workflows.
- Organizations that prefer Kubernetes-based, self-managed environments.

When this project may not be the right fit:

- You need a fully managed cloud-only MLOps stack with minimal infrastructure ownership.
- Your use case is a lightweight prototype with no deployment or monitoring requirements.

Decision checklist:

- You want repeatable and auditable ML releases.
- You are comfortable operating Kubernetes.
- You need integration between source control, CI/CD, model tracking, and serving.
- You want a practical reference architecture you can adapt to your own workloads.

## 🎯 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitHub (Version Control)                    │
│                    - Pull Mirroring Source                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (On-Premises)                   │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │   MinIO      │  │   MLflow     │  │   KServe     │           │
│  │   (S3-like)  │  │  (Tracking)  │  │  (Serving)   │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
│         ↑                  ↑                 ↑                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │      Training Pipeline (GitLab Runner on K8s)            │   │
│  │  - Data Ingestion → Feature Engineering → Training       │   │
│  │  - Experiment Tracking (MLflow)                          │   │
│  │  - Model Versioning (MinIO)                              │   │
│  │  - Auto Deployment to KServe                             │   │
│  └──────────────────────────────────────────────────────────┘   │
│         ↑                                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │      Monitoring & Retraining Triggers                    │   │
│  │  - Prometheus (Metrics)                                  │   │
│  │  - Model Drift Detection                                 │   │
│  │  - Automated Retraining                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

Quick links:

- [Executive summary](#executive-summary)
- [Project in plain English](#project-in-plain-english)
- [Choose your execution path](#choose-execution-path)
- [Deploy infrastructure](#deploy-infrastructure)
- [Run training in Kubernetes](#run-training-in-kubernetes)
- [Deploy and monitoring jobs in GitLab CI](#deploy-monitoring-jobs)
- [Teardown guide](docs/TEARDOWN.md)

<a id="choose-execution-path"></a>
### Choose Your Execution Path

- **Path A (recommended for teams with existing GitLab): GitLab CI/CD**
    - Push code to GitHub.
    - Assumes your team already has a running GitLab instance and configured runners.
    - GitLab mirror triggers pipeline and builds/runs in Kubernetes.
    - You can skip manual image build and manual training job steps.
- **Path A2 (self-managed GitLab in your cluster):**
    - Deploy GitLab CE + GitLab Runner from `kubernetes/gitlab/` manifests.
    - All required CI infrastructure for this path runs inside the Kubernetes cluster.
    - No local runtime setup is required outside cluster tooling (`kubectl`/cluster access).
    - **Runner provisioning (recommended): Use API-based automation** via `06-runner-provisioner.sh` script or Kubernetes Job — fully automated, no manual UI steps.
    - Then use the same `.gitlab-ci.yml` CI flow as Path A.
    - For deploy/monitor CI guidance, see [Section 8](#deploy-monitoring-jobs).
    - See `docs/GITLAB_SELF_MANAGED.md` for setup instructions and provisioning options.
    - For cleanup, follow `docs/TEARDOWN.md`.
- **Path B (manual in-cluster test run):**
    - Intended for local development/testing workflows.
    - Build training image yourself and run a one-off Kubernetes Job.
    - Building the Docker image does not require local Python (it uses `python:3.11-slim` in-container).
    - Python 3.11 is only required if you run training/tests directly on your local machine.
    - Useful for quick validation without waiting for GitLab.

### Prerequisites
- Kubernetes cluster (v1.24+) and `kubectl` connected
- Docker (only if you build images locally)
- Git

### ⚠️ Path A2 Users: GitLab Setup Required First

If you plan to use **Path A2 (self-managed GitLab in your cluster)**, complete the GitLab + runner deployment **before** proceeding past Section 2:

→ **[Follow `docs/GITLAB_SELF_MANAGED.md` now](docs/GITLAB_SELF_MANAGED.md)**

This deploys GitLab CE and GitLab Runner into your cluster, which you'll need for the training pipeline in Section 4.

---

### 1. Clone repository

```bash
git clone https://github.com/HovhannesHovakimyan/mlops-end-to-end-pipeline.git
cd mlops-end-to-end-pipeline
```

<a id="deploy-infrastructure"></a>
### 2. Deploy infrastructure

Create or start your Kubernetes cluster before applying manifests. In this guide, we use Minikube.

Recommended Minikube cluster parameters for this project:

- Path B (manual run):

```bash
minikube start -p mlops-e2e --driver=docker --cpus=2 --memory=4096 --disk-size=20g
```

- Path A2 (self-managed GitLab + runner in cluster):

```bash
minikube start -p mlops-e2e --driver=docker --cpus=4 --memory=8192 --disk-size=40g
```

- Heavier setup (if deploy/monitor jobs are enabled, see [Deploy and monitoring jobs in GitLab CI](#deploy-monitoring-jobs)):

```bash
minikube start -p mlops-e2e --driver=docker --cpus=6 --memory=12288 --disk-size=50g
```

Quick preflight before applying manifests:

```bash
kubectl config current-context
kubectl cluster-info
kubectl get nodes
```

```bash
kubectl apply -f kubernetes/01-namespaces.yaml
kubectl apply -f kubernetes/02-minio.yaml
kubectl apply -f kubernetes/03-mlflow.yaml

# optional: static PV profile for clusters without dynamic provisioning
# (use this before 02-minio.yaml and 03-mlflow.yaml if PVCs stay Pending)
# kubectl apply -f kubernetes/storage-static-examples/00-pv-hostpath-single-node.example.yaml
# or edit/apply kubernetes/storage-static-examples/01-pv-nfs.example.yaml

# wait for core services
kubectl wait --for=condition=available --timeout=300s deployment/minio -n minio
kubectl wait --for=condition=available --timeout=300s deployment/mlflow -n mlflow

# create buckets once
kubectl exec -n minio deployment/minio -- mc alias set local http://minio.minio:9000 minioadmin minioadmin
kubectl exec -n minio deployment/minio -- mc mb -p local/training-data
kubectl exec -n minio deployment/minio -- mc mb -p local/model-registry
kubectl exec -n minio deployment/minio -- mc mb -p local/mlflow-artifacts
```

If MinIO or MLflow does not start, check PVC/PV binding first.

### Troubleshooting: PVC Pending

Run these checks:

```bash
kubectl get pvc -n minio
kubectl get pvc -n mlflow
kubectl get pv
kubectl get storageclass
kubectl describe pvc minio-pvc -n minio
kubectl describe pvc mlflow-pvc -n mlflow
```

How to interpret:

- If PVC is `Bound`: storage is fine. Check pod events/logs next.
- If PVC is `Pending` and there is no default StorageClass: use static PV profile from `kubernetes/storage-static-examples/`.
- If PVC is `Pending` and a default StorageClass exists: check StorageClass provisioner health and cluster events.

Apply static profile (optional path):

```bash
kubectl apply -f kubernetes/storage-static-examples/00-pv-hostpath-single-node.example.yaml
# or (after editing NFS values)
kubectl apply -f kubernetes/storage-static-examples/01-pv-nfs.example.yaml

kubectl apply -f kubernetes/02-minio.yaml
kubectl apply -f kubernetes/03-mlflow.yaml
```

If you use **Path A (existing GitLab CI/CD)**, continue with GitLab mirror/pipeline setup and skip to optional UI or inference steps.
If you use **Path A2 (self-managed GitLab)**, follow `docs/GITLAB_SELF_MANAGED.md`.

### 3. Build training image (no local Python required)

Path B only.

```bash
# If using minikube, build directly into minikube's Docker daemon
eval "$(minikube docker-env)"
docker build -f docker/Dockerfile.training -t mlops-sanity-training:latest .
```

<a id="run-training-in-kubernetes"></a>
### 4. Run training in Kubernetes

**Path A / A2:** Training is triggered automatically by the GitLab CI pipeline when you push to `main`. The `train` stage in `.gitlab-ci.yml` runs the training job inside the cluster and uploads the model to MinIO. No manual steps are needed here — push your code and the pipeline handles it.

**Path B only (manual run):**

```bash
kubectl delete job sanity-train -n default --ignore-not-found
cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
    name: sanity-train
    namespace: default
spec:
    backoffLimit: 0
    template:
        spec:
            restartPolicy: Never
            containers:
            - name: trainer
                image: mlops-sanity-training:latest
                imagePullPolicy: Never
                env:
                - name: MLFLOW_TRACKING_URI
                    value: http://mlflow.mlflow:5000
                - name: MINIO_ENDPOINT
                    value: http://minio.minio:9000
                - name: AWS_ACCESS_KEY_ID
                    value: minioadmin
                - name: AWS_SECRET_ACCESS_KEY
                    value: minioadmin
                - name: AWS_S3_ENDPOINT_URL
                    value: http://minio.minio:9000
                - name: MLFLOW_S3_ENDPOINT_URL
                    value: http://minio.minio:9000
                - name: AWS_DEFAULT_REGION
                    value: us-east-1
YAML

kubectl wait --for=condition=complete --timeout=600s job/sanity-train -n default
kubectl logs job/sanity-train -n default --tail=120
```

### 5. Optional: port-forward for UI access

```bash
kubectl port-forward -n minio svc/minio 9000:9000 &
kubectl port-forward -n minio svc/minio-console 9001:9001 &
kubectl port-forward -n mlflow svc/mlflow 5000:5000 &

export MLFLOW_TRACKING_URI=http://localhost:5000
export MINIO_ENDPOINT=http://localhost:9000
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
```

### 6. Optional local developer mode (requires Python 3.11)

```bash
python3.11 -m venv venv
source venv/bin/activate
pip install -r models/requirements.txt
pip install pytest pytest-cov black flake8 mypy

# run training locally
python pipelines/train_pipeline.py
```

### 7. Optional: deploy inference service to KServe

KServe supports two deployment modes. Choose based on your environment:

| | RawDeployment | Knative (Serverless) |
|---|---|---|
| **Scale to zero** | No | Yes |
| **Autoscaling** | HPA (CPU/memory) | KPA (request-driven) |
| **Traffic splitting / canary** | Via InferenceGraph | Native |
| **Extra dependencies** | None | Knative Serving + Istio or Kourier |
| **Resource overhead** | Low | ~3–4 GB extra RAM |
| **Recommended for** | Dev, local, resource-constrained clusters | Production, GPU cost optimisation |

#### Option A: RawDeployment (recommended for Minikube / local)

```bash
# install cert-manager (required by KServe for TLS)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl wait --for=condition=available --timeout=120s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=120s deployment/cert-manager-webhook -n cert-manager

# install KServe — server-side apply is required (avoids annotation size limit on large CRDs)
kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.19.0/kserve.yaml
kubectl wait --for=condition=available --timeout=120s deployment/kserve-controller-manager -n kserve

# install KServe serving runtimes (sklearn, xgboost, tensorflow, etc. — shipped separately)
kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.19.0/kserve-cluster-resources.yaml

# disable Istio virtual host (not needed for RawDeployment)
kubectl patch configmap inferenceservice-config -n kserve --type=merge \
  -p '{"data":{"ingress":"{\"enableGatewayApi\":false,\"kserveIngressGateway\":\"kserve/kserve-ingress-gateway\",\"ingressGateway\":\"knative-serving/knative-ingress-gateway\",\"localGateway\":\"knative-serving/knative-local-gateway\",\"localGatewayService\":\"knative-local-gateway.istio-system.svc.cluster.local\",\"ingressDomain\":\"example.com\",\"ingressClassName\":\"istio\",\"domainTemplate\":\"{{ .Name }}-{{ .Namespace }}.{{ .IngressDomain }}\",\"urlScheme\":\"http\",\"disableIstioVirtualHost\":true,\"disableIngressCreation\":true,\"disableHTTPRouteTimeout\":false}"}}'

# install Prometheus Operator (required for ServiceMonitor CRDs)
kubectl apply --server-side -f https://github.com/prometheus-operator/prometheus-operator/releases/latest/download/bundle.yaml
kubectl wait --for=condition=available --timeout=120s deployment/prometheus-operator -n default

kubectl apply -f kubernetes/04-kserve-inference-service.yaml
kubectl get inferenceservice -n kserve
```

#### Option B: Knative Serverless (production-grade, requires ~8 GB+ RAM)

```bash
# install cert-manager (required by KServe for TLS)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl wait --for=condition=available --timeout=120s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=120s deployment/cert-manager-webhook -n cert-manager

# install Knative Serving
kubectl apply -f https://github.com/knative/serving/releases/latest/download/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/latest/download/serving-core.yaml

# install Kourier as the networking layer (lighter than Istio)
kubectl apply -f https://github.com/knative/net-kourier/releases/latest/download/kourier.yaml
kubectl patch configmap/config-network -n knative-serving \
  --type merge -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
kubectl wait --for=condition=available --timeout=180s deployment/net-kourier-controller -n kourier-system

# install KServe — server-side apply is required (avoids annotation size limit on large CRDs)
kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.19.0/kserve.yaml
kubectl wait --for=condition=available --timeout=120s deployment/kserve-controller-manager -n kserve

# install KServe serving runtimes (sklearn, xgboost, tensorflow, etc. — shipped separately)
kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.19.0/kserve-cluster-resources.yaml

# install Prometheus Operator (required for ServiceMonitor CRDs)
kubectl apply --server-side -f https://github.com/prometheus-operator/prometheus-operator/releases/latest/download/bundle.yaml
kubectl wait --for=condition=available --timeout=120s deployment/prometheus-operator -n default

# remove the RawDeployment annotation from the InferenceService before applying
# (edit kubernetes/04-kserve-inference-service.yaml and delete the
#  serving.kserve.io/deploymentMode: RawDeployment annotation line)
kubectl apply -f kubernetes/04-kserve-inference-service.yaml
kubectl get inferenceservice -n kserve
```

> **Note:** The InferenceService will stay in a non-Ready state until the training pipeline (step 4) has run and uploaded the model to MinIO at `s3://model-registry/churn-model/latest/model.pkl`. This is expected — once the model is present, KServe will automatically load it and the service will become Ready.

<a id="deploy-monitoring-jobs"></a>
### 8. Deploy and monitoring jobs in GitLab CI (optional)

By default, deploy and monitor jobs are disabled in `.gitlab-ci.yml`:

- `ENABLE_DEPLOY_JOBS="false"`
- `ENABLE_MONITOR_JOBS="false"`

Enable them only when your cluster and CI environment are ready.

Prerequisites:

- KServe CRDs installed and `kserve` namespace available
- GitLab runner has Kubernetes access for deploy/monitor stages
- CI variable `KUBE_CONTEXT` is set for production deploy job
- CI variable `KUBE_CONTEXT_STAGING` is set for staging deploy job
- In-cluster DNS/network paths are reachable:
    - `http://churn-predictor.kserve/health`
    - `http://mlflow.mlflow:5000/`

How to enable:

1. Open GitLab project CI/CD variables.
2. Set `ENABLE_DEPLOY_JOBS` to `true`.
3. Set `ENABLE_MONITOR_JOBS` to `true`.
4. Ensure `KUBE_CONTEXT` and `KUBE_CONTEXT_STAGING` are present and valid.
5. Run a pipeline on `main`.

Expected behavior:

- `deploy:kserve` and `deploy:staging` appear as manual jobs.
- After deploy jobs run, `monitor:inference` and `monitor:mlflow` run automatically.
- Successful monitor jobs confirm service health endpoints are reachable from the runner.

Quick verification commands:

```bash
kubectl get inferenceservice -n kserve
kubectl get pods -n kserve
kubectl get svc -n mlflow
```

## 📁 Project Structure

```
mlops-end-to-end-pipeline/
├── .gitlab-ci.yml
├── Makefile
├── setup.sh
├── docker/
│   ├── Dockerfile.training
│   └── Dockerfile.serving
├── kubernetes/
│   ├── 01-namespaces.yaml
│   ├── 02-minio.yaml
│   ├── 03-mlflow.yaml
│   └── 04-kserve-inference-service.yaml
├── models/
│   ├── predict.py
│   ├── requirements.txt
│   └── test_pipeline.py
├── pipelines/
│   └── train_pipeline.py
├── monitoring/
│   ├── alerts.yml
│   └── prometheus.yml
└── docs/
    ├── ARCHITECTURE.md
    ├── SETUP.md
    ├── DEVELOPMENT.md
    └── TEARDOWN.md
```

## 🔄 Workflow

### Training Workflow
1. **Trigger**: Push to `main` branch or scheduled daily
2. **Data Ingestion**: Fetch data from MinIO
3. **Feature Engineering**: Transform raw data
4. **Training**: Train model with MLflow experiment tracking
5. **Evaluation**: Validate against baseline
6. **Registry**: Store in MLflow Model Registry
7. **Serving**: Deploy to KServe via canary rollout

### Model Serving
- KServe handles A/B testing between model versions
- Canary deployment: 90% traffic to current, 10% to new model
- Automatic rollback if metrics degrade
- Prometheus metrics for latency, throughput, accuracy

### Monitoring & Retraining
- Prometheus tracks prediction metrics
- Model drift detector alerts when accuracy drops >5%
- Automated retraining triggered on drift detection
- Historical model versions retained for rollback

## 🛠️ Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Data Storage** | MinIO | S3-compatible object storage |
| **Experiment Tracking** | MLflow | Model versioning & metrics logging |
| **Model Serving** | KServe | Production inference serving |
| **Orchestration** | Kubernetes | Container orchestration |
| **CI/CD** | GitLab CI/CD (on-prem) | Automated training & deployment |
| **Monitoring** | Prometheus + Grafana | Metrics & dashboards |
| **Framework** | scikit-learn/PyTorch | ML model training |

## 📊 Example: Churn Prediction Model

This project includes a **Customer Churn Prediction** model as reference:
- **Input**: Customer demographics, account features
- **Output**: Probability of churn (0-1)
- **Baseline**: 85% accuracy
- **Target**: 90% accuracy with <50ms latency

## 🔐 Security Considerations

- ✅ MinIO with encryption at rest
- ✅ MLflow password-protected
- ✅ KServe with TLS enabled
- ✅ RBAC for all K8s resources
- ✅ GitLab CI/CD variables for credentials

## 📈 Performance Targets

| Metric | Target | Status |
|--------|--------|--------|
| Model Training Time | <10 minutes | 📊 |
| Inference Latency (p99) | <100ms | 📊 |
| Data Pipeline Throughput | >1000 rows/sec | 📊 |
| Availability | 99.5% | 📊 |

## 🧪 Testing

```bash
source venv/bin/activate
pytest models/test_pipeline.py -v
pytest models/ -v --cov=models/ --cov-report=term
```

## 🚢 Deployment Checklist

- [ ] Kubernetes cluster ready
- [ ] MinIO configured and accessible
- [ ] MLflow server running
- [ ] KServe installed on cluster
- [ ] GitLab CI/CD configured
- [ ] Docker registry accessible
- [ ] Monitoring stack deployed
- [ ] Model trained and registered
- [ ] KServe InferenceService deployed

## 📚 Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Detailed system design
- [SETUP.md](docs/SETUP.md) - Installation & configuration
- [DEVELOPMENT.md](docs/DEVELOPMENT.md) - Development workflow
- [TEARDOWN.md](docs/TEARDOWN.md) - Step-by-step cluster and Minikube cleanup

Quick teardown command:

```bash
make teardown-path-a2
```

This deletes Kubernetes resources and the temporary `path-a2-test` Minikube cluster profile only. It does not uninstall Minikube.

## 🤝 Contributing

1. Create feature branch from `develop`
2. Commit changes with clear messages
3. Push and create pull request
4. Pipeline must pass before merge
5. Deploy to staging, then production

## 📝 License

MIT License - See LICENSE file

## 🎓 Learning Resources

- [MLflow Documentation](https://mlflow.org/docs/latest/)
- [KServe Documentation](https://kserve.github.io/website/)
- [MinIO Kubernetes Docs](https://docs.min.io/docs/minio-kubernetes-operator.html)
- [GitLab CI/CD](https://docs.gitlab.com/ee/ci/)

---

**Portfolio Project**: End-to-End MLOps Pipeline on Kubernetes
**Created**: June 2026
