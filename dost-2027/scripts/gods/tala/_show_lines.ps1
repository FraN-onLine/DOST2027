param([string]$p, [int]$start, [int]$end)
Get-Content -Path $p | Select-Object -Skip ($start-1) -First $end
