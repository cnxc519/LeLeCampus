# 桌面端应用驱动辅助：前置窗口 + 截图 / 点击 / 输入
# 用法: powershell -File app_drive.ps1 -Action shot|click|type|key -X 100 -Y 200 -Text "abc" -Out out.png
param(
    [string]$Action = 'shot',
    [int]$X = 0,
    [int]$Y = 0,
    [string]$Text = '',
    [string]$Out = 'C:/Users/cnxc/Downloads/app_shot.png'
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -Name U -Namespace N -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out System.Drawing.Rectangle r);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
'@

$p = Get-Process LeLeDaiPao -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output 'APP_NOT_RUNNING'; exit 1 }
[N.U]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Milliseconds 700

$r = New-Object System.Drawing.Rectangle
[N.U]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
Write-Output ("RECT " + $r.X + "," + $r.Y + " " + $r.Width + "x" + $r.Height)

switch ($Action) {
    'shot' {
        $b = New-Object System.Drawing.Bitmap($r.Width, $r.Height)
        $g = [System.Drawing.Graphics]::FromImage($b)
        $g.CopyFromScreen($r.X, $r.Y, 0, 0, $r.Size)
        $b.Save($Out)
        $g.Dispose(); $b.Dispose()
        Write-Output 'SAVED'
    }
    'click' {
        [N.U]::SetCursorPos($X, $Y); Start-Sleep -Milliseconds 200
        [N.U]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
        [N.U]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
        Write-Output 'CLICKED'
    }
    'type' {
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        Start-Sleep -Milliseconds 100
        [System.Windows.Forms.SendKeys]::SendWait('{DEL}')
        Start-Sleep -Milliseconds 100
        [System.Windows.Forms.SendKeys]::SendWait($Text)
        Write-Output 'TYPED'
    }
    'key' {
        [System.Windows.Forms.SendKeys]::SendWait($Text)
        Write-Output 'KEYED'
    }
}
