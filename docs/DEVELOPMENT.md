# Development Workflow

## Project Structure Overview

```
mlops-end-to-end-pipeline/
├── kubernetes/           # K8s manifests (infrastructure as code)
├── pipelines/            # ML pipeline orchestration code
├── models/               # Model training and inference code
├── docker/               # Docker images for containers
├── monitoring/           # Prometheus & Grafana configs
├── docs/                 # Documentation
├── .gitlab-ci.yml            # CI/CD pipeline definition
├── .gitignore
└── README.md
```

## Getting Started

### 1. Clone and Setup Local Environment

```bash
git clone https://github.com/your-org/mlops-end-to-end-pipeline.git
cd mlops-end-to-end-pipeline

# Create virtual environment
python3.11 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r models/requirements.txt

# Optional: Install development dependencies
pip install pytest pytest-cov black flake8 mypy
```

### 2. Local Development

#### Training Pipeline Development

```bash
# Set environment variables for local dev
export MLFLOW_TRACKING_URI=http://localhost:5000
export MINIO_ENDPOINT=http://localhost:9000
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin

# Start MinIO locally (if using Docker)
docker run -p 9000:9000 -p 9001:9001 minio/minio server /data

# Start MLflow locally
mlflow server --backend-store-uri sqlite:///mlflow.db --default-artifact-root ./mlruns

# Run training pipeline
python pipelines/train_pipeline.py
```

#### Model Inference Development

```bash
# Start Flask development server
python models/predict.py

# In another terminal, test inference
curl -X POST http://localhost:5000/predict \
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

### 3. Code Quality

#### Formatting

```bash
# Format code with Black
black pipelines/ models/ --line-length 100

# Sort imports
isort pipelines/ models/
```

#### Linting

```bash
# Lint with flake8
flake8 pipelines/ models/ --max-line-length 100

# Type checking with mypy
mypy pipelines/ models/ --ignore-missing-imports
```

#### Testing

```bash
# Run unit tests
pytest models/ -v

# Run with coverage
pytest models/ --cov=models/ --cov-report=html

# Run specific test
pytest models/test_model.py::test_train_model -v
```

## Git Workflow

### Branch Strategy

We use Git Flow:
- **main**: Production-ready code, always deployable
- **develop**: Integration branch for features
- **feature/**: Feature branches from `develop`
- **hotfix/**: Critical fixes from `main`

### Creating a Feature

```bash
# Create feature branch
git checkout develop
git pull origin develop
git checkout -b feature/add-data-validation

# Make changes
# Test locally
pytest models/ -v
black pipelines/ models/
flake8 pipelines/ models/

# Commit with clear messages
git add .
git commit -m "Add data validation for training inputs"

# Push to GitHub
git push origin feature/add-data-validation

# Create pull request in GitHub UI
```

### Pull Request Checklist

Before requesting review:
- ✅ All tests pass: `pytest models/ -v`
- ✅ Code formatted: `black pipelines/ models/`
- ✅ No linting errors: `flake8 pipelines/ models/`
- ✅ Documentation updated
- ✅ Commit messages are clear
- ✅ No sensitive data committed

## CI/CD Pipeline

### Understanding the Pipeline

The `.gitlab-ci.yml` pipeline defines these stages:

1. **build**: Build Docker images
2. **train**: Execute training pipeline
3. **test**: Run tests and validation
4. **deploy**: Deploy to staging/production
5. **monitor**: Health checks

### Triggering Pipeline Manually

```bash
# Via GitLab UI:
# 1. Go to CI/CD -> Pipelines
# 2. Select branch and click "Run pipeline"
```

### Viewing Pipeline Logs

```bash
# In GitLab UI:
# CI/CD -> Pipelines -> Select pipeline -> View job logs
```

## Adding New Features

### Example: Adding a New Model

1. **Create model code** in `models/`:

```python
# models/my_new_model.py
class MyNewModel:
    def __init__(self, **kwargs):
        self.params = kwargs

    def train(self, X, y):
        # Training logic
        pass

    def predict(self, X):
        # Prediction logic
        pass
