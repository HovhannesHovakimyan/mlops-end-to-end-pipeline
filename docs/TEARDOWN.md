# Project Teardown Guide

This guide removes the project resources created by this repository, including Kubernetes manifests and the optional local Minikube cluster used for Path A2.

## Scope

This teardown removes:
- Namespaces and workloads created from `kubernetes/*.yaml`
- Path A2 GitLab and runner resources from `kubernetes/gitlab/*.yaml`
- Optional local Minikube profile (`path-a2-test`)

This teardown does not uninstall Minikube from your machine. It only deletes the local cluster profile.

## Fast Path

Run the full teardown with one command:

```bash
make teardown-path-a2
```

This wraps the manual steps below.

## Prerequisites

- `kubectl` installed and configured
- `minikube` installed (only if you want to delete local Minikube cluster)
- Access to the repository root

## Step 1: Move to repository root

```bash
cd /path/to/mlops-end-to-end-pipeline
```

## Step 2: Delete project manifests (required)

Delete manifests in reverse lexical order so dependent resources are removed before namespaces.

```bash
find kubernetes -type f \( -name "*.yaml" -o -name "*.yml" \) | sort -r | while read -r f; do
  echo "Deleting $f"
  kubectl delete -f "$f" --ignore-not-found
done
```

## Step 3: Remove namespace leftovers (recommended)

```bash
kubectl delete ns gitlab minio mlflow kserve --ignore-not-found
```

Notes:
- Namespace deletion can take a minute or more.
- If you did not deploy some components, `--ignore-not-found` avoids errors.

## Step 4: Verify Kubernetes resources are gone

```bash
kubectl get ns
kubectl get all -A
```

You should no longer see active project workloads in `gitlab`, `minio`, `mlflow`, or `kserve`.

## Step 5: Delete temporary Minikube cluster (optional)

Use this only for local Path A2 cleanup.

```bash
minikube delete -p path-a2-test
```

Verify:

```bash
minikube profile list
```

## One-command full teardown (optional)

```bash
set -e
find kubernetes -type f \( -name "*.yaml" -o -name "*.yml" \) | sort -r | while read -r f; do
  kubectl delete -f "$f" --ignore-not-found || true
done
kubectl delete ns gitlab minio mlflow kserve --ignore-not-found || true
minikube delete -p path-a2-test || true
```

## Troubleshooting

### `kubectl` cannot connect to cluster

Check context and cluster status:

```bash
kubectl config current-context
kubectl cluster-info
```

### Stuck namespace in `Terminating`

Common causes are dangling finalizers or deleted CRDs that owned custom resources.

Helpful checks:

```bash
kubectl get ns <namespace> -o json
kubectl api-resources | wc -l
```

If a namespace remains stuck, restore missing CRDs temporarily or remove finalizers carefully as a last resort.
