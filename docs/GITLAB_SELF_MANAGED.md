# Self-Managed GitLab + Runner on Kubernetes

This guide deploys a **single-node, lab/dev** GitLab instance and GitLab Runner into your Kubernetes cluster.
It is suitable for demos and local testing of this repository's `.gitlab-ci.yml` pipeline.

**Version:** GitLab CE 19.2.0 (latest) | GitLab Runner 19.2.0

## What You Get

- In-cluster GitLab CE service (`namespace: gitlab`) — GitLab 19.2.0
- In-cluster GitLab Runner (Kubernetes executor) — GitLab Runner 19.2.0
- Runner tags compatible with this project (`kubernetes`, `docker`)
- Cluster-contained CI infrastructure for this path (no local runtime installation required beyond `kubectl` and cluster access)

## Important Notes

- This setup is **not production-hardened**.
- Runner is bound to `cluster-admin` for simplicity in lab usage.
- Docker-in-Docker jobs require privileged runner pods.
- **Architecture (arm64):** The runner helper image is pinned to `arm64-v19.2.0` for Apple Silicon / arm64 nodes. If you run on x86_64, change `helper_image` in `kubernetes/gitlab/04-runner.yaml` from `arm64-v19.2.0` to `x86_64-v19.2.0`.
- **Modern token authentication:** Uses runner authentication tokens (GitLab 19.2.0 recommended method) created via API or UI.
- **⭐ Recommended: Automated provisioning via API** — The `06-runner-provisioner.sh` script (Method 1 below) automates runner creation via REST API with zero manual UI steps. No manual secret editing, no token copy-pasting. This is the fastest and most reliable approach.

## Deploy GitLab + Runner

```bash
kubectl apply -f kubernetes/gitlab/01-namespace.yaml
kubectl apply -f kubernetes/gitlab/02-gitlab.yaml
kubectl wait --for=condition=available --timeout=900s deployment/gitlab -n gitlab
```

**→ Need help choosing how to provision the runner?** See [GITLAB_RUNNER_PROVISIONING_GUIDE.md](GITLAB_RUNNER_PROVISIONING_GUIDE.md) for a comparison of manual UI, CLI script, and Kubernetes Job approaches.

## Runner Provisioning: Two Methods

### Method 1: Automated (Recommended) — Via GitLab Rails CLI

The provisioner script automates runner creation via GitLab's internal Rails CLI — no credentials or API calls needed, works with any GitLab version:

1. **Run the provisioner script** (no setup needed):
   ```bash
   kubernetes/gitlab/06-runner-provisioner.sh
   ```

   That's it! The script will:
   - ✅ Exec into the GitLab pod
   - ✅ Create a new runner via Rails CLI
   - ✅ Extract the authentication token
   - ✅ Generate `/tmp/gitlab-runner-secret.yaml` automatically

2. **Deploy the generated secret and runner**:
   ```bash
   kubectl apply -f /tmp/gitlab-runner-secret.yaml
   kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
   kubectl apply -f kubernetes/gitlab/04-runner.yaml
   kubectl wait --for=condition=available --timeout=300s deployment/gitlab-runner -n gitlab
   ```

### Method 2: Manual — Via GitLab UI

If you prefer to create the runner manually in the UI:

