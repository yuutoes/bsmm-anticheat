# BSMM Anti-Cheat

The recording check for BSMM matches. It is open source so every player can see exactly what it
looks at and what it sends.

There are two scripts:

| Script | When | What it does |
|---|---|---|
| `BSMM-Check.ps1` | Whenever staff ask for a PC check, for example if a player is suspected of cheating | Scans the PC for cheats, recent cheat use and signs of a cleanup, then opens Process Explorer |
| `BSMM-Monitor.ps1` | During a match, when staff want a player watched | Watches for suspicious activity until you press Ctrl+C |

## How to run

Open **PowerShell as administrator** (right-click > Run as administrator).

**PC check**, when staff ask for one:

```powershell
iex (iwr "https://raw.githubusercontent.com/yuutoes/bsmm-anticheat/main/BSMM-Check.ps1" -UseBasicParsing).Content
```

**Live monitor**, if staff ask you to run it during a match (in its own admin window):

```powershell
iex (iwr "https://raw.githubusercontent.com/yuutoes/bsmm-anticheat/main/BSMM-Monitor.ps1" -UseBasicParsing).Content
```

Both ask for your Roblox username and show a **report ID** on screen. Keep the window visible to
staff (screen share or recording) until they have seen the result.

## What it checks

- Windows Defender status, exclusions, allowed threats and detection history
- Programs and modules attached to Roblox, Roblox install files, FastFlags, Bloxstrap/Fishstrap integrations
- Cheat files, folders and shortcuts, and where recent downloads came from
- Run history Windows keeps (BAM, Prefetch, launch logs) and signs it was cleaned
- Kernel drivers, vulnerable drivers, test-signing, Memory Integrity, DMA hardware
- Overlays, windows hidden from recording, macro tools, extra displays and virtual desktops
- UAC level, window animations, OBS scripts and scene-switch/pause hotkeys
- Virtual machines, Remote Desktop, hidden/encrypted drives

## What is sent to BSMM staff

Reports go to the BSMM relay (`relay/worker.js`, a Cloudflare Worker), which posts them to a staff
Discord channel.

**Sent:** the report ID, the Roblox username you type in, a trust score, the result of each check,
the details of checks that failed or need review, your Windows build, Roblox version, PC uptime and
whether the script ran as admin. During the match: the alerts the live monitor raises.

**Never sent:** your Windows user name or PC name (removed from every path before sending), file
contents, passwords or tokens, browsing history, the list of programs you ran, or USB device names.

Everything that is sent is also shown on your screen.

## Does it change anything on my PC?

The checks only read. The script itself:

- downloads Process Explorer from Microsoft (`download.sysinternals.com`), checks Microsoft's
  signature, and deletes it again when you close it
- writes its own log to `C:\ProgramData\bsmm_security_events.log`
- changes the colours and title of its own PowerShell window

## For BSMM staff

- **Getting the most out of a PC check:** have the player run it straight away, before they can
  close or delete anything, ideally with Roblox still open (memory readers, injected modules and
  overlays are only visible while they run), and always as administrator (without it the run
  history checks see nothing).
- A PC that looks clean but shows wiped run history, cleared event logs or a reset change journal
  should be treated as suspicious. Windows run history only goes back about a week.
- `relay/` holds the relay that keeps the Discord webhook secret. Setup steps: `relay/SETUP.md`.
- Shared settings (brand, colours, relay address, trust score weights, cheat names) are at the top
  of **both** scripts. Change them in both.
- Always match the report ID in Discord with the one on the player's recording.
