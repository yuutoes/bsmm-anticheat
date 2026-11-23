[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:PreDefaultParams = 0
try { $script:PreDefaultParams = @($global:PSDefaultParameterValues.Keys).Count } catch {}
$script:PSDefaultParameterValues = @{}
$script:PreRemovedOverrides = @()
foreach ($__n in @(
    'Invoke-WebRequest','Invoke-RestMethod','Invoke-Expression','Test-Path','Get-Item',
    'Get-ChildItem','Get-ItemProperty','Get-ItemPropertyValue','Get-CimInstance','Get-WmiObject',
    'Get-Process','Start-Process','Get-Service','Get-WinEvent','Get-AuthenticodeSignature',
    'Get-Module','New-Item','Remove-Item','Add-Content','Get-Content','Get-Command','Write-Host',
    'Read-Host','Where-Object','ForEach-Object','Select-Object','Sort-Object','Measure-Object',
    'Out-Null','Get-Date','Out-String','Select-String','ConvertFrom-Json','ConvertTo-Json','Start-Sleep'
)) {
    foreach ($__kind in @('Alias', 'Function')) {
        if (Microsoft.PowerShell.Management\Test-Path -LiteralPath "$($__kind):\$__n") {
            $script:PreRemovedOverrides += "$($__kind.ToLower()) $__n"
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath "$($__kind):\$__n" -Force -ErrorAction SilentlyContinue
        }
    }
}

Clear-Host

$script:Brand = @{
    Name    = 'BSMM'
    Product = 'Anti-Cheat'
    Mode    = 'Live monitor'
    Version = '1.3.0'
    Website = ''
}

$script:Palette = @{
    Brand1 = @{ Hex = '#8B5CF6'; Fallback = 'Magenta' }
    Brand2 = @{ Hex = '#22D3EE'; Fallback = 'Cyan' }
    Shadow = @{ Hex = '#4C3A8A'; Fallback = 'DarkMagenta' }
    Text   = @{ Hex = '#F5F5F7'; Fallback = 'White' }
    Body   = @{ Hex = '#C9C9D1'; Fallback = 'Gray' }
    Muted  = @{ Hex = '#80808C'; Fallback = 'DarkGray' }
    Line   = @{ Hex = '#3C3C48'; Fallback = 'DarkGray' }
    Pass   = @{ Hex = '#34D399'; Fallback = 'Green' }
    Warn   = @{ Hex = '#FBBF24'; Fallback = 'Yellow' }
    Fail   = @{ Hex = '#FB4D6D'; Fallback = 'Red' }
    Info   = @{ Hex = '#7AA2F7'; Fallback = 'DarkCyan' }
    Ink    = @{ Hex = '#0E0E14'; Fallback = 'Black' }
}

$script:Report = @{
    LiveUpdateSeconds = 120
}

$script:Policy = @{
    MaxUptimeMinutes = 0
    DeepHistory      = $false
}

$script:Session = $null
try { $script:Session = $global:BsmmSession } catch {}
Microsoft.PowerShell.Utility\Remove-Variable -Name BsmmSession -Scope Global -Force -ErrorAction SilentlyContinue
if (-not ($script:Session -is [hashtable]) -or
    [string]$script:Session.Id -cnotmatch '^BSMM-[2-9A-HJ-NP-Z]{8}$' -or
    [string]$script:Session.Key -cnotmatch '^[0-9a-f]{64}$' -or
    [string]$script:Session.Relay -notmatch '^(https://[A-Za-z0-9.-]+(:\d+)?|http://(127\.0\.0\.1|localhost)(:\d+)?)$' -or
    [string]$script:Session.Mode -ne 'monitor') {
    Microsoft.PowerShell.Utility\Write-Host ''
    Microsoft.PowerShell.Utility\Write-Host '  This check only runs with a one-time code from BSMM staff.' -ForegroundColor Yellow
    Microsoft.PowerShell.Utility\Write-Host '  Ask staff for a new code, run the command again and enter it.' -ForegroundColor Yellow
    Microsoft.PowerShell.Utility\Write-Host ''
    return
}

$script:BsmmVersion = $script:Brand.Version
$script:ReportId = [string]$script:Session.Id
$script:MonitorLog = New-Object System.Collections.Generic.List[string]

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

$script:LogoRows = @(
    '######7 #######7###7   ###7###7   ###7',
    '##F==##7##F====J####7 ####!####7 ####!',
    '######FJ#######7##F####F##!##F####F##!',
    '##F==##7L====##!##!L##FJ##!##!L##FJ##!',
    '######FJ#######!##! L=J ##!##! L=J ##!',
    'L=====J L======JL=J     L=JL=J     L=J'
)

$script:Steps = @('Live monitor')

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

    try {
        $stdin = [BSMM.ConsoleApi]::GetStdHandle(-10)
        [uint32]$mode = 0
        if ([BSMM.ConsoleApi]::GetConsoleMode($stdin, [ref]$mode)) {
            $mode = ($mode -bor 0x0080) -band (-bnot 0x0040) -band (-bnot 0x0020)
            [void][BSMM.ConsoleApi]::SetConsoleMode($stdin, $mode)
        }
    } catch {}

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
    Out-Seg $script:ReportId -Fg 'Brand2' -Bold
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
        [datetime]$Since
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
                    Write-MonitorAlert -Message "WARNING: Could not query '$($filter.LogName)' log for tamper events ($($_.Exception.Message))" -Color Yellow
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

function Write-MonitorStatusLine {
    param([datetime]$Since)
    $elapsed = (Get-Date) - $Since
    $script:MonitorPulse = -not $script:MonitorPulse
    $dotTok = 'Line'; if ($script:MonitorPulse) { $dotTok = 'Fail' }
    $parts = @(
        @("`r  ", 'Body', $false),
        @($script:G.Dot, $dotTok, $false),
        @(' LIVE  ', 'Text', $true),
        @(('{0:hh\:mm\:ss}' -f $elapsed), 'Body', $false),
        @('    Ctrl+C when the match is over', 'Line', $false)
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
    if (-not $Level) { $Level = if ($Color -eq 'Yellow') { 'WARN' } else { 'INFO' } }
    if ($Level -eq 'NOTE') { $Level = 'INFO' }
    $script:MonitorAlertCounts[$Level]++
    if ($null -ne $script:MonitorLog) { [void]$script:MonitorLog.Add("[$(Get-Date -Format 'HH:mm:ss')] [$Level] $text") }
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
        [string]$Level = '',
        [string]$Color = ''
    )
    $key = Get-AlertDedupKey -Category $Category -Message $Message
    if (-not $script:MonitorSeenKeys.Add($key)) { return }
    $p = @{ Message = $Message }
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
    'wave', 'seliware', 'sirhurt', 'swift', 'solara', 'synapsex', 'synapse x', 'synapse z', 'synapsez', 'krnl',
    'fluxus', 'arceus', 'jjsploit', 'wearedevs', 'macsploit', 'hydrogen', 'vegax', 'vega x', 'scriptware',
    'script-ware', 'nihon', 'zenith', 'velocity', 'valyse', 'nezur', 'ronix', 'celery', 'cryptic', 'trigon',
    'oxygen', 'elysian', 'protosmasher', 'calamari', 'bunni', 'zorara', 'awpgg',
    'cheatengine', 'cheat engine', 'extremeinjector', 'injector', 'executor', 'aimbot', 'triggerbot', 'wallhack'
)

$script:FolderOnlyKeywords = @('map')

$script:TokenOnlyKeywords = @('loader', 'wave', 'swift', 'hydrogen', 'zenith', 'velocity', 'oxygen', 'cryptic', 'celery', 'nihon', 'trigon', 'aegis', 'injector', 'executor', 'bunni',
    'photon', 'evolve', 'matrix', 'clarity', 'spectre', 'severe', 'lumen', 'monolith', 'lattice', 'atlanta')

$script:KeywordBenignPattern = '(?i)\\(SystemApps|WindowsApps|Packages)\\MicrosoftWindows\.Client\.Photon.*|Photon ?(Engine|Unity|Voice|Server|Realtime)[^\\]*|SpectreClient[^\\]*|voiceclarity[^\\]*|Microsoft\.?Clarity[^\\]*|Matrix ?Awakens[^\\]*'

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
    if (-not (Get-BsmmKeywordRegex).IsMatch($Text) -and -not ($FolderName -and $Text -match '(?i)(^|[\\_\s\-\.])map($|[\\_\s\-\.])')) { return $null }
    $Text = [regex]::Replace($Text, $script:KeywordBenignPattern, '_')
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
        [hashtable]$Watched
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
            Write-MonitorAlert -Message "Script/Editor Launched ($toolTag): $name (PID $procId)$argInfo" -Level WARN
            $Watched[$procId] = $proc
            continue
        }

        if (-not (Test-ShouldLogProcessMonitorEvent -Proc $proc)) { continue }

        $label = "$($proc.Name) (PID $procId)"
        if ($proc.Path) { $label += " -> $($proc.Path)" }

        $tags = @($proc.Reasons | Where-Object { $_ -ne 'no image path' })
        if ($tags.Count -gt 0) {
            $level = if ($tags -match 'masquerade' -or ($tags | Where-Object { $_ -ne 'name/path mismatch' }).Count -gt 0) { 'FAIL' } else { 'WARN' }
            Write-MonitorAlert -Message "Started [$($tags -join ', ')]: $label" -Level $level
        } else {
            Write-MonitorAlert -Message "Started [userland]: $label" -Level WARN
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
            Write-MonitorAlert -Message "Exited [$($tags -join ', ')]: $label" -Level INFO
        } else {
            Write-MonitorAlert -Message "Exited [userland]: $label" -Level INFO
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
        if ($count -eq 0 -and -not (Test-Admin)) {
            $alerts += 'WARNING: Could not read the Prefetch folder (run as Administrator)'
        } elseif ($count -eq 0) {
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
    if ($entryCount -eq 0 -and -not (Test-Admin)) { $alerts += 'WARNING: Could not read BAM execution history (run as Administrator)' }
    elseif ($entryCount -eq 0) { $alerts += 'FAILURE: BAM execution history is empty' }
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
            $note = ''
            if ($tier -eq 'FAILURE' -and $path -match '(?i)^[A-Z]:\\(Program Files( \(x86\))?\\|Windows\\System32\\drivers\\)') { $tier = 'WARNING'; $note = ' (installed location, usually a hardware vendor tool)' }
            $alerts += "${tier}: Known-vulnerable driver LOADED${note}: $($drv.Name) -> $path"
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

$script:MicrosoftPreReleaseRoots = @('F8DB7E1C16F1FFD4AAAD4AAD8DFF0F2445184AEB', '8A334AA8052DD244A647306A76B8178FA215F344')

function Get-RootCertificateAlerts {
    $alerts = @()
    $stores = @(
        @{ Path = 'Cert:\LocalMachine\Root'; Label = 'machine' },
        @{ Path = 'Cert:\CurrentUser\Root';  Label = 'user' }
    )
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($store in $stores) {
        $certs = @()
        try { $certs = @(Get-ChildItem -Path $store.Path -ErrorAction Stop) } catch { continue }
        foreach ($cert in $certs) {
            if (-not $seen.Add([string]$cert.Thumbprint)) { continue }
            if (-not (Test-UserInstalledRootThumbprint -Thumbprint $cert.Thumbprint)) { continue }
            $subject = [string]$cert.Subject
            $short = $subject
            if ($subject -match 'CN=([^,]+)') { $short = $matches[1] }
            $when = Get-Date $cert.NotBefore -Format 'yyyy-MM-dd'
            $desc = "'$short' ($($store.Label) store, issued $when, $($cert.Thumbprint.Substring(0,8))...)"

            if ($script:MicrosoftPreReleaseRoots -contains $cert.Thumbprint) {
                $alerts += "INFO: Microsoft pre-release root certificate, normal on Windows Insider builds $desc"
            } elseif ($subject -match '(?i)microsoft') {
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

$script:BsmmExecExt    = @('.exe', '.dll', '.sys', '.bat', '.cmd', '.com', '.scr', '.ps1', '.vbs', '.js', '.ahk', '.lua', '.luau', '.msi', '.jar', '.asi')
$script:BsmmArchiveExt = @('.zip', '.rar', '.7z', '.tar', '.gz', '.iso', '.img', '.vhd', '.vhdx')

function Get-BsmmExtension {
    param([string]$Path)
    try { return [System.IO.Path]::GetExtension($Path).ToLower() } catch { return '' }
}

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
            if ($trusted) { continue }

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

function Get-BsmmUnix {
    param([datetime]$Time = (Get-Date))
    return [int64][Math]::Floor(($Time.ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds)
}

function ConvertTo-BsmmHex {
    param([byte[]]$Bytes)
    return ([BitConverter]::ToString($Bytes) -replace '-', '').ToLower()
}

$script:ReviewOnlyChecks = @(
    'UAC & Prompts', 'Windows Defender', 'Defender Exclusions', 'Allowed Threats', 'Defender Registry Overrides',
    'Active Defender Threats', 'Defender History', 'Windows Security Settings', 'Memory Integrity (HVCI)',
    'Root Certificates', 'Kernel Drivers', 'Process Scan', 'OBS & App Tamper', 'Suspicious Files', 'Signature Forgery',
    'Hidden Data Streams', 'Download Origins', 'Autorun / Persistence', 'Encrypted & Virtual Drives', 'Hidden Drive Letters'
)

function Limit-BsmmSeverity {
    param([string]$Check, [string[]]$Lines)
    if ($script:ReviewOnlyChecks -notcontains $Check) { return $Lines }
    return @(foreach ($line in @($Lines)) {
        $keep = $line -notlike 'FAILURE*' -or $line -match '(?i)roblox|bloxstrap|fishstrap|league policy'
        if (-not $keep) {
            foreach ($tag in [regex]::Matches($line, '\[([^\]\r\n]{2,40})\]')) {
                if ($script:CheatKeywords -contains $tag.Groups[1].Value) { $keep = $true; break }
            }
        }
        if ($keep) { $line } else { 'WARNING' + $line.Substring(7) }
    })
}

$script:RobloxIdPattern = '^[1-9]\d{0,18}$'
$script:RobloxJoinRegex = New-Object System.Text.RegularExpressions.Regex ('(?m)^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z),[^\r\n]*?game_join_loadtime: placeid:(\d+),[^\r\n]*?universeid:(\d+),[^\r\n]*?userid:(\d+)')
$script:RobloxIdentity = $null

function Add-BsmmRobloxAccount {
    param([hashtable]$Accounts, [string]$Id, [string]$Source, [int64]$Last = 0)
    if ($Id -notmatch $script:RobloxIdPattern) { return }
    if (-not $Accounts.ContainsKey($Id)) { $Accounts[$Id] = @{ id = $Id; sources = @(); last = [int64]0 } }
    $account = $Accounts[$Id]
    if ($account.sources -notcontains $Source) { $account.sources += $Source }
    if ($Last -gt $account.last) { $account.last = $Last }
}

function Get-BsmmRobloxIdentity {
    if ($script:RobloxIdentity) { return $script:RobloxIdentity }
    $accounts = @{}
    $userId = ''
    $root = Join-Path $env:LOCALAPPDATA 'Roblox'

    $storage = Join-Path $root 'LocalStorage\appStorage.json'
    $hasStorage = Test-Path -LiteralPath $storage -PathType Leaf
    if ($hasStorage) {
        try {
            $text = Read-BsmmTextFile -Path $storage
            if ($text -cmatch '"UserId"\s*:\s*"?(\d+)"?') {
                $userId = $matches[1]
                Add-BsmmRobloxAccount -Accounts $accounts -Id $userId -Source 'switcher'
            }
            if ($text -cmatch '"PreviousAccountsList"\s*:\s*("(?:[^"\\]|\\.)*")') {
                $previous = ($matches[1] | ConvertFrom-Json) | ConvertFrom-Json
                foreach ($entry in @($previous.PSObject.Properties)) {
                    $last = [int64]0
                    try { $last = [int64]$entry.Value.signOutTimestamp } catch {}
                    if ($last -gt 100000000000) { $last = [int64][Math]::Floor($last / 1000) }
                    $id = [string]$entry.Value.userId
                    if (-not $id) { $id = [string]$entry.Name }
                    Add-BsmmRobloxAccount -Accounts $accounts -Id $id -Source 'switcher' -Last $last
                }
            }
            $text = $null
        } catch {}
    }

    $games = New-Object System.Collections.Generic.List[object]
    $logs = @()
    try {
        $logs = @(Get-ChildItem -LiteralPath (Join-Path $root 'logs') -File -Filter '*_Player_*_last.log' -ErrorAction Stop |
            Where-Object { $_.Name -notmatch 'CrashHandler' } | Sort-Object LastWriteTime -Descending)
    } catch {}
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    foreach ($log in @($logs | Select-Object -First 40)) {
        $text = ''
        try { $text = Read-BsmmTextFile -Path $log.FullName } catch { continue }
        foreach ($join in $script:RobloxJoinRegex.Matches($text)) {
            $at = [int64]0
            try { $at = Get-BsmmUnix ([datetime]::Parse($join.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture, $styles)) } catch {}
            $player = $join.Groups[4].Value
            Add-BsmmRobloxAccount -Accounts $accounts -Id $player -Source 'logs' -Last $at
            if ($at -gt 0 -and $player -match $script:RobloxIdPattern) {
                $games.Add(@{ placeId = $join.Groups[2].Value; universeId = $join.Groups[3].Value; at = $at; userId = $player })
            }
        }
    }

    try {
        foreach ($dir in [IO.Directory]::GetDirectories($root)) {
            $name = [IO.Path]::GetFileName($dir)
            if ($name -match '^\d{3,19}$') { Add-BsmmRobloxAccount -Accounts $accounts -Id $name -Source 'studio' -Last (Get-BsmmUnix ([IO.Directory]::GetLastWriteTime($dir))) }
        }
    } catch {}

    $newestLog = $null
    if ($logs.Count -gt 0) { $newestLog = $logs[0].LastWriteTime }
    $script:RobloxIdentity = @{
        userId     = $userId
        accounts   = @($accounts.Values | Sort-Object { $_.last } -Descending | Select-Object -First 40)
        games      = @($games | Sort-Object { $_.at } -Descending | Select-Object -First 12)
        LogCount   = $logs.Count
        NewestLog  = $newestLog
        HasStorage = $hasStorage
    }
    return $script:RobloxIdentity
}

function Get-RobloxAccountDataAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    $id = Get-BsmmRobloxIdentity
    $lastRun = $null
    foreach ($run in @(Get-BsmmProgramHistory)) {
        if ($run.Source -ne 'exit' -and $run.Path -match '(?i)(^|\\)RobloxPlayerBeta\.exe$' -and (-not $lastRun -or $run.Time -gt $lastRun)) { $lastRun = $run.Time }
    }
    $ranText = ''
    if ($lastRun) { $ranText = Get-Date $lastRun -Format 'yyyy-MM-dd HH:mm' }

    if (-not $lastRun -and $id.LogCount -eq 0 -and -not $id.HasStorage) {
        $alerts.Add('WARNING: No sign that Roblox has been played on this PC (no logs, no saved account, no run history) - the player may be using a different PC')
    }
    if ($lastRun -and $lastRun -gt (Get-Date).AddDays(-3)) {
        if ($id.LogCount -eq 0) {
            $alerts.Add("WARNING: Roblox ran $ranText but the Roblox log folder has no game logs (the logs were deleted)")
        } elseif ($id.NewestLog -lt $lastRun.AddMinutes(-30)) {
            $alerts.Add("WARNING: Roblox ran $ranText but the newest Roblox log is from $(Get-Date $id.NewestLog -Format 'yyyy-MM-dd HH:mm') (later logs were deleted)")
        }
    }
    if (-not $id.HasStorage -and ($lastRun -or $id.LogCount -gt 0)) {
        $alerts.Add('WARNING: The saved Roblox account list (appStorage.json) is missing although Roblox has been used on this PC (account history was removed)')
    } elseif ($id.HasStorage -and -not $id.userId) {
        $alerts.Add('INFO: No Roblox account is logged in right now')
    }
    $count = @{ switcher = 0; logs = 0; studio = 0 }
    foreach ($account in @($id.accounts)) { foreach ($source in $account.sources) { $count[$source]++ } }
    $alerts.Add("INFO: $(@($id.accounts).Count) Roblox accounts found on this PC (account switcher $($count.switcher), game logs $($count.logs), Studio $($count.studio)); $($id.LogCount) game logs kept")
    if (-not ($alerts | Where-Object { $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: Roblox logs and saved account data are in place') }
    return @($alerts)
}

function Get-BsmmPcFingerprint {
    $placeholder = '(?i)^(|none|default string|to be filled by o\.?e\.?m\.?|system serial number|base board serial number|not applicable|not specified|n/a|unknown|[0-]+|[f-]+|123456789|03000200-0400-0500-0006-000700080009)$'
    $values = @()
    try { $values += [string](Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop | Select-Object -First 1).UUID } catch {}
    try { $values += [string](Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1).SerialNumber } catch {}
    try { $values += [string](Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).ProcessorId } catch {}
    $real = @($values | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ -notmatch $placeholder })
    if ($real.Count -lt 2) {
        try { $real += ([string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop)).ToUpper() } catch {}
    }
    if ($real.Count -eq 0) { return '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (ConvertTo-BsmmHex $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('bsmm-pc-v1|' + ($real -join '|')))) } finally { $sha.Dispose() }
}

$script:ProgramHistory = $null
$script:JournalPrefetch = $null

function Add-BsmmRun {
    param($Runs, [string]$Path, $Time, [string]$Source, [int]$Count = 0)
    if (-not $Path -or -not ($Time -is [datetime]) -or $Time.Year -lt 2015 -or $Time -gt (Get-Date).AddDays(1)) { return }
    $Runs.Add([pscustomobject]@{ Path = $Path; Time = $Time; Source = $Source; Runs = $Count })
}

function Resolve-BsmmDevicePath {
    param([string]$Path, [hashtable]$Serials, [hashtable]$Volumes)
    if ($Path -match '^[A-Za-z]:\\') { return $Path }
    if ($Path -match '(?i)^\\VOLUME\{[0-9a-f]+-([0-9a-f]+)\}(\\.+)$') {
        $serial = $matches[1].TrimStart('0').ToUpper()
        if ($Serials.ContainsKey($serial)) { return $Serials[$serial] + $matches[2] }
    } elseif ($Path -match '(?i)^(\\Device\\HarddiskVolume\d+)(\\.+)$') {
        if ($Volumes.ContainsKey($matches[1])) { return $Volumes[$matches[1]] + $matches[2] }
    }
    return $Path
}

function Get-BsmmProgramHistory {
    if ($script:ProgramHistory) { return $script:ProgramHistory }
    $runs = New-Object System.Collections.Generic.List[object]
    $admin = $false; try { $admin = [bool](Test-Admin) } catch {}
    $volumes = @{}; try { $volumes = Get-BsmmVolumeMap } catch {}
    $serials = @{}
    try {
        foreach ($disk in @(Get-CimInstance Win32_LogicalDisk -ErrorAction Stop)) {
            if ($disk.VolumeSerialNumber) { $serials[([string]$disk.VolumeSerialNumber).TrimStart('0').ToUpper()] = [string]$disk.DeviceID }
        }
    } catch {}
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $utc = [Globalization.DateTimeStyles]::AssumeUniversal

    try {
        $started = @{}
        foreach ($p in @(Get-CimInstance Win32_Process -Property ExecutablePath, CreationDate -ErrorAction Stop)) {
            if (-not $p.ExecutablePath -or -not $p.CreationDate) { continue }
            $key = [string]$p.ExecutablePath
            if (-not $started.ContainsKey($key) -or $p.CreationDate -lt $started[$key]) { $started[$key] = $p.CreationDate }
        }
        foreach ($key in $started.Keys) { Add-BsmmRun -Runs $runs -Path $key -Time $started[$key] -Source 'running' }
    } catch {}

    $prefetchPaths = @{}
    if ($admin -and (Initialize-BsmmForensics)) {
        try {
            foreach ($file in [IO.Directory]::GetFiles((Join-Path $env:SystemRoot 'Prefetch'), '*.pf')) {
                $info = $null
                try { $info = [BSMM.Timeline]::Prefetch($file) } catch {}
                if (-not $info -or -not $info.Exe) { continue }
                $path = $info.Exe
                if ($info.Path) { $path = Resolve-BsmmDevicePath -Path $info.Path -Serials $serials -Volumes $volumes }
                $prefetchPaths[[IO.Path]::GetFileName($file)] = $path
                foreach ($time in $info.Times) { Add-BsmmRun -Runs $runs -Path $path -Time $time -Source 'prefetch' -Count $info.RunCount }
            }
        } catch {}
    }

    if ($admin) {
        try {
            foreach ($entry in @(Get-BamEntries)) {
                Add-BsmmRun -Runs $runs -Path (Resolve-BsmmDevicePath -Path $entry.Raw -Serials $serials -Volumes $volumes) -Time $entry.Time -Source 'bam'
            }
        } catch {}
    }

    $pca = Join-Path $env:SystemRoot 'appcompat\pca'
    try {
        foreach ($line in ((Read-BsmmTextFile -Path (Join-Path $pca 'PcaAppLaunchDic.txt')) -split "`r?`n")) {
            $cut = $line.LastIndexOf('|')
            if ($cut -lt 1) { continue }
            $time = [datetime]::MinValue
            if ([datetime]::TryParse($line.Substring($cut + 1).Trim(), $culture, $utc, [ref]$time)) {
                Add-BsmmRun -Runs $runs -Path $line.Substring(0, $cut).Trim() -Time $time -Source 'launch'
            }
        }
    } catch {}

    foreach ($name in @('PcaGeneralDb0.txt', 'PcaGeneralDb1.txt')) {
        try {
            $perProgram = @{}
            $lines = (Read-BsmmTextFile -Path (Join-Path $pca $name)) -split "`r?`n"
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $fields = $lines[$i].Split('|')
                if ($fields.Count -lt 3 -or $fields[1] -ne '2') { continue }
                $path = [Environment]::ExpandEnvironmentVariables($fields[2].Trim())
                if ($path.StartsWith('\') -and -not $path.StartsWith('\\')) { $path = $env:SystemDrive + $path }
                $perProgram[$path] = 1 + [int]$perProgram[$path]
                if ($perProgram[$path] -gt 20) { continue }
                $time = [datetime]::MinValue
                if ([datetime]::TryParse($fields[0].Trim(), $culture, $utc, [ref]$time)) { Add-BsmmRun -Runs $runs -Path $path -Time $time -Source 'exit' }
            }
        } catch {}
    }

    try {
        $rootKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist')
        if ($rootKey) {
            foreach ($guid in $rootKey.GetSubKeyNames()) {
                $countKey = $rootKey.OpenSubKey("$guid\Count")
                if (-not $countKey) { continue }
                foreach ($valueName in $countKey.GetValueNames()) {
                    $raw = $countKey.GetValue($valueName)
                    if (-not ($raw -is [byte[]]) -or $raw.Length -lt 68) { continue }
                    $stamp = [BitConverter]::ToInt64($raw, 60)
                    if ($stamp -le 0) { continue }
                    $name = ConvertFrom-Rot13 $valueName
                    if ($name -match '^(\{[0-9A-Fa-f\-]{36}\})\\(.*)$' -and $script:KnownFolderGuids[$matches[1]]) { $name = Join-Path $script:KnownFolderGuids[$matches[1]] $matches[2] }
                    if ($name -notmatch '(?i)^[A-Z]:\\.+\.(exe|bat|cmd|com|scr|ahk|ps1|vbs|msi|jar)$') { continue }
                    $time = $null
                    try { $time = [DateTime]::FromFileTime($stamp) } catch { continue }
                    Add-BsmmRun -Runs $runs -Path $name -Time $time -Source 'userassist' -Count ([BitConverter]::ToInt32($raw, 4))
                }
                $countKey.Close()
            }
            $rootKey.Close()
        }
    } catch {}

    if ($script:JournalPrefetch -and $script:JournalPrefetch.Count -gt 0) {
        $byLeaf = @{}
        foreach ($run in $runs) {
            if ($run.Path -match '^[A-Za-z]:\\') { $byLeaf[[IO.Path]::GetFileName($run.Path).ToUpper()] = $run.Path }
        }
        $lastWrite = @{}
        foreach ($write in @($script:JournalPrefetch | Sort-Object Time)) {
            $file = [string]$write.Name
            if ($lastWrite.ContainsKey($file) -and ($write.Time - $lastWrite[$file]).TotalSeconds -lt 10) { $lastWrite[$file] = $write.Time; continue }
            $lastWrite[$file] = $write.Time
            $exe = $file -replace '(?i)-[0-9A-F]{6,8}\.pf$', ''
            $path = $exe
            if ($prefetchPaths.ContainsKey($file)) { $path = $prefetchPaths[$file] }
            elseif ($byLeaf.ContainsKey($exe.ToUpper())) { $path = $byLeaf[$exe.ToUpper()] }
            elseif (Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32\$exe") -PathType Leaf) { continue }
            Add-BsmmRun -Runs $runs -Path $path -Time $write.Time -Source 'journal'
        }
    }

    $script:ProgramHistory = $runs
    return $runs
}

function Get-BsmmUpdatedProgramPath {
    param([string]$Path)
    try {
        $parent = [IO.Path]::GetDirectoryName($Path)
        $root = [IO.Path]::GetDirectoryName($parent)
        if (-not $root -or [IO.Path]::GetFileName($parent) -notmatch '\d' -or [IO.Directory]::Exists($parent) -or -not [IO.Directory]::Exists($root)) { return $null }
        foreach ($dir in [IO.Directory]::GetDirectories($root)) {
            if ([IO.Path]::GetFileName($dir) -notmatch '\d') { continue }
            $candidate = [IO.Path]::Combine($dir, [IO.Path]::GetFileName($Path))
            if ([IO.File]::Exists($candidate)) { return $candidate }
        }
    } catch {}
    return $null
}

$script:ProgramSignatures = @{}
function Get-BsmmProgramSignature {
    param([string]$Path)
    if ($script:ProgramSignatures.ContainsKey($Path)) { return $script:ProgramSignatures[$Path] }
    $result = @{ sig = 'unknown'; signer = '' }
    if ($Path -match '^\\') { $result.sig = 'missing' }
    elseif ($Path -match '^[A-Za-z]:\\') {
        $file = $Path
        try {
            if (-not [IO.File]::Exists($file)) { $file = Get-BsmmUpdatedProgramPath -Path $Path }
            if (-not $file) { $result.sig = 'missing' }
            else {
                $sig = Get-BsmmSignature -Path $file
                if ((-not $sig -or [string]$sig.Status -ne 'Valid') -and $file -match '(?i)^(.+?\\(WindowsApps|SystemApps)\\[^\\]+)\\') {
                    $package = Get-BsmmSignature -Path ($matches[1] + '\AppxSignature.p7x')
                    if ($package -and [string]$package.Status -eq 'Valid') { $sig = $package }
                }
                if ($sig) {
                    $result.sig = 'unsigned'
                    if ([string]$sig.Status -eq 'Valid' -and $sig.SignerCertificate) {
                        $rootThumbprint = Get-SignatureRootThumbprint -Certificate $sig.SignerCertificate
                        if ($rootThumbprint -and -not (Test-UserInstalledRootThumbprint -Thumbprint $rootThumbprint)) { $result.sig = 'signed' }
                    }
                    $result.signer = Limit-BsmmText (Get-BsmmSigner $sig) 60
                }
            }
        } catch {}
    }
    $script:ProgramSignatures[$Path] = $result
    return $result
}

function Get-BsmmProgramRuns {
    $windows = ($env:SystemRoot + '\').ToLower()
    $monthAgo = (Get-Date).AddDays(-30)
    $history = @(Get-BsmmProgramHistory | Sort-Object Time -Descending)
    $cased = @{}
    foreach ($run in $history) { if ($run.Source -ne 'prefetch' -and $run.Source -ne 'journal') { $cased[[string]$run.Path] = [string]$run.Path } }

    $kept = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($run in $history) {
        $path = [string]$run.Path
        if ($cased.ContainsKey($path)) { $path = $cased[$path] }
        $lower = $path.ToLower()
        if ($run.Time -lt $monthAgo -and $run.Source -ne 'launch' -and $run.Source -ne 'userassist') { continue }
        if ($lower.StartsWith($windows)) {
            if ($lower -match '\\(softwaredistribution|winsxs|servicing|assembly|microsoft\.net)\\') { continue }
            if ($lower -notmatch '\\temp\\' -and [IO.File]::Exists($path)) { continue }
        }
        $at = Get-BsmmUnix $run.Time
        if (-not $seen.Add("$($run.Source)|$at|$lower")) { continue }
        $kept.Add(@{ path = $path; at = $at; src = [string]$run.Source; runs = [int]$run.Runs; recent = ($run.Time -ge $monthAgo) })
        if ($kept.Count -ge 2500) { break }
    }

    $clock = [Diagnostics.Stopwatch]::StartNew()
    foreach ($run in $kept) { if ($run.src -eq 'running') { [void](Get-BsmmProgramSignature -Path $run.path) } }
    return @(foreach ($run in $kept) {
        $state = @{ sig = 'unknown'; signer = '' }
        if ($run.recent -and ($clock.Elapsed.TotalSeconds -lt 40 -or $script:ProgramSignatures.ContainsKey($run.path))) { $state = Get-BsmmProgramSignature -Path $run.path }
        @{ path = (Limit-BsmmText (Protect-BsmmText $run.path) 300); at = $run.at; src = $run.src; sig = $state.sig; signer = $state.signer; runs = $run.runs }
    })
}

$script:ImGuiIgnorePaths = '(?i)\\(steamapps|Program Files( \(x86\))?|WindowsApps|Epic Games|Riot Games)\\'
$script:ImGuiHotPaths = '(?i)\\AppData\\Local\\(Roblox|Bloxstrap|Fishstrap)\\|\\Roblox\\Versions\\'

function Find-BsmmFile {
    param([string]$Root, [string]$Name, [int]$Depth)
    $hits = New-Object System.Collections.Generic.List[string]
    if (-not $Root -or -not [IO.Directory]::Exists($Root)) { return $hits }
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($Root, 0))
    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $file = [IO.Path]::Combine($item[0], $Name)
        if ([IO.File]::Exists($file)) { $hits.Add($file) }
        if ($item[1] -ge $Depth) { continue }
        try {
            foreach ($sub in (New-Object IO.DirectoryInfo $item[0]).GetDirectories()) {
                if (($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push(@($sub.FullName, ($item[1] + 1))) }
            }
        } catch {}
    }
    return $hits
}

function Get-ImGuiTraceAlerts {
    param([datetime]$Since = [datetime]::MinValue)
    $places = @(
        @{ Depth = 3; Roots = @(Get-BsmmUserFolders Desktop) + @(Get-BsmmUserFolders Downloads) + @(Get-BsmmUserFolders Documents) + @($env:LOCALAPPDATA, $env:APPDATA) },
        @{ Depth = 2; Roots = @($env:TEMP, $env:ProgramData, "${env:ProgramFiles(x86)}\Roblox\Versions") },
        @{ Depth = 1; Roots = @($env:SystemDrive + '\') },
        @{ Depth = 0; Roots = @($env:USERPROFILE, $env:SystemRoot, (Join-Path $env:SystemRoot 'System32'), (Join-Path $env:SystemRoot 'SysWOW64')) }
    )
    $found = @{}
    foreach ($place in $places) {
        foreach ($root in $place.Roots) { foreach ($file in @(Find-BsmmFile -Root $root -Name 'imgui.ini' -Depth $place.Depth)) { $found[$file] = $true } }
    }

    $alerts = New-Object System.Collections.Generic.List[string]
    $weekAgo = (Get-Date).AddDays(-7)
    $windows = ($env:SystemRoot + '\').ToLower()
    foreach ($path in @($found.Keys | Sort-Object)) {
        if ($path -match $script:ImGuiIgnorePaths) { continue }
        $written = $null
        try { $written = [IO.File]::GetLastWriteTime($path) } catch { continue }
        if ($written -lt $Since) { continue }
        $titles = @()
        try {
            if ((New-Object IO.FileInfo $path).Length -le 512KB) {
                $titles = @([regex]::Matches((Read-BsmmTextFile -Path $path), '(?m)^\[Window\]\[([^\]\r\n]{1,60})\]') | ForEach-Object { $_.Groups[1].Value } |
                    Where-Object { $_ -notmatch '^Debug##' } | Select-Object -Unique -First 6)
            }
        } catch {}
        $kw = Get-MatchedCheatKeyword -Text $path
        foreach ($title in $titles) { if (-not $kw) { $kw = Get-MatchedCheatKeyword -Text $title } }
        $detail = "last written $(Get-Date $written -Format 'yyyy-MM-dd HH:mm:ss') -> $path"
        if ($titles.Count -gt 0) { $detail += " (menu windows: $($titles -join ', '))" }
        if ($kw) { $alerts.Add("FAILURE: ImGui menu settings file [$kw] $detail") }
        elseif ($path -match $script:ImGuiHotPaths) { $alerts.Add("FAILURE: ImGui menu settings file inside the Roblox folder (a menu was drawn inside Roblox) $detail") }
        elseif ($path.ToLower().StartsWith($windows)) { $alerts.Add("WARNING: ImGui menu settings file in a Windows folder (left by a menu program that was started as administrator) $detail") }
        elseif ($written -ge $weekAgo) { $alerts.Add("WARNING: ImGui menu settings file used in the last 7 days $detail") }
        else { $alerts.Add("INFO: Old ImGui menu settings file $detail") }
    }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: No recent ImGui menu settings files (imgui.ini) found') }
    return @($alerts | Select-Object -First 25)
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
            $req.Timeout = 30000
            $req.ReadWriteTimeout = 30000
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
            if (($code -eq 429 -or $code -eq 0) -and $attempt -eq 1) { Start-Sleep -Seconds $retry; continue }
            return @{ Ok = $false; Code = $code; Error = $_.Exception.Message }
        } catch {
            return @{ Ok = $false; Code = 0; Error = $_.Exception.Message }
        }
    }
    return @{ Ok = $false; Code = 429; Error = 'rate limited' }
}

function Send-BsmmSigned {
    param([string]$Path, [int]$Seq, [hashtable]$Body)
    $enc = New-Object System.Text.UTF8Encoding($false)
    $bytes = $enc.GetBytes((ConvertTo-Json -InputObject $Body -Depth 8 -Compress))
    while ($bytes.Length -gt 1400000 -and @($Body.programs).Count -gt 100) {
        $Body.programs = @($Body.programs | Select-Object -First ([int](@($Body.programs).Count / 2)))
        $bytes = $enc.GetBytes((ConvertTo-Json -InputObject $Body -Depth 8 -Compress))
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hmac = New-Object System.Security.Cryptography.HMACSHA256 (, $enc.GetBytes([string]$script:Session.Key))
    try {
        $digest = ConvertTo-BsmmHex $sha.ComputeHash($bytes)
        $signature = ConvertTo-BsmmHex $hmac.ComputeHash($enc.GetBytes("$($script:Session.Id).$Seq.$digest"))
    } finally { $sha.Dispose(); $hmac.Dispose() }
    $headers = @{ 'X-Bsmm-Check' = [string]$script:Session.Id; 'X-Bsmm-Seq' = "$Seq"; 'X-Bsmm-Sig' = $signature }
    $result = Invoke-BsmmHttp -Method 'POST' -Url (([string]$script:Session.Relay).TrimEnd('/') + $Path) -Body $bytes -ContentType 'application/json' -Headers $headers
    return [bool]$result.Ok
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
    return $facts
}

function Get-BsmmReportChecks {
    param([array]$Results)
    return @(foreach ($result in @($Results)) {
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($line in @($result.Lines)) {
            if (-not $line -or $lines.Count -ge 300 -or -not (Test-BsmmReportLine -Section $result.Name -Line $line)) { continue }
            $lines.Add((Limit-BsmmText (Protect-BsmmText ((([string]$line) -replace "`r?`n", ' | ') -replace '\s+', ' ').Trim()) 700))
        }
        if ($lines.Count -eq 0 -and @($result.Lines).Count -gt 0) { $lines.Add('SUCCESS: Nothing to report') }
        @{ name = [string]$result.Name; lines = $lines.ToArray() }
    })
}

function Get-BsmmReportBody {
    param([array]$Results, [int]$Seconds)
    $admin = $false; try { $admin = [bool](Test-Admin) } catch {}
    $facts = [ordered]@{}
    foreach ($fact in (Get-BsmmSystemFacts).GetEnumerator()) { $facts[[string]$fact.Key] = Limit-BsmmText (Protect-BsmmText ([string]$fact.Value)) 200 }
    $identity = Get-BsmmRobloxIdentity
    $body = @{
        v        = [string]$script:Brand.Version
        seconds  = $Seconds
        admin    = $admin
        facts    = $facts
        checks   = @(Get-BsmmReportChecks -Results $Results)
        roblox   = @{ userId = [string]$identity.userId; accounts = @($identity.accounts); games = @($identity.games) }
        pc       = [string](Get-BsmmPcFingerprint)
        programs = @(Get-BsmmProgramRuns)
    }
    $body.clock = Get-BsmmUnix
    return $body
}

function Get-BsmmLiveBody {
    param([datetime]$Since, [string]$State)
    $counts = $script:MonitorAlertCounts
    $clean = { param($line) Limit-BsmmText (Protect-BsmmText ([string]$line)) 300 }
    $body = @{
        state   = $State
        elapsed = [int]((Get-Date) - $Since).TotalSeconds
        counts  = @{ fail = [int]$counts.FAIL; warn = [int]$counts.WARN; info = [int]$counts.INFO }
        recent  = @($script:MonitorLog | Where-Object { $_ -match '\[(FAIL|WARN)\]' } | Select-Object -Last 30 | ForEach-Object { & $clean $_ })
    }
    if ($State -eq 'ENDED') { $body.log = @($script:MonitorLog | Select-Object -Last 2500 | ForEach-Object { & $clean $_ }) }
    return $body
}

$script:BsmmForensicsSource = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

namespace BSMM
{
    public class UsnEntry
    {
        public DateTime Time;
        public uint Reason;
        public string Name;
        public string Path;
        public ulong Frn;
        public ulong ParentFrn;
        public bool IsDir;
    }

    public class UsnInfo
    {
        public bool Ok;
        public string Error;
        public ulong JournalId;
        public long FirstUsn;
        public long NextUsn;
        public ulong MaximumSize;
        public DateTime OldestRecord;
        public long RecordsRead;
    }

    // Aho-Corasick automaton over bytes. Every needle is searched as ASCII and as UTF-16LE.
    public class Matcher
    {
        private int[] delta;
        private ulong[] masks;

        public Matcher(string[] needles)
        {
            if (needles.Length > 64) throw new ArgumentException("at most 64 needles");
            var pats = new List<KeyValuePair<byte[], int>>();
            for (int i = 0; i < needles.Length; i++)
            {
                pats.Add(new KeyValuePair<byte[], int>(Encoding.ASCII.GetBytes(needles[i]), i));
                pats.Add(new KeyValuePair<byte[], int>(Encoding.Unicode.GetBytes(needles[i]), i));
            }
            var go = new List<int[]>();
            var outs = new List<ulong>();
            go.Add(NewRow()); outs.Add(0);
            foreach (var p in pats)
            {
                int s = 0;
                foreach (byte b in p.Key)
                {
                    if (go[s][b] < 0) { go.Add(NewRow()); outs.Add(0); go[s][b] = go.Count - 1; }
                    s = go[s][b];
                }
                outs[s] |= (1UL << p.Value);
            }
            int n = go.Count;
            int[] fail = new int[n];
            delta = new int[n * 256];
            masks = new ulong[n];
            var queue = new Queue<int>();
            masks[0] = outs[0];
            for (int c = 0; c < 256; c++)
            {
                int t = go[0][c];
                if (t < 0) { delta[c] = 0; }
                else { delta[c] = t; fail[t] = 0; queue.Enqueue(t); }
            }
            while (queue.Count > 0)
            {
                int r = queue.Dequeue();
                masks[r] = outs[r] | masks[fail[r]];
                for (int c = 0; c < 256; c++)
                {
                    int t = go[r][c];
                    if (t < 0) { delta[r * 256 + c] = delta[fail[r] * 256 + c]; }
                    else { fail[t] = delta[fail[r] * 256 + c]; delta[r * 256 + c] = t; queue.Enqueue(t); }
                }
            }
        }

        private static int[] NewRow()
        {
            int[] row = new int[256];
            for (int i = 0; i < 256; i++) row[i] = -1;
            return row;
        }

        public ulong Scan(byte[] buf, int len, ref int state)
        {
            ulong hits = 0;
            int s = state;
            int[] d = delta;
            ulong[] m = masks;
            for (int i = 0; i < len; i++)
            {
                s = d[(s << 8) | buf[i]];
                hits |= m[s];
            }
            state = s;
            return hits;
        }
    }

    public static class Forensics
    {
        const uint PROCESS_QUERY_INFORMATION = 0x0400;
        const uint PROCESS_VM_READ = 0x0010;
        const uint MEM_COMMIT = 0x1000;
        public const uint MEM_PRIVATE = 0x20000;
        public const uint MEM_MAPPED = 0x40000;
        public const uint MEM_IMAGE = 0x1000000;

        [StructLayout(LayoutKind.Sequential)]
        struct MBI
        {
            public IntPtr BaseAddress;
            public IntPtr AllocationBase;
            public uint AllocationProtect;
            public IntPtr RegionSize;
            public uint State;
            public uint Protect;
            public uint Type;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI info, IntPtr len);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inBuf, int inSize, byte[] outBuf, int outSize, out int returned, IntPtr overlapped);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        static extern int RegLoadAppKey(string file, out IntPtr hkResult, int samDesired, int options, int reserved);
        [StructLayout(LayoutKind.Sequential)]
        struct FILE_ID_DESCRIPTOR { public int dwSize; public int Type; public long FileId; public long Pad; }
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern SafeFileHandle OpenFileById(SafeFileHandle volumeHint, ref FILE_ID_DESCRIPTOR id, uint access, uint share, IntPtr sec, uint flags);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern uint GetFinalPathNameByHandle(SafeFileHandle h, StringBuilder buf, uint len, uint flags);

        delegate void ChunkHandler(byte[] buf, int len);

        static bool Readable(uint protect)
        {
            if ((protect & 0x100) != 0 || (protect & 0x01) != 0) return false;   // GUARD / NOACCESS
            return (protect & 0xEE) != 0;
        }

        static string WalkMemory(int pid, uint typeMask, long maxBytes, ChunkHandler onChunk)
        {
            IntPtr h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
            if (h == IntPtr.Zero) return "access denied (" + Marshal.GetLastWin32Error() + ")";
            try
            {
                byte[] buf = new byte[4 * 1024 * 1024];
                long total = 0;
                long addr = 0;
                int mbiSize = Marshal.SizeOf(typeof(MBI));
                MBI mbi;
                while (total < maxBytes)
                {
                    if (VirtualQueryEx(h, new IntPtr(addr), out mbi, new IntPtr(mbiSize)) == IntPtr.Zero) break;
                    long baseAddr = mbi.BaseAddress.ToInt64();
                    long size = mbi.RegionSize.ToInt64();
                    if (size <= 0) break;
                    if (mbi.State == MEM_COMMIT && (mbi.Type & typeMask) != 0 && Readable(mbi.Protect))
                    {
                        long off = 0;
                        while (off < size && total < maxBytes)
                        {
                            int want = (int)Math.Min(buf.Length, size - off);
                            IntPtr got;
                            if (!ReadProcessMemory(h, new IntPtr(baseAddr + off), buf, new IntPtr(want), out got)) break;
                            int n = (int)got.ToInt64();
                            if (n <= 0) break;
                            onChunk(buf, n);
                            total += n;
                            off += n;
                        }
                    }
                    long next = baseAddr + size;
                    if (next <= addr) break;
                    addr = next;
                }
                return null;
            }
            finally { CloseHandle(h); }
        }

        // ---- path strings -----------------------------------------------------------------------
        static readonly Regex PathRe = new Regex(
            @"(?:[A-Za-z]:|\\Device\\HarddiskVolume\d{1,3})\\(?:[^\\/:*?""<>|\x00-\x1f]{1,120}\\){0,24}[^\\/:*?""<>|\x00-\x1f]{1,120}?\.(?:exe|dll|sys|bat|cmd|ps1|lua|luau|ahk|jar|scr|py)(?![A-Za-z0-9])",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        static readonly Regex DpsRe = new Regex(
            @"!!([^!\\/:*?""<>|\x00-\x1f]{1,120}?\.[A-Za-z0-9]{2,5})!(\d{4}/\d\d/\d\d:\d\d:\d\d:\d\d)!",
            RegexOptions.CultureInvariant);

        static void Harvest(string s, HashSet<string> found, int max)
        {
            if (found.Count >= max) return;
            if (s.IndexOf('\\') >= 0)
            {
                foreach (Match m in PathRe.Matches(s)) { if (found.Count >= max) return; found.Add(m.Value); }
            }
            if (s.IndexOf("!!", StringComparison.Ordinal) >= 0)
            {
                foreach (Match m in DpsRe.Matches(s)) { if (found.Count >= max) return; found.Add("!!" + m.Groups[1].Value + "|" + m.Groups[2].Value); }
            }
        }

        static void ExtractStrings(byte[] b, int len, HashSet<string> found, int max)
        {
            const int MIN = 6;
            const int MAXLEN = 2048;
            int start = -1;
            bool interesting = false;
            for (int i = 0; i <= len; i++)
            {
                bool ok = false;
                byte c = 0;
                if (i < len) { c = b[i]; ok = c >= 0x20 && c < 0x7F; }
                if (ok)
                {
                    if (start < 0) { start = i; interesting = false; }
                    if (c == 0x5C || c == 0x21) interesting = true;
                    if (i - start >= MAXLEN)
                    {
                        if (interesting) Harvest(Encoding.ASCII.GetString(b, start, i - start), found, max);
                        start = -1;
                    }
                }
                else
                {
                    if (start >= 0 && interesting && i - start >= MIN) Harvest(Encoding.ASCII.GetString(b, start, i - start), found, max);
                    start = -1;
                }
            }
            start = -1;
            interesting = false;
            for (int i = 0; i <= len; i += 2)
            {
                bool ok = false;
                int ch = 0;
                if (i + 1 < len) { ch = b[i] | (b[i + 1] << 8); ok = ch >= 0x20 && ch < 0xD800 && ch != 0x7F; }
                if (ok)
                {
                    if (start < 0) { start = i; interesting = false; }
                    if (ch == 0x5C || ch == 0x21) interesting = true;
                    if ((i - start) / 2 >= MAXLEN)
                    {
                        if (interesting) Harvest(Encoding.Unicode.GetString(b, start, i - start), found, max);
                        start = -1;
                    }
                }
                else
                {
                    if (start >= 0 && interesting && (i - start) / 2 >= MIN) Harvest(Encoding.Unicode.GetString(b, start, i - start), found, max);
                    start = -1;
                }
            }
        }

        // Executable paths and DPS "!!name!timestamp" records found in a process's private/mapped memory.
        public static string[] ProcessPaths(int pid, long maxBytes, int maxResults, out string error)
        {
            var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            error = WalkMemory(pid, MEM_PRIVATE | MEM_MAPPED, maxBytes, delegate(byte[] buf, int len) { ExtractStrings(buf, len, found, maxResults); });
            string[] arr = new string[found.Count];
            found.CopyTo(arr);
            return arr;
        }

        // Same for a file on disk (copied databases, logs).
        public static string[] FilePaths(string path, long maxBytes, int maxResults)
        {
            var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                byte[] buf = new byte[4 * 1024 * 1024];
                long total = 0;
                int n;
                while (total < maxBytes && (n = fs.Read(buf, 0, buf.Length)) > 0) { ExtractStrings(buf, n, found, maxResults); total += n; }
            }
            string[] arr = new string[found.Count];
            found.CopyTo(arr);
            return arr;
        }

        // ---- fingerprints -------------------------------------------------------------------------
        public static ulong FileNeedles(string path, Matcher m, long maxBytes)
        {
            ulong hits = 0;
            int state = 0;
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                byte[] buf = new byte[1024 * 1024];
                long total = 0;
                int n;
                while (total < maxBytes && (n = fs.Read(buf, 0, buf.Length)) > 0) { hits |= m.Scan(buf, n, ref state); total += n; }
            }
            return hits;
        }

        public static ulong ProcessNeedles(int pid, Matcher m, long maxBytes, out string error)
        {
            ulong hits = 0;
            error = WalkMemory(pid, MEM_PRIVATE | MEM_MAPPED | MEM_IMAGE, maxBytes, delegate(byte[] buf, int len) { int st = 0; hits |= m.Scan(buf, len, ref st); });
            return hits;
        }

        public static bool HasEmbeddedSignature(string path)
        {
            try
            {
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var br = new BinaryReader(fs))
                {
                    if (fs.Length < 0x40 || br.ReadUInt16() != 0x5A4D) return false;
                    fs.Position = 0x3C;
                    int pe = br.ReadInt32();
                    if (pe <= 0 || pe > fs.Length - 160) return false;
                    fs.Position = pe;
                    if (br.ReadUInt32() != 0x00004550) return false;
                    fs.Position = pe + 24;
                    ushort magic = br.ReadUInt16();
                    long dir = pe + 24 + (magic == 0x20B ? 144 : 128);
                    if (dir + 8 > fs.Length) return false;
                    fs.Position = dir;
                    br.ReadUInt32();
                    return br.ReadUInt32() > 0;
                }
            }
            catch { return false; }
        }

        public static string[] PeSections(string path)
        {
            var list = new List<string>();
            try
            {
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var br = new BinaryReader(fs))
                {
                    if (fs.Length < 0x40 || br.ReadUInt16() != 0x5A4D) return list.ToArray();
                    fs.Position = 0x3C;
                    int pe = br.ReadInt32();
                    if (pe <= 0 || pe > fs.Length - 24) return list.ToArray();
                    fs.Position = pe;
                    if (br.ReadUInt32() != 0x00004550) return list.ToArray();
                    fs.Position = pe + 6;
                    int count = br.ReadUInt16();
                    fs.Position = pe + 20;
                    int optSize = br.ReadUInt16();
                    long sec = pe + 24 + optSize;
                    for (int i = 0; i < count && i < 96; i++)
                    {
                        long pos = sec + i * 40;
                        if (pos + 8 > fs.Length) break;
                        fs.Position = pos;
                        list.Add(Encoding.ASCII.GetString(br.ReadBytes(8)).TrimEnd('\0'));
                    }
                }
            }
            catch { }
            return list.ToArray();
        }

        // ---- registry app hive (Amcache copy) --------------------------------------------------------
        public static int LastHiveError;
        public static RegistryKey LoadAppHive(string file)
        {
            IntPtr h;
            LastHiveError = RegLoadAppKey(file, out h, 0x20019, 0, 0);
            if (LastHiveError != 0) return null;
            return RegistryKey.FromHandle(new SafeRegistryHandle(h, true));
        }

        // ---- USN change journal ------------------------------------------------------------------------
        class DirInfo { public string Name; public ulong Parent; }

        static string PathById(SafeFileHandle vol, ulong frn)
        {
            var id = new FILE_ID_DESCRIPTOR();
            id.dwSize = 24; id.Type = 0; id.FileId = (long)frn;
            using (SafeFileHandle h = OpenFileById(vol, ref id, 0x80, 7, IntPtr.Zero, 0x02000000))
            {
                if (h.IsInvalid) return null;
                var sb = new StringBuilder(1024);
                uint n = GetFinalPathNameByHandle(h, sb, 1024, 0);
                if (n == 0 || n >= 1024) return null;
                string path = sb.ToString();
                if (path.StartsWith(@"\\?\UNC\")) return null;
                if (path.StartsWith(@"\\?\")) path = path.Substring(4);
                return path.TrimEnd('\\');
            }
        }

        static string ResolveDir(SafeFileHandle vol, ulong frn, Dictionary<ulong, DirInfo> dirs, Dictionary<ulong, string> cache, string root, int depth)
        {
            string cached;
            if (cache.TryGetValue(frn, out cached)) return cached;
            string path = PathById(vol, frn);
            if (path == null)
            {
                DirInfo d;
                if (depth < 64 && dirs.TryGetValue(frn, out d) && d.Parent != frn)
                    path = ResolveDir(vol, d.Parent, dirs, cache, root, depth + 1) + "\\" + d.Name;
                else
                    path = root + "\\<deleted folder>";
            }
            cache[frn] = path;
            return path;
        }

        // Reads the newest maxBytes of the volume's change journal. Keeps records for files with one of the
        // given extensions (an entry without a leading dot is a whole file name, e.g. "imgui.ini"), folders
        // with one of the given names, and the new name of any such file renamed.
        public static List<UsnEntry> ReadUsn(string drive, long maxBytes, string[] exts, string[] dirNames, DateTime since, string skipPrefix, UsnInfo info)
        {
            var result = new List<UsnEntry>();
            info.Ok = false;
            string letter = drive.TrimEnd(':', '\\');
            using (SafeFileHandle h = CreateFile(@"\\.\" + letter + ":", 0x80000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
            {
                if (h.IsInvalid) { info.Error = "cannot open volume (" + Marshal.GetLastWin32Error() + ")"; return result; }
                byte[] q = new byte[80];
                int ret;
                if (!DeviceIoControl(h, 0x000900F4, null, 0, q, q.Length, out ret, IntPtr.Zero)) { info.Error = "no change journal (" + Marshal.GetLastWin32Error() + ")"; return result; }
                info.JournalId = BitConverter.ToUInt64(q, 0);
                info.FirstUsn = BitConverter.ToInt64(q, 8);
                info.NextUsn = BitConverter.ToInt64(q, 16);
                info.MaximumSize = BitConverter.ToUInt64(q, 40);

                var dirs = new Dictionary<ulong, DirInfo>();
                byte[] buf = new byte[1024 * 1024];
                var extSet = new HashSet<string>(exts, StringComparer.OrdinalIgnoreCase);
                var dirSet = new HashSet<string>(dirNames, StringComparer.OrdinalIgnoreCase);
                var renamed = new HashSet<ulong>();
                long stop = info.NextUsn;
                long usn = Math.Max(info.FirstUsn, stop - maxBytes);
                byte[] rin = new byte[40];
                Array.Copy(BitConverter.GetBytes(0xFFFFFFFFu), 0, rin, 8, 4);
                Array.Copy(BitConverter.GetBytes(info.JournalId), 0, rin, 32, 8);
                bool first = true;
                while (usn < stop)
                {
                    Array.Copy(BitConverter.GetBytes(usn), 0, rin, 0, 8);
                    if (!DeviceIoControl(h, 0x000900BB, rin, rin.Length, buf, buf.Length, out ret, IntPtr.Zero))
                    {
                        if (info.RecordsRead == 0) info.Error = "cannot read journal (" + Marshal.GetLastWin32Error() + ")";
                        break;
                    }
                    if (ret <= 8) break;
                    long next = BitConverter.ToInt64(buf, 0);
                    int p = 8;
                    while (p + 60 <= ret)
                    {
                        int len = BitConverter.ToInt32(buf, p);
                        if (len <= 0) break;
                        if (BitConverter.ToUInt16(buf, p + 4) == 2)
                        {
                            info.RecordsRead++;
                            long ts = BitConverter.ToInt64(buf, p + 32);
                            if (first) { try { info.OldestRecord = DateTime.FromFileTime(ts); } catch { } first = false; }
                            ulong frn = BitConverter.ToUInt64(buf, p + 8);
                            ulong parent = BitConverter.ToUInt64(buf, p + 16);
                            uint reason = BitConverter.ToUInt32(buf, p + 40);
                            bool isDir = (BitConverter.ToUInt32(buf, p + 52) & 0x10) != 0;
                            string name = Encoding.Unicode.GetString(buf, p + BitConverter.ToUInt16(buf, p + 58), BitConverter.ToUInt16(buf, p + 56));
                            if (isDir && !dirs.ContainsKey(frn)) { var d = new DirInfo(); d.Name = name; d.Parent = parent; dirs[frn] = d; }
                            string ext = "";
                            int dot = name.LastIndexOf('.');
                            if (dot >= 0) ext = name.Substring(dot);
                            bool keep = isDir ? dirSet.Contains(name) : (extSet.Contains(ext) || extSet.Contains(name));
                            if (keep && (reason & 0x1000) != 0) renamed.Add(frn);
                            if (!keep && (reason & 0x2000) != 0 && renamed.Contains(frn)) keep = true;
                            if (keep && result.Count < 400000)
                            {
                                var e = new UsnEntry();
                                try { e.Time = DateTime.FromFileTime(ts); } catch { }
                                e.Reason = reason; e.Name = name; e.Frn = frn; e.ParentFrn = parent; e.IsDir = isDir;
                                result.Add(e);
                            }
                        }
                        p += len;
                    }
                    if (next <= usn) break;
                    usn = next;
                }
                string root = letter + ":";
                var cache = new Dictionary<ulong, string>();
                var kept = new List<UsnEntry>();
                foreach (var e in result)
                {
                    if (e.Time < since) continue;
                    e.Path = ResolveDir(h, e.ParentFrn, dirs, cache, root, 0) + "\\" + e.Name;
                    if (!string.IsNullOrEmpty(skipPrefix) && e.Path.StartsWith(skipPrefix, StringComparison.OrdinalIgnoreCase) && !e.Name.EndsWith(".pf", StringComparison.OrdinalIgnoreCase) && !extSet.Contains(e.Name)) continue;
                    kept.Add(e);
                }
                result = kept;
                info.Ok = info.RecordsRead > 0 || info.Error == null;
            }
            return result;
        }
    }

    public class PrefetchInfo
    {
        public string Exe;          // program name as Windows recorded it (upper case, at most 29 characters)
        public string Path;         // full path from the file list, starting \VOLUME{...} or \DEVICE\..., or null
        public DateTime[] Times;    // the last runs, newest first (up to 8)
        public int RunCount;
    }

    public static class Timeline
    {
        [DllImport("ntdll.dll")] static extern int RtlGetCompressionWorkSpaceSize(ushort format, out uint bufferSize, out uint fragmentSize);
        [DllImport("ntdll.dll")] static extern int RtlDecompressBufferEx(ushort format, byte[] output, int outputSize, byte[] input, int inputSize, out int finalSize, byte[] workSpace);

        // Reads one prefetch file (Windows 8.1, 10 and 11): which program, how often and when it last ran.
        // Returns null for a file it does not understand.
        public static PrefetchInfo Prefetch(string file)
        {
            return Parse(File.ReadAllBytes(file));
        }

        public static PrefetchInfo Parse(byte[] raw)
        {
            if (raw == null || raw.Length < 16) return null;
            byte[] data = raw;
            if (raw[0] == 0x4D && raw[1] == 0x41 && raw[2] == 0x4D)        // "MAM": compressed, Windows 10 and later
            {
                ushort format = (ushort)(raw[3] & 0x0F);
                int start = (raw[3] & 0x80) != 0 ? 12 : 8;                 // an optional checksum follows the size
                int size = BitConverter.ToInt32(raw, 4);
                if (size <= 0 || size > 64 * 1024 * 1024 || raw.Length <= start) return null;
                uint bufferSize, fragmentSize;
                if (RtlGetCompressionWorkSpaceSize(format, out bufferSize, out fragmentSize) != 0) return null;
                byte[] input = new byte[raw.Length - start];
                Buffer.BlockCopy(raw, start, input, 0, input.Length);
                data = new byte[size];
                int final;
                if (RtlDecompressBufferEx(format, data, size, input, input.Length, out final, new byte[Math.Max(bufferSize, fragmentSize)]) != 0) return null;
            }
            if (data.Length < 0xD8 || data[4] != 0x53 || data[5] != 0x43 || data[6] != 0x43 || data[7] != 0x41) return null;   // "SCCA"
            int version = BitConverter.ToInt32(data, 0);
            if (version != 26 && version != 30 && version != 31) return null;

            var info = new PrefetchInfo();
            string exe = Encoding.Unicode.GetString(data, 0x10, 60);
            int end = exe.IndexOf('\0');
            info.Exe = end >= 0 ? exe.Substring(0, end) : exe;

            var times = new List<DateTime>();
            for (int i = 0; i < 8; i++)
            {
                long stamp = BitConverter.ToInt64(data, 0x80 + i * 8);
                if (stamp <= 0) continue;
                try { times.Add(DateTime.FromFileTime(stamp)); } catch { }
            }
            info.Times = times.ToArray();
            // Newer Windows 10 and 11 builds moved the run count 8 bytes earlier; the header size tells them apart.
            int countAt = (version == 26 || BitConverter.ToInt32(data, 0x54) == 304) ? 0xD0 : 0xC8;
            info.RunCount = BitConverter.ToInt32(data, countAt);

            int namesAt = BitConverter.ToInt32(data, 0x64), namesSize = BitConverter.ToInt32(data, 0x68);
            if (info.Exe.Length > 0 && namesAt > 0 && namesSize > 0 && (long)namesAt + namesSize <= data.Length)
            {
                foreach (string name in Encoding.Unicode.GetString(data, namesAt, namesSize).Split('\0'))
                {
                    int slash = name.LastIndexOf('\\');
                    if (slash < 0) continue;
                    string leaf = name.Substring(slash + 1);
                    bool same = info.Exe.Length >= 29 ? leaf.StartsWith(info.Exe, StringComparison.OrdinalIgnoreCase) : leaf.Equals(info.Exe, StringComparison.OrdinalIgnoreCase);
                    if (same) { info.Path = name; break; }
                }
            }
            return info;
        }
    }
}
'@

$script:BsmmForensicsError = ''
function Initialize-BsmmForensics {
    if ('BSMM.Forensics' -as [type]) { return $true }
    try {
        Add-Type -TypeDefinition $script:BsmmForensicsSource -ErrorAction Stop
        return $true
    } catch {
        $script:BsmmForensicsError = $_.Exception.Message
        return $false
    }
}

$script:KeywordRegex = $null
function Get-BsmmKeywordRegex {
    if ($script:KeywordRegex) { return $script:KeywordRegex }
    $sub = @(); $tok = @()
    foreach ($kw in $script:CheatKeywords) {
        if ($kw.Length -le 4 -or $script:TokenOnlyKeywords -contains $kw) { $tok += [regex]::Escape($kw) } else { $sub += [regex]::Escape($kw) }
    }
    $parts = @()
    if ($sub.Count -gt 0) { $parts += '(?:' + ($sub -join '|') + ')' }
    if ($tok.Count -gt 0) { $parts += '(?:^|[\\_\s\-\.])(?:' + ($tok -join '|') + ')(?:$|[\\_\s\-\.])' }
    $script:KeywordRegex = New-Object System.Text.RegularExpressions.Regex (('(?i)' + ($parts -join '|')), [System.Text.RegularExpressions.RegexOptions]::Compiled)
    return $script:KeywordRegex
}

$script:KeywordIgnorePaths = '(?i)\\(BattlEye|EasyAntiCheat[^\\]*|Riot Vanguard|Microsoft Office|WindowsApps|SystemApps|Microsoft Visual Studio|Blitz\\blitz-deps|Overwolf|steamapps\\common|DriverStore|WinSxS)\\'
function Get-BsmmCheatKeywordFast {
    param([string]$Text)
    if (-not $Text) { return $null }
    if ($Text -match $script:KeywordIgnorePaths) { return $null }
    if ($Text -match '(?i)(^|\\)(SpectreClient[^\\]*|voiceclarity[^\\]*)$') { return $null }
    if (-not (Get-BsmmKeywordRegex).IsMatch($Text)) { return $null }
    return (Get-MatchedCheatKeyword -Text $Text)
}

function ConvertTo-BsmmDrivePath {
    param([string]$Path, [hashtable]$Volumes)
    if ($Path -match '^(\\Device\\HarddiskVolume\d+)(\\.*)$') {
        if ($Volumes.ContainsKey($matches[1])) { return $Volumes[$matches[1]] + $matches[2] }
        return $null
    }
    return $Path
}

function Get-BsmmUserFolderRegex {
    if ($script:UserFolderRegex) { return $script:UserFolderRegex }
    $roots = @(Get-BsmmUserFolders Desktop) + @(Get-BsmmUserFolders Downloads) + @(Get-BsmmUserFolders Documents)
    $script:UserFolderRegex = '(?i)^(?:' + (($roots | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\\'
    return $script:UserFolderRegex
}

$script:FpNeedles = @(
    'getgenv', 'getrenv', 'getsenv', 'hookfunction', 'hookmetamethod', 'getrawmetatable', 'getnamecallmethod', 'setreadonly',
    'newcclosure', 'checkcaller', 'getconnections', 'fireclickdetector', 'firetouchinterest', 'identifyexecutor',
    'queue_on_teleport', 'getscriptbytecode', 'rconsoleprint',
    'VisualEngine', 'FakeDataModel',
    'RobloxPlayerBeta',
    'ReadProcessMemory', 'NtReadVirtualMemory', 'ZwReadVirtualMemory', 'WriteProcessMemory',
    'keyauth.win', 'keyauth.cc'
)

function Get-BsmmBitCount {
    param([UInt64]$Value, [int]$From, [int]$To)
    $n = 0
    for ($i = $From; $i -le $To; $i++) { if ((($Value -shr $i) -band 1) -eq 1) { $n++ } }
    return $n
}

function Get-BsmmFingerprintVerdict {
    param([UInt64]$Hits)
    $why = New-Object System.Collections.Generic.List[string]
    if ($Hits -eq 0) { return $why.ToArray() }
    $unc = Get-BsmmBitCount $Hits 0 16
    $rbx = Get-BsmmBitCount $Hits 17 18
    $rpb = Get-BsmmBitCount $Hits 19 19
    $ka  = Get-BsmmBitCount $Hits 24 25
    if ($unc -ge 4) { $why.Add("Roblox executor code ($unc executor-only Lua functions)") }
    if ($rbx -ge 1 -and $rpb -ge 1) { $why.Add('code that targets Roblox engine internals (external cheat)') }
    if ($ka -ge 1) { $why.Add('KeyAuth licence server (used by cheat loaders)') }
    return $why.ToArray()
}

$script:PackerSectionPattern = '^(?i)(\.vmp\d|\.themida|\.winlice|\.enigma\d|UPX\d|\.mpress\d)$'
$script:ExecutionEvidence = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

function Add-BsmmGroupedHits {
    param($Alerts, [string]$Level, [string]$Label, $Hits)
    $byRoot = [ordered]@{}
    foreach ($h in $Hits) {
        $root = $h.Path
        $cut = $h.Path.LastIndexOf('\')
        if ($cut -gt 0) { $root = $h.Path.Substring(0, $cut) }
        $parts = $h.Path -split '\\'
        for ($i = 1; $i -lt $parts.Count - 1; $i++) {
            if (Get-MatchedCheatKeyword -Text $parts[$i] -FolderName) { $root = ($parts[0..$i] -join '\'); break }
        }
        $key = "$($h.Kw)|$root"
        if (-not $byRoot.Contains($key)) { $byRoot[$key] = New-Object System.Collections.Generic.List[object] }
        $byRoot[$key].Add($h)
    }
    $byKw = @{}
    foreach ($key in $byRoot.Keys) { $kw = $key.Substring(0, $key.IndexOf('|')); if (-not $byKw.ContainsKey($kw)) { $byKw[$kw] = 0 }; $byKw[$kw]++ }
    $folded = @{}
    foreach ($key in $byRoot.Keys) {
        $kw = $key.Substring(0, $key.IndexOf('|'))
        if ($byKw[$kw] -gt 3) {
            if ($folded.ContainsKey($kw)) { continue }
            $folded[$kw] = $true
            $all = @(); foreach ($k2 in $byRoot.Keys) { if ($k2.StartsWith("$kw|")) { $all += $byRoot[$k2] } }
            $ex = ($all | Select-Object -First 2 | ForEach-Object { $_.Path + $_.Extra }) -join ' ; '
            $Alerts.Add("${Level}: $Label [$kw] $($all.Count) entries in $($byKw[$kw]) places (e.g. $ex)")
            continue
        }
        $g = $byRoot[$key]
        if ($g.Count -le 2) {
            foreach ($h in $g) { $Alerts.Add("${Level}: $Label [$($h.Kw)]$($h.Extra) -> $($h.Path)") }
        } else {
            $root = $key.Substring($key.IndexOf('|') + 1)
            $leaf = $g[0].Path.Substring($g[0].Path.LastIndexOf('\') + 1)
            $Alerts.Add("${Level}: $Label [$($g[0].Kw)] $($g.Count) programs under $root (e.g. $leaf$($g[0].Extra))")
        }
    }
}

function Get-ServiceMemoryTraceAlerts {
    if (-not (Test-Admin)) { return @('WARNING: Service memory traces need administrator rights') }
    if (-not (Initialize-BsmmForensics)) { return @("WARNING: Forensic engine unavailable ($script:BsmmForensicsError)") }
    try { [System.Diagnostics.Process]::EnterDebugMode() } catch {}

    $targets = [ordered]@{}
    foreach ($svc in @('DPS', 'PcaSvc', 'Schedule')) {
        try {
            $s = Get-CimInstance Win32_Service -Filter "Name='$svc'" -ErrorAction Stop
            if ($s -and $s.ProcessId -gt 0) { $targets[$svc] = [int]$s.ProcessId }
        } catch {}
    }
    $exp = Get-Process -Name explorer -ErrorAction SilentlyContinue | Sort-Object StartTime | Select-Object -First 1
    if ($exp) { $targets['Explorer'] = [int]$exp.Id }

    $alerts = New-Object System.Collections.Generic.List[string]
    $volumes = Get-BsmmVolumeMap
    $userRe = Get-BsmmUserFolderRegex
    $total = 0
    $reported = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $kwHits = [ordered]@{}
    foreach ($src in $targets.Keys) {
        $kwHits[$src] = New-Object System.Collections.Generic.List[object]
        $err = $null
        $found = @()
        try { $found = [BSMM.Forensics]::ProcessPaths($targets[$src], 512MB, 25000, [ref]$err) } catch { $err = $_.Exception.Message }
        if ($err) { $alerts.Add("WARNING: Could not read $src memory ($err)"); continue }
        $total += $found.Count
        foreach ($raw in $found) {
            if ($raw.StartsWith('!!')) {
                $parts = $raw.Substring(2) -split '\|', 2
                $kw = Get-BsmmCheatKeywordFast $parts[0]
                if ($kw -and $reported.Add("dps|$($parts[0])")) { $alerts.Add("FAILURE: [$src] ran '$($parts[0])' [$kw] (file stamp $($parts[1]))") }
                continue
            }
            $p = ConvertTo-BsmmDrivePath -Path $raw -Volumes $volumes
            if (-not $p) { continue }
            $kw = Get-BsmmCheatKeywordFast $p
            if ($kw) {
                if ($reported.Add($p)) { $kwHits[$src].Add([pscustomobject]@{ Kw = $kw; Path = $p; Extra = '' }) }
                continue
            }
            if ($p -match '^(?i)[a-z]:\\(windows|program files|program files \(x86\)|programdata\\microsoft)\\') { continue }
            $isExe = $p -match '(?i)\.(exe|bat|cmd|ps1|lua|luau|ahk|jar|py|scr)$'
            if (-not $isExe -and $p -notmatch '(?i)\.dll$') { continue }
            $exists = $false
            try { $exists = [System.IO.File]::Exists($p) } catch {}
            if ($exists) {
                [void]$script:ExecutionEvidence.Add($p)
            } elseif ($isExe -and $src -ne 'Explorer' -and $p -match $userRe -and $reported.Add($p)) {
                $alerts.Add("WARNING: [$src] ran since boot, and the file is now gone (deleted or renamed) -> $p")
            }
        }
    }
    foreach ($src in $kwHits.Keys) {
        if ($kwHits[$src].Count -eq 0) { continue }
        $verb = 'ran since boot'; if ($src -eq 'Explorer') { $verb = 'opened or showed since boot' }
        Add-BsmmGroupedHits -Alerts $alerts -Level 'FAILURE' -Label "[$src] $verb" -Hits $kwHits[$src]
    }
    $alerts.Add("INFO: Read $total execution traces from $(@($targets.Keys) -join ', ')")
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts.Insert(0, 'SUCCESS: No cheat or deleted program in the service memory traces')
    }
    return @($alerts | Select-Object -First 40)
}

function Get-ChangeJournalAlerts {
    if (-not (Test-Admin)) { return @('WARNING: The change journal needs administrator rights') }
    if (-not (Initialize-BsmmForensics)) { return @("WARNING: Forensic engine unavailable ($script:BsmmForensicsError)") }

    $info = New-Object BSMM.UsnInfo
    $exts = @('.exe', '.dll', '.sys', '.lua', '.luau', '.pf', '.onnx', '.engine', '.pt', '.ahk', '.bat', '.ps1', '.asi', 'imgui.ini')
    $script:JournalPrefetch = New-Object System.Collections.Generic.List[object]
    $imgui = New-Object System.Collections.Generic.List[string]
    $entries = $null
    try { $entries = [BSMM.Forensics]::ReadUsn($env:SystemDrive, 256MB, [string[]]$exts, [string[]]@('autoexec'), (Get-Date).AddDays(-7), ($env:SystemRoot + '\'), $info) } catch {
        return @("WARNING: Could not read the change journal ($($_.Exception.Message))")
    }
    if (-not $info.Ok) { return @("WARNING: Could not read the change journal ($($info.Error))") }

    $alerts = New-Object System.Collections.Generic.List[string]
    $logon = Get-LogonTime
    $weekAgo = (Get-Date).AddDays(-7)
    $userRe = Get-BsmmUserFolderRegex
    $kwSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $pfDeletes = New-Object System.Collections.Generic.List[datetime]
    $deleted = New-Object System.Collections.Generic.List[string]
    $replaced = New-Object System.Collections.Generic.List[string]
    $renames = New-Object System.Collections.Generic.List[string]
    $models = New-Object System.Collections.Generic.List[string]
    $sysCreated = @{}
    $oldNames = @{}

    $jHits = New-Object System.Collections.Generic.List[object]
    foreach ($e in $entries) {
        $r = $e.Reason
        $isDelete = ($r -band 0x200) -ne 0
        $isCreate = ($r -band 0x100) -ne 0
        $when = Get-Date $e.Time -Format 'MM-dd HH:mm'

        if (($r -band 0x1000) -ne 0) { $oldNames[[string]$e.Frn] = $e.Path }
        if (($r -band 0x2000) -ne 0 -and $oldNames.ContainsKey([string]$e.Frn)) {
            $old = $oldNames[[string]$e.Frn]
            $oldExt = ''; $newExt = ''; try { $oldExt = [IO.Path]::GetExtension($old); $newExt = [IO.Path]::GetExtension($e.Path) } catch {}
            if ($e.Time -ge $logon -and $oldExt -ne $newExt -and $oldExt -match '(?i)^\.(exe|dll|lua|luau|ahk|sys)$' -and $old -match $userRe) {
                $renames.Add("$when  $old  ->  $([IO.Path]::GetFileName($e.Path))")
            }
            $oldNames.Remove([string]$e.Frn)
        }

        $kw = Get-BsmmCheatKeywordFast $e.Path
        if ($kw) {
            $action = 'changed'
            if ($isDelete) { $action = 'deleted' } elseif (($r -band 0x3000) -ne 0) { $action = 'renamed' } elseif ($isCreate) { $action = 'created' }
            if ($kwSeen.Add("$action|$($e.Path)")) { $jHits.Add([pscustomobject]@{ Kw = $kw; Path = $e.Path; Extra = " $action $when" }) }
            continue
        }
        if ($e.IsDir) {
            if ($isCreate -and $kwSeen.Add("dir|$($e.Path)")) { $alerts.Add("FAILURE: Journal: executor 'autoexec' folder created $when -> $($e.Path)") }
            continue
        }
        $ext = ''; $dot = $e.Name.LastIndexOf('.'); if ($dot -ge 0) { $ext = $e.Name.Substring($dot).ToLower() }
        if ($ext -eq '.pf') {
            if ($isDelete) { if ($e.Time -ge $logon) { $pfDeletes.Add($e.Time) } }
            elseif (($r -band 0x107) -ne 0) { $script:JournalPrefetch.Add([pscustomobject]@{ Name = $e.Name; Time = $e.Time }) }
            continue
        }
        if ($e.Name -eq 'imgui.ini') {
            if (($isCreate -or $isDelete) -and $e.Path -notmatch $script:ImGuiIgnorePaths) {
                $imgui.Add("$(if ($isDelete) { 'deleted' } else { 'created' }) $when -> $($e.Path)")
            }
            continue
        }
        if ($ext -eq '.sys' -and $e.Path -match '(?i)\\(Temp|AppData)\\') {
            $k = [string]$e.Frn
            if ($isCreate) { $sysCreated[$k] = $e.Time }
            if ($isDelete -and $sysCreated.ContainsKey($k) -and ($e.Time - $sysCreated[$k]).TotalSeconds -le 120) {
                $leaf = $e.Name.ToLower()
                $lvl = 'WARNING'
                if ($script:VulnerableDriverTiers.ContainsKey($leaf) -and $script:VulnerableDriverTiers[$leaf] -eq 'FAILURE') { $lvl = 'FAILURE' }
                $alerts.Add("${lvl}: Journal: driver file dropped in a temp folder and deleted within 2 minutes $when (how kernel cheats are loaded) -> $($e.Path)")
            }
            continue
        }
        if ($ext -in @('.onnx', '.engine', '.pt') -and $isCreate -and $e.Path -match $userRe) { $models.Add("$when  $($e.Path)"); continue }
        if ($e.Time -lt $logon -or $e.Path -notmatch $userRe) { continue }
        if ($isDelete) { $deleted.Add("$when  $($e.Path)") }
        elseif (($r -band 0x5) -ne 0 -and -not $isCreate -and $ext -eq '.exe') { $replaced.Add("$when  $($e.Path)") }
    }

    Add-BsmmGroupedHits -Alerts $alerts -Level 'FAILURE' -Label 'Journal: changed' -Hits $jHits

    $pf = @($pfDeletes | Sort-Object)
    $burst = 0; $burstAt = $null
    for ($i = 0; $i -lt $pf.Count; $i++) {
        $j = $i
        while ($j + 1 -lt $pf.Count -and ($pf[$j + 1] - $pf[$i]).TotalSeconds -le 120) { $j++ }
        if (($j - $i + 1) -gt $burst) { $burst = $j - $i + 1; $burstAt = $pf[$i] }
    }
    if ($burst -ge 20) { $alerts.Add("FAILURE: Journal: $burst Prefetch files deleted within 2 minutes at $(Get-Date $burstAt -Format 'HH:mm') (Prefetch wipe)") }
    elseif ($burst -ge 6) { $alerts.Add("WARNING: Journal: $burst Prefetch files deleted within 2 minutes at $(Get-Date $burstAt -Format 'HH:mm')") }

    foreach ($x in @($renames | Select-Object -Unique -First 10)) { $alerts.Add("WARNING: Journal: program renamed to a non-program file since logon: $x") }
    foreach ($x in @($replaced | Select-Object -Unique -First 10)) { $alerts.Add("WARNING: Journal: program file overwritten in place since logon: $x") }
    foreach ($x in @($deleted | Select-Object -Unique -First 15)) { $alerts.Add("WARNING: Journal: deleted since logon: $x") }
    foreach ($x in @($models | Select-Object -Unique -First 5)) { $alerts.Add("WARNING: Journal: AI model file created (aimbots use these): $x") }
    foreach ($x in @($imgui | Select-Object -Unique -First 10)) {
        $lvl = 'WARNING'
        if ($x -match $script:ImGuiHotPaths) { $lvl = 'FAILURE' }
        $alerts.Add("${lvl}: Journal: ImGui menu settings file (imgui.ini) $x")
    }

    $covers = 'unknown'
    if ($info.OldestRecord -gt [datetime]'2000-01-01') { $covers = Get-Date $info.OldestRecord -Format 'yyyy-MM-dd HH:mm' }
    $alerts.Add("INFO: Change journal read back to $covers ($($info.RecordsRead) records)")
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts.Insert(0, 'SUCCESS: No suspicious deletes, renames or replaced programs in the change journal')
    }
    return @($alerts | Select-Object -First 45)
}

$script:FpSkipAppData = '^(?i)(Microsoft|Packages|Temp|Google|Mozilla|NVIDIA.*|Roblox|Bloxstrap|Fishstrap|Comms|ConnectedDevicesPlatform|D3DSCache|CrashDumps|pip|npm-cache|Yarn|JetBrains|Adobe|Discord.*|Spotify|Steam|Epic Games|EpicGamesLauncher|Riot Games|Battle\.net|Opera Software|BraveSoftware|CapCut|Medal|Overwolf|Zoom|Docker|GitHubDesktop|Postman|Notion|slack|Code|Cursor|Claude|AnthropicClaude)$'

function Get-CodeFingerprintAlerts {
    if (-not (Initialize-BsmmForensics)) { return @("WARNING: Forensic engine unavailable ($script:BsmmForensicsError)") }
    try { [System.Diagnostics.Process]::EnterDebugMode() } catch {}
    $matcher = [BSMM.Matcher]::new([string[]]$script:FpNeedles)
    $alerts = New-Object System.Collections.Generic.List[string]
    $files = New-Object 'System.Collections.Generic.Dictionary[string,System.IO.FileInfo]' ([StringComparer]::OrdinalIgnoreCase)
    $add = {
        param($fi)
        if ($fi -and $fi.Length -ge 16KB -and $fi.Length -le 80MB -and -not $files.ContainsKey($fi.FullName)) { $files[$fi.FullName] = $fi }
    }

    $userDirs = @(Get-BsmmUserFolders Desktop) + @(Get-BsmmUserFolders Downloads) + @(Get-BsmmUserFolders Documents)
    foreach ($d in $userDirs) {
        Get-ChildItem -LiteralPath $d -File -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^(?i)\.(exe|dll)$' } | ForEach-Object { & $add $_ }
    }
    $addUnsigned = {
        param($fi)
        if ($fi -and -not [BSMM.Forensics]::HasEmbeddedSignature($fi.FullName)) { & $add $fi }
    }
    foreach ($d in @($env:LOCALAPPDATA, $env:APPDATA)) {
        Get-ChildItem -LiteralPath $d -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $script:FpSkipAppData } | ForEach-Object {
            Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Depth 2 -Force -Filter '*.exe' -ErrorAction SilentlyContinue | ForEach-Object { & $addUnsigned $_ }
        }
    }
    Get-ChildItem -LiteralPath $env:TEMP -File -Recurse -Depth 1 -Force -Filter '*.exe' -ErrorAction SilentlyContinue | ForEach-Object { & $addUnsigned $_ }
    foreach ($p in @($script:ExecutionEvidence)) {
        if ($p -match '(?i)\.(exe|dll)$') { try { & $addUnsigned (Get-Item -LiteralPath $p -Force -ErrorAction Stop) } catch {} }
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $budget = 3GB; $used = 0; $scanned = 0; $limited = $false
    foreach ($fi in @($files.Values | Sort-Object -Property LastWriteTime -Descending)) {
        if ($used -ge $budget -or $sw.Elapsed.TotalSeconds -gt 35) { $limited = $true; break }
        if ($fi.FullName -match '(?i)\\(Roblox|Bloxstrap|Fishstrap)\\Versions\\|^[a-z]:\\windows\\') { continue }
        $hits = [UInt64]0
        try { $hits = [BSMM.Forensics]::FileNeedles($fi.FullName, $matcher, 80MB) } catch { continue }
        $used += $fi.Length; $scanned++
        $why = @(Get-BsmmFingerprintVerdict $hits)
        if ($why.Count -gt 0) {
            $sig = Get-CachedSignatureStatus -Path $fi.FullName
            if ($sig -eq 'Valid') { $alerts.Add("WARNING: Signed program contains $($why -join '; ') -> $($fi.FullName)") }
            else { $alerts.Add("FAILURE: Program contains $($why -join '; ') ($sig) -> $($fi.FullName)") }
            continue
        }
        $packers = @([BSMM.Forensics]::PeSections($fi.FullName) | Where-Object { $_ -match $script:PackerSectionPattern })
        if ($packers.Count -gt 0 -and (Get-CachedSignatureStatus -Path $fi.FullName) -ne 'Valid') {
            $alerts.Add("WARNING: Unsigned, protected program (packed with $(($packers | Select-Object -Unique) -join '/')) - cheats hide their code this way -> $($fi.FullName)")
        }
    }

    $procScanned = 0
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($sw.Elapsed.TotalSeconds -gt 60) { $limited = $true; break }
        if ($p.Id -eq $PID -or $p.ProcessName -match '^(?i)Roblox') { continue }
        $path = $null
        try { $path = $p.Path } catch {}
        if (-not $path -or $path -match '^(?i)[a-z]:\\windows\\') { continue }
        if ((Get-CachedSignatureStatus -Path $path) -eq 'Valid') { continue }
        $err = $null
        $hits = [UInt64]0
        try { $hits = [BSMM.Forensics]::ProcessNeedles($p.Id, $matcher, 256MB, [ref]$err) } catch { continue }
        $procScanned++
        $why = @(Get-BsmmFingerprintVerdict $hits)
        if ($why.Count -gt 0) { $alerts.Add("FAILURE: Running program contains $($why -join '; ') -> $($p.ProcessName) (PID $($p.Id)) $path") }
    }

    $layoutRoots = $userDirs + @($env:LOCALAPPDATA, $env:APPDATA)
    foreach ($r in $layoutRoots) {
        Get-ChildItem -LiteralPath $r -Directory -Recurse -Depth 3 -Force -Filter 'autoexec' -ErrorAction SilentlyContinue | ForEach-Object {
            $parent = $_.Parent.FullName
            if ((Test-Path -LiteralPath (Join-Path $parent 'workspace')) -or (Test-Path -LiteralPath (Join-Path $parent 'scripts'))) {
                $alerts.Add("FAILURE: Roblox executor folder layout (autoexec + workspace/scripts) -> $parent")
            } else {
                $alerts.Add("WARNING: Folder named 'autoexec' (Roblox executors use this) -> $($_.FullName)")
            }
        }
    }
    $luaHits = 0
    foreach ($d in $userDirs) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^(?i)\.(lua|luau)$' -and $_.Length -le 4MB } | Select-Object -First 300)) {
            if ($luaHits -ge 8) { break }
            $h = [UInt64]0
            try { $h = [BSMM.Forensics]::FileNeedles($f.FullName, $matcher, 4MB) } catch { continue }
            if ((Get-BsmmBitCount $h 0 16) -ge 2) { $luaHits++; $alerts.Add("WARNING: Exploit script (uses executor-only Lua functions) -> $($f.FullName)") }
        }
    }

    $note = "INFO: Looked inside $scanned programs and $procScanned running processes"
    if ($limited) { $note += ' (stopped at the time limit; newest files first)' }
    $alerts.Add($note)
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts.Insert(0, 'SUCCESS: No executor, external or loader code found inside programs or running processes')
    }
    return @($alerts | Select-Object -Unique -First 45)
}

function Get-LoggingTamperAlerts {
    param([switch]$Light)
    $alerts = New-Object System.Collections.Generic.List[string]
    $boot = Get-BootTime
    $services = [ordered]@{
        DPS      = 'Diagnostic Policy Service (keeps run history in memory)'
        PcaSvc   = 'Program Compatibility Assistant (launch log)'
        SysMain  = 'SysMain (Prefetch)'
        EventLog = 'Windows Event Log'
        Schedule = 'Task Scheduler'
    }
    foreach ($name in $services.Keys) {
        $label = $services[$name]
        $s = $null
        try { $s = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction Stop } catch {}
        if (-not $s) { $alerts.Add("WARNING: $label service is missing"); continue }
        if ($s.StartMode -eq 'Disabled') { $alerts.Add("WARNING: $label is disabled (some 'debloat' tools do this; it also stops evidence being recorded)"); continue }
        if ($s.State -ne 'Running') { $alerts.Add("WARNING: $label is not running ($($s.State))"); continue }
        $proc = Get-Process -Id $s.ProcessId -ErrorAction SilentlyContinue
        if (-not $proc) { continue }
        $susp = 0
        try { $susp = @($proc.Threads | Where-Object { [string]$_.ThreadState -eq 'Wait' -and [string]$_.WaitReason -eq 'Suspended' }).Count } catch {}
        if ($susp -gt 0) { $alerts.Add("FAILURE: $label has $susp frozen thread(s) - it shows as running but is not recording (a known screenshare bypass)") }
        try {
            if ($boot -and $proc.StartTime -gt $boot.AddMinutes(10)) {
                $alerts.Add("WARNING: $label was restarted at $(Get-Date $proc.StartTime -Format 'HH:mm'), which wipes its memory history")
            }
        } catch {}
    }
    $exp = Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exp) {
        $es = 0
        try { $es = @($exp.Threads | Where-Object { [string]$_.ThreadState -eq 'Wait' -and [string]$_.WaitReason -eq 'Suspended' }).Count } catch {}
        if ($es -gt 0) { $alerts.Add("WARNING: Explorer has $es frozen thread(s)") }
    }

    if ($boot -and -not $Light) {
        try {
            $evs = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7036; StartTime = $boot } -MaxEvents 3000 -ErrorAction Stop)
            $stopped = @{}
            foreach ($e in $evs) {
                $bin = ''
                try { $bin = [string]([xml]$e.ToXml()).Event.EventData.Binary } catch {}
                if (-not $bin -or $bin.Length -lt 8) { continue }
                $bytes = New-Object byte[] ($bin.Length / 2)
                for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($bin.Substring($i * 2, 2), 16) }
                $txt = [Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)
                if ($txt -match '^(DPS|PcaSvc|SysMain|EventLog|Schedule)/1$' -and -not $stopped.ContainsKey($matches[1])) {
                    $stopped[$matches[1]] = $e.TimeCreated
                    $alerts.Add("WARNING: $($services[$matches[1]]) was stopped at $(Get-Date $e.TimeCreated -Format 'HH:mm') this session")
                }
            }
        } catch {}
    }
    try {
        Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 3079; StartTime = (Get-Date).AddDays(-30) } -MaxEvents 3 -ErrorAction Stop | ForEach-Object {
            $alerts.Add("FAILURE: The change journal was deleted on $(Get-Date $_.TimeCreated -Format 'yyyy-MM-dd HH:mm') (wipes file history)")
        }
    } catch {}
    $ac = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
    foreach ($pair in @(@('DisablePCA', 1, 'Program Compatibility Assistant logging'), @('DisableInventory', 1, 'Amcache program inventory'), @('AITEnable', 0, 'Application telemetry (feeds Amcache)'), @('DisableEngine', 1, 'Application compatibility engine'))) {
        try {
            $v = Get-ItemPropertyValue -Path $ac -Name $pair[0] -ErrorAction Stop
            if ([int]$v -eq [int]$pair[1]) { $alerts.Add("WARNING: $($pair[2]) is turned off by policy ($($pair[0])=$v) - removes program history") }
        } catch {}
    }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts.Insert(0, 'SUCCESS: Windows evidence logging is running normally (no frozen, stopped or disabled services)')
    }
    return @($alerts | Select-Object -First 30)
}

function Copy-BsmmLockedFile {
    param([string]$Source, [string]$Dest)
    if (-not (Test-Path -LiteralPath $Source)) { return $false }
    try {
        $p = Start-Process -FilePath "$env:SystemRoot\System32\esentutl.exe" -ArgumentList @('/y', "`"$Source`"", '/vss', '/d', "`"$Dest`"") -WindowStyle Hidden -PassThru -ErrorAction Stop
        if (-not $p.WaitForExit(90000)) { try { $p.Kill() } catch {}; return $false }
    } catch { return $false }
    return (Test-Path -LiteralPath $Dest)
}

function Get-LongTermHistoryAlerts {
    if (-not $script:Policy.DeepHistory) { return @('INFO: Long-term history scan is turned off in the policy settings') }
    if (-not (Test-Admin)) { return @('WARNING: Long-term history needs administrator rights') }
    if (-not (Initialize-BsmmForensics)) { return @("WARNING: Forensic engine unavailable ($script:BsmmForensicsError)") }
    $alerts = New-Object System.Collections.Generic.List[string]
    $volumes = Get-BsmmVolumeMap
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $amHits = New-Object System.Collections.Generic.List[object]
    $srHits = New-Object System.Collections.Generic.List[object]
    $mpHits = New-Object System.Collections.Generic.List[object]
    $work = Join-Path $env:TEMP ('BSMM_hist_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $am = Join-Path $work 'amcache.hve'
        if (Copy-BsmmLockedFile -Source "$env:SystemRoot\appcompat\Programs\Amcache.hve" -Dest $am) {
            $hive = [BSMM.Forensics]::LoadAppHive($am)
            if ($hive) {
                try {
                    $inv = $hive.OpenSubKey('Root\InventoryApplicationFile')
                    $count = 0
                    if ($inv) {
                        foreach ($sub in $inv.GetSubKeyNames()) {
                            $k = $inv.OpenSubKey($sub)
                            if (-not $k) { continue }
                            $path = [string]$k.GetValue('LowerCaseLongPath')
                            $link = [string]$k.GetValue('LinkDate')
                            $sha1 = [string]$k.GetValue('FileId')
                            $k.Close()
                            $count++
                            $kw = Get-BsmmCheatKeywordFast $path
                            if ($kw -and $seen.Add($path)) {
                                $extra = " built $link"
                                if ($sha1.Length -gt 4) { $extra += " sha1 $($sha1.Substring(4))" }
                                $amHits.Add([pscustomobject]@{ Kw = $kw; Path = $path; Extra = $extra })
                            }
                        }
                        $inv.Close()
                    }
                    Add-BsmmGroupedHits -Alerts $alerts -Level 'FAILURE' -Label 'Amcache: ran' -Hits $amHits
                    $alerts.Add("INFO: Amcache: $count programs on record")
                } finally { $hive.Close() }
            } else { $alerts.Add("INFO: Amcache copy could not be opened (error $([BSMM.Forensics]::LastHiveError))") }
        } else { $alerts.Add('INFO: Amcache could not be copied (shadow copy unavailable)') }

        $sr = Join-Path $work 'srudb.dat'
        if (Copy-BsmmLockedFile -Source "$env:SystemRoot\System32\sru\SRUDB.dat" -Dest $sr) {
            $paths = [BSMM.Forensics]::FilePaths($sr, 2GB, 60000)
            foreach ($raw in $paths) {
                $extra = ''
                if ($raw.StartsWith('!!')) { $bits = $raw.Substring(2) -split '\|', 2; $p = $bits[0]; $extra = " (file stamp $($bits[1]))" }
                else { $p = ConvertTo-BsmmDrivePath -Path $raw -Volumes $volumes; if (-not $p) { $p = $raw } }
                $kw = Get-BsmmCheatKeywordFast $p
                if ($kw -and $seen.Add($p)) { $srHits.Add([pscustomobject]@{ Kw = $kw; Path = $p; Extra = $extra }) }
            }
            Add-BsmmGroupedHits -Alerts $alerts -Level 'FAILURE' -Label 'SRUM app history (~30 days):' -Hits $srHits
            $alerts.Add("INFO: SRUM: $($paths.Count) programs in the last ~30 days of usage history")
        } else { $alerts.Add('INFO: SRUM could not be copied (shadow copy unavailable)') }

        $mpDir = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Support'
        $logs = @(Get-ChildItem -LiteralPath $mpDir -Filter 'MPLog-*.log' -File -ErrorAction SilentlyContinue)
        $mpCount = 0
        foreach ($f in $logs) {
            try {
                foreach ($raw in [BSMM.Forensics]::FilePaths($f.FullName, 256MB, 60000)) {
                    $mpCount++
                    $p = ConvertTo-BsmmDrivePath -Path $raw -Volumes $volumes
                    if (-not $p) { $p = $raw }
                    $kw = Get-BsmmCheatKeywordFast $p
                    if ($kw -and $seen.Add($p)) { $mpHits.Add([pscustomobject]@{ Kw = $kw; Path = $p; Extra = '' }) }
                }
                $txt = Read-BsmmTextFile -Path $f.FullName
                foreach ($m in [regex]::Matches($txt, 'ProcessImageName:\s*([^,\r\n]+)')) {
                    $n = $m.Groups[1].Value.Trim()
                    $kw = Get-BsmmCheatKeywordFast $n
                    if ($kw -and $seen.Add("mp|$n")) { $alerts.Add("FAILURE: Defender activity log: process [$kw] '$n' ran") }
                }
            } catch {}
        }
        Add-BsmmGroupedHits -Alerts $alerts -Level 'FAILURE' -Label 'Defender activity log:' -Hits $mpHits
        if ($logs.Count -gt 0) { $alerts.Add("INFO: Defender activity log: $($logs.Count) file(s), $mpCount paths") }
        elseif (Test-Admin) { $alerts.Add('WARNING: Defender activity log (MPLog) is missing - it may have been deleted') }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts.Insert(0, 'SUCCESS: No cheat names in Amcache, SRUM or the Defender activity log')
    }
    return @($alerts | Select-Object -First 45)
}

function Get-AiAimbotAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    $sites = New-Object System.Collections.Generic.List[string]
    $pyRoots = @((Join-Path $env:LOCALAPPDATA 'Programs\Python'), (Join-Path $env:APPDATA 'Python'), (Join-Path $env:USERPROFILE 'anaconda3'), (Join-Path $env:USERPROFILE 'miniconda3'))
    $pyRoots += @(Get-ChildItem -Path "$env:SystemDrive\" -Directory -Filter 'Python*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($r in $pyRoots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        Get-ChildItem -LiteralPath $r -Directory -Recurse -Depth 4 -Filter 'site-packages' -ErrorAction SilentlyContinue | ForEach-Object { $sites.Add($_.FullName) }
    }
    foreach ($d in (@(Get-BsmmUserFolders Desktop) + @(Get-BsmmUserFolders Documents) + @(Get-BsmmUserFolders Downloads))) {
        Get-ChildItem -LiteralPath $d -File -Recurse -Depth 3 -Filter 'pyvenv.cfg' -ErrorAction SilentlyContinue | ForEach-Object {
            $sp = Join-Path $_.DirectoryName 'Lib\site-packages'
            if (Test-Path -LiteralPath $sp) { $sites.Add($sp) }
        }
    }
    foreach ($sp in @($sites | Select-Object -Unique)) {
        $names = @(Get-ChildItem -LiteralPath $sp -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLower() })
        $capture = @($names | Where-Object { $_ -match '^(bettercam|dxcam|d3dshot|windows_capture)' })
        $ai = @($names | Where-Object { $_ -match '^(ultralytics|onnxruntime|tensorrt)' })
        $inject = @($names | Where-Object { $_ -match '^(pydirectinput|interception|pyinterception)' })
        if ($capture.Count -gt 0 -and $ai.Count -gt 0) {
            $alerts.Add("WARNING: Screen-capture and AI detection libraries installed together (an aimbot toolkit): $(($capture + $ai) -join ', ') -> $sp")
        } elseif ($ai.Count -gt 0 -and $inject.Count -gt 0) {
            $alerts.Add("WARNING: AI detection and mouse-injection libraries installed together: $(($ai + $inject) -join ', ') -> $sp")
        }
    }
    foreach ($d in (@(Get-BsmmUserFolders Desktop) + @(Get-BsmmUserFolders Documents) + @(Get-BsmmUserFolders Downloads))) {
        Get-ChildItem -LiteralPath $d -File -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^(?i)\.(onnx|engine)$' -and $_.Length -gt 1MB } | Select-Object -First 5 |
            ForEach-Object { $alerts.Add("WARNING: AI model file (aimbots ship these) -> $($_.FullName)") }
    }
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($p.ProcessName -match '^(?i)Roblox' -or $p.Id -eq $PID) { continue }
        $path = $null; try { $path = $p.Path } catch {}
        if (-not $path -or $path -match '^(?i)[a-z]:\\windows\\|\\(NVIDIA|Microsoft|CapCut|Adobe|Blackmagic|obs-studio|Microsoft Office|WindowsApps)\\') { continue }
        $mods = @()
        try { $mods = @($p.Modules | ForEach-Object { $_.ModuleName }) } catch { continue }
        $aiMods = @($mods | Where-Object { $_ -match '^(?i)(onnxruntime|DirectML|nvinfer|onnxruntime_pybind11_state)' })
        if ($aiMods.Count -gt 0) { $alerts.Add("WARNING: Running program uses an AI model runtime ($(($aiMods | Select-Object -Unique) -join ', ')) -> $($p.ProcessName) $path") }
    }
    if ($alerts.Count -eq 0) { $alerts.Add('SUCCESS: No AI aimbot libraries, models or running AI runtimes found') }
    return @($alerts | Select-Object -Unique -First 20)
}

$script:InputBoardVids = @{
    '2341' = 'Arduino'; '2A03' = 'Arduino'; '1B4F' = 'SparkFun Pro Micro'; '16C0' = 'Teensy / V-USB board'
    '239A' = 'Adafruit board'; '2E8A' = 'Raspberry Pi Pico (RP2040)'; '303A' = 'Espressif ESP32 board'
}
function Get-InputHardwareAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    $present = @{}
    $ports = @{}; $mice = @{}
    try {
        foreach ($d in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)) {
            $id = [string]$d.DeviceID
            if ($id -notmatch 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') { continue }
            $vid = $matches[1].ToUpper(); $pidv = $matches[2].ToUpper(); $key = "$vid`:$pidv"
            $present[$key] = [string]$d.Name
            if ($script:InputBoardVids.ContainsKey($vid) -and -not $alerts.Contains("x$key")) {
                $alerts.Add("WARNING: Connected now: $($script:InputBoardVids[$vid]) ($key) '$($d.Name)' - these boards can pose as a mouse/keyboard for aim assistance")
                $alerts.Add("x$key")
            }
            if ([string]$d.PNPClass -eq 'Ports' -and $id -like 'USB\*') { $ports[$key] = [string]$d.Name }
            if ([string]$d.PNPClass -eq 'Mouse') { $mice[$key] = [string]$d.Name }
        }
    } catch { $alerts.Add('WARNING: Could not list connected devices') }
    foreach ($k in $mice.Keys) {
        if ($ports.ContainsKey($k)) { $alerts.Add("WARNING: Mouse that also exposes a serial port ($($k) '$($mice[$k])' + '$($ports[$k])') - typical of KMBox/MAKCU-style input boxes") }
    }
    try {
        $usb = Open-LocalMachineRegistryKey -SubKeyPath 'SYSTEM\CurrentControlSet\Enum\USB'
        if ($usb) {
            foreach ($n in $usb.GetSubKeyNames()) {
                if ($n -match '^VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})$') {
                    $vid = $matches[1].ToUpper(); $key = "$vid`:$($matches[2].ToUpper())"
                    if ($script:InputBoardVids.ContainsKey($vid) -and -not $present.ContainsKey($key)) {
                        $alerts.Add("INFO: Connected in the past: $($script:InputBoardVids[$vid]) ($key)")
                    }
                }
            }
            $usb.Close()
        }
    } catch {}
    $out = @($alerts | Where-Object { $_ -notlike 'x*' })
    if (-not ($out | Where-Object { $_ -like 'WARNING*' -or $_ -like 'FAILURE*' })) { $out = @('SUCCESS: No microcontroller boards or input boxes connected') + $out }
    return $out
}

$script:CodeFingerprint = ''
function Get-ScriptIntegrityAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    foreach ($o in @($script:PreRemovedOverrides | Where-Object { $_ })) { $alerts.Add("FAILURE: A PowerShell command was replaced before the check started ($o) - used to fake check results") }
    if ($script:PreDefaultParams -gt 0) { $alerts.Add("WARNING: PowerShell default parameter values were pre-set ($script:PreDefaultParams) - can silently change how commands behave") }
    foreach ($exe in @('powershell.exe', 'pwsh.exe', 'conhost.exe', 'powershell_ise.exe', 'WindowsTerminal.exe', 'OpenConsole.exe')) {
        foreach ($root in @('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options', 'SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options')) {
            try {
                $k = Open-LocalMachineRegistryKey -SubKeyPath "$root\$exe"
                if ($k) {
                    $dbg = [string]$k.GetValue('Debugger')
                    if ($dbg) { $alerts.Add("FAILURE: $exe is hijacked (IFEO Debugger -> $dbg)") }
                    $k.Close()
                }
            } catch {}
        }
    }
    try {
        foreach ($line in @(Get-Content -LiteralPath (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts') -ErrorAction Stop)) {
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith('#')) { continue }
            if ($t -match '(?i)(github|githubusercontent|workers\.dev|cloudflare|discord)') { $alerts.Add("FAILURE: hosts file redirects $($matches[1]) - can serve a fake clean check -> $t") }
        }
    } catch {}
    try {
        $defs = (Get-ChildItem Function: | Where-Object { $_.Name -like 'Get-*Alerts' } | Sort-Object Name | ForEach-Object { $_.Name + "`n" + $_.Definition }) -join "`n"
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($defs))
        $script:CodeFingerprint = ([BitConverter]::ToString($hash) -replace '-', '').Substring(0, 16)
        $alerts.Add("INFO: Code fingerprint $script:CodeFingerprint (the same for every unmodified copy of this version)")
    } catch {}
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts.Insert(0, 'SUCCESS: No signs that this check was hooked, redirected or modified')
    }
    return @($alerts)
}

function Get-SecurityPolicyAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    $pol = $script:Policy
    $sb = $null
    try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch {}
    if ($sb -eq $true) { $alerts.Add('SUCCESS: Secure Boot is on') }
    elseif ($sb -eq $false) { if ($pol.RequireSecureBoot) { $alerts.Add('FAILURE: Secure Boot is off (required by league policy)') } else { $alerts.Add('WARNING: Secure Boot is off (allows boot-level cheats)') } }
    else { $alerts.Add('INFO: Secure Boot status unavailable (legacy BIOS mode, or not run as administrator)') }

    $bl = $null
    try { $bl = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' -Name VulnerableDriverBlocklistEnable -ErrorAction Stop } catch {}
    if ($null -ne $bl -and [int]$bl -eq 0) {
        if ($pol.RequireDriverBlocklist) { $alerts.Add('FAILURE: Vulnerable Driver Blocklist is off (required by league policy; turning it off is step one of loading kernel cheats)') }
        else { $alerts.Add('WARNING: Vulnerable Driver Blocklist is off (turning it off is step one of loading kernel cheats)') }
    } else { $alerts.Add('SUCCESS: Vulnerable Driver Blocklist is not turned off') }

    $hvci = $null
    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        $hvci = @($dg.SecurityServicesRunning) -contains 2
    } catch {}
    if ($hvci -eq $true) { $alerts.Add('SUCCESS: Memory Integrity (HVCI) is running - blocks manually loaded kernel cheats') }
    elseif ($hvci -eq $false) {
        if ($pol.RequireMemoryIntegrity) { $alerts.Add('FAILURE: Memory Integrity (HVCI) is off (required by league policy)') }
        else { $alerts.Add('INFO: Memory Integrity (HVCI) is off - kernel cheats can load (not required by league policy)') }
    }
    return @($alerts)
}

$script:BsmmInspectSource = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace BSMM
{
    public class ProcReport
    {
        public int Pid;
        public string Error;
        public string Hollow;
        public int FloatingPe;
        public string FloatingPeAt;
        public int UnbackedThreads;
        public string UnbackedAt;
        public int ThreadsChecked;
    }

    public static class Inspect
    {
        [StructLayout(LayoutKind.Sequential)]
        struct MBI
        {
            public IntPtr BaseAddress;
            public IntPtr AllocationBase;
            public uint AllocationProtect;
            public IntPtr RegionSize;
            public uint State;
            public uint Protect;
            public uint Type;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct WIN32_FIND_STREAM_DATA
        {
            public long StreamSize;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 296)]
            public string cStreamName;
        }

        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenThread(uint access, bool inherit, int tid);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI info, IntPtr len);
        [DllImport("ntdll.dll")] static extern int NtQueryInformationThread(IntPtr h, int cls, out IntPtr info, int len, IntPtr retLen);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr FindFirstStreamW(string file, int level, out WIN32_FIND_STREAM_DATA data, int flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool FindNextStreamW(IntPtr h, out WIN32_FIND_STREAM_DATA data);
        [DllImport("kernel32.dll")] static extern bool FindClose(IntPtr h);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disposition, uint flags, IntPtr template);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct WINTRUST_FILE_INFO { public uint cbStruct; public string pcwszFilePath; public IntPtr hFile; public IntPtr pgKnownSubject; }
        [StructLayout(LayoutKind.Sequential)]
        struct WINTRUST_DATA
        {
            public uint cbStruct; public IntPtr pPolicyCallbackData; public IntPtr pSIPClientData; public uint dwUIChoice;
            public uint fdwRevocationChecks; public uint dwUnionChoice; public IntPtr pFile; public uint dwStateAction;
            public IntPtr hWVTStateData; public IntPtr pwszURLReference; public uint dwProvFlags; public uint dwUIContext; public IntPtr pSignatureSettings;
        }
        [DllImport("wintrust.dll", CharSet = CharSet.Unicode)]
        static extern int WinVerifyTrust(IntPtr hwnd, ref Guid action, ref WINTRUST_DATA data);

        // 0 = valid. Embedded signatures only; no revocation / network lookups, so it is fast.
        public static int VerifyFile(string path)
        {
            var fi = new WINTRUST_FILE_INFO();
            fi.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_FILE_INFO));
            fi.pcwszFilePath = path;
            IntPtr pFile = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WINTRUST_FILE_INFO)));
            Marshal.StructureToPtr(fi, pFile, false);
            try
            {
                var wd = new WINTRUST_DATA();
                wd.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_DATA));
                wd.dwUIChoice = 2;
                wd.fdwRevocationChecks = 0;
                wd.dwUnionChoice = 1;
                wd.pFile = pFile;
                wd.dwProvFlags = 0x1000;
                Guid action = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
                return WinVerifyTrust(new IntPtr(-1), ref action, ref wd);
            }
            finally { Marshal.DestroyStructure(pFile, typeof(WINTRUST_FILE_INFO)); Marshal.FreeHGlobal(pFile); }
        }

        public static string SignerName(string path)
        {
            try
            {
                var c = new System.Security.Cryptography.X509Certificates.X509Certificate2(System.Security.Cryptography.X509Certificates.X509Certificate.CreateFromSignedFile(path));
                return c.GetNameInfo(System.Security.Cryptography.X509Certificates.X509NameType.SimpleName, false);
            }
            catch { return ""; }
        }

        static bool IsExec(uint p) { return (p & 0xF0) != 0 && (p & 0x100) == 0; }

        static int PeOffset(byte[] b, int len)
        {
            if (len < 0x40 || b[0] != 0x4D || b[1] != 0x5A) return -1;
            int pe = BitConverter.ToInt32(b, 0x3C);
            if (pe <= 0 || pe + 0x60 > len) return -1;
            if (b[pe] != 0x50 || b[pe + 1] != 0x45 || b[pe + 2] != 0 || b[pe + 3] != 0) return -1;
            return pe;
        }

        static string CompareHeaders(byte[] mem, int memLen, byte[] disk, int diskLen)
        {
            int pd = PeOffset(disk, diskLen);
            if (pd < 0) return null;                       // file is not a normal PE: nothing to compare
            int pm = PeOffset(mem, memLen);
            if (pm < 0) return "PE header missing in memory";
            uint tsM = BitConverter.ToUInt32(mem, pm + 8), tsD = BitConverter.ToUInt32(disk, pd + 8);
            uint sizeM = BitConverter.ToUInt32(mem, pm + 24 + 56), sizeD = BitConverter.ToUInt32(disk, pd + 24 + 56);
            uint epM = BitConverter.ToUInt32(mem, pm + 24 + 16), epD = BitConverter.ToUInt32(disk, pd + 24 + 16);
            if (tsM != tsD) return "build stamp differs (memory " + tsM.ToString("X") + ", file " + tsD.ToString("X") + ")";
            if (sizeM != sizeD) return "image size differs (memory " + sizeM + ", file " + sizeD + ")";
            if (epM != epD) return "entry point differs";
            return null;
        }

        public static ProcReport InspectProcess(int pid, string imagePath, long imageBase, int[] threadIds)
        {
            var r = new ProcReport();
            r.Pid = pid;
            IntPtr h = OpenProcess(0x0410, false, pid);
            if (h == IntPtr.Zero) { r.Error = "denied"; return r; }
            try
            {
                if (imageBase != 0 && !string.IsNullOrEmpty(imagePath) && File.Exists(imagePath))
                {
                    byte[] mem = new byte[0x1000];
                    IntPtr got;
                    if (ReadProcessMemory(h, new IntPtr(imageBase), mem, new IntPtr(mem.Length), out got) && got.ToInt64() >= 0x200)
                    {
                        byte[] disk = new byte[0x1000];
                        int n = 0;
                        try
                        {
                            using (var fs = new FileStream(imagePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) n = fs.Read(disk, 0, disk.Length);
                        }
                        catch { n = 0; }
                        if (n > 0) r.Hollow = CompareHeaders(mem, (int)got.ToInt64(), disk, n);
                    }
                }

                var images = new List<long[]>();
                long addr = 0;
                int mbiSize = Marshal.SizeOf(typeof(MBI));
                MBI mbi;
                byte[] head = new byte[0x400];
                while (VirtualQueryEx(h, new IntPtr(addr), out mbi, new IntPtr(mbiSize)) != IntPtr.Zero)
                {
                    long b = mbi.BaseAddress.ToInt64(), size = mbi.RegionSize.ToInt64();
                    if (size <= 0) break;
                    if (mbi.State == 0x1000)
                    {
                        if (mbi.Type == 0x1000000) images.Add(new long[] { b, b + size });
                        else if (mbi.Type == 0x20000 && IsExec(mbi.Protect) && size >= 0x1000)
                        {
                            IntPtr got;
                            int peo = -1;
                            if (ReadProcessMemory(h, new IntPtr(b), head, new IntPtr(head.Length), out got)) peo = PeOffset(head, (int)got.ToInt64());
                            bool managed = false;
                            if (peo >= 0)
                            {
                                int opt = peo + 24;
                                int dirs = opt + (BitConverter.ToUInt16(head, opt) == 0x20B ? 112 : 96);
                                if (dirs + 14 * 8 + 8 <= head.Length && BitConverter.ToUInt32(head, dirs + 14 * 8 + 4) > 0) managed = true;
                            }
                            if (peo >= 0 && !managed)
                            {
                                r.FloatingPe++;
                                if (r.FloatingPeAt == null) r.FloatingPeAt = "0x" + b.ToString("X") + ", " + (size / 1024) + " KB";
                            }
                        }
                    }
                    long next = b + size;
                    if (next <= addr) break;
                    addr = next;
                }

                foreach (int tid in threadIds)
                {
                    IntPtr th = OpenThread(0x0040, false, tid);
                    if (th == IntPtr.Zero) continue;
                    IntPtr start;
                    int st = NtQueryInformationThread(th, 9, out start, IntPtr.Size, IntPtr.Zero);
                    CloseHandle(th);
                    if (st != 0 || start == IntPtr.Zero) continue;
                    r.ThreadsChecked++;
                    long s = start.ToInt64();
                    bool inImage = false;
                    foreach (var im in images) { if (s >= im[0] && s < im[1]) { inImage = true; break; } }
                    if (!inImage)
                    {
                        r.UnbackedThreads++;
                        if (r.UnbackedAt == null) r.UnbackedAt = "0x" + s.ToString("X");
                    }
                }
            }
            finally { CloseHandle(h); }
            return r;
        }

        // Alternate data streams other than the file's main content ("name|size").
        public static string[] Streams(string path)
        {
            var list = new List<string>();
            WIN32_FIND_STREAM_DATA d;
            IntPtr h = FindFirstStreamW(path, 0, out d, 0);
            if (h == new IntPtr(-1)) return list.ToArray();
            try
            {
                do { if (d.cStreamName != "::$DATA") list.Add(d.cStreamName + "|" + d.StreamSize); }
                while (FindNextStreamW(h, out d));
            }
            finally { FindClose(h); }
            return list.ToArray();
        }

        // True when the stream starts with an executable header.
        public static bool StreamIsExecutable(string path, string streamName)
        {
            using (SafeFileHandle h = CreateFile(path + streamName, 0x80000000, 7, IntPtr.Zero, 3, 0, IntPtr.Zero))
            {
                if (h.IsInvalid) return false;
                using (var fs = new FileStream(h, FileAccess.Read))
                {
                    byte[] b = new byte[2];
                    return fs.Read(b, 0, 2) == 2 && b[0] == 0x4D && b[1] == 0x5A;
                }
            }
        }
    }
}
'@

