#!/bin/bash

################################################################################
# GitLab Project Populator - Clone from GitHub and push to GitLab
#
# This script clones a GitHub repository and pushes it to a GitLab project
# created by the provisioner script.
#
# Usage:
#   ./08-populate-project-from-github.sh \
#     --github-url https://github.com/user/repo.git \
#     --gitlab-url http://localhost:8088 \
#     --gitlab-project-path root/mlops-e2e-github \
#     --local-dir /tmp/mlops-repo
#
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_URL=""
GITLAB_URL=""
GITLAB_PROJECT_PATH=""
LOCAL_DIR=""
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
GITLAB_PROJECT_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --github-url)
      GITHUB_URL="$2"
      shift 2
      ;;
    --gitlab-url)
      GITLAB_URL="$2"
      shift 2
      ;;
    --gitlab-project-path)
      GITLAB_PROJECT_PATH="$2"
      shift 2
      ;;
    --local-dir)
      LOCAL_DIR="$2"
      shift 2
      ;;
    --admin-token)
      ADMIN_TOKEN="$2"
      shift 2
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

if [[ -z "$GITHUB_URL" ]] || [[ -z "$GITLAB_URL" ]] || [[ -z "$GITLAB_PROJECT_PATH" ]] || [[ -z "$LOCAL_DIR" ]]; then
  echo -e "${RED}Error: Missing required parameters${NC}"
  echo "Usage: $0 --github-url URL --gitlab-url URL --gitlab-project-path PATH --local-dir DIR [--admin-token TOKEN]"
  exit 1
fi

# Embed credentials in URL if token provided (avoids interactive auth prompt)
if [[ -n "$ADMIN_TOKEN" ]]; then
  # Strip trailing slash, insert credentials after protocol
  GITLAB_PROJECT_URL=$(echo "$GITLAB_URL" | sed "s|://|://root:${ADMIN_TOKEN}@|")
  GITLAB_PROJECT_URL="${GITLAB_PROJECT_URL}/${GITLAB_PROJECT_PATH}.git"
else
  GITLAB_PROJECT_URL="${GITLAB_URL}/${GITLAB_PROJECT_PATH}.git"
fi

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}GitLab Project Populator${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""
echo "Configuration:"
echo "  GitHub URL: $GITHUB_URL"
echo "  GitLab URL: $GITLAB_URL"
echo "  GitLab Project: $GITLAB_PROJECT_PATH"
echo "  Local Dir: $LOCAL_DIR"
if [[ -n "$ADMIN_TOKEN" ]]; then
  echo "  Auth: token-based (no interactive prompt)"
else
  echo "  Auth: interactive (will prompt for credentials)"
fi
echo ""

# Step 1: Clone from GitHub
echo -e "${BLUE}[1/3]${NC} Cloning from GitHub..."
if [[ -d "$LOCAL_DIR" ]]; then
  echo -e "${YELLOW}  Directory already exists, pulling latest changes${NC}"
  cd "$LOCAL_DIR"
  git fetch origin
else
  git clone "$GITHUB_URL" "$LOCAL_DIR"
  cd "$LOCAL_DIR"
fi
echo -e "${GREEN}✓ Repository cloned/updated${NC}"

# Step 2: Add GitLab remote
echo -e "${BLUE}[2/3]${NC} Adding GitLab remote..."
if git remote | grep -q gitlab; then
  echo -e "${YELLOW}  GitLab remote already exists, updating${NC}"
  git remote set-url gitlab "$GITLAB_PROJECT_URL"
else
  git remote add gitlab "$GITLAB_PROJECT_URL"
fi
echo -e "${GREEN}✓ GitLab remote configured${NC}"

# Step 3: Push to GitLab
echo -e "${BLUE}[3/3]${NC} Pushing all branches to GitLab..."

# Temporarily unprotect default branch to allow force push
if [[ -n "$ADMIN_TOKEN" ]]; then
  # Discover default branch
  DEFAULT_BRANCH=$(curl -s -H "PRIVATE-TOKEN: $ADMIN_TOKEN" \
    "$GITLAB_URL/api/v4/projects?search=$(basename "$GITLAB_PROJECT_PATH")" \
    | grep -o '"default_branch":"[^"]*' | head -1 | cut -d'"' -f4)
  DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

  # Get project ID by path
  ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$GITLAB_PROJECT_PATH', safe=''))" 2>/dev/null \
    || echo "$GITLAB_PROJECT_PATH" | sed 's|/|%2F|g')
  GITLAB_PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $ADMIN_TOKEN" \
    "$GITLAB_URL/api/v4/projects/$ENCODED_PATH" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

  if [[ -n "$GITLAB_PROJECT_ID" ]]; then
    echo "  Temporarily unprotecting '$DEFAULT_BRANCH' branch..."
    curl -s -X DELETE "$GITLAB_URL/api/v4/projects/$GITLAB_PROJECT_ID/protected_branches/$DEFAULT_BRANCH" \
      -H "PRIVATE-TOKEN: $ADMIN_TOKEN" > /dev/null
  fi
fi

git push --force -u gitlab --all
git push -u gitlab --tags

# Re-protect the default branch
if [[ -n "$ADMIN_TOKEN" ]] && [[ -n "$GITLAB_PROJECT_ID" ]]; then
  echo "  Re-protecting '$DEFAULT_BRANCH' branch..."
  curl -s -X POST "$GITLAB_URL/api/v4/projects/$GITLAB_PROJECT_ID/protected_branches" \
    -H "PRIVATE-TOKEN: $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$DEFAULT_BRANCH\",\"push_access_level\":40,\"merge_access_level\":40}" > /dev/null
fi

echo ""
echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}✅ PROJECT POPULATION COMPLETE${NC}"
echo -e "${GREEN}========================================================${NC}"
echo ""
echo "Repository synced to GitLab!"
echo "  - Project: $GITLAB_URL/$GITLAB_PROJECT_PATH"
echo "  - Local dir: $LOCAL_DIR"
echo ""
echo "Next Steps:"
echo ""
echo "1. Verify all branches are in GitLab:"
echo "   curl -s -H 'PRIVATE-TOKEN: <token>' $GITLAB_URL/api/v4/projects/2/repository/branches | jq '.[] | .name'"
echo ""
echo "2. Trigger pipeline:"
echo "   cd $LOCAL_DIR"
echo "   git push gitlab main"
echo ""
echo "3. Monitor pipeline:"
echo "   $GITLAB_URL/$GITLAB_PROJECT_PATH/-/pipelines"
echo ""
echo -e "${GREEN}========================================================${NC}"
