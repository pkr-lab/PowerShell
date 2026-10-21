#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------
# Modul laden & Logging starten
# ---------------------------------------------------------

$modulePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1"
Import-Module $modulePath -ErrorAction Stop

Initialize-Logger -Level "INFO"
Write-Log -Level INFO -Message "Starte: Microsoft Store deaktivieren"

# ---------------------------------------------------------
# Admin-Check
# ---------------------------------------------------------

$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pri = [Security.Principal.WindowsPrincipal]::new($id)
if (-not $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log -Level ERROR -Message "Dieses Skript muss als Administrator ausgefuehrt werden (HKLM-Schreibzugriff)."
    throw "Administratorrechte erforderlich."
}

# ---------------------------------------------------------
# Microsoft Store per Registry-Richtlinie deaktivieren
# ---------------------------------------------------------

$regPath   = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
$valueName = "RemoveWindowsStore"

try {
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
        Write-Log -Level INFO -Message "Registry-Pfad erstellt: $regPath"
    }

    New-ItemProperty -Path $regPath -Name $valueName -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Log -Level INFO -Message "Microsoft Store deaktiviert (RemoveWindowsStore=1)"
}
catch {
    Write-Log -Level ERROR -Message "Fehler beim Deaktivieren des Stores: $($_.Exception.Message)"
    throw
}

# ---------------------------------------------------------
# Fertig
# ---------------------------------------------------------

Write-Log -Level INFO -Message "Microsoft Store wurde per Richtlinie deaktiviert. Windows-Neustart empfohlen."