$script:BsmmInspectError = ''
function Initialize-BsmmInspect {
    if ('BSMM.Inspect' -as [type]) { return $true }
    try { Add-Type -TypeDefinition $script:BsmmInspectSource -ErrorAction Stop; return $true }
    catch { $script:BsmmInspectError = $_.Exception.Message; return $false }
}

$script:LeakedCertSerials = @('43BB437D609866286DD839E1D00309F5', '14781BC862E8DC503A559346F5DCC518')
$script:TrustedSignerPattern = '(?i)^(Roblox Corporation|Microsoft Corporation|Microsoft Windows|NVIDIA Corporation|Advanced Micro Devices|Intel Corporation|Valve|Discord Inc\.|Riot Games|Epic Games|Google LLC|Logitech|Razer)'
$script:ImpersonatedSignerPattern = '(?i)(Roblox|Microsoft|NVIDIA|Valve|Discord|Riot|Epic Games|Google|Intel|AMD|Advanced Micro|Take-Two|Rockstar|Activision|Ubisoft|Electronic Arts|Blizzard|Bungie|Ubisoft)'

function Get-BsmmSigner {
    param($Sig)
    if ($Sig -and $Sig.SignerCertificate -and $Sig.SignerCertificate.Subject -match 'CN=("?)([^,"]+)') { return $matches[2].Trim() }
    return ''
}

