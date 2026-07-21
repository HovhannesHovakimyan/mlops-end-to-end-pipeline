# Automated GitLab + Runner Provisioning via Kubernetes Job

> ℹ️ **Before reading this:** For most users, the **CLI provisioner script** (`kubernetes/gitlab/06-runner-provisioner.sh`) in `docs/GITLAB_RUNNER_PROVISIONING_GUIDE.md` is the recommended approach. Read this guide only if you need fully declarative Kubernetes Job-based provisioning for GitOps workflows.

This document shows how to fully automate GitLab and runner setup using a **Kubernetes Job** for declarative infrastructure-as-code deployments.

## Use Case — When to Use This

- ✅ **GitOps workflows** (Flux, ArgoCD) — everything must be declarative YAML
- ✅ **Ephemeral test environments** — automated provisioning on cluster creation
- ✅ **Production-grade automation** — Kubernetes-native error handling and retry logic
- ✅ **Multi-cluster provisioning** — the same Job can deploy to multiple clusters

## When NOT to Use This

- ❌ **Quick lab testing** — use CLI script instead (faster, simpler)
- ❌ **Local development** — use CLI script instead
- ❌ **One-time setup** — use CLI script or manual UI

## Architecture

```
init-gitlab-job → wait for GitLab ready → create admin token → provision runner → runner pod starts
```

## Implementation

### Step 1: Deploy GitLab

```bash
kubectl apply -f kubernetes/gitlab/01-namespace.yaml
kubectl apply -f kubernetes/gitlab/02-gitlab.yaml
kubectl wait --for=condition=available --timeout=900s deployment/gitlab -n gitlab
```

### Step 2: Create Admin Token (One-time, done once)

The admin token is created via GitLab's internal CLI. This is a one-time operation:

```bash
# Option A: Exec into GitLab pod and create token
kubectl exec -it -n gitlab deployment/gitlab -- \
  gitlab-rails runner \
  "token = PersonalAccessToken.create(user: User.find(1), name: 'runner-provisioner', scopes: [:api, :admin]); puts token.token"
```

Or if you want to do this programmatically within a Kubernetes Job, use the provisioner setup job below.

### Step 3: Automated Runner Provisioning Job (Optional but Recommended)

This Kubernetes Job automates the entire runner setup process:

**File: `kubernetes/gitlab/07-runner-provisioner-job.yaml`**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: gitlab-runner-provisioner
  namespace: gitlab
spec:
  ttlSecondsAfterFinished: 300  # Clean up job after 5 minutes
  backoffLimit: 3
  template:
    spec:
      serviceAccountName: default
      restartPolicy: Never
      containers:
      - name: provisioner
        image: curlimages/curl:latest
        env:
        - name: GITLAB_URL
          value: "http://gitlab.gitlab.svc.cluster.local"
        - name: GITLAB_ADMIN_TOKEN
          valueFrom:
            secretKeyRef:
              name: gitlab-admin-token
              key: token
        command:
        - /bin/sh
        - -c
        - |
          set -e

          echo "Waiting for GitLab API to be ready..."
          for i in {1..60}; do
            if curl -s -f "$GITLAB_URL/api/v4/version" > /dev/null; then
              echo "✓ GitLab API is ready"
              break
            fi
            echo "  Attempt $i/60..."
            sleep 5
          done

          echo "Creating runner via GitLab API..."
          RUNNER_RESPONSE=$(curl -s -X POST \
            "$GITLAB_URL/api/v4/admin/runners" \
            --header "PRIVATE-TOKEN: $GITLAB_ADMIN_TOKEN" \
            --header "Content-Type: application/json" \
            --data '{
              "runner_type": "instance_type",
              "is_shared": true,
              "paused": false,
              "locked": false,
              "run_untagged": true,
              "tag_list": ["kubernetes", "docker"],
              "maximum_timeout": 3600
            }')

          echo "API Response: $RUNNER_RESPONSE"
          RUNNER_TOKEN=$(echo "$RUNNER_RESPONSE" | grep -o '"authentication_token":"[^"]*"' | cut -d'"' -f4)

          if [ -z "$RUNNER_TOKEN" ]; then
            echo "✗ Failed to create runner"
            exit 1
          fi

          echo "✓ Runner created, token: ${RUNNER_TOKEN:0:20}..."

          # Create the secret
          kubectl create secret generic gitlab-runner-auth \
            --from-literal=CI_SERVER_URL=$GITLAB_URL \
            --from-literal=RUNNER_TOKEN=$RUNNER_TOKEN \
            -n gitlab \
            --dry-run=client \
            -o yaml | kubectl apply -f -

          echo "✓ Runner secret created"
          echo "Next: kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml"
          echo "      kubectl apply -f kubernetes/gitlab/04-runner.yaml"
