# Architecture & Design Documentation

## System Architecture

The repository and automation split is intentional: GitHub provides public project history and collaboration visibility, while GitLab on-prem runs the production CI/CD pipeline. This demonstrates integration of diverse enterprise and developer-platform products.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        GitHub (Git Repository)                          │
│  - Source code versioning                                               │
│  - Source of truth for code and pull mirroring                           │
│  - Pull request workflows                                               │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              ↓
            ┌─────────────────────────────────────────┐
            │   GitLab On-Prem + Runner (on K8s)      │
            │  Executes production pipeline jobs       │
            └────────────────┬────────────────────────┘
                         │
        ┌────────────────┴─────────────────────────────────┐
        │                                                  │
        ↓                                                  ↓
   ┌──────────────┐                              ┌──────────────────┐
   │   Build Job  │◄────────────────────────────►│  Docker Registry │
   │ (Push images)│                              │  (Store images)  │
   └──────────────┘                              └──────────────────┘
        │
        ↓
   ┌──────────────────────────────────────────────────────────────┐
   │           Kubernetes Cluster (On-Premises)                   │
   ├──────────────────────────────────────────────────────────────┤
   │                                                              │
   │  ┌─────────────────────────────────────────────────────┐   │
   │  │         Training Pipeline (Job)                     │   │
   │  │  ┌──────────────┐  ┌──────────────┐               │   │
   │  │  │Data Loading  │→ │ Preprocessing│               │   │
   │  │  └──────────────┘  └──────────────┘               │   │
   │  │         ↓                  ↓                       │   │
   │  │  ┌──────────────┐  ┌──────────────┐               │   │
   │  │  │Feature Engr. │→ │  Training    │               │   │
   │  │  └──────────────┘  └──────────────┘               │   │
   │  │         ↓                  ↓                       │   │
   │  │  ┌──────────────┐  ┌──────────────┐               │   │
   │  │  │ Evaluation   │→ │MLflow Logger │               │   │
   │  │  └──────────────┘  └──────────────┘               │   │
   │  └──────────────────────────────────────────────────────┘   │
   │                         ↓                                    │
   │  ┌─────────────────────────────────────┐                    │
   │  │      MLflow Tracking Server         │                    │
   │  │  - Experiment tracking              │                    │
   │  │  - Model versioning                 │                    │
   │  │  - Metrics & parameters             │                    │
   │  └──────────────┬──────────────────────┘                    │
   │                 │                                            │
   │                 ↓                                            │
   │  ┌─────────────────────────────────────┐                    │
   │  │      Model Registry (MinIO)         │                    │
   │  │  - Store trained models             │                    │
   │  │  - Version control                  │                    │
   │  │  - S3-compatible access             │                    │
   │  └──────────────┬──────────────────────┘                    │
   │                 │                                            │
   │                 ↓                                            │
   │  ┌─────────────────────────────────────┐                    │
   │  │   KServe Inference Service          │                    │
   │  │  - Model serving                    │                    │
   │  │  - Canary deployment (90/10 split)  │                    │
   │  │  - Automatic rollout                │                    │
   │  └──────────────┬──────────────────────┘                    │
   │                 │                                            │
   │                 ↓                                            │
   │  ┌─────────────────────────────────────┐                    │
   │  │   Monitoring Stack                  │                    │
   │  │  - Prometheus (metrics collection)  │                    │
   │  │  - Grafana (visualization)          │                    │
   │  │  - Alert Manager (notifications)    │                    │
   │  └──────────────┬──────────────────────┘                    │
   │                 │                                            │
   │                 ↓ (on drift detected)                       │
   │  ┌─────────────────────────────────────┐                    │
   │  │  Drift Detection & Retraining       │                    │
   │  │  - Triggers automated retraining    │                    │
   │  │  - Pushes to GitHub for CI/CD flow  │                    │
   │  └─────────────────────────────────────┘                    │
   │                                                              │
   └──────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### GitHub
- **Version Control**: Stores all code, manifests, and configurations
- **Collaboration Surface**: Public repository visibility, pull requests, and portfolio traceability

### GitLab On-Prem
- **CI/CD Pipeline**: Orchestrates build, train, test, deploy, and monitor stages
- **Runner Execution**: Executes production pipeline jobs in on-prem environments

### Data Storage (MinIO)
- **Training Data Bucket**: `training-data/` - Raw and processed datasets
- **Model Registry**: `model-registry/` - Trained model artifacts with versioning
- **Experiment Logs**: Additional MLflow artifacts if needed

### MLflow
- **Experiment Tracking**: Records hyperparameters, metrics, and artifacts for each run
- **Model Registry**: Maintains model versions with tags (staging, production, etc.)
- **API**: Provides REST endpoints for model lookup and logging

### KServe
- **Model Serving**: Hosts trained model for real-time inference
- **Canary Deployment**: Gradual rollout (10% new model, 90% current)
- **Traffic Management**: A/B testing and gradual migration capabilities
- **Auto-scaling**: Scales based on request load

### Monitoring
- **Prometheus**: Scrapes metrics from all services
  - KServe inference latency and error rates
  - MLflow availability
  - MinIO storage usage
  - Kubernetes node/pod metrics
