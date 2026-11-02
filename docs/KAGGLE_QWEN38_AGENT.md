# Kaggle GPU coding and research agent (Qwen3.8-27B + OpenHands)

A self-hosted coding, research and agent environment that uses the free Kaggle GPU as its
brain and your BinaryLane VPS as its face. Added on 2026-11-02 to the existing
ccc-kaggle-agentic-workspace; it replaces the 7B-class setup in `kaggle/quick_start.py`.

## 1. What you get

| Layer | Component | Where |
|-------|-----------|-------|
| Model | **Qwen3.8-27B** (Apache-2.0), Unsloth Dynamic `UD-Q4_K_M` GGUF, 64K context | Kaggle 2x T4 |
| Inference | native **llama.cpp** `llama-server`, layer-split across both T4s, q8 KV cache | Kaggle |
| Link | authenticated **reverse SSH tunnel**, outbound from Kaggle, no public URL | Kaggle -> VPS |
| Gateway | **LiteLLM**: one OpenAI-compatible endpoint, named routes (`ccc-local`, `ccc-client`, ...) | VPS |
| Interface | **OpenHands** web UI: agent with terminal, editor, git, sandboxed workspace | VPS via Cloudflare Access |
| Research | **SearXNG** + `research/searx.py` / `research/fetch.py` + a `deep-research` skill | VPS |
| Terminal agents | Aider / OpenCode / Claude Code keep working; point them at the gateway | VPS |

```
 phone / laptop ──HTTPS──> Cloudflare Access ──tunnel──> OpenHands :3000 ─┐
                                                                         │ http://host.docker.internal:4000/v1
                                              sandbox containers ────────┤
                                                                         ▼
 Aider / OpenCode / Claude Code (VPS shell) ───────────────────────> LiteLLM :4000
                                                                         │
                          ccc-local / ccc-local-think ───────────────────┤──> 172.17.0.1:8081 ═ SSH -R ═> Kaggle llama-server
                          ccc-client / ccc-fast ─────────────────────────┘──> Anthropic API (paid, client-safe)

 SearXNG :8888 <── research/searx.py (called by the agent inside its sandbox)
```

## 2. Read this first: Kaggle's rules and the ban risk

I checked Kaggle's Terms of Use (version dated 22 June 2025) and current community reports.

* The Terms say you "will only use the Services for your own internal, personal,
  non-commercial use, and not on behalf of or for the benefit of any third party", and that
  Kaggle may terminate or suspend your account at its sole discretion if it decides you are
  in breach. The Terms do not name LLM serving or tunnels specifically.
* As of September-October 2026, Kaggle users are publicly complaining that tutorials are
  turning notebooks into free LLM servers (Ollama/vLLM/llama.cpp plus Cloudflare Tunnel or
  ngrok), that T4 availability is degrading, and they are asking Kaggle to detect tunnels and
  serving stacks and to ban the pattern explicitly. One commenter on a tutorial reports a
  ban for a "server farm" after a second run. These are user reports, not Kaggle policy, but
  the direction of enforcement is clear.
* You said some of this work will touch client projects. That is not allowed on the free
  Kaggle quota under the Terms above.

How this build limits the exposure (it cannot remove it):

1. **Personal and R&D work only goes to `ccc-local*`.** Client work goes to `ccc-client`
   (a paid Anthropic model through the same gateway), which never touches Kaggle. Do not put
   client code, data or credentials into a `ccc-local` conversation.
2. **No public endpoint.** No Cloudflare Quick Tunnel, ngrok or open port on Kaggle's side.
   The notebook opens one outbound SSH connection to your own VPS, which is the same pattern
   as a developer SSHing home.
3. **No keep-alive or quota games.** The worker has a hard stop (`SESSION_MAX_HOURS`, default
   6), does not restart itself after a crash, and in "Save & Run All" mode the Kaggle session
   ends when the script ends. No 24/7 loops, no second accounts.
4. **Use one account, your own, and keep it modest.** Treat the free GPU as a bonus, not
   infrastructure. If Kaggle bans the account you also lose your datasets and notebooks, so
   do not host anything irreplaceable there. Everything important is in Git on the VPS.
