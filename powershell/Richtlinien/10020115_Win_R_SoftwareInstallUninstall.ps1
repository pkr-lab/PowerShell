#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------
# Modul laden & Logging starten
# ---------------------------------------------------------

$modulePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1"
Import-Module $modulePath -ErrorAction Stop

Initialize-Logger -Level "INFO"
Write-Log -Level INFO -Message "Rollback: Setze Software-Richtlinien auf Windows-Standard zurueck"

# ---------------------------------------------------------
# Admin-Check (SRP liegt in HKLM)
# ---------------------------------------------------------

$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pri = [Security.Principal.WindowsPrincipal]::new($id)
if (-not $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log -Level ERROR -Message "HKLM-Schreibzugriff erfordert Administratorrechte."
    throw "Administratorrechte erforderlich."
}

# ---------------------------------------------------------
# 1) HKLM – SRP (Software Restriction Policies) entfernen
# ---------------------------------------------------------

$srpPath = "HKLM:\Software\Policies\Microsoft\Windows\Safer\CodeIdentifiers"

if (Test-Path $srpPath) {
    try {
        Remove-Item -Path $srpPath -Recurse -Force -ErrorAction Stop
        Write-Log -Level INFO -Message "SRP-Einstellungen entfernt: $srpPath"
    } catch {
        Write-Log -Level ERROR -Message "Fehler beim Entfernen von SRP: $($_.Exception.Message)"
    }
} else {
    Write-Log -Level INFO -Message "SRP-Einstellungen waren nicht gesetzt (kein Eintrag gefunden)."
}

# ---------------------------------------------------------
# 2) HKCU – Benutzerbeschraenkungen entfernen
# ---------------------------------------------------------

$removals = @(
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "SettingsPageVisibility" },
    @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\Appx";                   Name = "BlockRemoval" },
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Uninstall"; Name = "NoAddRemovePrograms" },
    @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\Control Panel";           Name = "DisableProgramsControlPanel" }
)

foreach ($item in $removals) {
    if (Test-Path $item.Path) {
        try {
            Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue
            Write-Log -Level INFO -Message "Entfernt: $($item.Name) aus $($item.Path)"
        } catch {
            Write-Log -Level WARN -Message "Konnte nicht entfernen: $($item.Name) - $($_.Exception.Message)"
        }
    } else {
        Write-Log -Level DEBUG -Message "Pfad nicht vorhanden (nichts zu tun): $($item.Path)"
    }
}

# ---------------------------------------------------------
# Fertig
# ---------------------------------------------------------

Write-Log -Level INFO -Message "Rollback abgeschlossen – alle Software-Richtlinien auf Standard."