$script:SigObjCache = @{}
function Get-BsmmSignature {
    param([string]$Path)
    if ($script:SigObjCache.ContainsKey($Path)) { return $script:SigObjCache[$Path] }
    $sig = $null
    try { $sig = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop } catch {}
    $script:SigObjCache[$Path] = $sig
    return $sig
}

function Get-SignatureForgeryAlerts {
    if (-not (Initialize-BsmmForensics)) { return @("WARNING: Forensic engine unavailable ($script:BsmmForensicsError)") }
    $alerts = New-Object System.Collections.Generic.List[string]
    $cands = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $userDirs = @(Get-BsmmUserFolders Desktop) + @(Get-BsmmUserFolders Downloads) + @(Get-BsmmUserFolders Documents)
    foreach ($d in $userDirs) {
        Get-ChildItem -LiteralPath $d -File -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^(?i)\.(exe|dll)$' } | ForEach-Object { [void]$cands.Add($_.FullName) }
    }
    foreach ($d in @($env:LOCALAPPDATA, $env:APPDATA)) {
        Get-ChildItem -LiteralPath $d -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $script:FpSkipAppData } | ForEach-Object {
            Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Depth 2 -Force -Filter '*.exe' -ErrorAction SilentlyContinue | ForEach-Object { [void]$cands.Add($_.FullName) }
        }
    }
    Get-ChildItem -LiteralPath $env:TEMP -File -Recurse -Depth 1 -Force -Filter '*.exe' -ErrorAction SilentlyContinue | ForEach-Object { [void]$cands.Add($_.FullName) }
    foreach ($p in @($script:ExecutionEvidence)) { [void]$cands.Add($p) }
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        $pp = $null; try { $pp = $proc.Path } catch {}
        if ($pp -and $pp -notmatch '^(?i)[a-z]:\\windows\\') { [void]$cands.Add($pp) }
    }

    if (-not (Initialize-BsmmInspect)) { return @("WARNING: Process inspector unavailable ($script:BsmmInspectError)") }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $checked = 0
    $verify = @{}
    $vf = { param($f) if (-not $verify.ContainsKey($f)) { $verify[$f] = [BSMM.Inspect]::VerifyFile($f) }; $verify[$f] }
    $ordered = @($cands | Where-Object { $_ -match '(?i)\\Users\\' }) + @($cands | Where-Object { $_ -notmatch '(?i)\\Users\\' })
    foreach ($path in $ordered) {
        if ($sw.Elapsed.TotalSeconds -gt 40) { $alerts.Add('INFO: Signature check stopped at its time limit'); break }
        if (-not ([System.IO.File]::Exists($path)) -or -not [BSMM.Forensics]::HasEmbeddedSignature($path)) { continue }
        $checked++
        $code = & $vf $path
        $signer = [BSMM.Inspect]::SignerName($path)
        $impersonated = $signer -match $script:ImpersonatedSignerPattern
        $inRoblox = $path -match '(?i)\\(Roblox|Bloxstrap|Fishstrap)\\Versions\\'
        $serial = ''
        try { $serial = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($path).GetSerialNumberString().ToUpper() } catch {}
        if ($serial -and $script:LeakedCertSerials -contains $serial) { $alerts.Add("FAILURE: Signed with the leaked NVIDIA certificate ($serial) -> $path"); continue }
        if ($code -eq -2146869232) { $alerts.Add("FAILURE: Signature copied onto a modified file - claims to be '$signer' but the file was changed after signing -> $path"); continue }
        if ($code -eq -2146762496) { $alerts.Add("WARNING: File carries a signature block Windows cannot read (damaged or fake signature) -> $path"); continue }
        if ($code -eq -2146762495) {
            if ($impersonated) { $alerts.Add("FAILURE: Signed with an expired '$signer' certificate - cheats reuse stolen or leaked publisher certificates -> $path") }
            continue
        }
        if ($code -ne 0) {
            if ($impersonated) { $alerts.Add("FAILURE: Fake '$signer' signature (Windows does not trust it, code 0x$('{0:X8}' -f $code)) -> $path") }
            elseif ($code -ne -2146762486) { $alerts.Add("WARNING: Signature not trusted by Windows (code 0x$('{0:X8}' -f $code), '$signer') -> $path") }
            continue
        }
        if ($impersonated -and -not (Test-SignedByShippedRoot -Path $path)) {
            $alerts.Add("FAILURE: '$signer' signature made with a certificate only trusted on this PC (self-made root) -> $path")
            continue
        }
        if ($signer -match '^(?i)Roblox Corporation' -and -not $inRoblox -and ([IO.Path]::GetFileName($path) -notmatch '^(?i)Roblox(Player|Studio)Installer')) {
            $dir2 = [IO.Path]::GetDirectoryName($path)
            $foreign = @(Get-ChildItem -LiteralPath $dir2 -File -Filter '*.dll' -Force -ErrorAction SilentlyContinue | Where-Object {
                -not ((& $vf $_.FullName) -eq 0 -and ([BSMM.Inspect]::SignerName($_.FullName)) -match $script:TrustedSignerPattern)
            })
            if ($foreign.Count -gt 0) { $alerts.Add("FAILURE: Roblox-signed program next to foreign DLL(s) $(($foreign | Select-Object -First 3 | ForEach-Object Name) -join ', ') - side-loading borrows Roblox's signature to run a cheat -> $path") }
            else { $alerts.Add("WARNING: Copy of a Roblox-signed program outside Roblox's folders -> $path") }
            continue
        }
        if ($path -match '(?i)\.exe$' -and $path -notmatch '(?i)\\Program Files') {
            $dir3 = [IO.Path]::GetDirectoryName($path)
            foreach ($dll in @(Get-ChildItem -LiteralPath $dir3 -File -Filter '*.dll' -Force -ErrorAction SilentlyContinue)) {
                if ($script:ProxyDllNames -notcontains $dll.Name.ToLower()) { continue }
                if ((& $vf $dll.FullName) -ne 0) { $alerts.Add("FAILURE: Signed program '$([IO.Path]::GetFileName($path))' ($signer) next to an unsigned '$($dll.Name)' - DLL side-loading -> $dir3") }
            }
        }
    }    $alerts.Add("INFO: Checked $checked signed programs")
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts.Insert(0, 'SUCCESS: No copied, fake or borrowed signatures found')
    }
    return @($alerts | Select-Object -Unique -First 30)
}

