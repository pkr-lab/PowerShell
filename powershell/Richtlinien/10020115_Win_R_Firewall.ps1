#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------
# Modul laden & Logging starten
# ---------------------------------------------------------

$modulePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1"
Import-Module $modulePath -ErrorAction Stop

Initialize-Logger -Level "INFO"
Write-Log -Level INFO -Message "Starte Firewall-Konfiguration"

# ---------------------------------------------------------
# Admin-Check
# ---------------------------------------------------------

$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pri = [Security.Principal.WindowsPrincipal]::new($id)
if (-not $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log -Level ERROR -Message "Administratorrechte erforderlich."
    throw "Dieses Skript muss als Administrator ausgefuehrt werden."
}

# ---------------------------------------------------------
# 1) Firewall-Profile aktivieren (Domain, Private, Public)
# ---------------------------------------------------------

Write-Log -Level INFO -Message "Aktiviere Windows-Firewall fuer alle Profile..."

try {
    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -ErrorAction Stop
    Write-Log -Level INFO -Message "Firewall aktiviert: Domain, Private, Public"
} catch {
    Write-Log -Level ERROR -Message "Fehler beim Aktivieren der Firewall: $($_.Exception.Message)"
    throw
}

# ---------------------------------------------------------
# 2) Standard-Eingehend: Blockieren | Ausgehend: Erlauben
# ---------------------------------------------------------

try {
    Set-NetFirewallProfile -Profile Domain,Private -DefaultInboundAction Block -DefaultOutboundAction Allow
    Set-NetFirewallProfile -Profile Public         -DefaultInboundAction Block -DefaultOutboundAction Allow
    Write-Log -Level INFO -Message "Standardregeln gesetzt: Eingehend=Block, Ausgehend=Allow"
} catch {
    Write-Log -Level ERROR -Message "Fehler beim Setzen der Standardregeln: $($_.Exception.Message)"
    throw
}

# ---------------------------------------------------------
# 3) Benoetigte eingehende Regeln aktivieren
# ---------------------------------------------------------

$rulesToEnable = @(
    "Remotedesktop-UserMode-In-TCP",   # RDP (falls benoetigt)
    "FPS-ICMP4-ERQ-In",                # Ping IPv4
    "FPS-ICMP6-ERQ-In"                 # Ping IPv6
)

foreach ($rule in $rulesToEnable) {
    try {
        $existing = Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue
        if ($existing) {
            Enable-NetFirewallRule -Name $rule -ErrorAction Stop
            Write-Log -Level INFO -Message "Firewall-Regel aktiviert: $rule"
        } else {
            Write-Log -Level WARN -Message "Firewall-Regel nicht gefunden (uebersprungen): $rule"
        }
    } catch {
        Write-Log -Level WARN -Message "Fehler bei Regel '$rule': $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------
# 4) Sicherheits-Haertung fuer Public-Profil
# ---------------------------------------------------------

try {
    Set-NetFirewallProfile -Profile Public `
        -AllowInboundRules $false `
        -AllowLocalFirewallRules $false `
        -AllowUnicastResponseToMulticast $false

    Write-Log -Level INFO -Message "Public-Profil gehaertet (keine lokalen Regeln, kein Multicast-Antwort)."
} catch {
    Write-Log -Level WARN -Message "Public-Profil-Haertung teilweise fehlgeschlagen: $($_.Exception.Message)"
}

# ---------------------------------------------------------
# 5) Firewall-Status ausgeben
# ---------------------------------------------------------

try {
    $profiles = Get-NetFirewallProfile -ErrorAction Stop
    foreach ($p in $profiles) {
        Write-Log -Level INFO -Message "Profil '$($p.Name)': Enabled=$($p.Enabled), Inbound=$($p.DefaultInboundAction), Outbound=$($p.DefaultOutboundAction)"
    }
} catch {
    Write-Log -Level WARN -Message "Status-Abfrage fehlgeschlagen: $($_.Exception.Message)"
}

# ---------------------------------------------------------
# Fertig
# ---------------------------------------------------------

Write-Log -Level INFO -Message "Firewall-Konfiguration abgeschlossen."
