# BSMM relay setup

The relay is a small free Cloudflare Worker. The anti-cheat scripts send their reports to it, and it
forwards them to your Discord webhook. The webhook URL lives only inside Cloudflare, so the scripts
(and this folder) are safe to publish on GitHub.

Takes about 10 minutes. No programming tools needed.

## 1. Make a fresh Discord webhook

The old webhook was pasted into chats and test files, so replace it.

1. Discord: **Server Settings > Integrations > Webhooks**.
2. Delete the old BSMM webhook.
3. **New Webhook**, pick the staff channel for reports, then **Copy Webhook URL**. Keep it private.

## 2. Create the Worker

1. Sign up (free) at **dash.cloudflare.com**.
2. Go to **Workers & Pages > Create > Create Worker**. Choose the "Hello World" starter.
3. Name it `bsmm-relay` and click **Deploy**.
4. Click **Edit code**. Delete everything in the editor, paste the whole contents of `worker.js`, then click **Deploy**.

## 3. Give it the webhook (as a secret)

1. Open the Worker, go to **Settings > Variables and Secrets > Add**.
2. Type: **Secret**. Name: `WEBHOOK_URL`. Value: the webhook URL from step 1.
3. Save / Deploy.

## 4. Connect the scripts

1. Copy the Worker's address from its overview page. It looks like
   `https://bsmm-relay.<your-name>.workers.dev`.
2. Open it in a browser. You should see **BSMM relay OK**.
3. In **both** `BSMM-Check.ps1` and `BSMM-Monitor.ps1`, near the top, set:

   ```powershell
   RelayUrl          = 'https://bsmm-relay.<your-name>.workers.dev'
   ```

4. Upload the two scripts to GitHub. The `relay` folder can be public too; it contains no secrets.

## What the relay enforces

- Only BSMM reports get through. The first embed title must start with `BSMM`. If you rename
  your brand in the scripts, change `TITLE_PREFIX` at the top of `worker.js` to match.
- No @everyone or role pings, no images or links, and the sender name is always "BSMM Anti-Cheat".
- Attachments must be BSMM log files (`BSMM-XXXXXXXX-system-check.txt` / `-live-monitor.txt`), max 1 MB.
- Each live-monitor message can only be edited by the script run that created it.
- 20 requests per minute per IP address.

Anyone can still send a *fake* report to the relay, because the scripts are public. Always match
the report ID in Discord with the one shown on the player's recording.

## Changing the webhook later

Update the `WEBHOOK_URL` secret in Cloudflare. The scripts do not need to change.

## Optional: deploy from the command line

With Node.js installed, from this folder:

```powershell
npx wrangler login
npx wrangler secret put WEBHOOK_URL
npx wrangler deploy
```

This also turns on Cloudflare's global rate limit (configured in `wrangler.toml`), which is stricter
than the per-server counter the dashboard version uses.