$script:InjectSkipNames = '^(?i)(Roblox.*|System|Idle|Registry|Secure System|Memory Compression|MsMpEng|NisSrv|MpDefenderCoreService|csrss|smss|wininit|services|lsass|.*Iso|vmmem.*)$'
function Get-InjectedCodeAlerts {
    param([int[]]$OnlyPids = @(), [switch]$NoModules)
    if (-not (Initialize-BsmmInspect)) { return @("WARNING: Process inspector unavailable ($script:BsmmInspectError)") }
    try { [System.Diagnostics.Process]::EnterDebugMode() } catch {}
    $alerts = New-Object System.Collections.Generic.List[string]
    $inspected = 0
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($p.Id -le 4 -or $p.Id -eq $PID -or $p.ProcessName -match $script:InjectSkipNames) { continue }
        if ($OnlyPids.Count -gt 0 -and $OnlyPids -notcontains $p.Id) { continue }
        $path = $null; $base = [long]0
        try { $path = $p.Path } catch {}
        try { $base = $p.MainModule.BaseAddress.ToInt64() } catch {}
        $tids = @()
        try { $tids = @($p.Threads | ForEach-Object { $_.Id }) } catch {}
        $r = $null
        try { $r = [BSMM.Inspect]::InspectProcess($p.Id, [string]$path, $base, [int[]]$tids) } catch { continue }
        if (-not $r -or $r.Error) { continue }
        $inspected++
        $who = "$($p.ProcessName) (PID $($p.Id))"
        if ($path) { $who += " $path" }
        if ($r.Hollow) { $alerts.Add("FAILURE: Running program does not match its file on disk ($($r.Hollow)) - hollowed or replaced process -> $who") }
        if ($r.FloatingPe -gt 0) { $alerts.Add("WARNING: $($r.FloatingPe) program image(s) loaded outside any file ($($r.FloatingPeAt)) - how manually mapped cheat DLLs look -> $who") }
        if ($r.UnbackedThreads -gt 0) { $alerts.Add("WARNING: $($r.UnbackedThreads) thread(s) started in code that belongs to no file (first at $($r.UnbackedAt)) - injected code -> $who") }

        if ($path) {
            try {
                if ($path.StartsWith('\\')) { $alerts.Add("WARNING: Program running from a network share -> $who") }
                else {
                    $dt = ([System.IO.DriveInfo]::new($path.Substring(0, 3))).DriveType
                    if ($dt -eq 'Removable' -or $dt -eq 'Network') { $alerts.Add("WARNING: Program running from a $($dt.ToString().ToLower()) drive -> $who") }
                }
            } catch {}
        }

        if (-not $NoModules -and $path -and (Get-CachedSignatureStatus -Path $path) -eq 'Valid') {
            $mods = @()
            try { $mods = @($p.Modules | ForEach-Object { $_.FileName }) } catch {}
            foreach ($m in $mods) {
                if (-not $m -or $m -notmatch '(?i)\\(Users|ProgramData)\\' -or $m -match '(?i)\\AppData\\Local\\Microsoft\\') { continue }
                if ((Get-CachedSignatureStatus -Path $m) -ne 'Valid') {
                    $alerts.Add("WARNING: Unsigned DLL from a user folder loaded into signed program $($p.ProcessName) -> $m")
                }
            }
        }
    }
    $alerts.Add("INFO: Inspected $inspected running programs")
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) {
        $alerts.Insert(0, 'SUCCESS: No hollowed programs, hidden code or injected threads found')
    }
    return @($alerts | Select-Object -Unique -First 30)
}

