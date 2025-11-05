# Managed Fields Guide for ArgoCD ignoreDifferences

## What are Managed Fields?

Kubernetes tracks which controllers/tools modify each field of a resource using the **Server-Side Apply** mechanism. Each modification is tracked with:
- **manager**: The name of the controller/tool making the change
- **operation**: How the change was made (Apply, Update)
- **fieldsV1**: Which fields were modified

## Why Use managedFieldsManagers?

Instead of specifying individual JSON paths to ignore, you can tell ArgoCD to ignore **all changes** made by specific field managers. This is more powerful because:

1. **Comprehensive**: Ignores everything a controller touches, not just specific paths
2. **Future-proof**: Works even if the controller starts modifying new fields
3. **Simpler**: Don't need to enumerate all possible JSON paths

## How to Discover Field Managers

### Option 1: View managedFields Directly

```bash
# Check an HPA
kubectl get hpa test-app-hpa -n deployment-hpa -o yaml

# Look for the managedFields section:
# metadata:
#   managedFields:
#   - manager: kubectl-client-side-apply
#     operation: Update
#     apiVersion: autoscaling/v2
#     time: "2024-01-15T10:00:00Z"
#     fieldsType: FieldsV1
#     fieldsV1: ...
#   - manager: kube-controller-manager
#     operation: Update
#     ...
```

### Option 2: Extract Just Manager Names

```bash
# HPA managers
kubectl get hpa test-app-hpa -n deployment-hpa -o json | \
  jq '.metadata.managedFields[].manager' -r | sort -u

# ScaledObject managers
kubectl get scaledobject test-app-scaledobject -n deployment-scaledobject -o json | \
  jq '.metadata.managedFields[].manager' -r | sort -u

# Check all HPAs across all namespaces
kubectl get hpa --all-namespaces -o json | \
  jq '.items[].metadata.managedFields[].manager' -r | sort -u
```

### Option 3: Check Which Fields a Manager Modified

```bash
# See what fields kube-controller-manager modifies on an HPA
kubectl get hpa test-app-hpa -n deployment-hpa -o json | \
  jq '.metadata.managedFields[] | select(.manager=="kube-controller-manager")'
```

## Common Field Managers

Here are field managers you'll commonly see:

| Manager | Description | Typical Resources |
|---------|-------------|-------------------|
| `kubectl` | Manual kubectl edit/patch commands | Any resource |
| `kubectl-client-side-apply` | kubectl apply (legacy) | Any resource |
| `kubectl-create` | kubectl create commands | Any resource |
| `argocd-controller` | ArgoCD syncing resources | Managed by ArgoCD |
| `kube-controller-manager` | HPA controller | HorizontalPodAutoscaler |
| `keda-operator` | KEDA operator | ScaledObject |
| `argo-rollouts` | Argo Rollouts controller | Rollout |
| Custom controller name | Your auto-rightsizing controller | HPA, ScaledObject, etc. |

## Configuration Strategies

### Strategy 1: Global ignoreDifferences.all (Current)

Ignore changes from specific managers across **all resources**:

```yaml
resource.customizations.ignoreDifferences.all: |
  managedFieldsManagers:
  - kube-controller-manager
  - keda-operator
  - kubectl-client-side-apply
  - kubectl
  # Your controller name
  - your-rightsizing-controller
```

**Pros**: 
- Simple, applies everywhere
- Good for controllers that touch multiple resource types

**Cons**: 
- Very broad - ignores these managers on ALL resources, not just HPA/ScaledObject
- Might hide drift you actually want to see

### Strategy 2: Resource-Specific with managedFieldsManagers

Ignore specific managers only for specific resource types:

```yaml
resource.customizations.ignoreDifferences.autoscaling_HorizontalPodAutoscaler: |
  managedFieldsManagers:
  - kube-controller-manager
  - kubectl
  - kubectl-client-side-apply
  - your-rightsizing-controller

resource.customizations.ignoreDifferences.keda.sh_ScaledObject: |
  managedFieldsManagers:
  - keda-operator
  - kubectl
  - kubectl-client-side-apply
  - your-rightsizing-controller
```

**Pros**: 
- More targeted - only affects specific resource types
- Better control over what gets ignored

**Cons**: 
- More verbose configuration

### Strategy 3: Hybrid Approach (Recommended)

Combine `managedFieldsManagers` and `jsonPointers` for fine-grained control:

```yaml
resource.customizations.ignoreDifferences.autoscaling_HorizontalPodAutoscaler: |
  # Ignore specific fields
  jsonPointers:
  - /spec/metrics
  - /spec/minReplicas
  - /spec/maxReplicas
  
  # AND ignore changes from specific managers
  managedFieldsManagers:
  - kube-controller-manager
  - your-rightsizing-controller
```

