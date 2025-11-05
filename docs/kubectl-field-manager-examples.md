# kubectl Field Manager Examples

This guide shows you how to set a custom field manager name when using kubectl commands. This is useful for testing and simulating your auto-rightsizing controller's behavior.

## Why Set a Custom Field Manager?

When you set a custom field manager name:
1. **Kubernetes tracks** who made each change to a resource
2. **ArgoCD can ignore** changes from specific field managers
3. **You can test** your controller's behavior before building it
4. **Debugging** becomes easier - you can see exactly what your controller modified

## Field Manager with kubectl Commands

### 1. Server-Side Apply (Recommended)

```bash
# Apply a file with custom field manager
kubectl apply --server-side \
  --field-manager=affirm-rightsizing-controller \
  -f manifests/01-deployment-hpa/hpa.yaml

# Force overwrite conflicts
kubectl apply --server-side \
  --field-manager=affirm-rightsizing-controller \
  --force-conflicts \
  -f manifests/01-deployment-hpa/hpa.yaml
```

### 2. JSON Patch with Field Manager

```bash
# Change CPU utilization target
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=json \
  --patch '[{"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":65}]' \
  --field-manager=affirm-rightsizing-controller

# Change multiple values
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=json \
  --patch '[
    {"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":65},
    {"op":"replace","path":"/spec/minReplicas","value":3},
    {"op":"replace","path":"/spec/maxReplicas","value":15}
  ]' \
  --field-manager=affirm-rightsizing-controller
```

### 3. Strategic Merge Patch with Field Manager

```bash
# Update max replicas
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=strategic \
  --patch '{"spec":{"maxReplicas":15}}' \
  --field-manager=affirm-rightsizing-controller

# Update multiple fields
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=strategic \
  --patch '{
    "spec": {
      "minReplicas": 3,
      "maxReplicas": 15,
      "metrics": [{
        "type": "Resource",
        "resource": {
          "name": "cpu",
          "target": {
            "type": "Utilization",
            "averageUtilization": 65
          }
        }
      }]
    }
  }' \
  --field-manager=affirm-rightsizing-controller
```

### 4. Merge Patch with Field Manager

```bash
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=merge \
  --patch '{"spec":{"maxReplicas":15}}' \
  --field-manager=affirm-rightsizing-controller
```

### 5. ScaledObject Examples

```bash
# Update ScaledObject CPU trigger
kubectl patch scaledobject test-app-scaledobject -n deployment-scaledobject \
  --type=json \
  --patch '[{"op":"replace","path":"/spec/triggers/0/metadata/value","value":"65"}]' \
  --field-manager=affirm-rightsizing-controller

# Update min/max replicas
kubectl patch scaledobject test-app-scaledobject -n deployment-scaledobject \
  --type=json \
  --patch '[
    {"op":"replace","path":"/spec/minReplicaCount","value":3},
    {"op":"replace","path":"/spec/maxReplicaCount","value":15}
  ]' \
  --field-manager=affirm-rightsizing-controller
```

### 6. Container-Specific HPA Thresholds

```bash
# Update CPU threshold for specific container
kubectl patch hpa test-app-hpa -n deployment-hpa-container-thresholds \
  --type=json \
  --patch '[{
    "op":"replace",
    "path":"/spec/metrics/0/containerResource/target/averageUtilization",
    "value":65
  }]' \
  --field-manager=affirm-rightsizing-controller

# Update memory threshold for sidecar container
kubectl patch hpa test-app-hpa -n deployment-hpa-container-thresholds \
  --type=json \
  --patch '[{
    "op":"replace",
    "path":"/spec/metrics/3/containerResource/target/averageUtilization",
    "value":70
  }]' \
  --field-manager=affirm-rightsizing-controller
```

## Verifying Field Manager Changes

### Check Field Managers on a Resource

```bash
# List all field managers
kubectl get hpa test-app-hpa -n deployment-hpa -o json | \
  jq -r '.metadata.managedFields[].manager' | sort -u

# Output example:
# affirm-rightsizing-controller
# argocd-controller
# kube-controller-manager
# kubectl-client-side-apply
```

### See What Fields a Manager Modified

```bash
# View all fields managed by your controller
kubectl get hpa test-app-hpa -n deployment-hpa -o json | \
  jq '.metadata.managedFields[] | select(.manager=="affirm-rightsizing-controller")'

# See just the fields (compact view)
kubectl get hpa test-app-hpa -n deployment-hpa -o json | \
  jq '.metadata.managedFields[] | select(.manager=="affirm-rightsizing-controller") | .fieldsV1'
```

### Compare Field Managers Across Resources

```bash
# Check all HPAs
kubectl get hpa --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): \(.metadata.managedFields[].manager)"' | \
  sort

# Filter for your controller only
kubectl get hpa --all-namespaces -o json | \
  jq -r '.items[] | select(.metadata.managedFields[].manager == "affirm-rightsizing-controller") | "\(.metadata.namespace)/\(.metadata.name)"'
```

