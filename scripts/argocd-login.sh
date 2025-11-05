#!/bin/bash

# ArgoCD Login Helper Script

echo "=========================================="
echo "ArgoCD Login Helper"
echo "=========================================="
echo ""

# Check if port-forward is running
if ! lsof -i :8080 | grep -q LISTEN; then
  echo "Starting port-forward to ArgoCD server..."
  kubectl port-forward svc/argocd-server -n argocd 8080:80 >/dev/null 2>&1 &
  PF_PID=$!
  echo "Port-forward started (PID: $PF_PID)"
  echo "Waiting for port-forward to be ready..."
  sleep 3
else
  echo "Port-forward already running on port 8080"
fi

echo ""
echo "ArgoCD Server: localhost:8080"
echo "Username: admin"
echo ""

# Prompt for password
read -s -p "Enter ArgoCD admin password: " PASSWORD
echo ""

echo ""
echo "Attempting login..."
argocd login localhost:8080 --username admin --password "$PASSWORD" --insecure

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Successfully logged in to ArgoCD!"
  echo ""
  echo "Test it:"
  echo "  argocd app list"
  echo "  argocd app get deployment-hpa"
else
  echo ""
  echo "❌ Login failed"
  echo ""
  echo "Troubleshooting:"
  echo "1. Check password is correct"
  echo "2. Get the default password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  echo "3. Check ArgoCD is running: kubectl get pods -n argocd"
fi

