# rollback-ubuntu.ps1 — remove the Ubuntu dual-boot from Windows 11 Pro,
# restoring the machine's original boot configuration.
#
# Covers steps 2-4 of docs/04-rollback.md: firmware boot entry, EFI files,
# and the two prep-time Windows settings. Partition deletion / C: extension
# (step 5) is deliberately NOT automated — do that in Disk Management, where
# you can see exactly what you're deleting.
#
# Run from an elevated PowerShell:  .\rollback-ubuntu.ps1
# Every change asks for confirmation first. Safe to re-run.

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

function Confirm-Step([string]$Prompt) {
    $reply = Read-Host "$Prompt [y/N]"
    return $reply -match '^[Yy]'
}

Write-Host "=== Ubuntu dual-boot rollback ===" -ForegroundColor Cyan
Write-Host "This removes what the Ubuntu install added. Windows itself was never modified."
Write-Host ""

# --- 1. Remove the 'ubuntu' firmware boot entry --------------------------
Write-Host "[1/4] Firmware boot entries" -ForegroundColor Cyan
$fw = bcdedit /enum firmware | Out-String
$entries = @()
foreach ($block in ($fw -split "(?m)^\s*$")) {
    if ($block -match 'description\s+ubuntu' -and $block -match 'identifier\s+(\{[0-9a-fA-F-]+\})') {
        $entries += $Matches[1]
    }
}
if ($entries.Count -eq 0) {
    Write-Host "  No 'ubuntu' firmware boot entry found - already clean."
} else {
    foreach ($guid in $entries) {
        if (Confirm-Step "  Delete firmware boot entry 'ubuntu' $guid ?") {
            bcdedit /delete $guid | Out-Null
            Write-Host "  Deleted $guid" -ForegroundColor Green
        } else {
            Write-Host "  Skipped $guid"
        }
    }
}

# --- 2. Remove GRUB's files from the EFI System Partition ----------------
Write-Host "[2/4] EFI System Partition cleanup" -ForegroundColor Cyan
$esp = 'S:'
if (Test-Path "$esp\") {
    Write-Host "  Drive letter S: is already in use - edit `$esp in this script or free the letter." -ForegroundColor Yellow
} else {
    mountvol $esp /S
    try {
        if (Test-Path "$esp\EFI\ubuntu") {
            if (-not (Test-Path "$esp\EFI\Microsoft\Boot\bootmgfw.efi")) {
                Write-Host "  SAFETY STOP: Windows Boot Manager not found on this ESP - aborting cleanup." -ForegroundColor Red
            } elseif (Confirm-Step "  Delete $esp\EFI\ubuntu (GRUB's folder; EFI\Microsoft is untouched)?") {
                Remove-Item -Recurse -Force "$esp\EFI\ubuntu"
                Write-Host "  Removed EFI\ubuntu" -ForegroundColor Green
            } else {
                Write-Host "  Skipped."
            }
        } else {
            Write-Host "  No EFI\ubuntu folder found - already clean."
        }
    } finally {
        mountvol $esp /D
    }
}

# --- 3. Re-enable hibernation / Fast Startup -----------------------------
Write-Host "[3/4] Hibernation & Fast Startup" -ForegroundColor Cyan
if (Confirm-Step "  Re-enable hibernation and Fast Startup (powercfg /h on)?") {
    powercfg /h on
    Write-Host "  Hibernation re-enabled." -ForegroundColor Green
} else {
    Write-Host "  Left off. (Recommended only while dual-booting.)"
}

# --- 4. Resume BitLocker --------------------------------------------------
Write-Host "[4/4] BitLocker" -ForegroundColor Cyan
$blv = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
if ($null -ne $blv -and $blv.ProtectionStatus -eq 'Off' -and $blv.VolumeStatus -eq 'FullyEncrypted') {
    if (Confirm-Step "  BitLocker protection on C: is suspended - resume it?") {
        Resume-BitLocker -MountPoint 'C:' | Out-Null
        Write-Host "  BitLocker protection resumed." -ForegroundColor Green
    }
} else {
    Write-Host "  BitLocker on C: needs no action (already protected, or not encrypted)."
}

# --- Remaining manual step ------------------------------------------------
Write-Host ""
Write-Host "=== Remaining manual step: reclaim the disk space ===" -ForegroundColor Cyan
Write-Host "  Win+X -> Disk Management:"
Write-Host "   1. Right-click the Ubuntu partition (no drive letter, no FS label) -> Delete Volume"
Write-Host "   2. Right-click C: -> Extend Volume... -> accept defaults"
Write-Host "  Candidate non-Windows partitions on disk 0:"
Get-Partition -DiskNumber 0 | Where-Object { -not $_.DriveLetter -and $_.Type -notmatch 'Recovery|System|Reserved' } |
    Format-Table PartitionNumber, Type, @{n='Size(GB)';e={[math]::Round($_.Size/1GB,1)}} -AutoSize
Write-Host "Rollback complete once the partition is deleted and C: extended." -ForegroundColor Green
