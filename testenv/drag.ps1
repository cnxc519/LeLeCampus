param([int]$x = 220, [int]$y1 = 500, [int]$y2 = 200)
Add-Type @'
using System; using System.Runtime.InteropServices;
public class DR {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
}
'@
[DR]::SetCursorPos($x, $y1) | Out-Null
Start-Sleep -Milliseconds 120
[DR]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)   # down
Start-Sleep -Milliseconds 80
$steps = 10
for ($i = 1; $i -le $steps; $i++) {
  $yy = $y1 + [int](($y2 - $y1) * $i / $steps)
  [DR]::SetCursorPos($x, $yy) | Out-Null
  Start-Sleep -Milliseconds 25
}
Start-Sleep -Milliseconds 100
[DR]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)   # up
Write-Host "dragged $y1 -> $y2"