5. **The gateway makes the GPU replaceable.** Agents only know `ccc-local`. If Kaggle
   throttles or bans you, point that alias at a rented GPU or a hosted open-weight API by
   editing three lines in `vps/agent-stack/litellm_config.yaml`. Nothing else changes.
6. The old `tmate` shell relay in `quick_start.py` is gone from v2. It exposed a shell on the
   Kaggle container via a third-party relay, which is both a security and a policy smell.

If you want a zero-risk primary backend, flip the alias now and keep Kaggle for experiments.

## 3. Why this model and stack (research summary)

**Quota.** Kaggle's free tier is about 30 GPU hours/week (sometimes more), sessions up to 12 h,
2x Tesla T4 (about 30 GB VRAM total) or one P100, 20 GB persistent output, 29 GB RAM. A forum
post says the P100 was retired on 15 Sep 2026 so T4 is the only GPU, and commenters report real
weekly usage being lower than 30 h; I could not verify either claim, so the code handles one or
two GPUs and you should check Settings -> Accelerator.

**Model.** Dozens of open models score higher on paper, but the frontier ones (Kimi K3, DeepSeek
V4, GLM-5.x, MiniMax M3: 230B-2.8T parameters) need multi-GPU server nodes and cannot run on
30 GB. In the range that fits, Qwen3.8-27B is the strongest option I found:

* Dense 27B, native vision-language, Apache-2.0, 262K native context, tool-calling fixes in the
  Unsloth GGUFs, Qwen's own pitch is coding, research and long-horizon agent tasks. A third-party
  roundup lists it at 61.7% on SWE-bench Pro (vendor/roundup figure, not independently run).
* Hybrid DeltaNet architecture: only 16 of 64 layers keep a KV cache. At 64K context with a q8
  cache that is about 2.3 GB, so the whole thing (16.5 GB weights + cache + buffers) fits in
  2x15 GB with room to spare. Q5_K_M (19.8 GB) also fits if you want more quality.
