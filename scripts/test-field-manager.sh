#!/bin/bash
set -e

# Test script for custom field manager with ArgoCD ignoreDifferences
# This simulates what your auto-rightsizing controller will do

FIELD_MANAGER="komodor-rightsizing-controller"
NAMESPACE="deployment-hpa"
HPA_NAME="test-app-hpa"

echo "=========================================="
echo "Testing Custom Field Manager: $FIELD_MANAGER"
echo "=========================================="
echo ""

# Check current ArgoCD sync status
echo "1. Checking initial ArgoCD sync status..."
if argocd app get deployment-hpa &>/dev/null; then
  argocd app get deployment-hpa --show-params | grep "Sync Status"
else
  echo "   Using kubectl (argocd CLI not available/logged in):"
  SYNC_STATUS=$(kubectl get application deployment-hpa -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "App not found")
  HEALTH_STATUS=$(kubectl get application deployment-hpa -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  echo "   Sync Status: $SYNC_STATUS"
  echo "   Health Status: $HEALTH_STATUS"
fi
echo ""

# Show current HPA configuration
echo "2. Current HPA configuration:"
kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}' && echo ""
kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.spec.minReplicas}' | xargs -I {} echo "minReplicas: {}"
kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.spec.maxReplicas}' | xargs -I {} echo "maxReplicas: {}"
echo ""

# Show current managed fields managers
echo "3. Current field managers on this HPA:"
kubectl get hpa $HPA_NAME -n $NAMESPACE -o json | jq -r '.metadata.managedFields[].manager' | sort -u
echo ""

# Apply change using custom field manager - CPU utilization
echo "4. Applying change with field manager: $FIELD_MANAGER"
echo "   Changing CPU target utilization to 65%..."
kubectl patch hpa $HPA_NAME -n $NAMESPACE \
  --type=json \
  --patch '[{"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":65}]' \
  --field-manager=$FIELD_MANAGER
echo "   ✓ Change applied"
echo ""

# Wait a moment for ArgoCD to process
echo "5. Waiting 5 seconds for ArgoCD to process changes..."
sleep 5
echo ""

# Show updated managed fields
echo "6. Updated field managers (should now include $FIELD_MANAGER):"
kubectl get hpa $HPA_NAME -n $NAMESPACE -o json | jq -r '.metadata.managedFields[].manager' | sort -u
echo ""

# Check which fields the custom manager modified
echo "7. Fields modified by $FIELD_MANAGER:"
kubectl get hpa $HPA_NAME -n $NAMESPACE -o json | \
  jq ".metadata.managedFields[] | select(.manager==\"$FIELD_MANAGER\") | .fieldsV1"
echo ""

# Check ArgoCD sync status after change
echo "8. Checking ArgoCD sync status after modification..."

# Try argocd CLI first, fall back to kubectl
if argocd app get deployment-hpa &>/dev/null; then
  SYNC_STATUS=$(argocd app get deployment-hpa -o json 2>/dev/null | jq -r '.status.sync.status' || echo "UNKNOWN")
  USE_CLI=true
else
  SYNC_STATUS=$(kubectl get application deployment-hpa -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "UNKNOWN")
  USE_CLI=false
fi

echo "   Sync Status: $SYNC_STATUS"

if [ "$SYNC_STATUS" = "Synced" ]; then
  echo "   ✅ SUCCESS! ArgoCD still shows Synced (no drift detected)"
elif [ "$SYNC_STATUS" = "OutOfSync" ]; then
  echo "   ❌ FAILED! ArgoCD detected drift"
  echo ""
  echo "   Troubleshooting:"
  echo "   1. Ensure the ConfigMap has $FIELD_MANAGER in managedFieldsManagers"
  echo "   2. Restart ArgoCD controllers:"
  echo "      kubectl rollout restart deployment argocd-application-controller -n argocd"
  echo "   3. Check ArgoCD diff:"
  if [ "$USE_CLI" = "true" ]; then
    echo "      argocd app diff deployment-hpa"
  else
    echo "      kubectl get application deployment-hpa -n argocd -o yaml"
  fi
else
  echo "   ⚠️  Could not determine sync status"
fi
echo ""

# Show the actual diff if out of sync
if [ "$SYNC_STATUS" = "OutOfSync" ]; then
  echo "9. Showing diff detected by ArgoCD:"
  if [ "$USE_CLI" = "true" ]; then
    argocd app diff deployment-hpa 2>/dev/null || echo "   (Could not get diff)"
  else
    echo "   Using kubectl:"
    kubectl get application deployment-hpa -n argocd -o jsonpath='{.status.operationState.syncResult.resources}' | jq '.' 2>/dev/null || echo "   (No diff details available via kubectl)"
  fi
fi

echo ""
echo "=========================================="
echo "Test complete!"
echo "=========================================="
echo ""
echo "To revert the change:"
echo "  kubectl patch hpa $HPA_NAME -n $NAMESPACE --type=json \\"
echo "    --patch '[{\"op\":\"replace\",\"path\":\"/spec/metrics/0/resource/target/averageUtilization\",\"value\":70}]' \\"
echo "    --field-manager=$FIELD_MANAGER"

