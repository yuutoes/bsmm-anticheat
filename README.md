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

The PC check also uses evidence that renaming or deleting a cheat does not remove:

- **Code inside programs**: executor Lua functions, Roblox engine internals used by externals,
  KeyAuth loader servers, protectors such as Themida/VMProtect, and the executor
  `autoexec` + `workspace` folder layout, in files and in running (unsigned) programs
- **Program traces in Windows' own memory** (Diagnostic Policy Service, Program Compatibility
  Assistant, Task Scheduler, Explorer), kept since the last restart
- **The NTFS change journal**: deleted, renamed or swapped programs, Prefetch wipes, kernel-driver drops
- **Long-term history**: Amcache (with file hashes), SRUM (about 30 days of app use) and Defender's
  activity log
- **Tampering**: frozen, stopped or disabled logging services, a deleted change journal, and hooks or
  redirects aimed at this check
- **AI aimbots and input hardware**: screen-capture + AI libraries, model files, Arduino-style boards
  and KMBox/MAKCU-style input boxes
- **Kernel protection**: Secure Boot, Vulnerable Driver Blocklist and Memory Integrity

And it checks for the tricks used to get past screenshare tools:

- **Borrowed or fake signatures**: signatures copied onto modified files, fake "Roblox"/"Microsoft"
  signers, self-made root certificates, stolen or leaked publisher certificates (including the 2022
  NVIDIA leak), Roblox-signed programs used to side-load a cheat DLL, and rerouted Windows signature
  checking
- **Code hidden inside other programs**: hollowed processes, program images loaded without a file,
  threads running code that belongs to no file, unsigned DLLs inside signed programs
- **Roblox bridges and proxies**: Roblox connected to a local program (how executors like Xeno talk
  to Roblox), the Fleasion proxy, Roblox certificate pinning switched off, and DLLs Roblox's own
  anti-cheat blocked (from Roblox's logs)
- **Kernel tells**: kernel debugger, processes hidden from the process list, test-signing reported by
  the kernel, PatchGuard crashes, drivers signed with fake-timestamp tools, AMSI/ETW patching
- **Hardware and capture**: hidden hypervisors, broken or driverless PCIe devices (DMA cards),
  programs that used Windows screen capture, input filter drivers and MAKCU-style serial devices
- **Hidden files and wiped evidence**: programs hidden in NTFS data streams, a recreated change
  journal, disabled event logs and deny rules that stop Windows recording program runs

A full PC check takes about 3 to 4 minutes.

### Live monitor

The live monitor first runs a deep scan of the PC as it is (about a minute), then during the match
watches for:

- programs started mid-match, checked for cheat code, copied signatures and USB/network origins
- Roblox launched from a fake or unsigned file, or with DLLs planted next to it
- Roblox connecting to a local program or proxy, and DLLs Roblox's anti-cheat blocks
- injected code in new programs, kernel debugger and hidden processes
- frozen or stopped logging services, new PCIe devices, input boards and boxes
- deleted or renamed programs, new executor folders, driver drops and Prefetch wipes
- programs using screen capture, plus everything the original monitor already tracked

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

- reads the memory of a few Windows services and of running programs to look for cheat traces
  and injected code (never Roblox's memory)
- lists the PC's local network connections to see whether Roblox talks to a program on the same PC
  (nothing about your network is sent)
- makes a temporary Windows shadow copy with Microsoft's `esentutl` to read the locked Amcache and
  SRUM history files, and deletes its copies straight after
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
- League policy switches are at the top of `BSMM-Check.ps1` (`RequireSecureBoot`,
  `RequireDriverBlocklist`, `RequireMemoryIntegrity`): turn them on to make those settings a FAIL
  instead of a warning.
- Every report includes a **code fingerprint**. It is the same for every unmodified copy of a
  version, so a different value means the player ran an edited script.
- `relay/` holds the relay that keeps the Discord webhook secret. Setup steps: `relay/SETUP.md`.
- Shared settings (brand, colours, relay address, trust score weights, cheat names) are at the top
  of **both** scripts. Change them in both.
- Always match the report ID in Discord with the one on the player's recording.
