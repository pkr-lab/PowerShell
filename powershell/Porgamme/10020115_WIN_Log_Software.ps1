# Modul laden
$modulePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1"
Import-Module $modulePath -ErrorAction Stop

Initialize-Logger -Level "INFO"

Write-Log -Level INFO -Message "=== Software-Inventur gestartet ==="

# Registry-Pfade für klassische Programme
$classicPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

function Get-InstalledPrograms {
    param([string]$RegistryPath)

    if (Test-Path $RegistryPath) {
        Get-ChildItem $RegistryPath | ForEach-Object {
            $props = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
            if ($props.DisplayName) {
                [PSCustomObject]@{
                    Name        = $props.DisplayName
                    Version     = $props.DisplayVersion
                    Publisher   = $props.Publisher
                    InstallDate = $props.InstallDate
                }
            }
        }
    }
}

# === Klassische Programme ===
Write-Log -Level INFO -Message "=== Klassische Programme ==="

try {
    $classicApps = foreach ($path in $classicPaths) {
        Get-InstalledPrograms -RegistryPath $path
    }

    if ($classicApps.Count -eq 0) {
        Write-Log -Level WARN -Message "Keine klassischen Programme gefunden."
    }
    else {
        foreach ($app in $classicApps | Sort-Object Name) {
            Write-Log -Level INFO -Message "Programm: $($app.Name) | Version: $($app.Version) | Publisher: $($app.Publisher)"
        }
    }
}
catch {
    Write-Log -Level ERROR -Message "Fehler beim Auslesen klassischer Programme: $($_.Exception.Message)"
}

# === UWP / Store Apps ===
Write-Log -Level INFO -Message "=== UWP / Store Apps ==="

try {
    $uwpApps = Get-AppxPackage |
        Select-Object Name, Version, Publisher |
        Sort-Object Name

    foreach ($app in $uwpApps) {
        Write-Log -Level INFO -Message "UWP-App: $($app.Name) | Version: $($app.Version) | Publisher: $($app.Publisher)"
    }
}
catch {
    Write-Log -Level ERROR -Message "Fehler beim Auslesen der UWP-Apps: $($_.Exception.Message)"
}

Write-Log -Level INFO -Message "=== Software-Inventur abgeschlossen ==="