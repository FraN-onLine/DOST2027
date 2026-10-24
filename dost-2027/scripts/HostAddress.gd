class_name HostAddress
extends RefCounted

# The Join screen's typed address and the host's own IP list - pure static
# helpers, so tools/join_by_ip_check.gd can test them without a scene.

const DEFAULT_PORT := 12345


# "host" or "host:port" -> {"ok": true, "host": String, "port": int}, or
# {"ok": false, "error": String}. The host is an IPv4 address or a hostname (it is
# not resolved here); IPv6 is not supported.
static func parse(text: String, default_port := DEFAULT_PORT) -> Dictionary:
	var clean := text.strip_edges()
	if clean.is_empty():
		return {"ok": false, "error": "Type the host's IP first"}
	var parts := clean.split(":")
	if parts.size() > 2:
		return {"ok": false, "error": "Use host or host:port (IPv6 is not supported)"}
	var host := parts[0].strip_edges()
	if host.is_empty() or not _is_host(host):
		return {"ok": false, "error": "That is not an IP address or host name"}
	var port := default_port
	if parts.size() == 2:
		var port_text := parts[1].strip_edges()
		if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
			return {"ok": false, "error": "The port must be a number from 1 to 65535"}
		port = int(port_text)
	return {"ok": true, "host": host, "port": port}


static func _is_host(host: String) -> bool:
	if host.is_valid_ip_address():
		return true
	if host.length() > 253 or host.begins_with(".") or host.begins_with("-"):
		return false
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"
	for index in range(host.length()):
		if not allowed.contains(host[index]):
			return false
	# four dotted numbers that are not an IP (300.1.1.1) are a typo, not a name
	return not host.replace(".", "").is_valid_int()


# The addresses worth telling a friend, best first: IPv4 only, no loopback or
# link-local, VPN-looking ranges before the home LAN's. Order inside a range is kept.
static func order_ips(addresses: Array) -> Array[String]:
	var ranked: Array = []
	for address in addresses:
		var ip := str(address)
		if not ip.is_valid_ip_address() or ip.contains(":"):
			continue
		var rank := _rank(ip)
		if rank >= 0:
			ranked.append({"ip": ip, "rank": rank, "at": ranked.size()})
	ranked.sort_custom(func(a, b): return a["rank"] < b["rank"] or (a["rank"] == b["rank"] and a["at"] < b["at"]))
	var out: Array[String] = []
	for entry in ranked:
		out.append(entry["ip"])
	return out


# -1 = never list it; otherwise lower is better.
static func _rank(ip: String) -> int:
	var octets := ip.split(".")
	if octets.size() != 4:
		return -1
	var a := int(octets[0])
	var b := int(octets[1])
	if a == 127 or a == 0 or (a == 169 and b == 254):
		return -1
	if a == 10:
		return 0
	if a == 100 and b >= 64 and b <= 127:
		return 1  # Tailscale
	if a == 26:
		return 2  # Radmin
	if a == 25:
		return 3  # Hamachi
	if a == 172 and b >= 16 and b <= 31:
		return 4
	if a == 192 and b == 168:
		return 5
	return 6


# "Your IPs: 10.147.17.23, 100.101.102.103 (port 12345)", or "" with none.
static func ips_line(addresses: Array, port: int) -> String:
	var ips := order_ips(addresses)
	return "" if ips.is_empty() else "Your IPs: %s (port %d)" % [", ".join(ips), port]
