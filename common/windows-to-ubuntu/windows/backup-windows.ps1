# backup-windows.ps1 — Step 1.0 of docs/01-windows-prep.md, scripted: a full
# system image of the existing Windows install and drives with the built-in
# Windows Backup engine (wbadmin) — the same image the Control Panel "Create
# a system image" wizard makes, restorable bit-for-bit via System Image
# Recovery (docs/04-rollback.md, Path B).
#
# Run from an elevated PowerShell:  .\backup-windows.ps1 -Target E:
#   -Target   drive letter of the external drive to back up TO (NTFS; it
#             cannot be one of the drives being backed up)
#   -Include  drive letters to back up besides the critical volumes (OS,
#             EFI, recovery); default: every fixed volume with a letter
#             except the target — the existing operating system and drives
# Confirms before starting. Non-destructive: it only writes to the target.

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [string[]]$Include
)
$ErrorActionPreference = 'Stop'

function Confirm-Step([string]$Prompt) {
    $reply = Read-Host "$Prompt [y/N]"
    return $reply -match '^[Yy]'
}

Write-Host "=== Full system image backup (wbadmin) ===" -ForegroundColor Cyan
Write-Host "Images the existing Windows install and drives to an external drive. Nothing on them is changed."
Write-Host ""

# --- 1. The target drive --------------------------------------------------
Write-Host "[1/3] Target" -ForegroundColor Cyan
$targetLetter = $Target.Trim().TrimEnd('\', ':').ToUpper()
if ($targetLetter -notmatch '^[A-Z]$') { throw "-Target must be a drive letter like E: (got '$Target')." }
$Target = "${targetLetter}:"
$system = $env:SystemDrive.TrimEnd(':').ToUpper()
if ($targetLetter -eq $system) { throw "$Target is the Windows drive itself - back up TO an external drive." }
$targetVol = Get-Volume -DriveLetter $targetLetter -ErrorAction SilentlyContinue
if ($null -eq $targetVol) { throw "$Target is not a mounted volume - plug the external drive in first." }
if ($targetVol.FileSystemType -ne 'NTFS') {
    throw "$Target is $($targetVol.FileSystemType); Windows Backup needs an NTFS target (Explorer -> right-click the drive -> Format -> NTFS)."
}
$osDisk  = (Get-Partition -DriveLetter $system).DiskNumber
$tgtDisk = (Get-Partition -DriveLetter $targetLetter).DiskNumber
if ($osDisk -eq $tgtDisk) {
    Write-Host "  WARNING: $Target is on the same physical disk as ${system}: - a disk failure or a" -ForegroundColor Yellow
    Write-Host "  repartitioning mishap takes the backup with it. Use an external drive." -ForegroundColor Yellow
}

# --- 2. What gets backed up -------------------------------------------------
Write-Host "[2/3] Volumes" -ForegroundColor Cyan
if (-not $Include) {
    $Include = Get-Volume |
        Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and "$($_.DriveLetter)" -ne $targetLetter } |
        ForEach-Object { "$($_.DriveLetter)" }
}
$Include = @($Include | ForEach-Object { $_.Trim().TrimEnd('\', ':').ToUpper() } |
    Where-Object { $_ -ne $targetLetter } | Sort-Object -Unique)
if ($Include -notcontains $system) { $Include = @($system) + $Include }
$used = 0
foreach ($letter in $Include) {
    $vol = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
    if ($null -eq $vol) { throw "-Include: ${letter}: is not a mounted volume." }
    $used += ($vol.Size - $vol.SizeRemaining)
}
$list = ($Include | ForEach-Object { "${_}:" }) -join ', '
Write-Host "  Backing up: $list + the critical volumes (EFI, recovery) - ~$([math]::Round($used/1GB,1)) GB in use"
Write-Host "  To:         $Target ($($targetVol.FileSystemLabel)) - $([math]::Round($targetVol.SizeRemaining/1GB,1)) GB free"
if ($targetVol.SizeRemaining -lt $used) {
    Write-Host "  WARNING: less free space on $Target than data to back up - the image will" -ForegroundColor Yellow
    Write-Host "  most likely fail partway. Use a bigger drive." -ForegroundColor Yellow
}

# --- 3. Run it ----------------------------------------------------------------
Write-Host "[3/3] System image" -ForegroundColor Cyan
if (-not (Confirm-Step "  Start the system image now (takes a while; Windows stays usable)?")) {
    Write-Host "  Skipped. Re-run when the external drive is ready."
    exit 0
}
$includeArg = ($Include | ForEach-Object { "${_}:" }) -join ','
Write-Host "  wbadmin start backup -backupTarget:$Target -include:$includeArg -allCritical -quiet"
& wbadmin start backup "-backupTarget:$Target" "-include:$includeArg" -allCritical -quiet
if ($LASTEXITCODE -ne 0) { throw "wbadmin exited with code $LASTEXITCODE - the backup did NOT complete." }
Write-Host "  System image written to $Target\WindowsImageBackup\$env:COMPUTERNAME" -ForegroundColor Green

Write-Host ""
Write-Host "=== Next ===" -ForegroundColor Cyan
Write-Host "  1. Create the Windows recovery drive (RecoveryDrive.exe, 8GB+ USB) - it boots"
Write-Host "     System Image Recovery if Windows ever won't start."
Write-Host "  2. To restore: recovery drive -> Troubleshoot -> Advanced options -> System Image"
Write-Host "     Recovery -> pick this image (docs/04-rollback.md, Path B)."
Write-Host "Continue with docs/01-windows-prep.md step 1.1." -ForegroundColor Green
