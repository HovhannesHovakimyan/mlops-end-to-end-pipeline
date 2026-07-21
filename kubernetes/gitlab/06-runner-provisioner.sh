#!/bin/bash
# Automated GitLab Runner Provisioning Script
# This script creates a runner via GitLab Rails CLI and generates the runner secret
#
# Usage:
#   ./kubernetes/gitlab/06-runner-provisioner.sh [--runner-url URL]
#
# --runner-url  URL that the runner pod uses to reach GitLab inside the cluster
#               (default: http://gitlab.gitlab.svc.cluster.local — usually correct)
#
# Requirements:
#   - kubectl access to the cluster with GitLab namespace
#   - GitLab pod must be running in gitlab namespace

set -e

# Defaults
RUNNER_URL="${RUNNER_URL:-http://gitlab.gitlab.svc.cluster.local}"
RUNNER_NAMESPACE="gitlab"
OUTPUT_SECRET="/tmp/gitlab-runner-secret.yaml"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --runner-url)
      RUNNER_URL="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--runner-url URL]"
      exit 1
      ;;
  esac
done

# Validate inputs
if ! kubectl get ns gitlab &>/dev/null; then
  echo "Error: GitLab namespace not found. Is GitLab deployed?"
  exit 1
fi

if ! kubectl get pod -n gitlab -l app=gitlab &>/dev/null; then
  echo "Error: GitLab pod not found in gitlab namespace"
  exit 1
fi

echo "Creating GitLab runner via GitLab Rails CLI..."
echo "  GitLab instance: $GITLAB_URL"
echo "  Runner CI URL:   $RUNNER_URL"

# Create runner via GitLab Rails CLI (works reliably across all GitLab versions)
# This runs inside the GitLab pod and creates an instance runner
RUNNER_RESPONSE=$(kubectl exec -n gitlab deployment/gitlab -- \
  gitlab-rails runner \
  "runner = Ci::Runner.create(runner_type: :instance_type, tag_list: ['kubernetes', 'docker'], run_untagged: true, locked: false); puts \"ID:#{runner.id}|TOKEN:#{runner.token}\"" 2>/dev/null)

# Parse ID and token
RUNNER_ID=$(echo "$RUNNER_RESPONSE" | grep -o "ID:[0-9]*" | cut -d':' -f2)
RUNNER_TOKEN=$(echo "$RUNNER_RESPONSE" | grep -o "TOKEN:[^|]*" | cut -d':' -f2)

if [ -z "$RUNNER_ID" ] || [ -z "$RUNNER_TOKEN" ]; then
  echo "Error: Failed to create runner. API response:"
  echo "$RUNNER_RESPONSE"
  exit 1
fi

echo "✓ Runner created successfully"
echo "  Runner ID: $RUNNER_ID"
echo "  Token: ${RUNNER_TOKEN:0:20}..."

# Generate the runner secret YAML
cat > "$OUTPUT_SECRET" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-runner-auth
  namespace: $RUNNER_NAMESPACE
type: Opaque
stringData:
  CI_SERVER_URL: $RUNNER_URL
  RUNNER_TOKEN: $RUNNER_TOKEN
EOF

echo ""
echo "✓ Runner secret generated: $OUTPUT_SECRET"
echo ""
echo "====================================================="
echo "  GitLab runner provisioning complete!"
echo "====================================================="
echo ""
echo "What was done:"
echo "  ✓ Created a new GitLab instance runner (ID: $RUNNER_ID)"
echo "  ✓ Extracted runner authentication token"
echo "  ✓ Generated Kubernetes secret YAML → $OUTPUT_SECRET"
echo ""
echo "Next steps:"
echo "  1. Apply the secret:     kubectl apply -f $OUTPUT_SECRET"
echo "  2. Deploy RBAC:          kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml"
echo "  3. Deploy runner pod:    kubectl apply -f kubernetes/gitlab/04-runner.yaml"
echo "  4. Wait for ready:       kubectl wait --for=condition=available --timeout=300s deployment/gitlab-runner -n gitlab"
echo ""
echo "Verify runner is online:"
echo "  kubectl logs -n gitlab deployment/gitlab-runner -f"
echo "  or: Admin Area → CI/CD → Runners (should show green 'online' status)"
echo ""
echo "  or check in GitLab UI: Admin → CI/CD → Runners"
