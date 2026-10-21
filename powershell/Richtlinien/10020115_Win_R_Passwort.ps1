#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Modul laden & Logging starten
# ---------------------------------------------------------

$modulePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1"
Import-Module $modulePath -ErrorAction Stop

Initialize-Logger -Level "INFO"
Write-Log -Level INFO -Message "Starte PIN-Komplexitaet GPO-Konfiguration"

# Globaler Fehler-Handler (nur PS7+; in 5.1 nicht verfügbar)
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
# Admin-Check
# ---------------------------------------------------------

$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pri = [Security.Principal.WindowsPrincipal]::new($id)
if (-not $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log -Level ERROR -Message "Dieses Skript muss als Administrator ausgefuehrt werden (HKLM-Schreibzugriff)."
    throw "Administratorrechte erforderlich."
}

# ---------------------------------------------------------
# Registry-Pfad erstellen
# ---------------------------------------------------------

$RegPIN = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork\PINComplexity"

try {
    New-Item $RegPIN -Force | Out-Null
    Write-Log -Level INFO -Message "Registry-Pfad sichergestellt: $RegPIN"
}
catch {
    Write-Log -Level ERROR -Message "Fehler beim Erstellen des Registry-Pfads: $($_.Exception.Message)"
    throw
}

# ---------------------------------------------------------
# PIN-Komplexitaet setzen
# ---------------------------------------------------------

try {
    Set-ItemProperty -Path $RegPIN -Name "Digits"            -Value 1   -Type DWord
    Set-ItemProperty -Path $RegPIN -Name "LowercaseLetters"  -Value 1   -Type DWord
    Set-ItemProperty -Path $RegPIN -Name "UppercaseLetters"  -Value 1   -Type DWord
    Set-ItemProperty -Path $RegPIN -Name "SpecialCharacters" -Value 1   -Type DWord
    Set-ItemProperty -Path $RegPIN -Name "MinimumPINLength"  -Value 8   -Type DWord
    Set-ItemProperty -Path $RegPIN -Name "Expiration"        -Value 180 -Type DWord

    Write-Log -Level INFO -Message "PIN-Komplexitaet gesetzt: Mindestlaenge=8, Ablauf=180 Tage, Gross/Klein/Ziffern/Sonderzeichen=aktiv"
}
catch {
    Write-Log -Level ERROR -Message "Fehler beim Setzen der PIN-Komplexitaet: $($_.Exception.Message)"
    throw
}

# ---------------------------------------------------------
# Fertig
# ---------------------------------------------------------

Write-Log -Level INFO -Message "PIN-Komplexitaet GPO-Konfiguration abgeschlossen"
