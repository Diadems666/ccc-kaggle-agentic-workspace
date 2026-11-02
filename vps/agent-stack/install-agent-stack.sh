#!/usr/bin/env bash
set -euo pipefail

# Install / update the CCC agent stack (LiteLLM + SearXNG + OpenHands) on the VPS.
# Run as root from anywhere:  sudo bash vps/agent-stack/install-agent-stack.sh
#
# Idempotent: safe to re-run. It never overwrites secrets already in .env.
#
# Env switches:
#   INSTALL_DOCKER=1   install Docker Engine via get.docker.com if missing
#   SKIP_SSHD=1        do not touch sshd (you will configure the tunnel user yourself)
#   SKIP_UFW=1         do not add ufw rules for the docker bridge
#   SKIP_START=1       write config only; do not run docker compose up

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/coding-workspace}"
WORKSPACE_ENV="${WORKSPACE_DIR}/.env"
ENV_FILE="${STACK_DIR}/.env"
SSHD_DROPIN="/etc/ssh/sshd_config.d/50-kaggle-gpu.conf"

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "run as root (sudo)"

# ─── 1. Docker ───────────────────────────────────────────────────────────────
say "Checking Docker"
if ! command -v docker >/dev/null 2>&1; then
    if [[ "${INSTALL_DOCKER:-0}" == "1" ]]; then
        curl -fsSL https://get.docker.com | sh
    else
        die "Docker not found. Re-run with INSTALL_DOCKER=1 or install it first."
    fi
fi
docker compose version >/dev/null 2>&1 || die "docker compose plugin missing (apt install docker-compose-plugin)"
systemctl enable --now docker >/dev/null 2>&1 || true

# ─── 2. Resources ────────────────────────────────────────────────────────────
say "Checking resources"
MEM_MB="$(free -m | awk 'NR==2{print $2}')"
echo "RAM: ${MEM_MB} MB"
if (( MEM_MB < 3500 )); then
    warn "OpenHands + LiteLLM + SearXNG want ~4 GB RAM (plus room for sandbox containers)."
    warn "With ${MEM_MB} MB expect swapping. Consider resizing the VPS, or run only litellm+searxng."
fi
DISK_GB="$(df -BG --output=avail "$STACK_DIR" | tail -n 1 | tr -dc '0-9')"
(( DISK_GB >= 10 )) || warn "Only ${DISK_GB} GB free; OpenHands images and sandboxes need ~10 GB."

# ─── 3. Bridge IP ────────────────────────────────────────────────────────────
say "Detecting docker bridge IP"
BRIDGE_IP="$(ip -4 -o addr show docker0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1 || true)"
BRIDGE_IP="${BRIDGE_IP:-172.17.0.1}"
echo "docker0: ${BRIDGE_IP}"

# ─── 4. .env (generate secrets once) ─────────────────────────────────────────
say "Preparing ${ENV_FILE}"
[[ -f "$ENV_FILE" ]] || cp "${STACK_DIR}/.env.example" "$ENV_FILE"
chmod 600 "$ENV_FILE"

get_env()  { grep -E "^$1=" "$ENV_FILE" | head -n 1 | cut -d= -f2- || true; }
set_env()  {
    local key="$1" value="$2"
    if grep -qE "^${key}=" "$ENV_FILE"; then
        # '|' delimiter is safe: generated values are hex / base64url-free of '|'
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
}

set_env BRIDGE_IP "$BRIDGE_IP"
[[ -n "$(get_env LITELLM_MASTER_KEY)" ]] || set_env LITELLM_MASTER_KEY "sk-ccc-$(openssl rand -hex 24)"
[[ -n "$(get_env SEARXNG_SECRET)" ]]     || set_env SEARXNG_SECRET "$(openssl rand -hex 32)"

