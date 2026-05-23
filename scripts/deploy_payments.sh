#!/usr/bin/env bash
# Deploy the payments app into the current AKS cluster (Phase 4).
#
# Mirrors the WI/KEDA sandbox pattern: pull the per-sandbox values from Terraform
# outputs, create the Service Bus secret, substitute the manifest placeholders,
# and apply. Re-runnable; safe to run after every sandbox rebuild.
#
# Prereqs: az logged in to the sandbox, kubectl pointed at the cluster
#   (az aks get-credentials -g <rg> -n aksgitops-aks --overwrite-existing),
#   Terraform applied (Phase 3 adds the KV signing key + federated credential).
set -euo pipefail

TF="terraform -chdir=terraform"
NS="payments"

echo "==> reading Terraform outputs"
KV_CLIENT_ID="$($TF output -raw kv_reader_client_id)"
KV_NAME="$($TF output -raw key_vault_name)"
SB_CONN="$($TF output -raw servicebus_keda_connection_string)"

echo "==> namespace + Service Bus secret"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic servicebus-conn \
  --from-literal=connection-string="$SB_CONN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> applying manifests (substituting placeholders)"
for f in k8s/apps/payments/*.yaml; do
  sed -e "s|__KV_READER_CLIENT_ID__|${KV_CLIENT_ID}|g" \
      -e "s|__KEY_VAULT_NAME__|${KV_NAME}|g" "$f" | kubectl apply -f -
done

echo "==> waiting for redis + api"
kubectl -n "$NS" rollout status deploy/redis --timeout=120s
kubectl -n "$NS" rollout status deploy/payments-api --timeout=120s

cat <<EOF

==> done. The worker is at 0 replicas (KEDA scales it on queue depth).

Test it:
  kubectl -n ${NS} port-forward svc/payments-api 8080:80   # keep this running
  # then, in another terminal:
  open http://localhost:8080/docs                           # Swagger UI
  python3 scripts/send_transfers.py 20                      # fire 20 transfers
  python3 scripts/send_transfers.py ledger                  # watch PENDING -> SETTLED
  watch kubectl -n ${NS} get pods                           # see KEDA scale 0 -> N -> 0
EOF