```

2. **Add to training pipeline** in `pipelines/train_pipeline.py`:

```python
from models.my_new_model import MyNewModel

# In train_model function:
model = MyNewModel(param1=value1, param2=value2)
model.train(X_train, y_train)
```

3. **Add tests** in `models/test_my_new_model.py`:

```python
import pytest
from models.my_new_model import MyNewModel

def test_train():
    model = MyNewModel()
    X = [[1, 2], [3, 4]]
    y = [0, 1]
    model.train(X, y)
    assert model is not None

def test_predict():
    model = MyNewModel()
    X = [[1, 2], [3, 4]]
    y = [0, 1]
    model.train(X, y)
    predictions = model.predict(X)
    assert len(predictions) == len(X)
```

4. **Create pull request** with the changes

5. **Pipeline runs automatically**, tests pass, then merge

### Example: Adding a New Data Source

1. **Update data loading** in `pipelines/train_pipeline.py`:

```python
def load_data():
    # Existing code...

    # Add new source
    df_new = load_from_new_source()
    df = pd.concat([df, df_new])
    return df
```

2. **Test locally**:

```bash
python pipelines/train_pipeline.py
```

3. **Commit and push**:

```bash
git add pipelines/train_pipeline.py
git commit -m "Add new data source from external API"
git push origin feature/add-new-datasource
```

## Troubleshooting

### Pipeline Fails to Build

```bash
# Check Docker build locally
docker build -f docker/Dockerfile.training -t test .

# View full logs in GitLab UI
# CI/CD -> Pipelines -> Build stage -> Build Docker Images job
```

### Training Job Fails

```bash
# Check pod logs
kubectl logs job/training-job

# Check events
kubectl describe job training-job

# Check resource limits
kubectl top pod training-pod
```

### Model Not Found in Registry

```bash
# Check MinIO bucket
mc ls minio/model-registry/

# Check MLflow models
curl http://localhost:5000/api/2.0/registered-models
```

## Performance Optimization

### Speeding Up Training

1. **Increase resources**:
   - Allocate more CPU/memory in Kubernetes manifests
   - Use GPU if available

2. **Parallelize data loading**:
   ```python
   df = pd.read_csv(file, nrows=100000)  # Load subset first
   ```

3. **Cache preprocessed data**:
   ```python
   # Save preprocessed data to MinIO
   s3_client.upload_fileobj(preprocessed_df, bucket, key)
   ```

### Reducing Inference Latency

1. **Model quantization**: Convert to smaller precision
2. **Model distillation**: Train smaller model from larger
3. **Batch predictions**: Process multiple requests together

## Useful Commands

```bash
# Check all resources
kubectl get all -n kserve

# View recent events
kubectl get events -n kserve --sort-by='.lastTimestamp'

# Port-forward services
kubectl port-forward -n mlflow svc/mlflow 5000:5000 &
kubectl port-forward -n minio svc/minio 9000:9000 &

# Scale deployment
kubectl scale deployment churn-predictor -n kserve --replicas=3

# Check resource usage
kubectl top nodes
kubectl top pods -n kserve

# View logs
kubectl logs deployment/mlflow -n mlflow -f

# Debug pod
kubectl exec -it pod/mlflow-xxx -n mlflow -- /bin/bash
```

## Documentation

Update documentation when making changes:

- **Architecture changes**: Update `docs/ARCHITECTURE.md`
- **Setup changes**: Update `docs/SETUP.md`
- **New features**: Add to `README.md` overview section

## Questions?

Refer to:
- [README.md](../README.md) - Project overview
- [ARCHITECTURE.md](ARCHITECTURE.md) - System design
- [SETUP.md](SETUP.md) - Installation guide
- Individual source files for code documentation

---

Happy coding! 🚀
