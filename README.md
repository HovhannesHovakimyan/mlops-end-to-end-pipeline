# End-to-End MLOps Pipeline with Kubernetes

A production-grade MLOps platform demonstrating complete ML lifecycle management on-premises using Kubernetes, MLflow, KServe, MinIO, GitHub (repository), and GitLab (on-prem CI/CD).

This hybrid setup is intentional for portfolio impact: it showcases practical integration across diverse products (GitHub for collaboration and visibility, GitLab on-prem for enterprise CI/CD execution).

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

### Prerequisites
- Kubernetes cluster (v1.24+) and `kubectl` connected
- Docker (only if you build images locally)
- Git

### 1. Clone repository

```bash
git clone https://github.com/HovhannesHovakimyan/mlops-end-to-end-pipeline.git
cd mlops-end-to-end-pipeline
```

### 2. Deploy infrastructure

```bash
kubectl apply -f kubernetes/01-namespaces.yaml
kubectl apply -f kubernetes/02-minio.yaml
kubectl apply -f kubernetes/03-mlflow.yaml

# wait for core services
kubectl wait --for=condition=available --timeout=300s deployment/minio -n minio
kubectl wait --for=condition=available --timeout=300s deployment/mlflow -n mlflow

# create buckets once
kubectl exec -n minio deployment/minio -- mc alias set local http://minio.minio:9000 minioadmin minioadmin
kubectl exec -n minio deployment/minio -- mc mb -p local/training-data
kubectl exec -n minio deployment/minio -- mc mb -p local/model-registry
kubectl exec -n minio deployment/minio -- mc mb -p local/mlflow-artifacts
```

### 3. Build training image (no local Python required)

```bash
# If using minikube, build directly into minikube's Docker daemon
eval "$(minikube docker-env)"
docker build -f docker/Dockerfile.training -t mlops-sanity-training:latest .
```

### 4. Run training in Kubernetes

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

```bash
# install KServe if not already installed
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml

kubectl apply -f kubernetes/04-kserve-inference-service.yaml
kubectl get inferenceservice -n kserve
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
    └── DEVELOPMENT.md
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
