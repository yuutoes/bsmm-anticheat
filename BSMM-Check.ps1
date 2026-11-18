[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:PSDefaultParameterValues = @{}
foreach ($__n in @(
    'Invoke-WebRequest','Invoke-RestMethod','Invoke-Expression','Test-Path','Get-Item',
    'Get-ChildItem','Get-ItemProperty','Get-ItemPropertyValue','Get-CimInstance','Get-WmiObject',
    'Get-Process','Start-Process','Get-Service','Get-WinEvent','Get-AuthenticodeSignature',
    'Get-Module','New-Item','Remove-Item','Add-Content'
)) {
    Microsoft.PowerShell.Management\Remove-Item -Path "Alias:\$__n"    -Force -ErrorAction SilentlyContinue
    Microsoft.PowerShell.Management\Remove-Item -Path "Function:\$__n" -Force -ErrorAction SilentlyContinue
}

Clear-Host

# =============================================================================
#   BSMM ANTI-CHEAT  -  PC Check
#   Run before the match. The live monitor is the separate BSMM-Monitor.ps1 script.
#
#   BRAND SETTINGS: edit this block to restyle the whole tool.
#   Colours are hex (#RRGGBB). "Fallback" is one of the 16 classic console
#   colours and is only used on very old consoles without true-colour support.
# =============================================================================
$script:Brand = @{
    Name    = 'BSMM'
    Product = 'Anti-Cheat'
    Mode    = 'PC check'
    Version = '1.0.0'
    Website = ''                     # optional, e.g. 'discord.gg/yourserver' - shown beside the logo
}

$script:Palette = @{
    Brand1 = @{ Hex = '#8B5CF6'; Fallback = 'Magenta' }       # logo gradient start + main accent
    Brand2 = @{ Hex = '#22D3EE'; Fallback = 'Cyan' }          # logo gradient end
    Shadow = @{ Hex = '#4C3A8A'; Fallback = 'DarkMagenta' }   # logo shadow lines
    Text   = @{ Hex = '#F5F5F7'; Fallback = 'White' }         # headings
    Body   = @{ Hex = '#C9C9D1'; Fallback = 'Gray' }          # normal text
    Muted  = @{ Hex = '#80808C'; Fallback = 'DarkGray' }      # secondary text
    Line   = @{ Hex = '#3C3C48'; Fallback = 'DarkGray' }      # rules and empty bar cells
    Pass   = @{ Hex = '#34D399'; Fallback = 'Green' }
    Warn   = @{ Hex = '#FBBF24'; Fallback = 'Yellow' }
    Fail   = @{ Hex = '#FB4D6D'; Fallback = 'Red' }
    Info   = @{ Hex = '#7AA2F7'; Fallback = 'DarkCyan' }
    Ink    = @{ Hex = '#0E0E14'; Fallback = 'Black' }         # text drawn on coloured badges
}

# --- Discord report ----------------------------------------------------------
# Reports go to your BSMM relay (relay/worker.js on Cloudflare), which forwards them to Discord.
# The Discord webhook is stored only on the relay, so this script is safe to publish.
# User names, the PC name and URL tokens are stripped before anything is sent.
$script:Report = @{
    RelayUrl          = 'https://bsmm-relay.yourgaydad2020.workers.dev'    # your BSMM relay (Cloudflare Worker)
    AskPlayerName     = $true    # ask for the player's Roblox username at the start (shown on screen and in the report)
    LiveUpdateSeconds = 120      # how often the live-monitor message is refreshed (keep >= 60 for Discord rate limits)
    AttachFullLog     = $true    # attach the full anonymised log as a .txt file
}

# --- League policy -----------------------------------------------------------
$script:Policy = @{
    MaxUptimeMinutes = 0         # e.g. 10 = warn if the PC was not restarted shortly before the check. 0 = off
}

# --- Trust score (starts at 100, these are subtracted) ------------------------
$script:TrustWeights = @{
    FailSection = 18; FailCap = 60     # per check that FAILED, up to the cap
    WarnSection = 4;  WarnCap = 28     # per check with warnings, up to the cap
    NotAdmin    = 10                   # checks could not run fully
    LiveFail    = 10; LiveWarn = 3; LiveCap = 40   # alerts raised during the live monitor
}

$script:BsmmVersion = $script:Brand.Version
$script:ReportId = 'BSMM-' + (([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')).ToUpper() -replace '[01]', '').Substring(0, 8)
$script:PlayerName = ''
$script:MonitorLog = New-Object System.Collections.Generic.List[string]

# =============================================================================
#   Console UI engine - nothing below needs editing to rebrand.
#   The source stays plain ASCII; box/block characters are built at runtime so
#   the script renders correctly whether it is saved to disk or piped to iex.
# =============================================================================
$script:Esc       = [string][char]27
$script:AnsiReset = "$([char]27)[0m"
$script:UseAnsi   = $false
$script:ConsoleWidth = 100
$script:UiWidth   = 76
$script:G = @{
    Block = [string][char]0x2588; Shade = [string][char]0x2591; H = [string][char]0x2500; V = [string][char]0x2502
    TL    = [string][char]0x250C; TR    = [string][char]0x2510; BL = [string][char]0x2514; BR = [string][char]0x2518
    Bar   = [string][char]0x258C; Dot   = [string][char]0x25CF; Ring = [string][char]0x25CB; Mid = [string][char]0x00B7
    Next  = [string][char]0x203A
    DH    = [string][char]0x2550; DV    = [string][char]0x2551; DTL = [string][char]0x2554; DTR = [string][char]0x2557
    DBL   = [string][char]0x255A; DBR   = [string][char]0x255D
}

# "BSMM" in block letters. '#' = solid block, the other symbols are the shadow lines.
$script:LogoRows = @(
    '######7 #######7###7   ###7###7   ###7',
    '##F==##7##F====J####7 ####!####7 ####!',
    '######FJ#######7##F####F##!##F####F##!',
    '##F==##7L====##!##!L##FJ##!##!L##FJ##!',
    '######FJ#######!##! L=J ##!##! L=J ##!',
    'L=====J L======JL=J     L=JL=J     L=J'
)

$script:Steps = @('System check', 'Process Explorer')

function ConvertFrom-BsmmHex {
    param([string]$Hex)
    try {
        $h = $Hex.Trim().TrimStart('#')
        return @([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16))
    } catch {
        return @(200, 200, 200)
    }
}

function Get-BsmmFg { param([int[]]$C) return "$script:Esc[38;2;$($C[0]);$($C[1]);$($C[2])m" }
function Get-BsmmBg { param([int[]]$C) return "$script:Esc[48;2;$($C[0]);$($C[1]);$($C[2])m" }

$script:Rgb = @{}
$script:AnsiFg = @{}
$script:AnsiBg = @{}
foreach ($__k in @($script:Palette.Keys)) {
    $script:Rgb[$__k] = ConvertFrom-BsmmHex $script:Palette[$__k].Hex
    $script:AnsiFg[$__k] = Get-BsmmFg $script:Rgb[$__k]
    $script:AnsiBg[$__k] = Get-BsmmBg $script:Rgb[$__k]
}

function Get-BsmmGradient {
    param([double]$T)
    if ($T -lt 0) { $T = 0 } elseif ($T -gt 1) { $T = 1 }
    $a = $script:Rgb['Brand1']; $b = $script:Rgb['Brand2']
    return @(
        [int]($a[0] + ($b[0] - $a[0]) * $T),
        [int]($a[1] + ($b[1] - $a[1]) * $T),
        [int]($a[2] + ($b[2] - $a[2]) * $T)
    )
}

function Initialize-BsmmConsole {
    try {
        if (-not ('BSMM.ConsoleApi' -as [type])) {
            Add-Type -Namespace BSMM -Name ConsoleApi -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@ -ErrorAction Stop
        }
    } catch {}

    # Turn off Quick Edit so a stray click cannot freeze the check mid-recording.
    try {
        $stdin = [BSMM.ConsoleApi]::GetStdHandle(-10)
        [uint32]$mode = 0
        if ([BSMM.ConsoleApi]::GetConsoleMode($stdin, [ref]$mode)) {
            $mode = ($mode -bor 0x0080) -band (-bnot 0x0040) -band (-bnot 0x0020)
            [void][BSMM.ConsoleApi]::SetConsoleMode($stdin, $mode)
        }
    } catch {}

    # Enable true-colour output (Windows 10 1703+ console and Windows Terminal).
    $ansi = $false
    if ($Host.Name -eq 'ConsoleHost') {
        try {
            $stdout = [BSMM.ConsoleApi]::GetStdHandle(-11)
            [uint32]$outMode = 0
            if ([BSMM.ConsoleApi]::GetConsoleMode($stdout, [ref]$outMode)) {
                if (($outMode -band 0x0004) -ne 0) {
                    $ansi = $true
                } elseif ([BSMM.ConsoleApi]::SetConsoleMode($stdout, [uint32]($outMode -bor 0x0004))) {
                    $ansi = $true
                }
            }
        } catch {}
        if (-not $ansi -and $env:WT_SESSION) { $ansi = $true }
    }
    if ($env:BSMM_PLAIN -eq '1') { $ansi = $false }
    $script:UseAnsi = $ansi

    try { if ([Console]::WindowWidth -gt 20) { $script:ConsoleWidth = [Console]::WindowWidth } } catch {}
    $script:UiWidth = [Math]::Max(56, [Math]::Min(96, $script:ConsoleWidth - 4))

    try {
        $Host.UI.RawUI.BackgroundColor = 'Black'
        $Host.UI.RawUI.ForegroundColor = 'Gray'
    } catch {}
    try { $Host.UI.RawUI.WindowTitle = "$($script:Brand.Name) $($script:Brand.Product) v$($script:Brand.Version) - $($script:Brand.Mode)" } catch {}
}

function Invoke-ConsoleRefresh {
    try { [Console]::Out.Flush() } catch {}
    try { [Console]::Error.Flush() } catch {}
}

# Real locations of Desktop / Downloads / Documents. With OneDrive backup (the Windows 11 default)
# they live under %OneDrive%, not %USERPROFILE%, so every place is returned, existing ones only.
$script:UserFolderCache = @{}
function Get-BsmmUserFolders {
    param([string]$Name)
    if ($script:UserFolderCache.ContainsKey($Name)) { return $script:UserFolderCache[$Name] }
    $out = New-Object System.Collections.Generic.List[string]
    $candidates = @()
    $valueName = @{ Desktop = 'Desktop'; Downloads = '{374DE290-123F-4565-9164-39C4925E467B}'; Documents = 'Personal' }[$Name]
    try {
        $usf = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop
        $candidates += [string]$usf.$valueName
    } catch {}
    if ($Name -eq 'Desktop') { $candidates += [Environment]::GetFolderPath('Desktop'); $candidates += (Join-Path $env:PUBLIC 'Desktop') }
    if ($Name -eq 'Documents') { $candidates += [Environment]::GetFolderPath('MyDocuments') }
    $candidates += (Join-Path $env:USERPROFILE $Name)
    foreach ($od in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) { if ($od) { $candidates += (Join-Path $od $Name) } }
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $p = [Environment]::ExpandEnvironmentVariables($c).TrimEnd('\')
        if ($p -and -not $out.Contains($p) -and (Test-Path -LiteralPath $p -PathType Container)) { $out.Add($p) }
    }
    $script:UserFolderCache[$Name] = $out.ToArray()
    return $script:UserFolderCache[$Name]
}

# Writes one coloured piece of text. Tokens are the keys of $script:Palette.
function Out-Seg {
    param([string]$Text = '', [string]$Fg = 'Body', [string]$Bg = '', [switch]$Bold, [switch]$NoNewline)
    if ($script:UseAnsi) {
        $seq = ''
        if ($Bold) { $seq += "$script:Esc[1m" }
        if ($Fg -and $script:AnsiFg.ContainsKey($Fg)) { $seq += $script:AnsiFg[$Fg] }
        if ($Bg -and $script:AnsiBg.ContainsKey($Bg)) { $seq += $script:AnsiBg[$Bg] }
        Write-Host ($seq + $Text + $script:AnsiReset) -NoNewline:$NoNewline
        return
    }
    $p = @{ Object = $Text; NoNewline = [bool]$NoNewline }
    if ($Fg -and $script:Palette.ContainsKey($Fg)) { $p['ForegroundColor'] = $script:Palette[$Fg].Fallback }
    if ($Bg -and $script:Palette.ContainsKey($Bg)) { $p['BackgroundColor'] = $script:Palette[$Bg].Fallback }
    Write-Host @p
}

function Out-Gradient {
    param([string]$Text, [switch]$Bold, [switch]$NoNewline)
    if (-not $script:UseAnsi) { Out-Seg $Text -Fg 'Brand1' -NoNewline:$NoNewline; return }
    $sb = New-Object System.Text.StringBuilder
    if ($Bold) { [void]$sb.Append("$script:Esc[1m") }
    $n = [Math]::Max(1, $Text.Length - 1)
    for ($i = 0; $i -lt $Text.Length; $i++) {
        [void]$sb.Append((Get-BsmmFg (Get-BsmmGradient ($i / $n)))).Append($Text[$i])
    }
    [void]$sb.Append($script:AnsiReset)
    Write-Host $sb.ToString() -NoNewline:$NoNewline
}

function Get-StatusToken {
    param([string]$Status)
    switch ($Status) {
        'PASS' { return 'Pass' }
        'FAIL' { return 'Fail' }
        'WARN' { return 'Warn' }
        'INFO' { return 'Info' }
        default { return 'Brand1' }
    }
}

# A 6-character status chip: " PASS " on a coloured background, or [PASS] on old consoles.
function Out-Badge {
    param([string]$Status, [switch]$NoNewline)
    $tok = Get-StatusToken $Status
    if ($script:UseAnsi) {
        Out-Seg (' ' + $Status.PadRight(4) + ' ') -Fg 'Ink' -Bg $tok -Bold -NoNewline:$NoNewline
    } else {
        Out-Seg ('[' + $Status.PadRight(4) + ']') -Fg $tok -NoNewline:$NoNewline
    }
}

function Out-Rule {
    param([string]$Token = 'Line')
    Out-Seg ('  ' + ($script:G.H * $script:UiWidth)) -Fg $Token
}

# "  TITLE ----------------------------- right text"
function Out-Heading {
    param([string]$Title, [string]$Right = '')
    $t = $Title.ToUpper()
    $fill = $script:UiWidth - $t.Length - 1
    if ($Right) { $fill -= ($Right.Length + 1) }
    if ($fill -lt 3) { $fill = 3 }
    Out-Seg '  ' -NoNewline
    Out-Gradient $t -Bold -NoNewline
    Out-Seg (' ' + ($script:G.H * $fill)) -Fg 'Line' -NoNewline
    if ($Right) { Out-Seg (' ' + $Right) -Fg 'Muted' -NoNewline }
    Out-Seg ''
}

# Splits text into lines no wider than $Width, preferring to break at spaces and path separators.
function Split-UiText {
    param([string]$Text, [int]$Width)
    $out = New-Object System.Collections.Generic.List[string]
    if ($Width -lt 10) { $Width = 10 }
    $rest = [string]$Text
    $breaks = [char[]]@(' ', '\', '/', ',', ';', '-')
    while ($rest.Length -gt $Width) {
        $cut = $rest.LastIndexOfAny($breaks, $Width - 1)
        if ($cut -lt [int]($Width * 0.5)) { $cut = $Width - 1 }
        $out.Add($rest.Substring(0, $cut + 1).TrimEnd())
        $rest = $rest.Substring($cut + 1).TrimStart()
    }
    if ($rest.Length -gt 0 -or $out.Count -eq 0) { $out.Add($rest) }
    return $out.ToArray()
}

# "    FAIL  message that wraps
#           with a hanging indent"
function Out-TaggedText {
    param([string]$Indent = '  ', [string]$Time = '', [string]$Tag = 'NOTE', [string]$Text = '', [string]$TextToken = 'Body')
    $tok = Get-StatusToken $Tag
    $lead = $Indent.Length + 6
    if ($Time) { $lead += $Time.Length + 2 }
    $avail = [Math]::Max(20, $script:UiWidth + 2 - $lead)
    $first = $true
    foreach ($para in ([string]$Text -split "`r?`n")) {
        $p = $para.Trim()
        if (-not $p) { continue }
        foreach ($chunk in (Split-UiText -Text $p -Width $avail)) {
            if ($first) {
                Out-Seg $Indent -NoNewline
                if ($Time) { Out-Seg ($Time + '  ') -Fg 'Muted' -NoNewline }
                Out-Seg ($Tag.PadRight(4) + '  ') -Fg $tok -Bold -NoNewline
                $first = $false
            } else {
                Out-Seg (' ' * $lead) -NoNewline
            }
            Out-Seg $chunk -Fg $TextToken
        }
    }
    if ($first) {
        Out-Seg $Indent -NoNewline
        if ($Time) { Out-Seg ($Time + '  ') -Fg 'Muted' -NoNewline }
        Out-Seg $Tag.PadRight(4) -Fg $tok -Bold
    }
}

# A bordered panel. With -Numbered, each line gets a step number in the accent colour.
function Out-Card {
    param([string]$Title, [string[]]$Lines, [string]$Accent = 'Brand1', [switch]$Numbered)
    $W = $script:UiWidth
    $inner = $W - 4
    $t = ' ' + $Title.ToUpper() + ' '
    $topFill = [Math]::Max(1, $W - 3 - $t.Length)
    Out-Seg ('  ' + $script:G.TL + $script:G.H) -Fg $Accent -NoNewline
    Out-Seg $t -Fg 'Text' -Bold -NoNewline
    Out-Seg (($script:G.H * $topFill) + $script:G.TR) -Fg $Accent
    $n = 0
    foreach ($line in $Lines) {
        $n++
        $prefix = ''
        if ($Numbered) { $prefix = ([string]$n) + '  ' }
        $chunks = @(Split-UiText -Text $line -Width ($inner - $prefix.Length))
        for ($i = 0; $i -lt $chunks.Count; $i++) {
            Out-Seg ('  ' + $script:G.V + ' ') -Fg $Accent -NoNewline
            if ($Numbered) {
                if ($i -eq 0) { Out-Seg $prefix -Fg $Accent -Bold -NoNewline } else { Out-Seg (' ' * $prefix.Length) -NoNewline }
            }
            Out-Seg $chunks[$i].PadRight($inner - $prefix.Length) -Fg 'Body' -NoNewline
            Out-Seg (' ' + $script:G.V) -Fg $Accent
        }
    }
    Out-Seg ('  ' + $script:G.BL + ($script:G.H * ($W - 2)) + $script:G.BR) -Fg $Accent
}

function Show-BsmmLogo {
    $map = @{ '#' = $script:G.Block; '=' = $script:G.DH; '!' = $script:G.DV; 'F' = $script:G.DTL; '7' = $script:G.DTR; 'L' = $script:G.DBL; 'J' = $script:G.DBR }
    $side = @{}
    $side[1] = @{ Text = ($script:Brand.Product.ToUpper()); Fg = 'Text'; Bold = $true }
    $side[2] = @{ Text = $script:Brand.Mode; Fg = 'Body'; Bold = $false }
    $ver = "v$($script:Brand.Version)"
    if ($script:Brand.Website) { $ver += "  $($script:G.Mid)  $($script:Brand.Website)" }
    $side[3] = @{ Text = $ver; Fg = 'Muted'; Bold = $false }

    $width = $script:LogoRows[0].Length
    for ($r = 0; $r -lt $script:LogoRows.Count; $r++) {
        $row = $script:LogoRows[$r]
        if ($script:UseAnsi) {
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append('  ')
            for ($i = 0; $i -lt $row.Length; $i++) {
                $ch = [string]$row[$i]
                if ($ch -eq ' ') { [void]$sb.Append(' '); continue }
                if ($ch -eq '#') {
                    $t = (($i / [double]($width - 1)) * 0.85) + (($r / 5.0) * 0.15)
                    [void]$sb.Append((Get-BsmmFg (Get-BsmmGradient $t))).Append($script:G.Block)
                } else {
                    [void]$sb.Append($script:AnsiFg['Shadow']).Append($map[$ch])
                }
            }
            [void]$sb.Append($script:AnsiReset)
            Write-Host $sb.ToString() -NoNewline
        } else {
            Write-Host '  ' -NoNewline
            $i = 0
            while ($i -lt $row.Length) {
                $isBlock = ($row[$i] -eq '#')
                $buf = ''
                while ($i -lt $row.Length -and (($row[$i] -eq '#') -eq $isBlock)) {
                    $c = [string]$row[$i]
                    if ($c -eq ' ') { $buf += ' ' } else { $buf += $map[$c] }
                    $i++
                }
                $tok = 'Shadow'; if ($isBlock) { $tok = 'Brand1' }
                Out-Seg $buf -Fg $tok -NoNewline
            }
        }
        if ($side.ContainsKey($r)) {
            Out-Seg ('     ' + $side[$r].Text) -Fg $side[$r].Fg -Bold:$side[$r].Bold
        } else {
            Out-Seg ''
        }
    }
}

function Show-StepTracker {
    param([int]$Current)
    Out-Seg '  ' -NoNewline
    for ($i = 1; $i -le $script:Steps.Count; $i++) {
        $label = $script:Steps[$i - 1].ToUpper()
        if ($i -lt $Current) {
            Out-Seg ($script:G.Dot + ' ' + $label) -Fg 'Pass' -NoNewline
        } elseif ($i -eq $Current) {
            Out-Seg ($script:G.Dot + ' ') -Fg 'Brand2' -NoNewline
            Out-Seg $label -Fg 'Text' -Bold -NoNewline
        } else {
            Out-Seg ($script:G.Ring + ' ' + $label) -Fg 'Muted' -NoNewline
        }
        if ($i -lt $script:Steps.Count) { Out-Seg ('  ' + ($script:G.H * 4) + '  ') -Fg 'Line' -NoNewline }
    }
    Out-Seg ''
}

function Show-SessionMeta {
    $os = ''
    try {
        $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $os = "build $($cv.CurrentBuild).$($cv.UBR)"
    } catch {}
    $admin = $false
    try { $admin = Test-Admin } catch {}
    Out-Seg '  ' -NoNewline
    Out-Seg 'TIME ' -Fg 'Muted' -NoNewline
    Out-Seg (Get-Date -Format 'yyyy-MM-dd  HH:mm:ss') -Fg 'Text' -NoNewline
    if ($os) {
        Out-Seg '     WINDOWS ' -Fg 'Muted' -NoNewline
        Out-Seg $os -Fg 'Body' -NoNewline
    }
    Out-Seg '     ADMIN ' -Fg 'Muted' -NoNewline
    if ($admin) { Out-Seg 'YES' -Fg 'Pass' -Bold } else { Out-Seg 'NO' -Fg 'Fail' -Bold }
    Out-Seg '  REPORT ' -Fg 'Muted' -NoNewline
    Out-Seg $script:ReportId -Fg 'Brand2' -Bold -NoNewline
    if ($script:PlayerName) {
        Out-Seg '     PLAYER ' -Fg 'Muted' -NoNewline
        Out-Seg $script:PlayerName -Fg 'Text' -Bold -NoNewline
    }
    Out-Seg ''
}

function Write-StepHeader {
    param([int]$Step = 1, [switch]$NoClear)
    if (-not $NoClear) { Clear-Host }
    Out-Seg ''
    Show-BsmmLogo
    Out-Seg ''
    Show-StepTracker -Current $Step
    Out-Rule
    Show-SessionMeta
    Out-Rule
}

function Read-BsmmContinue {
    param([string]$Text)
    Out-Seg ''
    Out-Seg '  ' -NoNewline
    if ($script:UseAnsi) { Out-Seg (' ' + $script:G.Next + ' ') -Fg 'Ink' -Bg 'Brand1' -Bold -NoNewline }
    else { Out-Seg ('[' + $script:G.Next + ']') -Fg 'Brand1' -NoNewline }
    Out-Seg ('  ' + $Text) -Fg 'Text' -Bold -NoNewline
    Out-Seg '   press Enter' -Fg 'Muted'
    Read-Host | Out-Null
}

Initialize-BsmmConsole

try {
    if (-not ('BSMM.FastEntropy' -as [type])) {
        Add-Type -Namespace BSMM -Name FastEntropy -MemberDefinition @'
public static double Compute(string filePath) {
    if (!System.IO.File.Exists(filePath)) return 0.0;
    try {
        using (var fs = new System.IO.FileStream(filePath, System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.ReadWrite)) {
            int toRead = (int)System.Math.Min(fs.Length, 4194304L);
            if (toRead <= 0) return 0.0;
            byte[] buffer = new byte[toRead];
            int read = fs.Read(buffer, 0, toRead);
            if (read <= 0) return 0.0;
            int[] counts = new int[256];
            for (int i = 0; i < read; i++) {
                counts[buffer[i]]++;
            }
            double entropy = 0.0;
            double len = (double)read;
            for (int i = 0; i < 256; i++) {
                if (counts[i] > 0) {
                    double p = counts[i] / len;
                    entropy -= p * System.Math.Log(p, 2);
                }
            }
            return System.Math.Round(entropy, 3);
        }
    } catch {
        return -1.0;
    }
}
'@ -ErrorAction SilentlyContinue
    }
} catch {}

function Get-FileEntropy {
    param ([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return 0.0 }
    try {
        if ('BSMM.FastEntropy' -as [type]) {
            return [BSMM.FastEntropy]::Compute($FilePath)
        }
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        if ($bytes.Length -eq 0) { return 0.0 }
        $sampleLen = [Math]::Min($bytes.Length, 1048576)
        $byteCounts = @{}
        for ($i = 0; $i -lt $sampleLen; $i++) { $byteCounts[$bytes[$i]]++ }
        $entropy = 0.0
        $len = [double]$sampleLen
        foreach ($count in $byteCounts.Values) {
            $p = $count / $len
            $entropy -= $p * [Math]::Log($p, 2)
        }
        return [Math]::Round($entropy, 3)
    } catch {
        return -1.0
    }
}

function Get-SuspiciousHighEntropyFileAlerts {
    $alerts = @()
    
    $targetFolders = @(Get-BsmmUserFolders Downloads) + @(Get-BsmmUserFolders Desktop) + @(
        $env:TEMP,
        "$env:SystemDrive\"
    )

    $scannedFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($folder in $targetFolders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }

        $files = Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '(?i)^\.(exe|dll)$' -and $_.Length -gt 50KB -and $_.Length -lt 30MB } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 20

        foreach ($file in $files) {
            if (-not $scannedFiles.Add($file.FullName)) { continue }

            $entropy = Get-FileEntropy -FilePath $file.FullName
            if ($entropy -lt 7.20 -or $entropy -gt 7.95) { continue }

            if (Test-SignedByShippedRoot -Path $file.FullName) { continue }

            $kw = Get-MatchedCheatKeyword -Text $file.Name
            $kwTag = if ($kw) { " [$kw]" } else { "" }
            $alerts += "WARNING: High-entropy packed binary$kwTag [Entropy: $entropy] -> $($file.FullName)"
        }
    }

    if ($alerts.Count -eq 0) {
        $alerts += 'SUCCESS: No high-entropy packed binaries detected'
    }

    return @($alerts | Select-Object -Unique)
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Open-LocalMachineRegistryKey {
    param([string]$SubKeyPath)

    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        if ([string]::IsNullOrWhiteSpace($SubKeyPath)) { return $base }
        return $base.OpenSubKey($SubKeyPath)
    } catch {
        return $null
    }
}

function Add-RegistryKeyFingerprint {
    param(
        [Microsoft.Win32.RegistryKey]$Key,
        [string]$Prefix,
        [System.Collections.Generic.List[string]]$Parts
    )

    foreach ($name in $Key.GetValueNames()) {
        $raw = $Key.GetValue($name)
        if ($null -eq $raw) {
            $Parts.Add("$Prefix|$name=")
        } elseif ($raw -is [byte[]]) {
            $Parts.Add("$Prefix|$name=0x$([BitConverter]::ToString($raw).Replace('-', ''))")
        } else {
            $Parts.Add("$Prefix|$name=$raw")
        }
    }

    foreach ($subName in $Key.GetSubKeyNames()) {
        $subKey = $Key.OpenSubKey($subName)
        if ($subKey) {
            Add-RegistryKeyFingerprint -Key $subKey -Prefix "$Prefix\$subName" -Parts $Parts
            $subKey.Close()
        } else {
            $Parts.Add("$Prefix\$subName=<missing>")
        }
    }
}

function Invoke-ToolDownload {
    param(
        [string]$Url,
        [string]$ZipPath,
        [string]$DestDir
    )

    if (-not $Url -or -not $ZipPath -or -not $DestDir) { return $false }

    try {
        $zipParent = Split-Path $ZipPath -Parent
        if ($zipParent -and -not (Test-Path $zipParent)) {
            New-Item -ItemType Directory -Path $zipParent -Force | Out-Null
        }
        if (-not (Test-Path $DestDir)) {
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        }

        if (Test-Path -LiteralPath $ZipPath) {
            Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
        }

        $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $downloaded = $false
        try {
            foreach ($attempt in 1..2) {
                try {
                    Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing -TimeoutSec 120 `
                        -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' | Out-Null
                    if ((Test-Path -LiteralPath $ZipPath) -and ((Get-Item -LiteralPath $ZipPath).Length -gt 1024)) {
                        $downloaded = $true
                        break
                    }
                } catch {
                    if ($attempt -eq 2) { throw }
                    Start-Sleep -Seconds 2
                }
            }
        } finally {
            [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
        }

        if (-not $downloaded) { return $false }

        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force
        return $true
    } catch {
        Out-TaggedText -Indent '  ' -Tag 'WARN' -Text "Download failed: $($_.Exception.Message)"
        return $false
    }
}

function Resolve-ToolExecutable {
    param(
        [string]$DestDir,
        [string]$ExeName,
        [string[]]$FallbackNames = @()
    )

    foreach ($name in @($ExeName) + @($FallbackNames)) {
        $direct = Join-Path $DestDir $name
        if (Test-Path -LiteralPath $direct) { return $direct }
    }

    foreach ($name in @($ExeName) + @($FallbackNames)) {
        $found = Get-ChildItem -Path $DestDir -Filter $name -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    return $null
}

function Start-BsmmExternalTool {
    param(
        [string]$Name,
        [string]$Url,
        [string]$ZipPath,
        [string]$DestDir,
        [string]$ExeName,
        [string[]]$FallbackExeNames = @(),
        [string[]]$StartArguments = @(),
        [string[]]$KillProcessNames = @(),
        [switch]$Wait,
        [ValidateSet('Normal', 'Maximized')]
        [string]$WindowStyle = 'Normal'
    )

    foreach ($killName in $KillProcessNames) {
        Get-Process -Name $killName -ErrorAction SilentlyContinue | ForEach-Object {
            try { Microsoft.PowerShell.Management\Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {}
        }
    }

    try {
        $exe = $null
        if (Invoke-ToolDownload -Url $Url -ZipPath $ZipPath -DestDir $DestDir) {
            $exe = Resolve-ToolExecutable -DestDir $DestDir -ExeName $ExeName -FallbackNames $FallbackExeNames
        }

        if (-not $exe) {
            Out-TaggedText -Indent '  ' -Tag 'WARN' -Text "$Name unavailable (download or extract failed)."
            return $false
        }

        $strayDlls = @(Get-ChildItem -LiteralPath $DestDir -Filter '*.dll' -Recurse -Force -ErrorAction SilentlyContinue)
        if ($strayDlls.Count -gt 0) {
            Out-TaggedText -Indent '  ' -Tag 'WARN' -Text "$Name rejected because unexpected DLL files were found next to it."
            return $false
        }

        if (-not (Test-SignedMicrosoftFile -Path $exe)) {
            Out-TaggedText -Indent '  ' -Tag 'WARN' -Text "$Name rejected because its Microsoft signature could not be validated."
            return $false
        }

        try {
            $startParams = @{
                FilePath    = $exe
                WindowStyle = $WindowStyle
                PassThru    = $true
                ErrorAction = 'Stop'
            }
            if ($StartArguments.Count -gt 0) { $startParams['ArgumentList'] = $StartArguments }

            $proc = Start-Process @startParams
            if ($Wait) { $proc.WaitForExit() }
            return $true
        } catch {
            Out-TaggedText -Indent '  ' -Tag 'WARN' -Text "$Name failed to start: $($_.Exception.Message)"
            return $false
        }
    } finally {
        if ($Wait) {
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath $DestDir -Recurse -Force -ErrorAction SilentlyContinue
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
        }
    }
}

$script:BsmmModuleState = @{}
$script:DefenderAvailable = $false

function Initialize-BsmmModules {
    $results = @()

    $moduleSpecs = @(
        @{ Name = 'Microsoft.PowerShell.Management'; Required = $true;  Label = 'PowerShell Management' },
        @{ Name = 'Microsoft.PowerShell.Utility';   Required = $true;  Label = 'PowerShell Utility' },
        @{ Name = 'Microsoft.PowerShell.Security';  Required = $true;  Label = 'PowerShell Security' },
        @{ Name = 'CimCmdlets';                     Required = $true;  Label = 'CIM cmdlets' },
        @{ Name = 'ScheduledTasks';                 Required = $true;  Label = 'Scheduled Tasks' },
        @{ Name = 'Defender';                       Required = $true;  Label = 'Windows Defender' },
        @{ Name = 'Microsoft.PowerShell.Operation.Validation'; Required = $false; Label = 'Operation.Validation' },
        @{ Name = 'PackageManagement';              Required = $false; Label = 'PackageManagement' },
        @{ Name = 'PowerShellGet';                  Required = $false; Label = 'PowerShellGet' },
        @{ Name = 'PSReadLine';                     Required = $false; Label = 'PSReadLine' },
        @{ Name = 'Pester';                         Required = $false; Label = 'Pester' }
    )

    foreach ($spec in $moduleSpecs) {
        $name = $spec.Name
        $required = [bool]$spec.Required
        $label = $spec.Label
        $available = @()

        try {
            $available = @(Microsoft.PowerShell.Core\Get-Module -ListAvailable -Name $name -ErrorAction SilentlyContinue)
        } catch {}

        if ($available.Count -eq 0) {
            $script:BsmmModuleState[$name] = $false
            if ($required) {
                $results += "FAILURE: Required module unavailable -> $label ($name)"
            } else {
                $results += "INFO: Optional module not installed -> $label ($name)"
            }
            continue
        }

        try {
            Microsoft.PowerShell.Core\Import-Module -Name $name -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        } catch {
            $script:BsmmModuleState[$name] = $false
            if ($required) {
                $results += "FAILURE: Required module could not be imported -> $label ($name)"
            } else {
                $results += "WARNING: Optional module could not be imported -> $label ($name)"
            }
            continue
        }

        if (Microsoft.PowerShell.Core\Get-Module -Name $name -ErrorAction SilentlyContinue) {
            $script:BsmmModuleState[$name] = $true
            $results += "SUCCESS: Module available -> $label"
        } else {
            $script:BsmmModuleState[$name] = $false
            if ($required) {
                $results += "FAILURE: Required module did not load -> $label ($name)"
            } else {
                $results += "WARNING: Optional module did not load -> $label ($name)"
            }
        }
    }

    $script:DefenderAvailable = $false
    if ($script:BsmmModuleState.ContainsKey('Defender') -and $script:BsmmModuleState['Defender']) {
        $defenderCommands = @('Get-MpComputerStatus', 'Get-MpPreference', 'Get-MpThreat')
        $missing = @()
        foreach ($commandName in $defenderCommands) {
            if (-not (Microsoft.PowerShell.Core\Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
                $missing += $commandName
            }
        }
        if ($missing.Count -eq 0) {
            $script:DefenderAvailable = $true
            $results += 'SUCCESS: Windows Defender cmdlets available'
        } else {
            $results += "FAILURE: Defender module loaded but cmdlets unavailable -> $($missing -join ', ')"
        }
    }

    return $results
}

function Get-Exclusions {
    $list = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    try {
        $prefs = Defender\Get-MpPreference -ErrorAction Stop
        foreach ($item in @($prefs.ExclusionPath) + @($prefs.ExclusionProcess) + @($prefs.ExclusionExtension)) {
            if ($item -and [string]$item -notlike 'N/A*') { [void]$list.Add([string]$item) }
        }
    } catch {}

    $regRoots = @(
        'SOFTWARE\Microsoft\Windows Defender\Exclusions',
        'SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions'
    )
    $regTypes = @('Paths', 'Processes', 'Extensions')

    foreach ($root in $regRoots) {
        foreach ($type in $regTypes) {
            try {
                $key = Open-LocalMachineRegistryKey -SubKeyPath "$root\$type"
                if (-not $key) { continue }
                foreach ($name in $key.GetValueNames()) {
                    if ($name) { [void]$list.Add($name) }
                }
                $key.Close()
            } catch {}
        }
    }

    return @($list)
}

$script:DefenderExclusionsRegRoots = @(
    'SOFTWARE\Microsoft\Windows Defender\Exclusions',
    'SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions'
)
$script:DefenderThreatsRegRoots = @(
    'SOFTWARE\Microsoft\Windows Defender\Threats',
    'SOFTWARE\Policies\Microsoft\Windows Defender\Threats'
)
$script:DefenderThreatsSystemSubkeys = @(
    'ThreatSeverityDefaultAction',
    'ThreatIDDefaultAction',
    'ThreatTypeDefaultAction'
)

function Get-RegistrySubtreeFingerprint {
    param([string]$RelativePath)

    $parts = New-Object 'System.Collections.Generic.List[string]'

    try {
        $root = Open-LocalMachineRegistryKey -SubKeyPath $RelativePath
        if (-not $root) { return 'MISSING' }
        Add-RegistryKeyFingerprint -Key $root -Prefix $RelativePath -Parts $parts
        $root.Close()
    } catch {
        return 'ERROR'
    }

    if ($parts.Count -eq 0) { return 'EMPTY' }
    return ($parts | Sort-Object) -join '|'
}

function Get-DefenderRegistryMonitorLabels {
    $labels = @{}
    foreach ($root in $script:DefenderExclusionsRegRoots) {
        $labels[$root] = "Defender Exclusions registry ($root)"
    }
    foreach ($root in $script:DefenderThreatsRegRoots) {
        $labels[$root] = "Defender Threats registry ($root)"
    }
    return $labels
}

function Get-DefenderRegistryFingerprints {
    $fps = @{}
    foreach ($root in ($script:DefenderExclusionsRegRoots + $script:DefenderThreatsRegRoots)) {
        $fps[$root] = Get-RegistrySubtreeFingerprint -RelativePath $root
    }
    return $fps
}

function Get-AllowedDefenderThreats {
    $list = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($relPath in @(
        'SOFTWARE\Microsoft\Windows Defender\Exclusions\Threats',
        'SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Threats'
    )) {
        try {
            $key = Open-LocalMachineRegistryKey -SubKeyPath $relPath
            if (-not $key) { continue }
            foreach ($name in $key.GetValueNames()) {
                if ($name) { [void]$list.Add("$relPath -> $name") }
            }
            foreach ($subName in $key.GetSubKeyNames()) {
                [void]$list.Add("$relPath\$subName")
            }
            $key.Close()
        } catch {}
    }

    foreach ($root in $script:DefenderThreatsRegRoots) {
        try {
            $key = Open-LocalMachineRegistryKey -SubKeyPath $root
            if (-not $key) { continue }
            foreach ($subName in $key.GetSubKeyNames()) {
                if ($script:DefenderThreatsSystemSubkeys -contains $subName) { continue }
                if ($subName -match '(?i)^\{?[0-9A-F-]{36}\}?$|^\d+$') {
                    [void]$list.Add("$root\$subName")
                }
            }
            $key.Close()
        } catch {}
    }

    return @($list)
}

function Get-DefenderStatusAlerts {
    $alerts = @()

    if (-not $script:DefenderAvailable) {
        $alerts += 'WARNING: Windows Defender PowerShell module/cmdlets unavailable'
        return $alerts
    }

    try {
        $def = Defender\Get-MpComputerStatus -ErrorAction Stop
        if (-not $def.RealTimeProtectionEnabled) {
            $alerts += 'FAILURE: Real-time protection disabled'
        }
        if (-not $def.IsTamperProtected) {
            $alerts += 'WARNING: Tamper protection disabled'
        }
    } catch {
        $alerts += 'WARNING: Defender status unavailable'
    }

    foreach ($disableKey in @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender',
        'HKLM:\SOFTWARE\Microsoft\Windows Defender'
    )) {
        try {
            $disabled = Get-ItemPropertyValue -Path $disableKey -Name 'DisableAntiSpyware' -ErrorAction Stop
            if ($disabled -eq 1) { $alerts += 'FAILURE: DisableAntiSpyware active' }
        } catch {}
    }

    return $alerts
}

$script:CorePowerShellModules = @(
    'Microsoft.PowerShell.Archive',
    'Microsoft.PowerShell.Diagnostics',
    'Microsoft.PowerShell.Host',
    'Microsoft.PowerShell.LocalAccounts',
    'Microsoft.PowerShell.Management',
    'Microsoft.PowerShell.Security',
    'Microsoft.PowerShell.Utility',
    'Microsoft.PowerShell.Operation.Validation',
    'PackageManagement',
    'PowerShellGet',
    'PSReadLine'
)

$script:MicrosoftCodeSigningRoots = @(
    '3B1EFD3A66EA28B16697394703A72CA340A05BD5',
    '8F43288AD272F3103B6FB1428485EA3014C0BCFE',
    'CDD4EEAE6000AC7F40C3802C171E30148030C072',
    'A43489159A520F0D93D032CCAF37E7FE20A8B419',
    '7F88CD7223F3C813818C994614A89C99FA3B5247',
    '73A5E64A3BFF8316FF0EDCCC618A906E4EAE4D74',
    '999A64C37FF47D9FAB95F14769891460EEC4C3C5',
    '06F1AA330B927B753A40E68CDF22E34BCBEF3352',
    'F40042E2E5F7E8EF8189FED15519AECE42C3BFA2'
)
$script:MicrosoftShippedRoots = $script:MicrosoftCodeSigningRoots + @(
    '31F9FC8BA3805986B721EA7295C65B3A44534274',
    '0119E81BE9A14CD8E22F40AC118C687ECBA3F4D8',
    '92B46C76E13054E104F230517E6E504D43AB10B5',
    '245C97DF7514E7CF2DF8BE72AE957B9E04741E85',
    'BE36A4562FB2EE05DBB3D32323ADF445084ED656',
    '18F7C1FCC3090203FD5BAA2F861A754976C8DD25'
)

$script:AuthRootThumbprints = $null

function Get-AuthRootThumbprints {
    if ($null -ne $script:AuthRootThumbprints) { return $script:AuthRootThumbprints }
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    try {
        Get-ChildItem 'Cert:\LocalMachine\AuthRoot' -ErrorAction Stop | ForEach-Object { [void]$set.Add($_.Thumbprint) }
    } catch {}
    foreach ($tp in $script:MicrosoftShippedRoots) { [void]$set.Add($tp) }
    $script:AuthRootThumbprints = $set
    return $set
}

function Test-UserInstalledRootThumbprint {
    param([string]$Thumbprint)
    if ([string]::IsNullOrWhiteSpace($Thumbprint)) { return $true }
    return -not (Get-AuthRootThumbprints).Contains($Thumbprint)
}

function Get-SignatureRootThumbprint {
    param($Certificate)

    if (-not $Certificate) { return $null }
    try {
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = 'NoCheck'
        [void]$chain.Build($Certificate)
        if ($chain.ChainElements.Count -eq 0) { return $null }
        return $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Thumbprint
    } catch {
        return $null
    }
}

function Test-SignedMicrosoftFile {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate) { return $false }
        if ($sig.SignerCertificate.Subject -notmatch '(?i)(Microsoft Corporation|Microsoft Windows)') { return $false }
        $root = Get-SignatureRootThumbprint -Certificate $sig.SignerCertificate
        return ($root -and ($script:MicrosoftCodeSigningRoots -contains $root))
    } catch {
        return $false
    }
}

function Test-SignedByShippedRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate) { return $false }
        $root = Get-SignatureRootThumbprint -Certificate $sig.SignerCertificate
        if (-not $root) { return $false }
        return -not (Test-UserInstalledRootThumbprint -Thumbprint $root)
    } catch {
        return $false
    }
}

$script:HandleHolderTrustedPrefixes = @(
    '\windows\system32\', '\windows\syswow64\', '\program files\', '\program files (x86)\', '\roblox\'
)

function Test-TrustedHandleHolder {
    param([string]$ExecutablePath)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $false }
    $lower = $ExecutablePath.ToLower().Replace('/', '\')
    $inTrustedDir = $false
    foreach ($prefix in $script:HandleHolderTrustedPrefixes) {
        if ($lower.Contains($prefix)) { $inTrustedDir = $true; break }
    }
    if (-not $inTrustedDir) { return $false }
    return (Test-SignedByShippedRoot -Path $ExecutablePath)
}

function Get-ClarityDetectionAlerts {
    $alerts = @()

    $cdPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\ConfigDefender"
    $cdTampered = $false

    if (Test-Path $cdPath) {
        $cdFiles = Get-ChildItem $cdPath -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }

        foreach ($file in $cdFiles) {
            $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction SilentlyContinue
            if ($sig.Status -ne 'Valid' -or ($sig.SignerCertificate -and $sig.SignerCertificate.Subject -notmatch "Microsoft")) {
                $alerts += "FAILURE: Unsigned/non-Microsoft file in ConfigDefender: '$($file.FullName)'"
                $cdTampered = $true
            }
        }

        $psm1File = Join-Path $cdPath "ConfigDefender.psm1"
        if (Test-Path $psm1File) {
            try {
                $psm1Content = Get-Content $psm1File -Raw -ErrorAction Stop
                if ($psm1Content -match "Spoofed ConfigDefender" -or $psm1Content -match "No-op" -or $psm1Content -match "Silently fail") {
                    $alerts += "FAILURE: ConfigDefender.psm1 contains spoofed/fake module markers."
                    $cdTampered = $true
                }
            } catch {}
        }

        $backupNames = @("ConfigDefender_exe_backup", "Defender_exe_backup", "ConfigDefender_exe_b")
        foreach ($bname in $backupNames) {
            $found = Get-ChildItem $cdPath -Filter "*$bname*" -Recurse -Force -ErrorAction SilentlyContinue
            if ($found) {
                foreach ($item in @($found)) {
                    $alerts += "FAILURE: Backup artifact found: '$($item.FullName)'"
                    $cdTampered = $true
                }
            }
        }

        $parentDir = Split-Path $cdPath -Parent
        foreach ($bname in $backupNames) {
            $found = Get-ChildItem $parentDir -Filter "*$bname*" -Force -ErrorAction SilentlyContinue
            if ($found) {
                foreach ($item in @($found)) {
                    $alerts += "FAILURE: Backup artifact found: '$($item.FullName)'"
                    $cdTampered = $true
                }
            }
        }
    }

    foreach ($processName in @('svchost', 'MsMpEng', 'TiWorker')) {
        Get-Process -Name $processName -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($_.Path -and -not (Test-ClarityExpectedProcessPath -ProcessName "$processName.exe" -ExecutablePath $_.Path)) {
                    $alerts += "FAILURE: $processName.exe from suspicious path: '$($_.Path)' (PID $($_.Id))"
                }
            } catch {}
        }
    }
    if (-not ('BsmmNalCheck' -as [type])) {
        try {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class BsmmNalCheck {
    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr CreateFileA(string name, uint access, uint share,
        IntPtr sec, uint disp, uint flags, IntPtr template);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
'@ -ErrorAction Stop
        } catch {
            $alerts += "WARNING: Could not initialize Intel NAL device check."
        }
    }

    if ('BsmmNalCheck' -as [type]) {
        try {
            $nalHandle = [BsmmNalCheck]::CreateFileA("\\.\Nal", [uint32]2147483648, 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
            if ($nalHandle -ne [IntPtr]::new(-1)) {
                $alerts += "FAILURE: Vulnerable Intel driver device (\\.\Nal) is ACTIVE - BYOVD attack"
                [BsmmNalCheck]::CloseHandle($nalHandle) | Out-Null
            }
        } catch {
            $alerts += "WARNING: Could not query Intel NAL device."
        }
    }

    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\Nal") {
        $alerts += "FAILURE: Intel Nal driver service exists in registry"
    }

    $defenderProc = Get-Process -Name "MsMpEng" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $defenderProc) {
        $alerts += "FAILURE: MsMpEng.exe is NOT running - Defender may be killed"
    } elseif ($defenderProc.Path -and $defenderProc.Path -notlike "C:\ProgramData\Microsoft\Windows Defender\Platform\*\MsMpEng.exe") {
        $alerts += "FAILURE: MsMpEng.exe running from unexpected path: '$($defenderProc.Path)'"
    }

    try {
        $rtpKey = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
        $val = Get-ItemPropertyValue -Path $rtpKey -Name "DisableRealtimeMonitoring" -ErrorAction Stop
        if ($val -ne 0) {
            $alerts += "FAILURE: Registry shows Defender real-time protection is DISABLED"
        }
    } catch {}

    if ($alerts.Count -eq 0) {
        if (Test-Path $cdPath) {
            $alerts += "SUCCESS: Clarity/Defender detection checks passed."
        } else {
            $alerts += "SUCCESS: Clarity/Defender detection checks passed (ConfigDefender path not present)."
        }
    }

    return @($alerts | Select-Object -Unique)
}

function Get-PowerShellModuleIntegrityAlerts {
    $alerts = @()
    $moduleRoots = @()

    foreach ($root in ($env:PSModulePath -split ';')) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root -PathType Container)) {
            $moduleRoots += $root
        }
    }

    foreach ($moduleName in $script:CorePowerShellModules) {
        $moduleDirs = @()
        foreach ($root in ($moduleRoots | Select-Object -Unique)) {
            $candidate = Join-Path $root $moduleName
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $moduleDirs += $candidate
            }
        }

        foreach ($moduleDir in ($moduleDirs | Select-Object -Unique)) {
            try {
                Get-ChildItem -LiteralPath $moduleDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $file = $_

                    if ($file.Extension -notmatch '(?i)^\.(ps1|psm1|psd1|dll|exe|ps1xml|cdxml)$') {
                        return
                    }

                    try {
                        $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction Stop
                    } catch {
                        $alerts += "WARNING: Could not verify PowerShell module file -> $($file.FullName)"
                        return
                    }

                    $isMicrosoft = $false
                    if ($sig.SignerCertificate) {
                        $isMicrosoft = ($sig.SignerCertificate.Subject -match '(?i)(Microsoft Corporation|Microsoft Windows)')
                    }

                    if ($sig.Status -eq 'Valid' -and $isMicrosoft) {
                        return
                    }

                    if ($sig.Status -eq 'NotSigned') {
                        $alerts += "WARNING: Unsigned PowerShell module file -> $($file.FullName)"
                    } else {
                        $alerts += "FAILURE: PowerShell module integrity issue -> $($file.FullName) [$($sig.Status)]"
                    }
                }
            } catch {
                $alerts += "WARNING: Could not scan PowerShell module -> $moduleDir"
            }
        }
    }

    if ($alerts.Count -eq 0) {
        $alerts += 'SUCCESS: Core PowerShell module files have acceptable signatures'
    }

    return @($alerts | Select-Object -Unique)
}

function Get-PowerShellBinaryIntegrityAlerts {
    $alerts = @()
    $paths = @(
        "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    )

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh -and $pwsh.Source) { $paths += $pwsh.Source }

    foreach ($path in ($paths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

        try {
            $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
            $isMicrosoft = $false
            if ($sig.SignerCertificate) {
                $isMicrosoft = ($sig.SignerCertificate.Subject -match '(?i)(Microsoft Corporation|Microsoft Windows)')
            }

            if ($sig.Status -eq 'Valid' -and $isMicrosoft) {
                $alerts += "SUCCESS: PowerShell binary signature valid -> $path"
            } else {
                $alerts += "FAILURE: PowerShell binary signature invalid -> $path [$($sig.Status)]"
            }
        } catch {
            $alerts += "WARNING: Could not verify PowerShell binary -> $path"
        }
    }

    if ($alerts.Count -eq 0) {
        $alerts += 'WARNING: No PowerShell binary could be located for signature verification'
    }

    return $alerts
}

function Initialize-BsmmIntegrityApi {
    if ('BSMM.IntegrityScan' -as [type]) { return $true }
    try {
        Add-Type -Namespace BSMM -Name IntegrityScan -UsingNamespace System.Text, System.Collections.Generic, System.Diagnostics -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true, SetLastError = true)]
public static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

[DllImport("kernel32.dll", CharSet = CharSet.Auto)]
public static extern IntPtr GetModuleHandle(string lpModuleName);

[DllImport("user32.dll")]
public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

[DllImport("user32.dll")]
public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

[DllImport("user32.dll")]
public static extern bool IsWindowVisible(IntPtr hWnd);

[DllImport("user32.dll", SetLastError = true)]
public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

public const int GWL_EXSTYLE = -20;
public const int WS_EX_TOPMOST = 0x00000008;
public const int WS_EX_TRANSPARENT = 0x00000020;
public const int WS_EX_LAYERED = 0x00080000;

public static string GetSyscallHookDetails(string functionName) {
    IntPtr hNtdll = GetModuleHandle("ntdll.dll");
    if (hNtdll == IntPtr.Zero) return null;
    IntPtr pFunc = GetProcAddress(hNtdll, functionName);
    if (pFunc == IntPtr.Zero) return null;

    byte[] b = new byte[32];
    System.Runtime.InteropServices.Marshal.Copy(pFunc, b, 0, 32);
    if (b[0] == 0x4C && b[1] == 0x8B && b[2] == 0xD1 && b[3] == 0xB8) {
        return null;
    }

    long target = 0;
    if (b[0] == 0xE9) {
        int rel32 = BitConverter.ToInt32(b, 1);
        target = pFunc.ToInt64() + 5 + rel32;
    } else if (b[0] == 0xFF && b[1] == 0x25) {
        int disp32 = BitConverter.ToInt32(b, 2);
        long ptr = pFunc.ToInt64() + 6 + disp32;
        try { target = System.Runtime.InteropServices.Marshal.ReadInt64((IntPtr)ptr); } catch {}
    } else if (b[0] == 0x48 && b[1] == 0xB8) {
        target = BitConverter.ToInt64(b, 2);
    }

    if (target != 0) {
        try {
            foreach (ProcessModule pm in Process.GetCurrentProcess().Modules) {
                long start = pm.BaseAddress.ToInt64();
                long end = start + pm.ModuleMemorySize;
                if (target >= start && target < end) {
                    return pm.FileName + " (Offset: +0x" + (target - start).ToString("X") + ")";
                }
            }
        } catch {}
        return "Unbacked Memory at 0x" + target.ToString("X") + " (Injected Shellcode / Manual Map)";
    }

    return "Trampoline at 0x" + pFunc.ToInt64().ToString("X") + " (Raw: " + BitConverter.ToString(b, 0, 8) + ")";
}

public static bool IsSyscallHooked(string functionName) {
    return GetSyscallHookDetails(functionName) != null;
}

private static List<string> _overlayHits;
private static bool OverlayEnumCallback(IntPtr hWnd, IntPtr lParam) {
    if (!IsWindowVisible(hWnd)) return true;
    int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
    if ((exStyle & WS_EX_TOPMOST) != 0 && (exStyle & WS_EX_TRANSPARENT) != 0) {
        uint pid = 0;
        GetWindowThreadProcessId(hWnd, out pid);
        StringBuilder title = new StringBuilder(256);
        GetWindowTextW(hWnd, title, title.Capacity);
        _overlayHits.Add(pid.ToString() + "|" + exStyle.ToString("X") + "|" + title.ToString());
    }
    return true;
}

public static string[] FindTopmostOverlays() {
    _overlayHits = new List<string>();
    try {
        EnumWindows(new EnumWindowsProc(OverlayEnumCallback), IntPtr.Zero);
    } catch {
        return null;
    }
    return _overlayHits.ToArray();
}
'@ -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-ClrHijackAlerts {
    $alerts = @()
    $vars = @(
        'COR_ENABLE_PROFILING', 'COR_PROFILER', 'COR_PROFILER_PATH',
        'CORECLR_ENABLE_PROFILING', 'CORECLR_PROFILER', 'CORECLR_PROFILER_PATH',
        'COMPLUS_ENABLE_PROFILING'
    )

    foreach ($v in $vars) {
        $m = [Environment]::GetEnvironmentVariable($v, 'Machine')
        $u = [Environment]::GetEnvironmentVariable($v, 'User')
        $p = [Environment]::GetEnvironmentVariable($v, 'Process')
        if ($m -or $u -or $p) {
            $alerts += "FAILURE: .NET CLR profiler hijack detected in $v (Machine: '$m', User: '$u', Process: '$p')"
        }
    }

    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: No CLR profiler hijacking detected' }
    return $alerts
}

function Get-NtdllSyscallIntegrityAlerts {
    $alerts = @()
    if ([IntPtr]::Size -ne 8) {
        return @('WARNING: 32-bit PowerShell - syscall integrity check skipped (run 64-bit PowerShell)')
    }
    if (-not (Initialize-BsmmIntegrityApi)) {
        return @('WARNING: Native integrity API could not be initialized')
    }

    $targets = @('NtQuerySystemInformation', 'NtOpenProcess', 'NtDuplicateObject', 'NtReadVirtualMemory')
    foreach ($fn in $targets) {
        $hookDetails = [BSMM.IntegrityScan]::GetSyscallHookDetails($fn)
        if ($hookDetails) {
            $alerts += "FAILURE: In-memory syscall hook on $fn in powershell.exe -> $hookDetails"
        }
    }

    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: Native syscall stubs intact (no inline hooks)' }
    return $alerts
}

function Get-StreamingProcessIntegrityAlerts {
    $alerts = @()
    $targets = @(
        'obs64', 'obs32', 'medal', 'Discord',
        'chrome', 'msedge', 'brave', 'firefox', 'opera', 'operagx', 'vivaldi',
        'spotify',
        'fleasion'
    )

    $scannedModules = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $sysRoot = $env:SystemRoot

    foreach ($name in $targets) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            $proc = $_
            try {
                foreach ($mod in $proc.Modules) {
                    $path = [string]$mod.FileName
                    if ([string]::IsNullOrWhiteSpace($path)) { continue }
                    if ($path.StartsWith($sysRoot, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    if (-not $scannedModules.Add($path)) { continue }

                    $isSigned = $false
                    try {
                        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($path)
                        if ($cert) { $isSigned = $true }
                    } catch {
                        $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $path -ErrorAction SilentlyContinue
                        if ($sig -and $sig.Status -eq 'Valid') { $isSigned = $true }
                    }

                    if (-not $isSigned) {
                        $entropy = Get-FileEntropy -FilePath $path
                        $alerts += "FAILURE: Unsigned module loaded in $($proc.Name) (PID $($proc.Id)) [Entropy: $entropy] -> $path"
                    } elseif (Test-UserLandProcessPath -ExecutablePath $path) {
                        $alerts += "WARNING: Userland module loaded in $($proc.Name) (PID $($proc.Id)) -> $path"
                    }
                }
            } catch {
                $alerts += "WARNING: Could not inspect modules for $($proc.Name) (PID $($proc.Id))"
            }
        }
    }

    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: Monitored applications module integrity verified' }
    return @($alerts | Select-Object -Unique)
}

function Get-TransparentOverlayAlerts {
    $alerts = @()
    if (-not (Initialize-BsmmIntegrityApi)) { return @('WARNING: Overlay scan API unavailable') }

    $hits = [BSMM.IntegrityScan]::FindTopmostOverlays()
    if ($null -eq $hits) { return @('WARNING: Failed to enumerate topmost overlays') }

    $trusted = @(
        'dwm', 'explorer', 'taskmgr', 'applicationframehost', 'systemsettings', 'textinputhost',
        'robloxplayerbeta', 'discord', 'gameoverlayui', 'nvidia overlay', 'nvcontainer',
        'gamebar', 'gamebarftserver', 'obs64', 'medal', 'steamwebhelper', 'shellexperiencehost',
        'procexp', 'procexp64', 'runtimebroker', 'startmenuexperiencehost', 'searchhost',
        'lockapp', 'widgets', 'ctfmon', 'searchui', 'sihost'
    )

    foreach ($hit in $hits) {
        $parts = $hit -split '\|', 3
        $pidVal = 0
        [void][int]::TryParse($parts[0], [ref]$pidVal)
        if ($pidVal -le 0 -or $pidVal -eq $PID) { continue }

        $pInfo = Resolve-ProcessIdentity -TargetPid $pidVal
        $nameLower = ($pInfo.Name -replace '\.exe$', '').ToLower()
        if ($trusted -contains $nameLower -and $pInfo.Path -and (Test-SignedByShippedRoot -Path $pInfo.Path)) { continue }

        if ($pInfo.Path -and $pInfo.Path.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-SignedByShippedRoot -Path $pInfo.Path)) {
            continue
        }

        $style = $parts[1]
        $title = if ($parts.Count -ge 3 -and $parts[2]) { " '$($parts[2])'" } else { '' }

        if ($pInfo.Path -and -not (Test-TrustedProcessPath -ExecutablePath $pInfo.Path)) {
            $alerts += "FAILURE: Transparent click-through overlay window$title from untrusted path (PID $pidVal, ExStyle 0x$style) -> $($pInfo.Path)"
        } else {
            $alerts += "WARNING: Transparent click-through overlay window$title detected (PID $pidVal, ExStyle 0x$style)"
        }
    }

    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: No suspicious transparent overlay windows found' }
    return @($alerts | Select-Object -Unique)
}

function Get-TaskManagerIntegrityAlerts {
    $alerts = @()
    
    $ifeoKeys = @('Taskmgr.exe', 'procexp.exe', 'procexp64.exe')
    foreach ($exe in $ifeoKeys) {
        $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exe"
        if (Test-Path $ifeoPath) {
            $debugger = (Get-ItemProperty -Path $ifeoPath -ErrorAction SilentlyContinue).Debugger
            if ($debugger) {
                if ($exe -eq 'Taskmgr.exe' -and ($debugger -match 'procexp(64)?\.exe')) {
                    $cleanDbg = $debugger.Trim('"', "'")
                    $dbgSig = if (Test-Path $cleanDbg) { Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $cleanDbg -ErrorAction SilentlyContinue } else { $null }
                    if ($dbgSig -and $dbgSig.Status -eq 'Valid' -and ($dbgSig.SignerCertificate.Subject -match 'Microsoft|Sysinternals')) {
                        $alerts += "INFO: Task Manager replaced by Sysinternals Process Explorer: $cleanDbg"
                    } else {
                        $alerts += "FAILURE: Taskmgr.exe redirected to untrusted debugger: $debugger"
                    }
                } else {
                    $alerts += "FAILURE: IFEO Redirection detected on $($exe)! Launches: $debugger"
                }
            }
        }
    }

    $peProcesses = Get-Process -Name @('procexp', 'procexp64') -ErrorAction SilentlyContinue
    if ($peProcesses) {
        foreach ($proc in $peProcesses) {
            $path = $proc.Path
            if ($path -and (Test-Path $path)) {
                $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $path -ErrorAction SilentlyContinue
                if ($sig.Status -ne 'Valid' -or ($sig.SignerCertificate.Subject -notmatch 'Microsoft|Sysinternals')) {
                    $alerts += "FAILURE: Process Explorer ($($proc.Name) PID $($proc.Id)) binary signature invalid: $($sig.Status)"
                }
            }
            try {
                foreach ($mod in $proc.Modules) {
                    $modPath = [string]$mod.FileName
                    if ([string]::IsNullOrWhiteSpace($modPath)) { continue }
                    if ($modPath.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    if (Test-Path $modPath) {
                        $isSigned = $false
                        try {
                            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($modPath)
                            if ($cert) { $isSigned = $true }
                        } catch {
                            $modSig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $modPath -ErrorAction SilentlyContinue
                            if ($modSig -and $modSig.Status -eq 'Valid') { $isSigned = $true }
                        }

                        if (-not $isSigned) {
                            $entropy = Get-FileEntropy -FilePath $modPath
                            $alerts += "FAILURE: Unsigned module in Process Explorer PID $($proc.Id) -> $($mod.ModuleName) [Entropy: $entropy] -> $modPath"
                        } elseif (Test-UserLandProcessPath -ExecutablePath $modPath) {
                            $alerts += "WARNING: Userland module in Process Explorer PID $($proc.Id) -> $modPath"
                        }
                    }
                }
            } catch {
                $alerts += "WARNING: Could not inspect modules for $($proc.Name) (PID $($proc.Id))"
            }
        }
    }

    $taskmgrBinary = "$env:SystemRoot\System32\Taskmgr.exe"
    if (-not (Test-Path $taskmgrBinary)) {
        $alerts += "FAILURE: Taskmgr.exe missing from System32!"
    } else {
        $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -FilePath $taskmgrBinary -ErrorAction SilentlyContinue
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Windows') {
            $alerts += "FAILURE: Taskmgr.exe binary signature invalid/missing: $($sig.Status)"
        }
    }

    $tmProcesses = Get-Process -Name 'Taskmgr' -ErrorAction SilentlyContinue
    if ($tmProcesses) {
        foreach ($proc in $tmProcesses) {
            if ($proc.Path -and $proc.Path -ne $taskmgrBinary) {
                $alerts += "FAILURE: Taskmgr is running from abnormal path: $($proc.Path)"
            }

            try {
                foreach ($mod in $proc.Modules) {
                    $modPath = [string]$mod.FileName
                    if ([string]::IsNullOrWhiteSpace($modPath)) { continue }
                    if ($modPath.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    if (Test-Path $modPath) {
                        $isSigned = $false
                        try {
                            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($modPath)
                            if ($cert) { $isSigned = $true }
                        } catch {
                            $modSig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $modPath -ErrorAction SilentlyContinue
                            if ($modSig -and $modSig.Status -eq 'Valid') { $isSigned = $true }
                        }

                        if (-not $isSigned) {
                            $entropy = Get-FileEntropy -FilePath $modPath
                            $alerts += "FAILURE: Suspicious module in Taskmgr PID $($proc.Id) -> $($mod.ModuleName) [Entropy: $entropy] -> $modPath"
                        }
                    }
                }
            } catch {}
        }
    }

    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' })) {
        $alerts = @('SUCCESS: Process Explorer & Task Manager integrity verified (no IFEO hijack, signed modules intact)') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

function Get-MemoryIntegrityAlerts {
    $alerts = @()
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'

    try {
        $enabled = Get-ItemPropertyValue -Path $regPath -Name 'Enabled' -ErrorAction Stop
        if ($enabled -eq 1) {
            $alerts += 'SUCCESS: Memory Integrity (HVCI) enabled'
        } else {
            $alerts += 'WARNING: Memory Integrity (HVCI) disabled'
        }
    } catch {
        $alerts += 'WARNING: Memory Integrity (HVCI) status unavailable'
    }

    return $alerts
}

function Get-ActiveDefenderThreatAlerts {
    $alerts = @()

    if (-not $script:DefenderAvailable) {
        $alerts += 'WARNING: Windows Defender PowerShell module/cmdlets unavailable'
        return $alerts
    }

    try {
        $threats = @(Defender\Get-MpThreat -ErrorAction Stop | Where-Object {
            $_.Status -eq 'Active'
        })

        if ($threats.Count -eq 0) {
            $alerts += 'SUCCESS: No active Microsoft Defender threats'
        } else {
            foreach ($threat in $threats) {
                $name = [string]$threat.ThreatName
                $resources = [string]$threat.Resources
                if ($resources) {
                    $alerts += "FAILURE: Active Defender threat -> $name | $resources"
                } else {
                    $alerts += "FAILURE: Active Defender threat -> $name"
                }
            }
        }
    } catch {
        $alerts += 'WARNING: Unable to query active Microsoft Defender threats'
    }

    return $alerts
}

function Get-RegistryToolProcessHits {
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    $messages = @()

    foreach ($procName in @('regedit.exe', 'reg.exe')) {
        try {
            Get-CimInstance Win32_Process -Filter "Name='$procName'" -ErrorAction Stop | ForEach-Object {
                $procId = [int]$_.ProcessId
                if (-not $seen.Add($procId)) { return }
                $path = [string]$_.ExecutablePath
                $cmd = [string]$_.CommandLine
                $label = "$procName (PID $procId)"
                if ($path) { $label += " -> $path" }
                if ($cmd) { $label += " [$cmd]" }
                $messages += $label
            }
        } catch {}
    }

    return $messages
}

$script:WindhawkProcessName = 'windhawk.exe'
$script:WindhawkWatchPaths = @(
    (Join-Path $env:USERPROFILE 'Downloads\windhawk.exe'),
    (Join-Path ${env:ProgramFiles} 'Windhawk\windhawk.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Windhawk\windhawk.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Windhawk\windhawk.exe')
)

function Get-WindhawkProcessHits {
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    $messages = @()

    try {
        Get-CimInstance Win32_Process -Filter "Name='$($script:WindhawkProcessName)'" -ErrorAction Stop | ForEach-Object {
            $procId = [int]$_.ProcessId
            if (-not $seen.Add($procId)) { return }
            $path = [string]$_.ExecutablePath
            $label = "$($script:WindhawkProcessName) (PID $procId)"
            if ($path) { $label += " -> $path" }
            $messages += $label
        }
    } catch {}

    return $messages
}

function Get-WindhawkStep1Alerts {
    $alerts = @()
    $hits = @(Get-WindhawkProcessHits)

    if ($hits.Count -gt 0) {
        foreach ($hit in $hits) {
            $alerts += "FAILURE: Windhawk running $hit"
        }
        return $alerts
    }

    $foundPaths = @()
    foreach ($p in ($script:WindhawkWatchPaths | Select-Object -Unique)) {
        if ($p -and (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) {
            $foundPaths += $p
        }
    }
    if ($foundPaths.Count -gt 0) {
        foreach ($p in $foundPaths) {
            $alerts += "WARNING: Windhawk found $p"
        }
        return $alerts
    }

    $alerts += 'SUCCESS: Windhawk not detected'
    return $alerts
}

function Get-CheatFolderHits {
    $hits = New-Object 'System.Collections.Generic.HashSet[string]'
    $scanPaths = @(Get-BsmmUserFolders Downloads) + @(Get-BsmmUserFolders Desktop) + @(Get-BsmmUserFolders Documents) + @(
        $env:LOCALAPPDATA,
        $env:APPDATA,
        $env:ProgramData,
        $env:TEMP,
        "$env:SystemDrive\"
    )

    foreach ($scanPath in $scanPaths) {
        if (-not (Test-Path $scanPath)) { continue }

        $maxDepth = 2
        if ($scanPath -eq "$env:SystemDrive\") { $maxDepth = 1 }

        Get-ChildItem -Path $scanPath -Directory -Recurse -Depth $maxDepth -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.FullName -match '(?i)\\(BattlEye|EasyAntiCheat[^\\]*|Riot Vanguard)\\') { return }
            $nameLower = $_.Name.ToLower()
            $matched = Get-MatchedCheatKeyword -Text $nameLower -FolderName
            if ($matched) { [void]$hits.Add($_.FullName) }
        }
    }

    return @($hits)
}

function Get-BamHistoryAlerts {
    $alerts = @()
    $roots = @(
        'SYSTEM\CurrentControlSet\Services\bam\State\UserSettings',
        'SYSTEM\CurrentControlSet\Services\dam\State\UserSettings'
    )

    foreach ($root in $roots) {
        try {
            $rootKey = Open-LocalMachineRegistryKey -SubKeyPath $root
            if (-not $rootKey) { continue }

            foreach ($sidName in $rootKey.GetSubKeyNames()) {
                if ($sidName -eq 'S-1-5-18') { continue }
                $sidKey = $rootKey.OpenSubKey($sidName)
                if (-not $sidKey) { continue }

                foreach ($valueName in $sidKey.GetValueNames()) {
                    if (-not $valueName) { continue }
                    $raw = $sidKey.GetValue($valueName)
                    if (-not $raw -or $raw.Length -lt 8) { continue }

                    $resolvedPath = $null
                    if ($valueName -match '^\\Device\\HarddiskVolume\d+\\(.+)$') {
                        $resolvedPath = Join-Path $env:SystemDrive $matches[1]
                    }
                    $leaf = Split-Path -Leaf $valueName

                    $kw = Get-MatchedCheatKeyword -Text $valueName
                    if (-not $kw -and $resolvedPath) { $kw = Get-MatchedCheatKeyword -Text $resolvedPath }

                    if ($kw) {
                        $hex = [System.BitConverter]::ToString($raw[7..0]) -replace '-', ''
                        $ranAt = 'unknown time'
                        try { $ranAt = (Get-Date ([DateTime]::FromFileTime([Convert]::ToInt64($hex, 16))) -Format 'yyyy-MM-dd HH:mm:ss') } catch {}
                        $alerts += "FAILURE: Execution history [$kw] '$leaf' ran $ranAt -> $valueName"
                        continue
                    }

                    if ($resolvedPath -and (Test-UntrustedUserProgramPath -Path $resolvedPath)) {
                        $hex = [System.BitConverter]::ToString($raw[7..0]) -replace '-', ''
                        $ranTime = $null
                        try { $ranTime = [DateTime]::FromFileTime([Convert]::ToInt64($hex, 16)) } catch {}
                        if ($ranTime -and $ranTime -ge (Get-LogonTime)) {
                            if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                                $status = Get-CachedSignatureStatus -Path $resolvedPath
                                if ($status -ne 'Valid') {
                                    $alerts += "WARNING: Unsigned executable in recent run history: $resolvedPath ($status)"
                                }
                            }
                        }
                    }
                }
                $sidKey.Close()
            }
            $rootKey.Close()
        } catch {}
    }

    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: No suspicious entries in execution history.' }
    return @($alerts | Select-Object -Unique)
}

function Get-BamRegistryFingerprints {
    $fps = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $roots = @(
        'SYSTEM\CurrentControlSet\Services\bam\State\UserSettings',
        'SYSTEM\CurrentControlSet\Services\dam\State\UserSettings'
    )

    foreach ($root in $roots) {
        try {
            $rootKey = Open-LocalMachineRegistryKey -SubKeyPath $root
            if (-not $rootKey) { continue }

            foreach ($sidName in $rootKey.GetSubKeyNames()) {
                if ($sidName -eq 'S-1-5-18') { continue }
                $sidKey = $rootKey.OpenSubKey($sidName)
                if (-not $sidKey) { continue }

                foreach ($valueName in $sidKey.GetValueNames()) {
                    if ($valueName) { [void]$fps.Add("$root|$sidName|$valueName") }
                }
                $sidKey.Close()
            }
            $rootKey.Close()
        } catch {}
    }

    return @($fps)
}

function Get-PrefetchFileNames {
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $prefetchPath = "$env:WINDIR\Prefetch"
    if (-not (Test-Path $prefetchPath)) { return @($names) }

    try {
        Get-ChildItem -Path $prefetchPath -Filter "*.pf" -ErrorAction Stop | ForEach-Object {
            [void]$names.Add($_.Name)
        }
    } catch {}

    return @($names)
}

$script:TamperLogFailureWarned = @{}

function Get-TamperLogEvents {
    param(
        [datetime]$Since,
        [string]$LogFile
    )

    $events = @()
    $filters = @(
        @{ LogName = 'Security'; Id = 1102 },
        @{ LogName = 'System'; Id = 104 }
    )

    foreach ($filter in $filters) {
        try {
            $filter.StartTime = $Since
            Get-WinEvent -FilterHashtable $filter -ErrorAction Stop | ForEach-Object { $events += $_ }
        } catch {
            if ($_.Exception.Message -notmatch '(?i)no events were found') {
                $warnKey = "winevent|$($filter.LogName)"
                if (-not $script:TamperLogFailureWarned.ContainsKey($warnKey)) {
                    $script:TamperLogFailureWarned[$warnKey] = $true
                    Write-MonitorAlert -Message "WARNING: Could not query '$($filter.LogName)' log for tamper events ($($_.Exception.Message))" -LogFile $LogFile -Color Yellow
                }
            }
        }
    }

    return $events
}

$script:MonitorAlertCounts = @{ FAIL = 0; WARN = 0; INFO = 0 }
$script:MonitorStatusShown = $false

function Clear-MonitorStatusLine {
    if (-not $script:MonitorStatusShown) { return }
    $width = 100
    try {
        if ([Console]::WindowWidth -gt 1) { $width = [Console]::WindowWidth - 1 }
    } catch {}
    Write-Host ("`r" + (' ' * $width) + "`r") -NoNewline
    $script:MonitorStatusShown = $false
}

# "  * LIVE  00:12:33    0 FAIL   1 WARN   3 INFO    Ctrl+C to stop"  (the dot blinks like a REC light)
function Write-MonitorStatusLine {
    param([datetime]$Since)
    $elapsed = (Get-Date) - $Since
    $script:MonitorPulse = -not $script:MonitorPulse
    $dotTok = 'Line'; if ($script:MonitorPulse) { $dotTok = 'Fail' }
    $c = $script:MonitorAlertCounts
    $parts = @(
        @("`r  ", 'Body', $false),
        @($script:G.Dot, $dotTok, $false),
        @(' LIVE  ', 'Text', $true),
        @(('{0:hh\:mm\:ss}' -f $elapsed), 'Body', $false),
        @('    ', 'Body', $false),
        @("$($c.FAIL) FAIL", $(if ($c.FAIL -gt 0) { 'Fail' } else { 'Muted' }), ($c.FAIL -gt 0)),
        @('   ', 'Body', $false),
        @("$($c.WARN) WARN", $(if ($c.WARN -gt 0) { 'Warn' } else { 'Muted' }), $false),
        @('   ', 'Body', $false),
        @("$($c.INFO) INFO", 'Muted', $false),
        @('    Ctrl+C to stop', 'Line', $false)
    )
    if ($script:UseAnsi) {
        $sb = New-Object System.Text.StringBuilder
        foreach ($p in $parts) {
            if ($p[2]) { [void]$sb.Append("$script:Esc[1m") }
            [void]$sb.Append($script:AnsiFg[$p[1]]).Append($p[0]).Append($script:AnsiReset)
        }
        Write-Host $sb.ToString() -NoNewline
    } else {
        foreach ($p in $parts) { Out-Seg $p[0] -Fg $p[1] -NoNewline }
    }
    $script:MonitorStatusShown = $true
}

function Write-MonitorAlert {
    param(
        [string]$Message,
        [string]$LogFile,
        [string]$Color = '',
        [ValidateSet('', 'FAIL', 'WARN', 'INFO', 'NOTE')]
        [string]$Level = ''
    )

    $text = $Message
    if ($Message -match '(?s)^(SUCCESS|FAILURE|WARNING|INFO):\s*(.*)$') {
        $text = $matches[2]
        if (-not $Level) {
            switch ($matches[1]) {
                'FAILURE' { $Level = 'FAIL' }
                'WARNING' { $Level = 'WARN' }
                'INFO'    { $Level = 'INFO' }
                'SUCCESS' { $Level = 'INFO' }
            }
        }
    }
    if (-not $Level) { $Level = if ($Color -eq 'Yellow') { 'WARN' } else { 'NOTE' } }
    if ($script:MonitorAlertCounts.ContainsKey($Level)) { $script:MonitorAlertCounts[$Level]++ }
    if ($null -ne $script:MonitorLog) { [void]$script:MonitorLog.Add("[$(Get-Date -Format 'HH:mm:ss')] [$Level] $text") }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Clear-MonitorStatusLine
    $textTok = switch ($Level) { 'FAIL' { 'Text' } 'INFO' { 'Muted' } default { 'Body' } }
    Out-TaggedText -Indent '  ' -Time (Get-Date -Format 'HH:mm:ss') -Tag $Level -Text $text -TextToken $textTok
    Invoke-ConsoleRefresh
    try {
        Add-Content -LiteralPath $LogFile -Value "[$timestamp] [$Level] $text" -ErrorAction Stop
    } catch {
        $fallback = Join-Path $env:TEMP 'bsmm_security_events.log'
        try { Add-Content -LiteralPath $fallback -Value "[$timestamp] [$Level] $text" -ErrorAction SilentlyContinue } catch {}
    }
}

$script:MonitorSeenKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

function Get-AlertDedupKey {
    param([string]$Category, [string]$Message)
    $k = $Message -replace '^(SUCCESS|FAILURE|WARNING|INFO):\s*', ''
    $k = $k -replace '\(PID[s]? [^\)]+\)', '(PID)' -replace '\bPID \d+', 'PID'
    $k = $k -replace '\b\d{1,2}:\d{2}:\d{2}\b', 'TIME'
    $k = $k -replace '\[Entropy: [\d\.\-]+\]', '[Entropy]'
    $k = $k -replace '\s+', ' '
    return "$Category|$($k.Trim())"
}

function Register-MonitorBaseline {
    param([string]$Category, [string[]]$Lines)
    foreach ($line in @($Lines)) {
        if ($line -and $line -notlike 'SUCCESS*') {
            [void]$script:MonitorSeenKeys.Add((Get-AlertDedupKey -Category $Category -Message $line))
        }
    }
}

function Write-MonitorAlertOnce {
    param(
        [string]$Category,
        [string]$Message,
        [string]$LogFile,
        [string]$Level = '',
        [string]$Color = ''
    )
    $key = Get-AlertDedupKey -Category $Category -Message $Message
    if (-not $script:MonitorSeenKeys.Add($key)) { return }
    $p = @{ Message = $Message; LogFile = $LogFile }
    if ($Level) { $p.Level = $Level }
    if ($Color) { $p.Color = $Color }
    Write-MonitorAlert @p
}

$script:CursorSchemeValueNames = @(
    '(Default)', 'Arrow', 'Help', 'AppStarting', 'Wait', 'Crosshair', 'IBeam',
    'NWPen', 'No', 'SizeNS', 'SizeWE', 'SizeNWSE', 'SizeNESW', 'SizeAll',
    'UpArrow', 'Hand', 'CursorBaseSize'
)

function Expand-CursorPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-CursorSchemeState {
    $state = @{}
    $keyPath = 'HKCU:\Control Panel\Cursors'
    if (-not (Test-Path $keyPath)) { return $state }

    foreach ($name in $script:CursorSchemeValueNames) {
        try {
            $state[$name] = [string](Get-ItemPropertyValue -Path $keyPath -Name $name -ErrorAction Stop)
        } catch {
            $state[$name] = ''
        }
    }
    return $state
}

function Get-CursorSchemeChanges {
    param(
        [hashtable]$Baseline,
        [hashtable]$Current
    )

    $changes = @()
    foreach ($name in $script:CursorSchemeValueNames) {
        $old = if ($Baseline.ContainsKey($name)) { [string]$Baseline[$name] } else { '' }
        $new = if ($Current.ContainsKey($name)) { [string]$Current[$name] } else { '' }
        if ($old -eq $new) { continue }

        $displayOld = Expand-CursorPath $old
        $displayNew = Expand-CursorPath $new
        $msg = "$name changed: '$displayOld' -> '$displayNew'"

        if ($displayNew -match '(?i)\.(cur|ani)$' -and $displayNew -notmatch '(?i)\\windows\\cursors\\') {
            $msg += ' [non-standard cursor path]'
        }

        $kw = Get-MatchedCheatKeyword -Text $displayNew
        if ($kw) { $msg += " [keyword: $kw]" }

        $changes += $msg
    }
    return $changes
}

$script:NvidiaShadowPlayFtsRegPath = 'SOFTWARE\NVIDIA Corporation\Global\NvApp\ShadowPlay\FTS'

function Test-NvidiaGpuPresent {
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -ExpandProperty Name
        foreach ($gpu in $gpus) {
            if ($gpu -match '(?i)nvidia') { return $true }
        }
    } catch {}
    return $false
}

function Get-NvidiaShadowPlayFtsState {
    $state = @{
        Exists = $false
        Values = @{}
    }

    try {
        $key = Open-LocalMachineRegistryKey -SubKeyPath $script:NvidiaShadowPlayFtsRegPath
        if (-not $key) { return $state }

        $state.Exists = $true
        foreach ($name in $key.GetValueNames()) {
            $raw = $key.GetValue($name)
            if ($raw -is [int]) {
                $state.Values[$name] = [int]$raw
            } elseif ($raw -is [byte[]] -and $raw.Length -ge 4) {
                $state.Values[$name] = [BitConverter]::ToInt32($raw, 0)
            } else {
                $state.Values[$name] = [string]$raw
            }
        }
        $key.Close()
    } catch {}

    return $state
}

function Get-NvidiaShadowPlayFtsAlerts {
    $alerts = @()
    $state = Get-NvidiaShadowPlayFtsState
    $nvidiaGpu = Test-NvidiaGpuPresent

    if (-not $nvidiaGpu) {
        $alerts += 'SUCCESS: NVIDIA ShadowPlay N/A'
        return $alerts
    }

    if (-not $state.Exists -or $state.Values.Count -eq 0) {
        $alerts += 'SUCCESS: ShadowPlay FTS not present'
        return $alerts
    }

    foreach ($name in ($state.Values.Keys | Sort-Object)) {
        $alerts += "SUCCESS: ShadowPlay FTS $name = $($state.Values[$name])"
    }

    return $alerts
}

function Get-MainCplProcessHits {
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    $messages = @()

    foreach ($procName in @('rundll32.exe', 'control.exe')) {
        try {
            Get-CimInstance Win32_Process -Filter "Name='$procName'" -ErrorAction Stop | ForEach-Object {
                $cmd = [string]$_.CommandLine
                if ($cmd -notmatch '(?i)main\.cpl') { return }
                if (-not $seen.Add([int]$_.ProcessId)) { return }
                $messages += "main.cpl opened PID $($_.ProcessId)"
            }
        } catch {}
    }

    return $messages
}

$script:CheatKeywords = @(
    'matcha', 'isabelle', 'severe', 'aegis', 'potassium', 'lattice', 'spectre', 'matrix', 'clarity', 'loader', 'photon', 'valex', 'aimmy',
    'keyauth', 'xeno', 'melatonin', 'evolve', 'serotonin', 'ghostify', 'dx9ware', 'unicore', 'lumen', 'monolith', 'skript',
    'ntfsdump', 'atlanta', 'eulen', 'hammafia', 'redengine', 'susano', 'bypass', 'volt', 'fleasion',
    # Roblox executors / script hubs (BSMM additions)
    'wave', 'seliware', 'sirhurt', 'swift', 'solara', 'synapsex', 'synapse x', 'synapse z', 'synapsez', 'krnl',
    'fluxus', 'arceus', 'jjsploit', 'wearedevs', 'macsploit', 'hydrogen', 'vegax', 'vega x', 'scriptware',
    'script-ware', 'nihon', 'zenith', 'velocity', 'valyse', 'nezur', 'ronix', 'celery', 'cryptic', 'trigon',
    'oxygen', 'elysian', 'protosmasher', 'calamari', 'bunni', 'zorara', 'awpgg',
    # generic cheat tools
    'cheatengine', 'cheat engine', 'extremeinjector', 'injector', 'executor', 'aimbot', 'triggerbot', 'wallhack'
)

$script:FolderOnlyKeywords = @('map')

# Common words that only count as a whole word (so 'tModLoader' or 'WebView2Loader' do not match 'loader').
$script:TokenOnlyKeywords = @('loader', 'wave', 'swift', 'hydrogen', 'zenith', 'velocity', 'oxygen', 'cryptic', 'celery', 'nihon', 'trigon', 'aegis', 'injector', 'executor', 'bunni')

function Test-KeywordTokenMatch {
    param(
        [string]$Text,
        [string]$Keyword
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Keyword)) { return $false }
    $escaped = [regex]::Escape($Keyword)
    return [regex]::IsMatch($Text, "(?i)(^|[\\_\s\-\.])(($escaped))($|[\\_\s\-\.])")
}

function Test-TrustedProcessPath {
    param([string]$ExecutablePath)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $true }
    $path = $ExecutablePath.ToLower().Replace('/', '\')
    $prefixes = @(
        "$($env:SystemRoot.ToLower())\",
        "$($env:ProgramFiles.ToLower())\"
    )
    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86) { $prefixes += "$($pf86.ToLower())\" }
    foreach ($prefix in $prefixes) {
        if ($path.StartsWith($prefix)) { return $true }
    }
    return $false
}

$script:MasqueradeProcessPaths = @{
    'svchost.exe'       = @('\windows\system32\svchost.exe', '\windows\syswow64\svchost.exe')
    'explorer.exe'      = @('\windows\explorer.exe')
    'csrss.exe'         = @('\windows\system32\csrss.exe')
    'lsass.exe'         = @('\windows\system32\lsass.exe')
    'services.exe'      = @('\windows\system32\services.exe')
    'smss.exe'          = @('\windows\system32\smss.exe')
    'winlogon.exe'      = @('\windows\system32\winlogon.exe')
    'dwm.exe'           = @('\windows\system32\dwm.exe')
    'taskhostw.exe'     = @('\windows\system32\taskhostw.exe')
    'runtimebroker.exe' = @('\windows\system32\runtimebroker.exe')
    'conhost.exe'       = @('\windows\system32\conhost.exe', '\windows\syswow64\conhost.exe')
    'dllhost.exe'       = @('\windows\system32\dllhost.exe', '\windows\syswow64\dllhost.exe')
    'spoolsv.exe'       = @('\windows\system32\spoolsv.exe')
    'wininit.exe'       = @('\windows\system32\wininit.exe')
    'sihost.exe'        = @('\windows\system32\sihost.exe')
    'fontdrvhost.exe'   = @('\windows\system32\fontdrvhost.exe')
}

function Get-MatchedCheatKeyword {
    param(
        [string]$Text,
        [switch]$FolderName
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $lower = $Text.ToLower()

    if ($FolderName) {
        foreach ($kw in $script:CheatKeywords) {
            if ($kw -eq 'loader' -and $lower -match '(?i)\b[a-z0-9_-]*(download|upload|bootload|workload|dataload)er') { continue }
            if ($kw.Length -le 4 -or $script:TokenOnlyKeywords -contains $kw) {
                if (Test-KeywordTokenMatch -Text $lower -Keyword $kw) { return $kw }
            } elseif ($lower -like "*$kw*") {
                return $kw
            }
        }
        foreach ($kw in $script:FolderOnlyKeywords) {
            if (Test-KeywordTokenMatch -Text $lower -Keyword $kw) { return $kw }
        }
        return $null
    }

    foreach ($kw in $script:CheatKeywords) {
        if ($kw -eq 'loader' -and $lower -match '(?i)\b[a-z0-9_-]*(download|upload|bootload|workload|dataload)er') { continue }
        if ($kw.Length -le 4 -or $script:TokenOnlyKeywords -contains $kw) {
            if (Test-KeywordTokenMatch -Text $lower -Keyword $kw) { return $kw }
        } elseif ($lower -like "*$kw*") {
            return $kw
        }
    }
    return $null
}

function Get-PersistenceAlerts {
    $alerts = @()

    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    foreach ($keyPath in $runKeys) {
        try {
            $props = Get-ItemProperty -Path $keyPath -ErrorAction Stop
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -match '^PS(Path|ParentPath|ChildName|Provider)$') { continue }
                $value = [string]$prop.Value
                $kw = Get-MatchedCheatKeyword -Text $value
                if (-not $kw) { $kw = Get-MatchedCheatKeyword -Text $prop.Name }
                if ($kw) {
                    $alerts += "FAILURE: Autorun entry [$kw] '$($prop.Name)' in $keyPath -> $value"
                }
            }
        } catch {}
    }

    $startupFolders = @()
    try { $startupFolders += [Environment]::GetFolderPath('Startup') } catch {}
    try { $startupFolders += [Environment]::GetFolderPath('CommonStartup') } catch {}

    foreach ($folder in ($startupFolders | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder)) { continue }
        Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | ForEach-Object {
            $kw = Get-MatchedCheatKeyword -Text $_.Name
            if ($kw) { $alerts += "FAILURE: Startup item [$kw] -> $($_.FullName)" }
        }
    }

    try {
        Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' } | ForEach-Object {
            $task = $_
            if ($task.TaskPath -like '\Microsoft\Windows\*' -and $task.Author -match '(?i)^Microsoft') { return }

            $actions = @($task.Actions | ForEach-Object {
                if ($_.Execute) { "$($_.Execute) $($_.Arguments)".Trim() }
                elseif ($_.ClassId) { "(COM handler $($_.ClassId))" }
                else { '(no command)' }
            })
            $actionText = $actions -join '; '
            $lowerAction = $actionText.ToLower()
            $label = "'$($task.TaskPath)$($task.TaskName)' -> $actionText"

            $scriptHost = $lowerAction -match 'powershell|pwsh|cmd\.exe|wscript|cscript|mshta|rundll32'
            $marker     = $lowerAction -match 'bypass|hidden|encodedcommand|-enc |-e |appdata|temp\\|downloads|iex|invoke-expression|downloadstring'
            if ($scriptHost -and $marker) {
                $alerts += "FAILURE: Scheduled task launches a hidden/bypass script $label"
                return
            }

            $kw = Get-MatchedCheatKeyword -Text $actionText
            if ($kw) {
                $alerts += "FAILURE: Scheduled task [$kw] $label"
                return
            }

            $nameKw = Get-MatchedCheatKeyword -Text $task.TaskName
            if ($nameKw) { $alerts += "WARNING: Scheduled task name contains [$nameKw] $label" }
        }
    } catch {
        $alerts += 'WARNING: Could not enumerate scheduled tasks.'
    }

    $alerts += @(Get-ExtendedPersistenceAlerts)

    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: No suspicious autorun/persistence entries found.' }
    return @($alerts | Select-Object -Unique)
}

function Get-ExtendedPersistenceAlerts {
    $alerts = @()

    foreach ($keyPath in @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows'
    )) {
        try {
            $dlls = [string](Get-ItemPropertyValue -Path $keyPath -Name 'AppInit_DLLs' -ErrorAction Stop)
            if (-not [string]::IsNullOrWhiteSpace($dlls)) {
                $load = 0
                try { $load = [int](Get-ItemPropertyValue -Path $keyPath -Name 'LoadAppInit_DLLs' -ErrorAction Stop) } catch {}
                $state = if ($load -eq 1) { 'enabled' } else { 'not enabled' }
                $alerts += "WARNING: AppInit_DLLs set ($state) -> $dlls"
            }
        } catch {}
    }

    foreach ($ifeoRoot in @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    )) {
        try {
            Get-ChildItem -Path $ifeoRoot -ErrorAction Stop | ForEach-Object {
                $exeName = $_.PSChildName
                $debugger = $null
                try { $debugger = [string](Get-ItemPropertyValue -Path $_.PSPath -Name 'Debugger' -ErrorAction Stop) } catch {}
                if ($debugger) {
                    if ($exeName -match '(?i)roblox') {
                        $alerts += "FAILURE: Game launch trigger: IFEO Debugger on $exeName -> $debugger"
                    } else {
                        $alerts += "WARNING: IFEO Debugger on $exeName -> $debugger"
                    }
                }
                $spe = Join-Path $ifeoRoot "SilentProcessExit\$exeName"
                try {
                    $mon = [string](Get-ItemPropertyValue -Path $spe -Name 'MonitorProcess' -ErrorAction Stop)
                    if ($mon) { $alerts += "WARNING: SilentProcessExit monitor on $exeName -> $mon" }
                } catch {}
            }
        } catch {}
    }

    try {
        Get-CimInstance -Namespace 'root\subscription' -ClassName '__EventConsumer' -ErrorAction Stop | ForEach-Object {
            $cls = $_.CimClass.CimClassName
            if ($cls -eq 'NTEventLogEventConsumer' -and $_.Name -eq 'SCM Event Log Consumer') { return }
            $detail = ''
            if ($cls -eq 'CommandLineEventConsumer') { $detail = [string]$_.CommandLineTemplate }
            elseif ($cls -eq 'ActiveScriptEventConsumer') { $detail = ([string]$_.ScriptText) -replace '\s+', ' ' }
            if ($detail.Length -gt 160) { $detail = $detail.Substring(0, 160) + '...' }
            if ($cls -match 'CommandLine|ActiveScript') {
                $alerts += "WARNING: WMI event consumer '$($_.Name)' ($cls) -> $detail"
            } else {
                $alerts += "INFO: WMI event consumer '$($_.Name)' ($cls)"
            }
        }
    } catch {}

    try {
        $count = 0
        Get-ChildItem -Path 'HKCU:\Software\Classes\CLSID' -ErrorAction Stop | ForEach-Object {
            $count++
            if ($count -gt 400) { return }
            $inproc = Join-Path $_.PSPath 'InprocServer32'
            $target = $null
            try { $target = [string](Get-ItemPropertyValue -Path $inproc -Name '(default)' -ErrorAction Stop) } catch { return }
            if (-not $target) { return }
            $expanded = [Environment]::ExpandEnvironmentVariables($target.Trim('"'))
            if (-not (Test-Path -LiteralPath $expanded -PathType Leaf)) {
                $alerts += "WARNING: COM hijack candidate $($_.PSChildName) -> $expanded (file missing)"
                return
            }
            if (-not (Test-SignedByShippedRoot -Path $expanded)) {
                $alerts += "WARNING: COM hijack candidate $($_.PSChildName) -> $expanded (unsigned or untrusted signer)"
            }
        }
    } catch {}

    return $alerts
}

