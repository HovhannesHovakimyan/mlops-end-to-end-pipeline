# Self-Managed GitLab + Runner on Kubernetes

This guide deploys a **single-node, lab/dev** GitLab instance and GitLab Runner into your Kubernetes cluster.
It is suitable for demos and local testing of this repository's `.gitlab-ci.yml` pipeline.

## What You Get

- In-cluster GitLab CE service (`namespace: gitlab`)
- In-cluster GitLab Runner (Kubernetes executor)
- Runner tags compatible with this project (`kubernetes`, `docker`)

## Important Notes

- This setup is **not production-hardened**.
- Runner is bound to `cluster-admin` for simplicity in lab usage.
- Docker-in-Docker jobs require privileged runner pods.
- You must replace the runner registration token before starting the runner.

## Deploy GitLab + Runner

```bash
kubectl apply -f kubernetes/gitlab/01-namespace.yaml
kubectl apply -f kubernetes/gitlab/02-gitlab.yaml
kubectl wait --for=condition=available --timeout=900s deployment/gitlab -n gitlab
```

Create runner auth secret:

```bash
cp kubernetes/gitlab/05-runner-secret.example.yaml /tmp/gitlab-runner-secret.yaml
# Edit RUNNER_REGISTRATION_TOKEN in /tmp/gitlab-runner-secret.yaml
kubectl apply -f /tmp/gitlab-runner-secret.yaml
```

Deploy runner:

```bash
kubectl apply -f kubernetes/gitlab/03-runner-rbac.yaml
kubectl apply -f kubernetes/gitlab/04-runner.yaml
kubectl wait --for=condition=available --timeout=300s deployment/gitlab-runner -n gitlab
```

## Access GitLab UI

```bash
kubectl port-forward -n gitlab svc/gitlab 8088:80
```

Open: `http://localhost:8088`

Default user: `root`

Default password (from manifest): `ChangeMeImmediately!`

Change it right after first login.

## Configure Project and Trigger Pipeline

1. Create/import your project in GitLab.
2. Set repository pull mirroring from GitHub (optional but recommended).
3. Confirm a runner is online in `Settings -> CI/CD -> Runners`.
4. Add required CI/CD variables used by `.gitlab-ci.yml`:
   - `REGISTRY_USER`
   - `REGISTRY_PASSWORD`
   - `MLFLOW_TRACKING_URI`
   - `MINIO_ENDPOINT`
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `KUBE_CONTEXT`
   - `KUBE_CONTEXT_STAGING`
5. Push to `main` (or run pipeline manually) and watch jobs execute.

## Cleanup

```bash
kubectl delete -f kubernetes/gitlab/04-runner.yaml
kubectl delete -f kubernetes/gitlab/03-runner-rbac.yaml
kubectl delete secret gitlab-runner-auth -n gitlab --ignore-not-found
kubectl delete -f kubernetes/gitlab/02-gitlab.yaml
kubectl delete -f kubernetes/gitlab/01-namespace.yaml
```
