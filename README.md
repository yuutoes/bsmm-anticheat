# BSMM Anti-Cheat

The recording check for BSMM matches. It is open source so every player can see exactly what it
looks at and what it sends.

There are two scripts:

| Script | When | What it does |
|---|---|---|
| `BSMM-Check.ps1` | Whenever staff ask for a PC check, for example if a player is suspected of cheating | Scans the PC for cheats, recent cheat use and signs of a cleanup, then opens Process Explorer |
| `BSMM-Monitor.ps1` | During a match, when staff want a player watched | Watches for suspicious activity until you press Ctrl+C |

## How to run

Staff start a check with `/pccheck` in Discord and give you a **one-time command**. It works once,
for 10 minutes, and only for you.

Open **PowerShell as administrator** (right-click > Run as administrator), paste the whole line and
press Enter. For a live monitor, do the same in its own admin window and leave it open for the match.

The scripts cannot be started from this page: without a command from staff they stop straight away.
The window shows a **report ID**. Results go to staff and are not listed on your screen.

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
- **Cheat menus after they are closed**: the `imgui.ini` settings file most cheat menus leave
  behind, and its creation or deletion in the change journal
- **Roblox accounts**: the accounts used on the PC and the games last joined, and Roblox logs or
  saved accounts that were wiped although Roblox was used recently

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
- programs using screen capture, new cheat menu settings files, plus everything the original
  monitor already tracked

## What is sent to BSMM staff

Reports go to the BSMM relay (`relay/worker.js`, a Cloudflare Worker). It only accepts a report
for a check staff started, works out the verdict itself, posts a summary to a staff Discord channel
and keeps the full report for staff for 90 days.

**Sent:** the report ID, the result of each check with the details of anything that failed or
needs review, your Windows build, Roblox version, PC uptime and whether the script ran as admin.
The Roblox user IDs of the accounts used on this PC and the games they last joined (IDs and times
from Roblox's own logs and account list). When programs were run on this PC (path, time and whether
the file is signed), so staff can compare it with your match times. A one-way hash of hardware
serial numbers, used to recognise the same PC again; the serial numbers themselves are not sent.
During a match: the alerts the live monitor raises.

**Never sent:** your Windows user name or PC name (removed from every path before sending), file
contents, passwords, Roblox cookies or login tokens (the script never opens them), browsing history
or USB device names.

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
- The relay hands out the script itself and knows which version it gave and which checks that
  version runs, so a report that leaves checks out, finishes too fast or names another version is
  marked as untrusted.
- Checks are started with `/pccheck` (admins and the security role). Each command is tied to one
  player, works once and expires after 10 minutes.
- `relay/` holds the relay. It keeps the Discord webhook and issues the API keys. Setup steps: `relay/SETUP.md`.
- Shared settings (brand, colours, cheat names, league policy) are at the top of **both** scripts.
  Change them in both. The trust score is worked out by the relay (`WEIGHTS` in `relay/worker.js`).
- Players do not see results, so a report ID read out by the player only tells you which report is theirs.
