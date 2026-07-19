# Makefile for MLOps Pipeline

.PHONY: help setup-local setup-k8s train test lint format clean teardown-path-a2 \
	docker-build docker-push port-forward logs verify

help:
	@echo "MLOps End-to-End Pipeline - Available Commands"
	@echo "=============================================="
	@echo ""
	@echo "Setup & Infrastructure:"
	@echo "  make setup-local       - Setup local development environment"
	@echo "  make setup-k8s         - Deploy services to Kubernetes"
	@echo "  make setup-all         - Setup local + Kubernetes"
	@echo ""
	@echo "Development:"
	@echo "  make train            - Run training pipeline locally"
	@echo "  make test             - Run tests"
	@echo "  make lint             - Run linting checks"
	@echo "  make format           - Format code with Black"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-build     - Build Docker images"
	@echo "  make docker-push      - Push images to registry"
	@echo ""
	@echo "Kubernetes:"
	@echo "  make port-forward     - Setup port forwarding"
	@echo "  make logs             - View logs from all services"
	@echo "  make verify           - Verify all deployments"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean            - Remove temporary files"
	@echo "  make teardown-path-a2 - Delete k8s manifests and Minikube cluster profile path-a2-test"
	@echo ""

# Setup local development environment
setup-local:
	@echo "Setting up local development environment..."
	python3.11 -m venv venv
	. venv/bin/activate && pip install -r models/requirements.txt
	. venv/bin/activate && pip install pytest pytest-cov black flake8 mypy
	@echo "✓ Local environment setup complete"

# Deploy to Kubernetes
setup-k8s: setup-k8s-namespaces setup-k8s-minio setup-k8s-mlflow
	@echo "✓ Kubernetes setup complete"

setup-k8s-namespaces:
	@echo "Creating Kubernetes namespaces..."
	kubectl apply -f kubernetes/01-namespaces.yaml

setup-k8s-minio:
	@echo "Deploying MinIO..."
	kubectl apply -f kubernetes/02-minio.yaml
	@echo "Waiting for MinIO..."
	kubectl wait --for=condition=available --timeout=300s deployment/minio -n minio || true

setup-k8s-mlflow:
	@echo "Deploying MLflow..."
	kubectl apply -f kubernetes/03-mlflow.yaml
	@echo "Waiting for MLflow..."
	kubectl wait --for=condition=available --timeout=300s deployment/mlflow -n mlflow || true

# Complete setup
setup-all: setup-local setup-k8s port-forward
	@echo "✓ Complete setup finished!"

# Run training pipeline
train:
	@. venv/bin/activate && python pipelines/train_pipeline.py

# Run tests
test:
	@. venv/bin/activate && pytest models/ -v --cov=models/ --cov-report=html
	@echo "Coverage report generated in htmlcov/index.html"

# Run linting
lint:
	@echo "Running linters..."
	@. venv/bin/activate && flake8 pipelines/ models/ --max-line-length=100 || true
	@. venv/bin/activate && mypy pipelines/ models/ --ignore-missing-imports || true

# Format code
format:
	@echo "Formatting code..."
	@. venv/bin/activate && black pipelines/ models/ --line-length=100
	@echo "✓ Code formatted"

# Build Docker images
docker-build:
	@echo "Building Docker images..."
	docker build -f docker/Dockerfile.training -t mlops-pipeline:training-latest .
	docker build -f docker/Dockerfile.serving -t mlops-pipeline:serving-latest .
	@echo "✓ Docker images built"

# Push Docker images
docker-push: docker-build
	@echo "Pushing Docker images to registry..."
	docker tag mlops-pipeline:training-latest $(REGISTRY)/mlops-pipeline:training-latest
	docker tag mlops-pipeline:serving-latest $(REGISTRY)/mlops-pipeline:serving-latest
	docker push $(REGISTRY)/mlops-pipeline:training-latest
	docker push $(REGISTRY)/mlops-pipeline:serving-latest
	@echo "✓ Images pushed"

# Setup port forwarding
port-forward:
	@echo "Setting up port forwarding..."
	@kubectl port-forward -n minio svc/minio 9000:9000 > /dev/null 2>&1 &
	@kubectl port-forward -n minio svc/minio-console 9001:9001 > /dev/null 2>&1 &
	@kubectl port-forward -n mlflow svc/mlflow 5000:5000 > /dev/null 2>&1 &
	@echo "✓ Port forwarding active"
	@echo ""
	@echo "Services available at:"
	@echo "  MinIO Console: http://localhost:9001 (admin/minioadmin)"
	@echo "  MLflow UI: http://localhost:5000"

# View logs
logs:
	@echo "=== MinIO Logs ==="
	@kubectl logs -n minio deployment/minio --tail=20 || true
	@echo ""
	@echo "=== MLflow Logs ==="
	@kubectl logs -n mlflow deployment/mlflow --tail=20 || true
	@echo ""
	@echo "=== KServe Logs ==="
	@kubectl logs -n kserve deployment/churn-predictor --tail=20 || true

# Verify deployments
verify:
	@echo "Verifying Kubernetes deployments..."
	@echo ""
	@echo "MinIO:"
	@kubectl get deployment -n minio
	@echo ""
	@echo "MLflow:"
	@kubectl get deployment -n mlflow
	@echo ""
	@echo "KServe:"
	@kubectl get inferenceservice -n kserve || echo "No InferenceServices deployed"

# Clean up
clean:
	@echo "Cleaning up..."
	@find . -type d -name __pycache__ -exec rm -rf {} + || true
	@find . -type f -name '*.pyc' -delete
	@rm -rf .pytest_cache htmlcov .coverage
	@rm -rf mlruns artifacts
	@echo "✓ Cleanup complete"

# Full Path A2 teardown: remove project manifests and optional local Minikube cluster profile
teardown-path-a2:
	@echo "Deleting Kubernetes manifests from kubernetes/..."
	@find kubernetes -type f \( -name '*.yaml' -o -name '*.yml' \) | sort -r | while read -r f; do \
		echo "Deleting $$f"; \
		kubectl delete -f "$$f" --ignore-not-found || true; \
	done
	@echo "Deleting namespace leftovers..."
	@kubectl delete ns gitlab minio mlflow kserve --ignore-not-found || true
	@echo "Deleting Minikube cluster profile path-a2-test (if present)..."
	@minikube delete -p path-a2-test || true
	@echo "✓ Path A2 teardown complete (Minikube installation is not removed)"
