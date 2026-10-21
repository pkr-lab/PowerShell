# Als Administrator ausführen
$baseDir = 'C:\Users\Public\10020115_WinScripts'
$counterFile = Join-Path $baseDir '10020115_Win_R_WLANCounter.txt'
$threshold = 20   # Anzahl Tage bis zur Anzeige

# Verzeichnis sicherstellen
if (-not (Test-Path -Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

# UTF8 mit BOM erzeugen
$utf8WithBom = New-Object System.Text.UTF8Encoding $true

function Get-CounterAndDate {
    param($path)
    if (Test-Path -Path $path) {
        try {
            $txt = [System.IO.File]::ReadAllText($path, $utf8WithBom).Trim()
            if ($txt -match '^\s*(\d+)\s*;\s*(\d{4}-\d{2}-\d{2})\s*$') {
                return @{
                    Counter = [int]$matches[1]
                    Date = [datetime]::ParseExact($matches[2], 'yyyy-MM-dd', $null)
                }
            } elseif ($txt -match '^\s*(\d+)\s*$') {
                return @{ Counter = [int]$matches[1]; Date = $null }
            }
        } catch {
            # Fehler beim Lesen/Parsen -> Defaults
        }
    }
    return @{ Counter = 0; Date = $null }
}

function Set-CounterAndDate {
    param(
        [Parameter(Mandatory=$true)] [string] $path,
        [Parameter(Mandatory=$true)] [int] $counter,
        $date
    )
    if ($null -ne $date) {
        # Wenn ein Datum übergeben wurde, versuche es in DateTime zu konvertieren
        try {
            $dt = [datetime]$date
            $dateStr = $dt.ToString('yyyy-MM-dd')
        } catch {
            $dateStr = ''
        }
    } else {
        $dateStr = ''
    }
    $line = "{0};{1}" -f $counter, $dateStr
    [System.IO.File]::WriteAllText($path, $line, $utf8WithBom)
}

# Initiale Datei erzeugen, falls nicht vorhanden (0;heute)
if (-not (Test-Path -Path $counterFile)) {
    Set-CounterAndDate -path $counterFile -counter 0 -date (Get-Date).Date
}

# Hauptlogik
$entry = Get-CounterAndDate -path $counterFile
$currentCounter = $entry.Counter
$lastDate = $entry.Date
$today = (Get-Date).Date

# Erhöhe nur einmal pro Kalendertag (wenn lastDate fehlt oder älter als heute)
if ($null -eq $lastDate -or $lastDate.Date -lt $today) {
    $currentCounter = $currentCounter + 1
    # beim Erhöhen: Datum = heute
    Set-CounterAndDate -path $counterFile -counter $currentCounter -date $today
} else {
    # nicht erhöht: stelle sicher, dass ein Datum in der Datei steht
    if ($null -eq $lastDate) { $lastDate = $today }
    Set-CounterAndDate -path $counterFile -counter $currentCounter -date $lastDate
}

# Wenn Schwellenwert erreicht oder überschritten -> zwingendes TopMost-Formular anzeigen
if ($currentCounter -ge $threshold) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $signature = @"
using System;
using System.Runtime.InteropServices;
public static class User32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@
    Add-Type -TypeDefinition $signature -PassThru | Out-Null

    $HWND_TOPMOST = [IntPtr]::op_Explicit(-1)
    $SWP_NOMOVE = 0x0002
    $SWP_NOSIZE = 0x0001
    $SWP_SHOWWINDOW = 0x0040
    $SWP_FLAGS = $SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_SHOWWINDOW

   # UI: verbessertes, mehrzeiliges Layout mit TableLayoutPanel
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'IT & Support'
$form.Width = 560
$form.Height = 260
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.ShowInTaskbar = $true
$form.Padding = '12,12,12,12'

# TableLayoutPanel für sauberes, responsives Layout
$tl = New-Object System.Windows.Forms.TableLayoutPanel
$tl.Dock = 'Fill'
$tl.ColumnCount = 3
$tl.RowCount = 4
$tl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,60)))  # Icon-Spalte
$tl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))  # Text-Spalte
$tl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,12)))  # Spacer
$tl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,8)))
$tl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$tl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
$tl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,48)))
$tl.Padding = '6,6,6,6'
$form.Controls.Add($tl)

# Icon
$pb = New-Object System.Windows.Forms.PictureBox
$pb.Width = 48
$pb.Height = 48
$pb.SizeMode = 'StretchImage'
$pb.Image = [System.Drawing.SystemIcons]::Warning.ToBitmap()
$tl.Controls.Add($pb, 0, 1)
$tl.SetRowSpan($pb, 2)

# Titel
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.AutoSize = $true
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$lblTitle.Text = 'WLAN Verbindung erforderlich'
$tl.Controls.Add($lblTitle, 1, 1)

# Nachricht: RichTextBox readonly (besseres Wrapping, selectable)
$rt = New-Object System.Windows.Forms.RichTextBox
$rt.ReadOnly = $true
$rt.BorderStyle = 'None'
$rt.BackColor = $form.BackColor
$rt.Font = New-Object System.Drawing.Font('Segoe UI',10)
$rt.Dock = 'Fill'
$rt.Multiline = $true
$rt.ScrollBars = 'None'
$rt.Text = "Dein PC war mehr als $threshold Tage nicht im WLAN.`r`n`r`nBitte stelle eine WLAN Verbindung her, um dein PC wieder besser zu schuetzen."
$tl.Controls.Add($rt, 1, 2)

# LinkLabel (unter dem Text, links)
$link = New-Object System.Windows.Forms.LinkLabel
$link.Text = 'WLAN Einstellungen öffnen'
$link.AutoSize = $true
$link.Anchor = 'Left'
$link.Add_LinkClicked({
    Start-Process 'ms-settings:network-wifi' -ErrorAction SilentlyContinue
})
$tl.Controls.Add($link, 1, 3)

# OK-Button (zentriert rechts unten)
$btnOk = New-Object System.Windows.Forms.Button
$btnOk.Text = 'OK'
$btnOk.Width = 100
$btnOk.Height = 32
$btnOk.Anchor = 'Right'
$btnOk.Add_Click({
    $form.Tag = 'ok'
    $form.Close()
})
# Platzieren: Button in Column 1, Row 3, rechts ausrichten
$tl.Controls.Add($btnOk, 1, 3)
$tl.SetCellPosition($btnOk, (New-Object System.Windows.Forms.TableLayoutPanelCellPosition(1,3)))

# Beim Shown-Ereignis: TopMost + Vordergrund erzwingen
$form.Add_Shown({
    [User32]::SetWindowPos($form.Handle, $HWND_TOPMOST, 0, 0, 0, 0, [uint32]$SWP_FLAGS) | Out-Null
    [User32]::SetForegroundWindow($form.Handle) | Out-Null
    $form.Activate()
})

# Timer, der Fokus während Anzeige wiederholt erzwingt
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 800
$timer.Add_Tick({
    if ($form.Visible) {
        [User32]::SetForegroundWindow($form.Handle) | Out-Null
    } else {
        $timer.Stop()
        $timer.Dispose()
    }
})
$timer.Start()

$form.ShowDialog() | Out-Null

    # Nach Bestätigung: Zähler zurücksetzen und Datum auf heute setzen
    Set-CounterAndDate -path $counterFile -counter 0 -date (Get-Date).Date
}