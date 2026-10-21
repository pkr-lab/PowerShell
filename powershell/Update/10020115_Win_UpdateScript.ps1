<#
.SYNOPSIS
Windows-Updates, Treiberupdates und Winget-Software-Updates installieren.

.PARAMETER RUN_IN_BACKGROUND
Interner Switch: wird beim Selbst-Neustart im Hintergrundmodus übergeben.

.PARAMETER LOGFILE
Interner Parameter: Logdateiname für den Hintergrundprozess.
#>

param(
    [switch]$RUN_IN_BACKGROUND,
    [string]$LOGFILE
)

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging-Modul importieren
# ---------------------------------------------------------

$modulePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1"
Import-Module $modulePath -ErrorAction Stop

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
# Hintergrundmodus: Erster Aufruf startet sich selbst hidden
# ---------------------------------------------------------

if (-not $RUN_IN_BACKGROUND) {
    $logFileName = "update_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
    Initialize-Logger -FileName $logFileName -Level "INFO" -ConsoleOutput $true -MaxSizeMB 10

    Write-Log -Level INFO -Message "Starte Update-Skript im Hintergrund (Logfile: $logFileName)..."

    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -RUN_IN_BACKGROUND -LOGFILE `"$logFileName`"" `
        -WindowStyle Hidden

    Write-Log -Level INFO -Message "Hintergrundprozess gestartet."
    exit 0
}

# ---------------------------------------------------------
# Hintergrundmodus: Logger mit übergebenem Dateinamen initialisieren
# ---------------------------------------------------------

if (-not $LOGFILE) { throw "LOGFILE-Parameter fehlt." }

Initialize-Logger -FileName $LOGFILE -Level "INFO" -ConsoleOutput $false -MaxSizeMB 10
Write-Log -Level INFO -Message "Update-Skript gestartet (Hintergrundmodus)."

# ExecutionPolicy für diesen Prozess
Set-ExecutionPolicy Bypass       -Scope Process     -Force
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------
# PSWindowsUpdate sicherstellen
# ---------------------------------------------------------

if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Log -Level INFO -Message "PSWindowsUpdate nicht gefunden – wird installiert..."
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop | Out-Null
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -ErrorAction Stop
        Write-Log -Level INFO -Message "PSWindowsUpdate erfolgreich installiert."
    } catch {
        Write-Log -Level ERROR -Message "Installation von PSWindowsUpdate fehlgeschlagen: $($_.Exception.Message)"
        exit 1
    }
}

Import-Module PSWindowsUpdate -ErrorAction Stop

# ---------------------------------------------------------
# Windows- und Treiberupdates abrufen
# ---------------------------------------------------------

Write-Log -Level INFO -Message "Suche nach Windows- und Treiberupdates..."

$allUpdates = $null
try {
    $allUpdates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -ErrorAction Stop
} catch {
    Write-Log -Level ERROR -Message "Fehler beim Abrufen der Updates: $($_.Exception.Message)"
}

$windowsUpdates = $allUpdates | Where-Object { $_.UpdateType -ne "Driver" }
$driverUpdates  = $allUpdates | Where-Object { $_.UpdateType -eq "Driver" }

if ($windowsUpdates) {
    Write-Log -Level INFO -Message "Gefundene Windows-Updates: $($windowsUpdates.Count)"
    $windowsUpdates | ForEach-Object { Write-Log -Level INFO -Message "  - $($_.Title)" }
} else {
    Write-Log -Level INFO -Message "Keine Windows-Updates verfuegbar."
}

if ($driverUpdates) {
    Write-Log -Level INFO -Message "Gefundene Treiber-Updates: $($driverUpdates.Count)"
    $driverUpdates | ForEach-Object { Write-Log -Level INFO -Message "  - $($_.Title)" }
} else {
    Write-Log -Level INFO -Message "Keine Treiber-Updates verfuegbar."
}

# ---------------------------------------------------------
# Updates installieren
# ---------------------------------------------------------

if ($allUpdates -and $allUpdates.Count -gt 0) {
    Write-Log -Level INFO -Message "Installiere $($allUpdates.Count) Updates..."
    try {
        $results = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop
        foreach ($res in $results) {
            $exitCode = if ($res.HResult) { $res.HResult } else { "OK" }
            Write-Log -Level INFO -Message "Update: $($res.Title) | Ergebnis: $($res.Result) | ExitCode: $exitCode"
        }
        Write-Log -Level INFO -Message "Windows-Update-Installation abgeschlossen."
    } catch {
        Write-Log -Level ERROR -Message "Fehler bei der Update-Installation: $($_.Exception.Message)"
    }
} else {
    Write-Log -Level INFO -Message "Keine Updates zur Installation vorhanden."
}

# Treiber-Suche in Windows Update aktivieren
try {
    $drvPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
    Set-ItemProperty -Path $drvPath -Name "SearchOrderConfig" -Value 1 -Type DWord
    Write-Log -Level INFO -Message "Treiberupdates ueber Windows Update aktiviert."
} catch {
    Write-Log -Level WARN -Message "Treiberupdate-Einstellung konnte nicht gesetzt werden: $($_.Exception.Message)"
}

# ---------------------------------------------------------
# Winget Software-Updates
# ---------------------------------------------------------

Write-Log -Level INFO -Message "Pruefe Winget-Updates..."

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Log -Level WARN -Message "winget nicht gefunden – Software-Updates werden uebersprungen."
} else {
    try {
        # Quellen aktualisieren
        winget source update 2>&1 | Out-Null

        # Verfuegbare Upgrades als Text auslesen (JSON-Ausgabe ist winget-versionsabhaengig)
        $upgradeOutput = winget upgrade --accept-source-agreements 2>&1 | Out-String

        if ($upgradeOutput -match "Keine Pakete" -or $upgradeOutput -match "No packages") {
            Write-Log -Level INFO -Message "Keine Winget-Updates verfuegbar."
        } else {
            Write-Log -Level INFO -Message "Winget-Updates gefunden. Starte Installation..."
            winget upgrade --all --silent --accept-package-agreements --accept-source-agreements 2>&1 |
                ForEach-Object { Write-Log -Level INFO -Message "winget: $_" }
            Write-Log -Level INFO -Message "Winget-Updates abgeschlossen."
        }
    } catch {
        Write-Log -Level ERROR -Message "Fehler bei Winget-Updates: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------
# Fertig
# ---------------------------------------------------------

Write-Log -Level INFO -Message "Update-Skript erfolgreich beendet."
Close-Logger