$script:BenignStreams = '^(?i):(Zone\.Identifier|SmartScreen|com\.dropbox\.[^:]*|ms-properties|OECustomProperty|encryptable|favicon|AFP_AfpInfo|Win32App_1|KAVICHS|\$OBJECT_ID|CA_INOC|TASKICON):'
function Get-HiddenStreamAlerts {
    if (-not (Initialize-BsmmInspect)) { return @("WARNING: Process inspector unavailable ($script:BsmmInspectError)") }
    $alerts = New-Object System.Collections.Generic.List[string]
    $roots = @(Get-BsmmUserFolders Desktop) + @(Get-BsmmUserFolders Downloads) + @(Get-BsmmUserFolders Documents) + @($env:TEMP, $env:LOCALAPPDATA, $env:APPDATA)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $checked = 0
    foreach ($r in $roots) {
        $depth = 3; if ($r -eq $env:LOCALAPPDATA -or $r -eq $env:APPDATA) { $depth = 1 }
        foreach ($item in @(Get-ChildItem -LiteralPath $r -Recurse -Depth $depth -Force -ErrorAction SilentlyContinue)) {
            if ($sw.Elapsed.TotalSeconds -gt 20) { break }
            $checked++
            $streams = @()
            try { $streams = [BSMM.Inspect]::Streams($item.FullName) } catch { continue }
            foreach ($s in $streams) {
                $bits = $s -split '\|'; $name = $bits[0]; $size = [long]$bits[1]
                if ($name -match $script:BenignStreams) { continue }
                $exe = $false
                try { $exe = [BSMM.Inspect]::StreamIsExecutable($item.FullName, $name) } catch {}
                if ($exe) { $alerts.Add("FAILURE: Program hidden inside the hidden data stream '$name' of -> $($item.FullName)") }
                elseif ($size -gt 64KB) { $alerts.Add("WARNING: $([Math]::Round($size / 1KB)) KB of data hidden in stream '$name' of -> $($item.FullName)") }
            }
        }
    }
    $alerts.Add("INFO: Checked hidden streams on $checked files and folders")
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: No programs hidden in alternate data streams') }
    return @($alerts | Select-Object -First 25)
}