function Resolve-ExecutablePathFromCommandLine {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($expanded.StartsWith('\??\', [StringComparison]::OrdinalIgnoreCase)) {
        $expanded = $expanded.Substring(4)
    } elseif ($expanded.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $expanded = $expanded.Substring(4)
    }

    $match = [regex]::Match($expanded, '^\s*"([^"]+)"')
    if ($match.Success) { return $match.Groups[1].Value }

    $match = [regex]::Match($expanded, '^\s*(?<path>.*?\.sys)(?:\s+.*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) { return $match.Groups['path'].Value.Trim().Trim('"') }

    $tokens = $expanded -split '\s+'
    if ($tokens.Count -gt 1) {
        for ($i = $tokens.Count; $i -ge 1; $i--) {
            $candidate = ($tokens[0..($i - 1)] -join ' ').Trim().Trim('"')
            if (-not $candidate) { continue }
            try {
                if (Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction Stop) {
                    return $candidate
                }
            } catch {}
        }
    }

    $match = [regex]::Match($expanded, '^\s*(\S+)')
    if ($match.Success) { return $match.Groups[1].Value.Trim('"') }

    return $null
}

function Normalize-KernelDriverPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))

    if ($path.StartsWith('\??\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = $path.Substring(4)
    } elseif ($path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = $path.Substring(4)
    }

    if ($path.StartsWith('\SystemRoot\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = $env:SystemRoot + $path.Substring(11)
    } elseif ($path.StartsWith('SystemRoot\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = Join-Path $env:SystemRoot $path.Substring(11)
    } elseif ($path.StartsWith('System32\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = Join-Path $env:SystemRoot $path
    }

    return $path.Trim('"')
}

function Resolve-KernelDriverImagePath {
    param(
        [string]$ServiceName,
        [string]$PathName
    )

    $candidates = New-Object 'System.Collections.Generic.List[string]'

    $direct = Resolve-ExecutablePathFromCommandLine -CommandLine $PathName
    if ($direct) { [void]$candidates.Add($direct) }

    if ($ServiceName) {
        try {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
            $imagePath = Get-ItemPropertyValue -Path $regPath -Name ImagePath -ErrorAction Stop
            $fromRegistry = Resolve-ExecutablePathFromCommandLine -CommandLine ([string]$imagePath)
            if ($fromRegistry) { [void]$candidates.Add($fromRegistry) }
        } catch {}
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $normalized = Normalize-KernelDriverPath -Path $candidate
        if ([string]::IsNullOrWhiteSpace($normalized)) { continue }

        try {
            if (Test-Path -LiteralPath $normalized -PathType Leaf -ErrorAction Stop) {
                return (Get-Item -LiteralPath $normalized -Force -ErrorAction Stop).FullName
            }
        } catch {}
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $normalized = Normalize-KernelDriverPath -Path $candidate
        if ($normalized) { return $normalized }
    }

    return $null
}

function Get-SuspiciousDriverAlerts {
    $alerts = @()

    try {
        $drivers = Get-CimInstance -ClassName Win32_SystemDriver -ErrorAction Stop |
            Where-Object { $_.State -eq 'Running' }
    } catch {
        $alerts += 'WARNING: Could not enumerate kernel drivers.'
        return $alerts
    }

    foreach ($drv in $drivers) {
        $rawPath = [string]$drv.PathName
        $resolvedPath = Resolve-KernelDriverImagePath -ServiceName ([string]$drv.Name) -PathName $rawPath

        $kw = Get-MatchedCheatKeyword -Text $drv.Name
        if (-not $kw) { $kw = Get-MatchedCheatKeyword -Text $drv.DisplayName }
        if (-not $kw) { $kw = Get-MatchedCheatKeyword -Text $resolvedPath }

        if ($kw) {
            $alerts += "FAILURE: Suspicious kernel driver [$kw] $($drv.Name) -> $resolvedPath"
            continue
        }

        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            $alerts += "WARNING: Could not resolve kernel driver image path: $($drv.Name)"
            continue
        }

        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf -ErrorAction SilentlyContinue)) {
            $alerts += "WARNING: Kernel driver image not found/readable: $($drv.Name) -> $resolvedPath"
            continue
        }

        try {
            $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $resolvedPath -ErrorAction Stop
            $status = [string]$sig.Status

            switch ($status) {
                'Valid' {
                }
                'NotSigned' {
                    $entropy = Get-FileEntropy -FilePath $resolvedPath
                    $alerts += "WARNING: Unsigned kernel driver: $($drv.Name) [Entropy: $entropy] -> $resolvedPath"
                }
                'HashMismatch' {
                    $alerts += "FAILURE: Kernel driver signature hash mismatch: $($drv.Name) -> $resolvedPath"
                }
                'NotTrusted' {
                    if ($sig.SignerCertificate) {
                        $subject = [string]$sig.SignerCertificate.Subject
                        $alerts += "INFO: Kernel driver has a signature, but Windows could not establish trust: $($drv.Name) -> $resolvedPath [$subject]"
                    } else {
                        $alerts += "WARNING: Kernel driver signature could not be trusted: $($drv.Name) -> $resolvedPath"
                    }
                }
                'UnknownError' {
                    $alerts += "WARNING: Kernel driver signature verification returned UnknownError: $($drv.Name) -> $resolvedPath"
                }
                default {
                    $alerts += "WARNING: Kernel driver signature status is ${status}: $($drv.Name) -> $resolvedPath"
                }
            }
        } catch {
            $alerts += "WARNING: Could not verify kernel driver signature: $($drv.Name) -> $resolvedPath"
        }
    }

    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: No suspicious kernel drivers detected.' }
    return @($alerts | Select-Object -Unique)
}

