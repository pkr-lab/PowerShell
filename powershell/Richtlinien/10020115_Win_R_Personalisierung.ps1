#Requires -Version 5.1
Set-StrictMode -Version Latest

# ----------------------------------------------------------------
# GLOBAL ERROR HANDLING – ALLE FEHLER AUTOMATISCH INS LOG
# ----------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$Global:PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# Optional: In PS7+ OnScriptError abonnieren, in 5.1 nicht verfügbar
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Register-EngineEvent -SourceIdentifier PowerShell.OnScriptError -Action {
        try {
            $msg = $_.SourceArgs[0].Exception.Message
            Write-Log -Level 'ERROR' -Message "PowerShell-Fehler: $msg"
        } catch { }
    } | Out-Null
}

# ----------------------------------------------------------------
# MODUL LADEN & LOGGING STARTEN
# ----------------------------------------------------------------

$modulePath = 'C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1'
Import-Module -Name $modulePath -ErrorAction Stop

Initialize-Logger -Level 'INFO'
Write-Log -Level INFO -Message 'Starte Gesamt-Konfiguration - Personalisierung'

# ----------------------------------------------------------------
# ADMIN-CHECK (für HKLM zwingend)
# ----------------------------------------------------------------

function Test-Admin {
    $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pri = [Security.Principal.WindowsPrincipal]::new($id)
    return $pri.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Log -Level ERROR -Message 'Dieses Skript muss als Administrator ausgeführt werden (HKLM-Policies).'
    throw 'Administratorrechte erforderlich.'
}

# ----------------------------------------------------------------
# REGISTRY-PFADE
# ----------------------------------------------------------------

$RegExplorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$RegSystem   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
$RegActive   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop'
$RegPers     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
$RegSysPol   = 'HKLM:\Software\Policies\Microsoft\Windows\System'

# ----------------------------------------------------------------
# 1) ALLE EINSTELLUNGEN AUF STANDARD ZURÜCKSETZEN
# ----------------------------------------------------------------

Write-Log -Level INFO -Message 'Setze alle Personalisierungsrichtlinien auf Standard zurück'

# Fehlschläge beim Remove sind möglich, daher SilentlyContinue und kein Throw hier
foreach ($item in @(
    @{Path=$RegExplorer; Name='NoThemesTab'},
    @{Path=$RegExplorer; Name='NoSaveSettings'},
    @{Path=$RegExplorer; Name='ThemeFile'},
    @{Path=$RegSystem;   Name='NoDispAppearancePage'},
    @{Path=$RegSystem;   Name='NoDispCPL'},
    @{Path=$RegActive;   Name='NoChangingWallPaper'},
    @{Path=$RegPers;     Name='DesktopWallpaper'},
    @{Path=$RegPers;     Name='DesktopWallpaperStyle'},
    @{Path=$RegPers;     Name='LockScreenImage'},
    @{Path=$RegPers;     Name='LockScreenImagePath'},
    @{Path=$RegPers;     Name='ForceLockScreenBackground'},
    @{Path=$RegPers;     Name='NoChangingLockScreen'},
    @{Path=$RegSysPol;   Name='Wallpaper'},
    @{Path=$RegSysPol;   Name='WallpaperStyle'}
)) {
    try { Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue } catch { }
}

Write-Log -Level INFO -Message 'Alle Richtlinien erfolgreich zurückgesetzt'

# Fehlende Pfade (HKCU UND HKLM) sicherstellen
foreach ($path in @($RegExplorer,$RegSystem,$RegActive,$RegPers,$RegSysPol)) {
    try {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
            Write-Log -Level INFO -Message "Registry-Pfad neu erstellt: $path"
        }
    } catch {
        Write-Log -Level ERROR -Message "Fehler beim Erstellen des Registry-Pfads: $path - $($_.Exception.Message)"
        throw
    }
}

# ----------------------------------------------------------------
# 2) HINTERGRUND UND SPERRBILDSCHIRM SETZEN (Dateien prüfen)
# ----------------------------------------------------------------

$UserWallpaper   = 'C:\Users\Public\10020115_WinScripts\Win11_C\Bilder\Hintergrund\Desktop.png'
$DesktopImage    = $UserWallpaper
$LockImageScreen = 'C:\Users\Public\10020115_WinScripts\Win11_C\Bilder\Hintergrund\Sperrbildschirm.png'