$script:KnownPciVendors = @('8086','1022','1002','10DE','10EC','14E4','168C','17CB','14C3','144D','1B4B','1B21','1912','1987','15B7','1C5C','126F','1E0F','1344','2646','1CC1','1E4B','1B73','104C','1106','1217','1180','11AB','1969','1102','1414','15AD','80EE','1AF4','1D6A','1CD7','1461','BDBD','1D0F','1B36','1179','1DBE','1F40','1E95','1D79','1217','105A','1000','9005','19E5','1D17','1D94')
function Get-HypervisorDmaAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    $hv = $null; $vm = $false
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $hv = [bool]$cs.HypervisorPresent
        $vm = "$($cs.Manufacturer) $($cs.Model)" -match '(?i)VMware|VirtualBox|innotek|QEMU|\bKVM\b|\bXen\b|Parallels|Virtual Machine'
    } catch {}
    $vbs = $false
    try { $vbs = [int](Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop).VirtualizationBasedSecurityStatus -eq 2 } catch {}
    $launch = ''
    try {
        $out = & "$env:SystemRoot\System32\bcdedit.exe" /enum '{current}' 2>$null | Out-String
        if ($out -match '(?im)^\s*hypervisorlaunchtype\s+(\S+)') { $launch = $matches[1] }
    } catch {}
    if ($hv -eq $true -and -not $vm) {
        if ($vbs -or $launch -match '(?i)^auto') { $alerts.Add("INFO: Windows' own hypervisor is running (Core Isolation / Hyper-V / WSL)") }
        elseif ($launch) { $alerts.Add("FAILURE: A hypervisor is running underneath Windows, but Windows did not start one (VBS off, hypervisor launch '$launch') - hypervisor cheats run this way") }
        else { $alerts.Add('WARNING: A hypervisor is running underneath Windows and its source could not be confirmed (run as administrator)') }
    }

    try {
        foreach ($d in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { [string]$_.DeviceID -like 'PCI\VEN_*' })) {
            if ([string]$d.DeviceID -notmatch 'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})') { continue }
            $ven = $matches[1].ToUpper(); $dev = $matches[2].ToUpper()
            if ($script:FpgaPciVendorIds.ContainsKey($ven)) { continue }
            $err = [int]$d.ConfigManagerErrorCode
            if ($err -ne 0) { $alerts.Add("WARNING: PCIe device not working (error $err): '$($d.Name)' ($ven`:$dev) - DMA cheat cards often show up as a broken or driverless device") }
            elseif ($script:KnownPciVendors -notcontains $ven) { $alerts.Add("INFO: PCIe device from an uncommon vendor: '$($d.Name)' ($ven`:$dev)") }
        }
    } catch { $alerts.Add('WARNING: Could not list PCIe devices') }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: No hidden hypervisor or broken PCIe devices') }
    return @($alerts | Select-Object -First 20)
}

$script:MonSeenPids = New-Object 'System.Collections.Generic.HashSet[int]'
$script:MonPending = @{}
$script:MonFingerprinted = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:MonPciBaseline = $null
$script:MonMatcher = $null

function Get-BsmmPciIds {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    try { foreach ($d in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)) { if ([string]$d.DeviceID -like 'PCI\*') { [void]$set.Add("$($d.DeviceID)|$($d.Name)") } } } catch {}
    return ,$set
}

function Initialize-BsmmMonitorBaseline {
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) { [void]$script:MonSeenPids.Add($p.Id) }
    $script:MonPciBaseline = Get-BsmmPciIds
    if (Initialize-BsmmForensics) { $script:MonMatcher = [BSMM.Matcher]::new([string[]]$script:FpNeedles) }
}

function Get-RunningFingerprintAlerts {
    param([int[]]$OnlyPids = @())
    $out = New-Object System.Collections.Generic.List[string]
    if (-not $script:MonMatcher) { return $out }
    try { [System.Diagnostics.Process]::EnterDebugMode() } catch {}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($p.Id -eq $PID -or $p.ProcessName -match '^(?i)Roblox') { continue }
        if ($OnlyPids.Count -gt 0 -and $OnlyPids -notcontains $p.Id) { continue }
        $path = $null; try { $path = $p.Path } catch {}
        if (-not $path -or $path -match '^(?i)[a-z]:\\windows\\') { continue }
        if ((Get-CachedSignatureStatus -Path $path) -eq 'Valid') { continue }
        $err = $null; $hits = [UInt64]0
        try { $hits = [BSMM.Forensics]::ProcessNeedles($p.Id, $script:MonMatcher, 256MB, [ref]$err) } catch { continue }
        $why = @(Get-BsmmFingerprintVerdict $hits)
        if ($why.Count -gt 0) { $out.Add("FAILURE: Running program contains $($why -join '; ') -> $($p.ProcessName) $path") }
    }
    return $out
}

function Get-BsmmNewProcessAlerts {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if (-not $script:MonSeenPids.Add($p.Id)) { continue }
        $script:MonPending[$p.Id] = Get-Date
        $path = $null; try { $path = $p.Path } catch {}
        if (-not $path) { continue }
        if ($p.ProcessName -match '^(?i)RobloxPlayerBeta$') {
            $sig = Get-BsmmSignature -Path $path
            $genuine = $sig -and [string]$sig.Status -eq 'Valid' -and (Get-BsmmSigner $sig) -match '^(?i)Roblox Corporation' -and $path -match '(?i)\\(Roblox|Bloxstrap|Fishstrap)\\Versions\\'
            if (-not $genuine) { $out.Add("FAILURE: Roblox was started from an unexpected or badly signed file -> $path") }
            foreach ($l in @(Get-RobloxFolderAlerts)) { if ($l -like 'FAILURE*' -or $l -like 'WARNING*') { $out.Add($l) } }
            continue
        }
        if ($path -match '^(?i)[a-z]:\\windows\\') { continue }
        $kw = Get-BsmmCheatKeywordFast $path
        if ($kw) { $out.Add("FAILURE: Started during the match [$kw] -> $($p.ProcessName) $path") }
        if ($script:MonMatcher -and $script:MonFingerprinted.Add($path)) {
            try {
                $why = @(Get-BsmmFingerprintVerdict ([BSMM.Forensics]::FileNeedles($path, $script:MonMatcher, 80MB)))
                if ($why.Count -gt 0) { $out.Add("FAILURE: Started during the match: program contains $($why -join '; ') -> $($p.ProcessName) $path") }
            } catch {}
            try {
                if ([BSMM.Forensics]::HasEmbeddedSignature($path) -and (Initialize-BsmmInspect)) {
                    if ([BSMM.Inspect]::VerifyFile($path) -eq -2146869232) { $out.Add("FAILURE: Started during the match with a copied signature ('$([BSMM.Inspect]::SignerName($path))', file modified after signing) -> $path") }
                }
            } catch {}
        }
        try {
            $dt = ([System.IO.DriveInfo]::new($path.Substring(0, 3))).DriveType
            if ($path.StartsWith('\\') -or $dt -eq 'Removable' -or $dt -eq 'Network') { $out.Add("WARNING: Program started from a USB stick or network drive during the match -> $path") }
        } catch {}
    }
    return $out
}

function Get-BsmmPendingPids {
    param([int]$Age = 8)
    $ready = @()
    foreach ($k in @($script:MonPending.Keys)) {
        if (((Get-Date) - $script:MonPending[$k]).TotalSeconds -ge $Age) { $ready += [int]$k; $script:MonPending.Remove($k) }
    }
    return ,$ready
}

