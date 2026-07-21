# GitLab Runner Provisioning: Three Approaches

Quick reference for choosing and using the runner provisioning method that best fits your workflow.

## ⭐ Recommended Approach: CLI Script (Approach 2)

For most use cases, the **CLI provisioner script** is the best balance:
- ✅ Fully automated (no UI steps after admin token creation)
- ✅ Simple to run (`kubernetes/gitlab/06-runner-provisioner.sh`)
- ✅ Fast (~2 minutes)
- ✅ Repeatable and testable
- ✅ No Kubernetes Job overhead

**Quick Start:**
```bash
export GITLAB_ADMIN_TOKEN="glpat-your_token"
kubernetes/gitlab/06-runner-provisioner.sh
kubectl apply -f /tmp/gitlab-runner-secret.yaml
kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
kubectl apply -f kubernetes/gitlab/04-runner.yaml
```

---

## Comparison Table

| Aspect | Manual (UI) | **CLI Script (Recommended)** | Kubernetes Job |
|--------|------------|-----------|-----------------|
| **User Interaction** | 5-6 manual UI steps | **1 CLI command** | Fully automated |
| **Admin Token** | Retrieved from UI | Create once, reuse | Auto-created by job |
| **Setup Time** | ~5 minutes | **~2 minutes** | ~5 minutes (one-time) |
| **Idempotency** | Manual (easy to forget runner) | Each run creates new runner | Controlled via Job |
| **CI/CD Integration** | ❌ Not suitable | ⚠️ Needs token in secrets | ✅ Ideal for GitOps |
| **Error Recovery** | Manual deletion required | Run script again | Delete job, rerun |
| **Recommended** | ❌ No | **✅ YES** | ✅ For GitOps only |

## Approach 1: Manual UI (Best for Learning)

**When to use:** First-time setup, exploring GitLab, quick lab testing

**Steps:**
```bash
# 1. Port-forward and open UI
kubectl port-forward -n gitlab svc/gitlab 8088:80 &
# → Open http://localhost:8088

# 2. In GitLab UI:
#    Admin → CI/CD → Runners → Create runner
#    OS: Linux, Tags: kubernetes,docker
#    Copy the authentication token

# 3. Create secret manually
cp kubernetes/gitlab/05-runner-secret.example.yaml /tmp/gitlab-runner-secret.yaml
# Edit RUNNER_TOKEN with your token
kubectl apply -f /tmp/gitlab-runner-secret.yaml

# 4. Deploy runner
kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
kubectl apply -f kubernetes/gitlab/04-runner.yaml
```

**Time:** ~5 minutes | **Effort:** Manual | **Reproducible:** No (requires remembering steps)

---

## Approach 2: CLI Provisioner Script (Best for Development)

**When to use:** Automated local development, testing deployments, when you want simple scripting

**Steps:**
```bash
# 1. Get admin token (one-time per GitLab instance)
kubectl port-forward -n gitlab svc/gitlab 8088:80 &
# → Open http://localhost:8088
# → Avatar (top right) → User settings → Access → Personal access tokens
# → Create token with name "provisioner" and scope "admin"
# → Copy token, e.g., glpat-ABC123xyz

# 2. Run provisioner script
export GITLAB_ADMIN_TOKEN="glpat-ABC123xyz"
kubernetes/gitlab/06-runner-provisioner.sh

# 3. Apply generated secret and deploy runner
kubectl apply -f /tmp/gitlab-runner-secret.yaml
kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
kubectl apply -f kubernetes/gitlab/04-runner.yaml
```

**Time:** ~2-3 minutes | **Effort:** Minimal | **Reproducible:** Yes (script is idempotent, but creates new runner each time)

**Features:**
- ✅ Uses GitLab REST API (`POST /api/v4/admin/runners`)
- ✅ Automatically extracts runner token
- ✅ Generates Kubernetes secret YAML
- ✅ Error handling and validation

**Advanced Usage — Environment Variables:**
```bash
export GITLAB_URL="http://gitlab.example.com"
export GITLAB_ADMIN_TOKEN="glpat-..."
kubernetes/gitlab/06-runner-provisioner.sh
```

**Advanced Usage — CLI Arguments:**
```bash
kubernetes/gitlab/06-runner-provisioner.sh \
  --gitlab-url http://gitlab.example.com \
  --admin-token glpat-ABC123xyz
```

---

## Approach 3: Kubernetes Job (Best for GitOps / Production)

**When to use:** Production environments, fully declarative deployments, GitOps workflows (Flux, ArgoCD), CI/CD pipeline environment setup

**Steps:**
```bash
# 1. Deploy GitLab
kubectl apply -f kubernetes/gitlab/01-namespace.yaml
kubectl apply -f kubernetes/gitlab/02-gitlab.yaml
kubectl wait --for=condition=available --timeout=900s deployment/gitlab -n gitlab

# 2. Create admin token secret (one-time, auto-created by provisioner)
ADMIN_TOKEN=$(kubectl exec -it -n gitlab deployment/gitlab -- \
  gitlab-rails runner \
  "token = PersonalAccessToken.create(user: User.find(1), name: 'provisioner', scopes: [:api, :admin]); puts token.token" | tr -d '\r')
kubectl create secret generic gitlab-admin-token --from-literal=token="$ADMIN_TOKEN" -n gitlab

# 3. Deploy runner provisioner job (creates runner automatically)
kubectl apply -f kubernetes/gitlab/07-runner-provisioner-job.yaml
kubectl wait --for=condition=complete --timeout=300s job/gitlab-runner-provisioner -n gitlab

# 4. Deploy runner RBAC and pod
kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
kubectl apply -f kubernetes/gitlab/04-runner.yaml
```

