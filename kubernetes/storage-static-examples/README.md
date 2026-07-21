# Static storage profile (optional)

Use this profile if your cluster does not have a default dynamic provisioner/StorageClass, and PVCs stay in Pending state.

The default project manifests already include PVCs:
- minio/minio-pvc (50Gi)
- mlflow/mlflow-pvc (20Gi)

These example PV manifests let those existing PVCs bind in clusters without auto-provisioning.

## Files

- 00-pv-hostpath-single-node.example.yaml
  - Single-node lab/dev clusters only.
  - Uses hostPath and is not recommended for production.

- 01-pv-nfs.example.yaml
  - Multi-node friendly option.
  - Edit NFS server/path values before applying.

## How to use

1. Create namespaces first:
   kubectl apply -f kubernetes/01-namespaces.yaml

2. Apply one static PV example file:
   kubectl apply -f kubernetes/storage-static-examples/00-pv-hostpath-single-node.example.yaml
   or
   kubectl apply -f kubernetes/storage-static-examples/01-pv-nfs.example.yaml

3. Apply application manifests as usual:
   kubectl apply -f kubernetes/02-minio.yaml
   kubectl apply -f kubernetes/03-mlflow.yaml

4. Verify binding:
   kubectl get pv
   kubectl get pvc -n minio
   kubectl get pvc -n mlflow

## Notes

- Dynamic provisioning environments (Minikube, k3d, Docker Desktop defaults) usually do not need these files.
- If you switch between dynamic and static storage modes in the same cluster, clean up old PVC/PV resources carefully.