function Normalize-ProcessImagePath {
    param([string]$ExecutablePath)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $null }

    $path = [Environment]::ExpandEnvironmentVariables($ExecutablePath.Trim().Trim('"')).Replace('/', '\')
    if ($path.StartsWith('\??\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = $path.Substring(4)
    } elseif ($path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = $path.Substring(4)
    }

    try {
        if ([IO.Path]::IsPathRooted($path)) {
            $path = [IO.Path]::GetFullPath($path)
        }
    } catch {}

    return $path.TrimEnd('\')
}

function Test-ClarityExpectedProcessPath {
    param(
        [string]$ProcessName,
        [string]$ExecutablePath
    )

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $false }

    $nameLower = ([string]$ProcessName).ToLower().Trim()
    if (-not $nameLower.EndsWith('.exe')) { $nameLower += '.exe' }
    $path = Normalize-ProcessImagePath -ExecutablePath $ExecutablePath
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }

    $root = Normalize-ProcessImagePath -ExecutablePath $env:SystemRoot
    $programData = Normalize-ProcessImagePath -ExecutablePath $env:ProgramData
    $leaf = Split-Path -Leaf $path

    switch ($nameLower) {
        'svchost.exe' {
            foreach ($suffix in @('\windows\system32\svchost.exe', '\windows\syswow64\svchost.exe')) {
                if ($path.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
            }
            return $false
        }
        'msmpeng.exe' {
            $prefix = Join-Path $programData 'Microsoft\Windows Defender\Platform'
            $prefix = Normalize-ProcessImagePath -ExecutablePath $prefix
            return ($leaf -ieq 'MsMpEng.exe' -and $path.StartsWith(($prefix + '\'), [StringComparison]::OrdinalIgnoreCase))
        }
        'tiworker.exe' {
            return ($leaf -ieq 'TiWorker.exe' -and $path.StartsWith(($root + '\'), [StringComparison]::OrdinalIgnoreCase) -and $path.Substring($root.Length).IndexOf('\', [StringComparison]::Ordinal) -ge 0)
        }
        default { return $false }
    }
}

function Test-MasqueradeProcessPath {
    param(
        [string]$ProcessName,
        [string]$ExecutablePath
    )

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $null }
    $nameLower = ([string]$ProcessName).ToLower()
    if (-not $nameLower.EndsWith('.exe')) { $nameLower += '.exe' }
    if (-not $script:MasqueradeProcessPaths.ContainsKey($nameLower)) { return $null }

    $path = Normalize-ProcessImagePath -ExecutablePath $ExecutablePath
    $systemRoot = Normalize-ProcessImagePath -ExecutablePath $env:SystemRoot
    $systemRootPrefix = $systemRoot + '\'

    if (-not $path.StartsWith($systemRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return "Windows process '$ProcessName' running from non-standard path: $ExecutablePath"
    }

    foreach ($legitSuffix in $script:MasqueradeProcessPaths[$nameLower]) {
        if ($path.EndsWith($legitSuffix, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    }

    return "Windows process '$ProcessName' running from non-standard path: $ExecutablePath"
}

function Get-SuspiciousProcessHits {
    $hits = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $messages = @()

    try {
        Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
            $procName = $_.Name
            $procPath = $_.ExecutablePath
            $procId = $_.ProcessId

            $masquerade = Test-MasqueradeProcessPath -ProcessName $procName -ExecutablePath $procPath
            if ($masquerade) {
                $key = "masquerade|$procName|$procPath"
                if ($hits.Add($key)) { $messages += "FAILURE: Masquerade $procName (PID $procId)" }
            }

            $nameKw = Get-MatchedCheatKeyword -Text $procName
            if ($nameKw) {
                $key = "name|$procName|$nameKw"
                if ($hits.Add($key)) { $messages += "FAILURE: $procName (PID $procId) [$nameKw]" }
            }

            if ($procPath -and -not (Test-TrustedProcessPath -ExecutablePath $procPath)) {
                $pathKw = Get-MatchedCheatKeyword -Text $procPath
                if ($pathKw) {
                    $key = "path|$procPath|$pathKw|$procId"
                    if ($hits.Add($key)) { $messages += "FAILURE: $procPath (PID $procId) [$pathKw]" }
                }
            }
        }
    } catch {
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            $nameKw = Get-MatchedCheatKeyword -Text $_.Name
            if ($nameKw) {
                $key = "name|$($_.Name)|$nameKw"
                if ($hits.Add($key)) { $messages += "FAILURE: $($_.Name) (PID $($_.Id)) [$nameKw]" }
            }
        }
    }

    return $messages
}

$script:MonitorProcessAllowlist = @(
    'robloxplayerbeta.exe',
    'fishstrap.exe',
    'robloxcrashhandler.exe',
    'bloxstrap.exe'
)

function Test-NoImagePathIgnoredProcess {
    param([string]$ProcessName)

    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $true }
    return $ProcessName -match '(?i)^(svchost|conhost|dllhost|RuntimeBroker|WmiPrvSE|SearchHost|ShellHost|ctfmon|sihost|taskhostw|spoolsv|lsass|services|smss|csrss|wininit|winlogon|fontdrvhost|dwm|explorer|msedgewebview2|SecurityHealthService|audiodg|smartscreen|SearchIndexer|Registry|NisSrv|MpDefenderCoreService|MsMpEng)\.exe$'
}

function Test-ShouldLogProcessMonitorEvent {
    param($Proc)

    $seriousReasons = @($Proc.Reasons | Where-Object { $_ -ne 'no image path' })
    $nameLower = [string]$Proc.Name
    if ($nameLower) { $nameLower = $nameLower.ToLower() }

    if ($nameLower -and $script:MonitorProcessAllowlist -contains $nameLower) {
        if ($seriousReasons.Count -eq 0) { return $false }
    }

    if ($seriousReasons.Count -gt 0) { return $true }
    if ($Proc.UserLand) { return $true }
    return $false
}

function Get-ProcessSuspiciousReasons {
    param(
        [string]$ProcessName,
        [string]$ExecutablePath
    )

    $reasons = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        if ($ProcessName -notmatch '(?i)^(System|Registry|Secure System|Memory Compression|Idle)$') {
            if (-not (Test-NoImagePathIgnoredProcess -ProcessName $ProcessName)) {
                [void]$reasons.Add('no image path')
            }
        }
    } else {
        $leaf = Split-Path $ExecutablePath -Leaf
        if ($ProcessName -and $leaf -and ($ProcessName.ToLower() -ne $leaf.ToLower())) {
            [void]$reasons.Add('name/path mismatch')
        }
    }

    if (Test-MasqueradeProcessPath -ProcessName $ProcessName -ExecutablePath $ExecutablePath) {
        [void]$reasons.Add('masquerade')
    }

    $nameKw = Get-MatchedCheatKeyword -Text $ProcessName
    if ($nameKw) { [void]$reasons.Add($nameKw) }

    if ($ExecutablePath) {
        $pathKw = Get-MatchedCheatKeyword -Text $ExecutablePath
        if ($pathKw) { [void]$reasons.Add($pathKw) }
    }

    return @($reasons)
}

function Test-UserLandProcessPath {
    param([string]$ExecutablePath)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $false }
    $path = $ExecutablePath.ToLower().Replace('/', '\')
    foreach ($marker in @('\downloads\', '\desktop\', '\temp\')) {
        if ($path -like "*$marker*") { return $true }
    }
    return $false
}

function Get-ProcessSnapshot {
    $snap = @{}
    try {
        Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
            $procId = [int]$_.ProcessId
            $path = [string]$_.ExecutablePath
            $name = [string]$_.Name
            $cmd  = [string]$_.CommandLine
            $reasons = @(Get-ProcessSuspiciousReasons -ProcessName $name -ExecutablePath $path)
            $snap[$procId] = @{
                Name        = $name
                Path        = $path
                CommandLine = $cmd
                Reasons     = $reasons
                UserLand    = Test-UserLandProcessPath -ExecutablePath $path
                Suspicious  = ($reasons.Count -gt 0)
            }
        }
    } catch { return $null }
    return $snap
}

function Update-ProcessChangeMonitor {
    param(
        [hashtable]$Previous,
        [hashtable]$Current,
        [hashtable]$Watched,
        [string]$LogFile
    )

    foreach ($procId in $Current.Keys) {
        if ($Previous.ContainsKey($procId)) { continue }

        $proc = $Current[$procId]
        $name = [string]$proc.Name
        $cmd  = [string]$proc.CommandLine

        $isNotepad = ($name -ieq 'notepad.exe')
        $isBat     = ($name -ieq 'cmd.exe') -and ($cmd -match '\.bat(\b|"|\s|$)')
        $isVbs     = ($name -imatch '^(wscript|cscript)\.exe$') -and ($cmd -match '\.vbs(\b|"|\s|$)')

        if ($isNotepad -or $isBat -or $isVbs) {
            $toolTag = if ($isNotepad) { 'Notepad' } elseif ($isBat) { 'Batch (.bat)' } else { 'VBScript (.vbs)' }
            $argInfo = if ($cmd) { " [$cmd]" } else { "" }
            Write-MonitorAlert -Message "Script/Editor Launched ($toolTag): $name (PID $procId)$argInfo" -LogFile $LogFile -Level WARN
            $Watched[$procId] = $proc
            continue
        }

        if (-not (Test-ShouldLogProcessMonitorEvent -Proc $proc)) { continue }

        $label = "$($proc.Name) (PID $procId)"
        if ($proc.Path) { $label += " -> $($proc.Path)" }

        $tags = @($proc.Reasons | Where-Object { $_ -ne 'no image path' })
        if ($tags.Count -gt 0) {
            $level = if ($tags -match 'masquerade' -or ($tags | Where-Object { $_ -ne 'name/path mismatch' }).Count -gt 0) { 'FAIL' } else { 'WARN' }
            Write-MonitorAlert -Message "Started [$($tags -join ', ')]: $label" -LogFile $LogFile -Level $level
        } else {
            Write-MonitorAlert -Message "Started [userland]: $label" -LogFile $LogFile -Level WARN
        }
        $Watched[$procId] = $proc
    }

    foreach ($procId in $Previous.Keys) {
        if ($Current.ContainsKey($procId)) { continue }
        if (-not $Watched.ContainsKey($procId)) { continue }

        $proc = $Previous[$procId]
        $label = "$($proc.Name) (PID $procId)"
        if ($proc.Path) { $label += " -> $($proc.Path)" }

        $tags = @($proc.Reasons | Where-Object { $_ -ne 'no image path' })
        if ($tags.Count -gt 0) {
            Write-MonitorAlert -Message "Exited [$($tags -join ', ')]: $label" -LogFile $LogFile -Level INFO
        } else {
            Write-MonitorAlert -Message "Exited [userland]: $label" -LogFile $LogFile -Level INFO
        }
        $Watched.Remove($procId) | Out-Null
    }
}

$script:ExternalReaderAllowlist = @(
    'robloxplayerbeta', 'robloxcrashhandler', 'robloxplayerlauncher',
    'bloxstrap', 'fishstrap', 'lunarstrap',
    'msmpeng', 'nissrv', 'securityhealthservice', 'mpdefendercoreservice',
    'csrss', 'lsass', 'wininit', 'services', 'searchindexer', 'wmiprvse',
    'procexp', 'procexp64', 'taskmgr', 'perfmon', 'resmon'
)

$script:CaptureWindowAllowlist = @(
    'logonui', 'consent', 'dwm', 'textinputhost', 'screenclippinghost',
    'snippingtool', 'searchhost', 'startmenuexperiencehost',
    'applicationframehost', 'systemsettings', 'shellexperiencehost'
)

function Initialize-ExternalScanApi {
    if ('BSMM.ExternalScan' -as [type]) { return $true }
    try {
        Add-Type -Namespace BSMM -Name ExternalScan -UsingNamespace System.Text, System.Collections.Generic -MemberDefinition @'
[DllImport("user32.dll")]
private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
[DllImport("user32.dll")]
private static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll", SetLastError = true)]
private static extern bool GetWindowDisplayAffinity(IntPtr hWnd, out uint dwAffinity);
[DllImport("user32.dll", SetLastError = true)]
private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
private static extern int GetClassNameW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
[DllImport("ntdll.dll")]
private static extern int NtQuerySystemInformation(int infoClass, IntPtr buffer, int length, out int returnLength);
[DllImport("kernel32.dll", SetLastError = true)]
private static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("kernel32.dll", SetLastError = true)]
private static extern bool DuplicateHandle(IntPtr srcProc, IntPtr srcHandle, IntPtr tgtProc, out IntPtr tgtHandle, uint access, bool inherit, uint options);
[DllImport("kernel32.dll", SetLastError = true)]
private static extern bool CloseHandle(IntPtr h);
[DllImport("kernel32.dll", SetLastError = true)]
private static extern int GetProcessId(IntPtr h);
[DllImport("kernel32.dll")]
private static extern IntPtr GetCurrentProcess();

private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

private const int SystemExtendedHandleInformation = 0x40;
private const uint PROCESS_DUP_HANDLE = 0x0040;
private const uint PROCESS_VM_READ = 0x0010;
private const uint DUPLICATE_SAME_ACCESS = 0x0002;

private static List<string> _winHits;
private static EnumWindowsProc _winCb;

private static bool WindowCallback(IntPtr hWnd, IntPtr lParam) {
    try {
        if (!IsWindowVisible(hWnd)) { return true; }
        uint affinity;
        if (!GetWindowDisplayAffinity(hWnd, out affinity)) { return true; }
        if (affinity == 0) { return true; }
        uint pid = 0;
        GetWindowThreadProcessId(hWnd, out pid);
        StringBuilder title = new StringBuilder(256);
        GetWindowTextW(hWnd, title, title.Capacity);
        StringBuilder cls = new StringBuilder(256);
        GetClassNameW(hWnd, cls, cls.Capacity);
        _winHits.Add(pid.ToString() + "|" + affinity.ToString() + "|" + title.ToString() + "|" + cls.ToString());
    } catch { }
    return true;
}

public static string[] FindCaptureProtectedWindows() {
    _winHits = new List<string>();
    _winCb = new EnumWindowsProc(WindowCallback);
    bool ok = false;
    try { ok = EnumWindows(_winCb, IntPtr.Zero); } catch { return null; }
    if (!ok) { return null; }
    return _winHits.ToArray();
}

public static int[] FindRobloxMemoryReaders(int[] targetPids) {
    List<int> readers = new List<int>();
    if (targetPids == null || targetPids.Length == 0) { return readers.ToArray(); }
    HashSet<int> targets = new HashSet<int>(targetPids);

    int length = 0x20000;
    IntPtr buffer = Marshal.AllocHGlobal(length);
    try {
        int needed = 0;
        int status = 0;
        for (int tries = 0; tries < 16; tries++) {
            status = NtQuerySystemInformation(SystemExtendedHandleInformation, buffer, length, out needed);
            if (status == unchecked((int)0xC0000004)) {
                Marshal.FreeHGlobal(buffer);
                length = (needed > length ? needed : length * 2) + 0x10000;
                buffer = Marshal.AllocHGlobal(length);
                continue;
            }
            break;
        }
        if (status != 0) { return null; }

        int ptr = IntPtr.Size;
        long handleCount = Marshal.ReadIntPtr(buffer).ToInt64();
        int headerSize = ptr * 2;
        int entrySize = ptr * 3 + 16;

        IntPtr self = GetCurrentProcess();
        Dictionary<int, IntPtr> opened = new Dictionary<int, IntPtr>();
        HashSet<int> done = new HashSet<int>();

        for (long i = 0; i < handleCount; i++) {
            int offset = (int)(headerSize + i * entrySize);
            int ownerPid = (int)Marshal.ReadIntPtr(buffer, offset + ptr).ToInt64();
            if (ownerPid <= 4) { continue; }
            if (done.Contains(ownerPid)) { continue; }
            if (targets.Contains(ownerPid)) { continue; }
            uint access = (uint)Marshal.ReadInt32(buffer, offset + ptr * 3);
            if ((access & PROCESS_VM_READ) == 0) { continue; }
            IntPtr handleValue = Marshal.ReadIntPtr(buffer, offset + ptr * 2);

            IntPtr owner;
            if (!opened.TryGetValue(ownerPid, out owner)) {
                owner = OpenProcess(PROCESS_DUP_HANDLE, false, ownerPid);
                opened[ownerPid] = owner;
            }
            if (owner == IntPtr.Zero) { continue; }

            IntPtr dup;
            if (!DuplicateHandle(owner, handleValue, self, out dup, 0, false, DUPLICATE_SAME_ACCESS)) { continue; }
            try {
                int objPid = GetProcessId(dup);
                if (objPid != 0 && targets.Contains(objPid)) {
                    readers.Add(ownerPid);
                    done.Add(ownerPid);
                }
            } catch { } finally {
                CloseHandle(dup);
            }
        }

        foreach (KeyValuePair<int, IntPtr> kv in opened) {
            if (kv.Value != IntPtr.Zero) { CloseHandle(kv.Value); }
        }
    } catch {
        return null;
    } finally {
        Marshal.FreeHGlobal(buffer);
    }
    return readers.ToArray();
}
'@ -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-RobloxTargetIds {
    $ids = New-Object 'System.Collections.Generic.List[int]'
    try {
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -match '(?i)^RobloxPlayerBeta$' } |
            ForEach-Object { $ids.Add([int]$_.Id) }
    } catch {}
    return @($ids)
}

function Resolve-ProcessIdentity {
    param([int]$TargetPid)

    try {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$TargetPid" -ErrorAction Stop | Select-Object -First 1
        if ($p) { return @{ Name = [string]$p.Name; Path = [string]$p.ExecutablePath } }
    } catch {}
    try {
        $p = Get-Process -Id $TargetPid -ErrorAction Stop
        return @{ Name = "$($p.ProcessName).exe"; Path = [string]$p.Path }
    } catch {}
    return @{ Name = "PID $TargetPid"; Path = '' }
}

function Get-ProcessForensicDetails {
    param([int]$TargetPid)

    $details = [ordered]@{
        Pid             = $TargetPid
        Name            = "PID $TargetPid"
        Path            = ''
        CommandLine     = ''
        ParentPid       = 0
        ParentName      = ''
        Services        = @()
        ForeignModules  = @()
        UnsignedModules = @()
        SignatureStatus = 'Unknown'
        Signer          = ''
    }

    try {
        $cimProc = Get-CimInstance Win32_Process -Filter "ProcessId=$TargetPid" -ErrorAction Stop | Select-Object -First 1
        if ($cimProc) {
            if ($cimProc.Name) { $details.Name = [string]$cimProc.Name }
            if ($cimProc.ExecutablePath) { $details.Path = [string]$cimProc.ExecutablePath }
            if ($cimProc.CommandLine) { $details.CommandLine = [string]$cimProc.CommandLine }
            if ($cimProc.ParentProcessId) {
                $details.ParentPid = [int]$cimProc.ParentProcessId
                try {
                    $pParent = Get-Process -Id $details.ParentPid -ErrorAction Stop
                    $details.ParentName = "$($pParent.ProcessName).exe"
                } catch {
                    $details.ParentName = "PID $($details.ParentPid)"
                }
            }
        }
    } catch {}

    if (-not $details.Path) {
        try {
            $p = Get-Process -Id $TargetPid -ErrorAction Stop
            $details.Name = "$($p.ProcessName).exe"
            $details.Path = [string]$p.Path
        } catch {}
    }

    try {
        $svcs = @(Get-CimInstance Win32_Service -Filter "ProcessId=$TargetPid" -ErrorAction Stop)
        foreach ($s in $svcs) {
            $details.Services += "$($s.Name) ($($s.DisplayName))"
        }
    } catch {}

    if ($details.Path -and (Test-Path -LiteralPath $details.Path)) {
        try {
            $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $details.Path -ErrorAction Stop
            $details.SignatureStatus = [string]$sig.Status
            if ($sig.SignerCertificate) {
                $details.Signer = [string]$sig.SignerCertificate.Subject
            }
        } catch {}
    }

    try {
        $proc = Get-Process -Id $TargetPid -ErrorAction Stop
        $mainExePath = [string]$details.Path
        $mainExeDir = if ($mainExePath) { [System.IO.Path]::GetDirectoryName($mainExePath) } else { '' }
        $procNameLower = ($details.Name -replace '\.exe$', '').ToLower()

        foreach ($mod in $proc.Modules) {
            $modPath = [string]$mod.FileName
            if ([string]::IsNullOrWhiteSpace($modPath)) { continue }

            if ($mainExePath -and [string]::Equals($modPath, $mainExePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $isUnderWinDir = $modPath.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)
            $isDefenderDir = ($modPath -like "$env:ProgramData\Microsoft\Windows Defender\Platform\*" -or $modPath -like "$env:ProgramFiles\Windows Defender\*")

            $modSig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $modPath -ErrorAction SilentlyContinue
            $status = if ($modSig) { [string]$modSig.Status } else { 'Unknown' }
            $subj = if ($modSig -and $modSig.SignerCertificate) { [string]$modSig.SignerCertificate.Subject } else { 'Unsigned' }
            $isMsSigned = ($status -eq 'Valid' -and ($subj -match 'Microsoft Windows|Microsoft Corporation'))

            if (($isUnderWinDir -or $isDefenderDir) -and $isMsSigned) {
                continue
            }

            if ($procNameLower -eq 'svchost' -and $isMsSigned) {
                continue
            }

            if ($procNameLower -in @('robloxplayerbeta', 'robloxcrashhandler', 'robloxplayerlauncher') -or $details.Name -match '(?i)roblox') {
                $isRobloxSigned = ($status -eq 'Valid' -and ($subj -match 'Roblox Corporation'))
                $isRobloxDir = ($mainExeDir -and $modPath.StartsWith($mainExeDir, [System.StringComparison]::OrdinalIgnoreCase))
                if ($isRobloxSigned -or $isRobloxDir) {
                    continue
                }
            }

            $isUserland = (Test-UserLandProcessPath -ExecutablePath $modPath)

            if ($status -ne 'Valid' -or $isUserland -or (-not $isMsSigned)) {
                $details.ForeignModules += @{
                    Name   = [string]$mod.ModuleName
                    Path   = $modPath
                    Status = $status
                    Signer = $subj
                }
                if ($status -ne 'Valid') {
                    $details.UnsignedModules += $modPath
                }
            }
        }
    } catch {}

    return $details
}

function Get-ServiceRootCauseDescription {
    param([string[]]$ServiceNames)

    $causes = New-Object System.Collections.Generic.List[string]
    foreach ($s in @($ServiceNames)) {
        $sLower = ($s -split ' ')[0].ToLower()
        switch ($sLower) {
            'winmgmt'              { $causes.Add('WMI Process Queries (hardware/performance metrics)') }
            'themes'               { $causes.Add('Desktop Window Theming (DWM visual styles & window composition)') }
            'sysmain'              { $causes.Add('Superfetch / RAM Cache (automatic memory page optimization)') }
            'audiosrv'             { $causes.Add('Windows Audio Engine (per-app volume mixer & session tracking)') }
            'audioendpointbuilder' { $causes.Add('Audio Device Management (active audio endpoints)') }
            'schedule'             { $causes.Add('Task Scheduler (background OS system maintenance)') }
            'appinfo'              { $causes.Add('Application Information (UAC application execution & elevation)') }
            'shellhwdetection'     { $causes.Add('Shell Hardware Detection (device/media monitoring)') }
            'diagtrack'            { $causes.Add('Diagnostic Telemetry (system diagnostic sampling)') }
            'bits'                 { $causes.Add('BITS (background system update transfer)') }
            'wsearch'              { $causes.Add('Windows Search (indexing desktop application metadata)') }
            'wersvc'               { $causes.Add('Windows Error Reporting (crash dump preparation)') }
            'usermgr'              { $causes.Add('User Manager (desktop user session handling)') }
            'usermanager'          { $causes.Add('User Manager (desktop user session handling)') }
            'usosvc'               { $causes.Add('Update Orchestrator (Windows update coordinator)') }
            'wpnservice'           { $causes.Add('Push Notifications (Windows notification system)') }
            'gpsvc'                { $causes.Add('Group Policy (system policy enforcement)') }
            'seclogon'             { $causes.Add('Secondary Logon (run-as credential helper)') }
            'lanmanserver'         { $causes.Add('Server Service (network resource sharing)') }
            'iphlpsvc'             { $causes.Add('IP Helper (network protocol management)') }
            'wlidsvc'              { $causes.Add('Microsoft Account Sign-in (live identity session helper)') }
            'dusmsvc'              { $causes.Add('Data Usage (network traffic monitoring)') }
            'dps'                  { $causes.Add('Diagnostic Policy Service (system health & performance diagnostics)') }
            'wscsvc'               { $causes.Add('Security Center (Windows security monitoring)') }
            'coremessagingregistrar' { $causes.Add('Core Messaging (XAML UI event dispatcher)') }
            'sens'                 { $causes.Add('System Event Notification (OS system events)') }
            'nsi'                  { $causes.Add('Network Store Interface (network state tracking)') }
            'netman'               { $causes.Add('Network Connections (adapter monitoring)') }
            'dnscache'             { $causes.Add('DNS Client (domain name resolution cache)') }
            'dhcp'                 { $causes.Add('DHCP Client (IP address lease management)') }
            'wuauserv'             { $causes.Add('Windows Update (OS security updates)') }
            'bfe'                  { $causes.Add('Base Filtering Engine (Windows firewall engine)') }
            'mpssvc'               { $causes.Add('Windows Defender Firewall (network packet filtering)') }
        }
    }

    if ($causes.Count -eq 0) { return 'Standard Windows background service operation' }
    return (($causes | Select-Object -Unique) -join '; ')
}

function Get-RobloxVersionInfo {
    $result = [pscustomobject]@{
        Installed      = $false
        IsRunning      = $false
        Pid            = 0
        Path           = ''
        FileVersion    = ''
        ProductVersion = ''
        VersionHash    = ''
        Is64Bit        = $false
    }

    try {
        $proc = Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc -and $proc.Path -and (Test-Path -LiteralPath $proc.Path -PathType Leaf)) {
            $result.IsRunning = $true
            $result.Pid       = [int]$proc.Id
            $result.Path      = [string]$proc.Path
        }
    } catch {}

    if (-not $result.Path) {
        $searchDirs = @(
            (Join-Path $env:LOCALAPPDATA 'Roblox\Versions'),
            (Join-Path $env:LOCALAPPDATA 'Bloxstrap\Versions'),
            (Join-Path $env:LOCALAPPDATA 'Fishstrap\Versions')
        )
        $candidates = @()
        foreach ($dir in $searchDirs) {
            if (Test-Path -LiteralPath $dir -PathType Container) {
                try {
                    $found = Get-ChildItem -LiteralPath $dir -Filter 'RobloxPlayerBeta.exe' -Recurse -File -ErrorAction SilentlyContinue
                    if ($found) { $candidates += $found }
                } catch {}
            }
        }
        if ($candidates.Count -gt 0) {
            $latest = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $result.Path = $latest.FullName
        }
    }

    if (-not $result.Path -or -not (Test-Path -LiteralPath $result.Path -PathType Leaf)) {
        return $result
    }

    $result.Installed = $true
    try {
        $fvi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($result.Path)
        $result.FileVersion    = [string]$fvi.FileVersion
        $result.ProductVersion = [string]$fvi.ProductVersion
    } catch {}

    $parent = Split-Path -Path $result.Path -Parent
    if ($parent) {
        $result.VersionHash = Split-Path -Path $parent -Leaf
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($result.Path)
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
        $result.Is64Bit = ($machine -eq 0x8664)
    } catch {}

    return $result
}

function Get-RobloxVersionAlerts {
    $alerts = @()
    $v = Get-RobloxVersionInfo

    if (-not $v.Installed) {
        $alerts += "WARNING: Roblox installation not found in %LocalAppData%"
        return $alerts
    }

    $arch = if ($v.Is64Bit) { "x64" } else { "x86" }
    $runTag = if ($v.IsRunning) { " (ACTIVE - PID $($v.Pid))" } else { " (Inactive/Last Installed)" }

    $alerts += "INFO: Client Status$runTag"
    $alerts += "SUCCESS: Build Hash -> $($v.VersionHash)"
    $alerts += "SUCCESS: File Version -> $($v.FileVersion) ($arch)"
    if ($v.ProductVersion -and ($v.ProductVersion -ne $v.FileVersion)) {
        $alerts += "INFO: Product Version -> $($v.ProductVersion)"
    }
    $alerts += "INFO: Executable -> $($v.Path)"

    return $alerts
}

function Get-ExternalCheatHits {
    if (-not (Initialize-ExternalScanApi)) {
        return 'WARNING: External scan unavailable'
    }

    $messages = @()

    $targets = @(Get-RobloxTargetIds)
    if ($targets.Count -gt 0) {
        $rawReaders = $null
        try { $rawReaders = [BSMM.ExternalScan]::FindRobloxMemoryReaders([int[]]$targets) } catch {}
        if ($null -eq $rawReaders) {
            $messages += 'WARNING: Memory-reader scan failed to run (results may be incomplete)'
        } else {
            $knownBenignServices = @(
                'sysmain', 'audiosrv', 'audioendpointbuilder', 'diagtrack', 'wsearch', 'wersvc',
                'dcomlaunch', 'rpcss', 'cryptsvc', 'winmgmt', 'themes', 'schedule', 'appinfo',
                'shellhwdetection', 'bits', 'iphlpsvc', 'lanmanserver', 'seclogon', 'usermgr', 'usermanager',
                'usosvc', 'wpnservice', 'gpsvc', 'profsvc', 'eventlog', 'plugplay', 'samss',
                'nsi', 'netman', 'dnscache', 'dhcp', 'wuauserv', 'bfe', 'mpssvc', 'wlidsvc',
                'dusmsvc', 'dps', 'wscsvc', 'coremessagingregistrar', 'sens'
            )
            foreach ($ownerId in (@($rawReaders) | Select-Object -Unique)) {
                $diag = Get-ProcessForensicDetails -TargetPid $ownerId
                $nameLower = ($diag.Name -replace '\.exe$', '').ToLower()

                if ($nameLower -in @('robloxplayerbeta', 'robloxcrashhandler', 'robloxplayerlauncher')) {
                    if ($diag.SignatureStatus -eq 'Valid' -and ($diag.Signer -match 'Roblox Corporation') -and $diag.ForeignModules.Count -eq 0) {
                        continue
                    }
                }

                if ($script:ExternalReaderAllowlist -contains $nameLower) {
                    if ($diag.UnsignedModules.Count -eq 0 -and $diag.ForeignModules.Count -eq 0) {
                        continue
                    }
                }

                if ($nameLower -eq 'svchost') {
                    if ($diag.ForeignModules.Count -gt 0) {
                        $fModList = ($diag.ForeignModules | ForEach-Object { "$($_.Name) [$($_.Status)] -> $($_.Path)" }) -join '; '
                        $entry = "FAILURE: Injected foreign DLL inside svchost.exe reading Roblox memory (PID $ownerId) -> $($diag.Path)"
                        $entry += "`n  |-> Root Cause: Foreign/unauthorized module loaded inside Windows Service Host"
                        $entry += "`n  |-> Why this was FLAGGED:"
                        $entry += "`n      [FAIL] Foreign/Injected Modules: $fModList"
                        $entry += "`n      [FAIL] Process Tampering: svchost.exe modified with foreign userland code"
                        $entry += "`n      [INFO] Hosted Services: $(if ($diag.Services.Count -gt 0) { $diag.Services -join ', ' } else { 'None' })"
                        if ($diag.ParentName) { $entry += "`n      [INFO] Parent Process: $($diag.ParentName) (PID $($diag.ParentPid))" }
                        if ($diag.CommandLine) { $entry += "`n      [INFO] Command Line: $($diag.CommandLine)" }
                        $entry += "`n  |-> Conclusion: Service host hijacking / DLL injection cheat."
                        $messages += $entry
                        continue
                    }

                    $allKnown = $true
                    $svcNames = @()
                    foreach ($svc in $diag.Services) {
                        $sName = ($svc -split ' ')[0].ToLower()
                        $svcNames += $sName
                        if ($knownBenignServices -notcontains $sName) { $allKnown = $false }
                    }

                    if ($allKnown -and $svcNames.Count -gt 0) {
                        $causeDesc = Get-ServiceRootCauseDescription -ServiceNames $svcNames
                        $entry = "INFO: Benign Windows Service inspecting Roblox memory: svchost.exe (PID $ownerId)"
                        $entry += "`n  |-> Hosted Services: $($diag.Services -join ', ')"
                        $entry += "`n  |-> What Caused It: $causeDesc"
                        $entry += "`n  |-> Why this is NOT a cheat:"
                        $entry += "`n      [PASS] Parent Verified: $($diag.ParentName) (PID $($diag.ParentPid)) [Windows Service Control Manager]"
                        $entry += "`n      [PASS] Binary Verified: Genuine Microsoft-signed binary ($($diag.Path))"
                        $entry += "`n      [PASS] Module Integrity: All loaded DLLs are Microsoft-signed (0 injected/userland DLLs)"
                        $entry += "`n      [PASS] Memory Access: Standard read-only OS query handles (no code injection, no memory patching)"
                        $entry += "`n  |-> Conclusion: Legitimate Windows OS background operation. Completely safe."
                        $messages += $entry
                        continue
                    } elseif ($diag.Services.Count -gt 0) {
                        $entry = "WARNING: Unrecognized service reading Roblox memory: svchost.exe (PID $ownerId)"
                        $entry += "`n  |-> Hosted Services: $($diag.Services -join ', ')"
                        if ($diag.CommandLine) { $entry += "`n  |-> Command Line: $($diag.CommandLine)" }
                        if ($diag.ParentName) { $entry += "`n  |-> Parent Process: $($diag.ParentName) (PID $($diag.ParentPid))" }
                        $entry += "`n  |-> Investigation Needed: Service name is not recognized as a standard Windows core service."
                        $messages += $entry
                        continue
                    }
                }

                if ((Test-TrustedHandleHolder -ExecutablePath $diag.Path) -and $diag.ForeignModules.Count -eq 0) {
                    continue
                }

                $label = "$($diag.Name) (PID $ownerId)"
                if ($diag.Path) { $label += " -> $($diag.Path)" }
                $entry = "FAILURE: Unauthorized process reading Roblox memory: $label"
                $entry += "`n  |-> Root Cause: Opened PROCESS_VM_READ handle directly to RobloxPlayerBeta.exe"
                $entry += "`n  |-> Why this was FLAGGED:"
                if ($diag.Services.Count -gt 0) {
                    $entry += "`n      [!] Hosted Services: $($diag.Services -join ', ')"
                }
                if ($diag.ParentName) {
                    $entry += "`n      [!] Parent Process: $($diag.ParentName) (PID $($diag.ParentPid))"
                }
                if ($diag.CommandLine) {
                    $cmdDisp = if ($diag.CommandLine.Length -gt 150) { $diag.CommandLine.Substring(0, 147) + '...' } else { $diag.CommandLine }
                    $entry += "`n      [!] Command Line: $cmdDisp"
                }
                if ($diag.SignatureStatus) {
                    $entry += "`n      [!] Signature: $($diag.SignatureStatus)$(if ($diag.Signer) { " ($($diag.Signer))" })"
                }
                if ($diag.ForeignModules.Count -gt 0) {
                    $fModList = ($diag.ForeignModules | ForEach-Object { "$($_.Name) [$($_.Status)] -> $($_.Path)" }) -join '; '
                    $entry += "`n      [!] Loaded Foreign/Injected DLLs: $fModList"
                }
                $entry += "`n  |-> Conclusion: Non-system process reading game memory without authorization."
                $messages += $entry
            }
        }
    }

    $rawWindows = $null
    try { $rawWindows = [BSMM.ExternalScan]::FindCaptureProtectedWindows() } catch {}
    if ($null -eq $rawWindows) {
        $messages += 'WARNING: Capture-protected window scan failed to run (results may be incomplete)'
    }
    $windows = @($rawWindows)
    foreach ($w in $windows) {
        $parts = $w -split '\|', 4
        if ($parts.Count -lt 2) { continue }
        $winPid = 0
        [void][int]::TryParse($parts[0], [ref]$winPid)
        if ($winPid -eq $PID -or $winPid -le 0) { continue }

        $info = Resolve-ProcessIdentity -TargetPid $winPid
        $nameLower = ($info.Name -replace '\.exe$', '').ToLower()
        if ($script:CaptureWindowAllowlist -contains $nameLower) { continue }

        $affLabel = switch ($parts[1]) {
            '1'  { 'WDA_MONITOR' }
            '17' { 'WDA_EXCLUDEFROMCAPTURE' }
            default { "affinity=$($parts[1])" }
        }
        $title = if ($parts.Count -ge 3 -and $parts[2]) { " '$($parts[2])'" } else { '' }
        $label = "$($info.Name) (PID $winPid)$title [$affLabel]"

        if ($info.Path -and -not (Test-TrustedProcessPath -ExecutablePath $info.Path)) {
            $messages += "FAILURE: Window hidden from capture $label -> $($info.Path)"
        } else {
            $messages += "WARNING: Window hidden from capture $label"
        }
    }

    if ($messages.Count -eq 0) {
        return 'SUCCESS: No external/overlay cheat detected'
    }
    if (-not ($messages | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $messages = @('SUCCESS: No unauthorized memory readers or hidden overlays detected') + $messages
    }
    return $messages
}

$script:LogonTime = $null

function Get-LogonTime {
    if ($script:LogonTime) { return $script:LogonTime }
    try {
        $exp = Get-Process -Name explorer -ErrorAction Stop | Sort-Object StartTime | Select-Object -First 1
        if ($exp -and $exp.StartTime) { $script:LogonTime = $exp.StartTime; return $script:LogonTime }
    } catch {}
    try {
        $script:LogonTime = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
    } catch {
        $script:LogonTime = (Get-Date).AddHours(-12)
    }
    return $script:LogonTime
}

function Get-BootTime {
    try { return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime } catch { return $null }
}

function Get-BamEntries {
    $entries = @()
    $roots = @(
        'SYSTEM\CurrentControlSet\Services\bam\State\UserSettings',
        'SYSTEM\CurrentControlSet\Services\dam\State\UserSettings'
    )
    foreach ($root in $roots) {
        try {
            $rootKey = Open-LocalMachineRegistryKey -SubKeyPath $root
            if (-not $rootKey) { continue }
            foreach ($sidName in $rootKey.GetSubKeyNames()) {
                if ($sidName -eq 'S-1-5-18') { continue }
                $sidKey = $rootKey.OpenSubKey($sidName)
                if (-not $sidKey) { continue }
                foreach ($valueName in $sidKey.GetValueNames()) {
                    if (-not $valueName -or $valueName -notmatch '\\') { continue }
                    $raw = $sidKey.GetValue($valueName)
                    if (-not ($raw -is [byte[]]) -or $raw.Length -lt 8) { continue }
                    $ranAt = $null
                    try { $ranAt = [DateTime]::FromFileTime([BitConverter]::ToInt64($raw, 0)) } catch {}
                    $resolved = $null
                    if ($valueName -match '^\\Device\\HarddiskVolume\d+\\(.+)$') {
                        $resolved = Join-Path $env:SystemDrive $matches[1]
                    } elseif ($valueName -match '^[A-Za-z]:\\') {
                        $resolved = $valueName
                    }
                    $entries += [pscustomobject]@{
                        Raw      = $valueName
                        Path     = $resolved
                        Leaf     = (Split-Path -Leaf $valueName)
                        Time     = $ranAt
                        Sid      = $sidName
                    }
                }
                $sidKey.Close()
            }
            $rootKey.Close()
        } catch {}
    }
    return $entries
}

function Get-SessionSummaryAlerts {
    $alerts = @()
    $logon = Get-LogonTime
    $boot = Get-BootTime
    $alerts += "INFO: User logon (explorer.exe start) -> $(Get-Date $logon -Format 'yyyy-MM-dd HH:mm:ss')"
    if ($boot) { $alerts += "INFO: Last boot -> $(Get-Date $boot -Format 'yyyy-MM-dd HH:mm:ss')" }
    try {
        $install = (Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name InstallDate -ErrorAction Stop)
        $installDate = [DateTimeOffset]::FromUnixTimeSeconds([int64]$install).LocalDateTime
        $alerts += "INFO: Windows installed -> $(Get-Date $installDate -Format 'yyyy-MM-dd')"
        if ($installDate -gt (Get-Date).AddDays(-14)) {
            $alerts += "WARNING: Windows was installed less than 14 days ago (fresh install wipes execution history)"
        }
    } catch {}

    $recent = @(Get-BamEntries | Where-Object { $_.Time -and $_.Time -ge $logon -and $_.Raw -notmatch '(?i)\\windows\\' } |
        Sort-Object Time -Descending)
    if ($recent.Count -eq 0) {
        $alerts += 'INFO: No non-Windows executables recorded since logon'
    } else {
        $shown = 0
        foreach ($e in $recent) {
            if ($shown -ge 25) { $alerts += "INFO: ... and $($recent.Count - 25) more"; break }
            $alerts += "INFO: Ran $(Get-Date $e.Time -Format 'HH:mm:ss') -> $($e.Raw)"
            $shown++
        }
    }
    return $alerts
}

function Get-TestSigningAlerts {
    $alerts = @()
    try {
        $out = & "$env:SystemRoot\System32\bcdedit.exe" /enum '{current}' 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -and $out -match 'denied|privilege') {
            $alerts += 'WARNING: Could not read boot configuration (run as Administrator)'
        } else {
            if ($out -match '(?im)^\s*testsigning\s+Yes') { $alerts += 'FAILURE: Test signing is ENABLED (unsigned drivers can load)' }
            if ($out -match '(?im)^\s*nointegritychecks\s+Yes') { $alerts += 'FAILURE: Driver integrity checks are DISABLED (nointegritychecks)' }
            if ($out -match '(?im)^\s*debug\s+Yes') { $alerts += 'WARNING: Kernel debugging is enabled' }
            if ($out -match '(?im)^\s*hypervisorlaunchtype\s+Off') { $alerts += 'INFO: Hypervisor launch is Off (Memory Integrity cannot run)' }
        }
    } catch {
        $alerts += 'WARNING: Could not query boot configuration'
    }
    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: Test signing off, driver signature enforcement on' }
    return $alerts
}

function Get-PrefetchHealthAlerts {
    $alerts = @()
    $prefetchPath = "$env:WINDIR\Prefetch"

    if (-not (Test-Path -LiteralPath $prefetchPath)) {
        $alerts += 'FAILURE: Prefetch folder is missing'
    } else {
        $count = 0
        try { $count = @(Get-ChildItem -LiteralPath $prefetchPath -Filter '*.pf' -ErrorAction Stop).Count } catch {}
        if ($count -eq 0) {
            $alerts += 'FAILURE: Prefetch folder is empty (execution history wiped or prefetch disabled)'
        } elseif ($count -lt 20) {
            $alerts += "WARNING: Only $count prefetch files present (recently cleaned?)"
        } else {
            $alerts += "INFO: $count prefetch files present"
        }
        try {
            $newest = Get-ChildItem -LiteralPath $prefetchPath -Filter '*.pf' -ErrorAction Stop |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($newest -and $newest.LastWriteTime -lt (Get-Date).AddHours(-6)) {
                $alerts += "WARNING: Newest prefetch file is from $(Get-Date $newest.LastWriteTime -Format 'yyyy-MM-dd HH:mm') (prefetch may be off)"
            }
        } catch {}
    }

    try {
        $ep = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name EnablePrefetcher -ErrorAction Stop
        if ([int]$ep -eq 0) { $alerts += 'FAILURE: EnablePrefetcher is 0 (prefetch logging turned off)' }
        elseif ([int]$ep -eq 2) { $alerts += 'WARNING: EnablePrefetcher is 2 (boot-only; application prefetch off)' }
    } catch {
        $alerts += 'WARNING: EnablePrefetcher value unreadable'
    }

    try {
        $svc = Get-Service -Name SysMain -ErrorAction Stop
        if ($svc.Status -ne 'Running') { $alerts += "FAILURE: SysMain service is $($svc.Status) (prefetch/superfetch not recording)" }
        if ($svc.StartType -eq 'Disabled') { $alerts += 'FAILURE: SysMain service is Disabled' }
    } catch {
        $alerts += 'WARNING: SysMain service not found'
    }

    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: Prefetch enabled and recording') + $alerts
    }
    return $alerts
}

function Get-BamServiceAlerts {
    $alerts = @()
    try {
        $svc = Get-Service -Name bam -ErrorAction Stop
        if ($svc.Status -ne 'Running') { $alerts += "FAILURE: BAM service is $($svc.Status) (execution history not recording)" }
        if ($svc.StartType -eq 'Disabled') { $alerts += 'FAILURE: BAM service start type is Disabled' }
    } catch {
        $alerts += 'FAILURE: BAM service not found'
    }
    try {
        $dam = Get-Service -Name dam -ErrorAction Stop
        if ($dam.Status -ne 'Running') { $alerts += "INFO: DAM service is $($dam.Status) (normal on desktops)" }
    } catch {}
    try {
        $start = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\bam' -Name Start -ErrorAction Stop
        if ([int]$start -eq 4) { $alerts += 'FAILURE: BAM driver Start=4 (disabled in registry)' }
    } catch {}
    $entryCount = @(Get-BamEntries).Count
    if ($entryCount -eq 0) { $alerts += 'FAILURE: BAM execution history is empty' }
    else { $alerts += "INFO: $entryCount BAM/DAM entries" }

    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: BAM service running and recording') + $alerts
    }
    return $alerts
}

function Get-UsnJournalState {
    param([string]$Drive = $env:SystemDrive)
    $state = @{ Present = $false; JournalId = $null; Created = $null; Error = $null }
    try {
        $out = & "$env:SystemRoot\System32\fsutil.exe" usn queryjournal $Drive 2>&1 | Out-String
        if ($out -match '(?i)not active|no.*journal') { $state.Error = 'not active'; return $state }
        if ($out -match '(?im)^\s*Usn Journal ID\s*:\s*0x([0-9a-f]+)') {
            $state.Present = $true
            $state.JournalId = $matches[1]
            try { $state.Created = [DateTime]::FromFileTime([Convert]::ToInt64($matches[1], 16)) } catch {}
        } elseif ($out -match '(?i)denied|privilege') {
            $state.Error = 'access denied'
        } else {
            $state.Error = 'unparsed'
        }
    } catch {
        $state.Error = $_.Exception.Message
    }
    return $state
}

function Get-UsnJournalAlerts {
    $alerts = @()
    $state = Get-UsnJournalState
    if ($state.Error -eq 'not active') {
        $alerts += "FAILURE: USN change journal is not present on $env:SystemDrive (deleted)"
        return $alerts
    }
    if ($state.Error -eq 'access denied') {
        $alerts += 'WARNING: USN journal unreadable (run as Administrator)'
        return $alerts
    }
    if (-not $state.Present) {
        $alerts += 'WARNING: USN journal state could not be determined'
        return $alerts
    }
    $boot = Get-BootTime
    if ($state.Created) {
        $alerts += "INFO: USN journal created $(Get-Date $state.Created -Format 'yyyy-MM-dd HH:mm:ss')"
        if ($boot -and $state.Created -gt $boot.AddMinutes(10)) {
            $alerts += "FAILURE: USN journal was recreated after boot ($(Get-Date $boot -Format 'HH:mm:ss')) - journal was deleted this session"
        } elseif ($state.Created -gt (Get-Date).AddDays(-2)) {
            $alerts += 'WARNING: USN journal is less than 2 days old'
        }
    }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: USN change journal present and intact') + $alerts
    }
    return $alerts
}

function Get-ClockChangeAlerts {
    param([datetime]$Since = (Get-LogonTime))
    $alerts = @()
    $found = $false

    try {
        Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4616; StartTime = $Since } -ErrorAction Stop | ForEach-Object {
            $msg = [string]$_.Message
            if ($msg -match '(?i)svchost\.exe|w32time|VBoxService|vmtoolsd') { return }
            $delta = $null
            if ($msg -match '(?s)Previous Time:\s*\S*\s*([\d:\-T\.Z ]+?)\s*New Time:\s*\S*\s*([\d:\-T\.Z ]+?)\s') {
                try { $delta = ([datetime]$matches[2]) - ([datetime]$matches[1]) } catch {}
            }
            if ($delta -and [math]::Abs($delta.TotalSeconds) -lt 60) { return }
            $proc = ''
            if ($msg -match '(?m)Process Name:\s*(.+)$') { $proc = $matches[1].Trim() }
            $found = $true
            $alerts += "WARNING: System time changed at $(Get-Date $_.TimeCreated -Format 'HH:mm:ss') by $proc"
        }
    } catch {
        if ($_.Exception.Message -notmatch '(?i)no events were found') {
            $alerts += 'INFO: Security log unreadable for time-change events (run as Administrator)'
        }
    }

    try {
        Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 1; StartTime = $Since } -ErrorAction Stop | ForEach-Object {
            $msg = [string]$_.Message
            if ($msg -match '(?i)synchroni[sz]') { return }
            if ($msg -match '(?i)Process:\s*''[^'']*\\(svchost|VBoxService|vmtoolsd)\.exe') { return }
            if ($msg -match '(?i)Time Delta:\s*(-?\d+)\s*ms' -and [math]::Abs([int64]$matches[1]) -lt 60000) { return }
            $proc = 'unknown process'
            if ($msg -match '(?i)Process:\s*''([^'']+)''') { $proc = Split-Path -Leaf $matches[1] }
            $delta = ''
            if ($msg -match '(?i)Time Delta:\s*(-?\d+)\s*ms') { $delta = " by $([math]::Round([int64]$matches[1] / 1000))s" }
            $found = $true
            $alerts += "WARNING: System time changed$delta at $(Get-Date $_.TimeCreated -Format 'HH:mm:ss') by $proc"
        }
    } catch {}

    if (-not $found -and -not ($alerts | Where-Object { $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: No manual system clock changes since logon') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

$script:AntiForensicCommandPatterns = @(
    @{ Level = 'FAILURE'; Label = 'event log cleared';        Pattern = 'wevtutil\s+(cl|clear-log)|Clear-EventLog|Limit-EventLog' },
    @{ Level = 'FAILURE'; Label = 'shadow copies deleted';    Pattern = 'vssadmin.*delete\s+shadows|shadowcopy\s+delete|Win32_ShadowCopy.*Delete' },
    @{ Level = 'FAILURE'; Label = 'USN journal deleted';      Pattern = 'fsutil\s+usn\s+deletejournal' },
    @{ Level = 'FAILURE'; Label = 'prefetch wiped';           Pattern = '(Remove-Item|del |rd |rmdir|erase )[^\r\n]*prefetch' },
    @{ Level = 'FAILURE'; Label = 'BAM history wiped';        Pattern = '(reg\s+delete|Remove-Item|Remove-ItemProperty)[^\r\n]*\\bam\\' },
    @{ Level = 'FAILURE'; Label = 'Defender disabled';        Pattern = 'Set-MpPreference[^\r\n]*-Disable(RealtimeMonitoring|IOAVProtection|BehaviorMonitoring)\s+\$?true' },
    @{ Level = 'FAILURE'; Label = 'test signing enabled';     Pattern = 'bcdedit[^\r\n]*testsigning\s+on|nointegritychecks\s+on' },
    @{ Level = 'WARNING'; Label = 'Defender exclusion added'; Pattern = 'Add-MpPreference[^\r\n]*-Exclusion' },
    @{ Level = 'WARNING'; Label = 'encoded command';          Pattern = '-(EncodedCommand|enc)\s+[A-Za-z0-9+/=]{20,}' },
    @{ Level = 'WARNING'; Label = 'permissions changed';      Pattern = 'icacls[^\r\n]*(prefetch|\\bam|eventlog|winevt)' }
)

function Get-CommandHistoryAlerts {
    $alerts = @()
    $sources = @()

    $historyFile = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'
    if (Test-Path -LiteralPath $historyFile) {
        try {
            $lines = @(Get-Content -LiteralPath $historyFile -ErrorAction Stop | Select-Object -Last 2000)
            $sources += @{ Name = 'PowerShell history'; Lines = $lines }
        } catch {}
    } else {
        $alerts += 'INFO: No PowerShell history file (never used interactively, or cleared)'
    }

    try {
        $since = (Get-LogonTime).AddDays(-7)
        $evLines = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-PowerShell/Operational'; Id = 4104; StartTime = $since } -MaxEvents 500 -ErrorAction Stop |
            ForEach-Object { [string]$_.Message } |
            Where-Object { $_ -notmatch 'AntiForensicCommandPatterns|bsmm_security_events|ror_security_events|BsmmVersion|RoRVersion|Get-CommandHistoryAlerts' })
        if ($evLines.Count -gt 0) { $sources += @{ Name = 'PowerShell script log'; Lines = $evLines } }
    } catch {}

    foreach ($src in $sources) {
        foreach ($rule in $script:AntiForensicCommandPatterns) {
            $hits = @($src.Lines | Where-Object { $_ -match "(?i)$($rule.Pattern)" } | Select-Object -Unique | Select-Object -First 3)
            foreach ($hit in $hits) {
                if ($hit -match '(?i)bsmm_security_events|ror_security_events|BSMM v\d|RoR v\d') { continue }
                $snippet = ($hit -replace '\s+', ' ').Trim()
                if ($snippet.Length -gt 140) { $snippet = $snippet.Substring(0, 140) + '...' }
                $alerts += "$($rule.Level): $($rule.Label) in $($src.Name) -> $snippet"
            }
        }
    }

    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: No anti-forensic commands in command history') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

$script:VulnerableDriverTiers = @{
    'iqvw64e.sys'      = 'FAILURE'; 'iqvw64.sys'   = 'FAILURE'; 'gdrv.sys'        = 'FAILURE'; 'dbutil_2_3.sys' = 'FAILURE'
    'kprocesshacker.sys' = 'FAILURE'; 'mhyprot2.sys' = 'FAILURE'; 'mhyprot3.sys'  = 'FAILURE'; 'capcom.sys'   = 'FAILURE'
    'physmem.sys'      = 'FAILURE'; 'hw.sys'       = 'FAILURE'; 'speedfan.sys'    = 'FAILURE'; 'viragt64.sys' = 'FAILURE'
    'tfsysmon.sys'     = 'FAILURE'; 'amsdk.sys'    = 'FAILURE'; 'adv64drv.sys'    = 'FAILURE'; 'bs_def64.sys' = 'FAILURE'
    'bs_hwmio64.sys'   = 'FAILURE'; 'iomap64.sys'  = 'FAILURE'; 'asupio.sys'      = 'FAILURE'; 'ucorew64.sys' = 'FAILURE'
    'msio64.sys'       = 'FAILURE'; 'ntiolib_x64.sys' = 'FAILURE'; 'winio64.sys'  = 'FAILURE'; 'inpoutx64.sys' = 'FAILURE'
    'kevp64.sys'       = 'FAILURE'; 'procexp152.sys' = 'SKIP'
    'rtcore64.sys'     = 'WARNING'; 'winring0x64.sys' = 'WARNING'; 'winring0.sys' = 'WARNING'; 'ene.sys'     = 'WARNING'
    'eneio64.sys'      = 'WARNING'; 'enetechio64.sys' = 'WARNING'; 'asio.sys'     = 'WARNING'; 'asio2.sys'   = 'WARNING'
    'asio3.sys'        = 'WARNING'; 'aswarpot.sys' = 'WARNING'; 'directio64.sys'  = 'WARNING'; 'cpuz141.sys' = 'WARNING'
    'atillk64.sys'     = 'WARNING'; 'amifldrv64.sys' = 'WARNING'
}

function Get-VulnerableDriverAlerts {
    $alerts = @()
    try {
        $drivers = @(Get-CimInstance -ClassName Win32_SystemDriver -ErrorAction Stop)
    } catch {
        return @('WARNING: Could not enumerate drivers for vulnerable-driver check')
    }

    foreach ($drv in $drivers) {
        $path = Resolve-KernelDriverImagePath -ServiceName ([string]$drv.Name) -PathName ([string]$drv.PathName)
        $leaf = ''
        if ($path) { $leaf = (Split-Path -Leaf $path).ToLower() }
        if (-not $leaf) { continue }
        if (-not $script:VulnerableDriverTiers.ContainsKey($leaf)) { continue }
        $tier = $script:VulnerableDriverTiers[$leaf]
        if ($tier -eq 'SKIP') { continue }
        if ($drv.State -eq 'Running') {
            $alerts += "${tier}: Known-vulnerable driver LOADED: $($drv.Name) -> $path"
        } else {
            $alerts += "INFO: Known-vulnerable driver installed but not running: $($drv.Name) -> $path"
        }
    }

    try {
        Get-ChildItem -LiteralPath "$env:SystemRoot\System32\drivers" -Filter '*.sys' -ErrorAction Stop | ForEach-Object {
            $leaf = $_.Name.ToLower()
            if ($script:VulnerableDriverTiers.ContainsKey($leaf) -and $script:VulnerableDriverTiers[$leaf] -ne 'SKIP') {
                $line = "INFO: Known-vulnerable driver file present: $($_.FullName)"
                if (-not ($alerts -match [regex]::Escape($leaf))) { $alerts += $line }
            }
        }
    } catch {}

    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: No known-vulnerable drivers found' }
    return @($alerts | Select-Object -Unique)
}

$script:InputDriverServices = @(
    @{ Service = 'ViGEmBus';     Level = 'WARNING'; Label = 'ViGEmBus virtual gamepad driver' },
    @{ Service = 'HidHide';      Level = 'WARNING'; Label = 'HidHide input-hiding driver' },
    @{ Service = 'WinIo';        Level = 'WARNING'; Label = 'WinIo direct hardware access driver' },
    @{ Service = 'interception'; Level = 'WARNING'; Label = 'Interception input driver' }
)
$script:FpgaPciVendorIds = @{
    '10EE' = 'Xilinx'; '1172' = 'Altera/Intel FPGA'; '1204' = 'Lattice'; '11AA' = 'Microsemi/Actel'; '1D0F' = 'Amazon (Xilinx-based)'
}

function Get-InputAndDmaDeviceAlerts {
    $alerts = @()

    foreach ($spec in $script:InputDriverServices) {
        try {
            $svc = Get-Service -Name $spec.Service -ErrorAction Stop
            $alerts += "$($spec.Level): $($spec.Label) installed (service $($svc.Name), $($svc.Status))"
        } catch {}
    }

    foreach ($name in @('keyboard', 'mouse')) {
        try {
            $img = [string](Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -Name ImagePath -ErrorAction Stop)
            if ($img -match "(?i)\\drivers\\$name\.sys") { $alerts += "WARNING: Interception input driver installed as service '$name' -> $img" }
        } catch {}
    }

    try {
        Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.DeviceID -like 'PCI\VEN_*' } | ForEach-Object {
            if ($_.DeviceID -match '^PCI\\VEN_([0-9A-Fa-f]{4})') {
                $ven = $matches[1].ToUpper()
                if ($script:FpgaPciVendorIds.ContainsKey($ven)) {
                    $alerts += "FAILURE: FPGA PCIe device present ($($script:FpgaPciVendorIds[$ven])) -> $($_.Name) [$($_.DeviceID)]"
                }
            }
        }
    } catch {
        $alerts += 'WARNING: Could not enumerate PCI devices'
    }

    try {
        $pciKey = Open-LocalMachineRegistryKey -SubKeyPath 'SYSTEM\CurrentControlSet\Enum\PCI'
        if ($pciKey) {
            foreach ($sub in $pciKey.GetSubKeyNames()) {
                if ($sub -match '^VEN_([0-9A-Fa-f]{4})') {
                    $ven = $matches[1].ToUpper()
                    if ($script:FpgaPciVendorIds.ContainsKey($ven) -and -not ($alerts -match [regex]::Escape($sub))) {
                        $alerts += "WARNING: FPGA PCIe device ($($script:FpgaPciVendorIds[$ven])) was installed previously -> $sub"
                    }
                }
            }
            $pciKey.Close()
        }
    } catch {}

    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: No virtual-input drivers or DMA hardware found' }
    return @($alerts | Select-Object -Unique)
}

$script:WellKnownCaPattern = '(?i)DigiCert|GlobalSign|Sectigo|COMODO|USERTrust|AAA Certificate|Entrust|Go ?Daddy|Starfield|Baltimore|VeriSign|Thawte|GeoTrust|Symantec|ISRG|Let.s Encrypt|Amazon|Google Trust|GTS Root|Apple|Certum|QuoVadis|IdenTrust|DST Root|SwissSign|T-TeleSec|Actalis|Buypass|D-TRUST|SSL\.com|Cybertrust|Network Solutions|Trustwave|SecureTrust|Secure Global|AffirmTrust|XRamp|Certigna|CFCA|TWCA|Hongkong Post|e-Szigno|NetLock|OISTE|WISeKey|Security Communication|Staat der Nederlanden|Izenpe|emSign|GDCA|Chambers|TrustCor|Hellenic|Atos|ANF|Camerfirma|HARICA|Telia|Sonera|Microsec|E-Tugra|TunTrust|vTrus|BJCA|Kaspersky|ESET|Avast|AVG|Bitdefender|Norton|McAfee|Fortinet|Sophos|Zscaler|Cisco|Palo Alto|Trend Micro|Malwarebytes|Adobe|Mozilla|VMware|Oracle|Intel|NVIDIA|AMD|Dell|Hewlett|HP Inc|Lenovo|ASUS|Acer|Samsung|Valve|Epic Games|Discord|Roblox|Logitech|Razer|Corsair|Steelseries|NordVPN'

function Get-RootCertificateAlerts {
    $alerts = @()
    $stores = @(
        @{ Path = 'Cert:\CurrentUser\Root';  Label = 'user' },
        @{ Path = 'Cert:\LocalMachine\Root'; Label = 'machine' }
    )
    foreach ($store in $stores) {
        $certs = @()
        try { $certs = @(Get-ChildItem -Path $store.Path -ErrorAction Stop) } catch { continue }
        foreach ($cert in $certs) {
            if (-not (Test-UserInstalledRootThumbprint -Thumbprint $cert.Thumbprint)) { continue }
            $subject = [string]$cert.Subject
            $short = $subject
            if ($subject -match 'CN=([^,]+)') { $short = $matches[1] }
            $when = Get-Date $cert.NotBefore -Format 'yyyy-MM-dd'
            $desc = "'$short' ($($store.Label) store, issued $when, $($cert.Thumbprint.Substring(0,8))...)"

            if ($subject -match '(?i)microsoft') {
                $alerts += "FAILURE: Forged Microsoft root certificate $desc"
            } elseif ($store.Label -eq 'user') {
                $alerts += "WARNING: Root certificate installed in user store $desc"
            } elseif ($subject -match $script:WellKnownCaPattern) {
                $alerts += "INFO: Non-default root certificate $desc"
            } else {
                $alerts += "WARNING: Unknown root certificate installed $desc"
            }
        }
    }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: No user-installed root certificates') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

function Get-RootCertificateThumbprintSet {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @('Cert:\CurrentUser\Root', 'Cert:\LocalMachine\Root')) {
        try { Get-ChildItem -Path $p -ErrorAction Stop | ForEach-Object { [void]$set.Add("$p|$($_.Thumbprint)|$($_.Subject)") } } catch {}
    }
    return $set
}

function Get-RobloxModuleAlerts {
    $alerts = @()
    $procs = @()
    try { $procs = @(Get-Process -Name RobloxPlayerBeta -ErrorAction Stop) } catch {}
    if ($procs.Count -eq 0) { return @('INFO: Roblox is not running - loaded-module check skipped') }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $checked = 0
    foreach ($proc in $procs) {
        $modules = $null
        try { $modules = $proc.Modules } catch {
            $alerts += "WARNING: Could not list modules of RobloxPlayerBeta (PID $($proc.Id)): $($_.Exception.Message)"
            continue
        }
        foreach ($m in $modules) {
            $file = [string]$m.FileName
            if (-not $file -or -not $seen.Add($file)) { continue }
            $lower = $file.ToLower()
            if ($lower.StartsWith("$($env:SystemRoot.ToLower())\")) { continue }
            $checked++

            $sig = $null
            try { $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $file -ErrorAction Stop } catch {}
            $status = if ($sig) { [string]$sig.Status } else { 'Unknown' }
            $userLand = Test-UserLandProcessPath -ExecutablePath $file
            $kw = Get-MatchedCheatKeyword -Text $file
            $kwTag = if ($kw) { " [$kw]" } else { '' }

            if ($status -ne 'Valid') {
                $entropy = Get-FileEntropy -FilePath $file
                $alerts += "FAILURE: Unsigned/invalid module$kwTag loaded in Roblox ($status) [Entropy: $entropy] -> $file"
            } elseif (-not (Test-SignedByShippedRoot -Path $file)) {
                $alerts += "FAILURE: Module$kwTag signed by a user-installed root loaded in Roblox -> $file"
            } elseif ($userLand -and $kw) {
                $alerts += "FAILURE: Module [$kw] from a user folder loaded in Roblox -> $file"
            } elseif ($userLand) {
                $signer = ''
                if ($sig.SignerCertificate -and $sig.SignerCertificate.Subject -match 'CN=([^,]+)') { $signer = $matches[1] }
                $alerts += "WARNING: Signed module from a user folder loaded in Roblox ($signer) -> $file"
            }
        }
    }

    if ($alerts.Count -eq 0) { $alerts += "SUCCESS: All $checked non-Windows modules in Roblox are validly signed" }
    return @($alerts | Select-Object -Unique)
}

function Get-RobloxMemoryIntegrityAlerts {
    $alerts = @()
    $proc = Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue
    if (-not $proc) {
        $alerts += 'INFO: Roblox (RobloxPlayerBeta) is not currently running'
        return $alerts
    }
    try {
        if ($proc.Responding -eq $false) {
            $alerts += "WARNING: Roblox process (PID $($proc.Id)) is not responding"
        } else {
            $alerts += "SUCCESS: Roblox process (PID $($proc.Id)) memory space intact"
        }
    } catch {
        $alerts += "INFO: Roblox memory check completed"
    }
    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: Roblox memory integrity verified' }
    return $alerts
}

function Get-RobloxNamedPipeAlerts {
    $alerts = @()
    $cheatPipeKeywords = @(
        'krampus','solara','wavepipe','celery','fluxus','krnl','wearedevs',
        'oxygen','electron','hydrogen','swift','comet','valyse','xeno','synapse'
    )
    try {
        $pipes = [System.IO.Directory]::GetFiles('\\.\pipe\')
        foreach ($pipe in $pipes) {
            $leaf = Split-Path -Leaf $pipe
            $leafLower = $leaf.ToLower()
            foreach ($kw in $cheatPipeKeywords) {
                if ($leafLower.Contains($kw)) {
                    $alerts += "FAILURE: Detected cheat named pipe: \\.\pipe\$leaf"
                    break
                }
            }
        }
    } catch {}
    if ($alerts.Count -eq 0) {
        $alerts += 'SUCCESS: No suspicious or cheat named pipes detected'
    }
    return $alerts
}

function Get-FastFlagsAlerts {
    $alerts = @()
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Roblox\Versions\*\ClientSettings\ClientAppSettings.json'),
        (Join-Path $env:LOCALAPPDATA 'Bloxstrap\Modifications\ClientSettings\ClientAppSettings.json'),
        (Join-Path $env:LOCALAPPDATA 'Fishstrap\Modifications\ClientSettings\ClientAppSettings.json')
    )
    $suspiciousFlags = @(
        'FFlagDebugDisplayUntrackedMemory',
        'FFlagDebugGraphicsDisableDirect3D11',
        'FFlagVisualEngine'
    )
    $foundFiles = Resolve-Path $candidates -ErrorAction SilentlyContinue
    foreach ($file in $foundFiles) {
        try {
            $jsonText = [System.IO.File]::ReadAllText($file.Path)
            foreach ($sf in $suspiciousFlags) {
                if ($jsonText.Contains($sf)) {
                    $alerts += "WARNING: Exploit-associated FastFlag in $($file.Path): $sf"
                }
            }
        } catch {}
    }
    if ($alerts.Count -eq 0) {
        $alerts += 'SUCCESS: No exploit-associated FastFlags detected'
    }
    return $alerts
}

function Get-AntiBypassNetworkAlerts {
    $alerts = @()
    try {
        $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
        if (Test-Path $hostsPath) {
            $lines = Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                if ($trimmed.StartsWith('#') -or -not $trimmed) { continue }
                if ($trimmed -match '(?i)(roblox|rbxcdn|clientsettings)') {
                    $alerts += "FAILURE: Hosts file redirection: $trimmed"
                }
            }
        }
        $proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        if (Test-Path $proxyKey) {
            $proxyEnabled = (Get-ItemProperty -Path $proxyKey -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable
            if ($proxyEnabled -eq 1) {
                $server = (Get-ItemProperty -Path $proxyKey -Name ProxyServer -ErrorAction SilentlyContinue).ProxyServer
                $alerts += "WARNING: System proxy enabled: $server"
            }
        }
    } catch {}
    if ($alerts.Count -eq 0) {
        $alerts += 'SUCCESS: Network configuration and hosts file clean'
    }
    return $alerts
}

function Get-ArtifactCrossCheckAlerts {
    $alerts = @()
    try {
        $sysMain = Get-Service -Name SysMain -ErrorAction SilentlyContinue
        if ($sysMain -and $sysMain.Status -ne 'Running') {
            return @('INFO: SysMain service is not running - prefetch artifact cross-check skipped')
        }
    } catch {}

    $logon = Get-LogonTime
    $prefetch = @(Get-PrefetchFileNames)
    if ($prefetch.Count -eq 0) { return @('WARNING: No prefetch files to cross-check against BAM') }

    $pfIndex = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($pf in $prefetch) {
        if ($pf -match '^(.+?)-[0-9A-F]{8}\.pf$') { [void]$pfIndex.Add($matches[1]) }
    }

    $recent = @(Get-BamEntries | Where-Object {
        $_.Time -and $_.Time -ge $logon -and $_.Leaf -match '(?i)\.exe$' -and $_.Raw -notmatch '(?i)\\windows\\|\\windowsapps\\|\\microsoft\\edge'
    })
    $missing = @()
    foreach ($e in $recent) {
        if (-not $pfIndex.Contains($e.Leaf)) { $missing += $e }
    }

    if ($recent.Count -gt 0 -and $missing.Count -eq $recent.Count -and $recent.Count -ge 3) {
        $alerts += "FAILURE: None of the $($recent.Count) programs run since logon have a prefetch file (prefetch cleaned or disabled)"
    }
    foreach ($e in ($missing | Sort-Object Time -Descending | Select-Object -First 10)) {
        $alerts += "WARNING: Ran since logon but has no prefetch file -> $($e.Raw) ($(Get-Date $e.Time -Format 'HH:mm:ss'))"
    }
    if ($missing.Count -gt 10) { $alerts += "INFO: ... and $($missing.Count - 10) more without prefetch" }

    if ($alerts.Count -eq 0) { $alerts += "SUCCESS: BAM and prefetch agree for $($recent.Count) programs run since logon" }
    return $alerts
}

function Get-DefenderHistoryAlerts {
    if (-not $script:DefenderAvailable) { return @('WARNING: Defender cmdlets unavailable') }
    $alerts = @()
    try {
        $dets = @(Defender\Get-MpThreatDetection -ErrorAction Stop | Sort-Object InitialDetectionTime -Descending)
        if ($dets.Count -eq 0) { return @('SUCCESS: No Defender detection history') }
        $names = @{}
        try { Defender\Get-MpThreat -ErrorAction Stop | ForEach-Object { $names[[string]$_.ThreatID] = [string]$_.ThreatName } } catch {}
        $shown = 0
        foreach ($d in $dets) {
            if ($shown -ge 10) { $alerts += "INFO: ... and $($dets.Count - 10) more detections"; break }
            $name = $names[[string]$d.ThreatID]
            if (-not $name) { $name = "ThreatID $($d.ThreatID)" }
            $res = ([string]($d.Resources -join ', ')) -replace '^(file|containerfile|process):_', ''
            $when = Get-Date $d.InitialDetectionTime -Format 'yyyy-MM-dd HH:mm'
            $kw = Get-MatchedCheatKeyword -Text $res
            if ($kw) { $alerts += "WARNING: Defender detected [$kw] $name at $when -> $res" }
            else { $alerts += "INFO: Defender detected $name at $when -> $res" }
            $shown++
        }
        $alerts = @("INFO: $($dets.Count) Defender detections on record") + $alerts
    } catch {
        $alerts += 'WARNING: Could not read Defender detection history'
    }
    return $alerts
}

$script:DnsAllowlistPattern = '(?i)(^|\.)(microsoft\.com|clarity\.ms|msftconnecttest\.com|photonengine\.com|matrix\.org|roblox\.com|rbxcdn\.com|rbx\.com|discord\.com|discordapp\.com|discord\.gg|gstatic\.com|googleapis\.com|cloudflare\.com|akamaized\.net|edgesuite\.net|windowsupdate\.com|live\.com|office\.com|nvidia\.com|amd\.com|intel\.com|steamstatic\.com|steampowered\.com|epicgames\.com|unity3d\.com|spotify\.com|github\.com|githubusercontent\.com)$'

function Get-DnsCacheAlerts {
    $alerts = @()
    try {
        $entries = @(Get-DnsClientCache -ErrorAction Stop | Select-Object -ExpandProperty Entry -Unique)
    } catch {
        return @('WARNING: Could not read DNS cache')
    }
    foreach ($hostName in $entries) {
        if (-not $hostName -or $hostName -match $script:DnsAllowlistPattern) { continue }
        $kw = Get-MatchedCheatKeyword -Text $hostName
        if ($kw) { $alerts += "WARNING: DNS cache entry [$kw] -> $hostName" }
    }
    if ($alerts.Count -eq 0) { $alerts += "SUCCESS: No cheat keywords in DNS cache ($($entries.Count) entries)" }
    return @($alerts | Select-Object -Unique)
}

function Convert-RegistryFileTime {
    param($Raw)
    try {
        if ($Raw -is [byte[]] -and $Raw.Length -ge 8) { return [DateTime]::FromFileTime([BitConverter]::ToInt64($Raw, 0)) }
        if ($Raw -is [int64]) { return [DateTime]::FromFileTime($Raw) }
    } catch {}
    return $null
}

function Get-UsbHistoryAlerts {
    $alerts = @()
    $logon = Get-LogonTime
    $removed = @()
    $propKey = 'Properties\{83da6326-97a6-4088-9453-a1923f573b29}'
    foreach ($enumRoot in @('SYSTEM\CurrentControlSet\Enum\USBSTOR', 'SYSTEM\CurrentControlSet\Enum\USB')) {
        try {
            $root = Open-LocalMachineRegistryKey -SubKeyPath $enumRoot
            if (-not $root) { continue }
            foreach ($dev in $root.GetSubKeyNames()) {
                if ($enumRoot -like '*\USB' -and $dev -match '(?i)ROOT_HUB|VID_8087|VID_045E&PID_0[0-9A-F]{3}$') { continue }
                $devKey = $root.OpenSubKey($dev)
                if (-not $devKey) { continue }
                foreach ($inst in $devKey.GetSubKeyNames()) {
                    $instKey = $devKey.OpenSubKey($inst)
                    if (-not $instKey) { continue }
                    $removalKey = $instKey.OpenSubKey("$propKey\0067")
                    if ($removalKey) {
                        $removedAt = Convert-RegistryFileTime -Raw ($removalKey.GetValue(''))
                        $removalKey.Close()
                        if ($removedAt -and $removedAt -ge $logon) {
                            $name = [string]$instKey.GetValue('FriendlyName')
                            if (-not $name) { $name = ([string]$instKey.GetValue('DeviceDesc')) -replace '^@.*;', '' }
                            if (-not $name) { $name = $dev }
                            $removed += [pscustomobject]@{ Name = $name; Time = $removedAt; Id = $dev }
                        }
                    }
                    $instKey.Close()
                }
                $devKey.Close()
            }
            $root.Close()
        } catch {}
    }
    if ($removed.Count -eq 0) { return @('SUCCESS: No USB devices removed since logon') }
    foreach ($r in ($removed | Sort-Object Time -Descending | Select-Object -First 15)) {
        $alerts += "INFO: USB device removed $(Get-Date $r.Time -Format 'HH:mm:ss') -> $($r.Name)"
    }
    if ($removed.Count -gt 15) { $alerts += "INFO: ... and $($removed.Count - 15) more" }
    return $alerts
}

function Get-CpuGpuAlerts {
    $alerts = @()
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Name
        if ($cpu) { $alerts += "SUCCESS: CPU -> $cpu" }
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -ExpandProperty Name)
        foreach ($gpu in $gpus) { $alerts += "SUCCESS: GPU -> $gpu" }
        if (-not $cpu -or $gpus.Count -eq 0) { $alerts += 'WARNING: CPU or GPU could not be identified' }
    } catch {
        $alerts += 'WARNING: Unable to query CPU/GPU information.'
    }
    return $alerts
}

function Get-DefenderStep1Alerts {
    $alerts = @()
    try {
        if (-not $script:DefenderAvailable) {
            $alerts += 'WARNING: Windows Defender status check unavailable because the Defender module/cmdlets could not be loaded.'
        } else {
            $def = Defender\Get-MpComputerStatus -ErrorAction Stop
            if ($def.RealTimeProtectionEnabled) { $alerts += 'SUCCESS: Real-time protection enabled' }
            else { $alerts += 'FAILURE: Real-time protection disabled' }
            if (-not $def.IsTamperProtected) { $alerts += 'WARNING: Tamper protection disabled' }
            if ($def.AntivirusSignatureAge -gt 7) { $alerts += "WARNING: Defender signatures are $($def.AntivirusSignatureAge) days old" }
        }
    } catch {
        $alerts += "WARNING: Unable to query Defender: $($_.Exception.Message)"
    }
    foreach ($disableKey in @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender',
        'HKLM:\SOFTWARE\Microsoft\Windows Defender'
    )) {
        try {
            $disabled = Get-ItemPropertyValue -Path $disableKey -Name 'DisableAntiSpyware' -ErrorAction Stop
            if ($disabled -eq 1) { $alerts += 'FAILURE: DisableAntiSpyware active' }
        } catch {}
    }
    return $alerts
}

function Get-ExclusionAlerts {
    $alerts = @()
    try {
        $allExclusions = @(Get-Exclusions)
        if ($allExclusions.Count -eq 0) {
            if ($script:DefenderAvailable) { $alerts += 'SUCCESS: No Defender exclusions' }
            else { $alerts += 'WARNING: Defender exclusions could not be fully verified because the Defender module/cmdlets are unavailable.' }
        } else {
            foreach ($excl in $allExclusions) {
                $exclKw = Get-MatchedCheatKeyword -Text $excl
                if ($exclKw) { $alerts += "FAILURE: Defender exclusion [$exclKw] -> $excl" }
                else { $alerts += "FAILURE: Defender exclusion -> $excl" }
            }
        }
    } catch {
        $alerts += 'WARNING: Exclusions check failed.'
    }
    return $alerts
}

function Get-AllowedThreatAlerts {
    $alerts = @()
    try {
        $allowedThreats = @(Get-AllowedDefenderThreats)
        if ($allowedThreats.Count -eq 0) { $alerts += 'SUCCESS: No allowed threats' }
        else { foreach ($threat in $allowedThreats) { $alerts += "FAILURE: Allowed threat -> $threat" } }
    } catch {
        $alerts += 'WARNING: Allowed threats check failed.'
    }
    return $alerts
}

function Get-KeyAuthAlerts {
    $alerts = @()
    try {
        $keyAuthHits = @()
        $keyRoot = Join-Path $env:ProgramData 'KeyAuth'
        if (Test-Path $keyRoot) {
            $keyAuthHits += $keyRoot
            Get-ChildItem $keyRoot -Recurse -Directory -Depth 3 -ErrorAction SilentlyContinue | ForEach-Object { $keyAuthHits += $_.FullName }
        }
        if ($keyAuthHits.Count -eq 0) { $alerts += 'SUCCESS: KeyAuth clean' }
        else { foreach ($hit in ($keyAuthHits | Select-Object -Unique)) { $alerts += "FAILURE: KeyAuth $hit" } }
    } catch {
        $alerts += 'WARNING: KeyAuth check failed'
    }
    return $alerts
}

function Get-RegistryMarkerAlerts {
    $alerts = @()
    try {
        if (Test-Path -LiteralPath 'HKCU:\Antenna') { $alerts += 'FAILURE: Cheat registry marker found (HKCU:\Antenna)' }
    } catch {}
    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: Registry clean' }
    return $alerts
}

function Get-ProcessScanAlerts {
    $hits = @(Get-SuspiciousProcessHits)
    if ($hits.Count -eq 0) { return @('SUCCESS: Processes clean') }
    return $hits
}

function Get-PowerShellHostIntegrityAlerts {
    $alerts = @()

    $ic = $ExecutionContext.InvokeCommand
    foreach ($hookName in 'PreCommandLookupAction', 'PostCommandLookupAction', 'CommandNotFoundAction') {
        $action = $ic.$hookName
        if ($null -ne $action) {
            $hookOrigin = ''
            try {
                if ($action.Target -and $action.Target.Constants) {
                    foreach ($c in $action.Target.Constants) {
                        if ($c -is [System.Management.Automation.ScriptBlock]) {
                            if ($c.File) { $hookOrigin = " [File: $($c.File)]" }
                            elseif ($c.Ast -and $c.Ast.Extent -and $c.Ast.Extent.File) { $hookOrigin = " [File: $($c.Ast.Extent.File)]" }
                            else { $hookOrigin = " [Code: $($c.ToString().Trim())]" }
                            break
                        }
                    }
                }
                if (-not $hookOrigin -and $action.Method -and $action.Method.DeclaringType) {
                    $hookOrigin = " [Assembly: $($action.Method.DeclaringType.Assembly.Location)]"
                }
            } catch {}
            $alerts += "FAILURE: PowerShell command-lookup hook set -> $hookName$hookOrigin"
        }
    }

    try {
        foreach ($bp in @(Microsoft.PowerShell.Utility\Get-PSBreakpoint -ErrorAction Stop)) {
            $target = if ($bp.Command) { "command '$($bp.Command)'" } elseif ($bp.Variable) { "variable '$($bp.Variable)'" } else { "script $($bp.Script)" }
            $lvl = if ($bp.Action) { 'FAILURE' } else { 'WARNING' }
            $alerts += "${lvl}: PowerShell breakpoint on $target"
        }
    } catch {}

    try {
        $cmdlets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        Microsoft.PowerShell.Core\Get-Command -CommandType Cmdlet -ErrorAction SilentlyContinue | ForEach-Object { [void]$cmdlets.Add($_.Name) }
        foreach ($fn in @(Microsoft.PowerShell.Management\Get-ChildItem Function:\ -ErrorAction SilentlyContinue)) {
            if ($cmdlets.Contains($fn.Name)) {
                $srcFile = if ($fn.ScriptBlock.File) { " [File: $($fn.ScriptBlock.File)]" }
                           elseif ($fn.Module.Path) { " [Module: $($fn.Module.Path)]" }
                           elseif ($fn.ScriptBlock.Ast -and $fn.ScriptBlock.Ast.Extent -and $fn.ScriptBlock.Ast.Extent.File) { " [File: $($fn.ScriptBlock.Ast.Extent.File)]" }
                           else { " [Code: $($fn.ScriptBlock.ToString().Trim())]" }
                $alerts += "FAILURE: Function overrides built-in cmdlet -> $($fn.Name)$srcFile"
            }
        }
        foreach ($al in @(Microsoft.PowerShell.Management\Get-ChildItem Alias:\ -ErrorAction SilentlyContinue)) {
            if ($cmdlets.Contains($al.Name)) { $alerts += "FAILURE: Alias overrides built-in cmdlet -> $($al.Name) => $($al.Definition)" }
        }
    } catch { $alerts += 'WARNING: Could not check for cmdlet overrides' }

    foreach ($p in @($PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost, $PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost)) {
        if ($p -and (Microsoft.PowerShell.Management\Test-Path -LiteralPath $p -PathType Leaf)) {
            $content = ''
            try { $content = Microsoft.PowerShell.Management\Get-Content -LiteralPath $p -Raw -ErrorAction Stop } catch {}
            if ($content -match '(?i)CommandLookupAction|Set-PSBreakpoint|PSDefaultParameterValues|Update-TypeData|Add-Type|DllImport|Set-Alias|New-Alias|Invoke-Expression|\biex\b|DownloadString|function\s+(Get|Test|Select|Where|Invoke)-') {
                $alerts += "FAILURE: PowerShell profile contains hijack-capable code -> $p"
            } else {
                $alerts += "INFO: PowerShell profile present -> $p"
            }
        }
    }

    $gdp = $global:PSDefaultParameterValues
    if ($gdp -and $gdp.Count -gt 0) {
        foreach ($k in $gdp.Keys) { $alerts += "WARNING: Global default parameter set -> $k = $($gdp[$k])" }
    }

    $knownDefaultScriptMembers = @{
        'System.Diagnostics.Process' = @('Path', 'Company', 'CPU', 'FileVersion', 'ProductVersion', 'Description', 'Product')
        'System.IO.FileInfo'         = @('VersionInfo', 'BaseName')
    }

    foreach ($t in 'System.Management.Automation.Signature', 'System.Diagnostics.Process', 'System.IO.FileInfo', 'Microsoft.Management.Infrastructure.CimInstance') {
        try {
            $td = Microsoft.PowerShell.Utility\Get-TypeData -TypeName $t -ErrorAction Stop
            if (-not $td) { continue }
            $known = $knownDefaultScriptMembers[$t]
            if ($null -eq $known) { $known = @() }
            foreach ($m in $td.Members.Values) {
                if ($m -is [System.Management.Automation.Runspaces.ScriptPropertyData] -or $m -is [System.Management.Automation.Runspaces.ScriptMethodData]) {
                    if ($known -contains $m.Name) { continue }
                    $alerts += "FAILURE: Script override on $t -> '$($m.Name)'"
                }
            }
        } catch {}
    }

    foreach ($mod in @(Microsoft.PowerShell.Core\Get-Module)) {
        if (-not $mod.Path -or -not (Microsoft.PowerShell.Management\Test-Path -LiteralPath $mod.Path -PathType Leaf)) { continue }
        try {
            $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $mod.Path -ErrorAction Stop
            $isMs = $sig.Status -eq 'Valid' -and $sig.SignerCertificate -and $sig.SignerCertificate.Subject -match '(?i)Microsoft (Corporation|Windows)'
            if (-not $isMs) { $alerts += "WARNING: Non-Microsoft module loaded in session -> $($mod.Name) [$($sig.Status)] $($mod.Path)" }
        } catch {}
    }

    try {
        $sysRoot = $env:SystemRoot.ToLower() + '\'
        foreach ($m in [System.Diagnostics.Process]::GetCurrentProcess().Modules) {
            $path = [string]$m.FileName
            if (-not $path) { continue }
            $lower = $path.ToLower()
            if ($lower -match '\\assembly\\nativeimages_') { continue }
            $sig = $null
            try { $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop } catch {}
            $status = if ($sig) { [string]$sig.Status } else { 'Unknown' }
            if ($status -ne 'Valid') {
                if ($lower.StartsWith($sysRoot)) { continue }
                $alerts += "FAILURE: Unsigned DLL loaded in PowerShell ($status) -> $path"
            } elseif (-not (Test-SignedByShippedRoot -Path $path)) {
                $alerts += "FAILURE: DLL signed by user-installed root loaded in PowerShell -> $path"
            } elseif (Test-UserLandProcessPath -ExecutablePath $path) {
                $alerts += "WARNING: DLL from a user folder loaded in PowerShell -> $path"
            }
        }
    } catch { $alerts += 'WARNING: Could not list DLLs loaded in PowerShell' }

    foreach ($pair in @(
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging', 'EnableScriptBlockLogging'),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging', 'EnableModuleLogging')
    )) {
        try {
            if ([int](Microsoft.PowerShell.Management\Get-ItemPropertyValue -Path $pair[0] -Name $pair[1] -ErrorAction Stop) -eq 0) {
                $alerts += "WARNING: PowerShell logging disabled by policy -> $($pair[0])"
            }
        } catch {}
    }
    if (Microsoft.PowerShell.Management\Test-Path 'HKLM:\SOFTWARE\Microsoft\AMSI\Providers') {
        if (@(Microsoft.PowerShell.Management\Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\AMSI\Providers' -ErrorAction SilentlyContinue).Count -eq 0) {
            $alerts += 'FAILURE: No AMSI providers registered (script scanning disabled)'
        }
    } else {
        $alerts += 'WARNING: AMSI providers key missing'
    }

    try {
        $me = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($me.ParentProcessId)" -ErrorAction SilentlyContinue
        if ($parent -and $parent.Name -notmatch '(?i)^(explorer|cmd|powershell|pwsh|WindowsTerminal|OpenConsole|conhost|Code|svchost|RuntimeBroker)\.exe$') {
            $lvl = if ($parent.ExecutablePath -and -not (Test-SignedByShippedRoot -Path $parent.ExecutablePath)) { 'FAILURE' } else { 'WARNING' }
            $alerts += "${lvl}: PowerShell launched by unusual parent -> $($parent.Name) $($parent.ExecutablePath)"
        }
    } catch {}

    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: No PowerShell host hijacking detected') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

$script:SignatureCache = @{}

function Get-CachedSignatureStatus {
    param([string]$Path)
    if (-not $Path) { return 'Unknown' }
    if ($script:SignatureCache.ContainsKey($Path)) { return $script:SignatureCache[$Path] }
    $status = 'Unknown'
    try { $status = [string](Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop).Status } catch {}
    if ($status -eq 'Valid' -and -not (Test-SignedByShippedRoot -Path $Path)) { $status = 'UntrustedRoot' }
    $script:SignatureCache[$Path] = $status
    return $status
}

function Test-UntrustedUserProgramPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $l = $Path.ToLower()
    if ($l -match '\\roblox\\versions\\|\\bloxstrap\\|\\fishstrap\\|\\discord\\app-|\\microsoft\\teams\\|\\spotify\\|\\antigravity\\|\\utorrent web\\|\\telegram desktop\\|\\programs\\microsoft vs code\\') { return $false }
    return ($l -match '\\(downloads|desktop|documents|temp|appdata)\\')
}

function Get-UnsignedUserProgramAlerts {
    $alerts = @()
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction Stop
        $grouped = @{}
        foreach ($p in $procs) {
            $path = [string]$p.ExecutablePath
            if (-not (Test-UntrustedUserProgramPath -Path $path)) { continue }
            $status = Get-CachedSignatureStatus -Path $path
            if ($status -eq 'Valid') { continue }
            if (-not $grouped.ContainsKey($path)) {
                $grouped[$path] = @{
                    Name = $p.Name
                    Status = $status
                    Pids = New-Object System.Collections.Generic.List[int]
                }
            }
            $grouped[$path].Pids.Add([int]$p.ProcessId)
        }

        foreach ($path in $grouped.Keys) {
            $item = $grouped[$path]
            $kw = Get-MatchedCheatKeyword -Text $path
            $kwTag = if ($kw) { " [$kw]" } else { '' }
            $pidStr = if ($item.Pids.Count -eq 1) { "PID $($item.Pids[0])" } else { "PID $($item.Pids -join ', ')" }
            if ($kw) {
                $alerts += "FAILURE: Unsigned program$kwTag running from user folder ($($item.Status)) -> $($item.Name) ($pidStr) $path"
            } else {
                $alerts += "WARNING: Unsigned program running from user folder ($($item.Status)) -> $($item.Name) ($pidStr) $path"
            }
        }
    } catch { $alerts += 'WARNING: Could not enumerate processes for signature check' }
    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: No unsigned programs running from user folders' }
    return @($alerts | Select-Object -Unique)
}

