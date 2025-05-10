# upload.ps1 - Upload the built .fs file to Tang Nano 9K
# Run from the project folder (hdmi_test)

# NOTE: Since Gowin drivers are installed, use Gowin Programmer GUI instead of openFPGALoader
# openFPGALoader requires WinUSB driver which conflicts with Gowin's FTDI driver

$fs = 'top.fs'
if (-not (Test-Path $fs)) { 
    throw "File $fs not found. Run build_powershell.ps1 first." 
}

Write-Host "========================================"
Write-Host "Bitstream ready: $fs"
Write-Host "========================================"
Write-Host ""
Write-Host "To upload using Gowin Programmer:"
Write-Host "1. Open Gowin Programmer (from Gowin IDE installation)"
Write-Host "2. Connect Tang Nano 9K via USB"
Write-Host "3. Click 'Add' button and select: $((Get-Item $fs).FullName)"
Write-Host "4. Operation: Program/Configure"
Write-Host "5. Device: GW1NR-9C"
Write-Host "6. Access Mode: SRAM Program"
Write-Host "7. Click 'Program/Configure' button"
Write-Host ""
Write-Host "Alternative - Use command line (if Gowin CLI is in PATH):"
Write-Host "  programmer_cli -d GW1NR-9C -f top.fs"
Write-Host ""
Write-Host "Note: openFPGALoader is disabled because it requires WinUSB driver"
Write-Host "which conflicts with the FTDI VCP driver used by Gowin tools."
Write-Host "========================================" 