- **Grafana**: Visualizes metrics in dashboards
- **AlertManager**: Sends alerts on violations

## Data Flow

### Training Flow
1. **Trigger**: GitLab on-prem pipeline triggered by mirrored GitHub changes or schedule
2. **Build**: Docker image built and pushed to registry
3. **Training Job**: Kubernetes Job spawns training container
4. **Data Loading**: Pull data from MinIO `training-data/` bucket
5. **Processing**: Features engineered and normalized
6. **Training**: Model trained with hyperparameters
7. **Logging**: MLflow logs metrics, params, and model
8. **Registry**: Model saved to MinIO `model-registry/{run_id}/`
9. **Versioning**: Latest model symlinked for easy deployment

### Serving Flow
1. **Deployment**: KServe InferenceService reads model from MinIO
2. **Serving**: Model loaded into memory for inference
3. **Prediction**: API receives request, performs inference
4. **Metrics**: Latency and results sent to Prometheus
5. **Logging**: Predictions logged for monitoring

### Monitoring & Retraining Flow
1. **Collection**: Prometheus scrapes prediction metrics
2. **Analysis**: Rules detect performance degradation
3. **Drift Detection**: Custom script detects model drift
4. **Alert**: AlertManager sends notification
5. **Trigger**: Webhook triggers GitLab on-prem pipeline for retraining
6. **Retraining**: New model trained and evaluated
7. **Deployment**: If metrics improve, deploy new version

## Key Design Decisions

### 1. Canary Deployment (90/10 split)
- **Why**: Reduces risk of deploying underperforming models
- **How**: KServe routes 10% traffic to new model, 90% to current
- **Monitor**: Compare prediction accuracy and latency between versions
- **Rollback**: Automatic if new version degrades metrics

### 2. MinIO for Model Storage
- **Why**: S3-compatible, runs on-premises, same as cloud
- **Benefit**: Easy migration path to cloud (AWS S3, GCS, Azure Blob)
- **Versioning**: All model artifacts timestamped and versioned

### 3. MLflow for Experiment Tracking
- **Why**: Industry standard, integrates with KServe, reproducible experiments
- **Tracking**: Every training run logged with metrics, parameters, and model
- **Registry**: Manages model lifecycle (staging → production)

### 4. Kubernetes for Orchestration
- **Why**: Scalable, self-healing, multi-tenancy support
- **Benefits**: Resource isolation, horizontal scaling, monitoring built-in
- **On-premises**: Works with any Kubernetes distribution (bare metal, KVM, etc.)

### 5. GitOps with GitHub + GitLab On-Prem
- **Why**: Infrastructure as Code, version-controlled deployments
- **Flow**: Code push → CI/CD pipeline → Automated deployment
- **Audit**: Full audit trail of changes

## Security Considerations

### Data Security
- ✅ MinIO configured with encryption at rest
- ✅ S3 bucket policies restrict access to training pods
- ✅ API keys stored in GitLab CI/CD variables (not in code)

### Model Security
- ✅ Model versions signed and versioned
- ✅ Only validated models promoted to production
- ✅ Canary deployment prevents untested models

### Access Control
- ✅ RBAC for Kubernetes resources
- ✅ Service accounts with minimal permissions
- ✅ CI/CD credentials managed via protected variables

### Networking
- ✅ Pod-to-pod communication via network policies
- ✅ Namespaces isolate services (minio, mlflow, kserve)
- ✅ TLS for external communication

## Performance Considerations

### Training Performance
- **Parallelization**: Training job uses all available CPU cores
- **Resource Limits**: Configurable memory and CPU quotas
- **Data Loading**: Efficient batch loading from MinIO

### Inference Performance
- **Latency Target**: <100ms p99 latency
- **Throughput**: Horizontal scaling via KServe auto-scaling
- **Caching**: Model loaded once, reused for all predictions

### Storage Performance
- **MinIO**: High-speed local storage or network-attached
- **Archival**: Old models moved to slower storage after 90 days

## Scalability

### Horizontal Scaling
- **Training**: Multiple training jobs can run in parallel
- **Serving**: KServe auto-scales replicas based on request rate
- **Storage**: MinIO can scale horizontally with more disks

### Vertical Scaling
- **GPU Support**: Training jobs can request GPUs
- **High-Memory**: Inference pods can handle larger models

## Disaster Recovery

### Backup Strategy
- ✅ MinIO bucket replication enabled
- ✅ MLflow database backed up daily
- ✅ Git history provides code recovery
- ✅ Model versioning allows rollback

### Failover
- **MinIO**: Replicated across multiple disks/nodes
- **MLflow**: Single instance with persistent volume
- **KServe**: Multiple replicas for high availability

## Monitoring Metrics

### Key Metrics to Track
1. **Model Performance**
   - Accuracy (training vs. production)
   - F1-score, Precision, Recall
   - Latency (p50, p95, p99)
   - Throughput (requests/sec)

2. **Infrastructure**
   - Pod availability and restarts
   - Resource utilization (CPU, memory)
   - Storage usage and growth rate
   - Network throughput

3. **Pipeline**
   - Training job duration
   - Model deployment time
   - Time to detect drift and retrain

---

See [SETUP.md](SETUP.md) for installation instructions.