**Time:** ~10 minutes (one-time) | **Effort:** Zero after Job setup | **Reproducible:** Yes (fully declarative)

**Features:**
- ✅ Fully declarative and GitOps-compatible
- ✅ Can be managed by Flux/ArgoCD
- ✅ Automatic admin token creation
- ✅ Job cleans up after 5 minutes (ttlSecondsAfterFinished)
- ✅ Exponential backoff and error handling

**For GitOps (Flux/ArgoCD):**
```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - kubernetes/gitlab/01-namespace.yaml
  - kubernetes/gitlab/02-gitlab.yaml
  - kubernetes/gitlab/03-runner-rbac.yaml
  - kubernetes/gitlab/04-runner.yaml
  - kubernetes/gitlab/07-runner-provisioner-job.yaml  # Automatically runs!
```

---

## Comparison: Real-World Scenarios

### Scenario 1: Quick Lab Testing
→ **Use Approach 1 (Manual UI)**
- Don't need to script anything
- Easy to understand each step
- Can inspect what's created via UI

### Scenario 2: Local Development with Multiple Clusters
→ **Use Approach 2 (CLI Script)**
```bash
for cluster in dev test staging; do
  kubectx $cluster
  kubernetes/gitlab/06-runner-provisioner.sh
  kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
  kubectl apply -f kubernetes/gitlab/04-runner.yaml
done
```

### Scenario 3: Production Environment Setup
→ **Use Approach 3 (Kubernetes Job)**
```bash
# Commit to Git
git add kubernetes/gitlab/07-runner-provisioner-job.yaml
git commit -m "Add automated runner provisioner"

# Push to trigger GitOps
git push
# → Flux/ArgoCD auto-reconciles and deploys
```

### Scenario 4: Ephemeral Test Environments
→ **Use Approach 3 + Helm/Kustomize**
```bash
helm template gitlab kubernetes/gitlab/ | kubectl apply -f -
# Everything auto-provisions including runner
```

---

## Troubleshooting

### Script vs. UI vs. Job: Which should I choose?

| Problem | Solution |
|---------|----------|
| "I just want to learn GitLab" | Use Approach 1 (Manual UI) |
| "I deploy locally frequently" | Use Approach 2 (Script) |
| "I use Flux/ArgoCD" | Use Approach 3 (Job) |
| "I'm not sure" | Start with Approach 1, then move to Approach 2 |

### Common Issues

**Problem:** Token not working in script
```bash
# Verify token has admin scope
kubectl port-forward -n gitlab svc/gitlab 8088:80 &
# → Check token in Avatar (top right) → User settings → Access → Personal access tokens
# → Token should show scopes: api, admin
```

**Problem:** Job fails to create runner
```bash
# Check job logs
kubectl logs -n gitlab job/gitlab-runner-provisioner

# Verify admin token secret
kubectl get secret -n gitlab gitlab-admin-token -o jsonpath='{.data.token}' | base64 -d

# Check GitLab pod is ready
kubectl get pod -n gitlab -l app=gitlab
```

**Problem:** "Runner not appearing in GitLab UI"
```bash
# Check runner pod logs
kubectl logs -n gitlab deployment/gitlab-runner

# Verify network connectivity
kubectl exec -it -n gitlab deployment/gitlab-runner -- \
  curl -s http://gitlab.gitlab.svc.cluster.local/api/v4/version
```

---

## Migration Path

If you start with one approach and want to switch:

**Manual → Script:**
```bash
# Delete old runner in UI (Admin → CI/CD → Runners)
# Run provisioner script with new admin token
kubernetes/gitlab/06-runner-provisioner.sh
```

**Script → Job:**
```bash
# Store admin token as Kubernetes secret
kubectl create secret generic gitlab-admin-token \
  --from-literal=token=$GITLAB_ADMIN_TOKEN -n gitlab

# Deploy Job
kubectl apply -f kubernetes/gitlab/07-runner-provisioner-job.yaml
```

---

## Reference: API Calls Used

All three approaches use the same underlying GitLab API, just at different levels:

**REST API Endpoint:**
```
POST /api/v4/admin/runners
Header: PRIVATE-TOKEN: <admin_token>

Request:
{
  "runner_type": "instance_type",
  "is_shared": true,
  "tag_list": ["kubernetes", "docker"],
  "run_untagged": true,
  "locked": false
}

Response:
{
  "id": 1,
  "token": "glrt-...",  ← Use this in runner config
  "authentication_token": "glrt-...",
  "created_at": "2026-07-21T23:12:00Z"
}
```

**GitLab Rails CLI (used by Job):**
```ruby
token = PersonalAccessToken.create(
  user: User.find(1),  # root user
  name: 'provisioner',
  scopes: [:api, :admin]
)
puts token.token  # → glpat-...
```

---

## Next Steps

1. **Choose your approach** based on the comparison table above
2. **Follow the steps** for your chosen approach
3. **Verify runner is online**: `kubectl logs -n gitlab deployment/gitlab-runner`
4. **Check in GitLab UI**: Admin → CI/CD → Runners (should show green "online" status)
5. **Push to main branch** to trigger your first training pipeline!

For more details on each approach, see:
- Manual UI: `docs/GITLAB_SELF_MANAGED.md` → Method 2
- CLI Script: `docs/GITLAB_SELF_MANAGED.md` → Method 1
- Kubernetes Job: `docs/GITLAB_AUTOMATED_PROVISIONING.md`