```

### Step 4: Create Admin Token Secret

Before running the provisioner job, create the admin token secret:

**Option A: Get existing root password and create token**

```bash
# Option 1: Use the provisioner script's built-in setup
kubernetes/gitlab/06-runner-provisioner.sh --setup-admin-token
```

**Option B: Manually create and store**

```bash
# Get admin token from GitLab pod
ADMIN_TOKEN=$(kubectl exec -it -n gitlab deployment/gitlab -- \
  gitlab-rails runner \
  "token = PersonalAccessToken.create(user: User.find(1), name: 'runner-provisioner', scopes: [:api, :admin]); puts token.token" | tr -d '\r')

# Store it in Kubernetes secret
kubectl create secret generic gitlab-admin-token \
  --from-literal=token="$ADMIN_TOKEN" \
  -n gitlab
```

### Step 5: Deploy Runner Provisioner Job

```bash
kubectl apply -f kubernetes/gitlab/07-runner-provisioner-job.yaml
kubectl wait --for=condition=complete --timeout=300s job/gitlab-runner-provisioner -n gitlab
```

### Step 6: Deploy Runner RBAC and Pod

```bash
kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
kubectl apply -f kubernetes/gitlab/04-runner.yaml
kubectl wait --for=condition=available --timeout=300s deployment/gitlab-runner -n gitlab
```

## Fully Automated One-Shot Deployment

To deploy everything in one command:

```bash
#!/bin/bash
set -e

echo "1. Creating namespace and storage..."
kubectl apply -f kubernetes/gitlab/01-namespace.yaml

echo "2. Deploying GitLab CE..."
kubectl apply -f kubernetes/gitlab/02-gitlab.yaml
kubectl wait --for=condition=available --timeout=900s deployment/gitlab -n gitlab

echo "3. Creating admin token secret..."
ADMIN_TOKEN=$(kubectl exec -it -n gitlab deployment/gitlab -- \
  gitlab-rails runner \
  "token = PersonalAccessToken.create(user: User.find(1), name: 'runner-provisioner', scopes: [:api, :admin]); puts token.token" | tr -d '\r')
kubectl create secret generic gitlab-admin-token --from-literal=token="$ADMIN_TOKEN" -n gitlab

echo "4. Running runner provisioner job..."
kubectl apply -f kubernetes/gitlab/07-runner-provisioner-job.yaml
kubectl wait --for=condition=complete --timeout=300s job/gitlab-runner-provisioner -n gitlab

echo "5. Deploying runner RBAC and pod..."
kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
kubectl apply -f kubernetes/gitlab/04-runner.yaml
kubectl wait --for=condition=available --timeout=300s deployment/gitlab-runner -n gitlab

echo "✓ GitLab + Runner fully deployed!"
```

## API Reference

**Create Runner Endpoint:**
- `POST /api/v4/admin/runners`
- Requires: `PRIVATE-TOKEN` header with admin scope
- Response includes: `id`, `authentication_token`, `created_at`

**Required Parameters:**
- `runner_type`: `"instance_type"` (system-wide runner) or `"group_type"` / `"project_type"`
- `is_shared`: `true` for instance runners

**Optional Parameters:**
- `tag_list`: Array of tags (strings)
- `run_untagged`: Boolean (allow untagged jobs)
- `paused`: Boolean
- `locked`: Boolean (prevent project override)
- `maximum_timeout`: Integer (seconds)

## Troubleshooting

**Problem:** Admin token creation fails
```bash
# Verify GitLab pod is ready
kubectl get pod -n gitlab -l app=gitlab

# Check GitLab logs
kubectl logs -n gitlab deployment/gitlab
```

**Problem:** Runner provisioner job fails
```bash
# Check job logs
kubectl logs -n gitlab job/gitlab-runner-provisioner

# Verify admin token secret exists
kubectl get secret -n gitlab gitlab-admin-token
```

**Problem:** Runner doesn't show as "online" in GitLab UI
```bash
# Check runner pod logs
kubectl logs -n gitlab deployment/gitlab-runner

# Verify runner secret has correct URL and token
kubectl get secret -n gitlab gitlab-runner-auth -o yaml
```

## Security Considerations

- ⚠️ Admin token is sensitive — store it in a secure secret manager for production
- ⚠️ The provisioner job outputs logs; consider using log redaction in production
- ✅ Token is created with minimal scope (`api`, `admin`) — rotate after provisioning
- ✅ Use Kubernetes RBAC to limit who can read secrets
- ✅ Consider setting token expiration in GitLab UI after creation

## GitOps Integration Example

For GitOps workflows using Flux or ArgoCD:

```yaml
apiVersion: kustomization.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: gitlab-setup
spec:
  interval: 1h
  sourceRef:
    kind: GitRepository
    name: mlops-pipeline
  path: ./kubernetes/gitlab
  patches:
  - target:
      kind: Deployment
      name: gitlab
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: "http://gitlab.example.com"  # Override URL for your domain
```

Then the provisioner job runs automatically as part of the reconciliation.
