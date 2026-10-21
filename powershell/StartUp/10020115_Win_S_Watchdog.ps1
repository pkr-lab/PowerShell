# ---------------------------------------------------------
# LOGGER – direkt integriert (verbessert)
# ---------------------------------------------------------

# Globale Variablen
$Global:LogFilePath = $null
$Global:LogLevel = "INFO"
$Global:EnableConsoleOutput = $true
$Global:MaxLogSizeMB = 5
$Global:DefaultLogFolder = "C:\Users\Public\10020115_WinScripts\Logs\"

function Initialize-Logger {
    param(
        [string]$FileName = "log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log",
        [ValidateSet("DEBUG","INFO","WARN","ERROR")]
        [string]$Level = "INFO",
        [bool]$ConsoleOutput = $true,
        [int]$MaxSizeMB = 5
    )

    if (-not (Test-Path $Global:DefaultLogFolder)) {
        New-Item -Path $Global:DefaultLogFolder -ItemType Directory -Force | Out-Null
    }

    $Path = Join-Path $Global:DefaultLogFolder $FileName

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }

    $Global:LogFilePath = $Path
    $Global:LogLevel = $Level
    $Global:EnableConsoleOutput = $ConsoleOutput
    $Global:MaxLogSizeMB = $MaxSizeMB

    Write-Log -Level "INFO" -Message "Logger initialisiert. Logfile: $Path"
}

function Rotate-Log {
    if (-not (Test-Path $Global:LogFilePath)) { return }

    $sizeMB = (Get-Item $Global:LogFilePath).Length / 1MB

    if ($sizeMB -ge $Global:MaxLogSizeMB) {
        $timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
        $archivePath = "$Global:LogFilePath.$timestamp.bak"

        Move-Item -Path $Global:LogFilePath -Destination $archivePath -Force
        New-Item -Path $Global:LogFilePath -ItemType File -Force | Out-Null
        Write-Log -Level "INFO" -Message "Log rotiert: $archivePath"
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("DEBUG","INFO","WARN","ERROR")]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $levels = @{ DEBUG = 1; INFO = 2; WARN = 3; ERROR = 4 }
    if ($levels[$Level] -lt $levels[$Global:LogLevel]) {
        return
    }

    Rotate-Log

    $timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp] [$Level] $Message"

    Add-Content -Path $Global:LogFilePath -Value $entry

    if ($Global:EnableConsoleOutput) {
        switch ($Level) {
            "ERROR" { Write-Host $entry -ForegroundColor Red }
            "WARN"  { Write-Host $entry -ForegroundColor Yellow }
            "INFO"  { Write-Host $entry -ForegroundColor Cyan }
            "DEBUG" { Write-Host $entry -ForegroundColor DarkGray }
        }
    }
}

function Get-LogConfig {
    [PSCustomObject]@{
        LogFilePath     = $Global:LogFilePath
        LogLevel        = $Global:LogLevel
        ConsoleOutput   = $Global:EnableConsoleOutput
        MaxLogSizeMB    = $Global:MaxLogSizeMB
        DefaultFolder   = $Global:DefaultLogFolder
    }
}

# ---------------------------------------------------------
# Internetverbindung prüfen (mit Retry und Timeout)
# Wartezeit zwischen Versuchen standardmäßig 10 Sekunden
# ---------------------------------------------------------
function Test-InternetConnection {
    param(
        [int]$Retries = 5,
        [int]$DelaySeconds = 10,
        [int]$TimeoutSec = 10
    )

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri "https://www.google.com/generate_204" -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
            if ($resp.StatusCode -in 200,204) {
                Write-Log -Level "INFO" -Message "Internetverbindung erkannt (Versuch $i/$Retries)."
                return $true
            }
        }
        catch {
            Write-Log -Level "WARN" -Message "Keine Internetverbindung (Versuch $i/$Retries): $($_.Exception.Message)"
            if ($i -lt $Retries) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }

    Write-Log -Level "ERROR" -Message "Keine Internetverbindung nach $Retries Versuchen."
    return $false
}

