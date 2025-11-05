# Setup Instructions for Auto-Rightsizing Test Environment

This guide provides step-by-step instructions for setting up and deploying the auto-rightsizing test environment with ArgoCD.

## Prerequisites Verification

Before starting, verify that you have the following components installed and running:

### 1. Kubernetes Cluster

```bash
kubectl cluster-info
kubectl get nodes
```

Expected: A running Kubernetes cluster (version 1.20+)

### 2. ArgoCD

```bash
kubectl get pods -n argocd
argocd version
```

Expected: ArgoCD pods running in the `argocd` namespace

If not installed:
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Metrics Server

Required for HPA to function:

```bash
kubectl get deployment metrics-server -n kube-system
```

If not installed:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 4. KEDA (for ScaledObject tests)

```bash
kubectl get pods -n keda
```

If not installed:
```bash
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml
```

### 5. Argo Rollouts (for Rollout tests)

```bash
kubectl get pods -n argo-rollouts
```

If not installed:
```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

## Setup Steps

### Step 1: Create and Initialize Git Repository

1. **Initialize the repository**:

```bash
cd /Users/amitbaroz/Documents/Customers/Affirm
git init
git add .
git commit -m "Initial commit: Auto-rightsizing test scenarios"
```

2. **Create a remote repository** on GitHub, GitLab, or your preferred Git hosting service.

3. **Push to remote**:

```bash
git remote add origin <YOUR_REPO_URL>
git branch -M main
git push -u origin main
```

**Important**: Note your repository URL - you'll need it in the next step.

### Step 2: Update ArgoCD Application Manifests

Update all ArgoCD Application manifests with your actual repository URL:

```bash
# Replace <REPLACE_WITH_YOUR_REPO_URL> with your actual repo URL
find argocd/applications -name "*.yaml" -exec sed -i '' 's|<REPLACE_WITH_YOUR_REPO_URL>|https://github.com/your-org/your-repo.git|g' {} \;
```

Or manually edit each file in `argocd/applications/` and replace:
```yaml
repoURL: <REPLACE_WITH_YOUR_REPO_URL>
```

with your actual repository URL:
```yaml
repoURL: https://github.com/your-org/your-repo.git
```

**Commit and push the changes**:
```bash
git add argocd/applications/
git commit -m "Update repository URLs in ArgoCD applications"
git push
```

### Step 3: Configure ArgoCD to Ignore HPA/ScaledObject Differences

This is the **most critical step** for auto-rightsizing to work without sync drift.

1. **Backup existing ArgoCD ConfigMap** (if it exists):

```bash
kubectl get configmap argocd-cm -n argocd -o yaml > argocd-cm-backup.yaml
```

2. **Apply the ignoreDifferences configuration**:

If you already have an `argocd-cm` ConfigMap with custom configurations, you'll need to **merge** the configurations manually. Otherwise:

```bash
kubectl apply -f argocd/configmap-ignoredifferences.yaml
```

3. **Restart ArgoCD Application Controller**:

The configuration changes require a restart to take effect:

```bash
kubectl rollout restart deployment argocd-application-controller -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd
```

4. **Verify the restart**:

```bash
kubectl rollout status deployment argocd-application-controller -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd
```

### Step 4: Deploy Test Applications via ArgoCD

Deploy all test scenarios:

```bash
kubectl apply -f argocd/applications/
```

Verify applications are created:

```bash
argocd app list
```

Expected output should show 8 applications:
- `deployment-hpa`
- `rollout-hpa`
- `deployment-scaledobject`
- `rollout-scaledobject`
- `deployment-hpa-container-thresholds`
- `rollout-hpa-container-thresholds`
- `deployment-scaledobject-container-thresholds`
- `rollout-scaledobject-container-thresholds`

### Step 5: Wait for Initial Sync

ArgoCD will automatically sync the applications. Monitor the sync status:

```bash
# Watch all applications
watch argocd app list

# Or check individual application
argocd app get deployment-hpa

