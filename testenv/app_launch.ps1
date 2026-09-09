# 桌面端 App 测试驱动：清僵尸 → 启动 → 前置 → 截图
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Name U -Namespace N -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out System.Drawing.Rectangle r);
'@

Get-Process LeLeDaiPao -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

$env:PATH = 'D:/qt/6.9.3/mingw_64/bin;' + $env:PATH
Start-Process 'E:/LeLeDaiPao/app/build/Desktop_Qt_6_9_3_MinGW_64_bit-Debug/LeLeDaiPao.exe'
Start-Sleep -Seconds 7

$p = Get-Process LeLeDaiPao -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output 'FAIL: not running'; exit 1 }
if ($p.MainWindowHandle -eq [IntPtr]::Zero) { Write-Output 'FAIL: no main window'; exit 1 }
[N.U]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Milliseconds 800

$r = New-Object System.Drawing.Rectangle
[N.U]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
Write-Output ("RECT " + $r.X + "," + $r.Y + " " + $r.Width + "x" + $r.Height)

$b = New-Object System.Drawing.Bitmap($r.Width, $r.Height)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.CopyFromScreen($r.X, $r.Y, 0, 0, $r.Size)
$b.Save('C:/Users/cnxc/Downloads/state1.png')
$g.Dispose(); $b.Dispose()
Write-Output 'SAVED'