# ---------------------------------------------------------
# Sicherstellen und Backup: Alle .ps1 Dateien konvertieren
# - Backup wird angelegt: <file>.bak.<timestamp>
# - Zielkodierung: UTF-16LE (Unicode) mit BOM (Windows PowerShell kompatibel)
# ---------------------------------------------------------
function Ensure-AllScriptsEncoding {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    if (-not (Test-Path $RootPath)) {
        Write-Log -Level "WARN" -Message "Ensure-AllScriptsEncoding: RootPath existiert nicht: $RootPath"
        return
    }

    $timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
    $ps1Files = Get-ChildItem -Path $RootPath -Filter "*.ps1" -Recurse -File -ErrorAction SilentlyContinue

    foreach ($file in $ps1Files) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $needsConversion = $true

            if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                # UTF-16 LE BOM vorhanden -> kompatibel
                $needsConversion = $false
            } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                # UTF-8 with BOM -> kompatibel
                $needsConversion = $false
            }

            if ($needsConversion) {
                $backupPath = "$($file.FullName).bak.$timestamp"
                Copy-Item -LiteralPath $file.FullName -Destination $backupPath -Force
                $content = Get-Content -Raw -LiteralPath $file.FullName -ErrorAction Stop
                # Konvertiere zu UTF-16LE (Unicode) mit BOM
                $content | Out-File -LiteralPath $file.FullName -Encoding Unicode -Force
                Write-Log -Level "INFO" -Message "Konvertiert zu UTF-16LE und Backup erstellt: $($file.FullName) -> $backupPath"
            } else {
                Write-Log -Level "DEBUG" -Message "Kodierung OK: $($file.FullName)"
            }
        }
        catch {
            Write-Log -Level "WARN" -Message "Ensure-AllScriptsEncoding fehlgeschlagen: $($file.FullName) - $($_.Exception.Message)"
        }
    }
}

# ---------------------------------------------------------
# Logger initialisieren
# ---------------------------------------------------------
Initialize-Logger -Level "INFO"
Write-Log -Level INFO -Message "Starte kombinierten Import- und WatchDog-Prozess."

# ---------------------------------------------------------
# 0. Konfiguration
# ---------------------------------------------------------
$Source = "C:\Users\DLRG-JugendAndernach\DLRG\DLRG OG Andernach Projekte-Jugendnotebooks - Jugendnotebooks\Win11_C"
$DestinationRoot = "C:\Users\Public\10020115_WinScripts"
$Destination = Join-Path $DestinationRoot "Win11_C"

# Relativer Pfad zur Message-Script-Datei (relativ zu Source / Destination)
$MessageScriptRelative = "Software\Scripte\StartUp\10020115_Win_S_Messagebox.ps1"
$MessageScriptSource = Join-Path $Source $MessageScriptRelative
$MessageScriptDestination = Join-Path $Destination $MessageScriptRelative

# WatchDog / Skriptpfade
$ScriptRoot = Join-Path $Destination "Software\Scripte"
$StartUpExcludePath = Join-Path $Destination "Software\Scripte\StartUp"

Write-Log -Level INFO -Message "Prüfe Internetverbindung vor Kopiervorgang..."