Write-Log -Level INFO -Message 'Setze Desktop- und Sperrbildschirmbilder'

# Benutzer-Desktop (HKCU)
if (Test-Path $UserWallpaper) {
    try {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -Value $UserWallpaper -Type String
        Write-Log -Level INFO -Message "Benutzer-Hintergrund gesetzt: $UserWallpaper"

        # Zuverlässiger anwenden: SystemParametersInfo und Explorer neu starten
        $sig = @'
using System;
using System.Runtime.InteropServices;
public class NativeMethods {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
        Add-Type -TypeDefinition $sig -ErrorAction SilentlyContinue | Out-Null
        [void][NativeMethods]::SystemParametersInfo(20, 0, $UserWallpaper, 0x01 -bor 0x02) # SPI_SETDESKWALLPAPER + SPIF
        Start-Sleep -Milliseconds 500
        # Explorer sanft neu starten, damit Änderungen sicher sichtbar sind
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Process explorer.exe
    } catch {
        Write-Log -Level ERROR -Message "Fehler beim Setzen des Benutzer-Hintergrunds: $($_.Exception.Message)"
    }
} else {
    Write-Log -Level ERROR -Message "Benutzer-Hintergrund nicht gefunden: $UserWallpaper"
}

Start-Sleep -Seconds 2

# Sperrbildschirm-Datei prüfen (Policy wird später gesetzt)
if (Test-Path $LockImageScreen) {
    Write-Log -Level INFO -Message "Sperrbildschirmbild gefunden: $LockImageScreen"
} else {
    Write-Log -Level ERROR -Message "Sperrbildschirmbild nicht gefunden: $LockImageScreen"
}

Start-Sleep -Seconds 2

# ----------------------------------------------------------------
# 3) RICHTLINIEN WIEDER AKTIVIEREN – ADMX-KONFORM
# ----------------------------------------------------------------

Write-Log -Level INFO -Message 'Setze ADMX-konforme Richtlinien - Aenderungen werden gesperrt'

try {
    # Desktop-Hintergrund (Computer-Policy für alle Benutzer)
    Set-ItemProperty -Path $RegSysPol -Name 'Wallpaper' -Value $DesktopImage   -Type String
    Set-ItemProperty -Path $RegSysPol -Name 'WallpaperStyle' -Value '10'       -Type String
    Write-Log -Level INFO -Message 'ADMX-Policy für Desktop-Hintergrund gesetzt (HKLM\...\System)'

    # Sperrbildschirm (Computer-Policy)
    Set-ItemProperty -Path $RegPers -Name 'LockScreenImage'      -Value $LockImageScreen -Type String
    Set-ItemProperty -Path $RegPers -Name 'NoChangingLockScreen' -Value 1               -Type DWord
    Write-Log -Level INFO -Message 'ADMX-Policy für Sperrbildschirm gesetzt (HKLM\...\Personalization)'

    # Benutzer-Sperren (HKCU) – nur Hintergrundbild und Design sperren.
    # NoDispCPL und NoSaveSettings werden NICHT gesetzt, damit der Benutzer
    # weiterhin Bildschirmauflösung, Anordnung (Multi-Monitor) und
    # Desktop-Icon-Positionen ändern kann.
    Set-ItemProperty -Path $RegExplorer -Name 'NoThemesTab'         -Value 1 -Type DWord
    Set-ItemProperty -Path $RegActive   -Name 'NoChangingWallPaper' -Value 1 -Type DWord
    Set-ItemProperty -Path $RegExplorer -Name 'ThemeFile'           -Value $UserWallpaper -Type String
    Write-Log -Level INFO -Message 'Benutzer-Richtlinien gesetzt: Hintergrundbild + Design gesperrt; Bildschirm-Einstellungen erlaubt'
}
catch {
    Write-Log -Level ERROR -Message "Fehler beim Setzen der ADMX-Richtlinien: $($_.Exception.Message)"
    throw
}

# Gruppenrichtlinien aktualisieren (optional, falls GPOs vorhanden sind)
try {
    gpupdate /target:computer /force | Out-Null
} catch { }

Write-Log -Level INFO -Message 'Gesamt-Konfiguration abgeschlossen'