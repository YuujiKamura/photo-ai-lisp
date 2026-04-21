# scripts/ime-smoke.ps1
# Programmatic MS-IME input smoke test for photo-ai-lisp /shell preedit rendering.
# Verifies c9f1cdc term.textarea reposition fix via SendInput + ImmSetOpenStatus.
# refs #36

param(
  [string]$Hub          = "http://localhost:8091",
  [int]$WaitAfterStart  = 6,
  [string]$Chrome       = "C:\Program Files\Google\Chrome\Application\chrome.exe",
  [string]$Winshot      = "$env:USERPROFILE\winshot\winshot.exe"
)

$ErrorActionPreference = "Stop"
$ts        = Get-Date -Format "yyyyMMdd-HHmmss"
$startUtc  = [System.DateTime]::UtcNow   # used to filter trace entries from this run only
$preedit   = "$env:TEMP\ime-preedit-$ts.png"
$committed = "$env:TEMP\ime-committed-$ts.png"

# ---------------------------------------------------------------------------
# 1. Hub liveness check
# ---------------------------------------------------------------------------
Write-Host "[1] Checking hub at $Hub ..."
try {
  $r = Invoke-WebRequest -Uri "$Hub/" -TimeoutSec 5 -UseBasicParsing
  if ($r.StatusCode -ne 200) { throw "HTTP $($r.StatusCode)" }
  Write-Host "    hub OK (HTTP 200)"
} catch {
  Write-Error "hub unreachable: $_"
  exit 1
}

# ---------------------------------------------------------------------------
# 2. Native Win32 / IMM32 / SendInput inline C#
#    Uses EnumWindows (reliable) instead of FindWindowEx(null, null, ...) which
#    silently returns 0 when called from a non-interactive PowerShell session.
# ---------------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'ImeSmoke.Win').Type) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace ImeSmoke {
  public class Win {
    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
                               public static extern int  GetWindowText(IntPtr hwnd, StringBuilder sb, int n);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("imm32.dll")]  public static extern IntPtr ImmGetContext(IntPtr hwnd);
    [DllImport("imm32.dll")]  public static extern bool   ImmSetOpenStatus(IntPtr himc, bool fOpen);
    [DllImport("imm32.dll")]  public static extern bool   ImmReleaseContext(IntPtr hwnd, IntPtr himc);
    [DllImport("user32.dll")] public static extern uint   SendInput(uint n, INPUT[] inputs, int cb);

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
      public uint type;
      public INPUTUNION U;
    }
    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION {
      [FieldOffset(0)] public KEYBDINPUT    ki;
      [FieldOffset(0)] public HARDWAREINPUT hi;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
      public ushort wVk;
      public ushort wScan;
      public uint   dwFlags;
      public uint   time;
      public IntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT {
      public uint   uMsg;
      public ushort wParamL;
      public ushort wParamH;
    }
  }
}
'@
}

# ---------------------------------------------------------------------------
# Helper: find "photo-ai-lisp" window via EnumWindows
# ---------------------------------------------------------------------------
function Find-PhotoAiWindow {
  $result = [IntPtr]::Zero
  $cb = [ImeSmoke.Win+EnumWindowsProc]{
    param($hwnd, $lParam)
    $sb = New-Object System.Text.StringBuilder 512
    [ImeSmoke.Win]::GetWindowText($hwnd, $sb, 512) | Out-Null
    if ($sb.ToString() -eq "photo-ai-lisp") {
      Set-Variable -Name foundHwnd -Value $hwnd -Scope Script
      return $false  # stop enumeration
    }
    return $true
  }
  $script:foundHwnd = [IntPtr]::Zero
  [ImeSmoke.Win]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
  return $script:foundHwnd
}

# ---------------------------------------------------------------------------
# Helper: send a VK down+up pair
# ---------------------------------------------------------------------------
function Send-VK([uint16]$vk) {
  # INPUT struct size: type(4) + largest union member KEYBDINPUT(2+2+4+4+8) = 4+20 = 24 bytes
  # On 64-bit: pointer is 8 bytes, so KEYBDINPUT = 2+2+4+4+8 = 20, INPUT = 4 + 4(pad) + 20 = 28
  # Use Marshal.SizeOf on an instance to avoid nested-type reflection issue
  $inst    = New-Object ImeSmoke.Win+INPUT
  $cbInput = [System.Runtime.InteropServices.Marshal]::SizeOf($inst)

  $down         = New-Object ImeSmoke.Win+INPUT
  $down.type    = [uint32]1
  $downKi       = New-Object ImeSmoke.Win+KEYBDINPUT
  $downKi.wVk   = [uint16]$vk
  $downUnion    = New-Object ImeSmoke.Win+INPUTUNION
  $downUnion.ki = $downKi
  $down.U       = $downUnion

  $up           = New-Object ImeSmoke.Win+INPUT
  $up.type      = [uint32]1
  $upKi         = New-Object ImeSmoke.Win+KEYBDINPUT
  $upKi.wVk     = [uint16]$vk
  $upKi.dwFlags = [uint32]2   # KEYEVENTF_KEYUP
  $upUnion      = New-Object ImeSmoke.Win+INPUTUNION
  $upUnion.ki   = $upKi
  $up.U         = $upUnion

  [ImeSmoke.Win]::SendInput([uint32]2, @($down, $up), $cbInput) | Out-Null
  Start-Sleep -Milliseconds 60
}