# View sync status in detail
argocd app sync deployment-hpa --dry-run
```

Wait until all applications show status: `Synced` and `Healthy`.

### Step 6: Verify Deployments

1. **Check namespaces**:

```bash
kubectl get namespaces | grep -E 'deployment|rollout'
```

2. **Check pods in each namespace**:

```bash
for ns in deployment-hpa rollout-hpa deployment-scaledobject rollout-scaledobject \
          deployment-hpa-container-thresholds rollout-hpa-container-thresholds \
          deployment-scaledobject-container-thresholds rollout-scaledobject-container-thresholds; do
  echo "=== Namespace: $ns ==="
  kubectl get pods -n $ns
  echo ""
done
```

3. **Check HPAs**:

```bash
kubectl get hpa --all-namespaces | grep test-app
```

4. **Check ScaledObjects**:

```bash
kubectl get scaledobject --all-namespaces
```

5. **Check Rollouts**:

```bash
kubectl get rollout --all-namespaces
```

## Testing Auto-Rightsizing

Now that everything is deployed, you can test the auto-rightsizing functionality.

### Test 1: Modify HPA Thresholds

1. **Manually update an HPA**:

```bash
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/metrics/0/resource/target/averageUtilization", "value": 75}]'
```

2. **Verify ArgoCD doesn't detect drift**:

```bash
argocd app get deployment-hpa
```

Expected: Application status should remain `Synced` (not `OutOfSync`)

3. **Verify the change was applied**:

```bash
kubectl get hpa test-app-hpa -n deployment-hpa -o yaml | grep averageUtilization
```

### Test 2: Modify ScaledObject Triggers

1. **Update a ScaledObject**:

```bash
kubectl patch scaledobject test-app-scaledobject -n deployment-scaledobject \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/triggers/0/metadata/value", "value": "75"}]'
```

2. **Verify ArgoCD doesn't detect drift**:

```bash
argocd app get deployment-scaledobject
```

Expected: Application status should remain `Synced`

### Test 3: Modify Container-Specific Thresholds

For HPAs with container-specific metrics:

```bash
kubectl patch hpa test-app-hpa -n deployment-hpa-container-thresholds \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/metrics/0/containerResource/target/averageUtilization", "value": 65}]'
```

Verify ArgoCD sync status remains unchanged.

### Test 4: Simulate Auto-Rightsizing Changes

Create a script to simulate what your auto-rightsizing controller would do:

```bash
#!/bin/bash
# simulate-rightsizing.sh

# Update HPA thresholds based on "observed metrics"
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type='json' \
  -p='[
    {"op": "replace", "path": "/spec/metrics/0/resource/target/averageUtilization", "value": 65},
    {"op": "replace", "path": "/spec/metrics/1/resource/target/averageUtilization", "value": 75}
  ]'

# Update ScaledObject triggers
kubectl patch scaledobject test-app-scaledobject -n deployment-scaledobject \
  --type='json' \
  -p='[
    {"op": "replace", "path": "/spec/triggers/0/metadata/value", "value": "65"},
    {"op": "replace", "path": "/spec/triggers/1/metadata/value", "value": "75"}
  ]'

echo "Auto-rightsizing simulation complete"
echo "Checking ArgoCD sync status..."

sleep 5