$script:BaselineBamKeys = @{}
$script:BaselinePrefetchFiles = @{}
$script:MainLoopFailureWarned = @{}

function Get-AlertSetSummary {
    param([string[]]$Lines)

    $s = @{ Fail = 0; Warn = 0; Info = 0; Pass = 0 }
    foreach ($line in @($Lines)) {
        if ($line -like 'FAILURE*')     { $s.Fail++ }
        elseif ($line -like 'WARNING*') { $s.Warn++ }
        elseif ($line -like 'INFO*')    { $s.Info++ }
        elseif ($line -like 'SUCCESS*') { $s.Pass++ }
    }
    if ($s.Fail -gt 0)     { $s.Status = 'FAIL' }
    elseif ($s.Warn -gt 0) { $s.Status = 'WARN' }
    elseif ($null -eq $Lines -or $Lines.Count -eq 0) { $s.Status = 'WARN'; $s.Warn = 1 }
    else                   { $s.Status = 'PASS' }
    return $s
}

function Test-AlertSetPassed {
    param([string[]]$Lines)
    return ((Get-AlertSetSummary -Lines $Lines).Status -ne 'FAIL')
}

function Write-Rule { Out-Rule }

function Write-TaggedLine {
    param([string]$Line, [string]$Indent = '  ')

    $tag = 'NOTE'; $text = $Line
    if ($Line -match '(?s)^(SUCCESS|FAILURE|WARNING|INFO):\s*(.*)$') {
        $text = $matches[2]
        switch ($matches[1]) {
            'SUCCESS' { $tag = 'PASS' }
            'FAILURE' { $tag = 'FAIL' }
            'WARNING' { $tag = 'WARN' }
            'INFO'    { $tag = 'INFO' }
        }
    }
    $textTok = switch ($tag) { 'FAIL' { 'Text' } 'INFO' { 'Muted' } default { 'Body' } }
    Out-TaggedText -Indent $Indent -Tag $tag -Text $text -TextToken $textTok
}

