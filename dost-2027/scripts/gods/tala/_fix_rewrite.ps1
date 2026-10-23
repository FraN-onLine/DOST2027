$scriptPath = 'c:/Dost2027/dost-2027/scripts/gods/tala/tala_arena.gd'
$lines = Get-Content -Path $scriptPath

$headerEnd = -1
$tailStart = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'var _seen_tala_hits') { $headerEnd = $i; break }
    if ($lines[$i] -match 'var _blitz_ended') { $tailStart = $i; break }
}

Write-Host "header_end=$headerEnd tail_start=$tailStart"

$header = $lines[0..$headerEnd]

$tail = $lines[$tailStart..($lines.Count - 1)]

$new = @()
$new += $header
$new += @()

# BLITZ section
$new += @(' ', '# --- BLITZ -----------------------------------------------------')
$new += @('# The gold pulse that runs through the whole field during blitz: the field')
$new += @('# FieldFlash rect is tinted gold and its alpha waxes and wanes at')
$new += @('# blitz_field_pulse_rate, so the arena visibly pulses like Mayari')
$new += @('# blitz wave pulses. It is driven on the shared round clock, so every')
$new += @('# screen lands on the same pulse phase at the same time.')
$new += @('var _blitz := false')
$new += @('var _blitz_pulse := 0.0  # phase of the gold pulse, 0..TAU')
$new += @('var _blitz_field_tint := Color.WHITE')
$new += @('var _blitz_ended := false')
$new += @()
$new += @('func _update_blitz() -> void:')
$new += @('    if _blitz_ended:')
$new += @('        _blitz = false')
$new += @('        _blitz_ended = false')
$new += @('    if _trial_time > _blitz_time or _blitz:')
$new += @('        return')
$new += @('    _blitz = true')
$new += @('    _blitz_ended = false')
$new += @('    _blitz_pulse = 0.0')
$new += @('    _blitz_field_tint = Color.WHITE')
$new += @('    spawn_second_tala()')
$new += @()
$new += @('func _tick_blitz(delta: float) -> void:')
$new += @('    if not _blitz:')
$new += @('        return')
$new += @('    _blitz_pulse += delta * TAU / blitz_field_pulse_rate')
$new += @('    if _blitz_pulse > TAU:')
$new += @('        _blitz_pulse = fmod(_blitz_pulse, TAU)')
$new += @('    _tick_stunned_thrower(delta)')
$new += @()
$new += @('func _tick_stunned_thrower(delta: float) -> void:')
$new += @('    if not _blitz:')
$new += @('        return')
$new += @('    var slipper := _slippers.get(_slipper_stun_owner, {})')
$new += @('    if str(slipper.get("state", "")) != "stunned":')
$new += @('        return')
$new += @('    _slipper_stun_left = maxf(0.0, _slipper_stun_left - delta)')
$new += @('    if _slipper_stun_left <= 0.0:')
$new += @('        _slippers[_slipper_stun_owner]["state"] = "dropped"')
$new += @('        _slipper_stun_owner = -1')
$new += @()
$new += @('func spawn_second_tala() -> void:')
$new += @('    if tala_clone == null or not is_instance_valid(tala_clone):')
$new += @('        return')
$new += @('    if _second_tala_spawned:')
$new += @('        return')
$new += @('    _second_tala_spawned = true')
$new += @('    if tala != null and is_instance_valid(tala):')
$new += @('        tala_clone.global_position = tala.global_position + Vector2(0.0, -tala.radius * 1.4)')
$new += @()
$new += @('var _second_tala_spawned := false')
$new += @('var _slipper_stun_owner := -1')
$new += @('var _slipper_stun_left := 0.0')

$content = $new -join [Environment]::NewLine
$content += [Environment]::NewLine
$content += $tail -join [Environment]::NewLine

Set-Content -Path $scriptPath -Value $content
Write-Host 'REWROTE file'
