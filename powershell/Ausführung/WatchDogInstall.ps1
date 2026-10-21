<#
.SYNOPSIS
Richtet den GPO-Watchdog als geplante Aufgabe ein, die bei jedem Benutzer-Login startet.

.DESCRIPTION
Muss im INTERAKTIVEN Benutzerkontext ausgeführt werden (NICHT als Administrator).
Erstellt einen Scheduled Task für den aktuellen Benutzer und setzt einen Run-Key,
der den Task beim Login startet.

.PARAMETER TaskName
Name der geplanten Aufgabe. Standard: "GPO-Watchdog"

.PARAMETER ScriptPath
Pfad zum Watchdog-Skript. Standard: C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\StartUp\10020115_Win_S_Watchdog.ps1
#>

#Requires -Version 5.1

param(
    [string]$TaskName   = "GPO-Watchdog",
    [string]$ScriptPath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\StartUp\10020115_Win_S_Watchdog.ps1"
)

$ErrorActionPreference = "Stop"

$RunKeyPath  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunKeyName  = "GPOWatchdogStarter"
$RunKeyValue = "schtasks.exe /run /tn `"$TaskName`""

# ---------------------------------------------------------
# 0) Benutzerkontext prüfen
# ---------------------------------------------------------
$currentUser = (Get-CimInstance Win32_ComputerSystem).UserName

if ([string]::IsNullOrWhiteSpace($currentUser)) {
    Write-Warning "Kein interaktiver Benutzer erkannt. Bitte PowerShell normal (nicht als Administrator) öffnen."
    exit 1
}

Write-Host "Aktueller Benutzer: $currentUser"

# Sicherheitswarnung, wenn als erhöhter Prozess gestartet
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pri = [Security.Principal.WindowsPrincipal]::new($id)
if ($pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Dieses Skript läuft als Administrator. Der Run-Key wird im Admin-Profil gesetzt, nicht im Benutzerprofil."
    Write-Warning "Empfehlung: PowerShell ohne 'Als Administrator' starten."
}

# ---------------------------------------------------------
# 1) Watchdog-Skriptpfad prüfen
# ---------------------------------------------------------
if (-not (Test-Path $ScriptPath)) {
    Write-Warning "Watchdog-Skript nicht gefunden: $ScriptPath"
    Write-Warning "Bitte sicherstellen, dass der Pfad korrekt ist, bevor der Task registriert wird."
}

# ---------------------------------------------------------
# 2) Alte Aufgabe entfernen (falls vorhanden)
# ---------------------------------------------------------
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Vorhandene Aufgabe '$TaskName' entfernt."
}

# ---------------------------------------------------------
# 3) Aufgabe erstellen
# ---------------------------------------------------------
$action    = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

$principal = New-ScheduledTaskPrincipal -UserId $currentUser -RunLevel Highest

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -ErrorAction Stop
    Write-Host "Aufgabe '$TaskName' registriert für Benutzer: $currentUser"
} catch {
    Write-Error "Fehler beim Registrieren der Aufgabe: $_"
    exit 2
}

# ---------------------------------------------------------
# 4) Run-Key setzen (startet Task bei Logon)
# ---------------------------------------------------------
$existingVal = Get-ItemProperty -Path $RunKeyPath -Name $RunKeyName -ErrorAction SilentlyContinue

if ($existingVal) {
    Set-ItemProperty  -Path $RunKeyPath -Name $RunKeyName -Value $RunKeyValue
    Write-Host "Run-Key aktualisiert: $RunKeyName"
} else {
    New-ItemProperty  -Path $RunKeyPath -Name $RunKeyName -Value $RunKeyValue -PropertyType String | Out-Null
    Write-Host "Run-Key erstellt: $RunKeyName"
}

# ---------------------------------------------------------
# 5) Kontrolle
# ---------------------------------------------------------
Start-Sleep -Seconds 1
Get-ScheduledTask -TaskName $TaskName |
    Select-Object TaskName, @{Name='Principal'; Expression={$_.Principal.UserId}} |
    Format-List

Write-Host "Setup abgeschlossen. Task '$TaskName' startet beim naechsten Login."
