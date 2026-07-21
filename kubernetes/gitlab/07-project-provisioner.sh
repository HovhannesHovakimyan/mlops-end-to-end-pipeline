#!/bin/bash

################################################################################
# GitLab Project Provisioner
#
# Automates GitLab project creation, CI/CD variable setup, and pull mirroring
# using GitLab REST API. No manual UI steps required.
#
# Usage:
#   ./07-project-provisioner.sh \
#     --gitlab-url http://localhost:8088 \
#     --admin-token glpat-xxxx \
#     --project-name mlops-e2e \
#     [--github-url https://github.com/user/repo.git] \
#     [--variables-file /path/to/variables.env]
#
# Environment File Format (variables.env):
#   REGISTRY_USER=myuser
#   REGISTRY_PASSWORD=mypass
#   MLFLOW_TRACKING_URI=http://mlflow.mlflow:5000
#   MINIO_ENDPOINT=http://minio.minio:9000
#   AWS_ACCESS_KEY_ID=minioadmin
#   AWS_SECRET_ACCESS_KEY=minioadmin
#   KUBE_CONTEXT=minikube
#   KUBE_CONTEXT_STAGING=minikube
#
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
GITLAB_URL="${GITLAB_URL:-http://localhost:8088}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
PROJECT_NAME="${PROJECT_NAME:-}"
GITHUB_URL="${GITHUB_URL:-}"
VARIABLES_FILE="${VARIABLES_FILE:-}"
PROJECT_VISIBILITY="private"
INIT_REPO_WITH_README=true

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --gitlab-url)
      GITLAB_URL="$2"
      shift 2
      ;;
    --admin-token)
      ADMIN_TOKEN="$2"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --github-url)
      GITHUB_URL="$2"
      shift 2
      ;;
    --variables-file)
      VARIABLES_FILE="$2"
      shift 2
      ;;
    --visibility)
      PROJECT_VISIBILITY="$2"
      shift 2
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$ADMIN_TOKEN" ]]; then
  echo -e "${RED}Error: --admin-token is required${NC}"
  echo "Usage: $0 --gitlab-url URL --admin-token TOKEN --project-name NAME [--github-url GITHUB_URL] [--variables-file FILE]"
  exit 1
fi

if [[ -z "$PROJECT_NAME" ]]; then
  echo -e "${RED}Error: --project-name is required${NC}"
  echo "Usage: $0 --gitlab-url URL --admin-token TOKEN --project-name NAME [--github-url GITHUB_URL] [--variables-file FILE]"
  exit 1
