# Setup & Installation Guide

## Prerequisites

- **Kubernetes Cluster**: v1.24+ on-premises
- **kubectl**: Configured and connected to your cluster
- **Docker**: v20.10+ for building images
- **GitHub**: Repository with Actions enabled
- **Helm** (optional): For easier package management
- **Disk Space**: At least 100GB available for storage

### Cluster Requirements
- **Minimum 3 nodes** with at least 16GB memory each
- **Network**: All nodes must communicate with each other
- **Storage**: Persistent storage provisioner available

## Installation Steps

### Step 1: Clone the Repository

```bash
git clone https://github.com/your-org/mlops-end-to-end-pipeline.git
cd mlops-end-to-end-pipeline
```

### Step 2: Create Namespaces

Deploy the namespaces for all services:

```bash
kubectl apply -f kubernetes/01-namespaces.yaml
```

Verify namespaces are created:

```bash
kubectl get namespaces | grep -E 'minio|mlflow|kserve'
```

### Step 3: Deploy MinIO (Object Storage)

```bash
# Create MinIO deployment
kubectl apply -f kubernetes/02-minio.yaml

# Verify pods are running
kubectl get pods -n minio

# Port-forward for UI access
kubectl port-forward -n minio svc/minio-console 9001:9001 &
```

Access MinIO UI at `http://localhost:9001`
- Username: `minioadmin`
- Password: `minioadmin`

Create necessary buckets in MinIO:
```bash
kubectl exec -it -n minio deployment/minio -- /bin/bash

# Inside container:
mc alias set minio http://localhost:9000 minioadmin minioadmin
mc mb minio/training-data
mc mb minio/model-registry
mc mb minio/mlflow-artifacts
```

### Step 4: Deploy MLflow (Experiment Tracking)

```bash
# Create MLflow deployment
kubectl apply -f kubernetes/03-mlflow.yaml

# Verify pods are running
kubectl get pods -n mlflow

# Port-forward for UI access
kubectl port-forward -n mlflow svc/mlflow 5000:5000 &
```

Access MLflow UI at `http://localhost:5000`

### Step 5: Install KServe (Model Serving)

If not already installed on your cluster, install KServe:

```bash
# Install KServe operator
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml

# Wait for KServe operator to be ready
kubectl wait --for=condition=Progressing=True deployment -l control-plane=kserve-controller-manager -n kserve --timeout=300s

# Create KServe namespace (if not exists)
kubectl apply -f kubernetes/01-namespaces.yaml
```

### Step 6: Deploy Monitoring Stack

```bash
# Create Prometheus namespace
kubectl create namespace monitoring || true

# Deploy Prometheus with our config
kubectl apply -f monitoring/prometheus.yml -n monitoring

# Deploy Grafana (optional)
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set adminPassword=admin \
  --set persistence.enabled=true \
  --set persistence.size=10Gi
```

### Step 7: Configure GitLab On-Prem CI/CD (with GitHub as Repo)

Use GitHub as the source repository and GitLab on-prem as the CI/CD executor:

This is an intentional architecture choice to showcase integration across diverse products in a single MLOps platform.

1. In GitLab on-prem, create a project and enable repository pull mirroring from your GitHub repository.
2. Ensure your GitLab Runner is available to that project.
3. Keep `.gitlab-ci.yml` in this repository root (already present).

Configure these CI/CD variables in GitLab project settings:
- `REGISTRY_USER`
- `REGISTRY_PASSWORD`
- `MLFLOW_TRACKING_URI`
- `MINIO_ENDPOINT`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

#### Recommended: GitHub -> GitLab Pull Mirroring Setup

Use this as the default integration path:

1. In GitLab project, open `Settings -> Repository -> Mirroring repositories`.
2. Add mirror URL: `https://github.com/<org>/<repo>.git`.
3. Authentication:
  - Use a GitHub PAT with read access to the repository.
  - Store credentials in GitLab securely (masked/protected where available).
4. Set mirror direction to `Pull`.
5. Enable `Only mirror protected branches` (recommended for production flow).
6. Set mirror cadence to your operational target (e.g., every 1-5 minutes).
7. In GitLab CI/CD settings, ensure pipelines run on mirrored updates to `main`.

Expected behavior:
- You push to GitHub.
- GitLab pulls the new commit on the mirror interval.
- GitLab Runner (on Kubernetes) executes `.gitlab-ci.yml`.

Portfolio note:
This setup intentionally demonstrates cross-platform integration: GitHub for public collaboration and visibility, GitLab on-prem for enterprise CI/CD execution.

