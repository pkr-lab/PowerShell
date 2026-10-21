<#
.SYNOPSIS
Kopiert .dotx-Vorlagen in %APPDATA%\Microsoft\Templates, setzt den Word-Benutzervorlagenpfad in der Registry
und öffnet jede Vorlage einmal mit einer einzigen Word COM-Instanz (readonly).
#>

param(
    [string]$ModulePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Software\Scripte\Logging.psm1",
    [string]$TemplateSourcePath = "C:\Users\Public\10020115_WinScripts\Win11_C\Vorlagen",
    [ValidateSet("DEBUG","INFO","WARN","ERROR")]
    [string]$LogLevel = "INFO",
    [string[]]$OfficeVersions = @("16.0","15.0","14.0","12.0"),
    [bool]$OpenInWord = $true
)

# --- Logging-Modul laden ---
if (-not (Test-Path -Path $ModulePath)) {
    Write-Error "Logging-Modul nicht gefunden: $ModulePath"
    exit 1
}
Import-Module -Name $ModulePath -ErrorAction Stop
Initialize-Logger -Level $LogLevel

try {
    Write-Log -Level INFO -Message "Starte Kopiervorgang der Word-Vorlagen."

    # --- Quellordner prüfen ---
    if (-not (Test-Path -Path $TemplateSourcePath -PathType Container)) {
        Write-Log -Level ERROR -Message "Vorlagenordner wurde nicht gefunden: $TemplateSourcePath"
        throw "Vorlagenordner fehlt."
    }

    # --- Templates sammeln ---
    $Templates = Get-ChildItem -Path $TemplateSourcePath -Filter *.dotx -File -ErrorAction Stop
    if (-not $Templates -or $Templates.Count -eq 0) {
        Write-Log -Level WARN -Message "Keine .dotx Dateien im Ordner gefunden: $TemplateSourcePath"
        throw "Keine Vorlagen vorhanden."
    }

    # --- Zielordner (per Benutzer) ---
    $WordTemplateFolder = Join-Path $env:APPDATA "Microsoft\Templates"
    if (-not (Test-Path -Path $WordTemplateFolder)) {
        Write-Log -Level WARN -Message "Word-Vorlagenordner existiert nicht – wird erstellt: $WordTemplateFolder"
        New-Item -Path $WordTemplateFolder -ItemType Directory -Force | Out-Null
    }

    # --- Dateien kopieren ---
    foreach ($Template in $Templates) {
        $TargetPath = Join-Path $WordTemplateFolder $Template.Name
        try {
            Copy-Item -Path $Template.FullName -Destination $TargetPath -Force -ErrorAction Stop
            Write-Log -Level INFO -Message "Vorlage kopiert: $($Template.Name) → $TargetPath"
        }
        catch {
            Write-Log -Level ERROR -Message "Fehler beim Kopieren von $($Template.FullName): $_"
        }
    }

    # --- Word-Prozesse beenden (falls offen) ---
    $wordProcs = Get-Process -Name WINWORD -ErrorAction SilentlyContinue
    if ($wordProcs) {
        Write-Log -Level INFO -Message "Beende laufende Word-Prozesse..."
        $wordProcs | Stop-Process -Force
        Start-Sleep -Seconds 1
    }

    # --- Registry: PersonalTemplates / USERTEMPLATES setzen für angegebene Office-Versionen ---
    foreach ($ver in $OfficeVersions) {
        $regPath = "HKCU:\SOFTWARE\Microsoft\Office\$ver\Word\Options"
        try {
            if (-not (Test-Path -Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
                Write-Log -Level DEBUG -Message "Registry-Schlüssel erstellt: $regPath"
            }

            $expandValue = $WordTemplateFolder
            New-ItemProperty -Path $regPath -Name "PersonalTemplates" -PropertyType ExpandString -Value $expandValue -Force | Out-Null
            New-ItemProperty -Path $regPath -Name "USERTEMPLATES" -PropertyType ExpandString -Value $expandValue -Force | Out-Null

            # <-- Hier die korrigierte Interpolation mit ${ver}
            Write-Log -Level INFO -Message "Registry gesetzt für Office ${ver}: $expandValue"
        }
        catch {
            Write-Log -Level WARN -Message "Konnte Registry für Version $ver nicht setzen: $_"
        }
    }

    # --- Optional: Vorlagen einmal in Word öffnen und schließen (eine COM-Instanz) ---
    if ($OpenInWord) {
        $word = $null
        try {
            $word = New-Object -ComObject Word.Application
            $word.Visible = $false

            foreach ($Template in $Templates) {
                $TargetPath = Join-Path $WordTemplateFolder $Template.Name
                if (Test-Path $TargetPath) {
                    try {
                        $doc = $word.Documents.Open($TargetPath, $false, $true)
                        Start-Sleep -Milliseconds 500
                        $doc.Close($false)
                        Write-Log -Level INFO -Message "Vorlage in Word geöffnet und geschlossen: $($Template.Name)"
                    }
                    catch {
                        Write-Log -Level WARN -Message "Konnte Vorlage nicht in Word öffnen: $($Template.Name) - $_"
                    }
                }
                else {
                    Write-Log -Level WARN -Message "Zielvorlage nicht gefunden (wird übersprungen): $TargetPath"
                }
            }
        }
        catch {
            Write-Log -Level ERROR -Message "Fehler beim Starten von Word COM: $_"
        }
        finally {
            if ($word -ne $null) {
                try { $word.Quit() } catch {}
                try { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null } catch {}
                Remove-Variable word -ErrorAction SilentlyContinue
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
    }

    Write-Log -Level INFO -Message "Vorgang abgeschlossen: Vorlagen kopiert und Word-Pfad gesetzt."
    Write-Output "Fertig. Bitte Word neu starten, falls es geöffnet war, damit die Änderungen sichtbar werden."
}
catch {
    Write-Log -Level ERROR -Message "Fehler im Script: $_"
    throw
}