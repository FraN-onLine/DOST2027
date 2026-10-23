param([string]$p)
git -C (Split-Path $p) checkout -- $p
Write-Host "RESTORED $p"
