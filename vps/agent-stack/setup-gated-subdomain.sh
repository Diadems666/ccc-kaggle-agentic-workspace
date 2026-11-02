#!/usr/bin/env bash
set -euo pipefail

# Publish OpenHands at https://kaggle.tropicops.cloud behind Cloudflare Access.
# Run as root on the VPS, after install-agent-stack.sh.
#
# Required environment:
#   CF_API_TOKEN     API token with: Zone:DNS:Edit, Access:Apps and Policies:Edit, Account:Read
#   CF_ACCOUNT_ID    Cloudflare account id
# Optional:
#   SUBDOMAIN        default kaggle.tropicops.cloud
#   ALLOWED_EMAILS   comma-separated, default joe.venner@hotmail.com
#   ORIGIN           default http://localhost:3000 (OpenHands)
#   CLOUDFLARED_CONFIG default /etc/cloudflared/config.yml
#   SESSION_DURATION default 24h
#
# Idempotent: re-running updates rather than duplicates. The script ends by
# verifying that the public URL redirects to Cloudflare Access (i.e. is gated)
# and exits non-zero if it is not.

SUBDOMAIN="${SUBDOMAIN:-kaggle.tropicops.cloud}"
ALLOWED_EMAILS="${ALLOWED_EMAILS:-joe.venner@hotmail.com}"
ORIGIN="${ORIGIN:-http://localhost:3000}"
CFG="${CLOUDFLARED_CONFIG:-/etc/cloudflared/config.yml}"
SESSION_DURATION="${SESSION_DURATION:-24h}"
API="https://api.cloudflare.com/client/v4"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || die "Run as root."
: "${CF_API_TOKEN:?Set CF_API_TOKEN}"
: "${CF_ACCOUNT_ID:?Set CF_ACCOUNT_ID}"
command -v curl >/dev/null || die "curl required"
command -v python3 >/dev/null || die "python3 required"
[[ -f "$CFG" ]] || die "cloudflared config not found at $CFG"

cf() {  # method path [json-body]
    local method="$1" path="$2" body="${3:-}"
    if [[ -n "$body" ]]; then
        curl -sS -X "$method" "$API$path" -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" --data "$body"
    else
        curl -sS -X "$method" "$API$path" -H "Authorization: Bearer $CF_API_TOKEN"
    fi
}

jget() {  # python expression over parsed stdin JSON in variable d
    python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"
}

check_ok() {
    local resp="$1" what="$2"
    python3 -c "import sys,json; d=json.loads(sys.argv[1]); sys.exit(0 if d.get('success') else 1)" "$resp" \
        || die "$what failed: $(python3 -c "import sys,json; print(json.loads(sys.argv[1]).get('errors'))" "$resp")"
}

# 1. Zone + tunnel ------------------------------------------------------------
APEX="$(awk -F. '{print $(NF-1)"."$NF}' <<<"$SUBDOMAIN")"
log "Looking up zone $APEX"
RESP="$(cf GET "/zones?name=${APEX}")"
check_ok "$RESP" "Zone lookup"
ZONE_ID="$(jget "d['result'][0]['id'] if d['result'] else ''" <<<"$RESP")"
[[ -n "$ZONE_ID" ]] || die "Zone $APEX is not in this Cloudflare account."

TUNNEL_ID="$(sed -n 's/^tunnel:[[:space:]]*//p' "$CFG" | head -n 1 | tr -d '\r"')"
[[ -n "$TUNNEL_ID" && "$TUNNEL_ID" != YOUR_TUNNEL_ID_HERE ]] || die "No tunnel id in $CFG"
log "Tunnel: $TUNNEL_ID"

# 2. DNS CNAME ----------------------------------------------------------------
TARGET="${TUNNEL_ID}.cfargotunnel.com"
RESP="$(cf GET "/zones/${ZONE_ID}/dns_records?name=${SUBDOMAIN}")"
check_ok "$RESP" "DNS lookup"
REC_ID="$(jget "d['result'][0]['id'] if d['result'] else ''" <<<"$RESP")"
BODY="{\"type\":\"CNAME\",\"name\":\"${SUBDOMAIN}\",\"content\":\"${TARGET}\",\"proxied\":true}"
if [[ -n "$REC_ID" ]]; then
    log "Updating DNS record"
    check_ok "$(cf PUT "/zones/${ZONE_ID}/dns_records/${REC_ID}" "$BODY")" "DNS update"
