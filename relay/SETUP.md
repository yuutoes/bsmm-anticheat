# BSMM relay setup

The relay is a small free Cloudflare Worker. It hands the anti-cheat scripts to players through
one-time commands, accepts their signed reports, works out the verdict, posts a summary to your
Discord webhook and keeps the full reports for the staff website.

The webhook URL and the API keys live only inside Cloudflare, so the scripts (and this folder) are
safe to publish on GitHub.

Takes about 15 minutes.

## 1. Make a fresh Discord webhook

The old webhook was pasted into chats and test files, so replace it.

1. Discord: **Server Settings > Integrations > Webhooks**.
2. Delete the old BSMM webhook.
3. **New Webhook**, pick the staff channel for reports, then **Copy Webhook URL**. Keep it private.

## 2. Create the database and the Worker

1. Sign up (free) at **dash.cloudflare.com**.
2. **Storage & Databases > D1 > Create**. Name it `bsmm-relay`. The tables are created by the relay
   itself the first time you use it.
3. **Workers & Pages > Create > Create Worker**. Choose the "Hello World" starter, name it
   `bsmm-relay` and click **Deploy**.
4. Click **Edit code**. Delete everything in the editor, paste the whole contents of `worker.js`,
   then click **Deploy**.
5. Open the Worker, **Settings > Bindings > Add > D1 database**. Variable name: `DB`. Database:
   `bsmm-relay`.
6. **Settings > Variables and Secrets > Add**. Type: **Secret**. Name: `ADMIN_SECRET`. Value: a long
   random text of at least 32 characters. This is the only thing that can create API keys, so keep
   it to yourself. PowerShell makes one with:

   ```powershell
   -join ((1..48) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
   ```

7. Copy the Worker's address from its overview page. It looks like
   `https://bsmm-relay.<your-name>.workers.dev`. Open it in a browser: you should see
   **BSMM relay OK**.

## 3. Create your API key

Run this in PowerShell with your own values. `view_url` is optional: it is the staff page on your
website, and adds a "Full report" link to each Discord message.

```powershell
$admin = 'YOUR-ADMIN-SECRET'
$body = @{
    name        = 'BSMM'
    webhook_url = 'https://discord.com/api/webhooks/...'
    view_url    = 'https://your-website/staff/pc-checks'
} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri 'https://bsmm-relay.<your-name>.workers.dev/admin/keys' `
    -Headers @{ Authorization = "Bearer $admin" } -ContentType 'application/json' -Body $body
```

The answer contains the `key` (it starts with `bsmm_`). It is shown **once**: the relay only stores
a hash of it.

## 4. Connect the bot and the website

Set these two values in the bot's `.env` and in the website's environment, then restart both:

```
ANTICHEAT_RELAY_URL=https://bsmm-relay.<your-name>.workers.dev
ANTICHEAT_API_KEY=bsmm_...
```

Staff then start a check with `/pccheck` in Discord. The scripts themselves need no settings: the
relay tells each run where to report.

By default the relay reads the scripts from this GitHub repository. To read them from somewhere
else, add a variable `SCRIPT_BASE_URL` with the address of the folder that holds both `.ps1` files.

## Giving a key to another league

Repeat step 3 with their name and their own webhook. They get their own key, their reports go to
their own channel, and they can only see their own checks. Their bot calls:

```
POST /v1/checks        Authorization: Bearer <their key>
{ "mode": "check" or "monitor", "roblox_id": "...", "player": "...", "requested_by": "...",
  "matches": [{ "id": "...", "started_at": <unix seconds>, "ended_at": <unix seconds> }] }
```

and gets back the one-time `command` to give the player. All fields are optional.

To see the keys or switch one off:

```powershell
Invoke-RestMethod -Uri 'https://bsmm-relay.<your-name>.workers.dev/admin/keys' -Headers @{ Authorization = "Bearer $admin" }
Invoke-RestMethod -Method Delete -Uri 'https://bsmm-relay.<your-name>.workers.dev/admin/keys/<id>' -Headers @{ Authorization = "Bearer $admin" }
```

## What the relay enforces

- A check can only be started with a valid API key. Keys are 256 random bits, cannot be guessed
  and can only be created with the admin secret.
- A one-time command downloads the script once, within 10 minutes, and only to PowerShell.
- Each run gets its own signing key. A report is accepted once, only if its signature matches, and
  only within 45 minutes of the download (8 hours for a live monitor).
- The verdict is worked out by the relay, not by the player's PC. Reports that leave checks out,
  finish too fast or come from another script version are marked as untrusted.
- What the PC reports is compared with what the relay already knows: the Roblox account staff asked
  about, earlier reports from the same player and the same PC, and the player's match times.
- No @everyone or role pings reach Discord, and the sender name is always "BSMM Anti-Cheat".
- 20 requests per minute per IP address from players' PCs, 30 new checks per minute per API key.
- Reports are deleted after 90 days.

The scripts are public and the signing key is on the player's PC while the script runs, so a
determined player can still write a program that sends a made-up report. The relay makes that slow
and easy to get wrong (missing checks, wrong timing, a history that does not match the last report),
but a clean report is evidence, not proof.

## Changing the webhook later

Create a new key with the new webhook (step 3), put it in the bot and the website, then switch the
old key off.

## Optional: deploy from the command line

With Node.js installed, from this folder:

```powershell
npx wrangler login
npx wrangler d1 create bsmm-relay      # paste the id it prints into wrangler.toml
npx wrangler secret put ADMIN_SECRET
npx wrangler deploy
```

This also turns on Cloudflare's global rate limit (configured in `wrangler.toml`), which is stricter
than the per-server counter the dashboard version uses.