# "  | Kernel Drivers                                   FAIL "  followed by its findings
function Write-Section {
    param($Title, $Lines)

    $summary = Get-AlertSetSummary -Lines @($Lines)
    $tok = Get-StatusToken $summary.Status
    $pad = [Math]::Max(1, $script:UiWidth - 8 - ([string]$Title).Length)
    Out-Seg ''
    Out-Seg '  ' -NoNewline
    Out-Seg $script:G.Bar -Fg $tok -NoNewline
    Out-Seg (' ' + $Title) -Fg 'Text' -Bold -NoNewline
    Out-Seg (' ' * $pad) -NoNewline
    Out-Badge $summary.Status
    foreach ($line in @($Lines)) { Write-TaggedLine -Line $line -Indent '    ' }
}

# =============================================================================
#   BSMM additional checks
#   Each returns lines starting with SUCCESS: / INFO: / WARNING: / FAILURE:
# =============================================================================

$script:BsmmExecExt    = @('.exe', '.dll', '.sys', '.bat', '.cmd', '.com', '.scr', '.ps1', '.vbs', '.js', '.ahk', '.lua', '.luau', '.msi', '.jar', '.asi')
$script:BsmmArchiveExt = @('.zip', '.rar', '.7z', '.tar', '.gz', '.iso', '.img', '.vhd', '.vhdx')