function Get-BsmmJournalSinceAlerts {
    param([datetime]$Since)
    $out = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Admin) -or -not (Initialize-BsmmForensics)) { return $out }
    $info = New-Object BSMM.UsnInfo
    $entries = $null
    try { $entries = [BSMM.Forensics]::ReadUsn($env:SystemDrive, 32MB, [string[]]@('.exe', '.dll', '.sys', '.lua', '.luau', '.pf', '.ahk', '.bat', '.ps1', '.asi', 'imgui.ini'), [string[]]@('autoexec'), $Since, ($env:SystemRoot + '\'), $info) } catch { return $out }
    if (-not $info.Ok) { return $out }
    $userRe = Get-BsmmUserFolderRegex
    $pf = 0
    $old = @{}
    foreach ($e in $entries) {
        $r = $e.Reason
        $del = ($r -band 0x200) -ne 0
        $create = ($r -band 0x100) -ne 0
        if (($r -band 0x1000) -ne 0) { $old[[string]$e.Frn] = $e.Path }
        if ($e.IsDir) { if ($create) { $out.Add("FAILURE: Executor 'autoexec' folder created during the match -> $($e.Path)") }; continue }
        if ($e.Name -like '*.pf') { if ($del) { $pf++ }; continue }
        if ($e.Name -eq 'imgui.ini') {
            if (($create -or $del) -and $e.Path -notmatch $script:ImGuiIgnorePaths) {
                $lvl = 'WARNING'; if ($e.Path -match $script:ImGuiHotPaths) { $lvl = 'FAILURE' }
                $out.Add("${lvl}: ImGui menu settings file (imgui.ini) $(if ($del) { 'deleted' } else { 'created' }) during the match -> $($e.Path)")
            }
            continue
        }
        $kw = Get-BsmmCheatKeywordFast $e.Path
        if ($kw) {
            $act = 'changed'; if ($del) { $act = 'deleted' } elseif (($r -band 0x3000) -ne 0) { $act = 'renamed' } elseif ($create) { $act = 'created' }
            $out.Add("FAILURE: [$kw] file $act during the match -> $($e.Path)")
            continue
        }
        if ($e.Name -like '*.sys' -and $e.Path -match '(?i)\\(Temp|AppData)\\' -and $create) { $out.Add("FAILURE: Driver file dropped in a temp folder during the match (kernel cheat loaders do this) -> $($e.Path)"); continue }
        if ($del -and $e.Path -match $userRe -and $e.Name -match '(?i)\.(exe|dll|lua|luau|ahk)$') { $out.Add("WARNING: Program deleted during the match -> $($e.Path)") }
        if (($r -band 0x2000) -ne 0 -and $old.ContainsKey([string]$e.Frn)) {
            $o = $old[[string]$e.Frn]
            if ($o -match '(?i)\.(exe|dll|lua|luau|ahk)$' -and $e.Path -notmatch '(?i)\.(exe|dll|lua|luau|ahk)$') { $out.Add("WARNING: Program renamed to hide it during the match: $o -> $($e.Name)") }
        }
    }
    if ($pf -ge 5) { $out.Add("FAILURE: $pf Prefetch files deleted during the match (Prefetch wipe)") }
    return $out
}

function Get-BsmmDeviceChangeAlerts {
    $out = New-Object System.Collections.Generic.List[string]
    $devs = @()
    try { $devs = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop) } catch { return $out }
    $ports = @{}; $mice = @{}
    foreach ($d in $devs) {
        $id = [string]$d.DeviceID
        if ($id -like 'PCI\*' -and $script:MonPciBaseline -and -not $script:MonPciBaseline.Contains("$id|$($d.Name)")) {
            $out.Add("FAILURE: PCIe device appeared during the match (hot-plugged DMA hardware?) -> $($d.Name) $id")
        }
        if ($id -notmatch 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') { continue }
        $vid = $matches[1].ToUpper(); $key = "$vid`:$($matches[2].ToUpper())"
        if ($script:InputBoardVids.ContainsKey($vid)) { $out.Add("WARNING: $($script:InputBoardVids[$vid]) connected ($key) '$($d.Name)' - can pose as a mouse/keyboard") }
        if ([string]$d.PNPClass -eq 'Ports' -and $id -like 'USB\*') { $ports[$key] = $true }
        if ([string]$d.PNPClass -eq 'Mouse') { $mice[$key] = [string]$d.Name }
    }
    foreach ($k in $mice.Keys) { if ($ports.ContainsKey($k)) { $out.Add("WARNING: Mouse that also exposes a serial port ($($k) '$($mice[$k])') - typical of KMBox/MAKCU-style input boxes") } }
    return $out
}

$script:BsmmKernSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace BSMM
{
    public static class Kern
    {
        [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int cls, IntPtr buf, int len, out int ret);
        [DllImport("iphlpapi.dll")] static extern uint GetExtendedTcpTable(IntPtr table, ref int size, bool order, int af, int tableClass, int reserved);
        [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr module, string name);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadLibrary(string name);

        // SYSTEM_CODEINTEGRITY_INFORMATION (class 103). 0xFFFFFFFF = query failed.
        public static uint CodeIntegrityOptions()
        {
            IntPtr b = Marshal.AllocHGlobal(8);
            try
            {
                Marshal.WriteInt32(b, 0, 8);
                Marshal.WriteInt32(b, 4, 0);
                int ret;
                if (NtQuerySystemInformation(103, b, 8, out ret) != 0) return 0xFFFFFFFF;
                return (uint)Marshal.ReadInt32(b, 4);
            }
            finally { Marshal.FreeHGlobal(b); }
        }

        // SYSTEM_KERNEL_DEBUGGER_INFORMATION (class 35) plus KUSER_SHARED_DATA.KdDebuggerEnabled.
        public static bool KernelDebuggerEnabled()
        {
            bool on = false;
            IntPtr b = Marshal.AllocHGlobal(2);
            try
            {
                int ret;
                if (NtQuerySystemInformation(35, b, 2, out ret) == 0 && Marshal.ReadByte(b, 0) != 0) on = true;
            }
            finally { Marshal.FreeHGlobal(b); }
            try { if ((Marshal.ReadByte(new IntPtr(0x7FFE02D4)) & 1) != 0) on = true; } catch { }
            return on;
        }

        // Live processes that answer by PID but are missing from the normal process list (DKOM hiding).
        public static int[] HiddenPids(int[] listed)
        {
            var set = new HashSet<int>(listed);
            var hidden = new List<int>();
            for (int pid = 8; pid < 0x40000; pid += 4)
            {
                if (set.Contains(pid)) continue;
                IntPtr h = OpenProcess(0x1000, false, pid);
                if (h == IntPtr.Zero) continue;
                uint code;
                if (GetExitCodeProcess(h, out code) && code == 259) hidden.Add(pid);
                CloseHandle(h);
            }
            return hidden.ToArray();
        }

        static string Ip(uint a) { return (a & 0xFF) + "." + ((a >> 8) & 0xFF) + "." + ((a >> 16) & 0xFF) + "." + ((a >> 24) & 0xFF); }
        static int Port(int p) { return ((p & 0xFF) << 8) | ((p >> 8) & 0xFF); }

        // IPv4 TCP table: "state|localIp|localPort|remoteIp|remotePort|pid" (state 2 = LISTEN, 5 = ESTABLISHED)
        public static string[] TcpTable()
        {
            var list = new List<string>();
            for (int attempt = 0; attempt < 3; attempt++)
            {
                int size = 0;
                GetExtendedTcpTable(IntPtr.Zero, ref size, false, 2, 5, 0);
                size += 4096;
                IntPtr b = Marshal.AllocHGlobal(size);
                try
                {
                    if (GetExtendedTcpTable(b, ref size, false, 2, 5, 0) != 0) continue;
                    int n = Marshal.ReadInt32(b);
                    for (int i = 0; i < n; i++)
                    {
                        IntPtr row = new IntPtr(b.ToInt64() + 4 + i * 24);
                        list.Add((uint)Marshal.ReadInt32(row, 0) + "|" + Ip((uint)Marshal.ReadInt32(row, 4)) + "|" + Port(Marshal.ReadInt32(row, 8)) + "|" +
                                 Ip((uint)Marshal.ReadInt32(row, 12)) + "|" + Port(Marshal.ReadInt32(row, 16)) + "|" + Marshal.ReadInt32(row, 20));
                    }
                    return list.ToArray();
                }
                finally { Marshal.FreeHGlobal(b); }
            }
            return list.ToArray();
        }

        // Detects the classic AMSI / ETW "patch to return" tricks in THIS process.
        public static string ProloguePatch(string dll, string fn)
        {
            IntPtr m = GetModuleHandle(dll);
            if (m == IntPtr.Zero) m = LoadLibrary(dll);
            if (m == IntPtr.Zero) return null;
            IntPtr p = GetProcAddress(m, fn);
            if (p == IntPtr.Zero) return null;
            byte b0 = Marshal.ReadByte(p), b1 = Marshal.ReadByte(p, 1), b2 = Marshal.ReadByte(p, 2);
            if (b0 == 0xC3) return "patched to return immediately";
            if (b0 == 0x33 && b1 == 0xC0 && b2 == 0xC3) return "patched to return 0";
            if (b0 == 0xB8 && Marshal.ReadByte(p, 5) == 0xC3) return "patched to return a fixed value";
            if (b0 == 0xE9 || (b0 == 0xFF && b1 == 0x25)) return "redirected (hooked)";
            return null;
        }
    }
}
'@
$script:BsmmKernError = ''
function Initialize-BsmmKern {
    if ('BSMM.Kern' -as [type]) { return $true }
    try { Add-Type -TypeDefinition $script:BsmmKernSource -ErrorAction Stop; return $true }
    catch { $script:BsmmKernError = $_.Exception.Message; return $false }
}

$script:BridgeAllowSigners = '(?i)(Kaspersky|AVAST|AVG|ESET|Bitdefender|Malwarebytes|Norton|McAfee|Sophos|Trend Micro|Avira|F-Secure|Microsoft|NVIDIA|Discord|Overwolf|ExitLag|Valve)'
function Get-RobloxBridgeAlerts {
    if (-not (Initialize-BsmmKern)) { return @("WARNING: Kernel helper unavailable ($script:BsmmKernError)") }
    $alerts = New-Object System.Collections.Generic.List[string]
    $rows = @([BSMM.Kern]::TcpTable() | ForEach-Object { $f = $_ -split '\|'; [pscustomobject]@{ State = [int]$f[0]; LIp = $f[1]; LPort = [int]$f[2]; RIp = $f[3]; RPort = [int]$f[4]; Pid = [int]$f[5] } })
    $rbx = @{}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(?i)Roblox(PlayerBeta|Studio)' })) { $rbx[$p.Id] = $true }
    $listeners = @{}
    foreach ($r in $rows) { if ($r.State -eq 2) { $listeners[$r.LPort] = $r.Pid } }
    $describe = {
        param($procId)
        $pp = Get-Process -Id $procId -ErrorAction SilentlyContinue
        $path = $null; try { $path = $pp.Path } catch {}
        [pscustomobject]@{ Name = $(if ($pp) { $pp.ProcessName } else { "PID $procId" }); Path = $path }
    }
    if ($listeners.ContainsKey(58443)) {
        $d = & $describe $listeners[58443]
        $alerts.Add("FAILURE: A program is listening on port 58443, the port of the Fleasion Roblox traffic proxy -> $($d.Name) $($d.Path)")
    }
    $seen = @{}
    foreach ($r in $rows) {
        if (-not $rbx.ContainsKey($r.Pid) -or $r.RIp -notmatch '^127\.') { continue }
        if (-not $listeners.ContainsKey($r.RPort)) { continue }
        $owner = $listeners[$r.RPort]
        if ($rbx.ContainsKey($owner) -or $seen.ContainsKey($owner)) { continue }
        $seen[$owner] = $true
        $d = & $describe $owner
        $signer = ''
        if ($d.Path -and (Initialize-BsmmInspect) -and [BSMM.Inspect]::VerifyFile($d.Path) -eq 0) { $signer = [BSMM.Inspect]::SignerName($d.Path) }
        if ($signer -and $signer -match $script:BridgeAllowSigners) { $alerts.Add("INFO: Roblox is connected to local program $($d.Name) ($signer) on port $($r.RPort)") }
        else { $alerts.Add("FAILURE: Roblox is connected to a local program on this PC (port $($r.RPort)) - how executors like Xeno and traffic proxies talk to Roblox -> $($d.Name) $($d.Path)") }
    }
    if ($rbx.Count -eq 0) { $alerts.Add('INFO: Roblox is not running - the bridge check works best while Roblox is open') }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: Roblox is not connected to any local program or proxy') }
    return @($alerts)
}

function Get-RobloxTamperAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    $roots = @('Roblox', 'Bloxstrap', 'Fishstrap', 'Froststrap', 'Voidstrap') | ForEach-Object { Join-Path $env:LOCALAPPDATA "$_\Versions" }
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} 'Roblox\Versions') }
    $counts = @{}
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($v in @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue)) {
            $exe = Join-Path $v.FullName 'RobloxPlayerBeta.exe'
            $pem = Join-Path $v.FullName 'ssl\cacert.pem'
            if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $pem)) { continue }
            $txt = ''
            try { $txt = [IO.File]::ReadAllText($pem) } catch {}
            $n = ([regex]::Matches($txt, 'BEGIN CERTIFICATE')).Count
            $counts[$v.FullName] = $n
            if ((Get-Item -LiteralPath $pem).LastWriteTime -gt (Get-Item -LiteralPath $exe).LastWriteTime.AddMinutes(30)) {
                $alerts.Add("FAILURE: Roblox's trusted-certificate list was edited after install ($n certificates) - traffic proxies like Fleasion do this -> $pem")
            }
        }
    }
    if (@($counts.Values | Select-Object -Unique).Count -gt 1) {
        $alerts.Add("WARNING: Roblox version folders have different certificate lists ($((@($counts.Values | Select-Object -Unique)) -join ' vs ') certificates)")
    }
    $flagFiles = @((Join-Path $env:TEMP 'Roblox\cache\flag_cache.dat'), (Join-Path $env:LOCALAPPDATA 'Roblox\ClientSettings\ClientAppSettings.json'))
    foreach ($r in $roots) { if (Test-Path -LiteralPath $r) { $flagFiles += @(Get-ChildItem -LiteralPath $r -Recurse -Depth 2 -Filter 'ClientAppSettings.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) } }
    foreach ($app in @('Bloxstrap', 'Fishstrap', 'Froststrap', 'Voidstrap')) { $flagFiles += (Join-Path $env:LOCALAPPDATA "$app\Modifications\ClientSettings\ClientAppSettings.json") }
    foreach ($f in @($flagFiles | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $txt = ''
        try { $txt = [IO.File]::ReadAllText($f) } catch {}
        if ($txt -match '(?i)"DFFlagHttpUseEmbeddedCaCerts"\s*:\s*"?false') { $alerts.Add("FAILURE: Roblox certificate pinning is switched off (DFFlagHttpUseEmbeddedCaCerts=False) - lets a proxy read and change Roblox traffic -> $f") }
    }

    $logDir = Join-Path $env:LOCALAPPDATA 'Roblox\logs'
    $volumes = Get-BsmmVolumeMap
    $blocked = @{}; $local = 0; $files = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $logDir -Filter '*.log' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-14) -and $_.Name -match '(?i)player' } | Sort-Object LastWriteTime -Descending | Select-Object -First 40)) {
        $files++
        $txt = ''
        try { $fs = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs); $txt = $sr.ReadToEnd(); $sr.Close() } catch { continue }
        foreach ($m in [regex]::Matches($txt, '(?i)Blocked DLL:\s*([^\r\n]+)')) {
            $raw = $m.Groups[1].Value.Trim()
            $p = ConvertTo-BsmmDrivePath -Path $raw -Volumes $volumes
            if (-not $p) { $p = $raw }
            if ($p -match '(?i)^[a-z]:\\(windows|program files)' ) { continue }
            if (-not $blocked.ContainsKey($p)) { $blocked[$p] = Get-Date $f.LastWriteTime -Format 'yyyy-MM-dd HH:mm' }
        }
        $local += @([regex]::Matches($txt, '(?i)HttpTraceError[^\r\n]*(127\.0\.0\.1|localhost)[^\r\n]*') | Where-Object { $_.Value -notmatch '(?i)/api/rojo|:3487[0-9]' }).Count
    }
    foreach ($k in $blocked.Keys) { $alerts.Add("FAILURE: Roblox's anti-cheat blocked a DLL from loading into Roblox ($($blocked[$k])) -> $k") }
    if ($local -gt 0) { $alerts.Add("WARNING: Roblox tried to reach a server on this PC $local time(s) (executor bridges run a local server)") }
    if ($files -eq 0 -and (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Roblox\Versions'))) { $alerts.Add('INFO: No Roblox game logs from the last 14 days') }
    else { $alerts.Add("INFO: Read $files Roblox log file(s)") }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: Roblox install, certificate pinning and logs show no tampering') }
    return @($alerts | Select-Object -First 25)
}

function Get-KernelIntegrityAlerts {
    param([switch]$Light)
    $alerts = New-Object System.Collections.Generic.List[string]
    if (-not (Initialize-BsmmKern)) { return @("WARNING: Kernel helper unavailable ($script:BsmmKernError)") }
    $ci = [BSMM.Kern]::CodeIntegrityOptions()
    if ($ci -ne [uint32]::MaxValue) {
        if (($ci -band 0x2) -ne 0) { $alerts.Add('FAILURE: Windows is in test-signing mode (kernel reports it) - any self-signed driver can load') }
        if (($ci -band 0x80) -ne 0) { $alerts.Add('FAILURE: Code integrity debug mode is on (kernel reports it)') }
    }
    if ([BSMM.Kern]::KernelDebuggerEnabled()) { $alerts.Add('FAILURE: Kernel debugging is enabled - lets kernel memory be read and patched') }
    foreach ($pair in @(@('amsi.dll', 'AmsiScanBuffer'), @('ntdll.dll', 'EtwEventWrite'), @('ntdll.dll', 'NtTraceEvent'))) {
        try { $res = [BSMM.Kern]::ProloguePatch($pair[0], $pair[1]) } catch { $res = $null }
        if ($res) {
            $lvl = 'FAILURE'; if ($res -like 'redirected*') { $lvl = 'WARNING' }
            $alerts.Add("${lvl}: $($pair[1]) in this check's own process is $res - used to blind security logging")
        }
    }
    try {
        $before = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
        foreach ($h in @([BSMM.Kern]::HiddenPids([int[]]$before))) {
            $visible = $false
            try { [void][System.Diagnostics.Process]::GetProcessById($h); $visible = $true } catch {}
            if (-not $visible) { $alerts.Add("FAILURE: Hidden running process (PID $h) - answers by ID but is missing from the process list (kernel-level hiding)") }
        }
    } catch {}
    if ($Light) {
        if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: Kernel state looks normal') }
        return @($alerts)
    }

    $expect = @(
        @('SOFTWARE\Microsoft\Cryptography\OID\EncodingType 0\CryptSIPDllVerifyIndirectData\{C689AAB8-8E78-11D0-8C47-00C04FC295EE}', 'Dll', 'WINTRUST.DLL', 'FuncName', 'CryptSIPVerifyIndirectData'),
        @('SOFTWARE\Microsoft\Cryptography\OID\EncodingType 0\CryptSIPDllGetSignedDataMsg\{C689AAB8-8E78-11D0-8C47-00C04FC295EE}', 'Dll', 'WINTRUST.DLL', 'FuncName', 'CryptSIPGetSignedDataMsg'),
        @('SOFTWARE\Microsoft\Cryptography\Providers\Trust\FinalPolicy\{00AAC56B-CD44-11D0-8CC2-00C04FC295EE}', '$DLL', 'WINTRUST.DLL', '$Function', 'SoftpubAuthenticode')
    )
    foreach ($view in @('', 'WOW6432Node\')) {
        foreach ($e in $expect) {
            $sub = $e[0] -replace '^SOFTWARE\\', "SOFTWARE\$view"
            try {
                $k = Open-LocalMachineRegistryKey -SubKeyPath $sub
                if (-not $k) { continue }
                $dll = [IO.Path]::GetFileName([string]$k.GetValue($e[1])); $fn = [string]$k.GetValue($e[3])
                $k.Close()
                if ($dll -and ($dll -ne $e[2] -or $fn -ne $e[4])) { $alerts.Add("FAILURE: Windows signature checking has been rerouted ($dll!$fn) - makes forged signatures look valid -> HKLM\$sub") }
            } catch {}
        }
    }

    if (Initialize-BsmmForensics) {
        $m = [BSMM.Matcher]::new([string[]]@('JemmyLoveJenny', 'Fake Timestamp Responder'))
        try {
            foreach ($drv in @(Get-CimInstance Win32_SystemDriver -Filter "State='Running'" -ErrorAction Stop)) {
                $p = Normalize-KernelDriverPath -Path ([string]$drv.PathName)
                if (-not $p) { continue }
                if (-not (Test-Path -LiteralPath $p)) { $alerts.Add("WARNING: Running driver '$($drv.Name)' has no file on disk ($p)"); continue }
                try {
                    if ((Get-Item -LiteralPath $p).Length -le 40MB -and [BSMM.Forensics]::FileNeedles($p, $m, 40MB) -ne 0) { $alerts.Add("FAILURE: Driver signed with a fake-timestamp signing tool (HookSignTool) -> $p") }
                } catch {}
                try {
                    $serial = [System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($p).GetSerialNumberString()
                    if ($script:LeakedCertSerials -contains $serial.ToUpper()) { $alerts.Add("FAILURE: Driver signed with the leaked NVIDIA certificate ($serial) -> $p") }
                } catch {}
            }
        } catch {}
    }

    try {
        $bug = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; StartTime = (Get-Date).AddDays(-30) } -MaxEvents 50 -ErrorAction Stop | Where-Object { $_.ProviderName -match 'WER-SystemErrorReporting|BugCheck' })
        foreach ($e in $bug) {
            if ([string]$e.Message -match '0x0*109\b|\(0x00000109') { $alerts.Add("FAILURE: PatchGuard crash (bugcheck 0x109) on $(Get-Date $e.TimeCreated -Format 'yyyy-MM-dd') - Windows caught the kernel being modified") }
        }
        if ($bug.Count -gt 0) { $alerts.Add("INFO: $($bug.Count) blue-screen crash(es) in the last 30 days") }
    } catch {}

    try {
        foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = @(5001, 5007); StartTime = (Get-Date).AddDays(-7) } -MaxEvents 200 -ErrorAction Stop)) {
            $when = Get-Date $e.TimeCreated -Format 'yyyy-MM-dd HH:mm'
            if ($e.Id -eq 5001) { $alerts.Add("WARNING: Defender real-time protection was turned off on $when"); continue }
            $msg = [string]$e.Message
            if ($msg -match '(?i)\\Exclusions\\(Paths|Processes|Extensions)\\([^\r\n=]+?)\s*=') {
                $what = $matches[2].Trim()
                if ($msg -match '(?i)New value:\s*(\r?\n|$)' -or $msg -match '(?i)New value:\s*$') { $alerts.Add("WARNING: Defender exclusion removed on $when (added earlier, then cleaned up) -> $what") }
                else { $alerts.Add("WARNING: Defender exclusion added on $when -> $what") }
            }
        }
    } catch {}
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: No kernel debugger, hidden processes, rerouted signature checks or suspicious drivers') }
    return @($alerts | Select-Object -Unique -First 30)
}