* Alternatives considered: Qwen3-Coder-Next (80B MoE, 3B active; needs ~2-bit to fit, which
  hurts quality), Devstral Small 2 (24B, strong SWE-agent results, shorter context),
  Qwen3.6-35B-A3B (what OpenHands' docs suggest first; faster, but older and weaker),
  gpt-oss-20b (fast but weaker at long agent tasks), Qwen3.8-Flash-Next (180B experimental
  architecture, pruned GGUFs only). All are Apache-2.0-ish; swap by editing `HF_REPO` and the
  filename logic in `kaggle/quick_start_v2.py`.

**Engine.** llama.cpp, compiled for T4 (sm_75), not vLLM and not `llama-cpp-python`. vLLM has no
good path on T4 for a 27B (no bf16, limited quant kernels); the Python wheels lag new
architectures. The compile takes about 25 minutes, so you do it once and keep the binary in a
private Kaggle Dataset.

**Interface.** OpenHands is the only candidate I found with a self-hostable browser UI, a
sandboxed workspace and an agent loop built for coding. OpenCode, Goose, Cline and Aider are
terminal/IDE tools; they still work against the gateway. SearXNG is the standard self-hosted
search layer for research agents; the research loop is a skill so it works in any agent.

**Honest expectations.** Generation on two T4s is bandwidth-bound: expect roughly 10-15
tokens/second for the Q4 model (my estimate from memory bandwidth, not a measurement; the
worker prints a real number at startup). Prompt processing of a 30K-token repo context takes a
minute or more. Thinking mode multiplies tokens per step by 3-10x, which is why `ccc-local`
runs with thinking OFF and `ccc-local-think` is opt-in. It is a very good open model, not
Claude: for hard cross-cutting refactors, use `ccc-client`.

## 4. Setup runbook

### 4.1 One-time: build the llama.cpp binary (Kaggle, ~25 min, uses ~0.5 GPU-hour)

1. Kaggle -> New Notebook, import `kaggle/kaggle-build-llama.ipynb`, Accelerator **GPU T4 x2**, Internet **On**.
2. Run all. When it finishes, open the Output panel -> `llama-cpp-sm75.tar.gz` -> **New Dataset**,
   name it `llama-cpp-sm75`, visibility **Private**.
3. Optional but recommended: also upload `Qwen3.8-27B-UD-Q4_K_M.gguf` (16.5 GB) as a private
   dataset from your PC (`kaggle datasets create`), which saves a 10-20 minute download per session.

### 4.2 VPS: install the stack

```bash
cd /opt/coding-workspace && git pull
sudo INSTALL_DOCKER=1 bash vps/agent-stack/install-agent-stack.sh   # drop INSTALL_DOCKER if Docker exists
```

It detects the docker bridge IP, generates the gateway and SearXNG secrets, copies your
`ANTHROPIC_API_KEY` from the workspace `.env`, installs the sshd drop-in that lets the tunnel
user bind exactly `172.17.0.1:8081` and nothing else, opens ufw for containers on docker0, and
starts everything. It prints the OpenHands settings to enter. VPS needs about 4 GB of RAM; the
installer warns if it has less.

Tighten the tunnel key line in `/home/kaggle-gpu/.ssh/authorized_keys`:

```
restrict,port-forwarding,permitlisten="172.17.0.1:8081" ssh-ed25519 AAAA... kaggle-tunnel
```

Pin the host key so the notebook never trusts an impostor:

```bash
ssh-keyscan -t ed25519 YOUR_VPS_IP     # paste the line into the notebook as env VPS_HOST_KEY
```

### 4.3 Cloudflare

Add the ingress block from `vps/cloudflare/tunnel-config.yml.example` for
`agent.cairnscustomcomputers.cloud` -> `http://localhost:3000`, create a CNAME for it, and create
an **Access** application with the same email policy as the IDE. Do not skip Access: OpenHands
holds the Docker socket, which is root-equivalent on the VPS.

### 4.4 Each session (from your phone is fine)

1. Kaggle notebook `kaggle/kaggle-quick-start-v2.ipynb` (secrets `KAGGLE_TUNNEL_KEY`, optional
   `LLM_API_KEY`; attach the datasets; accelerator **GPU T4 x2**; Internet on).
2. Prefer **Save Version -> Save & Run All (Commit)** so the session ends by itself when the
   worker stops. Interactive sessions work too, but then you must stop the session yourself
   after the cell finishes or it keeps burning quota while idle.
3. Within ~3-6 minutes: `bash scripts/agent_stack_status.sh --smoke` on the VPS shows the whole
   chain green and a real end-to-end completion.
4. Open `https://agent.cairnscustomcomputers.cloud`.

### 4.5 OpenHands settings (first run only)

Settings -> LLM -> Advanced:

| Field | Value |
|-------|-------|
| Custom model | `openai/ccc-local` (personal) or `openai/ccc-client` (client work) |
| Base URL | `http://host.docker.internal:4000/v1` |
| API key | the `LITELLM_MASTER_KEY` printed by the installer (also in `vps/agent-stack/.env`) |

Switch the model per conversation, not globally: **one conversation per project, and the model
is chosen by who the project is for.** Start a new conversation after changing skills.

### 4.6 Terminal agents on the VPS

```bash
bash scripts/switch_provider.sh local        # points tools at the gateway (ccc-local)
aider --openai-api-base http://127.0.0.1:4000/v1 --openai-api-key "$LITELLM_MASTER_KEY" --model openai/ccc-local
```

## 5. Using it

* **Coding:** "Add pagination to the notes API and write tests" in OpenHands on `ccc-local`.
  The `local-model-discipline` skill (plan file, small diffs, tests first) is loaded from
  `.agents/skills/`; copy that folder into each project (or keep projects under this repo).
* **Deep research:** "Deep research: compare ... and write a sourced report." The
  `deep-research` skill drives SearXNG, writes `research/<topic>/{plan,notes,report}.md`, and
  refuses to cite pages it did not read. Use `ccc-local-think` for the final synthesis if
  quality matters more than speed.
* **Client work:** use `ccc-client`. Same UI, same tools, paid model, no Kaggle.

## 6. Tuning

| Want | Change |
|------|--------|
| Higher quality | `os.environ["QUANT"] = "Q5_K_M"` (19.8 GB) |
| Longer context | `os.environ["CONTEXT_SIZE"] = "131072"` (auto steps down if it will not fit) |
| Faster | keep thinking off; try `LLAMA_EXTRA_ARGS` with llama.cpp's MTP/speculative flags (the Unsloth repo ships an `MTP` folder; check your build's `--help`) |
| Concurrent requests | `PARALLEL=2` splits the context between slots |
| Silent API failover | uncomment `fallbacks` in `litellm_config.yaml` (off by default so a dead GPU never turns into surprise API spend) |

