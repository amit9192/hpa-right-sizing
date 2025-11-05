# Quick Start Guide

## Repository Setup Complete! ✓

Your test environment is ready. Here's what to do next:

## Step 1: Push Your Changes to GitHub

```bash
cd /Users/amitbaroz/Documents/Customers/Affirm
git add .
git commit -m "Configure ArgoCD applications with repository URL"
git push origin main
```

## Step 2: Configure ArgoCD to Ignore HPA/ScaledObject Changes

**This is the critical step that prevents sync drift!**

Apply the ConfigMap that tells ArgoCD to ignore changes to HPA and ScaledObject resources:

```bash
kubectl apply -f argocd/configmap-ignoredifferences.yaml
```

Then restart the ArgoCD controllers:

```bash
kubectl rollout restart deployment argocd-application-controller -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd
```

Wait for the restart to complete:

```bash
kubectl rollout status deployment argocd-application-controller -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd
```

## Step 3: Deploy All Test Applications

```bash
kubectl apply -f argocd/applications/
```

## Step 4: Monitor Deployment

Watch the applications sync:

```bash
# List all applications
argocd app list

# Watch for changes
watch argocd app list

# Or check individually
argocd app get deployment-hpa
```

## Step 5: Verify Everything is Running

```bash
# Check all namespaces
kubectl get namespaces | grep -E 'deployment|rollout'

# Check pods across all test namespaces
for ns in deployment-hpa rollout-hpa deployment-scaledobject rollout-scaledobject \
          deployment-hpa-container-thresholds rollout-hpa-container-thresholds \
          deployment-scaledobject-container-thresholds rollout-scaledobject-container-thresholds; do
  echo "=== $ns ==="
  kubectl get pods -n $ns
done

# Check HPAs
kubectl get hpa --all-namespaces | grep test-app

# Check ScaledObjects
kubectl get scaledobject --all-namespaces
```

## Step 6: Test Auto-Rightsizing (Verify No Sync Drift)

Test that changes to HPA don't cause ArgoCD sync drift:

```bash
# Modify an HPA
kubectl patch hpa test-app-hpa -n deployment-hpa \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/metrics/0/resource/target/averageUtilization", "value": 75}]'

# Check ArgoCD status - should still show "Synced"
argocd app get deployment-hpa
```

Expected result: Application remains `Synced` ✓

Test ScaledObject changes:

```bash
# Modify a ScaledObject
kubectl patch scaledobject test-app-scaledobject -n deployment-scaledobject \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/triggers/0/metadata/value", "value": "75"}]'

# Check ArgoCD status - should still show "Synced"
argocd app get deployment-scaledobject
```

Expected result: Application remains `Synced` ✓

## What You've Built

This repository contains **8 test scenarios** for auto-rightsizing:

### Basic Scenarios:
1. **deployment-hpa** - Deployment with HPA
2. **rollout-hpa** - Argo Rollout with HPA
3. **deployment-scaledobject** - Deployment with KEDA ScaledObject
4. **rollout-scaledobject** - Rollout with KEDA ScaledObject

### Container-Specific Threshold Scenarios:
5. **deployment-hpa-container-thresholds** - Multi-container Deployment with per-container HPA metrics
6. **rollout-hpa-container-thresholds** - Multi-container Rollout with per-container HPA metrics
7. **deployment-scaledobject-container-thresholds** - Multi-container Deployment with ScaledObject annotations
8. **rollout-scaledobject-container-thresholds** - Multi-container Rollout with ScaledObject annotations

## Key Configuration

The `argocd/configmap-ignoredifferences.yaml` file configures ArgoCD to ignore changes in:

- HPA: `/spec/metrics`, `/spec/minReplicas`, `/spec/maxReplicas`, `/spec/behavior`
- ScaledObject: `/spec/triggers`, `/spec/minReplicaCount`, `/spec/maxReplicaCount`

This allows your auto-rightsizing controller to modify these fields without causing ArgoCD to detect drift.

## Prerequisites Checklist

Before deploying, ensure you have:

- [ ] Kubernetes cluster (1.20+)
- [ ] ArgoCD installed and running
- [ ] Metrics Server installed (for HPA)
- [ ] KEDA installed (for ScaledObject tests)
- [ ] Argo Rollouts installed (for Rollout tests)
- [ ] `kubectl` configured to access your cluster
- [ ] `argocd` CLI installed

## Need More Details?

See the full documentation:
- `README.md` - Complete project overview
- `docs/setup-instructions.md` - Detailed setup guide with troubleshooting

## Repository Structure

```
.
├── README.md                    # Project overview
├── QUICKSTART.md               # This file
├── manifests/                  # Kubernetes manifests for all test scenarios
│   ├── 01-deployment-hpa/
│   ├── 02-rollout-hpa/
│   ├── 03-deployment-scaledobject/
│   ├── 04-rollout-scaledobject/
│   ├── 05-deployment-hpa-container-thresholds/
│   ├── 06-rollout-hpa-container-thresholds/
│   ├── 07-deployment-scaledobject-container-thresholds/
│   └── 08-rollout-scaledobject-container-thresholds/
├── argocd/
│   ├── applications/           # ArgoCD Application manifests (all configured with your repo URL)
│   └── configmap-ignoredifferences.yaml  # Critical: prevents sync drift
└── docs/
    └── setup-instructions.md   # Detailed setup guide

```

## Troubleshooting

If applications show "OutOfSync":
1. Verify ConfigMap was applied: `kubectl get configmap argocd-cm -n argocd -o yaml | grep ignoreDifferences`
2. Restart ArgoCD controllers (see Step 2)
3. Check ArgoCD logs: `kubectl logs -n argocd deployment/argocd-application-controller`

If HPAs show "unknown" metrics:
1. Wait 1-2 minutes for metrics to populate
2. Verify Metrics Server: `kubectl get deployment metrics-server -n kube-system`
3. Check pod metrics: `kubectl top pods -n <namespace>`

## Next Steps

Once everything is deployed and verified:

1. Build your auto-rightsizing controller to watch metrics and update HPA/ScaledObject resources
2. Test with load generation to trigger actual scaling
3. Monitor that ArgoCD stays in sync as your controller makes changes
4. Iterate on the ignored fields configuration if needed

Happy testing! 🚀