1. **Access GitLab UI** and get authentication token:
   ```bash
   kubectl port-forward -n gitlab svc/gitlab 8088:80 &
   ```

   Open [http://localhost:8088](http://localhost:8088), log in as `root` / `ChangeMeImmediately!`. Then:
   - Click **Admin Area** (wrench icon)
   - Go to **CI/CD → Runners**
   - Click **Create runner** (top right)
   - Select **Operating system:** Linux
   - Add **Tags:** `kubernetes,docker`
   - Leave other settings as defaults, click **Create runner**
   - Copy the **Runner authentication token** (shown once only)
   - Change the default password immediately

2. **Create runner secret manually**:
   ```bash
   cp kubernetes/gitlab/05-runner-secret.example.yaml /tmp/gitlab-runner-secret.yaml
   # Edit RUNNER_TOKEN in /tmp/gitlab-runner-secret.yaml with the token you copied
   kubectl apply -f /tmp/gitlab-runner-secret.yaml
   ```

3. **Deploy runner**:
   ```bash
   kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
   kubectl apply -f kubernetes/gitlab/04-runner.yaml
   kubectl wait --for=condition=available --timeout=300s deployment/gitlab-runner -n gitlab
   ```

## Configure Project and Trigger Pipeline

### ⭐ Method 1: Automated Setup (Recommended)

1. **Create a CI/CD variables file:**
   ```bash
   cp kubernetes/gitlab/variables.env.example variables.env
   # Edit variables.env with your actual values
   ```

2. **Run the project provisioner:**
   ```bash
   # If importing from GitHub
   kubernetes/gitlab/07-project-provisioner.sh \
     --gitlab-url http://localhost:8088 \
     --admin-token glpat-xxxx \
     --project-name mlops-e2e \
     --github-url https://github.com/your-username/your-repo.git \
     --variables-file variables.env

   # Or create blank project
   kubernetes/gitlab/07-project-provisioner.sh \
     --gitlab-url http://localhost:8088 \
     --admin-token glpat-xxxx \
     --project-name mlops-e2e \
     --variables-file variables.env
   ```

   This will automatically:
   - ✓ Create the GitLab project
   - ✓ Add all CI/CD variables

3. **Push code from GitHub to GitLab (if using GitHub URL):**
   ```bash
   kubernetes/gitlab/08-populate-project-from-github.sh \
     --github-url https://github.com/your-username/your-repo.git \
     --gitlab-url http://localhost:8088 \
     --gitlab-project-path root/mlops-e2e \
     --admin-token glpat-xxxx \
     --local-dir /tmp/mlops-repo
   ```

   This will automatically:
   - ✓ Clone the GitHub repo locally
   - ✓ Push all branches and tags to GitLab (handles protected branch rules)
   - ✓ Verify `.gitlab-ci.yml` is present

4. **Confirm runner is online:**
   - Go to **Admin area → CI/CD → Runners**
   - Verify Runner ID 1 shows green "online" status

5. **Trigger the pipeline:**
   ```bash
   git push origin main
   ```

---

### Alternative: Manual Setup (If Preferred)

If you prefer to configure the project manually via GitLab UI:

1. **Create or import your project in GitLab:**
   - Log in to [http://localhost:8088](http://localhost:8088) as `root` / `ChangeMeImmediately!`
   - Click the **+** icon (top left) → **New project/repository**
   - Choose **Create blank project** or **Import project** (paste GitHub URL)
   - Note the project path (e.g., `root/mlops-e2e`)

2. **Add required CI/CD variables:**
   - Go to your project → **Settings → CI/CD → Variables**
   - Click **Add variable** for each of the following:
     - `REGISTRY_USER`, `REGISTRY_PASSWORD`
     - `MLFLOW_TRACKING_URI` (e.g., `http://mlflow.mlflow:5000`)
     - `MINIO_ENDPOINT` (e.g., `http://minio.minio:9000`)
     - `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
     - `KUBE_CONTEXT`, `KUBE_CONTEXT_STAGING`
   - Mark sensitive variables as **Protected** and **Masked**

3. **Confirm runner is online:** **Admin area → CI/CD → Runners** → Runner ID 1 should show green "online"

4. **Trigger the pipeline:**
   - Push code: `git push origin main`, or
   - Go to your project → **Build → Pipelines** → click **Run pipeline**

---

### Monitor Pipeline Execution (Both Methods)

- **GitLab UI**: Navigate to your project → **Build → Pipelines** to see job status
- **Detailed logs**: Click any job to view execution logs
- **Runner activity**: `kubectl logs -n gitlab deployment/gitlab-runner -f`
- **Expected pipeline stages** (from `.gitlab-ci.yml`):
  - **train**: Runs training job, uploads model to MinIO
  - **deploy**: Creates/updates InferenceService in KServe
  - **monitor**: (Optional) Sets up monitoring and logging

## Authentication Method (Modern Token-Based)

This setup uses **GitLab Runner authentication tokens** (the recommended method in GitLab 19.2.0+), not the legacy registration token flow:

- **Legacy method** (deprecated): `gitlab-runner register --registration-token` command that auto-created runners
- **Modern method** (current): Create a runner in GitLab UI, receive an authentication token, embed token in `config.toml`

Benefits:
- ✅ Token is generated once and visible only at creation time (better security)
- ✅ Runner lifecycle can be managed independently in GitLab UI
- ✅ Simplified troubleshooting (UI shows runner status and logs)
- ✅ Aligned with GitLab's current architecture

If you need to rotate the token, delete the runner in GitLab UI and create a new one with a fresh authentication token.

## Provisioner Script Reference

The `06-runner-provisioner.sh` script simplifies runner setup by automating the GitLab API calls:

**How it works:**
1. Takes an admin access token as input (retrieved from GitLab personal settings)
2. Calls GitLab's REST API (`POST /api/v4/admin/runners`)
3. Extracts the runner ID and authentication token from the API response
4. Generates the Kubernetes secret YAML with the token pre-populated

**Idempotency:** Each script invocation creates a **new runner**. If you run it twice, you'll get two runners. To avoid this in automated pipelines, either:
- Save and reuse the generated secret
- Check if runner already exists before re-running
- Delete the runner in GitLab UI before re-running the provisioner

**Admin Token Notes:**
- Create it in GitLab UI: Avatar → User settings → Access → Personal access tokens (scopes: `api`, `admin_mode`)
- Or use an existing admin account's session token
- For production: use CI/CD secrets to store the admin token securely
- Token is temporary for provisioning — delete it after runner is created if desired

## Cleanup

```bash
kubectl delete -f kubernetes/gitlab/04-runner.yaml
kubectl delete -f kubernetes/gitlab/03-runner-rbac.yaml
kubectl delete secret gitlab-runner-auth -n gitlab --ignore-not-found
kubectl delete -f kubernetes/gitlab/02-gitlab.yaml
kubectl delete -f kubernetes/gitlab/01-namespace.yaml
```
