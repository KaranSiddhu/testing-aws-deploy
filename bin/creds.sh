#!/usr/bin/env bash
# Print the operator/handoff packet — superadmin login, Grafana password, and the
# zone nameservers to delegate. Reads Secrets Manager + terraform output. Sources .env.
# (Uses python3's stdlib json — no extra deps.)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; [ -f .env ] && . ./.env; set +a
REGION="${AWS_REGION:-us-east-1}"

sm() { aws secretsmanager get-secret-value --region "$REGION" --secret-id "$1" --query SecretString --output text; }

echo "=== Superadmin — log in at https://app.lab.karansiddhu.com/superadmin ==="
sm magoneai-app-secrets | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  email:   ",d["superadmin-email"]);print("  password:",d["superadmin-password"])'
echo
echo "=== Grafana — admin user is set in the grafana chart (GF_SECURITY_ADMIN_USER) ==="
sm magoneai-app-secrets | python3 -c 'import sys,json;print("  password:",json.load(sys.stdin)["grafana-admin-password"])'
echo
echo "=== Zone nameservers to delegate at the registrar ==="
( cd terraform/infra && terraform output -json dns_zone_name_servers 2>/dev/null | tr -d '[]"' | tr ',' '\n' | sed 's/^/  /' ) \
  || echo "  (run where terraform state is reachable)"
