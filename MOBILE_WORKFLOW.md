# Mobile Workflow

How to use this workspace from an iPhone, iPad, or Android device.

## Setup on Mobile

### iOS (iPhone / iPad)

**Recommended browser**: Safari or Chrome (both support the code-server web IDE)

1. Open Safari → navigate to `https://coding.cairnscustomcomputers.cloud`
2. Complete Cloudflare Access email OTP
3. You're in the IDE. Tap the hamburger menu to open the file explorer.

**For a better experience on iPhone:**
- Add to Home Screen (share button → "Add to Home Screen") — runs in standalone mode, more screen space
- Use a hardware Bluetooth keyboard (dramatically improves typing speed)
- Enable "Desktop website" in Safari for the full editor layout

**Recommended apps:**
- [Working Copy](https://workingcopyapp.com/) — Git client for reviewing diffs and browsing code
- [SSH Files](https://apps.apple.com/app/ssh-files/id402699023) — SSH + SFTP for direct VPS file access
- [Prompt 3](https://panic.com/prompt/) — SSH terminal for VPS management
- [iSH](https://ish.app/) — Linux shell on iOS for running local scripts

### Android

1. Open Chrome → navigate to `https://coding.cairnscustomcomputers.cloud`
2. Complete Cloudflare Access email OTP
3. Tap the three-dot menu → "Add to Home screen" for PWA install

**Recommended apps:**
- [Termux](https://termux.dev/) — full Linux terminal (can run aider locally on device)
- [JuiceSSH](https://juicessh.com/) — SSH terminal
- [MGit](https://manichord.com/projects/mgit.html) — Git client

---

## Mobile-Optimised Keyboard Shortcuts

code-server key bindings that work well on mobile (especially with Bluetooth keyboard):

| Action | Shortcut |
|--------|----------|
| Command palette | Ctrl+Shift+P |
| Toggle terminal | Ctrl+` |
| Split editor | Ctrl+\ |
| Go to file | Ctrl+P |
| Find in files | Ctrl+Shift+F |
| Format document | Shift+Alt+F |
| Save | Ctrl+S |
| Undo | Ctrl+Z |
| Redo | Ctrl+Shift+Z |

For touchscreen-only operation, use the VS Code context menus (long-press or right-click equivalent).

---

## Phone-First Agent Workflow

The recommended mobile workflow minimises typing by letting the AI do most of the work.

### Typical session from phone

```
1. Open IDE in browser
2. Open terminal (Ctrl+`)
3. cd /opt/coding-workspace/repos/PROJECT
4. git pull

5. Start agent:
   claude   (or: aider FILE1 FILE2)

6. Type your intent in plain English:
   "Add input validation to the registration form.
    Fields: email (must be valid), password (min 8 chars, 1 uppercase, 1 number).
    Show inline errors below each field."

7. Review the diff the agent proposes
8. Accept or edit

9. git add -A && git commit -m "feat: form validation" && git push
```

### Voice input trick (iOS)

1. Tap the microphone on the iOS keyboard
2. Dictate your intent
3. iOS transcribes it into the terminal / chat input
4. Works surprisingly well for longer prompts

### Using Working Copy (iOS) for code review

When you want to review changes without full IDE:
1. Working Copy → pull repo
2. Browse changed files
3. Tap a file → see diff view
4. Add a comment or commit message directly from the app

---

## Kaggle GPU from Mobile

Starting a Kaggle session from your phone:

1. Open [kaggle.com](https://kaggle.com) in mobile browser
2. Navigate to Notebooks → New Notebook
3. Top-right settings → Enable GPU accelerator (T4 × 1)
4. In Code cell, paste the one-liner setup (from `kaggle/KAGGLE_NOTEBOOK_SETUP.md`):

```python
!git clone https://github.com/YOUR_ORG/ccc-kaggle-agentic-workspace /tmp/ws && bash /tmp/ws/kaggle/setup_kaggle_gpu_worker.sh
```

5. Run it, then run the tunnel script in the next cell
6. Switch back to your IDE browser tab — GPU is now available

The Kaggle mobile site is usable but clunky. Consider keeping a second browser tab open for Kaggle on your phone while the IDE is in the main tab.

---

## Low-Bandwidth Mode

If on mobile data (3G/4G with low signal):

1. Use `vscode-minimal` theme to reduce rendering overhead
2. Disable file explorer auto-refresh: Settings → `files.autoSave: off`
3. Close all unused editor tabs
4. Prefer terminal-based agents (aider in terminal) over web-UI agents
5. Use GitHub mobile app for PR review instead of IDE

---

## Screen Size Optimisation

### iPhone (small screen)

- Use split view: terminal on one side, file on the other
- Set font size to 11px: Settings → Editor: Font Size → 11
- Use the minimap (Ctrl+Shift+P → "Toggle Minimap") to navigate large files quickly
- Use `Ctrl+P` (go to file) instead of sidebar navigation

### iPad (recommended for mobile coding)

- Full code-server layout works well in landscape
- Use Stage Manager (iPad OS 16+) to run IDE side-by-side with a notes app
- Enable the iPad external keyboard shortcuts (Cmd replaces Ctrl in some bindings)
- Drag-and-drop files from Files app into the IDE works

---

## Connectivity and Offline

The workspace requires internet access to reach the VPS. For offline resilience:

- **Working Copy** (iOS): pull repos when online, edit locally, push when reconnected
- **Termux** (Android): full local development environment, git push when reconnected
- **Caching**: code-server caches the UI locally; you can browse cached files offline but can't save

For flights or poor connectivity:
1. Before going offline: `git push && bash scripts/backup_workspace.sh`
2. Work locally on your device using Working Copy / Termux
3. On reconnection: push local changes, pull on VPS

---

## Notifications (Optional)

Configure the session watchdog to send you a push notification when the Kaggle session is about to expire:

1. Create a free [ntfy.sh](https://ntfy.sh) account
2. Install ntfy app on your phone and subscribe to a topic (e.g., `ccc-workspace-kaggle`)
3. Add to VPS `.env`:
   ```
   ALERT_WEBHOOK_URL=https://ntfy.sh/YOUR_TOPIC
   ```
4. The watchdog will POST to this URL 30 minutes before Kaggle session expires

You'll get a push notification to your phone: "Kaggle GPU session expiring in 30 min — saving state".