**Pros**: 
- Maximum control
- Can ignore specific fields from Git AND runtime changes from controllers

**Cons**: 
- Most complex configuration

## How to Control managedFields in Your Controller

When you build your auto-rightsizing controller, you can control the field manager name:

### Option 1: Using kubectl apply

```bash
# Default manager name is "kubectl-client-side-apply"
kubectl apply -f resource.yaml

# Custom field manager name
kubectl apply -f resource.yaml --field-manager=my-rightsizing-controller
```

### Option 2: Using kubectl patch

```bash
# Specify field manager in patch operations
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=json \
  --patch '[{"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":75}]'
```

The field manager will be the client name (e.g., `kubectl`).

### Option 3: Using Client-Go (Recommended for Controllers)

```go
import (
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
)

// Use Server-Side Apply with custom field manager
options := metav1.ApplyOptions{
    FieldManager: "my-rightsizing-controller",
    Force:        true,
}

result, err := clientset.AutoscalingV2().HorizontalPodAutoscalers(namespace).
    Apply(ctx, hpaApplyConfig, options)
```

### Option 4: Using kubectl with Custom User Agent

```bash
# Set a custom field manager via server-side apply
kubectl apply --server-side --field-manager=rightsizing-controller -f resource.yaml
```

## Testing Your Configuration

### Step 1: Deploy Resources
```bash
kubectl apply -f argocd/applications/
```

### Step 2: Wait for Sync
```bash
argocd app list
```

### Step 3: Make a Change as Your Controller Would
```bash
# Simulate your controller making a change
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=json \
  --patch '[{"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":75}]'
```

### Step 4: Check managedFields
```bash
kubectl get hpa test-app-hpa -n deployment-hpa -o json | \
  jq '.metadata.managedFields[] | {manager: .manager, operation: .operation}'
```

### Step 5: Verify ArgoCD Doesn't Detect Drift
```bash
argocd app get deployment-hpa
# Should show: "Sync Status: Synced"
```

### Step 6: Test with Custom Field Manager
```bash
# Apply a change with your controller's name
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=json \
  --patch '[{"op":"replace","path":"/spec/minReplicas","value":3}]'

# Check if ArgoCD still shows Synced
argocd app get deployment-hpa
```

## Debugging Tips

### See Exactly What's Different

```bash
# Show the diff ArgoCD sees
argocd app diff deployment-hpa

# Show detailed diff with managed fields
kubectl get hpa test-app-hpa -n deployment-hpa -o yaml > /tmp/live.yaml
# Compare with Git version
```

### Check ArgoCD's View

```bash
# Get the app manifest as ArgoCD sees it
argocd app manifests deployment-hpa

# Get detailed app info
argocd app get deployment-hpa -o yaml
```

### View ArgoCD Controller Logs

```bash
# See what ArgoCD is processing
kubectl logs -n argocd deployment/argocd-application-controller -f | grep -i "ignore\|diff"
```

## Recommended Configuration for Auto-Rightsizing

Based on your use case, here's the recommended configuration:

```yaml
# Global: Ignore kubectl changes (for manual testing)
resource.customizations.ignoreDifferences.all: |
  managedFieldsManagers:
  - kubectl
  - kubectl-client-side-apply

# HPA-specific: Ignore HPA controller and your rightsizing controller
resource.customizations.ignoreDifferences.autoscaling_HorizontalPodAutoscaler: |
  jsonPointers:
  - /spec/metrics
  - /spec/minReplicas
  - /spec/maxReplicas
  - /spec/behavior
  
  managedFieldsManagers:
  - kube-controller-manager
  - your-rightsizing-controller-name

# ScaledObject-specific: Ignore KEDA and your controller
resource.customizations.ignoreDifferences.keda.sh_ScaledObject: |
  jsonPointers:
  - /spec/triggers
  - /spec/minReplicaCount
  - /spec/maxReplicaCount
  
  managedFieldsManagers:
  - keda-operator
  - your-rightsizing-controller-name
```

## Next Steps

1. **Deploy with current config** and test with `kubectl` changes
2. **Check managedFields** on your live resources
3. **Build your controller** with a custom field manager name
4. **Update the ConfigMap** to include your controller's manager name
5. **Test end-to-end** that your controller's changes don't cause drift

## References

- [Kubernetes Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/)
- [ArgoCD Resource Customizations](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/)
- [ArgoCD ignoreDifferences](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/#application-level-configuration)

