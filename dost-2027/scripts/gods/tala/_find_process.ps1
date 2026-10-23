$path = 'c:/Dost2027/dost-2027/scripts/gods/tala/tala_arena.gd'
$a = Get-Content -Path $path
$i = 0
foreach ($line in $a) {
    $i++
    if ($line -match 'func _process') {
        Write-Output $i
        break
    }
}
