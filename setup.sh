#!/bin/bash
# Quick setup script for MLOps pipeline

set -e

echo "🚀 MLOps End-to-End Pipeline Setup"
echo "===================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

command -v kubectl &> /dev/null || { echo "kubectl not found"; exit 1; }
echo -e "${GREEN}✓ kubectl found${NC}"

command -v docker &> /dev/null || { echo "docker not found"; exit 1; }
echo -e "${GREEN}✓ docker found${NC}"

# Create namespaces
echo -e "${BLUE}Creating Kubernetes namespaces...${NC}"
kubectl apply -f kubernetes/01-namespaces.yaml
echo -e "${GREEN}✓ Namespaces created${NC}"

# Deploy MinIO
echo -e "${BLUE}Deploying MinIO...${NC}"
kubectl apply -f kubernetes/02-minio.yaml
echo -e "${GREEN}✓ MinIO deployed${NC}"

# Wait for MinIO
echo -e "${YELLOW}Waiting for MinIO to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/minio -n minio || true

# Deploy MLflow
echo -e "${BLUE}Deploying MLflow...${NC}"
kubectl apply -f kubernetes/03-mlflow.yaml
echo -e "${GREEN}✓ MLflow deployed${NC}"

# Wait for MLflow
echo -e "${YELLOW}Waiting for MLflow to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/mlflow -n mlflow || true

# Check KServe
echo -e "${BLUE}Checking KServe installation...${NC}"
if kubectl get ns kserve &> /dev/null; then
    echo -e "${GREEN}✓ KServe namespace found${NC}"
else
    echo -e "${YELLOW}⚠ KServe not installed. Installing...${NC}"
    kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml
    echo -e "${GREEN}✓ KServe installed${NC}"
fi

# Setup port forwarding (optional)
echo ""
echo -e "${BLUE}Optional: Setup port forwarding?${NC}"
read -p "Do you want to setup port forwarding? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Starting port forwarding in background...${NC}"
    kubectl port-forward -n minio svc/minio 9000:9000 &
    kubectl port-forward -n minio svc/minio-console 9001:9001 &
    kubectl port-forward -n mlflow svc/mlflow 5000:5000 &
    echo -e "${GREEN}✓ Port forwarding started${NC}"
    echo ""
    echo "Access services at:"
    echo "  MinIO UI: http://localhost:9001 (admin/minioadmin)"
    echo "  MLflow UI: http://localhost:5000"
    echo ""
fi

# Verify deployments
echo -e "${BLUE}Verifying deployments...${NC}"
echo ""
echo "Pods in minio namespace:"
kubectl get pods -n minio
echo ""
echo "Pods in mlflow namespace:"
kubectl get pods -n mlflow
echo ""

echo -e "${GREEN}Setup completed! ✓${NC}"
echo ""
echo "Next steps:"
echo "1. Create buckets in MinIO:"
echo "   kubectl exec -it -n minio deployment/minio -- /bin/bash"
echo "   mc alias set minio http://localhost:9000 minioadmin minioadmin"
echo "   mc mb minio/training-data minio/model-registry minio/mlflow-artifacts"
echo ""
echo "2. Push code to GitLab to trigger GitLab CI/CD pipeline"
echo ""
echo "3. View documentation:"
echo "   - docs/ARCHITECTURE.md - System design"
echo "   - docs/SETUP.md - Installation details"
echo "   - docs/DEVELOPMENT.md - Development workflow"
echo ""
