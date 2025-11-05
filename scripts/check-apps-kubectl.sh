#!/bin/bash
# Check ArgoCD applications using kubectl instead of argocd CLI

echo "=========================================="
echo "ArgoCD Applications Status (via kubectl)"
echo "=========================================="
echo ""

# Check if applications exist
echo "Applications in ArgoCD:"
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || {
  echo "No applications found or ArgoCD CRDs not installed"
  exit 1
}

echo ""
echo "=========================================="
echo "Detailed Status for Each Application"
echo "=========================================="
echo ""

for app in deployment-hpa rollout-hpa deployment-scaledobject rollout-scaledobject \
           deployment-hpa-container-thresholds rollout-hpa-container-thresholds \
           deployment-scaledobject-container-thresholds rollout-scaledobject-container-thresholds; do
  
  echo "--- $app ---"
  
  # Check if app exists
  if kubectl get application $app -n argocd &>/dev/null; then
    SYNC_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    REPO=$(kubectl get application $app -n argocd -o jsonpath='{.spec.source.repoURL}' 2>/dev/null || echo "Unknown")
    PATH=$(kubectl get application $app -n argocd -o jsonpath='{.spec.source.path}' 2>/dev/null || echo "Unknown")
    
    echo "  Sync Status:   $SYNC_STATUS"
    echo "  Health Status: $HEALTH_STATUS"
    echo "  Repository:    $REPO"
    echo "  Path:          $PATH"
    
    # Show sync message if out of sync
    if [ "$SYNC_STATUS" = "OutOfSync" ]; then
      echo "  ⚠️  Application is out of sync!"
      MESSAGE=$(kubectl get application $app -n argocd -o jsonpath='{.status.sync.message}' 2>/dev/null)
      if [ ! -z "$MESSAGE" ]; then
        echo "  Message: $MESSAGE"
      fi
    elif [ "$SYNC_STATUS" = "Synced" ]; then
      echo "  ✅ Application is synced"
    fi
  else
    echo "  ❌ Application not found"
  fi
  echo ""
done

echo "=========================================="
echo "ArgoCD ConfigMap Status"
echo "=========================================="
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 10 "ignoreDifferences" || echo "No ignoreDifferences configured"

