<#
================================================================================
SCRIPT NAME:    TECH-248368_Msg823_WindowsEventLog_Probe_V1.ps1
TICKET ID:      TECH-248368
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-16
VERSION:        v1.0

PURPOSE:
    Read-only collection of Windows event logs around the Msg 823 / OS error 59
    (network error reading \\10.4.1.85\...\TMW_Live.mdf) at 2026-11-16 09:07 ET.
    Companion to TECH-248368_Msg823_ErrorLog_Probe_V1.sql.

USAGE (run ON the SQL Server host, elevated PowerShell; repeat on the storage /
file server 10.4.1.85 if you have access):
    .\TECH-248368_Msg823_WindowsEventLog_Probe_V1.ps1
    .\TECH-248368_Msg823_WindowsEventLog_Probe_V1.ps1 -Start '2026-11-16 08:30' -End '2026-11-16 10:00'

CHANGE LOG:
    2026-11-16 - J.Cook - TECH-248368 - Initial build
================================================================================
#>
param(
    [datetime]$Start = '2026-11-16 08:30',   # server-local time
    [datetime]$End   = '2026-11-16 10:00',
    [string]$OutDir  = "$env:USERPROFILE\Documents"
)

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out   = Join-Path $OutDir "TECH-248368_Msg823_WinEvents_$stamp.csv"
$rows  = @()

function Pull($label, $filter) {
    try {
        Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
            Select-Object @{n='Source';e={$label}}, TimeCreated, LogName, ProviderName, Id,
                          LevelDisplayName, @{n='Message';e={($_.Message -replace '\s+',' ')}}
    } catch [System.Exception] {
        if ($_.Exception.Message -notmatch 'No events were found') {
            Write-Warning "$label : $($_.Exception.Message)"
        }
    }
}

# System log: errors + warnings (1=Critical, 2=Error, 3=Warning) in the window
$rows += Pull 'System'      @{LogName='System';      StartTime=$Start; EndTime=$End; Level=1,2,3}

# Application log: SQL Server events (823/824/825, 17053, 18056 etc.)
$rows += Pull 'Application' @{LogName='Application'; StartTime=$Start; EndTime=$End; Level=1,2,3}

# SMB client (the UNC path to \\10.4.1.85) - connectivity + operational channels
foreach ($ch in 'Microsoft-Windows-SMBClient/Connectivity','Microsoft-Windows-SMBClient/Operational','Microsoft-Windows-SMBClient/Security') {
    $rows += Pull "SMBClient" @{LogName=$ch; StartTime=$Start; EndTime=$End}
}

$rows = $rows | Where-Object { $_ } | Sort-Object TimeCreated
$rows | Export-Csv -NoTypeInformation -Path $out

Write-Host "Events collected: $($rows.Count)"
Write-Host "Saved to: $out"
Write-Host ''
Write-Host 'Lines most likely related (disk, SMB, network, SQL 823/824):'
$rows | Where-Object {
    $_.Message -match '10\.4\.1\.85|TMW_Live|823|824|network|SMB|timeout|reset|disconnect|retry|reset to device' -or
    $_.ProviderName -match 'disk|Ntfs|mrxsmb|SMBClient|Tcpip|MSSQL'
} | Format-Table TimeCreated, ProviderName, Id, LevelDisplayName, Message -AutoSize -Wrap
