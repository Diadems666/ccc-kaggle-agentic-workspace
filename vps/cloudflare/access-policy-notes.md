# Cloudflare Access Policy Setup

Step-by-step guide to protecting the coding subdomain with Cloudflare Access.

## What is Cloudflare Access?

Cloudflare Access sits in front of your coding IDE and requires users to authenticate before they can reach it. Authentication uses a one-time code sent to your email — no passwords, no VPN, no app install required.

## Setup Steps

### 1. Create the Cloudflare Tunnel

1. Go to [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com)
2. Navigate to: Networks → Tunnels → Create a tunnel
3. Choose "Cloudflared" as connector type
4. Name it: `ccc-coding-workspace`
5. Follow the install instructions — or copy the token and put it in your VPS `.env`:
   ```
   CLOUDFLARE_TUNNEL_TOKEN=eyJ...
   ```
6. In the tunnel's Public Hostname tab, add:
   - Subdomain: `coding`
   - Domain: `cairnscustomcomputers.cloud`
   - Service: `http://localhost:8080`

### 2. Configure DNS

In Cloudflare DNS for `cairnscustomcomputers.cloud`:
- Type: CNAME
- Name: `coding`
- Target: `YOUR_TUNNEL_ID.cfargotunnel.com`
- Proxy status: Proxied (orange cloud)

This is handled automatically if you configure the tunnel via the dashboard.

### 3. Create an Access Application

1. Zero Trust → Access → Applications → Add an application
2. Choose: Self-hosted
3. Fill in:
   - **Application name**: CCC Coding Workspace
   - **Session duration**: 24 hours (or your preference)
   - **Application domain**: `coding.cairnscustomcomputers.cloud`
4. Click Next

### 4. Create an Access Policy

On the policy configuration screen:
- **Policy name**: Allow Owner
- **Action**: Allow
- Add a rule:
  - Selector: **Emails**
  - Value: `joe.venner@hotmail.com` (your email address)

Click Save.

### 5. Verify

Navigate to `https://coding.cairnscustomcomputers.cloud` from any browser.

You should see a Cloudflare Access login page asking for your email. Enter it, check your email for the OTP, enter it, and you're in.

## Security Notes

- The OTP is valid for 10 minutes
- The session cookie lasts for the configured session duration (default 24h)
- If you need to revoke access immediately: Zero Trust → Access → Revoke Session
- Adding multiple emails: add more "Emails" rules or use an email domain rule

## Troubleshooting

### "Access Denied" after correct OTP

Check that the email you entered exactly matches the email in the policy.

### "1033 Argo Tunnel error"

cloudflared is running but code-server is not responding. Check:
```bash
sudo systemctl status code-server
```

### "526 SSL Error"

Usually means cloudflared isn't running or can't connect. Check:
```bash
sudo systemctl status cloudflared
journalctl -u cloudflared -f
```

## Multiple Users

To give another person access:
1. Zero Trust → Access → Applications → your app → Policies → Edit
2. Add another Emails rule with their address
3. Or: create an "Allow" rule with Selector: **Email Domain** = `yourdomain.com` for team access