function Get-BsmmExtension {
    param([string]$Path)
    try { return [System.IO.Path]::GetExtension($Path).ToLower() } catch { return '' }
}

# Reads a text file whatever its encoding (UTF-16 with or without BOM, UTF-8, ANSI),
# even while Windows still has it open.
function Read-BsmmTextFile {
    param([string]$Path)
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $ms = New-Object System.IO.MemoryStream
        $fs.CopyTo($ms)
        $bytes = $ms.ToArray()
    } finally {
        $fs.Dispose()
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) }
    $sample = [Math]::Min($bytes.Length, 4000)
    $zeros = 0
    for ($i = 1; $i -lt $sample; $i += 2) { if ($bytes[$i] -eq 0) { $zeros++ } }
    if ($sample -gt 0 -and $zeros -gt ($sample / 4)) { return [Text.Encoding]::Unicode.GetString($bytes) }
    return [Text.Encoding]::UTF8.GetString($bytes)
}

# --- 1. Session environment: virtual machine, Remote Desktop, Windows Sandbox -----------------
function Get-SessionEnvironmentAlerts {
    $alerts = @()
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $bios = $null
        try { $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop } catch {}
        $fingerprint = "$($cs.Manufacturer) | $($cs.Model) | $($bios.Manufacturer) | $($bios.SMBIOSBIOSVersion) | $($bios.SerialNumber)"
        if ($fingerprint -match '(?i)VMware|VirtualBox|innotek|QEMU|\bKVM\b|\bXen\b|Parallels|Bochs|BHYVE|Virtual Machine') {
            $alerts += "WARNING: This check is running inside a virtual machine ($($matches[0])) - the game may be running on a different PC"
        }
    } catch {
        $alerts += 'WARNING: Could not read hardware information'
    }
    if ($env:SESSIONNAME -and $env:SESSIONNAME -match '^RDP-') {
        $alerts += "WARNING: Running over Remote Desktop ($env:SESSIONNAME) - the screen on the recording may belong to a different PC"
    }
    if ($env:USERNAME -eq 'WDAGUtilityAccount') {
        $alerts += 'WARNING: Running inside Windows Sandbox - this is not the real Windows install'
    }
    $boot = Get-BootTime
    if ($boot) {
        $up = (Get-Date) - $boot
        $upText = '{0}h {1:00}m' -f [int][Math]::Floor($up.TotalHours), $up.Minutes
        if ($script:Policy.MaxUptimeMinutes -gt 0 -and $up.TotalMinutes -gt $script:Policy.MaxUptimeMinutes) {
            $alerts += "WARNING: PC was not restarted before the check (up for $upText, the limit is $($script:Policy.MaxUptimeMinutes) min)"
        } else {
            $alerts += "INFO: PC uptime $upText (booted $(Get-Date $boot -Format 'yyyy-MM-dd HH:mm'))"
        }
    }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts = @('SUCCESS: Running on a physical PC in a local session') + $alerts }
    return $alerts
}

# --- 2. Program launch traces: Windows 11 PCA log + Explorer UserAssist ----------------------
#     Both survive the usual BAM / Prefetch cleaners.
$script:KnownFolderGuids = @{
    '{374DE290-123F-4565-9164-39C4925E467B}' = @(Get-BsmmUserFolders Downloads)[0]
    '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}' = @(Get-BsmmUserFolders Desktop)[0]
    '{FDD39AD0-238F-46AF-ADB4-6C85480369C7}' = @(Get-BsmmUserFolders Documents)[0]
    '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}' = $env:LOCALAPPDATA
    '{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}' = $env:APPDATA
    '{F38BF404-1D43-42F2-9305-67DE0B28FC23}' = $env:SystemRoot
    '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}' = (Join-Path $env:SystemRoot 'System32')
    '{D65231B0-B2F1-4857-A4CE-A8E7C6EA7D27}' = (Join-Path $env:SystemRoot 'SysWOW64')
    '{6D809377-6AF0-444B-8957-A3773F02200E}' = $env:ProgramFiles
    '{7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E}' = ${env:ProgramFiles(x86)}
}

function ConvertFrom-Rot13 {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder $Text.Length
    foreach ($ch in $Text.ToCharArray()) {
        $c = [int]$ch
        if ($c -ge 65 -and $c -le 90) { $c = (($c - 65 + 13) % 26) + 65 }
        elseif ($c -ge 97 -and $c -le 122) { $c = (($c - 97 + 13) % 26) + 97 }
        [void]$sb.Append([char]$c)
    }
    return $sb.ToString()
}

function Get-PcaLaunchAlerts {
    $alerts = @()
    $file = Join-Path $env:SystemRoot 'appcompat\pca\PcaAppLaunchDic.txt'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        return @('INFO: Windows launch log (PCA) not present - it only exists on Windows 11 22H2 and newer')
    }
    $content = $null
    try { $content = Read-BsmmTextFile -Path $file } catch {
        return @('WARNING: Could not read the Windows launch log (PCA) - run as administrator')
    }
    $logon = Get-LogonTime
    $weekAgo = (Get-Date).AddDays(-7)
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal
    $recent = 0
    foreach ($line in ($content -split "`r?`n")) {
        $parts = $line.Split('|')
        if ($parts.Count -lt 2) { continue }
        $path = $parts[0].Trim()
        $stamp = $parts[$parts.Count - 1].Trim()
        if (-not $path) { continue }
        $ranAt = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($stamp, 'yyyy-MM-dd HH:mm:ss.fff', $culture, $styles, [ref]$ranAt)) {
            if (-not [datetime]::TryParse($stamp, $culture, $styles, [ref]$ranAt)) { continue }
        }
        if ($ranAt -lt $weekAgo) { continue }
        $when = Get-Date $ranAt -Format 'yyyy-MM-dd HH:mm'
        $kw = Get-MatchedCheatKeyword -Text $path
        if ($kw) {
            $alerts += "FAILURE: Windows launch log [$kw] ran $when -> $path"
            continue
        }
        if ($ranAt -ge $logon) {
            $recent++
            if ((Test-UntrustedUserProgramPath -Path $path) -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
                $alerts += "WARNING: Program ran this session and was deleted afterwards ($when) -> $path"
            }
        }
    }
    if ($alerts.Count -eq 0) { $alerts += "SUCCESS: Windows launch log clean ($recent programs started since logon)" }
    return @($alerts | Select-Object -Unique)
}

