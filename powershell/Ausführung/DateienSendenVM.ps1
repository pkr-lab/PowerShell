<#
.SYNOPSIS
Hilfsbefehle für Hyper-V-Testumgebung: Dateien in VM kopieren, GPO-Backup/Import.

.DESCRIPTION
Dieses Skript enthält häufig benötigte Befehle für die Arbeit mit der Hyper-V-Testmaschine.
Befehle einzeln ausführen oder gezielt auskommentieren.

Voraussetzungen:
- Hyper-V-Modul installiert (Windows Feature)
- GroupPolicy-Modul (RSAT) für GPO-Befehle
- Administrator-Rechte
#>

#Requires -Version 5.1

param(
    [string]$VMName          = "*Win11ProTestUmgebung*",
    [string]$SourceZip       = "C:\Users\$env:USERNAME\IdeaProjects\PowerShell.zip",
    [string]$DestinationInVM = "C:\Users\Win11ProTest\Desktop\PowerShell.zip",
    [string]$GpoName         = "MeineTestGPO",
    [string]$GpoBackupPath   = "C:\GPO-Backups"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# 1) Datei in VM kopieren (Hyper-V Guest Services erforderlich)
# ---------------------------------------------------------
function Send-FileToVM {
    Write-Host "Kopiere '$SourceZip' -> VM '$VMName' : '$DestinationInVM' ..."

    if (-not (Test-Path $SourceZip)) {
        Write-Warning "Quelldatei nicht gefunden: $SourceZip"
        return
    }

    Copy-VMFile -VMName $VMName `
                -SourcePath $SourceZip `
                -DestinationPath $DestinationInVM `
                -CreateFullPath `
                -FileSource Host `
                -ErrorAction Stop

    Write-Host "Datei erfolgreich in VM kopiert."
}

# ---------------------------------------------------------
# 2) Hyper-V Local Account Dialog öffnen (bei VM-Erstkonfiguration)
# ---------------------------------------------------------
function Open-HyperVLocalAccount {
    Write-Host "Öffne Hyper-V Local Account Setup..."
    Start-Process "ms-cxh:localonly"
}

# ---------------------------------------------------------
# 3) GPO exportieren (Backup)
# ---------------------------------------------------------
function Export-GpoBackup {
    Write-Host "Exportiere GPO '$GpoName' nach '$GpoBackupPath' ..."

    if (-not (Test-Path $GpoBackupPath)) {
        New-Item -Path $GpoBackupPath -ItemType Directory -Force | Out-Null
    }

    Backup-GPO -Name $GpoName -Path $GpoBackupPath -ErrorAction Stop
    Write-Host "GPO-Backup abgeschlossen."
}

# ---------------------------------------------------------
# 4) GPO importieren (Restore)
# ---------------------------------------------------------
function Import-GpoBackup {
    Write-Host "Importiere GPO '$GpoName' aus '$GpoBackupPath' ..."

    Import-GPO -BackupGpoName $GpoName `
               -Path $GpoBackupPath `
               -TargetName $GpoName `
               -ErrorAction Stop

    Write-Host "GPO-Import abgeschlossen."
}

# ---------------------------------------------------------
# Hauptmenü
# ---------------------------------------------------------
Write-Host ""
Write-Host "Verfuegbare Aktionen:"
Write-Host "  1) Datei in VM senden"
Write-Host "  2) Hyper-V Local Account oeffnen"
Write-Host "  3) GPO exportieren"
Write-Host "  4) GPO importieren"
Write-Host ""

$choice = Read-Host "Aktion waehlen (1-4)"

switch ($choice) {
    "1" { Send-FileToVM }
    "2" { Open-HyperVLocalAccount }
    "3" { Export-GpoBackup }
    "4" { Import-GpoBackup }
    default { Write-Warning "Ungültige Eingabe." }
}