fi

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}GitLab Project Provisioner${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""
echo "Configuration:"
echo "  GitLab URL: $GITLAB_URL"
echo "  Project Name: $PROJECT_NAME"
echo "  Visibility: $PROJECT_VISIBILITY"
if [[ -n "$GITHUB_URL" ]]; then
  echo "  GitHub URL: $GITHUB_URL"
fi
if [[ -n "$VARIABLES_FILE" ]]; then
  echo "  Variables File: $VARIABLES_FILE"
fi
echo ""

# Function to make API calls with timeout
gitlab_api_call() {
  local method=$1
  local endpoint=$2
  local data=${3:-}
  local timeout=${4:-30}  # Default 30 second timeout

  local url="${GITLAB_URL}/api/v4${endpoint}"
  local headers=(-H "PRIVATE-TOKEN: $ADMIN_TOKEN" -H "Content-Type: application/json")

  if [[ -z "$data" ]]; then
    curl -s --max-time "$timeout" -X "$method" "${headers[@]}" "$url"
  else
    curl -s --max-time "$timeout" -X "$method" "${headers[@]}" -d "$data" "$url"
  fi
}

# Step 1: Create project
echo -e "${BLUE}[1/4]${NC} Creating GitLab project..."

# Always create blank project first (avoids timeout with imports)
PROJECT_DATA=$(cat <<EOF
{
  "name": "$PROJECT_NAME",
  "description": "MLOps End-to-End Pipeline Project",
  "visibility": "$PROJECT_VISIBILITY",
  "initialize_with_readme": $INIT_REPO_WITH_README
}
EOF
)

PROJECT_RESPONSE=$(gitlab_api_call POST "/projects" "$PROJECT_DATA" 30)
PROJECT_ID=$(echo "$PROJECT_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}Failed to create project. API Response:${NC}"
  echo "$PROJECT_RESPONSE" | head -20
  exit 1
fi

PROJECT_PATH=$(echo "$PROJECT_RESPONSE" | grep -o '"path_with_namespace":"[^"]*' | cut -d'"' -f4)
echo -e "${GREEN}✓ Project created: $PROJECT_PATH (ID: $PROJECT_ID)${NC}"

# Step 2: Set up CI/CD variables from file
if [[ -n "$VARIABLES_FILE" ]] && [[ -f "$VARIABLES_FILE" ]]; then
  echo -e "${BLUE}[2/4]${NC} Adding CI/CD variables from $VARIABLES_FILE..."

  # Source the variables file to get all variables
  set +a
  source "$VARIABLES_FILE"
  set -a

  VARIABLES=(
    "REGISTRY_USER"
    "REGISTRY_PASSWORD"
    "MLFLOW_TRACKING_URI"
    "MINIO_ENDPOINT"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "KUBE_CONTEXT"
    "KUBE_CONTEXT_STAGING"
  )

  ADDED_COUNT=0
  for var_name in "${VARIABLES[@]}"; do
    var_value="${!var_name:-}"

    if [[ -n "$var_value" ]]; then
      # Determine if variable should be masked (for sensitive values)
      PROTECTED="false"
      MASKED="false"

      if [[ "$var_name" =~ PASSWORD|SECRET|TOKEN|KEY ]]; then
        PROTECTED="true"
        MASKED="true"
      fi

      VAR_DATA=$(cat <<EOF
{
  "key": "$var_name",
  "value": "$var_value",
  "protected": $PROTECTED,
  "masked": $MASKED
}
EOF
)

      VAR_RESPONSE=$(gitlab_api_call POST "/projects/$PROJECT_ID/variables" "$VAR_DATA")

      if echo "$VAR_RESPONSE" | grep -q '"key":"'"$var_name"'"'; then
        echo -e "${GREEN}  ✓ $var_name${NC}"
        ((ADDED_COUNT++))
      else
        echo -e "${YELLOW}  ⚠ Failed to add $var_name${NC}"
      fi
    fi
  done

  echo -e "${GREEN}✓ Added $ADDED_COUNT CI/CD variables${NC}"
else
  if [[ -n "$VARIABLES_FILE" ]]; then
    echo -e "${YELLOW}[2/4] Skipping CI/CD variables (file not found: $VARIABLES_FILE)${NC}"
  else
    echo -e "${YELLOW}[2/4] Skipping CI/CD variables (no --variables-file provided)${NC}"
  fi
  echo "    Tip: Add variables manually in GitLab UI: Settings → CI/CD → Variables"
fi

# Step 3: Set up GitHub import (if provided)
if [[ -n "$GITHUB_URL" ]]; then
  echo -e "${BLUE}[3/4]${NC} Setting up GitHub import (runs asynchronously in background)..."

  IMPORT_DATA=$(cat <<EOF
{
  "import_url": "$GITHUB_URL",
  "import_type": "github"
}
EOF
)

  # Use longer timeout for import setup call (90 seconds)
  IMPORT_RESPONSE=$(gitlab_api_call PUT "/projects/$PROJECT_ID" "$IMPORT_DATA" 90)

  if echo "$IMPORT_RESPONSE" | grep -q '"import_source":' || echo "$IMPORT_RESPONSE" | grep -q '"import_url":'; then
    echo -e "${GREEN}✓ GitHub import initiated${NC}"
    echo -e "${YELLOW}  ⚠ Repository import happens in background. Check project settings to monitor progress.${NC}"
  else
    echo -e "${YELLOW}⚠ Import setup returned: $(echo "$IMPORT_RESPONSE" | head -c 100)${NC}"
  fi
else
  echo -e "${YELLOW}[3/4] Skipping GitHub import (no --github-url provided)${NC}"
fi

# Step 4: Display project information
echo -e "${BLUE}[4/4]${NC} Project details:"
echo ""
echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}✅ PROJECT PROVISIONING COMPLETE${NC}"
echo -e "${GREEN}========================================================${NC}"
echo ""
echo "Project Information:"
echo "  - Name: $PROJECT_NAME"
echo "  - Path: $PROJECT_PATH"
echo "  - ID: $PROJECT_ID"
echo "  - URL: $GITLAB_URL/$PROJECT_PATH"
echo "  - Visibility: $PROJECT_VISIBILITY"
echo ""

if [[ -n "$GITHUB_URL" ]]; then
  echo "Repository Import:"
  echo "  - Source: $GITHUB_URL"
  echo "  - Status: Importing in background"
  echo "  - Monitor at: $GITLAB_URL/$PROJECT_PATH/-/settings/integrations/github"
  echo ""
fi

echo "Next Steps:"
echo ""
if [[ -n "$GITHUB_URL" ]]; then
  echo "1. Wait for GitHub import to complete (check project settings)"
  echo ""
  echo "2. Once ready, clone the imported project locally:"
  echo "   git clone $GITLAB_URL/$PROJECT_PATH.git"
  echo ""
  echo "3. Trigger the pipeline by pushing to main:"
  echo "   git push origin main"
  echo ""
else
  echo "1. Clone the project locally:"
  echo "   git clone $GITLAB_URL/$PROJECT_PATH.git"
  echo ""
  echo "2. Add your code and .gitlab-ci.yml to the repo"
  echo ""
  echo "3. Trigger the pipeline by pushing to main:"
  echo "   git push origin main"
  echo ""
fi

echo "4. Monitor pipeline execution:"
echo "   - GitLab UI: $GITLAB_URL/$PROJECT_PATH/-/pipelines"
echo "   - Runner logs: kubectl logs -n gitlab deployment/gitlab-runner -f"
echo ""
echo -e "${GREEN}========================================================${NC}"
