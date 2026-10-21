#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Global:PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# ---------------------------------------------------------
# Logging-Modul laden
# ---------------------------------------------------------
$modulePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1"
Import-Module $modulePath -ErrorAction Stop

Initialize-Logger -Level "INFO"
Write-Log -Level INFO -Message "Starte OEM-Branding & Legal Notice Konfiguration"

# Fehler-Events nur in PS7+ (in 5.1 nicht verfügbar)
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
# Admin-Check (HKLM-Schreibzugriff)
# ---------------------------------------------------------
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pri = [Security.Principal.WindowsPrincipal]::new($id)
if (-not $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log -Level ERROR -Message "Dieses Skript muss als Administrator ausgefuehrt werden."
    throw "Administratorrechte erforderlich."
}

# ---------------------------------------------------------
# Konfiguration – hier zentral anpassen
# ---------------------------------------------------------
$Manufacturer   = "DLRG-Jugend Andernach | EDV & Technik"
$SupportHours   = "10-18 Uhr"
$SupportPhone   = "+49 1575 6018834"
$SupportURL     = "https://andernach.dlrg.de"
$Model          = "Jugendnotebook"
$LogoPath       = "C:\Users\Public\10020115_WinScripts\Win11_C\Bilder\Logo\Logo.bmp"

$LegalCaption   = "Nutzungshinweis"
$LegalText      = "Dieses Geraet ist Eigentum der DLRG-Jugend Andernach. Unbefugte Nutzung ist untersagt. Bei Fragen wende dich an: $SupportPhone"

# ---------------------------------------------------------
# Helper: Registry-Wert nur schreiben wenn nötig
# ---------------------------------------------------------
function Set-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [Microsoft.Win32.RegistryValueKind]$Kind = [Microsoft.Win32.RegistryValueKind]::String
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
        Write-Log -Level DEBUG -Message "Registry-Pfad erstellt: $Path"
    }
    $current = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $current -or $current.$Name -ne $Value) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Kind -Force
        Write-Log -Level DEBUG -Message "Registry gesetzt: $Path\$Name = $Value"
    }
}

# ---------------------------------------------------------
# 1) OEM-Informationen (Systemeigenschaften → Support)
# ---------------------------------------------------------
Write-Log -Level INFO -Message "Setze OEM-Branding..."

$oemPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
try {
    Set-RegValue -Path $oemPath -Name "Manufacturer"   -Value $Manufacturer
    Set-RegValue -Path $oemPath -Name "Model"          -Value $Model
    Set-RegValue -Path $oemPath -Name "SupportHours"   -Value $SupportHours
    Set-RegValue -Path $oemPath -Name "SupportPhone"   -Value $SupportPhone
    Set-RegValue -Path $oemPath -Name "SupportURL"     -Value $SupportURL

    if (Test-Path $LogoPath) {
        Set-RegValue -Path $oemPath -Name "Logo" -Value $LogoPath
        Write-Log -Level INFO -Message "OEM-Logo gesetzt: $LogoPath"
    } else {
        Write-Log -Level WARN -Message "OEM-Logo nicht gefunden (wird uebersprungen): $LogoPath"
    }

    Write-Log -Level INFO -Message "OEM-Branding abgeschlossen."
} catch {
    Write-Log -Level ERROR -Message "Fehler beim OEM-Branding: $($_.Exception.Message)"
    throw
}

# ---------------------------------------------------------
# 2) Legal Notice (Anmeldebildschirm-Hinweis)
# ---------------------------------------------------------
Write-Log -Level INFO -Message "Setze Legal Notice..."

$winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
try {
    Set-RegValue -Path $winlogonPath -Name "LegalNoticeCaption" -Value $LegalCaption
    Set-RegValue -Path $winlogonPath -Name "LegalNoticeText"    -Value $LegalText
    Write-Log -Level INFO -Message "Legal Notice gesetzt: '$LegalCaption'"
} catch {
    Write-Log -Level ERROR -Message "Fehler beim Setzen der Legal Notice: $($_.Exception.Message)"
    throw
}

# ---------------------------------------------------------
# 3) Computerbeschreibung setzen
# ---------------------------------------------------------
Write-Log -Level INFO -Message "Setze Computerbeschreibung..."

try {
    $srvPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
    Set-RegValue -Path $srvPath -Name "srvcomment" -Value "$Manufacturer - $Model"
    Write-Log -Level INFO -Message "Computerbeschreibung gesetzt."
} catch {
    Write-Log -Level WARN -Message "Computerbeschreibung konnte nicht gesetzt werden: $($_.Exception.Message)"
}

# ---------------------------------------------------------
# Fertig
# ---------------------------------------------------------
Write-Log -Level INFO -Message "OEM-Branding & Legal Notice Konfiguration abgeschlossen."
Write-Log -Level INFO -Message "Aenderungen werden nach einem Neustart vollstaendig sichtbar."