# ---------------------------------------------------------
# 1. IMPORT-SCHRITT (nur wenn Internet vorhanden)
# ---------------------------------------------------------
if (-not (Test-InternetConnection -Retries 5 -DelaySeconds 10 -TimeoutSec 10)) {
    Write-Log -Level "ERROR" -Message "Abbruch: Keine Internetverbindung. Versuche Message-Script auszuführen."

    if (Test-Path -Path $MessageScriptSource) {
        Write-Log -Level "INFO" -Message "Führe Message-Script aus (Quelle): $MessageScriptSource"
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MessageScriptSource
            Write-Log -Level "INFO" -Message "Message-Script ausgeführt: $MessageScriptSource"
        } catch {
            Write-Log -Level "WARN" -Message "Ausführen des Message-Scripts (Quelle) fehlgeschlagen: $($_.Exception.Message)"
        }
    }
    elseif (Test-Path -Path $MessageScriptDestination) {
        Write-Log -Level "INFO" -Message "Führe Message-Script aus (Ziel): $MessageScriptDestination"
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MessageScriptDestination
            Write-Log -Level "INFO" -Message "Message-Script ausgeführt: $MessageScriptDestination"
        } catch {
            Write-Log -Level "WARN" -Message "Ausführen des Message-Scripts (Ziel) fehlgeschlagen: $($_.Exception.Message)"
        }
    }
    else {
        Write-Log -Level "WARN" -Message "Message-Script nicht gefunden (Quelle: $MessageScriptSource, Ziel: $MessageScriptDestination)."
    }

    Write-Log -Level INFO -Message "Gesamter Prozess beendet."
    exit 1
}

Write-Log -Level INFO -Message "Internetverbindung vorhanden. Starte Kopiervorgang fuer Win11_C"
Write-Log -Level INFO -Message "Quelle: $Source"
Write-Log -Level INFO -Message "Ziel: $Destination"

# Entferne mögliche Offline-Attribute aus Quelldateien (robust)
Write-Log -Level INFO -Message "Entferne moegliche Offline-Attribute aus Quelldateien..."
try {
    if (Test-Path -Path $Source) {
        Get-ChildItem -Path $Source -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $item = Get-Item -LiteralPath $_.FullName -Force
                if ($item.Attributes -band [System.IO.FileAttributes]::Offline) {
                    $item.Attributes = $item.Attributes -bxor [System.IO.FileAttributes]::Offline
                }
            } catch {
                Write-Log -Level "WARN" -Message "Attrib entfernen fehlgeschlagen: $($_.FullName) - $($_.Exception.Message)"
            }
        }
    } else {
        Write-Log -Level "ERROR" -Message "Quellpfad existiert nicht: $Source"
        Write-Log -Level INFO -Message "Gesamter Prozess beendet."
        exit 1
    }
} catch {
    Write-Log -Level "WARN" -Message "Fehler beim Entfernen von Attributen: $($_.Exception.Message)"
}

# Lösche vorhandenen Zielordner falls vorhanden
if (Test-Path -Path $Destination) {
    Write-Log -Level INFO -Message "Loesche vorhandenen Ordner Win11_C..."
    try {
        Remove-Item -Path $Destination -Recurse -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 300
    } catch {
        Write-Log -Level "ERROR" -Message "Loeschen des Zielordners fehlgeschlagen: $($_.Exception.Message)"
        Write-Log -Level INFO -Message "Gesamter Prozess beendet."
        exit 1
    }
} else {
    Write-Log -Level INFO -Message "Ordner Win11_C existiert nicht, kein Loeschen notwendig."
}

# Erstelle Zielordner
Write-Log -Level INFO -Message "Erstelle Zielordner Win11_C..."
try {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
} catch {
    Write-Log -Level "ERROR" -Message "Erstellen des Zielordners fehlgeschlagen: $($_.Exception.Message)"
    Write-Log -Level INFO -Message "Gesamter Prozess beendet."
    exit 1
}

# Kopiere Dateien
Write-Log -Level INFO -Message "Kopiere Dateien nach Win11_C..."
try {
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force -ErrorAction Stop
    Write-Log -Level INFO -Message "Kopiervorgang abgeschlossen."
} catch {
    Write-Log -Level "ERROR" -Message "Kopiervorgang fehlgeschlagen: $($_.Exception.Message)"
    Write-Log -Level INFO -Message "Gesamter Prozess beendet."
    exit 1
}