### Step 8: Build Docker Images

```bash
# Build training image
docker build -f docker/Dockerfile.training -t mlops-pipeline:training-latest .

# Build serving image
docker build -f docker/Dockerfile.serving -t mlops-pipeline:serving-latest .

# Push to your registry
docker tag mlops-pipeline:training-latest your-registry/mlops-pipeline:training-latest
docker push your-registry/mlops-pipeline:training-latest

docker tag mlops-pipeline:serving-latest your-registry/mlops-pipeline:serving-latest
docker push your-registry/mlops-pipeline:serving-latest
```

### Step 9: Configure Environment Variables

Create a `.env` file with your settings:

```bash
# MinIO
MINIO_ENDPOINT=http://minio.minio:9000
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin

# MLflow
MLFLOW_TRACKING_URI=http://mlflow.mlflow:5000

# Kubernetes
KUBE_CONTEXT=your-cluster-context
KUBE_CONTEXT_STAGING=your-staging-context

# Registry
REGISTRY=your-registry.com
REGISTRY_USER=your-user
REGISTRY_PASSWORD=your-password
```

### Step 10: Push to GitHub

```bash
# Initialize git repo (if not done)
git init
git add .
git commit -m "Initial commit: MLOps end-to-end pipeline"
git remote add origin https://github.com/your-org/mlops-end-to-end-pipeline.git
git branch -M main
git push -u origin main
```

GitLab on-prem pipeline will trigger after mirror sync (or via webhook-triggered sync).

## Verification

### Check All Services

```bash
# Verify all pods are running
kubectl get pods -A | grep -E 'minio|mlflow|kserve'

# Check pod logs for errors
kubectl logs -n minio deployment/minio
kubectl logs -n mlflow deployment/mlflow

# Verify services are accessible
kubectl port-forward -n minio svc/minio 9000:9000 &
kubectl port-forward -n mlflow svc/mlflow 5000:5000 &
```

### Test Training Pipeline

```bash
# Run training job manually
kubectl create job test-training \
  --image=your-registry/mlops-pipeline:training-latest \
  -n default

# Monitor job progress
kubectl logs -f job/test-training

# Check if model was registered in MLflow
curl http://localhost:5000/api/2.0/registered-models
```

### Test Inference Service

```bash
# Deploy KServe InferenceService
kubectl apply -f kubernetes/04-kserve-inference-service.yaml

# Port-forward KServe service
kubectl port-forward -n kserve svc/kserve-predictor 8080:8080 &

# Test prediction
curl -X POST http://localhost:8080/predict \
  -H "Content-Type: application/json" \
  -d '{
    "tenure": 12,
    "monthly_charges": 65.0,
    "total_charges": 780.0,
    "contract_length": 1,
    "internet_service": 1,
    "monthly_services": 4
  }'
```

## Common Issues

### 1. MinIO Pod Not Starting

```bash
# Check pod status
kubectl describe pod -n minio deployment/minio

# Check PVC is bound
kubectl get pvc -n minio

# If PVC pending, create a StorageClass:
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
```

### 2. MLflow Cannot Connect to MinIO

```bash
# Verify MinIO is running
kubectl get svc -n minio

# Check environment variables in MLflow pod
kubectl exec -n mlflow deployment/mlflow -- env | grep AWS

# Test connectivity from MLflow pod
kubectl exec -n mlflow deployment/mlflow -- \
  python -c "import boto3; s3=boto3.client('s3', endpoint_url='http://minio.minio:9000'); print(s3.list_buckets())"
```

### 3. GitLab Runner Cannot Reach Kubernetes

```bash
# Verify required GitLab CI/CD variables are configured
# - MLFLOW_TRACKING_URI
# - MINIO_ENDPOINT
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY

# Re-run pipeline from GitLab UI
# CI/CD -> Pipelines -> Run pipeline
```

### 4. KServe InferenceService Stuck in Creating

```bash
# Check KServe operator logs
kubectl logs -n kserve -l control-plane=kserve-controller-manager

# Check InferenceService status
kubectl describe inferenceservice churn-predictor -n kserve

# Check if model download is stuck
kubectl logs -n kserve -l app=churn-predictor
```

## Next Steps

1. **Configure GitLab CI/CD**: Update `.gitlab-ci.yml` with your registry and cluster details
2. **Set up Monitoring**: Access Grafana and create dashboards for your metrics
3. **Run First Pipeline**: Push code to trigger training and deployment
4. **Configure Alerts**: Set up notifications for failures and performance issues

See [DEVELOPMENT.md](DEVELOPMENT.md) for development workflow.
