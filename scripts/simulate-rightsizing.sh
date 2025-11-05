#!/bin/bash
set -e

# Simulate auto-rightsizing changes using custom field manager
# This script demonstrates how your controller would modify HPA and ScaledObject resources

FIELD_MANAGER="komodor-rightsizing-controller"

echo "=========================================="
echo "Simulating Auto-Rightsizing Controller"
echo "Field Manager: $FIELD_MANAGER"
echo "=========================================="
echo ""

# Function to patch and report
patch_resource() {
  local resource_type=$1
  local resource_name=$2
  local namespace=$3
  local patch=$4
  local description=$5
  
  echo "📝 $description"
  echo "   Resource: $resource_type/$resource_name in $namespace"
  
  kubectl patch $resource_type $resource_name -n $namespace \
    --type=json \
    --patch "$patch" \
    --field-manager=$FIELD_MANAGER
  
  echo "   ✅ Applied"
  echo ""
}

# Test 1: Basic Deployment + HPA
echo "Test 1: Deployment + HPA"
echo "------------------------"
patch_resource "hpa" "test-app-hpa" "deployment-hpa" \
  '[{"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":65}]' \
  "Adjusting CPU threshold from 70% to 65%"

patch_resource "hpa" "test-app-hpa" "deployment-hpa" \
  '[{"op":"replace","path":"/spec/maxReplicas","value":12}]' \
  "Adjusting max replicas from 10 to 12"

# Test 2: Rollout + HPA
echo "Test 2: Rollout + HPA"
echo "---------------------"
patch_resource "hpa" "test-app-hpa" "rollout-hpa" \
  '[{"op":"replace","path":"/spec/metrics/0/resource/target/averageUtilization","value":68}]' \
  "Adjusting CPU threshold to 68%"

# Test 3: Deployment + ScaledObject
echo "Test 3: Deployment + ScaledObject"
echo "----------------------------------"
patch_resource "scaledobject" "test-app-scaledobject" "deployment-scaledobject" \
  '[{"op":"replace","path":"/spec/triggers/0/metadata/value","value":"65"}]' \
  "Adjusting CPU trigger from 70 to 65"

patch_resource "scaledobject" "test-app-scaledobject" "deployment-scaledobject" \
  '[{"op":"replace","path":"/spec/maxReplicaCount","value":12}]' \
  "Adjusting max replicas to 12"

# Test 4: Container-specific thresholds
echo "Test 4: Container-Specific HPA Thresholds"
echo "------------------------------------------"
patch_resource "hpa" "test-app-hpa" "deployment-hpa-container-thresholds" \
  '[{"op":"replace","path":"/spec/metrics/0/containerResource/target/averageUtilization","value":65}]' \
  "Adjusting nginx container CPU threshold to 65%"

patch_resource "hpa" "test-app-hpa" "deployment-hpa-container-thresholds" \
  '[{"op":"replace","path":"/spec/metrics/2/containerResource/target/averageUtilization","value":55}]' \
  "Adjusting sidecar container CPU threshold to 55%"

echo "=========================================="
echo "All changes applied successfully!"
echo "=========================================="
echo ""

# Check ArgoCD sync status for all apps using kubectl
echo "Checking ArgoCD Application sync status (via kubectl)..."
echo ""

for app in deployment-hpa; do  # Add more apps as you deploy them: rollout-hpa deployment-scaledobject deployment-hpa-container-thresholds
  # Get sync and health status
  SYNC_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NOT_FOUND")
  HEALTH_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  
  if [ "$SYNC_STATUS" = "NOT_FOUND" ]; then
    echo "⚠️  $app: Application not found (not deployed yet?)"
  elif [ "$SYNC_STATUS" = "Synced" ]; then
    echo "✅ $app: $SYNC_STATUS (Health: $HEALTH_STATUS)"
  elif [ "$SYNC_STATUS" = "OutOfSync" ]; then
    echo "❌ $app: $SYNC_STATUS (Health: $HEALTH_STATUS) - DRIFT DETECTED!"
  else
    echo "⚠️  $app: $SYNC_STATUS (Health: $HEALTH_STATUS)"
  fi
done

echo ""
echo "To verify field managers, run:"
echo "  kubectl get hpa test-app-hpa -n deployment-hpa -o json | jq -r '.metadata.managedFields[].manager' | sort -u"
echo ""
echo "To check which fields were modified by $FIELD_MANAGER:"
echo "  kubectl get hpa test-app-hpa -n deployment-hpa -o json | jq '.metadata.managedFields[] | select(.manager==\"$FIELD_MANAGER\")'"