# Entferne versteckte / system / read-only Attribute im Ziel (setze Normal)
Write-Log -Level INFO -Message "Entferne versteckte Attribute im Ziel..."
try {
    Get-ChildItem -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $it = Get-Item -LiteralPath $_.FullName -Force
            $it.Attributes = 'Normal'
        } catch {
            Write-Log -Level "WARN" -Message "Attribute setzen fehlgeschlagen: $($_.FullName) - $($_.Exception.Message)"
        }
    }
    try { (Get-Item -LiteralPath $Destination -Force).Attributes = 'Normal' } catch {}
} catch {
    Write-Log -Level "WARN" -Message "Fehler beim Entfernen von Attributen im Ziel: $($_.Exception.Message)"
}

# ---------------------------------------------------------
# 2. WARTEN (3 Sekunden)
# ---------------------------------------------------------
Write-Log -Level INFO -Message "Warte 3 Sekunden, bevor WatchDog startet..."
Start-Sleep -Seconds 3

# ---------------------------------------------------------
# 3. WATCHDOG – Kodierung sicherstellen, Backup, Skripte rekursiv ausführen
# - Ignoriere alle Skripte unter dem exakten StartUp-Pfad
# ---------------------------------------------------------
Write-Log -Level INFO -Message "WatchDog gestartet."
Write-Log -Level INFO -Message "Suche nach Skripten in: $ScriptRoot"
Write-Log -Level DEBUG -Message "StartUp-Ausschlusspfad: $StartUpExcludePath"

# 1) Sicherstellen: alle Skripte konvertieren und Backup anlegen
try {
    if (Test-Path -Path $ScriptRoot) {
        Ensure-AllScriptsEncoding -RootPath $ScriptRoot
    } else {
        Write-Log -Level "WARN" -Message "ScriptRoot existiert nicht: $ScriptRoot"
    }
} catch {
    Write-Log -Level "ERROR" -Message "Fehler in Ensure-AllScriptsEncoding: $($_.Exception.Message)"
}

# 2) Skripte ausführen (separate Prozesse für Isolation; Kodierung ist jetzt kompatibel)
$Scripts = @()
if (Test-Path -Path $ScriptRoot) {
    # Normalisiere Ausschlusspfad mit abschließendem Backslash für StartsWith-Vergleich
    $excludeNormalized = [IO.Path]::GetFullPath($StartUpExcludePath)
    if (-not $excludeNormalized.EndsWith('\')) { $excludeNormalized += '\' }

    $Scripts = Get-ChildItem -Path $ScriptRoot -Filter "*.ps1" -Recurse -File -ErrorAction SilentlyContinue |
               Where-Object {
                   $full = [IO.Path]::GetFullPath($_.FullName)
                   # Ausschluss: exakter StartUp-Pfad (inkl. Unterordner) wird ausgeschlossen
                   -not ($full.StartsWith($excludeNormalized, [System.StringComparison]::InvariantCultureIgnoreCase))
               }
} else {
    Write-Log -Level "WARN" -Message "ScriptRoot existiert nicht: $ScriptRoot"
}

if ($Scripts -and $Scripts.Count -gt 0) {
    foreach ($Script in $Scripts) {
        Write-Log -Level "INFO" -Message "Starte Script (separate process): $($Script.FullName)"
        try {
            $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
            $argList = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$Script.FullName)
            Start-Process -FilePath $psExe -ArgumentList $argList -Wait -NoNewWindow -ErrorAction Stop
            Write-Log -Level "INFO" -Message "Fertig: $($Script.Name)"
        }
        catch {
            Write-Log -Level "ERROR" -Message "Fehler in $($Script.Name): $($_.Exception.Message)"
        }
    }
} else {
    Write-Log -Level "WARN" -Message "Keine Skripte gefunden (nach Ausschluss von StartUp)."
}

Write-Log -Level INFO -Message "WatchDog abgeschlossen."
Write-Log -Level INFO -Message "Gesamter Prozess beendet."