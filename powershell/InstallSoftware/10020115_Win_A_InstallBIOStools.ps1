#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =====================================================================
#  Logging-Modul laden
# =====================================================================
$modulePath = 'C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1'
Import-Module -Name $modulePath -ErrorAction Stop

Initialize-Logger -Level 'INFO'
Write-Log -Level INFO -Message "Scriptstart: Geraetepruefung & BIOS-Tool-Installation"

# =====================================================================
#  Helper-Funktionen
# =====================================================================

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = [Security.Principal.WindowsPrincipal]::new($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-HasHPCMSL {
    if (Get-InstalledModule -Name 'HPCMSL' -ErrorAction SilentlyContinue) { return $true }
    if (Get-Module -ListAvailable -Name 'HPCMSL')                         { return $true }
    return $false
}

function Ensure-PackageInfra {
    Write-Log -Level INFO -Message "Stelle Paket-Infrastruktur sicher (NuGet, PSGallery)..."

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop | Out-Null
    } catch {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
    }

    try {
        $pg = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
        if ($pg.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
        }
    } catch {
        Register-PSRepository -Default -ErrorAction Stop
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
    }

    Write-Log -Level INFO -Message "Paket-Infrastruktur bereit."
}

function Install-LenovoSystemUpdate {
    param(
        [string]$InstallerPath = "LenovoBiosInstall\system_update.exe"
    )

    if (-not (Test-Path $InstallerPath)) {
        Write-Log -Level ERROR -Message "Lenovo Installer nicht gefunden: $InstallerPath"
        throw "Lenovo Installer fehlt. Bitte von https://support.lenovo.com herunterladen."
    }

    Write-Log -Level INFO -Message "Starte Lenovo System Update Installation: $InstallerPath"
    Start-Process -FilePath $InstallerPath -ArgumentList "/VERYSILENT /NORESTART" -Wait -ErrorAction Stop
    Write-Log -Level INFO -Message "Lenovo System Update erfolgreich installiert."
}

# =====================================================================
#  Gerätehersteller ermitteln
# =====================================================================

$manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer.Trim()
Write-Log -Level INFO -Message "Geraetehersteller erkannt: $manufacturer"

# =====================================================================
#  Hauptlogik
# =====================================================================

try {
    switch -Wildcard ($manufacturer) {

        "HP*" {
            Write-Log -Level INFO -Message "HP-Geraet erkannt – pruefe HPCMSL..."

            if (Test-HasHPCMSL) {
                Write-Log -Level INFO -Message "HPCMSL bereits installiert. Kein Handlungsbedarf."
                exit 0
            }

            Write-Log -Level INFO -Message "HPCMSL nicht gefunden – Installation wird vorbereitet..."
            Ensure-PackageInfra

            $scope = if (Test-IsAdmin) { 'AllUsers' } else { 'CurrentUser' }
            Write-Log -Level INFO -Message "Installations-Scope: $scope"

            Install-Module -Name 'HPCMSL' -Scope $scope -Force -AcceptLicense -ErrorAction Stop
            Import-Module HPCMSL -ErrorAction Stop

            $ver = (Get-Module HPCMSL).Version
            Write-Log -Level INFO -Message "HPCMSL erfolgreich installiert. Version: $ver"
            exit 0
        }

        "Lenovo*" {
            Write-Log -Level INFO -Message "Lenovo-Geraet erkannt – installiere Lenovo System Update..."
            Install-LenovoSystemUpdate
            exit 0
        }

        default {
            Write-Log -Level WARN -Message "Unbekannter Hersteller '$manufacturer' – keine Installation durchgefuehrt."
            exit 0
        }
    }
} catch {
    Write-Log -Level ERROR -Message "Kritischer Fehler: $($_.Exception.Message)"
    exit 1
}