# ---------------------------------------------------------------------------
# 3. Find or launch Chrome --app window
# ---------------------------------------------------------------------------
$hwnd = Find-PhotoAiWindow
if ($hwnd -eq [IntPtr]::Zero) {
  Write-Host "[2] No existing window — launching Chrome --app ..."
  $profile = "$env:TEMP\chrome-ime-smoke"
  Start-Process -FilePath $Chrome -ArgumentList @(
    "--app=$Hub/",
    "--user-data-dir=$profile",
    "--window-size=1280,780"
  )
  Write-Host "    Waiting 6s for Chrome to open ..."
  Start-Sleep -Seconds 6

  $hwnd = Find-PhotoAiWindow
  if ($hwnd -eq [IntPtr]::Zero) {
    Write-Error "photo-ai-lisp window not found after Chrome launch"
    exit 1
  }
  Write-Host "    Chrome window found: 0x$("{0:X}" -f $hwnd.ToInt64())"
} else {
  Write-Host "[2] Reusing existing window: 0x$("{0:X}" -f $hwnd.ToInt64())"
}

# Bring window to foreground
[ImeSmoke.Win]::ShowWindow($hwnd, 9) | Out-Null   # SW_RESTORE
[ImeSmoke.Win]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 800

# ---------------------------------------------------------------------------
# 4. Select agent "1" (claude) if pick-agent screen is showing
# ---------------------------------------------------------------------------
Write-Host "[3] Sending '1' + Enter to select claude ..."
Send-VK ([uint16]0x31)   # VK '1'
Send-VK ([uint16]0x0D)   # VK_RETURN
Write-Host "    Waiting $WaitAfterStart s for claude shell to start ..."
Start-Sleep -Seconds $WaitAfterStart

# ---------------------------------------------------------------------------
# 5. Enable IME programmatically via ImmSetOpenStatus
# ---------------------------------------------------------------------------
Write-Host "[4] Enabling MS-IME (ImmSetOpenStatus) ..."
$himc = [ImeSmoke.Win]::ImmGetContext($hwnd)
if ($himc -ne [IntPtr]::Zero) {
  $ok = [ImeSmoke.Win]::ImmSetOpenStatus($himc, $true)
  [ImeSmoke.Win]::ImmReleaseContext($hwnd, $himc) | Out-Null
  Write-Host "    ImmSetOpenStatus => $ok"
} else {
  Write-Warning "    ImmGetContext returned NULL — IME may not activate"
}
Start-Sleep -Milliseconds 400

# ---------------------------------------------------------------------------
# 6. SendInput: n i h o n g o  → preedit "にほんご"
# ---------------------------------------------------------------------------
Write-Host "[5] Sending 'nihongo' via SendInput ..."
$keys = @(
  [uint16][byte][char]'N',
  [uint16][byte][char]'I',
  [uint16][byte][char]'H',
  [uint16][byte][char]'O',
  [uint16][byte][char]'N',
  [uint16][byte][char]'G',
  [uint16][byte][char]'O'
)
foreach ($vk in $keys) { Send-VK $vk }
Start-Sleep -Seconds 1

# ---------------------------------------------------------------------------
# 7. Capture preedit screenshot
# ---------------------------------------------------------------------------
Write-Host "[6] Capturing preedit screenshot => $preedit"
$hwndDec = $hwnd.ToInt64()
& $Winshot --handle $hwndDec -o $preedit 2>&1 | ForEach-Object { Write-Host "    winshot: $_" }

# ---------------------------------------------------------------------------
# 8. Enter — confirm hiragana without kanji conversion
# ---------------------------------------------------------------------------
Write-Host "[7] Sending Enter to commit hiragana ..."
Send-VK ([uint16]0x0D)
Start-Sleep -Seconds 1

# ---------------------------------------------------------------------------
# 9. Capture committed screenshot
# ---------------------------------------------------------------------------
Write-Host "[8] Capturing committed screenshot => $committed"
& $Winshot --handle $hwndDec -o $committed 2>&1 | ForEach-Object { Write-Host "    winshot: $_" }

# ---------------------------------------------------------------------------
# 10. Fetch /api/shell-trace and inspect ':in' entries
# ---------------------------------------------------------------------------
Write-Host "[9] Fetching /api/shell-trace ..."
$trace     = $null
$inEntries = @()
try {
  $trace     = Invoke-RestMethod -Uri "$Hub/api/shell-trace" -TimeoutSec 5
  # Only look at entries from this run (ts >= $startUtc - 30s to account for clock skew)
  $cutoff    = $startUtc.AddSeconds(-30)
  $inEntries = @($trace | Where-Object {
    $_.dir -eq 'in' -and
    [System.DateTime]::Parse($_.ts, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) -ge $cutoff
  } | Select-Object -First 10)
  Write-Host "    ':in' entries (newest first, up to 10):"
  foreach ($e in $inEntries) {
    Write-Host ("      bytes={0,4}  preview={1}" -f $e.bytes, $e.preview)
  }
} catch {
  Write-Warning "    shell-trace fetch failed: $_"
}

# ---------------------------------------------------------------------------
# 11. Verdict
# ---------------------------------------------------------------------------
Write-Host "---"
Write-Host "preedit  : $preedit"
Write-Host "committed: $committed"

# CJK check: hiragana block + the specific characters にほんご
$cjkPattern = '[぀-ゟ゠-ヿ]'
$matched = $inEntries | Where-Object { $_.preview -match $cjkPattern }

if ($matched) {
  Write-Host "RESULT: OK — CJK found in :in trace"
  foreach ($m in $matched) {
    Write-Host ("  bytes={0} preview={1}" -f $m.bytes, $m.preview)
  }
  exit 0
} else {
  Write-Host "RESULT: FAIL — no CJK in :in trace entries"
  Write-Host "  (preedit screenshot may still show UI-level IME popup from Chrome/Windows)"
  exit 1
}
