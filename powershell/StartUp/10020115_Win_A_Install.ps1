<#
.SYNOPSIS
Erste-Einrichtung: Erstellt Verzeichnisstruktur und prueft Voraussetzungen.

.DESCRIPTION
Wird einmalig bei Ersteinrichtung ausgefuehrt (nicht durch den Watchdog,
da er im StartUp-Ordner liegt, der vom Watchdog ausgeschlossen wird).
Stellt sicher, dass die benoetigten Basisordner existieren und
erstellt eine Software-Inventur des Systems.
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Modul laden & Logging starten
# ---------------------------------------------------------

$modulePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1"
Import-Module $modulePath -ErrorAction Stop

Initialize-Logger -Level "INFO"
Write-Log -Level INFO -Message "=== Erste-Einrichtung gestartet ==="

# Fehler-Handler nur in PS7+
if ($PSVersionTable.PSVersion.Major -ge 7) {
    try {
        Register-EngineEvent -SourceIdentifier PowerShell.OnScriptError -Action {
            try {
                $msg = $_.SourceArgs[0].Exception.Message
                Write-Log -Level "ERROR" -Message "PowerShell-Fehler: $msg"
            } catch {}
        } | Out-Null
    } catch {}
}

# ---------------------------------------------------------
# Verzeichnisstruktur sicherstellen
# ---------------------------------------------------------

$baseDirs = @(
    "C:\Users\Public\10020115_WinScripts\Logs",
    "C:\Users\Public\10020115_WinScripts\Win11_C"
)

foreach ($dir in $baseDirs) {
    if (-not (Test-Path $dir)) {
        try {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Log -Level INFO -Message "Verzeichnis erstellt: $dir"
        } catch {
            Write-Log -Level WARN -Message "Verzeichnis konnte nicht erstellt werden: $dir - $($_.Exception.Message)"
        }
    } else {
        Write-Log -Level DEBUG -Message "Verzeichnis vorhanden: $dir"
    }
}

# ---------------------------------------------------------
# Software-Inventur
# ---------------------------------------------------------

Write-Log -Level INFO -Message "=== Software-Inventur ==="

$classicPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

function Get-InstalledPrograms {
    param([string]$RegistryPath)
    if (-not (Test-Path $RegistryPath)) {
        Write-Log -Level WARN -Message "Registry-Pfad nicht gefunden: $RegistryPath"
        return
    }
    Get-ChildItem $RegistryPath -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $props = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
            if ($props.DisplayName) {
                [PSCustomObject]@{
                    Name        = $props.DisplayName
                    Version     = $props.DisplayVersion
                    Publisher   = $props.Publisher
                    InstallDate = $props.InstallDate
                }
            }
        } catch {
            Write-Log -Level WARN -Message "Fehler beim Lesen eines Registry-Eintrags: $($_.Exception.Message)"
        }
    }
}

try {
    $classicApps = foreach ($path in $classicPaths) {
        Get-InstalledPrograms -RegistryPath $path
    }

    $sorted = $classicApps | Where-Object { $_ } | Sort-Object Name
    if (-not $sorted -or $sorted.Count -eq 0) {
        Write-Log -Level WARN -Message "Keine klassischen Programme gefunden."
    } else {
        Write-Log -Level INFO -Message "Klassische Programme: $($sorted.Count) gefunden."
        foreach ($app in $sorted) {
            Write-Log -Level INFO -Message "  $($app.Name) | v$($app.Version) | $($app.Publisher)"
        }
    }
} catch {
    Write-Log -Level ERROR -Message "Fehler bei klassischen Programmen: $($_.Exception.Message)"
}

try {
    $uwpApps = Get-AppxPackage -ErrorAction Stop | Sort-Object Name
    Write-Log -Level INFO -Message "UWP/Store-Apps: $($uwpApps.Count) gefunden."
    foreach ($app in $uwpApps) {
        Write-Log -Level INFO -Message "  UWP: $($app.Name) | v$($app.Version)"
    }
} catch {
    Write-Log -Level ERROR -Message "Fehler bei UWP-Apps: $($_.Exception.Message)"
}

# ---------------------------------------------------------
# Fertig
# ---------------------------------------------------------

Write-Log -Level INFO -Message "=== Erste-Einrichtung abgeschlossen ==="
