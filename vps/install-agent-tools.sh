#!/usr/bin/env bash
set -euo pipefail

# Install all AI agent tools:
# - Claude Code (@anthropic-ai/claude-code)
# - OpenCode (opencode-ai)
# - Codex CLI (@openai/codex)
# - Aider (aider-chat via pip)

INSTALL_USER="${INSTALL_USER:-deploy}"
WORKSPACE_DIR="/opt/coding-workspace"

echo "=== Installing Agent Tools ==="
echo ""

# ─── Claude Code ──────────────────────────────────────────────────────────────
echo "[1/4] Installing Claude Code..."
npm install -g @anthropic-ai/claude-code --quiet
CLAUDE_VER=$(claude --version 2>/dev/null | head -1 || echo "installed")
echo "  claude: $CLAUDE_VER"

# ─── OpenCode ─────────────────────────────────────────────────────────────────
echo "[2/4] Installing OpenCode..."
npm install -g opencode-ai --quiet 2>/dev/null || \
    echo "  WARNING: opencode-ai install failed — verify package name at npmjs.com/package/opencode-ai"
command -v opencode &>/dev/null && echo "  opencode: $(opencode --version 2>/dev/null | head -1 || echo 'installed')"

# ─── Codex CLI ────────────────────────────────────────────────────────────────
echo "[3/4] Installing Codex CLI..."
npm install -g @openai/codex --quiet 2>/dev/null || \
    echo "  WARNING: @openai/codex install failed — verify at npmjs.com/package/@openai/codex"
command -v codex &>/dev/null && echo "  codex: $(codex --version 2>/dev/null | head -1 || echo 'installed')"

# ─── Aider ────────────────────────────────────────────────────────────────────
echo "[4/4] Installing Aider..."
pip3 install -q aider-chat 2>/dev/null || pip install -q aider-chat
AIDER_VER=$(aider --version 2>/dev/null | head -1 || echo "installed")
echo "  aider: $AIDER_VER"

# ─── Write default Aider config ───────────────────────────────────────────────
AIDER_CONFIG="/home/${INSTALL_USER}/.aider.conf.yml"
if [[ ! -f "$AIDER_CONFIG" ]]; then
    cat > "$AIDER_CONFIG" << 'EOF'
model: claude/claude-sonnet-4-6
auto-commits: true
git: true
pretty: true
stream: true
dark-mode: true
EOF
    chown "${INSTALL_USER}:${INSTALL_USER}" "$AIDER_CONFIG"
    echo "  Aider config written to $AIDER_CONFIG"
fi

# ─── Write Claude Code settings ───────────────────────────────────────────────
CLAUDE_SETTINGS_DIR="/home/${INSTALL_USER}/.claude"
mkdir -p "$CLAUDE_SETTINGS_DIR"
if [[ ! -f "${CLAUDE_SETTINGS_DIR}/settings.json" ]]; then
    cat > "${CLAUDE_SETTINGS_DIR}/settings.json" << 'EOF'
{
  "model": "claude-sonnet-4-6",
  "theme": "dark"
}
EOF
    chown -R "${INSTALL_USER}:${INSTALL_USER}" "$CLAUDE_SETTINGS_DIR"
    echo "  Claude Code settings written to ${CLAUDE_SETTINGS_DIR}/settings.json"
fi

echo ""
echo "=== Agent tools installed ==="
echo ""
echo "Verify installation:"
echo "  claude --version"
echo "  aider --version"
echo ""
echo "Configure API keys in ${WORKSPACE_DIR}/.env:"
echo "  ANTHROPIC_API_KEY=sk-ant-..."
echo "  OPENAI_API_KEY=sk-..."
