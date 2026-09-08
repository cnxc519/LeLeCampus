param([string]$text = "")
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait($text)
Write-Host ("typed: " + $text)