if [[ -z "$(get_env ANTHROPIC_API_KEY)" && -f "$WORKSPACE_ENV" ]]; then
    KEY_FROM_WS="$(grep -E '^ANTHROPIC_API_KEY=' "$WORKSPACE_ENV" | head -n 1 | cut -d= -f2- || true)"
    if [[ -n "$KEY_FROM_WS" && "$KEY_FROM_WS" != sk-ant-YOUR_KEY_HERE ]]; then
        set_env ANTHROPIC_API_KEY "$KEY_FROM_WS"
        echo "ANTHROPIC_API_KEY copied from ${WORKSPACE_ENV}"
    fi
fi
[[ -n "$(get_env ANTHROPIC_API_KEY)" ]] || warn "ANTHROPIC_API_KEY empty: ccc-client / ccc-fast will not work until you set it in ${ENV_FILE}."

mkdir -p "$(get_env OPENHANDS_STATE_DIR)"

# ─── 5. sshd: let the Kaggle tunnel user bind ONLY ${BRIDGE_IP}:8081 ─────────
if [[ "${SKIP_SSHD:-0}" != "1" ]]; then
    say "Configuring sshd for the Kaggle tunnel user"
    id kaggle-gpu >/dev/null 2>&1 || die "user kaggle-gpu missing; run vps/create-users.sh first"
    install -d -m 755 /etc/ssh/sshd_config.d
    [[ -f "$SSHD_DROPIN" ]] && cp "$SSHD_DROPIN" "${SSHD_DROPIN}.bak.$(date +%s)"
    sed "s/__BRIDGE_IP__/${BRIDGE_IP}/g" "${STACK_DIR}/sshd-kaggle-gpu.conf.template" > "$SSHD_DROPIN"
    chmod 644 "$SSHD_DROPIN"
    if sshd -t; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd
        echo "sshd reloaded with ${SSHD_DROPIN}"
    else
        rm -f "$SSHD_DROPIN"
        die "sshd config test failed; drop-in removed, nothing changed"
    fi
    if ! grep -qs "permitlisten" /home/kaggle-gpu/.ssh/authorized_keys; then
        warn "Tighten /home/kaggle-gpu/.ssh/authorized_keys. The key line should start with:"
        warn "  restrict,port-forwarding,permitlisten=\"${BRIDGE_IP}:8081\" ssh-ed25519 AAAA..."
        warn "(see docs/KAGGLE_QWEN38_AGENT.md)"
    fi
fi

# ─── 6. ufw: allow containers on docker0 to reach the bridge-bound ports ─────
if [[ "${SKIP_UFW:-0}" != "1" ]] && command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    say "Adding ufw rules for docker0 -> ${BRIDGE_IP}"
    for port in 4000 8081 8888; do
        ufw allow in on docker0 to "$BRIDGE_IP" port "$port" proto tcp comment "ccc agent stack" >/dev/null
    done
fi

# ─── 7. Start ────────────────────────────────────────────────────────────────
if [[ "${SKIP_START:-0}" == "1" ]]; then
    say "SKIP_START=1 set; not starting containers"
else
    say "Pulling images and starting the stack"
    (cd "$STACK_DIR" && docker compose pull && docker compose up -d)
fi

MASTER="$(get_env LITELLM_MASTER_KEY)"
cat <<EOF

────────────────────────────────────────────────────────────────────────
Agent stack installed.

 1. Cloudflare: add an ingress rule for your OpenHands hostname and protect it with an
    Access policy (see vps/cloudflare/tunnel-config.yml.example):
        hostname: agent.cairnscustomcomputers.cloud  ->  http://localhost:3000

 2. OpenHands first run -> Settings -> LLM -> Advanced:
        Custom model : openai/ccc-local          (or openai/ccc-client for client work)
        Base URL     : http://host.docker.internal:4000/v1
        API key      : ${MASTER}

 3. Start the Kaggle worker (docs/KAGGLE_QWEN38_AGENT.md), then check:
        bash scripts/agent_stack_status.sh
────────────────────────────────────────────────────────────────────────
EOF