function Get-UserAssistAlerts {
    $alerts = @()
    try {
        $adv = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ErrorAction Stop
        if ($null -ne $adv.Start_TrackProgs -and [int]$adv.Start_TrackProgs -eq 0) {
            $alerts += 'INFO: Windows app-launch tracking is switched off in privacy settings (Explorer history is not recorded)'
        }
    } catch {}

    $rootKey = $null
    try { $rootKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist') } catch {}
    if (-not $rootKey) { return @('WARNING: Explorer launch history (UserAssist) is missing - it may have been wiped') + $alerts }

    $logon = Get-LogonTime
    $weekAgo = (Get-Date).AddDays(-7)
    $entries = 0
    foreach ($guid in $rootKey.GetSubKeyNames()) {
        $countKey = $null
        try { $countKey = $rootKey.OpenSubKey("$guid\Count") } catch {}
        if (-not $countKey) { continue }
        foreach ($valueName in $countKey.GetValueNames()) {
            $raw = $countKey.GetValue($valueName)
            if (-not ($raw -is [byte[]]) -or $raw.Length -lt 68) { continue }
            $ft = [BitConverter]::ToInt64($raw, 60)
            if ($ft -le 0) { continue }
            $ranAt = $null
            try { $ranAt = [DateTime]::FromFileTime($ft) } catch { continue }
            if ($ranAt -lt $weekAgo) { continue }
            $name = ConvertFrom-Rot13 $valueName
            if ($name -match '^(\{[0-9A-Fa-f\-]{36}\})\\(.*)$' -and $script:KnownFolderGuids.ContainsKey($matches[1]) -and $script:KnownFolderGuids[$matches[1]]) {
                $name = Join-Path $script:KnownFolderGuids[$matches[1]] $matches[2]
            }
            if ($name -notmatch '(?i)\.(exe|bat|cmd|com|scr|ahk|ps1|vbs|msi|jar)$') { continue }
            $entries++
            $when = Get-Date $ranAt -Format 'yyyy-MM-dd HH:mm'
            $kw = Get-MatchedCheatKeyword -Text $name
            if ($kw) {
                $alerts += "FAILURE: Explorer launch history [$kw] opened $when -> $name"
                continue
            }
            if ($ranAt -ge $logon -and $name -match '^[A-Za-z]:\\' -and (Test-UntrustedUserProgramPath -Path $name) -and
                -not (Test-Path -LiteralPath $name -PathType Leaf)) {
                $alerts += "WARNING: Program opened from Explorer this session was deleted afterwards ($when) -> $name"
            }
        }
        $countKey.Close()
    }
    $rootKey.Close()
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @("SUCCESS: Explorer launch history clean ($entries programs opened in the last 7 days)") + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

# --- 3. Recycle Bin: programs deleted just before the check --------------------------------
function Get-RecycleBinEntries {
    param([datetime]$Since)
    $entries = @()
    $sid = $null
    try { $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch {}
    if (-not $sid) { return $entries }
    $drives = @()
    try {
        $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName })
    } catch {
        $drives = @("$env:SystemDrive\")
    }
    foreach ($d in $drives) {
        $bin = Join-Path $d ('$Recycle.Bin\' + $sid)
        if (-not (Test-Path -LiteralPath $bin)) { continue }
        $files = @()
        try { $files = @(Get-ChildItem -LiteralPath $bin -Force -File -Filter '$I*' -ErrorAction Stop) } catch { continue }
        foreach ($f in $files) {
            if ($f.LastWriteTime -lt $Since.AddMinutes(-5)) { continue }
            try {
                $b = [System.IO.File]::ReadAllBytes($f.FullName)
                if ($b.Length -lt 24) { continue }
                $ver = [BitConverter]::ToInt64($b, 0)
                $deletedAt = [DateTime]::FromFileTime([BitConverter]::ToInt64($b, 16))
                if ($deletedAt -lt $Since) { continue }
                $orig = ''
                if ($ver -ge 2 -and $b.Length -ge 28) {
                    $len = [BitConverter]::ToInt32($b, 24)
                    $byteLen = [Math]::Min($len * 2, $b.Length - 28)
                    if ($byteLen -gt 0) { $orig = [Text.Encoding]::Unicode.GetString($b, 28, $byteLen) }
                } else {
                    $orig = [Text.Encoding]::Unicode.GetString($b, 24, [Math]::Min(520, $b.Length - 24))
                }
                $orig = $orig.Split([char]0)[0]
                if (-not $orig) { continue }
                $rItem = Join-Path $f.DirectoryName ('$R' + $f.Name.Substring(2))
                $entries += [pscustomobject]@{
                    Path      = $orig
                    DeletedAt = $deletedAt
                    IsFolder  = (Test-Path -LiteralPath $rItem -PathType Container)
                }
            } catch {}
        }
    }
    return $entries
}

function Get-RecycleBinAlerts {
    $alerts = @()
    $logon = Get-LogonTime
    foreach ($e in (@(Get-RecycleBinEntries -Since ((Get-Date).AddDays(-7))) | Sort-Object DeletedAt -Descending)) {
        $when = Get-Date $e.DeletedAt -Format 'yyyy-MM-dd HH:mm'
        $kw = Get-MatchedCheatKeyword -Text $e.Path
        if ($kw) {
            $alerts += "FAILURE: Deleted [$kw] on $when -> $($e.Path)"
            continue
        }
        if ($e.DeletedAt -lt $logon) { continue }
        $ext = Get-BsmmExtension $e.Path
        if (-not $e.IsFolder -and $script:BsmmExecExt -contains $ext) {
            $alerts += "WARNING: Program deleted this session ($when) -> $($e.Path)"
        } elseif ($e.IsFolder -or $script:BsmmArchiveExt -contains $ext) {
            $alerts += "INFO: Deleted this session ($when) -> $($e.Path)"
        }
    }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: No programs sent to the Recycle Bin this session') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

# --- 4. Download origins: where recent programs and archives were downloaded from ----------
#     Windows stores the source URL of every browser download (Mark of the Web).
$script:FileHostPattern = '(?i)(^|\.)(mediafire\.com|mega\.nz|mega\.io|gofile\.io|pixeldrain\.com|catbox\.moe|workupload\.com|sendspace\.com|anonfiles\.com|krakenfiles\.com|1fichier\.com|uploadhaven\.com|transfer\.sh|filebin\.net|files\.fm|qu\.ax|bashupload\.com|cdn\.discordapp\.com|media\.discordapp\.net|cdn\.discordapp\.net)$'

function Get-DownloadOriginAlerts {
    $alerts = @()
    $since = (Get-Date).AddDays(-14)
    $wanted = $script:BsmmExecExt + $script:BsmmArchiveExt
    $checked = 0
    foreach ($folder in (@(Get-BsmmUserFolders Downloads) + @(Get-BsmmUserFolders Desktop))) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        $files = @()
        try {
            $files = @(Get-ChildItem -LiteralPath $folder -File -Recurse -Depth 2 -Force -ErrorAction SilentlyContinue |
                Where-Object { ($_.LastWriteTime -ge $since -or $_.CreationTime -ge $since) -and ($wanted -contains $_.Extension.ToLower()) } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 300)
        } catch {}
        foreach ($f in $files) {
            $checked++
            $zone = $null
            try { $zone = @(Get-Content -LiteralPath $f.FullName -Stream Zone.Identifier -ErrorAction Stop) } catch { continue }
            $hostUrl = ''; $refUrl = ''
            foreach ($zl in $zone) {
                if ($zl -match '^HostUrl=(.+)$') { $hostUrl = $matches[1].Trim() }
                elseif ($zl -match '^ReferrerUrl=(.+)$') { $refUrl = $matches[1].Trim() }
            }
            $src = $hostUrl; if (-not $src) { $src = $refUrl }
            if (-not $src -or $src -match '^(?i)about:') { continue }
            $clean = ($src -split '[\?#]')[0]
            $hostName = ''
            try { $hostName = ([Uri]$clean).Host.ToLower() } catch {}
            $kw = Get-MatchedCheatKeyword -Text $f.Name
            if (-not $kw) { $kw = Get-MatchedCheatKeyword -Text $clean }
            if (-not $kw -and $refUrl) { $kw = Get-MatchedCheatKeyword -Text (($refUrl -split '[\?#]')[0]) }
            if ($kw) {
                $alerts += "FAILURE: Downloaded [$kw] '$($f.Name)' from $clean"
                continue
            }
            if ($hostName -and $hostName -match $script:FileHostPattern) {
                if ($script:BsmmExecExt -contains $f.Extension.ToLower()) {
                    $alerts += "WARNING: Program downloaded from a file-sharing site ($hostName) -> $($f.FullName)"
                } else {
                    $alerts += "INFO: Archive downloaded from a file-sharing site ($hostName) -> $($f.FullName)"
                }
            }
        }
    }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @("SUCCESS: Download sources look normal ($checked recent programs/archives checked)") + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

# --- 5. Driver install log: new drivers/services and drivers Windows refused to load --------
function Get-ServiceInstallEvents {
    param([datetime]$Since)
    $events = @()
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7045; StartTime = $Since } -MaxEvents 300 -ErrorAction Stop)
    } catch {}
    $out = @()
    foreach ($e in $events) {
        $props = @($e.Properties | ForEach-Object { [string]$_.Value })
        if ($props.Count -lt 2) { continue }
        $out += [pscustomobject]@{ Time = $e.TimeCreated; Name = $props[0]; Image = $props[1]; RecordId = $e.RecordId }
    }
    return $out
}

function Get-DriverInstallAlerts {
    $alerts = @()
    $logon = Get-LogonTime
    $since = (Get-Date).AddDays(-7)

    # Software such as RGB/fan tools re-installs its driver on every launch, so group repeats.
    $groups = @(Get-ServiceInstallEvents -Since $since | Group-Object { "$($_.Name)|$($_.Image)".ToLower() })
    foreach ($g in $groups) {
        $ev = @($g.Group | Sort-Object Time -Descending)[0]
        $times = ''
        if ($g.Count -gt 1) { $times = " (x$($g.Count))" }
        $norm = [string](Normalize-KernelDriverPath -Path $ev.Image)
        if (-not $norm) { $norm = [string]$ev.Image }
        $lower = $norm.ToLower()
        $isDriver = $lower -match '\.sys(\s|"|$)'
        $leaf = ''
        if ($lower -match '([^\\/"]+\.sys)') { $leaf = $matches[1] }
        if ($leaf -match '^procexp\d*\.sys$') { continue }
        $thisSession = ($ev.Time -ge $logon)
        $when = (Get-Date $ev.Time -Format 'yyyy-MM-dd HH:mm') + $times
        $userLand = $lower -match '\\(users|temp|downloads|desktop|appdata)\\'
        $tier = $null
        if ($leaf -and $script:VulnerableDriverTiers.ContainsKey($leaf)) { $tier = $script:VulnerableDriverTiers[$leaf] }
        $kw = Get-MatchedCheatKeyword -Text "$($ev.Name) $norm"

        if ($kw) {
            $alerts += "FAILURE: Service/driver [$kw] installed $when -> $($ev.Name) ($norm)"
        } elseif ($tier -and $tier -ne 'SKIP' -and $userLand) {
            $alerts += "FAILURE: Known vulnerable driver '$leaf' installed from a user folder $when - the classic way to load cheats into the kernel -> $norm"
        } elseif ($tier -and $tier -ne 'SKIP') {
            # Installed by regular software (e.g. MSI Center, RGB/fan tools). The 'Vulnerable Drivers'
            # check already raises this if the driver is loaded right now.
            $alerts += "INFO: Known vulnerable driver '$leaf' installed by software $when -> $norm"
        } elseif ($isDriver -and $userLand) {
            $lvl = 'WARNING'; if ($thisSession) { $lvl = 'FAILURE' }
            $alerts += "${lvl}: Kernel driver installed from a user folder $when -> $($ev.Name) ($norm)"
        } elseif ($isDriver -and $thisSession -and $lower -notmatch '\\windows\\system32\\(drivers|driverstore)\\' -and $lower -notmatch '\\program files') {
            $alerts += "WARNING: New kernel driver installed this session ($when) -> $($ev.Name) ($norm)"
        } elseif ($isDriver -and $thisSession) {
            $alerts += "INFO: Driver installed this session ($when) -> $($ev.Name) ($norm)"
        } elseif (-not $isDriver -and $thisSession -and $userLand) {
            $alerts += "WARNING: Service installed from a user folder this session ($when) -> $($ev.Name) ($norm)"
        }
    }

    # Code Integrity: drivers Windows blocked or could not verify (bad/revoked signature, driver blocklist)
    try {
        $ci = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; Id = @(3004, 3023, 3033, 3077); StartTime = $since } -MaxEvents 300 -ErrorAction Stop)
        $seen = @{}
        foreach ($e in $ci) {
            $msg = [string]$e.Message
            if ($msg -notmatch '(?i)([^\\/"\s]+\.sys)\b') { continue }
            $leafOrig = $matches[1]
            $leaf = $leafOrig.ToLower()
            if ($seen.ContainsKey($leaf)) { continue }
            $seen[$leaf] = $true
            $idx = $msg.IndexOf($leafOrig, [StringComparison]::OrdinalIgnoreCase)
            $start = $msg.LastIndexOf('\Device\', $idx, [StringComparison]::OrdinalIgnoreCase)
            $shown = $leafOrig
            if ($start -ge 0) { $shown = $msg.Substring($start, $idx + $leafOrig.Length - $start) }
            $when = Get-Date $e.TimeCreated -Format 'yyyy-MM-dd HH:mm'
            $tier = $null
            if ($script:VulnerableDriverTiers.ContainsKey($leaf)) { $tier = $script:VulnerableDriverTiers[$leaf] }
            if ($tier -eq 'FAILURE' -or (Get-MatchedCheatKeyword -Text $shown)) {
                $alerts += "FAILURE: Windows blocked driver '$leafOrig' from loading on $when - it is used to load cheats -> $shown"
            } else {
                $alerts += "WARNING: Windows blocked or could not verify driver '$leafOrig' on $when (event $($e.Id)) -> $shown"
            }
        }
    } catch {}

    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: No suspicious driver installs or blocked drivers in the last 7 days') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

# --- 6. Encrypted / virtual drives (where tools get hidden before a screenshare) ------------
function Get-HiddenVolumeAlerts {
    $alerts = @()
    try {
        Get-CimInstance Win32_SystemDriver -ErrorAction Stop |
            Where-Object { $_.Name -match '^(?i)(veracrypt|truecrypt|imdisk|awealloc|osfmount|phdskmnt|aimwrfltr)$' } |
            ForEach-Object {
                $lvl = 'INFO'; if ($_.State -eq 'Running') { $lvl = 'WARNING' }
                $alerts += "${lvl}: Encrypted/virtual drive software installed - driver '$($_.Name)' is $($_.State)"
            }
    } catch {}

    foreach ($pn in @('VeraCrypt', 'VeraCrypt-x64', 'TrueCrypt', 'ImDiskTk', 'OSFMount')) {
        try {
            if (Get-Process -Name $pn -ErrorAction Stop) { $alerts += "WARNING: $pn is open right now" }
        } catch {}
    }

    try {
        $mk = Open-LocalMachineRegistryKey -SubKeyPath 'SYSTEM\MountedDevices'
        if ($mk) {
            foreach ($vn in $mk.GetValueNames()) {
                $data = $mk.GetValue($vn)
                if (-not ($data -is [byte[]]) -or $data.Length -lt 8) { continue }
                $txt = [Text.Encoding]::Unicode.GetString($data)
                if ($txt -match '(?i)(veracrypt|truecrypt|imdisk)') {
                    $kind = $matches[1]
                    $label = $vn -replace '^\\DosDevices\\', 'drive '
                    $alerts += "WARNING: A $kind volume has been mounted on this PC ($label)"
                }
            }
            $mk.Close()
        }
    } catch {}

    try {
        Get-CimInstance Win32_DiskDrive -ErrorAction Stop |
            Where-Object { $_.Model -match '(?i)veracrypt|truecrypt|imdisk|arsenal|virtual disk' } |
            ForEach-Object {
                $gb = 0; try { $gb = [Math]::Round($_.Size / 1GB, 1) } catch {}
                $alerts += "WARNING: Virtual disk attached right now -> $($_.Model) ($gb GB)"
            }
    } catch {}

    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: No encrypted or virtual drives mounted') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

# --- 7. Macro and auto-clicker tools -----------------------------------------------------------
$script:MacroProcessPattern = '^(?i)(autohotkey.*|ahk2exe|tinytask|macrorecorder|jitbit.*|macrocreator.*|autoclicker|op ?auto ?clicker.*|gs ?auto ?clicker.*|speed ?auto ?clicker|max ?auto ?clicker|murgee.*|rewasd.*|keyran.*)$'
$script:MacroProductPattern = '(?i)AutoHotkey|Macro Recorder|Macro Creator|Auto ?Clicker|TinyTask|reWASD'

function Get-MacroToolAlerts {
    $alerts = @()
    $seen = @{}
    $procs = @()
    try { $procs = @(Get-Process -ErrorAction Stop) } catch {}
    foreach ($p in $procs) {
        $name = [string]$p.ProcessName
        $path = $null
        try { $path = $p.Path } catch {}
        $why = $null
        if ($name -match $script:MacroProcessPattern) {
            $why = $name
        } elseif ($path -and $path -notmatch '^(?i)[a-z]:\\windows\\') {
            try {
                $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
                if ("$($vi.ProductName) $($vi.FileDescription)" -match $script:MacroProductPattern) { $why = "$($matches[0]) - process '$name'" }
            } catch {}
        }
        if (-not $why) { continue }
        $key = "$name|$path"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $detail = ''
        if ($name -match '(?i)autohotkey') {
            try {
                $cl = [string](Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction Stop).CommandLine
                if ($cl -match '(?i)"([^"]+\.ahk)"') { $detail = " running $($matches[1])" }
                elseif ($cl -match '(?i)(\S+\.ahk)') { $detail = " running $($matches[1])" }
            } catch {}
        }
        $shown = $path; if (-not $shown) { $shown = $name }
        $alerts += "WARNING: Macro / auto-clicker running ($why)$detail -> $shown"
    }
    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: No macro or auto-clicker tools running' }
    return @($alerts | Select-Object -Unique)
}

# --- 8. Roblox install folder: planted proxy DLLs and modified client files ------------------
$script:ProxyDllNames = @(
    'dxgi.dll', 'd3d9.dll', 'd3d10.dll', 'd3d11.dll', 'd3d12.dll', 'dinput8.dll', 'version.dll', 'winmm.dll',
    'winhttp.dll', 'wininet.dll', 'xinput1_3.dll', 'xinput1_4.dll', 'xinput9_1_0.dll', 'opengl32.dll', 'dbghelp.dll',
    'dsound.dll', 'msimg32.dll', 'uxtheme.dll', 'cryptsp.dll', 'wtsapi32.dll', 'iphlpapi.dll', 'userenv.dll',
    'hid.dll', 'dwmapi.dll', 'mswsock.dll', 'dbgcore.dll', 'winspool.drv'
)

function Get-RobloxFolderAlerts {
    $alerts = @()
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Roblox\Versions'),
        (Join-Path $env:LOCALAPPDATA 'Bloxstrap\Versions'),
        (Join-Path $env:LOCALAPPDATA 'Fishstrap\Versions')
    )
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} 'Roblox\Versions') }
    $folders = @()
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r -PathType Container)) { continue }
        try {
            $folders += @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction Stop |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'RobloxPlayerBeta.exe') -PathType Leaf })
        } catch {}
    }
    if ($folders.Count -eq 0) { return @('INFO: No Roblox client folder found') }

    $checked = 0
    foreach ($folder in $folders) {
        $files = @()
        try { $files = @(Get-ChildItem -LiteralPath $folder.FullName -File -Force -ErrorAction Stop | Where-Object { $_.Extension -match '^(?i)\.(dll|exe|asi|drv)$' }) } catch { continue }
        foreach ($f in $files) {
            $checked++
            $sig = $null
            try { $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $f.FullName -ErrorAction Stop } catch {}
            $status = 'Unknown'; if ($sig) { $status = [string]$sig.Status }
            $signer = ''
            if ($sig -and $sig.SignerCertificate -and $sig.SignerCertificate.Subject -match 'CN=([^,]+)') { $signer = $matches[1].Trim('"', ' ') }
            $name = $f.Name.ToLower()
            $kw = Get-MatchedCheatKeyword -Text $f.Name
            $trusted = ($status -eq 'Valid' -and $signer -match '^(?i)(Roblox Corporation|Microsoft Corporation|Microsoft Windows)$')
            if ($trusted) { continue }    # validly signed by Roblox/Microsoft (e.g. WebView2Loader.dll)

            if ($name -eq 'robloxplayerbeta.exe') {
                $alerts += "FAILURE: Roblox client is not signed by Roblox ($status) - modified or patched client -> $($f.FullName)"
            } elseif ($kw) {
                $alerts += "FAILURE: [$kw] file inside the Roblox folder -> $($f.FullName)"
            } elseif ($f.Extension -eq '.asi' -or $script:ProxyDllNames -contains $name) {
                $alerts += "FAILURE: Planted '$name' next to Roblox ($status) - a common way to inject cheats -> $($f.FullName)"
            } elseif ($status -ne 'Valid') {
                $alerts += "WARNING: Unsigned file inside the Roblox folder ($status) -> $($f.FullName)"
            } else {
                $alerts += "WARNING: File in the Roblox folder signed by '$signer' -> $($f.FullName)"
            }
        }
    }
    if ($alerts.Count -eq 0) { $alerts += "SUCCESS: Roblox folder clean ($checked files in $($folders.Count) version folder(s), all signed by Roblox/Microsoft)" }
    return @($alerts | Select-Object -Unique)
}

# =============================================================================
#   Recording-policy checks (the manual steps from the league rules, automated)
# =============================================================================

# --- 9. UAC: elevation prompts must be visible to the recording --------------------------------
function Get-UacAlerts {
    $p = $null
    try { $p = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop } catch {
        return @('WARNING: Could not read UAC settings')
    }
    $lua = 1;     if ($null -ne $p.EnableLUA) { $lua = [int]$p.EnableLUA }
    $consent = 5; if ($null -ne $p.ConsentPromptBehaviorAdmin) { $consent = [int]$p.ConsentPromptBehaviorAdmin }
    $secure = 1;  if ($null -ne $p.PromptOnSecureDesktop) { $secure = [int]$p.PromptOnSecureDesktop }
    if ($lua -eq 0) { return @('FAILURE: UAC is turned off - programs get admin rights without any prompt') }
    if ($consent -eq 0) { return @('FAILURE: UAC is set to "Never notify" - admin prompts are skipped silently') }
    if ($secure -eq 1) { return @('WARNING: UAC prompts appear on the secure desktop, which records as a black screen (set UAC to the second-lowest level)') }
    return @('SUCCESS: UAC is on and its prompts are visible to the recording')
}

# --- 10. Window animations: with them off, a cheat window can vanish between frames ------------
function Get-AnimationAlerts {
    $alerts = @()
    try {
        $min = [string](Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name MinAnimate -ErrorAction Stop)
        if ($min -eq '0') { $alerts += 'WARNING: "Animate windows when minimizing and maximizing" is off - windows can be hidden instantly' }
    } catch {}
    try {
        $tb = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarAnimations -ErrorAction Stop
        if ([int]$tb -eq 0) { $alerts += 'WARNING: Taskbar animations are off' }
    } catch {}
    try {
        $fx = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -ErrorAction Stop
        if ([int]$fx -eq 2) { $alerts += 'WARNING: Visual effects are set to "Adjust for best performance" (all animations off)' }
    } catch {}
    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: Window animations are on' }
    return $alerts
}

# --- 11. Displays and virtual desktops ----------------------------------------------------------
function Get-DisplayDesktopAlerts {
    $alerts = @()
    $count = 0
    try {
        $count = @(Get-CimInstance -Namespace 'root\wmi' -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop | Where-Object { $_.Active }).Count
    } catch {}
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $screens = [System.Windows.Forms.Screen]::AllScreens.Count
        if ($screens -gt $count) { $count = $screens }
    } catch {}
    if ($count -gt 1) { $alerts += "WARNING: $count displays are connected - only one is allowed during the recording" }
    elseif ($count -eq 1) { $alerts += 'SUCCESS: One display connected' }

    $ids = $null
    try { $ids = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops' -Name VirtualDesktopIDs -ErrorAction Stop).VirtualDesktopIDs } catch {}
    if (-not $ids) {
        try {
            $sid = (Get-Process -Id $PID).SessionId
            $ids = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\$sid\VirtualDesktops" -Name VirtualDesktopIDs -ErrorAction Stop).VirtualDesktopIDs
        } catch {}
    }
    if ($ids -is [byte[]] -and $ids.Length -ge 32) {
        $alerts += "WARNING: $([int]($ids.Length / 16)) virtual desktops are open (Win+Tab) - windows can be hidden on another desktop"
    } else {
        $alerts += 'SUCCESS: Only one virtual desktop'
    }
    return $alerts
}

# --- 12. OBS: scripts, scene-switch / pause hotkeys -----------------------------------------------
function Get-IniValue {
    param([string[]]$Lines, [string]$Section, [string]$Name)
    $inSection = $false
    foreach ($l in $Lines) {
        if ($l -match '^\s*\[(.+)\]\s*$') { $inSection = ($matches[1] -eq $Section); continue }
        if ($inSection -and $l -match ('^\s*' + [regex]::Escape($Name) + '\s*=(.*)$')) { return $matches[1].Trim() }
    }
    return $null
}

function Get-ObsAlerts {
    $alerts = @()
    $base = Join-Path $env:APPDATA 'obs-studio'
    if (-not (Test-Path -LiteralPath $base)) { return @('INFO: OBS Studio is not set up for this Windows user (another recorder may be in use)') }

    $ini = @()
    foreach ($n in @('user.ini', 'global.ini')) {
        $f = Join-Path $base $n
        if (Test-Path -LiteralPath $f) { try { $ini += @(Get-Content -LiteralPath $f -ErrorAction Stop) } catch {} }
    }
    $collectionFile = Get-IniValue -Lines $ini -Section 'Basic' -Name 'SceneCollectionFile'
    $profileDir = Get-IniValue -Lines $ini -Section 'Basic' -Name 'ProfileDir'

    $sceneJson = $null
    if ($collectionFile) { $sceneJson = Join-Path $base "basic\scenes\$collectionFile.json" }
    if (-not $sceneJson -or -not (Test-Path -LiteralPath $sceneJson)) {
        $latest = Get-ChildItem -LiteralPath (Join-Path $base 'basic\scenes') -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $sceneJson = $latest.FullName }
    }

    if ($sceneJson -and (Test-Path -LiteralPath $sceneJson)) {
        try {
            $doc = Get-Content -LiteralPath $sceneJson -Raw -ErrorAction Stop | ConvertFrom-Json
            $scripts = @()
            if ($doc.modules -and $doc.modules.'scripts-tool') { $scripts = @($doc.modules.'scripts-tool' | Where-Object { $_ -and $_.path }) }
            foreach ($s in $scripts) { $alerts += "WARNING: OBS script loaded -> $($s.path)" }

            $scenes = @($doc.sources | Where-Object { $_.id -eq 'scene' })
            $switchKeys = @()
            foreach ($src in @($doc.sources)) {
                if (-not $src.hotkeys) { continue }
                foreach ($prop in $src.hotkeys.PSObject.Properties) {
                    if ($prop.Name -match '^(OBSBasic\.SelectScene|libobs\.(show|hide)_scene_item)' -and @($prop.Value).Count -gt 0) {
                        $switchKeys += "$($src.name): $($prop.Name)"
                    }
                }
            }
            if ($switchKeys.Count -gt 0) {
                $alerts += "WARNING: OBS has $($switchKeys.Count) scene/source switching hotkey(s) -> $(($switchKeys | Select-Object -First 4) -join '; ')"
            }
            if ($scenes.Count -gt 1) {
                $names = ($scenes | ForEach-Object { $_.name } | Select-Object -First 6) -join ', '
                $alerts += "INFO: OBS scene collection has $($scenes.Count) scenes -> $names"
            }
        } catch {
            $alerts += 'INFO: Could not read the OBS scene collection'
        }
    }

    if ($profileDir) {
        $basicIni = Join-Path $base "basic\profiles\$profileDir\basic.ini"
        if (Test-Path -LiteralPath $basicIni) {
            try {
                $lines = @(Get-Content -LiteralPath $basicIni -ErrorAction Stop)
                foreach ($hk in @('OBSBasic.PauseRecording', 'OBSBasic.UnpauseRecording', 'OBSBasic.StopRecording')) {
                    $v = Get-IniValue -Lines $lines -Section 'Hotkeys' -Name $hk
                    if ($v -and $v -match '"key"') { $alerts += "WARNING: OBS hotkey bound to $($hk -replace '^OBSBasic\.', '') - the recording can be paused/stopped with a key" }
                }
            } catch {}
        }
    }

    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: OBS has no scripts and no scene-switch or pause hotkeys') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

# --- 13. Bloxstrap / Fishstrap: custom integrations and DLLs in Modifications -----------------
function Get-BootstrapperAlerts {
    $alerts = @()
    $found = 0
    foreach ($app in @('Bloxstrap', 'Fishstrap')) {
        $root = Join-Path $env:LOCALAPPDATA $app
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $found++
        $settings = Join-Path $root 'Settings.json'
        if (Test-Path -LiteralPath $settings) {
            try {
                $json = Get-Content -LiteralPath $settings -Raw -ErrorAction Stop | ConvertFrom-Json
                foreach ($ci in @($json.CustomIntegrations)) {
                    if (-not $ci) { continue }
                    $target = "$($ci.Location) $($ci.LaunchArgs)".Trim()
                    $kw = Get-MatchedCheatKeyword -Text $target
                    if ($kw) { $alerts += "FAILURE: $app custom integration [$kw] launches with Roblox -> $target" }
                    else { $alerts += "WARNING: $app custom integration '$($ci.Name)' launches with Roblox -> $target" }
                }
            } catch {
                $alerts += "INFO: Could not read $app settings"
            }
        }
        $mods = Join-Path $root 'Modifications'
        if (Test-Path -LiteralPath $mods) {
            Get-ChildItem -LiteralPath $mods -File -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '^(?i)\.(dll|exe|asi|sys)$' } |
                ForEach-Object { $alerts += "FAILURE: $app Modifications folder contains '$($_.Name)' - it gets copied next to Roblox at launch -> $($_.FullName)" }
        }
    }
    if ($found -eq 0) { return @('INFO: Bloxstrap / Fishstrap not installed') }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: No custom integrations or injected files in Bloxstrap/Fishstrap') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

# --- 14. Windows Security settings the rules ask players to show -------------------------------
function Get-SecuritySettingAlerts {
    $alerts = @()
    try {
        foreach ($fp in @(Get-NetFirewallProfile -ErrorAction Stop)) {
            if ([string]$fp.Enabled -eq 'False') { $alerts += "WARNING: Windows Firewall is off for the $($fp.Name) network profile" }
        }
    } catch { $alerts += 'INFO: Could not read firewall settings' }
    try {
        $bl = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' -Name VulnerableDriverBlocklistEnable -ErrorAction Stop
        if ([int]$bl -eq 0) { $alerts += 'WARNING: Microsoft Vulnerable Driver Blocklist is turned off (Core Isolation)' }
    } catch {}
    foreach ($hive in @('HKCU', 'HKLM')) {
        try {
            $n = Get-ItemPropertyValue -Path "${hive}:\Software\Microsoft\Windows Defender Security Center\Notifications" -Name DisableNotifications -ErrorAction Stop
            if ([int]$n -eq 1) { $alerts += 'WARNING: Windows Security notifications are turned off - detections would not pop up on the recording'; break }
        } catch {}
    }
    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: Firewall, driver blocklist and security notifications are on' }
    return @($alerts | Select-Object -Unique)
}

# --- 15. Extra launch traces: taskbar switch history, compatibility store, MuiCache, Recent ------
function Get-RegistryTraceAlerts {
    $alerts = @()
    $sources = @(
        @{ Label = 'Taskbar switch history';    Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched' },
        @{ Label = 'Compatibility Assistant';   Path = 'Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store' },
        @{ Label = 'Compatibility layers';      Path = 'Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' },
        @{ Label = 'MuiCache';                  Path = 'Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache' }
    )
    $total = 0
    foreach ($src in $sources) {
        $k = $null
        try { $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($src.Path) } catch {}
        if (-not $k) { continue }
        foreach ($vn in $k.GetValueNames()) {
            if (-not $vn) { continue }
            $total++
            $kw = Get-MatchedCheatKeyword -Text $vn
            if ($kw) { $alerts += "WARNING: $($src.Label) (no date) [$kw] -> $($vn -replace '\.(FriendlyAppName|ApplicationCompany)$', '')" }
        }
        $k.Close()
    }
    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
    $weekAgo = (Get-Date).AddDays(-7)
    Get-ChildItem -LiteralPath $recent -Filter '*.lnk' -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $weekAgo } |
        ForEach-Object {
            $total++
            $kw = Get-MatchedCheatKeyword -Text $_.BaseName
            if ($kw) { $alerts += "FAILURE: Recent files [$kw] opened $(Get-Date $_.LastWriteTime -Format 'yyyy-MM-dd HH:mm') -> $($_.BaseName)" }
        }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts += "SUCCESS: No cheat names in $total registry launch traces and recent files" }
    return @($alerts | Select-Object -Unique)
}

