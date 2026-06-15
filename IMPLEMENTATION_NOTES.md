# Implementation Notes

Technical notes and gotchas discovered during implementation.

## VPS Provisioning

### Ubuntu 24.04 vs 22.04

The VPS scripts target Ubuntu 24.04 LTS. Key differences from 22.04:
- Python 3.12 is default (not 3.10) — some older packages may need pinning
- `apt` package names for some node/npm tools have changed
- systemd 255 — unit file syntax is the same

If you must use 22.04, the scripts will work but `python3-pip` installs to a different location. Use `pip3 install --break-system-packages` if you hit PEP 668 errors.

### NodeJS installation

The scripts use NodeSource to install Node 20 LTS (not Ubuntu's older packaged version). The install-vps.sh script handles this:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

Node 20 is required for Claude Code and OpenCode. Node 18 may work but is untested.

### npm global installs

npm global packages install to `/usr/local/lib/node_modules/` when running as root. The scripts use `sudo npm install -g` for agent tools to make them available system-wide.

If you prefer per-user installs (as `deploy` user), set `npm prefix` and add to PATH:
```bash
npm config set prefix ~/.npm-global
export PATH="$HOME/.npm-global/bin:$PATH"
```

---

## code-server

### Port selection

code-server runs on port 8080. This is the internal port — Cloudflare Tunnel maps it to HTTPS 443 externally.

If port 8080 is in use, change it in:
1. `/etc/code-server/config.yaml` → `bind-addr: 127.0.0.1:8081`
2. `/etc/cloudflared/config.yml` → update the `service:` URL to match

### Extension compatibility

code-server uses the Open VSX extension registry, not the Microsoft VS Code Marketplace. Most popular extensions are available on Open VSX, but some proprietary ones are not (e.g., GitHub Copilot, some JetBrains extensions).

To install an extension from `.vsix` file:
```bash
code-server --install-extension /path/to/extension.vsix
```

### code-server vs OpenVSCode Server

| Feature | code-server | OpenVSCode Server |
|---------|-------------|-------------------|
| Extension registry | Open VSX | Open VSX |
| Auth | Password (built-in) | None (use Cloudflare Access) |
| Mobile UX | Good | Slightly better |
| Active development | Active | Active |

Both are installed by the respective scripts. Default is code-server (has built-in password auth as additional layer). OpenVSCode Server relies entirely on Cloudflare Access for auth.

---

## Cloudflare Tunnel

### Tunnel token format

The tunnel token is a long base64 string starting with `eyJ...`. It encodes the tunnel ID, account tag, and secret.

It goes into `/etc/cloudflared/config.yml` as:
```yaml
tunnel: YOUR_TUNNEL_ID
credentials-file: /root/.cloudflared/YOUR_TUNNEL_ID.json
```

Or in newer cloudflared versions, you can use:
```bash
cloudflared service install TOKEN_STRING
```

Which auto-creates the config.

### DNS configuration

Add a CNAME in Cloudflare DNS:
- Name: `coding`
- Target: `YOUR_TUNNEL_ID.cfargotunnel.com`
- Proxy: enabled (orange cloud)

Do **not** set the target to your VPS IP — that would bypass the tunnel.

### Cloudflare Access JWT

Cloudflare Access injects a JWT cookie into requests passing through an Access application. The JWT is signed with Cloudflare's key and validates every request.

If code-server complains about an unknown cookie, this is normal — the cookie is for Cloudflare's use, not code-server's. It doesn't affect code-server functionality.

---

## Kaggle SSH Tunnel

### SSH key restrictions

The kaggle-gpu user's authorized_keys entry uses restrictions to limit what the key can do:

```
command="echo 'tunnel only'",no-pty,no-agent-forwarding,no-X11-forwarding,permitopen="localhost:8080" ssh-ed25519 AAAA...
```

The `permitopen` directive restricts port forwarding to only the LLM server port. This prevents the Kaggle key from being used to access other services on the VPS.

### Reverse tunnel SSH command

```bash
# Run on Kaggle notebook:
ssh -N -R 8081:localhost:8080 \
    -i /tmp/kaggle_tunnel_key \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    kaggle-gpu@YOUR_VPS_IP
```

- `-N`: don't execute remote command, just maintain tunnel
- `-R 8081:localhost:8080`: forward VPS port 8081 to Kaggle port 8080
- `ServerAliveInterval/CountMax`: keep tunnel alive and detect drops

### GatewayPorts for VPS accessibility

By default, reverse tunnel ports bind to `127.0.0.1` on the VPS only. Since we only need the LLM from the VPS itself (agents running on VPS), this is correct and more secure.

If you ever need other machines to reach the Kaggle LLM through the VPS tunnel, set `GatewayPorts clientspecified` in `/etc/ssh/sshd_config` (not recommended without additional firewall rules).

---

## llama.cpp Server

### CUDA vs CPU

On Kaggle T4, llama.cpp must be compiled with CUDA support:
```bash
CMAKE_ARGS="-DGGML_CUDA=on" pip install llama-cpp-python
```

Without CUDA, inference falls back to CPU which is ~10× slower. The setup script handles this, but verify with:
```bash
python3 -c "from llama_cpp import Llama; l=Llama('model.gguf', n_gpu_layers=-1); print('GPU layers:', l.n_gpu_layers)"
```

### vLLM vs llama.cpp

| Aspect | vLLM | llama.cpp |
|--------|------|-----------|
| Throughput | Higher | Lower |
| VRAM efficiency | Lower | Higher |
| Install size | ~8 GB | ~200 MB |
| Model format | HuggingFace | GGUF |
| T4 compatibility | Requires CUDA 11.8+ | Works well |

Use llama.cpp by default (more T4-compatible). Switch to vLLM for high-throughput sessions with `start_vllm_server.sh`.

---

## Agent Tools

### Claude Code settings.json location

On the VPS (as the deploy user): `~/.claude/settings.json`

On Kaggle notebooks: not persistent — configure via environment variable or pass flags directly.

### Aider git integration

Aider creates commits automatically by default. To disable for a session:
```bash
aider --no-auto-commits FILE
```

Aider's commits include a `[aider]` tag in the message. You can clean these up before pushing to shared repos:
```bash
git rebase -i origin/main  # squash aider commits into meaningful ones
```

### Context file precedence

When agents start in a directory, they load context files in this order:
1. `CLAUDE.md` (Claude Code only)
2. `AGENTS.md` (general, supported by some agents)
3. `.aider.conf.yml` (Aider only)
4. Environment variables
5. Command-line flags
