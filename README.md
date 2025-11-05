# Auto-Rightsizing Test Repository for ArgoCD

This repository contains test scenarios for validating auto-rightsizing functionality with workloads managed by HPA (Horizontal Pod Autoscaler) and ScaledObject (KEDA) when deployed via ArgoCD.

## Overview

The purpose of this test environment is to ensure that auto-rightsizing changes to HPA and ScaledObject resources are not tracked by ArgoCD, preventing sync drift issues.

## Test Scenarios

This repository includes the following test scenarios:

### 1. Basic Scenarios
- **deployment-hpa**: Standard Deployment managed by an HPA
- **rollout-hpa**: Argo Rollout managed by an HPA
- **deployment-scaledobject**: Standard Deployment managed by a ScaledObject (KEDA)
- **rollout-scaledobject**: Argo Rollout managed by a ScaledObject (KEDA)

### 2. Container-Specific Threshold Scenarios
- **deployment-hpa-container-thresholds**: Deployment with HPA using container-specific CPU/memory thresholds
- **rollout-hpa-container-thresholds**: Rollout with HPA using container-specific CPU/memory thresholds
- **deployment-scaledobject-container-thresholds**: Deployment with ScaledObject using container-specific thresholds
- **rollout-scaledobject-container-thresholds**: Rollout with ScaledObject using container-specific thresholds

## Directory Structure

```
.
├── README.md
├── manifests/
│   ├── 01-deployment-hpa/
│   ├── 02-rollout-hpa/
│   ├── 03-deployment-scaledobject/
│   ├── 04-rollout-scaledobject/
│   ├── 05-deployment-hpa-container-thresholds/
│   ├── 06-rollout-hpa-container-thresholds/
│   ├── 07-deployment-scaledobject-container-thresholds/
│   └── 08-rollout-scaledobject-container-thresholds/
├── argocd/
│   ├── applications/
│   │   └── *.yaml (ArgoCD Application manifests)
│   └── configmap-ignoredifferences.yaml
└── docs/
    └── setup-instructions.md
```

## Prerequisites

- Kubernetes cluster (1.20+)
- ArgoCD installed and configured
- KEDA operator installed (for ScaledObject tests)
- Argo Rollouts controller installed (for Rollout tests)
- Git repository hosting this code

## Quick Start

### 1. Initialize Git Repository

```bash
git init
git add .
git commit -m "Initial commit: Auto-rightsizing test scenarios"
git remote add origin <your-repo-url>
git push -u origin main
```

### 2. Configure ArgoCD to Ignore HPA/ScaledObject Differences

Apply the ArgoCD ConfigMap that configures ignoreDifferences:

```bash
kubectl apply -f argocd/configmap-ignoredifferences.yaml
```

**Important**: After applying the ConfigMap, restart the ArgoCD application controller:

```bash
kubectl rollout restart deployment argocd-application-controller -n argocd
```

### 3. Deploy Test Applications

Deploy all test scenarios via ArgoCD:

```bash
kubectl apply -f argocd/applications/
```

### 4. Verify Deployments

Check that all applications are synced:

```bash
argocd app list
argocd app get <app-name>
```

## Testing Auto-Rightsizing

Once deployed, you can test the auto-rightsizing functionality:

1. **Modify HPA/ScaledObject resources** (e.g., change target CPU utilization)
2. **Verify ArgoCD doesn't detect drift** - The applications should remain in "Synced" status
3. **Check that workloads scale appropriately** based on the updated thresholds

## Validation Checklist

- [ ] All ArgoCD Applications are in "Synced" state
- [ ] HPAs are functioning and scaling pods based on metrics
- [ ] ScaledObjects are functioning and scaling pods based on triggers
- [ ] Manual changes to HPA/ScaledObject specs don't cause ArgoCD sync drift
- [ ] Auto-rightsizing changes are applied successfully
- [ ] Container-specific thresholds are respected

## Troubleshooting

### ArgoCD Shows Out of Sync

If ArgoCD still shows applications as out of sync after modifying HPA/ScaledObject:

1. Verify the ConfigMap was applied correctly
2. Ensure the ArgoCD controller was restarted
3. Check ArgoCD logs for any errors
4. Verify the `ignoreDifferences` configuration in the ConfigMap

### ScaledObjects Not Working

If ScaledObjects aren't scaling:

1. Verify KEDA is installed: `kubectl get pods -n keda`
2. Check ScaledObject status: `kubectl describe scaledobject <name>`
3. Review KEDA operator logs

### Rollouts Not Deploying

If Rollouts aren't working:

1. Verify Argo Rollouts is installed: `kubectl get pods -n argo-rollouts`
2. Check Rollout status: `kubectl describe rollout <name>`
3. Review rollouts controller logs

## Notes

- All test applications use the `nginx:latest` image as a simple workload
- Each scenario is isolated in its own namespace matching the application name
- The ArgoCD sync policy is set to automated with self-healing enabled
- Resource requests/limits are set to enable HPA metric collection

## Contributing

When adding new test scenarios:

1. Create a new directory under `manifests/`
2. Include all necessary Kubernetes manifests
3. Create a corresponding ArgoCD Application in `argocd/applications/`
4. Update this README with the new scenario
5. Test the scenario end-to-end before committing

