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
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   MinIO      │  │   MLflow     │  │   KServe     │          │
│  │   (S3-like)  │  │  (Tracking)  │  │  (Serving)   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         ↑                  ↑                 ↑                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │      Training Pipeline (GitLab Runner on K8s)            │   │
│  │  - Data Ingestion → Feature Engineering → Training       │   │
│  │  - Experiment Tracking (MLflow)                          │   │
│  │  - Model Versioning (MinIO)                              │   │
│  │  - Auto Deployment to KServe                             │   │
│  └──────────────────────────────────────────────────────────┘   │
│         ↑                                                        │
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
- Kubernetes cluster (v1.24+)
- kubectl configured
- GitLab on-prem with Runner deployed on Kubernetes
- Docker
- At least 16GB memory available on cluster

### 1. Deploy Infrastructure

```bash
# Deploy MinIO (S3-like storage)
kubectl apply -f kubernetes/minio-namespace.yaml
kubectl apply -f kubernetes/minio-pvc.yaml
kubectl apply -f kubernetes/minio-deployment.yaml
kubectl apply -f kubernetes/minio-service.yaml

# Deploy MLflow (Experiment tracking & model registry)
kubectl apply -f kubernetes/mlflow-namespace.yaml
kubectl apply -f kubernetes/mlflow-configmap.yaml
kubectl apply -f kubernetes/mlflow-pvc.yaml
kubectl apply -f kubernetes/mlflow-deployment.yaml
kubectl apply -f kubernetes/mlflow-service.yaml

# Deploy KServe (Model serving)
kubectl apply -f kubernetes/kserve-namespace.yaml
kubectl apply -f kubernetes/kserve-inference-service.yaml
```

### 2. Verify Deployments
```bash
# Check all pods
kubectl get pods -A

# Port-forward services for local access
kubectl port-forward -n minio svc/minio 9000:9000 &
kubectl port-forward -n mlflow svc/mlflow 5000:5000 &
kubectl port-forward -n kserve svc/kserve-predictor 8080:8080 &
```

### 3. Train Model
```bash
# Build training container
docker build -f docker/Dockerfile.training -t model-training:latest .

# Run training (locally or submit to K8s)
python pipelines/train_pipeline.py
```

### 4. Deploy Model to KServe
The model is automatically deployed after successful training via GitLab on-prem CI/CD.

## 📁 Project Structure

```
mlops-end-to-end-pipeline/
├── kubernetes/                 # K8s manifests
│   ├── minio-*.yaml           # MinIO storage
│   ├── mlflow-*.yaml          # MLflow tracking server
│   ├── kserve-*.yaml          # KServe model serving
│   └── namespace.yaml         # Namespace configs
├── pipelines/                  # ML pipeline code
│   ├── train_pipeline.py       # Main training orchestration
│   ├── data_processing.py      # Data ingestion & preprocessing
│   ├── feature_engineering.py  # Feature extraction
│   └── model_evaluation.py     # Model validation metrics
├── models/                     # Model code
│   ├── train.py                # Training script
│   ├── predict.py              # Inference script
│   ├── model.py                # Model definition
│   └── requirements.txt         # Python dependencies
├── docker/                     # Docker images
│   ├── Dockerfile.training     # Training image
│   ├── Dockerfile.serving      # Serving image
│   └── requirements.txt        # Dependencies
├── monitoring/                 # Observability
│   ├── prometheus-config.yaml  # Metrics scraping
│   ├── grafana-config.yaml     # Dashboards
│   └── alerts.yaml             # Alert rules
├── .gitlab-ci.yml              # Primary GitLab on-prem CI/CD pipeline
├── docs/                       # Documentation
│   ├── ARCHITECTURE.md         # System design
│   ├── SETUP.md                # Installation guide
│   └── DEVELOPMENT.md          # Dev workflow
└── README.md                   # This file
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
# Unit tests
pytest models/test_*.py

# Integration tests
pytest tests/integration/

# Model performance tests
pytest tests/model_performance/
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
