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
#             except the target, plus every unlettered NTFS volume on the
#             OS disk (the vendor's factory-recovery partition) — the
#             existing operating system and drives
# Confirms before starting. Non-destructive: it only writes to the target.

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [string[]]$Include
)
$ErrorActionPreference = 'Stop'

function Confirm-Step([string]$Prompt, [switch]$DefaultYes) {
    # A backup is non-destructive, so (unlike the rollback script) a bare
    # Enter means yes here — the repo's rule for every backup prompt.
    if ($DefaultYes) {
        $reply = Read-Host "$Prompt [Y/n]"
        return $reply -notmatch '^[Nn]'
    }
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
if ($targetVol.DriveType -ne 'Fixed') {
    throw "$Target is $($targetVol.DriveType) media; Windows Backup needs a fixed (hard-disk class) NTFS drive - USB flash sticks and SD cards are not accepted, USB HDD/SSD enclosures are."
}
if ($targetVol.FileSystemType -eq 'Unknown') {
    throw "$Target has no readable filesystem - locked (BitLocker To Go) or unformatted? Unlock it, or format it as NTFS."
}
if ($targetVol.FileSystemType -ne 'NTFS') {
    throw "$Target is $($targetVol.FileSystemType); Windows Backup needs an NTFS target (Explorer -> right-click the drive -> Format -> NTFS)."
}
# Warning only: dynamic disks, spanned volumes and superfloppy media have
# no MSFT_Partition behind the letter, and that must not abort the backup.
$osPart  = Get-Partition -DriveLetter $system -ErrorAction SilentlyContinue
$tgtPart = Get-Partition -DriveLetter $targetLetter -ErrorAction SilentlyContinue
if ($null -ne $osPart -and $null -ne $tgtPart) {
    if ($osPart.DiskNumber -eq $tgtPart.DiskNumber) {
        Write-Host "  WARNING: $Target is on the same physical disk as ${system}: - a disk failure or a" -ForegroundColor Yellow
        Write-Host "  repartitioning mishap takes the backup with it. Use an external drive." -ForegroundColor Yellow
    }
} else {
    Write-Host "  (Could not tell which physical disk $Target is on - make sure it is an external drive.)"
}

# --- 2. What gets backed up -------------------------------------------------
Write-Host "[2/3] Volumes" -ForegroundColor Cyan
# What gets imaged: the OS volume, every lettered fixed volume (the user's
# "drives"), and every other NTFS/ReFS volume on the OS disk even without a
# letter - that is where vendors keep their factory-recovery partition
# (MSI's BIOS_RVY, for one), and -allCritical alone leaves those out.
# wbadmin takes unlettered volumes as \?\Volume{GUID}\ paths.
$osDiskNumber = (Get-Partition -DriveLetter $system -ErrorAction SilentlyContinue).DiskNumber
$entries = @()   # objects: Arg ('C:' or '\?\Volume{...}\'), Label, Used (bytes)
function Add-Entry($vol, $arg, $label) {
    $script:entries += [pscustomobject]@{ Arg = $arg; Label = $label; Used = ($vol.Size - $vol.SizeRemaining) }
}
if ($Include) {
    foreach ($item in @($Include | ForEach-Object { $_.Trim().TrimEnd('\', ':').ToUpper() } | Sort-Object -Unique)) {
        if ($item -eq $targetLetter) { continue }
        $vol = Get-Volume -DriveLetter $item -ErrorAction SilentlyContinue
        if ($null -eq $vol) { throw "-Include: ${item}: is not a mounted volume." }
        Add-Entry $vol "${item}:" "${item}: ($($vol.FileSystemLabel))"
    }
    if (-not ($entries | Where-Object { $_.Arg -eq "${system}:" })) {
        $vol = Get-Volume -DriveLetter $system
        $entries = @([pscustomobject]@{ Arg = "${system}:"; Label = "${system}: ($($vol.FileSystemLabel))"; Used = ($vol.Size - $vol.SizeRemaining) }) + $entries
    }
} else {
    foreach ($vol in (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.FileSystemType -in 'NTFS', 'ReFS' })) {
        $letter = ("$($vol.DriveLetter)").Trim([char]0)
        if ($letter -eq $targetLetter) { continue }
        $part = Get-Partition | Where-Object { $_.AccessPaths -contains $vol.Path } | Select-Object -First 1
        $onOsDisk = ($null -ne $part -and $null -ne $osDiskNumber -and $part.DiskNumber -eq $osDiskNumber)
        if (-not $letter -and -not $onOsDisk) { continue }
        if ($letter) {
            Add-Entry $vol "${letter}:" "${letter}: ($($vol.FileSystemLabel))"
        } else {
            Add-Entry $vol $vol.Path "$($vol.FileSystemLabel) [no letter, disk $($part.DiskNumber)]"
        }
    }
    $entries = @($entries | Sort-Object { $_.Arg -ne "${system}:" }, { $_.Arg })
}
$used = 0
foreach ($entry in $entries) { $used += $entry.Used }
$list = ($entries | ForEach-Object { $_.Label }) -join ', '
Write-Host "  Backing up: $list + the critical volumes (EFI, recovery) - ~$([math]::Round($used/1GB,1)) GB in use"
Write-Host "  To:         $Target ($($targetVol.FileSystemLabel)) - $([math]::Round($targetVol.SizeRemaining/1GB,1)) GB free"
if ($targetVol.SizeRemaining -lt $used) {
    Write-Host "  WARNING: less free space on $Target than data to back up - the image will" -ForegroundColor Yellow
    Write-Host "  most likely fail partway. Use a bigger drive." -ForegroundColor Yellow
}

# --- 3. Run it ----------------------------------------------------------------
Write-Host "[3/3] System image" -ForegroundColor Cyan
if (-not (Confirm-Step "  Start the system image now (takes a while; Windows stays usable)?" -DefaultYes)) {
    Write-Host "  Skipped. Re-run when the external drive is ready."
    exit 0
}
$includeArg = ($entries | ForEach-Object { $_.Arg }) -join ','
Write-Host "  wbadmin start backup -backupTarget:$Target -include:$includeArg -allCritical -quiet"
& wbadmin start backup "-backupTarget:$Target" "-include:$includeArg" -allCritical -quiet
if ($LASTEXITCODE -ne 0) { throw "wbadmin exited with code $LASTEXITCODE - the backup did NOT complete." }
Write-Host "  System image written to $Target\WindowsImageBackup\$env:COMPUTERNAME" -ForegroundColor Green
Write-Host "  NOTE: the image is stored UNENCRYPTED even if ${system}: uses BitLocker - keep the drive" -ForegroundColor Yellow
Write-Host "  physically safe, or turn on BitLocker To Go for $Target before running this." -ForegroundColor Yellow

Write-Host ""
Write-Host "=== Next ===" -ForegroundColor Cyan
Write-Host "  1. Create the Windows recovery drive (RecoveryDrive.exe, 8GB+ USB) - it boots"
Write-Host "     System Image Recovery if Windows ever won't start."
Write-Host "  2. To restore: recovery drive -> Troubleshoot -> Advanced options -> System Image"
Write-Host "     Recovery -> pick this image (docs/04-rollback.md, Path B)."
Write-Host "Continue with docs/01-windows-prep.md step 1.1." -ForegroundColor Green