## Testing Workflow

### Complete Test Workflow

```bash
# 1. Check initial state
argocd app get deployment-hpa
kubectl get hpa test-app-hpa -n deployment-hpa -o yaml

# 2. Make a change with your field manager
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=json \
  --patch '[{"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":65}]' \
  --field-manager=affirm-rightsizing-controller

# 3. Verify the field manager is recorded
kubectl get hpa test-app-hpa -n deployment-hpa -o json | \
  jq -r '.metadata.managedFields[].manager' | grep affirm

# 4. Wait for ArgoCD to process
sleep 5

# 5. Check ArgoCD sync status (should still be Synced)
argocd app get deployment-hpa | grep "Sync Status"

# 6. If OutOfSync, check the diff
argocd app diff deployment-hpa
```

## Using Test Scripts

We've created helper scripts to make testing easier:

### Run Single Test

```bash
# Test with custom field manager and check ArgoCD status
./scripts/test-field-manager.sh
```

### Simulate Full Auto-Rightsizing

```bash
# Apply changes to all test scenarios
./scripts/simulate-rightsizing.sh
```

## Common Patterns for Your Controller

### Pattern 1: Read-Modify-Write

```bash
# 1. Get current value
CURRENT_CPU=$(kubectl get hpa test-app-hpa -n deployment-hpa \
  -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}')

# 2. Calculate new value (example: reduce by 5%)
NEW_CPU=$((CURRENT_CPU - 5))

# 3. Apply with your field manager
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type=json \
  --patch "[{\"op\":\"replace\",\"path\":\"/spec/metrics/0/resource/target/averageUtilization\",\"value\":$NEW_CPU}]" \
  --field-manager=affirm-rightsizing-controller
```

### Pattern 2: Conditional Update

```bash
# Only update if above threshold
CURRENT_CPU=$(kubectl get hpa test-app-hpa -n deployment-hpa \
  -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}')

if [ $CURRENT_CPU -gt 70 ]; then
  echo "CPU threshold too high, adjusting..."
  kubectl patch hpa test-app-hpa -n deployment-hpa \
    --type=json \
    --patch '[{"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":65}]' \
    --field-manager=affirm-rightsizing-controller
fi
```

### Pattern 3: Batch Updates

```bash
# Update multiple HPAs
for ns in deployment-hpa rollout-hpa deployment-hpa-container-thresholds; do
  echo "Updating HPA in $ns..."
  kubectl patch hpa test-app-hpa -n $ns \
    --type=json \
    --patch '[{"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":65}]' \
    --field-manager=affirm-rightsizing-controller
done
```

## Cleanup Field Manager Ownership

If you need to remove field manager ownership (careful - this can cause conflicts):

```bash
# Re-apply as a different manager to take ownership
kubectl apply --server-side \
  --field-manager=kubectl \
  --force-conflicts \
  -f manifests/01-deployment-hpa/hpa.yaml

# Or delete and recreate the resource
kubectl delete hpa test-app-hpa -n deployment-hpa
kubectl apply -f manifests/01-deployment-hpa/hpa.yaml
```

## Troubleshooting

### Issue: Field Manager Not Showing

**Check:**
```bash
kubectl get hpa test-app-hpa -n deployment-hpa -o json | \
  jq '.metadata.managedFields[] | {manager: .manager, time: .time, operation: .operation}'
```

**Solution:** Ensure you're using `--field-manager` flag in your kubectl command.

### Issue: Conflict on Field Ownership

**Error:** `Apply failed with 1 conflict`

**Solution:** Use `--force-conflicts`:
```bash
kubectl apply --server-side \
  --field-manager=affirm-rightsizing-controller \
  --force-conflicts \
  -f resource.yaml
```

### Issue: ArgoCD Still Detects Drift

**Check:**
1. Verify field manager is in ArgoCD ConfigMap:
```bash
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 5 managedFieldsManagers
```

2. Restart ArgoCD controllers:
```bash
kubectl rollout restart deployment argocd-application-controller -n argocd
```

3. Check the actual diff:
```bash
argocd app diff deployment-hpa
```

## Next Steps

1. **Test with kubectl**: Use the examples above to simulate your controller
2. **Verify ArgoCD behavior**: Ensure sync status remains "Synced"
3. **Build your controller**: Use the same field manager name in your code
4. **Deploy and monitor**: Watch for any drift detection issues

## Reference

- Field manager flag: `--field-manager=<name>`
- Works with: `kubectl apply`, `kubectl patch`, `kubectl create`, `kubectl replace`
- Best practice: Use a consistent, descriptive name (e.g., `affirm-rightsizing-controller`)