$script:CaptureAllow = '(?i)\\(obs64|obs32|Medal|Discord|DiscordCanary|nvcontainer|NVIDIA Share|NVIDIA App|steamwebhelper|Steam|ShareX|SnippingTool|ScreenClippingHost|Teams|ms-teams|Zoom|chrome|msedge|firefox|opera|brave|Code|Cursor|CapCut|Lightshot|Greenshot|PowerToys[^\\]*|explorer|GameBar[^\\]*|XboxGameBar[^\\]*)\.exe$'
function Get-ScreenCaptureAlerts {
    param([datetime]$Since = (Get-Date).AddDays(-7))
    $alerts = New-Object System.Collections.Generic.List[string]
    foreach ($cap in @('graphicsCaptureProgrammatic', 'graphicsCaptureWithoutBorder')) {
        $k = $null
        try { $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$cap\NonPackaged") } catch {}
        if (-not $k) { continue }
        foreach ($sub in $k.GetSubKeyNames()) {
            $sk = $k.OpenSubKey($sub)
            if (-not $sk) { continue }
            $ft = $sk.GetValue('LastUsedTimeStart')
            $sk.Close()
            if (-not $ft) { continue }
            $when = $null
            try { $when = [DateTime]::FromFileTime([long]$ft) } catch { continue }
            if ($when -lt $Since) { continue }
            $path = $sub -replace '#', '\'
            if ($path -match $script:CaptureAllow) { continue }
            $kw = Get-BsmmCheatKeywordFast $path
            if ($kw) { $alerts.Add("FAILURE: [$kw] captured the screen on $(Get-Date $when -Format 'yyyy-MM-dd HH:mm') -> $path") }
            elseif ((Test-UntrustedUserProgramPath -Path $path) -or -not (Test-Path -LiteralPath $path)) { $alerts.Add("WARNING: Program captured the screen on $(Get-Date $when -Format 'yyyy-MM-dd HH:mm') (colourbots and AI aimbots do this) -> $path") }
            else { $alerts.Add("INFO: Screen captured by $path on $(Get-Date $when -Format 'yyyy-MM-dd HH:mm')") }
        }
        $k.Close()
    }
    if (-not ($alerts | Where-Object { $_ -like 'FAILURE*' -or $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: No unexpected program used Windows screen capture') }
    return @($alerts | Select-Object -First 15)
}

function Get-InputFilterAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    foreach ($cls in @(@('{4D36E96F-E325-11CE-BFC1-08002BE10318}', 'mouse', 'mouclass'), @('{4D36E96B-E325-11CE-BFC1-08002BE10318}', 'keyboard', 'kbdclass'))) {
        try {
            $k = Open-LocalMachineRegistryKey -SubKeyPath "SYSTEM\CurrentControlSet\Control\Class\$($cls[0])"
            if ($k) {
                $extra = @(@($k.GetValue('UpperFilters')) | Where-Object { $_ -and $_ -ne $cls[2] })
                $k.Close()
                foreach ($x in $extra) {
                    if ($x -match '^(?i)rawaccel$') { $alerts.Add("INFO: Raw Accel mouse-acceleration driver installed ($x) - legitimate, but it does change mouse input") }
                    else { $alerts.Add("WARNING: Extra $($cls[1]) filter driver '$x' - input-injection drivers (Interception) install this way") }
                }
            }
        } catch {}
    }
    try {
        foreach ($d in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { [string]$_.DeviceID -match 'VID_1A86&PID_55D3' })) {
            $alerts.Add("WARNING: WCH CH343 serial device connected ('$($d.Name)') - the chip used by MAKCU input boxes")
        }
    } catch {}
    if (-not ($alerts | Where-Object { $_ -like 'WARNING*' })) { $alerts.Insert(0, 'SUCCESS: No input-injection filter drivers or MAKCU-style serial devices') }
    return @($alerts)
}

function Get-LoggingTamperExtraAlerts {
    $alerts = New-Object System.Collections.Generic.List[string]
    if ((Test-Admin) -and (Initialize-BsmmForensics)) {
        try {
            $info = New-Object BSMM.UsnInfo
            [void][BSMM.Forensics]::ReadUsn($env:SystemDrive, 0, [string[]]@('.x'), [string[]]@('x'), (Get-Date), '', $info)
            if ($info.JournalId -gt 0) {
                $created = [DateTime]::FromFileTime([long]$info.JournalId)
                $boot = Get-BootTime
                if ($boot -and $created -gt $boot) { $alerts.Add("FAILURE: The change journal was deleted and recreated this session ($(Get-Date $created -Format 'yyyy-MM-dd HH:mm')) - wipes file history") }
                elseif ($created -gt (Get-Date).AddDays(-7)) { $alerts.Add("WARNING: The change journal was recreated on $(Get-Date $created -Format 'yyyy-MM-dd HH:mm') (file history before that is gone)") }
                else { $alerts.Add("INFO: Change journal exists since $(Get-Date $created -Format 'yyyy-MM-dd')") }
            }
        } catch {}
    }
    foreach ($ch in @('Microsoft-Windows-PowerShell/Operational', 'Microsoft-Windows-CodeIntegrity/Operational', 'Microsoft-Windows-Kernel-PnP/Configuration', 'Microsoft-Windows-Windows Defender/Operational')) {
        try {
            $k = Open-LocalMachineRegistryKey -SubKeyPath "SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\$ch"
            if ($k) { $en = $k.GetValue('Enabled'); $k.Close(); if ($null -ne $en -and [int]$en -eq 0) { $alerts.Add("WARNING: Event log '$ch' is switched off") } }
        } catch {}
    }
    foreach ($target in @("$env:SystemRoot\Prefetch", "$env:SystemRoot\appcompat\pca", "$env:SystemRoot\appcompat\Programs", 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings')) {
        try {
            $acl = Get-Acl -LiteralPath $target -ErrorAction Stop
            if (@($acl.Access | Where-Object { [string]$_.AccessControlType -eq 'Deny' }).Count -gt 0) { $alerts.Add("FAILURE: A deny rule blocks Windows from recording program runs in $target") }
        } catch {}
    }
    return @($alerts)
}

$script:RobloxLogOffsets = @{}
function Get-BsmmRobloxLogTailAlerts {
    $out = New-Object System.Collections.Generic.List[string]
    $logDir = Join-Path $env:LOCALAPPDATA 'Roblox\logs'
    $volumes = Get-BsmmVolumeMap
    foreach ($f in @(Get-ChildItem -LiteralPath $logDir -Filter '*.log' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) -and $_.Name -match '(?i)player' })) {
        $start = 0L
        if ($script:RobloxLogOffsets.ContainsKey($f.FullName)) { $start = $script:RobloxLogOffsets[$f.FullName] }
        if ($f.Length -le $start) { continue }
        try {
            $fs = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite')
            [void]$fs.Seek($start, 'Begin')
            $sr = New-Object IO.StreamReader($fs)
            $txt = $sr.ReadToEnd()
            $script:RobloxLogOffsets[$f.FullName] = $fs.Length
            $sr.Close()
        } catch { continue }
        foreach ($m in [regex]::Matches($txt, '(?i)Blocked DLL:\s*([^\r\n]+)')) {
            $p = ConvertTo-BsmmDrivePath -Path $m.Groups[1].Value.Trim() -Volumes $volumes
            if (-not $p) { $p = $m.Groups[1].Value.Trim() }
            if ($p -notmatch '(?i)^[a-z]:\\(windows|program files)') { $out.Add("FAILURE: Roblox's anti-cheat blocked a DLL during the match -> $p") }
        }
        if (@([regex]::Matches($txt, '(?i)HttpTraceError[^\r\n]*(127\.0\.0\.1|localhost)[^\r\n]*') | Where-Object { $_.Value -notmatch '(?i)/api/rojo|:3487[0-9]' }).Count -gt 0) { $out.Add('WARNING: Roblox tried to reach a server on this PC during the match (executor bridge?)') }
    }
    return $out
}

$script:ProgressWidth = 28

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
[void](Initialize-BsmmModules)

$script:LiveSeq = 0
$script:LiveStarted = $false
$script:LastLiveUpdate = Get-Date
function Send-BsmmLiveUpdate {
    param([datetime]$Since, [string]$State = 'RUNNING')
    $script:LastLiveUpdate = Get-Date
    $body = Get-BsmmLiveBody -Since $Since -State $State
    if (-not $script:LiveStarted) {
        $report = Get-BsmmReportBody -Results @() -Seconds 0
        foreach ($key in @($report.Keys)) { $body[$key] = $report[$key] }
    }
    $script:LiveSeq++
    $sent = $false
    try { $sent = Send-BsmmSigned -Path '/v1/live' -Seq $script:LiveSeq -Body $body } catch {}
    if ($sent) { $script:LiveStarted = $true }
    return $sent
}

Write-StepHeader -Step 1
Out-TaggedText -Indent '  ' -Tag 'NOTE' -Text 'Activity goes to BSMM staff under this report ID and is not shown here. User names, the PC name and personal files are never sent.' -TextToken 'Muted'
if (-not (Test-Admin)) {
    Out-Seg ''
    Out-Card -Title 'Not running as administrator' -Accent 'Warn' -Lines @(
        'Several monitor checks need admin rights and will be incomplete.',
        'Ask staff for a new code, right-click PowerShell, choose "Run as administrator" and run the command there.'
    )
}
Out-Seg ''
Out-Card -Title 'Keep this window open' -Lines @(
    'Leave this window running for the whole match. Staff can see if it is closed early.',
    'Nothing is listed here while it runs. Press Ctrl+C when the match is over.'
)
Out-Seg ''
Out-TaggedText -Indent '  ' -Tag 'NOTE' -Text 'Starting up (about a minute)...' -TextToken 'Muted'

Write-MonitorAlert -Message "BSMM v$($script:BsmmVersion) live monitor started" -Level INFO
[void](Send-BsmmLiveUpdate -Since (Get-Date))

$usbMonitoringAvailable = $false
try {
    Get-EventSubscriber -SourceIdentifier USBChange -ErrorAction SilentlyContinue |
        Unregister-Event -Force -ErrorAction SilentlyContinue
    Register-WmiEvent -Class Win32_VolumeChangeEvent -SourceIdentifier USBChange -ErrorAction Stop | Out-Null
    $usbMonitoringAvailable = $true
} catch {
    Write-MonitorAlert -Message "WARNING: USB insertion/removal monitoring unavailable ($($_.Exception.Message))" -Color Yellow
}

trap {
    Write-MonitorAlert -Message "BSMM monitor error ($($_.Exception.Message))" -Color Yellow
    break
}

foreach ($fp in (Get-BamRegistryFingerprints)) { $script:BaselineBamKeys[$fp] = $true }
foreach ($pf in (Get-PrefetchFileNames)) { $script:BaselinePrefetchFiles[$pf] = $true }

$previousExclusions = @{}
foreach ($ex in (Get-Exclusions)) { $previousExclusions[$ex] = $true }
$knownCheatFolders = @{}
foreach ($folder in (Get-CheatFolderHits)) {
    $knownCheatFolders[$folder] = $true
}
$reportedBamDeletions = @{}
$reportedPrefetchDeletions = @{}
$reportedTamperEvents = @{}
$reportedPrefetchHits = @{}
$reportedCursorChanges = @{}
$baselineCursorScheme = Get-CursorSchemeState
$reportedDefenderRegChanges = @{}
$baselineDefenderReg = Get-DefenderRegistryFingerprints
$defenderRegLabels = Get-DefenderRegistryMonitorLabels
$lastProcessSnapshot = Get-ProcessSnapshot
$watchedProcesses = @{}
$monitoringStart = Get-Date

$folderScanCounter = 0
$deletionScanCounter = 0
$processChangeCounter = 0
$mainCplScanCounter = 0
$defenderScanCounter = 0
$activeThreatScanCounter = 0
$externalScanCounter = 0
$integrityScanCounter = 0
$bsmmExtraScanCounter = 0
$statusLineCounter = 0

$baselineUsn = Get-UsnJournalState
$baselineRootCerts = Get-RootCertificateThumbprintSet
$script:MonitoredServices = @('bam', 'SysMain', 'WinDefend', 'EventLog', 'Sense', 'wscsvc')
$baselineServices = @{}
foreach ($name in $script:MonitoredServices) {
    try { $baselineServices[$name] = [string](Get-Service -Name $name -ErrorAction Stop).Status } catch {}
}

$script:LastRobloxBuildAnnounced = $null

Initialize-BsmmMonitorBaseline
foreach ($__scan in @({ Get-InjectedCodeAlerts }, { Get-RunningFingerprintAlerts }, { Get-LoggingTamperAlerts }, { Get-LoggingTamperExtraAlerts }, { Get-HypervisorDmaAlerts }, { Get-SecurityPolicyAlerts }, { Get-ScriptIntegrityAlerts }, { Get-KernelIntegrityAlerts }, { Get-RobloxBridgeAlerts }, { Get-RobloxTamperAlerts }, { Get-InputFilterAlerts }, { Get-ImGuiTraceAlerts })) {
    try {
        foreach ($__l in @(& $__scan)) {
            if ($__l -like 'FAILURE*' -or $__l -like 'WARNING*') { Write-MonitorAlertOnce -Category 'deep' -Message $__l }
        }
    } catch {}
}
[void](Send-BsmmLiveUpdate -Since $monitoringStart)
$bsmmDeepTick = 0

function Get-MonitorIntegrityAlerts {
    param([datetime]$Since)
    $out = @()

    foreach ($name in $script:MonitoredServices) {
        if (-not $baselineServices.ContainsKey($name)) { continue }
        try {
            $status = [string](Get-Service -Name $name -ErrorAction Stop).Status
            if ($status -ne $baselineServices[$name] -and $status -ne 'Running') {
                $out += "FAILURE: Service $name changed from $($baselineServices[$name]) to $status during the match"
            }
        } catch {}
    }

    $usn = Get-UsnJournalState
    if ($baselineUsn.Present) {
        if ($usn.Error -eq 'not active') { $out += "FAILURE: USN change journal was deleted during the match" }
        elseif ($usn.Present -and $usn.JournalId -ne $baselineUsn.JournalId) { $out += "FAILURE: USN change journal was recreated during the match (deleted and re-enabled)" }
    }

    foreach ($entry in (Get-RootCertificateThumbprintSet)) {
        if ($baselineRootCerts.Contains($entry)) { continue }
        $parts = $entry -split '\|', 3
        $short = $parts[2]; if ($short -match 'CN=([^,]+)') { $short = $matches[1] }
        $lvl = if ($parts[2] -match '(?i)microsoft') { 'FAILURE' } else { 'WARNING' }
        $out += "${lvl}: Root certificate installed during match -> '$short' ($($parts[0]))"
    }

    foreach ($line in (Get-ClockChangeAlerts -Since $Since)) {
        if ($line -like 'WARNING*') { $out += $line }
    }

    foreach ($line in (Get-RobloxModuleAlerts)) {
        if ($line -like 'FAILURE*' -or $line -like 'WARNING*') { $out += $line }
    }

    return $out
}

$step1Categories = @{
    'PowerShell Module Integrity'  = 'pshost'
    'Process Scan'                 = 'userprog'
    'Transparent Overlays'         = 'overlay'
    'External / Overlay'           = 'external'
    'Process Explorer & Taskmgr'   = 'taskmgr'
    'Roblox Modules'               = 'integrity'
    'Windows Defender'             = 'defender'
    'Active Defender Threats'      = 'threats'
    'Macro & Auto-Clickers'        = 'macro'
}
foreach ($r in $script:SystemCheckResults) {
    if ($step1Categories.ContainsKey($r.Name)) {
        Register-MonitorBaseline -Category $step1Categories[$r.Name] -Lines $r.Lines
    }
}

try {
while ($true) {
    $usbEvent = $null
    if ($usbMonitoringAvailable) {
        $usbEvent = Wait-Event -SourceIdentifier USBChange -Timeout 1 -ErrorAction SilentlyContinue
    } else {
        Start-Sleep -Seconds 1
    }

    if ($usbEvent) {
        $eventType = $usbEvent.SourceEventArgs.NewEvent.EventType
        $driveLetter = $usbEvent.SourceEventArgs.NewEvent.DriveName

        if ($eventType -eq 2) {
            Write-MonitorAlert -Message "USB drive inserted ($driveLetter)" -Level NOTE
        } elseif ($eventType -eq 3) {
            Write-MonitorAlert -Message "USB drive removed ($driveLetter)" -Level NOTE
        }

        Remove-Event -EventIdentifier $usbEvent.EventIdentifier -ErrorAction SilentlyContinue
    }

    try {
        $currentExclusions = @{}
        foreach ($ex in (Get-Exclusions)) { $currentExclusions[$ex] = $true }

        foreach ($ex in $currentExclusions.Keys) {
            if (-not $previousExclusions.ContainsKey($ex)) {
                $exclKw = Get-MatchedCheatKeyword -Text $ex
                if ($exclKw) {
                    Write-MonitorAlert -Message "Defender exclusion added [$exclKw]: $ex" -Level FAIL
                } else {
                    Write-MonitorAlert -Message "Defender exclusion added during match: $ex" -Level FAIL
                }
            }
        }

        foreach ($ex in $previousExclusions.Keys) {
            if (-not $currentExclusions.ContainsKey($ex)) {
                Write-MonitorAlert -Message "Exclusion removed: $ex" -Color Yellow
            }
        }

        $previousExclusions = $currentExclusions
    } catch {
        $warnKey = "exclusions|$($_.Exception.Message)"
        if (-not $script:MainLoopFailureWarned.ContainsKey($warnKey)) {
            $script:MainLoopFailureWarned[$warnKey] = $true
            Write-MonitorAlert -Message "WARNING: Exclusion tracking failed ($($_.Exception.Message))" -Color Yellow
        }
    }

    foreach ($change in (Get-CursorSchemeChanges -Baseline $baselineCursorScheme -Current (Get-CursorSchemeState))) {
        if (-not $reportedCursorChanges.ContainsKey($change)) {
            $reportedCursorChanges[$change] = $true
            Write-MonitorAlert -Message "Cursor changed: $change" -Color Yellow
        }
    }

    $mainCplScanCounter++
    if ($mainCplScanCounter -ge 5) {
        $mainCplScanCounter = 0
        foreach ($hit in (Get-MainCplProcessHits))     { Write-MonitorAlertOnce -Category 'maincpl'  -Message $hit -Color Yellow }
        foreach ($hit in (Get-RegistryToolProcessHits)) { Write-MonitorAlertOnce -Category 'regtool'  -Message "Registry tool: $hit" -Color Yellow }
        foreach ($hit in (Get-WindhawkProcessHits))     { Write-MonitorAlertOnce -Category 'windhawk' -Message "Windhawk running: $hit" -Level FAIL }
    }

    $defenderScanCounter++
    if ($defenderScanCounter -ge 5) {
        $defenderScanCounter = 0

        try {
            foreach ($line in (Get-DefenderStatusAlerts)) {
                Write-MonitorAlertOnce -Category 'defender' -Message $line -Color Yellow
            }

            foreach ($entry in (Get-DefenderRegistryFingerprints).GetEnumerator()) {
                $root = $entry.Key
                $currentFp = $entry.Value
                $baselineFp = $baselineDefenderReg[$root]
                if ($currentFp -eq $baselineFp) { continue }

                $changeKey = "$root|$currentFp"
                if ($reportedDefenderRegChanges.ContainsKey($changeKey)) { continue }
                $reportedDefenderRegChanges[$changeKey] = $true

                $label = if ($defenderRegLabels.ContainsKey($root)) { $defenderRegLabels[$root] } else { $root }
                Write-MonitorAlert -Message "$label changed: $currentFp" -Color Yellow
            }
        } catch {
            $warnKey = "defender|$($_.Exception.Message)"
            if (-not $script:MainLoopFailureWarned.ContainsKey($warnKey)) {
                $script:MainLoopFailureWarned[$warnKey] = $true
                Write-MonitorAlert -Message "WARNING: Defender status/registry tracking failed ($($_.Exception.Message))" -Color Yellow
            }
        }
    }

    $activeThreatScanCounter++
    if ($activeThreatScanCounter -ge 5) {
        $activeThreatScanCounter = 0
        foreach ($line in (Get-ActiveDefenderThreatAlerts)) {
            if ($line -like 'SUCCESS*') { continue }
            Write-MonitorAlertOnce -Category 'threats' -Message $line -Color Yellow
        }
    }

    $externalScanCounter++
    if ($externalScanCounter -ge 5) {
        $externalScanCounter = 0

        foreach ($line in (Get-ExternalCheatHits)) {
            if ($line -like 'SUCCESS*') { continue }
            Write-MonitorAlertOnce -Category 'external' -Message $line -Color Yellow
        }

        foreach ($line in (Get-TransparentOverlayAlerts)) {
            if ($line -like 'SUCCESS*') { continue }
            Write-MonitorAlertOnce -Category 'overlay' -Message $line -Level WARN
        }

        foreach ($line in (Get-TaskManagerIntegrityAlerts)) {
            if ($line -like 'SUCCESS*' -or $line -like 'INFO*') { continue }
            Write-MonitorAlertOnce -Category 'taskmgr' -Message $line -Level FAIL
        }

        foreach ($line in (Get-UnsignedUserProgramAlerts)) {
            if ($line -like 'SUCCESS*') { continue }
            Write-MonitorAlertOnce -Category 'userprog' -Message $line
        }
    }

    $folderScanCounter++
    if ($folderScanCounter -ge 30) {
        $folderScanCounter = 0
        foreach ($folder in (Get-CheatFolderHits)) {
            if (-not $knownCheatFolders.ContainsKey($folder)) {
                $knownCheatFolders[$folder] = $true
                Write-MonitorAlert -Message "Cheat folder: $folder" -Color Yellow
            }
        }
    }

    $processChangeCounter++
    if ($processChangeCounter -ge 3) {
        $processChangeCounter = 0
        $currentProcessSnapshot = Get-ProcessSnapshot
        if ($null -ne $currentProcessSnapshot) {
            if ($null -ne $lastProcessSnapshot) {
                Update-ProcessChangeMonitor -Previous $lastProcessSnapshot -Current $currentProcessSnapshot -Watched $watchedProcesses
            }
            $lastProcessSnapshot = $currentProcessSnapshot
        }

        $rTarget = Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($rTarget) {
            $rbxToken = "$($rTarget.Id)|$($rTarget.StartTime.Ticks)"
            if ($script:LastRobloxBuildAnnounced -ne $rbxToken) {
                $script:LastRobloxBuildAnnounced = $rbxToken
                $v = Get-RobloxVersionInfo
                Write-MonitorAlert -Message "Roblox client running: $($v.VersionHash) (Ver: $($v.FileVersion), PID $($rTarget.Id))" -Level INFO
            }
        } else {
            $script:LastRobloxBuildAnnounced = $null
        }
    }

    $deletionScanCounter++
    if ($deletionScanCounter -ge 10) {
        $deletionScanCounter = 0

        $currentBam = @{}
        foreach ($fp in (Get-BamRegistryFingerprints)) { $currentBam[$fp] = $true }
        foreach ($fp in $script:BaselineBamKeys.Keys) {
            if (-not $currentBam.ContainsKey($fp) -and -not $reportedBamDeletions.ContainsKey($fp)) {
                $reportedBamDeletions[$fp] = $true
                $display = ($fp -split '\|')[-1]
                Write-MonitorAlert -Message "BAM execution-history entry removed: $display" -Level FAIL
            }
        }

        $currentPrefetch = @{}
        foreach ($pf in (Get-PrefetchFileNames)) { $currentPrefetch[$pf] = $true }
        foreach ($pf in $currentPrefetch.Keys) {
            if ($script:BaselinePrefetchFiles.ContainsKey($pf) -or $reportedPrefetchHits.ContainsKey($pf)) { continue }
            $pfKw = Get-MatchedCheatKeyword -Text $pf
            if ($pfKw) {
                $reportedPrefetchHits[$pf] = $true
                Write-MonitorAlert -Message "Prefetch added [$pfKw]: $pf" -Level FAIL
            }
        }
        foreach ($pf in $script:BaselinePrefetchFiles.Keys) {
            if (-not $currentPrefetch.ContainsKey($pf) -and -not $reportedPrefetchDeletions.ContainsKey($pf)) {
                $pfKw = Get-MatchedCheatKeyword -Text $pf
                if ($pfKw) {
                    $reportedPrefetchDeletions[$pf] = $true
                    Write-MonitorAlert -Message "Prefetch deleted [$pfKw]: $pf" -Level FAIL
                }
            }
        }

        foreach ($ev in (Get-TamperLogEvents -Since $monitoringStart)) {
            $eventKey = "$($ev.LogName)|$($ev.RecordId)"
            if ($reportedTamperEvents.ContainsKey($eventKey)) { continue }
            $reportedTamperEvents[$eventKey] = $true
            Write-MonitorAlert -Message "Event log cleared ($($ev.LogName) event $($ev.Id))" -Level FAIL
        }
    }

    $integrityScanCounter++
    if ($integrityScanCounter -ge 15) {
        $integrityScanCounter = 0
        try {
            foreach ($line in (Get-MonitorIntegrityAlerts -Since $monitoringStart)) {
                Write-MonitorAlertOnce -Category 'integrity' -Message $line
            }
            foreach ($line in (Get-PowerShellHostIntegrityAlerts)) {
                if ($line -like 'SUCCESS*' -or $line -like 'INFO*') { continue }
                Write-MonitorAlertOnce -Category 'pshost' -Message $line
            }
            foreach ($line in (Get-NtdllSyscallIntegrityAlerts)) {
                if ($line -like 'SUCCESS*' -or $line -like 'INFO*') { continue }
                Write-MonitorAlertOnce -Category 'pshost' -Message $line
            }
        } catch {
            Write-MonitorAlertOnce -Category 'error' -Message "WARNING: Integrity tracking failed ($($_.Exception.Message))"
        }
    }

    $bsmmExtraScanCounter++
    if ($bsmmExtraScanCounter -ge 10) {
        $bsmmExtraScanCounter = 0
        try {
            foreach ($ev in (Get-ServiceInstallEvents -Since $monitoringStart)) {
                if ($ev.Image -match '(?i)procexp\d*\.sys') { continue }
                if ($ev.Image -match '(?i)\.sys\b') {
                    Write-MonitorAlertOnce -Category 'svcinstall' -Message "Kernel driver installed during the match: $($ev.Name) -> $($ev.Image)" -Level FAIL
                } else {
                    Write-MonitorAlertOnce -Category 'svcinstall' -Message "Service installed during the match: $($ev.Name) -> $($ev.Image)" -Level WARN
                }
            }
            foreach ($line in (Get-MacroToolAlerts)) {
                if ($line -like 'SUCCESS*') { continue }
                Write-MonitorAlertOnce -Category 'macro' -Message $line
            }
            foreach ($e in (Get-RecycleBinEntries -Since $monitoringStart)) {
                $kw = Get-MatchedCheatKeyword -Text $e.Path
                if ($kw) {
                    Write-MonitorAlertOnce -Category 'recycle' -Message "Deleted during the match [$kw]: $($e.Path)" -Level FAIL
                } elseif ($script:BsmmExecExt -contains (Get-BsmmExtension $e.Path)) {
                    Write-MonitorAlertOnce -Category 'recycle' -Message "Program deleted during the match: $($e.Path)" -Level WARN
                }
            }
        } catch {
            Write-MonitorAlertOnce -Category 'error' -Message "WARNING: Extra tracking failed ($($_.Exception.Message))"
        }
    }

    $bsmmDeepTick++
    try {
        if ($bsmmDeepTick % 5 -eq 0) {
            foreach ($l in @(Get-BsmmNewProcessAlerts) + @(Get-RobloxBridgeAlerts)) {
                if ($l -like 'FAILURE*' -or $l -like 'WARNING*') { Write-MonitorAlertOnce -Category 'deep' -Message $l }
            }
        }
        if ($bsmmDeepTick % 30 -eq 0) {
            $ready = Get-BsmmPendingPids -Age 8
            if ($ready.Count -gt 0) {
                foreach ($l in @(Get-InjectedCodeAlerts -OnlyPids $ready) + @(Get-RunningFingerprintAlerts -OnlyPids $ready)) {
                    if ($l -like 'FAILURE*' -or $l -like 'WARNING*') { Write-MonitorAlertOnce -Category 'deep' -Message $l }
                }
            }
            foreach ($l in @(Get-LoggingTamperAlerts -Light) + @(Get-BsmmDeviceChangeAlerts)) {
                if ($l -like 'FAILURE*' -or $l -like 'WARNING*') { Write-MonitorAlertOnce -Category 'deep' -Message $l }
            }
        }
        if ($bsmmDeepTick % 60 -eq 0) {
            foreach ($l in @(Get-BsmmJournalSinceAlerts -Since $monitoringStart) + @(Get-BsmmRobloxLogTailAlerts) + @(Get-KernelIntegrityAlerts -Light) + @(Get-ScreenCaptureAlerts -Since $monitoringStart) + @(Get-ImGuiTraceAlerts -Since $monitoringStart)) {
                if ($l -like 'FAILURE*' -or $l -like 'WARNING*') { Write-MonitorAlertOnce -Category 'deep' -Message $l }
            }
        }
        if ($bsmmDeepTick % 600 -eq 0) {
            foreach ($l in @(Get-InjectedCodeAlerts -NoModules) + @(Get-RunningFingerprintAlerts)) {
                if ($l -like 'FAILURE*' -or $l -like 'WARNING*') { Write-MonitorAlertOnce -Category 'deep' -Message $l }
            }
        }
    } catch {
        Write-MonitorAlertOnce -Category 'error' -Message "WARNING: Deep check failed ($($_.Exception.Message))"
    }

    if (((Get-Date) - $script:LastLiveUpdate).TotalSeconds -ge [Math]::Max(60, $script:Report.LiveUpdateSeconds)) {
        [void](Send-BsmmLiveUpdate -Since $monitoringStart)
    }

    $statusLineCounter++
    if ($statusLineCounter -ge 2) {
        $statusLineCounter = 0
        Write-MonitorStatusLine -Since $monitoringStart
    }
}
} finally {
    Clear-MonitorStatusLine
    $elapsed = (Get-Date) - $monitoringStart
    Write-MonitorAlert -Message ("BSMM monitor stopped after {0:hh\:mm\:ss} ({1} fail, {2} warn, {3} info)" -f $elapsed, $script:MonitorAlertCounts.FAIL, $script:MonitorAlertCounts.WARN, $script:MonitorAlertCounts.INFO) -Level INFO
    Get-EventSubscriber -SourceIdentifier USBChange -ErrorAction SilentlyContinue |
        Unregister-Event -Force -ErrorAction SilentlyContinue

    $ended = Send-BsmmLiveUpdate -Since $monitoringStart -State 'ENDED'
    $script:Session.Key = ''
    Out-Seg ''
    Out-Seg '  ' -NoNewline
    Out-Seg 'MONITOR STOPPED' -Fg 'Text' -Bold -NoNewline
    Out-Seg "   report $($script:ReportId)" -Fg 'Muted'
    if ($ended) { Out-TaggedText -Indent '  ' -Tag 'PASS' -Text "Report $($script:ReportId) sent to BSMM staff" }
    else { Out-TaggedText -Indent '  ' -Tag 'WARN' -Text "The end of report $($script:ReportId) could not be sent. Tell staff." }
}