## 7. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Accelerator greyed out in Kaggle | Quota used up or GPUs busy; wait for the weekly reset or try later |
| Status shows tunnel bound to `127.0.0.1` | sshd drop-in not active or notebook missing `VPS_TUNNEL_BIND=172.17.0.1`; rerun the installer |
| `remote port forwarding failed` | An old tunnel is still holding 8081; `sudo ss -ltnp \| grep 8081`, kill the stale sshd child |
| LiteLLM 500 on `ccc-local` | Tunnel down or model still loading; check `agent_stack_status.sh` |
| Agent loops or returns plain chat | Local model failing tool calls; try `ccc-local-think`, shorten the task, or use `ccc-client` |
| Thinking mode not toggling | The `enable_thinking` kwarg name may differ; the worker prints whether thinking is ON/off at startup, check the llama.cpp chat template |
| llama-server binary: missing `.so` | CUDA version in the Kaggle image changed; rebuild the dataset |

## 8. What I verified and what I could not

Verified here: Python logic (profile selection, key decoding, search/fetch tools: 18 unit tests
pass), shell syntax and ShellCheck on all scripts, Docker Compose config renders, YAML validity.

**Not testable from here (needs a real run, expect small fixes):** the llama.cpp CUDA build on
Kaggle's image, flag compatibility of your llama.cpp version (the launcher probes `--help` for
flash-attention, jinja, reasoning and template-kwargs support), real tokens/second, the sshd
`PermitListen` rule on your VPS's OpenSSH, the LiteLLM and OpenHands image tags, and whether
OpenHands 1.8 picks up the settings exactly as listed. Pin image tags after the first good run.
The first session is a shakedown: run it with `SESSION_MAX_HOURS=1`.

## Sources

* [Kaggle Terms of Use (22 Jun 2025)](https://www.kaggle.com/terms)
* [Kaggle forum: tutorial wave converting notebooks into free LLM servers](https://www.kaggle.com/discussions/product-feedback/743895)
* [Kaggle forum: TPU interactive sessions and LLM hosting abuse](https://www.kaggle.com/discussions/product-feedback/745847)
* [Free 35B LLM server on Kaggle (llama.cpp, dual T4, gotchas)](https://dev.to/tahsine/free-35b-multimodal-llm-server-on-kaggle-gpu-accessible-from-any-openai-compatible-client-4m2h)
* [Kaggle free tier limits (agentdeals)](https://agentdeals.dev/vendor/kaggle)
* [Best open-source coding models 2026 (Morph)](https://www.morphllm.com/best-open-source-coding-model-2026)
* [Best open-source models for autonomous coding agents (Modal)](https://modal.com/resources/best-open-source-models-autonomous-coding-agents)
* [Qwen/Qwen3.8-27B model card](https://hf.co/Qwen/Qwen3.8-27B) and [unsloth/Qwen3.8-27B-GGUF](https://hf.co/unsloth/Qwen3.8-27B-GGUF)
* [OpenHands: local LLMs](https://docs.openhands.dev/modules/usage/llms/local-llms) and [skills](https://docs.openhands.dev/overview/skills)
* [Self-hosted deep research systems compared](https://dev.to/rosgluk/self-hosted-deep-research-systems-12-tools-compared-7pp)
