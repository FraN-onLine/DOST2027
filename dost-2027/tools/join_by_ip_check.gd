extends SceneTree

# Validation: JOIN BY IP's address parser and the host's IP list (HostAddress).
# Run: godot --headless --path <project> -s res://tools/join_by_ip_check.gd

var _problems := 0


func _initialize() -> void:
	var p := HostAddress.parse("10.147.17.23")
	_check(p["ok"] and p["host"] == "10.147.17.23" and p["port"] == HostAddress.DEFAULT_PORT, "a bare IPv4 takes the default port")
	p = HostAddress.parse("  10.147.17.23:4000 ")
	_check(p["ok"] and p["host"] == "10.147.17.23" and p["port"] == 4000, "IPv4:port, spaces trimmed")
	p = HostAddress.parse("lamp-pc")
	_check(p["ok"] and p["host"] == "lamp-pc" and p["port"] == HostAddress.DEFAULT_PORT, "a MagicDNS name parses")
	p = HostAddress.parse("lamp-pc.tail1234.ts.net:999")
	_check(p["ok"] and p["port"] == 999, "a dotted name with a port parses")
	for bad in ["10.0.0.1:0", "10.0.0.1:70000", "10.0.0.1:abc", "10.0.0.1:", "10.0.0.1:1:2"]:
		_check(not HostAddress.parse(bad)["ok"], "bad port rejected: '%s'" % bad)
	for bad in ["", "   ", ":123", "bad host", "300.1.1.1", "-x"]:
		_check(not HostAddress.parse(bad)["ok"], "rejected: '%s'" % bad)
	_check(HostAddress.parse("")["error"] != "", "an empty field says what to do")

	var ips := HostAddress.order_ips(["192.168.1.5", "127.0.0.1", "169.254.3.3", "fe80::1", "172.20.0.4", "25.1.2.3", "26.1.2.3", "100.101.102.103", "100.20.0.1", "10.147.17.23", "8.8.8.8"])
	_check(str(ips) == str(["10.147.17.23", "100.101.102.103", "26.1.2.3", "25.1.2.3", "172.20.0.4", "192.168.1.5", "100.20.0.1", "8.8.8.8"]),
		"the IP list drops loopback / link-local / IPv6 and puts VPN ranges first (%s)" % str(ips))
	_check(HostAddress.order_ips(["127.0.0.1"]).is_empty() and HostAddress.ips_line(["127.0.0.1"], 1) == "", "nothing to show without a usable IP")
	_check(HostAddress.ips_line(["192.168.1.5", "10.147.17.23"], 12345) == "Your IPs: 10.147.17.23, 192.168.1.5 (port 12345)", "the lobby line reads right")
	_check(Settings.DEFAULTS["gameplay"].has("last_ip"), "the last IP has a settings key")

	print("Join by IP checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