argocd app list | grep -E 'deployment-hpa|deployment-scaledobject'
```

Run the script and verify applications remain synced.

## Validation Checklist

Use this checklist to validate your setup:

- [ ] All 8 ArgoCD Applications are deployed
- [ ] All applications show status: `Synced` and `Healthy`
- [ ] All pods are running in their respective namespaces
- [ ] HPAs are created and reporting metrics (may take 1-2 minutes)
- [ ] ScaledObjects are created and KEDA is managing them
- [ ] Rollouts are deployed and healthy
- [ ] Metrics Server is providing pod metrics
- [ ] Manual changes to HPA specs don't cause sync drift
- [ ] Manual changes to ScaledObject specs don't cause sync drift
- [ ] ArgoCD ConfigMap includes ignoreDifferences configuration
- [ ] ArgoCD controllers have been restarted after ConfigMap changes

## Troubleshooting

### Issue: ArgoCD Shows Applications as OutOfSync

**Diagnosis**:
```bash
argocd app get <app-name> --show-operation
argocd app diff <app-name>
```

**Solutions**:
1. Verify the ConfigMap was applied correctly:
   ```bash
   kubectl get configmap argocd-cm -n argocd -o yaml
   ```

2. Check if ignoreDifferences is configured:
   ```bash
   kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 10 "ignoreDifferences"
   ```

3. Restart ArgoCD controllers:
   ```bash
   kubectl rollout restart deployment argocd-application-controller -n argocd
   kubectl rollout restart deployment argocd-repo-server -n argocd
   ```

### Issue: HPAs Show "unknown" for Current Metrics

**Diagnosis**:
```bash
kubectl get hpa --all-namespaces
kubectl describe hpa <hpa-name> -n <namespace>
```

**Common causes**:
- Metrics Server not installed or not running
- Pods haven't been running long enough (wait 1-2 minutes)
- Resource requests not defined on pods

**Solutions**:
```bash
# Check Metrics Server
kubectl get deployment metrics-server -n kube-system
kubectl logs -n kube-system deployment/metrics-server

# Verify pod metrics are available
kubectl top pods -n <namespace>
```

### Issue: ScaledObjects Not Scaling

**Diagnosis**:
```bash
kubectl describe scaledobject <name> -n <namespace>
kubectl logs -n keda deployment/keda-operator
```

**Solutions**:
1. Verify KEDA is installed:
   ```bash
   kubectl get pods -n keda
   ```

2. Check ScaledObject status:
   ```bash
   kubectl get scaledobject <name> -n <namespace> -o yaml
   ```

3. Review KEDA logs for errors:
   ```bash
   kubectl logs -n keda -l app=keda-operator --tail=100
   ```

### Issue: Rollouts Not Deploying

**Diagnosis**:
```bash
kubectl describe rollout <name> -n <namespace>
kubectl logs -n argo-rollouts deployment/argo-rollouts
```

**Solutions**:
1. Verify Argo Rollouts is installed:
   ```bash
   kubectl get pods -n argo-rollouts
   ```

2. Check Rollout status:
   ```bash
   kubectl get rollout <name> -n <namespace> -o yaml
   ```

### Issue: ArgoCD Can't Access Git Repository

**Diagnosis**:
```bash
argocd app get <app-name>
kubectl logs -n argocd deployment/argocd-repo-server
```

**Solutions**:
1. Verify repository URL is correct in Application manifests
2. Check if repository requires authentication:
   ```bash
   argocd repo list
   ```

3. Add repository credentials if needed:
   ```bash
   argocd repo add <repo-url> --username <username> --password <password>
   ```

## Next Steps

After successful deployment:

1. **Implement Auto-Rightsizing Logic**: Build your controller that monitors metrics and updates HPA/ScaledObject resources
2. **Test at Scale**: Generate load on the applications to trigger scaling
3. **Monitor Sync Status**: Ensure ArgoCD doesn't detect drift as your controller makes changes
4. **Refine Thresholds**: Adjust the ignoreDifferences configuration if needed
5. **Add Monitoring**: Set up Prometheus/Grafana to track HPA/ScaledObject changes

## Cleanup

To remove all test resources:

```bash
# Delete ArgoCD Applications
kubectl delete -f argocd/applications/

# Wait for resources to be cleaned up (may take a minute)
sleep 30

# Verify namespaces are deleted
kubectl get namespaces | grep -E 'deployment|rollout'

# Optional: Remove ArgoCD ConfigMap customizations
kubectl patch configmap argocd-cm -n argocd --type json -p='[{"op": "remove", "path": "/data/resource.customizations.ignoreDifferences.all"}]'
```

## Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [KEDA Documentation](https://keda.sh/)
- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [Kubernetes HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [ArgoCD Resource Customizations](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/)

