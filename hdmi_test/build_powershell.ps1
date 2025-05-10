# build_powershell.ps1 - Run synthesis and place-and-route using PowerShell directly (not MSYS)
# Run from the project folder (hdmi_test)

# Source the OSS CAD Suite environment to set up paths and environment variables properly
$ossCadRoot = 'C:\Users\1kfil\Documents\C\Libraries\oss-cad-suite'
& "$ossCadRoot\environment.ps1"

Write-Host "Running build with OSS CAD Suite tools..."
Write-Host "Current PATH includes: $($env:PATH.Split(';')[0..5] -join '; ')..."

# Run yosys (synthesis)
Write-Host "`nRunning Yosys synthesis..."
& yosys.exe -p "synth_gowin -json top.v.json -top top" top.v
if ($LASTEXITCODE -ne 0) {
    throw "Yosys synthesis failed with exit code $LASTEXITCODE"
}
Write-Host "Yosys synthesis complete: top.v.json created."

# Find nextpnr binary
$nextpnrPath = $null
$nextpnrArgs = @()

# Prefer nextpnr-himbaechel (supports Gowin via uarch)
if (Test-Path "$ossCadRoot\bin\nextpnr-himbaechel.exe") {
    $nextpnrPath = "$ossCadRoot\bin\nextpnr-himbaechel.exe"
    $nextpnrArgs = @(
        "--json", "top.v.json",
        "--write", "top.v_pnr.json",
        "--device", "GW1NR-LV9QN88PC6/I5",
        "--vopt", "family=GW1N-9C",
        "--vopt", "cst=tangnano9k.cst"
    )
} elseif (Test-Path "$ossCadRoot\bin\nextpnr-gowin.exe") {
    $nextpnrPath = "$ossCadRoot\bin\nextpnr-gowin.exe"
    $nextpnrArgs = @(
        "--json", "top.v.json",
        "--write", "top.v_pnr.json",
        "--device", "GW1NR-LV9QN88PC6/I5",
        "--cst", "tangnano9k.cst"
    )
} else {
    throw "No suitable nextpnr binary found. Please install nextpnr-gowin or ensure nextpnr-himbaechel is present in $ossCadRoot\bin"
}

Write-Host "`nUsing nextpnr: $nextpnrPath"
Write-Host "`nRunning place and route..."
& $nextpnrPath @nextpnrArgs
if ($LASTEXITCODE -ne 0) {
    throw "nextpnr place-and-route failed with exit code $LASTEXITCODE"
}

Write-Host "`nPlace and route complete: top.v_pnr.json created."

# Generate bitstream using gowin_pack
Write-Host "`nGenerating bitstream with gowin_pack..."
& gowin_pack -d GW1N-9C -o top.fs top.v_pnr.json
if ($LASTEXITCODE -ne 0) {
    throw "gowin_pack bitstream generation failed with exit code $LASTEXITCODE"
}

Write-Host "`nBitstream generation complete: top.fs created."
Write-Host "You can now upload to the Tang Nano 9K using:"
Write-Host "  openFPGALoader -b tangnano9k top.fs"