else
    log "Creating DNS record"
    check_ok "$(cf POST "/zones/${ZONE_ID}/dns_records" "$BODY")" "DNS create"
fi

# 3. Access application FIRST, so the host is never exposed ungated ------------
log "Configuring Cloudflare Access"
POLICY="$(python3 - "$ALLOWED_EMAILS" <<'PY'
import json, sys
emails = [e.strip() for e in sys.argv[1].split(",") if e.strip()]
print(json.dumps([{
    "name": "Owner only",
    "decision": "allow",
    "include": [{"email": {"email": e}} for e in emails],
}]))
PY
)"
APP_BODY="$(python3 - "$SUBDOMAIN" "$SESSION_DURATION" "$POLICY" <<'PY'
import json, sys
host, dur, pol = sys.argv[1:4]
print(json.dumps({
    "name": "Kaggle agent (OpenHands)",
    "domain": host,
    "type": "self_hosted",
    "session_duration": dur,
    "policies": json.loads(pol),
    "auto_redirect_to_identity": False,
    "http_only_cookie_attribute": True,
}))
PY
)"
RESP="$(cf GET "/accounts/${CF_ACCOUNT_ID}/access/apps")"
check_ok "$RESP" "Access app list"
APP_ID="$(jget "next((a['id'] for a in d['result'] if a.get('domain')=='${SUBDOMAIN}'), '')" <<<"$RESP")"
if [[ -n "$APP_ID" ]]; then
    check_ok "$(cf PUT "/accounts/${CF_ACCOUNT_ID}/access/apps/${APP_ID}" "$APP_BODY")" "Access app update"
else
    check_ok "$(cf POST "/accounts/${CF_ACCOUNT_ID}/access/apps" "$APP_BODY")" "Access app create"
fi
log "Access app ready; allowed: $ALLOWED_EMAILS"

# 4. Tunnel ingress -----------------------------------------------------------
if grep -q "hostname: ${SUBDOMAIN}" "$CFG"; then
    log "Ingress for $SUBDOMAIN already present"
else
    log "Adding ingress rule (backup: ${CFG}.bak.$(date +%s))"
    cp "$CFG" "${CFG}.bak.$(date +%s)"
    python3 - "$CFG" "$SUBDOMAIN" "$ORIGIN" <<'PY'
import sys
path, host, origin = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
block = (f"  # OpenHands agent UI (gated by Cloudflare Access)\n"
         f"  - hostname: {host}\n    service: {origin}\n"
         f"    originRequest:\n      connectTimeout: 30s\n\n")
marker = "  # Catch-all"
if marker in text:
    text = text.replace(marker, block + marker, 1)
else:
    idx = text.rfind("  - service: http_status:404")
    if idx < 0:
        raise SystemExit("catch-all rule not found in config")
    text = text[:idx] + block + text[idx:]
open(path, "w", encoding="utf-8").write(text)
PY
fi
if command -v cloudflared >/dev/null; then
    cloudflared tunnel --config "$CFG" ingress validate || die "ingress validation failed; restore the .bak file"
fi
systemctl restart cloudflared
sleep 5

# 5. Verify it is gated -------------------------------------------------------
log "Verifying https://${SUBDOMAIN} is gated"
CODE="" LOC=""
for _ in 1 2 3 4 5 6; do
    HDRS="$(curl -sS -o /dev/null -D - --max-time 15 "https://${SUBDOMAIN}/" || true)"
    CODE="$(head -n 1 <<<"$HDRS" | awk '{print $2}')"
    LOC="$(grep -i '^location:' <<<"$HDRS" | head -n 1 | tr -d '\r')"
    [[ -n "$CODE" ]] && break
    sleep 5
done
if [[ "$CODE" =~ ^30[1-3]$ && "$LOC" == *cloudflareaccess.com* ]]; then
    echo "OK: unauthenticated request is redirected to Cloudflare Access login."
    echo "Open https://${SUBDOMAIN} in a browser and sign in with: $ALLOWED_EMAILS"
else
    echo "FAIL: expected a redirect to cloudflareaccess.com, got HTTP '${CODE:-none}' ${LOC}" >&2
    echo "Treat https://${SUBDOMAIN} as UNPROTECTED. OpenHands has the docker socket." >&2
    echo "Disable it now: remove the ingress block from $CFG and restart cloudflared." >&2
    exit 1
fi