# --- 19. Cheat files, folders and shortcuts on disk (Desktop / Downloads / Documents, incl. OneDrive) --
function Get-CheatFileAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    $flagged = New-Object System.Collections.Generic.List[string]

    foreach ($folder in @(Get-CheatFolderHits | Sort-Object Length)) {
        if ($flagged | Where-Object { $folder.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }) { continue }
        $kw = Get-MatchedCheatKeyword -Text (Split-Path -Leaf $folder) -FolderName
        $alerts.Add("FAILURE: Cheat-named folder [$kw] -> $folder")
        $flagged.Add($folder)
    }

    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch {}
    $lnkDirs = @(Get-BsmmUserFolders Desktop) + @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'))
    foreach ($d in $lnkDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($lnk in @(Get-ChildItem -LiteralPath $d -Filter '*.lnk' -File -Recurse -Depth 2 -Force -ErrorAction SilentlyContinue)) {
            $target = ''
            if ($shell) { try { $target = [string]$shell.CreateShortcut($lnk.FullName).TargetPath } catch {} }
            # skip shortcuts that sit inside, or (Start Menu only) point into, a folder already reported
            $inFlagged = @($flagged | Where-Object { $lnk.FullName.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            if (-not $inFlagged -and $d -like '*Start Menu*' -and $target) {
                $inFlagged = @($flagged | Where-Object { $target.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            }
            if ($inFlagged) { continue }
            $kw = Get-MatchedCheatKeyword -Text $lnk.BaseName
            if (-not $kw -and $target) { $kw = Get-MatchedCheatKeyword -Text $target }
            if ($kw) { $alerts.Add("FAILURE: Shortcut [$kw] '$($lnk.BaseName)' -> $target") }
        }
    }

    $docs = @(Get-BsmmUserFolders Documents)
    $unsignedInDocs = 0
    foreach ($d in (@(Get-BsmmUserFolders Desktop) + @(Get-BsmmUserFolders Downloads) + $docs)) {
        $files = @(Get-ChildItem -LiteralPath $d -File -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^(?i)\.(exe|dll|bat|cmd|ps1|lua|luau|ahk|zip|rar|7z)$' } | Select-Object -First 4000)
        foreach ($f in $files) {
            if ($flagged | Where-Object { $f.FullName.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }) { continue }
            $kw = Get-MatchedCheatKeyword -Text $f.FullName.Substring($d.Length)
            if ($kw) {
                $alerts.Add("FAILURE: Cheat-named file [$kw] -> $($f.FullName)")
                $flagged.Add($f.DirectoryName)
                continue
            }
            # Documents is not an install location: unsigned programs there are usually hidden on purpose
            if ($docs -contains $d -and $f.Extension -match '^(?i)\.exe$' -and $unsignedInDocs -lt 15) {
                $st = Get-CachedSignatureStatus -Path $f.FullName
                if ($st -ne 'Valid') {
                    $unsignedInDocs++
                    $alerts.Add("WARNING: Unsigned program hidden in Documents ($st) -> $($f.FullName)")
                }
            }
        }
    }

    if ($alerts.Count -eq 0) { return @('SUCCESS: No cheat-named files, folders or shortcuts found') }
    $all = @($alerts | Select-Object -Unique)
    $userPat = '\\(OneDrive\\)?(Desktop|Documents|Downloads)\\'
    $out = @($all | Where-Object { $_ -match $userPat }) + @($all | Where-Object { $_ -match 'Shortcut' -and $_ -notmatch $userPat }) +
           @($all | Where-Object { $_ -notmatch $userPat -and $_ -notmatch 'Shortcut' })
    if ($out.Count -gt 60) { $out = @($out[0..59]) + @("INFO: ... and $($out.Count - 60) more") }
    return $out
}

# --- 16. Defender overrides in the registry (incl. Group Policy keys Get-MpPreference can miss) --
function Get-DefenderRegistryOverrideAlerts {
    $alerts = @()
    $denied = 0
    $actionNames = @{ 6 = 'Allow'; 9 = 'No action' }
    foreach ($root in @('SOFTWARE\Microsoft\Windows Defender', 'SOFTWARE\Policies\Microsoft\Windows Defender')) {
        foreach ($sub in @('ThreatIDDefaultAction', 'ThreatSeverityDefaultAction', 'ThreatTypeDefaultAction')) {
            try {
                $k = Open-LocalMachineRegistryKey -SubKeyPath "$root\Threats\$sub"
                if (-not $k) { continue }
                foreach ($vn in $k.GetValueNames()) {
                    if (-not $vn) { continue }
                    $v = 0; try { $v = [int]$k.GetValue($vn) } catch {}
                    if ($actionNames.ContainsKey($v)) {
                        $alerts += "FAILURE: Defender told to '$($actionNames[$v])' $($sub -replace 'DefaultAction', '') $vn -> HKLM\$root\Threats\$sub"
                    }
                }
                $k.Close()
            } catch [System.Security.SecurityException] { $denied++ } catch [System.UnauthorizedAccessException] { $denied++ } catch {}
        }
        foreach ($sub in @('TemporaryPaths', 'IpAddresses')) {
            try {
                $k = Open-LocalMachineRegistryKey -SubKeyPath "$root\Exclusions\$sub"
                if (-not $k) { continue }
                foreach ($vn in $k.GetValueNames()) {
                    if ($vn) { $alerts += "WARNING: Defender $sub exclusion -> $vn" }
                }
                $k.Close()
            } catch [System.Security.SecurityException] { $denied++ } catch [System.UnauthorizedAccessException] { $denied++ } catch {}
        }
    }
    if ($alerts.Count -eq 0) {
        if ($denied -gt 0) { return @('INFO: Some Defender registry keys could not be read (run as administrator)') }
        return @('SUCCESS: No Defender "allow" overrides or hidden exclusions in the registry')
    }
    return @($alerts | Select-Object -Unique)
}

# --- 17. Hidden drive letters: subst / DefineDosDevice / permanent DOS device mappings ------------
function Initialize-BsmmDosDevice {
    if ('BSMM.DosDevice' -as [type]) { return $true }
    try {
        Add-Type -Namespace BSMM -Name DosDevice -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern uint QueryDosDevice(string lpDeviceName, System.Text.StringBuilder lpTargetPath, int ucchMax);
'@ -ErrorAction Stop
        return $true
    } catch { return $false }
}

# Maps \Device\HarddiskVolumeN to its drive letter, so paths on D:, E: ... resolve correctly.
function Get-BsmmVolumeMap {
    $map = @{}
    if (-not (Initialize-BsmmDosDevice)) { return $map }
    foreach ($letter in [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ') {
        $sb = New-Object System.Text.StringBuilder 1024
        if ([BSMM.DosDevice]::QueryDosDevice("${letter}:", $sb, 1024) -ne 0) {
            $t = $sb.ToString()
            if ($t -match '^\\Device\\HarddiskVolume\d+$') { $map[$t] = "${letter}:" }
        }
    }
    return $map
}

function Get-HiddenDriveLetterAlerts {
    $alerts = @()
    try {
        if (-not (Initialize-BsmmDosDevice)) { throw 'QueryDosDevice unavailable' }
        foreach ($letter in [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ') {
            $sb = New-Object System.Text.StringBuilder 1024
            if ([BSMM.DosDevice]::QueryDosDevice("${letter}:", $sb, 1024) -eq 0) { continue }
            $target = $sb.ToString()
            if ($target -like '\??\*') {
                $alerts += "WARNING: Drive ${letter}: is a 'subst' shortcut to a folder -> $($target.Substring(4))"
            } elseif ($target -match '(?i)veracrypt|truecrypt|imdisk|osfmount|ramdisk') {
                $alerts += "WARNING: Drive ${letter}: is an encrypted/virtual volume -> $target"
            }
        }
    } catch {
        $alerts += 'INFO: Could not list drive letter targets'
    }
    try {
        $k = Open-LocalMachineRegistryKey -SubKeyPath 'SYSTEM\CurrentControlSet\Control\Session Manager\DOS Devices'
        if ($k) {
            foreach ($vn in $k.GetValueNames()) {
                if ($vn -match '^[A-Za-z]:$') { $alerts += "FAILURE: Permanent hidden drive mapping $vn -> $($k.GetValue($vn))" }
            }
            $k.Close()
        }
    } catch {}
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts = @('SUCCESS: No subst or hidden drive letters (drives created from a non-admin window are not visible here)') + $alerts
    }
    return @($alerts | Select-Object -Unique)
}

# --- 18. Programs in the BAM run history that ran this session and are now deleted --------------
function Get-BamDeletedAlerts {
    $alerts = @()
    $logon = Get-LogonTime
    $volumes = Get-BsmmVolumeMap
    foreach ($e in @(Get-BamEntries | Where-Object { $_.Time -and $_.Time -ge $logon })) {
        $path = $null
        if ($e.Raw -match '^(\\Device\\HarddiskVolume\d+)(\\.+)$' -and $volumes.ContainsKey($matches[1])) { $path = $volumes[$matches[1]] + $matches[2] }
        elseif ($e.Raw -match '^[A-Za-z]:\\') { $path = $e.Raw }
        if (-not $path) { continue }
        if ((Test-UntrustedUserProgramPath -Path $path) -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $alerts += "WARNING: Ran this session ($(Get-Date $e.Time -Format 'HH:mm')) and the file is now gone -> $path"
        }
    }
    if ($alerts.Count -eq 0) { $alerts += 'SUCCESS: Nothing that ran this session from Downloads/Desktop/Temp has been deleted' }
    return @($alerts | Select-Object -Unique)
}

# =============================================================================
#   Trust score and Discord report
# =============================================================================

function Get-BsmmTrustScore {
    param([array]$Results, [int]$LiveFail = 0, [int]$LiveWarn = 0)
    $w = $script:TrustWeights
    $fail = @($Results | Where-Object { $_.Summary.Status -eq 'FAIL' }).Count
    $warn = @($Results | Where-Object { $_.Summary.Status -eq 'WARN' }).Count
    $score = 100
    $score -= [Math]::Min($w.FailCap, $fail * $w.FailSection)
    $score -= [Math]::Min($w.WarnCap, $warn * $w.WarnSection)
    $admin = $false; try { $admin = Test-Admin } catch {}
    if (-not $admin) { $score -= $w.NotAdmin }
    $score -= [Math]::Min($w.LiveCap, ($LiveFail * $w.LiveFail) + ($LiveWarn * $w.LiveWarn))
    $score = [int][Math]::Max(0, [Math]::Min(100, $score))

    $label = 'TRUSTED'; $token = 'Pass'; $color = 0x34D399
    if ($score -lt 40)     { $label = 'HIGH RISK';  $token = 'Fail'; $color = 0xFB4D6D }
    elseif ($score -lt 70) { $label = 'SUSPICIOUS'; $token = 'Fail'; $color = 0xF97316 }
    elseif ($score -lt 90) { $label = 'REVIEW';     $token = 'Warn'; $color = 0xFBBF24 }
    return @{ Score = $score; Label = $label; Token = $token; Color = $color; Fail = $fail; Warn = $warn; Admin = $admin }
}

# Removes personal details before anything leaves the PC.
function Protect-BsmmText {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text
    if ($env:USERPROFILE) { $t = [regex]::Replace($t, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', 'IgnoreCase') }
    $t = [regex]::Replace($t, '(?i)\b([A-Z]:\\Users\\)(?!Public\\|Default\\)[^\\/:*?"<>|\r\n]+', '$1<user>')
    $t = [regex]::Replace($t, '(?i)(\\Device\\HarddiskVolume\d+\\Users\\)[^\\\r\n]+', '$1<user>')
    if ($env:USERNAME -and $env:USERNAME.Length -ge 3) { $t = [regex]::Replace($t, '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($env:USERNAME) + '(?![A-Za-z0-9])', '<user>') }
    if ($env:COMPUTERNAME -and $env:COMPUTERNAME.Length -ge 3) { $t = [regex]::Replace($t, '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($env:COMPUTERNAME) + '(?![A-Za-z0-9])', '<pc>') }
    $t = [regex]::Replace($t, '(?i)(https?://[^\s?#]+)[?#]\S*', '$1')
    return $t.Replace('`', "'")
}

# Lines left out of the Discord report because they describe the player's personal activity
# rather than anything suspicious (the full list of apps they ran, USB device names, archive names).
function Test-BsmmReportLine {
    param([string]$Section, [string]$Line)
    if ($Section -eq 'Session' -and $Line -match '^INFO: (Ran |\.\.\. and)') { return $false }
    if ($Section -eq 'USB History' -and $Line -like 'INFO*') { return $false }
    if ($Section -eq 'Download Origins' -and $Line -like 'INFO*') { return $false }
    return $true
}

function Limit-BsmmText {
    param([string]$Text, [int]$Max)
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, [Math]::Max(0, $Max - 3)) + '...'
}

function Invoke-BsmmHttp {
    param([string]$Method, [string]$Url, [byte[]]$Body, [string]$ContentType, [hashtable]$Headers = @{})
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = $Method
            $req.ContentType = $ContentType
            foreach ($h in $Headers.Keys) { $req.Headers[$h] = [string]$Headers[$h] }
            $req.UserAgent = "BSMM-AntiCheat/$($script:Brand.Version)"
            $req.Timeout = 10000
            $req.ReadWriteTimeout = 10000
            $req.ContentLength = $Body.Length
            $stream = $req.GetRequestStream()
            $stream.Write($Body, 0, $Body.Length)
            $stream.Close()
            $resp = $req.GetResponse()
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $text = $reader.ReadToEnd()
            $reader.Close(); $resp.Close()
            return @{ Ok = $true; Body = $text }
        } catch [System.Net.WebException] {
            $code = 0; $retry = 2
            try { $code = [int]$_.Exception.Response.StatusCode } catch {}
            try { $ra = $_.Exception.Response.Headers['Retry-After']; if ($ra) { $retry = [Math]::Min(5, [Math]::Ceiling([double]$ra)) } } catch {}
            if ($code -eq 429 -and $attempt -eq 1) { Start-Sleep -Seconds $retry; continue }
            return @{ Ok = $false; Code = $code; Error = $_.Exception.Message }
        } catch {
            return @{ Ok = $false; Code = 0; Error = $_.Exception.Message }
        }
    }
    return @{ Ok = $false; Code = 429; Error = 'rate limited' }
}

function Test-BsmmRelay {
    $url = [string]$script:Report.RelayUrl
    return ($url -match '^https://[^\s/]+' -or $url -match '^http://(127\.0\.0\.1|localhost)(:\d+)?') -and $url -notmatch 'YOUR-SUBDOMAIN'
}

$script:RelayKeys = @{}

# Posts (or edits, with -MessageId) a report message through the relay. Returns the message id, or $null on failure.
function Send-BsmmWebhook {
    param([hashtable]$Payload, [string]$FileName = '', [string]$FileText = '', [string]$MessageId = '')
    if (-not (Test-BsmmRelay)) { return $null }
    $url = ([string]$script:Report.RelayUrl).TrimEnd('/')
    $Payload['allowed_mentions'] = @{ parse = @() }    # never ping anyone
    $json = ConvertTo-Json -InputObject $Payload -Depth 10 -Compress
    $enc = New-Object System.Text.UTF8Encoding($false)

    if ($MessageId) {
        $key = [string]$script:RelayKeys[$MessageId]
        $r = Invoke-BsmmHttp -Method 'PATCH' -Url "$url/report/$MessageId" -Body $enc.GetBytes($json) -ContentType 'application/json' -Headers @{ 'X-Edit-Key' = $key }
        if ($r.Ok) { return $MessageId }
        return $null
    }

    if ($FileName -and $FileText) {
        $boundary = 'BSMM' + [guid]::NewGuid().ToString('N')
        $ms = New-Object System.IO.MemoryStream
        $parts = @(
            "--$boundary`r`nContent-Disposition: form-data; name=`"payload_json`"`r`nContent-Type: application/json`r`n`r`n$json`r`n",
            "--$boundary`r`nContent-Disposition: form-data; name=`"files[0]`"; filename=`"$FileName`"`r`nContent-Type: text/plain; charset=utf-8`r`n`r`n",
            $FileText,
            "`r`n--$boundary--`r`n"
        )
        foreach ($part in $parts) { $b = $enc.GetBytes($part); $ms.Write($b, 0, $b.Length) }
        $r = Invoke-BsmmHttp -Method 'POST' -Url "$url/report" -Body $ms.ToArray() -ContentType "multipart/form-data; boundary=$boundary"
    } else {
        $r = Invoke-BsmmHttp -Method 'POST' -Url "$url/report" -Body $enc.GetBytes($json) -ContentType 'application/json'
    }
    if (-not $r.Ok) { return $null }
    try {
        $resp = $r.Body | ConvertFrom-Json
        if ($resp.key) { $script:RelayKeys[[string]$resp.id] = [string]$resp.key }
        return [string]$resp.id
    } catch { return 'sent' }
}

function Get-BsmmSystemFacts {
    $facts = [ordered]@{}
    try {
        $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $facts['Windows'] = "$($cv.ProductName) build $($cv.CurrentBuild).$($cv.UBR)"
    } catch {}
    $boot = Get-BootTime
    if ($boot) {
        $up = (Get-Date) - $boot
        $facts['Uptime'] = '{0}h {1:00}m' -f [int][Math]::Floor($up.TotalHours), $up.Minutes
    }
    try {
        $v = Get-RobloxVersionInfo
        if ($v.Installed) {
            $state = 'not running'; if ($v.IsRunning) { $state = 'running' }
            $facts['Roblox'] = "$($v.VersionHash) ($state)"
        } else { $facts['Roblox'] = 'not found' }
    } catch {}
    $admin = $false; try { $admin = Test-Admin } catch {}
    $facts['Admin'] = $(if ($admin) { 'Yes' } else { 'NO - checks incomplete' })
    return $facts
}

function Get-BsmmReportHeader {
    $player = $script:PlayerName; if (-not $player) { $player = '(not given)' }
    return "Report $($script:ReportId)  |  Player $player  |  BSMM $($script:Brand.Product) v$($script:Brand.Version)"
}

# Full anonymised text log of step 1 (attached to the Discord message).
function Get-BsmmSystemReportText {
    param([array]$Results, $Trust, [int]$Seconds)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine((Get-BsmmReportHeader))
    [void]$sb.AppendLine("Generated $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) UTC  |  scan took ${Seconds}s")
    [void]$sb.AppendLine("Trust score: $($Trust.Score)/100 ($($Trust.Label))  |  $($Trust.Fail) failed, $($Trust.Warn) to review, $($Results.Count) checks")
    foreach ($kv in (Get-BsmmSystemFacts).GetEnumerator()) { [void]$sb.AppendLine("$($kv.Key): $($kv.Value)") }
    [void]$sb.AppendLine('')
    foreach ($r in $Results) {
        [void]$sb.AppendLine(('[{0}] {1}' -f $r.Summary.Status, $r.Name))
        foreach ($l in @($r.Lines)) {
            if (-not (Test-BsmmReportLine -Section $r.Name -Line $l)) { continue }
            [void]$sb.AppendLine('    ' + (Protect-BsmmText (($l -replace "`r?`n", ' | ') -replace '\s+', ' ')))
        }
    }
    return $sb.ToString()
}

function Send-BsmmSystemReport {
    param([array]$Results, $Trust, [int]$Seconds)
    $facts = Get-BsmmSystemFacts
    $player = $script:PlayerName; if (-not $player) { $player = 'not given' }

    $fields = @()
    $fields += @{ name = 'Result'; value = "$($Trust.Fail) failed / $($Trust.Warn) to review / $($Results.Count) checks"; inline = $true }
    foreach ($kv in $facts.GetEnumerator()) { $fields += @{ name = $kv.Key; value = (Limit-BsmmText (Protect-BsmmText ([string]$kv.Value)) 1000); inline = $true } }
    $failNames = @($Results | Where-Object { $_.Summary.Status -eq 'FAIL' } | ForEach-Object { $_.Name })
    $warnNames = @($Results | Where-Object { $_.Summary.Status -eq 'WARN' } | ForEach-Object { $_.Name })
    if ($failNames.Count -gt 0) { $fields += @{ name = 'Failed checks'; value = (Limit-BsmmText ($failNames -join ', ') 1000); inline = $false } }
    if ($warnNames.Count -gt 0) { $fields += @{ name = 'Needs review'; value = (Limit-BsmmText ($warnNames -join ', ') 1000); inline = $false } }

    $findings = New-Object System.Collections.Generic.List[string]
    foreach ($status in @('FAIL', 'WARN')) {
        foreach ($r in @($Results | Where-Object { $_.Summary.Status -eq $status })) {
            foreach ($l in @($r.Lines)) {
                if ($l -notlike 'FAILURE*' -and $l -notlike 'WARNING*') { continue }
                $tag = 'WARN'; if ($l -like 'FAILURE*') { $tag = 'FAIL' }
                $msg = ($l -replace '^(FAILURE|WARNING):\s*', '') -replace "`r?`n", ' | ' -replace '\s+', ' '
                $findings.Add("$tag  $($r.Name): $(Limit-BsmmText (Protect-BsmmText $msg) 220)")
            }
        }
    }
    $desc = "**Trust score: $($Trust.Score)/100 - $($Trust.Label)**`nReport ``$($script:ReportId)`` - Player ``$(Protect-BsmmText $player)```nMatch this report ID with the one on the recording."
    $embeds = @(@{
        title = "$($script:Brand.Name) $($script:Brand.Product) - System check"
        description = $desc
        color = $Trust.Color
        fields = $fields
        footer = @{ text = "BSMM v$($script:Brand.Version) - scan took ${Seconds}s" }
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
    })
    if ($findings.Count -gt 0) {
        $body = ''
        $shown = 0
        foreach ($f in $findings) {
            if (($body.Length + $f.Length + 1) -gt 3600) { break }
            $body += $f + "`n"; $shown++
        }
        if ($shown -lt $findings.Count) { $body += "... $($findings.Count - $shown) more in the attached log`n" }
        $embeds += @{ title = "Findings ($($findings.Count))"; description = "``````text`n$body``````"; color = $Trust.Color }
    }

    $file = ''; $text = ''
    if ($script:Report.AttachFullLog) {
        $file = "$($script:ReportId)-system-check.txt"
        $text = Get-BsmmSystemReportText -Results $Results -Trust $Trust -Seconds $Seconds
    }
    return (Send-BsmmWebhook -Payload @{ username = "$($script:Brand.Name) Anti-Cheat"; embeds = $embeds } -FileName $file -FileText $text)
}

# One message per match that is edited while the live monitor runs (a heartbeat staff can watch).
function Get-BsmmLivePayload {
    param([datetime]$Since, [string]$State, $Trust)
    $elapsed = (Get-Date) - $Since
    $c = $script:MonitorAlertCounts
    $recent = @($script:MonitorLog | Where-Object { $_ -match '\[(FAIL|WARN)\]' } | Select-Object -Last 12)
    $body = ''
    foreach ($l in $recent) { $body += (Limit-BsmmText (Protect-BsmmText $l) 200) + "`n" }
    if (-not $body) { $body = "No suspicious activity so far.`n" }
    $player = $script:PlayerName; if (-not $player) { $player = 'not given' }
    $color = $Trust.Color
    if ($State -eq 'RUNNING') { $color = 0x7AA2F7 }
    return @{
        username = "$($script:Brand.Name) Anti-Cheat"
        embeds = @(@{
            title = "$($script:Brand.Name) $($script:Brand.Product) - Live monitor ($State)"
            description = "Report ``$($script:ReportId)`` - Player ``$(Protect-BsmmText $player)```n**Trust score: $($Trust.Score)/100 - $($Trust.Label)**`n``````text`n$body``````"
            color = $color
            fields = @(
                @{ name = 'Monitoring for'; value = ('{0:hh\:mm\:ss}' -f $elapsed); inline = $true },
                @{ name = 'Alerts'; value = "$($c.FAIL) fail / $($c.WARN) warn / $($c.INFO) info"; inline = $true }
            )
            footer = @{ text = "Last update - if this stops updating before the match ends, the window was closed" }
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
        })
    }
}

$script:ProgressWidth = 28

# "  ######......   54%  Checking Defender exclusions..."  redrawn in place
function Write-CheckProgress {
    param([int]$Done, [int]$Total, [string]$Text)

    $percent = 0
    if ($Total -gt 0) { $percent = [int][math]::Floor(($Done / $Total) * 100) }
    $cells = $script:ProgressWidth
    $filled = [int][math]::Floor(($percent / 100) * $cells)
    $label = '{0,3}%' -f $percent
    $width = $script:ConsoleWidth
    try { if ([Console]::WindowWidth -gt 1) { $width = [Console]::WindowWidth } } catch {}
    $fixed = 2 + $cells + 2 + $label.Length + 2
    $maxText = [Math]::Max(8, $width - 1 - $fixed)
    if ($Text.Length -gt $maxText) { $Text = $Text.Substring(0, $maxText - 3) + '...' }
    $padCount = [Math]::Max(0, $width - 1 - $fixed - $Text.Length)

    if ($script:UseAnsi) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append("`r  ")
        for ($i = 0; $i -lt $cells; $i++) {
            if ($i -lt $filled) {
                [void]$sb.Append((Get-BsmmFg (Get-BsmmGradient ($i / [double]($cells - 1))))).Append($script:G.Block)
            } else {
                [void]$sb.Append($script:AnsiFg['Line']).Append($script:G.Shade)
            }
        }
        [void]$sb.Append($script:AnsiReset).Append('  ')
        [void]$sb.Append("$script:Esc[1m").Append($script:AnsiFg['Text']).Append($label).Append($script:AnsiReset).Append('  ')
        [void]$sb.Append($script:AnsiFg['Muted']).Append($Text).Append($script:AnsiReset).Append(' ' * $padCount)
        Write-Host $sb.ToString() -NoNewline
    } else {
        Write-Host "`r  " -NoNewline
        Out-Seg ($script:G.Block * $filled) -Fg 'Brand1' -NoNewline
        Out-Seg ($script:G.Shade * ($cells - $filled)) -Fg 'Line' -NoNewline
        Out-Seg ('  ' + $label + '  ') -Fg 'Text' -NoNewline
        Out-Seg ($Text + (' ' * $padCount)) -Fg 'Muted' -NoNewline
    }
}

function Write-ResultCell {
    param($Result, [int]$NameWidth = 30, [switch]$NoNewline)
    $name = [string]$Result.Name
    if ($name.Length -gt $NameWidth) { $name = $name.Substring(0, $NameWidth - 3) + '...' }
    $status = $Result.Summary.Status
    Out-Badge $status -NoNewline
    $nameTok = 'Body'; if ($status -eq 'FAIL' -or $status -eq 'WARN') { $nameTok = 'Text' }
    Out-Seg ('  ' + $name.PadRight($NameWidth)) -Fg $nameTok -Bold:($status -eq 'FAIL') -NoNewline:$NoNewline
}

# The result grid, verdict panel and per-section details shown at the end of step 1.
function Show-SystemCheckSummary {
    param([array]$Results, [int]$Seconds)

    $total = $Results.Count
    $fail = @($Results | Where-Object { $_.Summary.Status -eq 'FAIL' }).Count
    $warn = @($Results | Where-Object { $_.Summary.Status -eq 'WARN' }).Count
    $clean = $total - $fail - $warn

    Out-Seg ''
    Out-Heading 'Results' ("$total checks $($script:G.Mid) ${Seconds}s")
    Out-Seg ''
    $nameW = 30
    $cellW = 6 + 2 + $nameW
    if ($script:UiWidth -ge ($cellW * 2 + 4)) {
        $half = [int][Math]::Ceiling($total / 2)
        for ($i = 0; $i -lt $half; $i++) {
            Out-Seg '  ' -NoNewline
            Write-ResultCell $Results[$i] -NameWidth $nameW -NoNewline
            if ($i + $half -lt $total) {
                Out-Seg '    ' -NoNewline
                Write-ResultCell $Results[$i + $half] -NameWidth $nameW
            } else {
                Out-Seg ''
            }
        }
    } else {
        foreach ($r in $Results) { Out-Seg '  ' -NoNewline; Write-ResultCell $r -NameWidth $nameW }
    }

    # Verdict panel
    $trustNow = Get-BsmmTrustScore -Results $Results
    $vText = $trustNow.Label; $vTok = $trustNow.Token
    $W = $script:UiWidth
    $inner = $W - 4
    $summaryText = "$fail failed  $($script:G.Mid)  $warn to review  $($script:G.Mid)  $clean clean"

    Out-Seg ''
    Out-Seg ('  ' + $script:G.TL + ($script:G.H * ($W - 2)) + $script:G.TR) -Fg $vTok
    # line 1: big verdict chip + counts
    Out-Seg ('  ' + $script:G.V + ' ') -Fg $vTok -NoNewline
    $chip = " $vText "
    if ($script:UseAnsi) { Out-Seg $chip -Fg 'Ink' -Bg $vTok -Bold -NoNewline } else { $chip = "[$vText]"; Out-Seg $chip -Fg $vTok -NoNewline }
    $rest = '   ' + $summaryText
    if (($chip.Length + $rest.Length) -gt $inner) { $rest = $rest.Substring(0, [Math]::Max(0, $inner - $chip.Length)) }
    Out-Seg $rest.PadRight($inner - $chip.Length) -Fg 'Body' -NoNewline
    Out-Seg (' ' + $script:G.V) -Fg $vTok
    # line 2: stacked bar of fail / warn / clean
    $cells = [Math]::Min(48, $inner - 14)
    $fc = 0; $wc = 0
    if ($total -gt 0) {
        $fc = [int][Math]::Round($cells * $fail / $total); if ($fail -gt 0 -and $fc -lt 1) { $fc = 1 }
        $wc = [int][Math]::Round($cells * $warn / $total); if ($warn -gt 0 -and $wc -lt 1) { $wc = 1 }
    }
    $pc = [Math]::Max(0, $cells - $fc - $wc)
    $trust = Get-BsmmTrustScore -Results $Results
    $pctText = "  TRUST $($trust.Score)/100"
    Out-Seg ('  ' + $script:G.V + ' ') -Fg $vTok -NoNewline
    Out-Seg ($script:G.Block * $fc) -Fg 'Fail' -NoNewline
    Out-Seg ($script:G.Block * $wc) -Fg 'Warn' -NoNewline
    Out-Seg ($script:G.Block * $pc) -Fg 'Pass' -NoNewline
    Out-Seg $pctText.PadRight($inner - $cells) -Fg $trust.Token -Bold -NoNewline
    Out-Seg (' ' + $script:G.V) -Fg $vTok
    Out-Seg ('  ' + $script:G.BL + ($script:G.H * ($W - 2)) + $script:G.BR) -Fg $vTok

    # Details: failures first, then warnings, then anything with extra context
    $ordered = @($Results | Where-Object { $_.Summary.Status -eq 'FAIL' }) +
               @($Results | Where-Object { $_.Summary.Status -eq 'WARN' }) +
               @($Results | Where-Object { $_.Summary.Status -eq 'PASS' -and $_.Summary.Info -gt 0 })
    if ($ordered.Count -gt 0) {
        Out-Seg ''
        Out-Heading 'Details'
        foreach ($r in $ordered) { Write-Section $r.Name $r.Lines }
    }
}

$script:SystemChecks = @(
    @{ Name = 'PowerShell Modules';           Caption = 'Loading PowerShell modules';         Run = { Initialize-BsmmModules } },
    @{ Name = 'CPU & GPU';                    Caption = 'Reading CPU and GPU';                Run = { Get-CpuGpuAlerts } },
    @{ Name = 'Roblox Client Version';        Caption = 'Checking Roblox version';            Run = { Get-RobloxVersionAlerts } },
    @{ Name = 'Session';                      Caption = 'Reading logon time and run history'; Run = { Get-SessionSummaryAlerts } },
    @{ Name = 'Session Environment';          Caption = 'Checking for virtual machines and remote sessions'; Run = { Get-SessionEnvironmentAlerts } },
    @{ Name = 'UAC & Prompts';                Caption = 'Checking UAC level';                 Run = { Get-UacAlerts } },
    @{ Name = 'Window Animations';            Caption = 'Checking window animations';         Run = { Get-AnimationAlerts } },
    @{ Name = 'Displays & Desktops';          Caption = 'Counting displays and desktops';     Run = { Get-DisplayDesktopAlerts } },
    @{ Name = 'Recording Software (OBS)';     Caption = 'Checking OBS scripts and hotkeys';   Run = { Get-ObsAlerts } },
    @{ Name = 'Windows Defender';             Caption = 'Checking Windows Defender';          Run = { Get-DefenderStep1Alerts } },
    @{ Name = 'Defender Exclusions';          Caption = 'Checking Defender exclusions';       Run = { Get-ExclusionAlerts } },
    @{ Name = 'Allowed Threats';              Caption = 'Checking allowed threats';           Run = { Get-AllowedThreatAlerts } },
    @{ Name = 'Defender Registry Overrides';  Caption = 'Reading Defender registry overrides'; Run = { Get-DefenderRegistryOverrideAlerts } },
    @{ Name = 'Active Defender Threats';      Caption = 'Checking active Defender threats';   Run = { Get-ActiveDefenderThreatAlerts } },
    @{ Name = 'Defender History';             Caption = 'Reading Defender detection history'; Run = { Get-DefenderHistoryAlerts } },
    @{ Name = 'Windows Security Settings';    Caption = 'Checking firewall and driver blocklist'; Run = { Get-SecuritySettingAlerts } },
    @{ Name = 'Clarity / Defender Integrity'; Caption = 'Checking Defender integrity';        Run = { Get-ClarityDetectionAlerts } },
    @{ Name = 'Memory Integrity (HVCI)';      Caption = 'Checking Memory Integrity';          Run = { Get-MemoryIntegrityAlerts } },
    @{ Name = 'CLR Profiler Hijack';          Caption = 'Checking .NET profiler environment'; Run = { Get-ClrHijackAlerts } },
    @{ Name = 'Native Syscall Hooks';         Caption = 'Auditing NTDLL syscall stubs';       Run = { Get-NtdllSyscallIntegrityAlerts } },
    @{ Name = 'OBS & App Tamper';             Caption = 'Auditing browsers, streaming & apps'; Run = { Get-StreamingProcessIntegrityAlerts } },
    @{ Name = 'Transparent Overlays';         Caption = 'Scanning topmost click-through windows'; Run = { Get-TransparentOverlayAlerts } },
    @{ Name = 'Process Explorer & Taskmgr';   Caption = 'Auditing Process Explorer & Taskmgr'; Run = { Get-TaskManagerIntegrityAlerts } },
    @{ Name = 'Test Signing';                 Caption = 'Checking boot configuration';        Run = { Get-TestSigningAlerts } },
    @{ Name = 'Kernel Drivers';               Caption = 'Verifying kernel drivers';           Run = { Get-SuspiciousDriverAlerts } },

    @{ Name = 'Vulnerable Drivers';           Caption = 'Checking for vulnerable drivers';    Run = { Get-VulnerableDriverAlerts } },
    @{ Name = 'Driver Install Log';           Caption = 'Reading driver install and block log';  Run = { Get-DriverInstallAlerts } },
    @{ Name = 'Input & DMA Devices';          Caption = 'Checking input drivers and PCIe';    Run = { Get-InputAndDmaDeviceAlerts } },
    @{ Name = 'Macro & Auto-Clickers';        Caption = 'Checking for macro tools';           Run = { Get-MacroToolAlerts } },
    @{ Name = 'PowerShell Module Integrity';  Caption = 'Verifying PowerShell modules';       Run = { @(Get-PowerShellHostIntegrityAlerts; Get-PowerShellModuleIntegrityAlerts) | Select-Object -Unique } },
    @{ Name = 'PowerShell Binary Integrity';  Caption = 'Verifying PowerShell binaries';      Run = { Get-PowerShellBinaryIntegrityAlerts } },
    @{ Name = 'Root Certificates';            Caption = 'Checking root certificates';         Run = { Get-RootCertificateAlerts } },
    @{ Name = 'Process Scan';                 Caption = 'Scanning processes';                 Run = { @(Get-ProcessScanAlerts; Get-UnsignedUserProgramAlerts) | Select-Object -Unique } },
    @{ Name = 'External / Overlay';           Caption = 'Scanning external / overlay activity'; Run = { Get-ExternalCheatHits } },
    @{ Name = 'Roblox Modules';               Caption = 'Checking modules loaded in Roblox';  Run = { Get-RobloxModuleAlerts } },
    @{ Name = 'Roblox Memory Integrity';      Caption = 'Checking Roblox memory integrity';   Run = { Get-RobloxMemoryIntegrityAlerts } },
    @{ Name = 'Roblox Folder Integrity';      Caption = 'Checking Roblox install folder';     Run = { Get-RobloxFolderAlerts } },
    @{ Name = 'Roblox Named Pipes';           Caption = 'Auditing named pipes';               Run = { Get-RobloxNamedPipeAlerts } },
    @{ Name = 'FastFlags (ClientAppSettings)';Caption = 'Auditing FastFlags';                 Run = { Get-FastFlagsAlerts } },
    @{ Name = 'Bloxstrap / Fishstrap';        Caption = 'Checking Bloxstrap integrations';    Run = { Get-BootstrapperAlerts } },
    @{ Name = 'Anti-Bypass & Network';        Caption = 'Checking network and hosts bypass';  Run = { Get-AntiBypassNetworkAlerts } },
    @{ Name = 'KeyAuth';                      Caption = 'Checking KeyAuth';                   Run = { Get-KeyAuthAlerts } },
    @{ Name = 'Suspicious Files';             Caption = 'Scanning for high-entropy binaries'; Run = { Get-SuspiciousHighEntropyFileAlerts } },
    @{ Name = 'Cheat Files & Shortcuts';      Caption = 'Searching for cheat files and shortcuts'; Run = { Get-CheatFileAlerts } },
    @{ Name = 'Download Origins';             Caption = 'Checking where downloads came from'; Run = { Get-DownloadOriginAlerts } },
    @{ Name = 'Windhawk';                     Caption = 'Checking Windhawk';                  Run = { Get-WindhawkStep1Alerts } },
    @{ Name = 'Registry Markers';             Caption = 'Checking registry markers';          Run = { Get-RegistryMarkerAlerts } },
    @{ Name = 'NVIDIA ShadowPlay';            Caption = 'Checking NVIDIA ShadowPlay';         Run = { Get-NvidiaShadowPlayFtsAlerts } },
    @{ Name = 'Execution History (BAM/DAM)';  Caption = 'Reading execution history';          Run = { Get-BamHistoryAlerts } },
    @{ Name = 'BAM Service';                  Caption = 'Checking BAM service';               Run = { Get-BamServiceAlerts } },

    @{ Name = 'Prefetch Health';              Caption = 'Checking prefetch';                  Run = { Get-PrefetchHealthAlerts } },
    @{ Name = 'Artifact Cross-Check';         Caption = 'Cross-checking BAM vs prefetch';     Run = { Get-ArtifactCrossCheckAlerts } },
    @{ Name = 'Program Launch Traces';        Caption = 'Reading Windows launch logs';        Run = { @(Get-PcaLaunchAlerts; Get-UserAssistAlerts; Get-RegistryTraceAlerts; Get-BamDeletedAlerts) } },
    @{ Name = 'USN Journal';                  Caption = 'Checking USN change journal';        Run = { Get-UsnJournalAlerts } },
    @{ Name = 'Recycle Bin';                  Caption = 'Checking recently deleted files';    Run = { Get-RecycleBinAlerts } },
    @{ Name = 'System Clock';                 Caption = 'Checking for clock changes';         Run = { Get-ClockChangeAlerts } },
    @{ Name = 'Command History';              Caption = 'Scanning command history';           Run = { Get-CommandHistoryAlerts } },
    @{ Name = 'Autorun / Persistence';        Caption = 'Checking autorun and persistence';   Run = { Get-PersistenceAlerts } },
    @{ Name = 'DNS Cache';                    Caption = 'Checking DNS cache';                 Run = { Get-DnsCacheAlerts } },
    @{ Name = 'USB History';                  Caption = 'Reading USB removal history';        Run = { Get-UsbHistoryAlerts } },
    @{ Name = 'Encrypted & Virtual Drives';   Caption = 'Checking for hidden drives';         Run = { Get-HiddenVolumeAlerts } },
    @{ Name = 'Hidden Drive Letters';         Caption = 'Checking for subst drives';          Run = { Get-HiddenDriveLetterAlerts } }
)

$script:SystemCheckResults = @()
$checkTotal = $script:SystemChecks.Count
$checkDone = 0

if ($script:Report.AskPlayerName) {
    Write-StepHeader -Step 1
    Out-Seg ''
    Out-Seg '  ' -NoNewline
    Out-Seg 'Roblox username' -Fg 'Text' -Bold -NoNewline
    Out-Seg '  (shown on the recording and in the report)' -Fg 'Muted'
    Out-Seg '  > ' -Fg 'Brand1' -NoNewline
    $script:PlayerName = (([string](Read-Host)) -replace '[^A-Za-z0-9_\. -]', '').Trim()
    if ($script:PlayerName.Length -gt 32) { $script:PlayerName = $script:PlayerName.Substring(0, 32) }
}

Write-StepHeader -Step 1
if (Test-BsmmRelay) {
    Out-TaggedText -Indent '  ' -Tag 'NOTE' -Text 'Results are sent to BSMM staff with this report ID. User names, the PC name and personal files are never sent.' -TextToken 'Muted'
}
if (-not (Test-Admin)) {
    Out-Seg ''
    Out-Card -Title 'Not running as administrator' -Accent 'Warn' -Lines @(
        'Several checks need admin rights and will be incomplete.',
        'Close this window, right-click PowerShell, choose "Run as administrator" and start the check again.'
    )
}
Out-Seg ''
Out-Heading 'Scanning' "$checkTotal checks"
Out-Seg ''
$step1Start = Get-Date

foreach ($check in $script:SystemChecks) {
    Write-CheckProgress -Done $checkDone -Total $checkTotal -Text "$($check.Caption)..."
    $lines = @()
    try {
        $lines = @(& $check.Run)
    } catch {
        $lines = @("WARNING: Check crashed ($($_.Exception.Message))")
    }
    $script:SystemCheckResults += @{ Name = $check.Name; Lines = $lines; Summary = (Get-AlertSetSummary -Lines $lines) }
    $checkDone++
}
$step1Seconds = [int][math]::Round(((Get-Date) - $step1Start).TotalSeconds)
Write-CheckProgress -Done $checkTotal -Total $checkTotal -Text "Done in ${step1Seconds}s"
Out-Seg ''

$failCount = @($script:SystemCheckResults | Where-Object { $_.Summary.Status -eq 'FAIL' }).Count
$warnCount = @($script:SystemCheckResults | Where-Object { $_.Summary.Status -eq 'WARN' }).Count

Show-SystemCheckSummary -Results $script:SystemCheckResults -Seconds $step1Seconds

$script:SystemTrust = Get-BsmmTrustScore -Results $script:SystemCheckResults
if (Test-BsmmRelay) {
    Out-Seg ''
    $sentId = $null
    try { $sentId = Send-BsmmSystemReport -Results $script:SystemCheckResults -Trust $script:SystemTrust -Seconds $step1Seconds } catch {}
    if ($sentId) { Out-TaggedText -Indent '  ' -Tag 'PASS' -Text "Report $($script:ReportId) sent to BSMM staff" }
    else { Out-TaggedText -Indent '  ' -Tag 'WARN' -Text "Report $($script:ReportId) could not be sent (no internet?) - the recording is still valid" }
}

Out-Seg ''
Out-Rule
Read-BsmmContinue 'Continue to step 2: Process Explorer'

Write-StepHeader -Step 2
Out-Seg ''
Out-Card -Title 'What to do' -Numbered -Lines @(
    'Process Explorer opens full screen. Leave it open for a few seconds so the whole process list is on the recording.',
    'If the list does not fit on one screen, scroll through it slowly.',
    'Close Process Explorer (File > Exit). This window waits for it and then continues.'
)
Out-Seg ''
Out-TaggedText -Indent '  ' -Tag 'NOTE' -Text 'Downloading Process Explorer from Microsoft Sysinternals and checking its signature...' -TextToken 'Muted'
$procexpDir = Join-Path $env:TEMP ('BSMM_' + [guid]::NewGuid().ToString('N'))
if (Start-BsmmExternalTool -Name 'Process Explorer' `
        -Url 'https://download.sysinternals.com/files/ProcessExplorer.zip' `
        -ZipPath "$procexpDir.zip" `
        -DestDir $procexpDir `
        -ExeName 'procexp64.exe' `
        -FallbackExeNames @('procexp.exe') `
        -StartArguments @('/accepteula') `
        -KillProcessNames @('procexp', 'procexp64', 'procexp64a') `
        -WindowStyle Maximized `
        -Wait) {
    Out-TaggedText -Indent '  ' -Tag 'PASS' -Text 'Process Explorer closed.'
}

Out-Seg ''
Out-Rule
Out-Seg ''
Out-Seg '  ' -NoNewline
Out-Seg 'PC CHECK COMPLETE' -Fg 'Text' -Bold -NoNewline
Out-Seg ("   TRUST $($script:SystemTrust.Score)/100  $($script:SystemTrust.Label)") -Fg $script:SystemTrust.Token -Bold -NoNewline
Out-Seg "   report $($script:ReportId)" -Fg 'Muted'
Out-Seg ''
Out-Card -Title 'Next' -Numbered -Lines @(
    'Keep recording.',
    'Open a new PowerShell window as administrator and start the BSMM live monitor before you join the match.'
)
Out-Seg ''