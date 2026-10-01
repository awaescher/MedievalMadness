extends SceneTree
## Tiny self-hostable relay (same protocol as relay/cloudflare/worker.js): rooms with a 4 letter code, a star topology
## (clients only talk to the host, the host talks to everybody). Run it anywhere Godot runs:
##   godot --headless --path . --script res://tools/relay_server.gd -- --port=9080
## Messages are JSON text frames. Client -> relay: {"t":"hi","role":"host|join","code":"ABCD","name":"..","ver":".."},
## {"t":"msg","to":<peer id, 0 = everybody else (host only)>,"d":{...}}. Relay -> client: {"t":"hello",...},
## {"t":"peer","id":..,"name":..,"on":true|false}, {"t":"msg","from":<id>,"d":{...}}, {"t":"err","m":".."}.

const MAX_PEERS := 8
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var server := TCPServer.new()
var pending: Array = []          # [{ws}] connected but without "hi" yet
var rooms: Dictionary = {}       # code -> {peers: {id: {ws, name}}, next: int}
var rng := RandomNumberGenerator.new()
var port: int = 9080

func _initialize() -> void:
	rng.randomize()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.get_slice("=", 1))
	var err: int = server.listen(port)
	if err != OK:
		push_error("relay: cannot listen on %d (%d)" % [port, err])
		quit(1)
		return
	print("relay listening on port %d" % port)

func _new_code() -> String:
	for attempt in 50:
		var c: String = ""
		for i in 4:
			c += ALPHABET[rng.randi() % ALPHABET.length()]
		if not rooms.has(c):
			return c
	return "ZZZZ"

func _process(_delta: float) -> bool:
	while server.is_connection_available():
		var tcp: StreamPeerTCP = server.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 21
		ws.outbound_buffer_size = 1 << 21
		ws.max_queued_packets = 4096
		ws.accept_stream(tcp)
		pending.append({"ws": ws, "t": Time.get_ticks_msec()})
	var i: int = pending.size() - 1
	while i >= 0:
		var ws: WebSocketPeer = (pending[i] as Dictionary)["ws"] as WebSocketPeer
		ws.poll()
		var st: int = ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED or Time.get_ticks_msec() - int((pending[i] as Dictionary)["t"]) > 10000:
			pending.remove_at(i)
		elif st == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			var m: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary and str((m as Dictionary).get("t", "")) == "hi":
				_hi(ws, m as Dictionary)
				pending.remove_at(i)
		i -= 1
	for code in rooms.keys():
		var room: Dictionary = rooms[code] as Dictionary
		var peers: Dictionary = room["peers"] as Dictionary
		for id in peers.keys():
			var peer: Dictionary = peers[id] as Dictionary
			var ws2: WebSocketPeer = peer["ws"] as WebSocketPeer
			ws2.poll()
			var st2: int = ws2.get_ready_state()
			while st2 == WebSocketPeer.STATE_OPEN and ws2.get_available_packet_count() > 0:
				var m2: Variant = JSON.parse_string(ws2.get_packet().get_string_from_utf8())
				if m2 is Dictionary:
					_msg(str(code), int(id), m2 as Dictionary)
			if st2 == WebSocketPeer.STATE_CLOSED:
				_leave(str(code), int(id))
				break
	return false

func _send(ws: WebSocketPeer, d: Dictionary) -> void:
	ws.send_text(JSON.stringify(d))

func _roster(room: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in (room["peers"] as Dictionary):
		out[str(id)] = str(((room["peers"] as Dictionary)[id] as Dictionary)["name"])
	return out

func _hi(ws: WebSocketPeer, m: Dictionary) -> void:
	var role: String = str(m.get("role", "join"))
	var nm: String = str(m.get("name", "?")).substr(0, 24)
	if role == "host":
		var code: String = _new_code()
		rooms[code] = {"peers": {1: {"ws": ws, "name": nm}}, "next": 2}
		_send(ws, {"t": "hello", "id": 1, "code": code, "host": true, "roster": {"1": nm}})
		print("room %s opened by %s" % [code, nm])
		return
	var code2: String = str(m.get("code", "")).to_upper()
	if not rooms.has(code2):
		_send(ws, {"t": "err", "m": "room_not_found"})
		ws.close()
		return
	var room: Dictionary = rooms[code2] as Dictionary
	var peers: Dictionary = room["peers"] as Dictionary
	if peers.size() >= MAX_PEERS:
		_send(ws, {"t": "err", "m": "room_full"})
		ws.close()
		return
	var id: int = int(room["next"])
	room["next"] = id + 1
	peers[id] = {"ws": ws, "name": nm}
	_send(ws, {"t": "hello", "id": id, "code": code2, "host": false, "roster": _roster(room)})
	for pid in peers:
		if int(pid) != id:
			_send((peers[pid] as Dictionary)["ws"] as WebSocketPeer, {"t": "peer", "id": id, "name": nm, "on": true})
	print("room %s: %s joined as %d" % [code2, nm, id])

func _msg(code: String, from: int, m: Dictionary) -> void:
	if str(m.get("t", "")) != "msg":
		return
	var room: Dictionary = rooms[code] as Dictionary
	var peers: Dictionary = room["peers"] as Dictionary
	var out: Dictionary = {"t": "msg", "from": from, "d": m.get("d", {})}
	var to: int = int(m.get("to", 1))
	if from != 1:
		to = 1
	if to == 0:
		for pid in peers:
			if int(pid) != from:
				_send((peers[pid] as Dictionary)["ws"] as WebSocketPeer, out)
	elif peers.has(to):
		_send((peers[to] as Dictionary)["ws"] as WebSocketPeer, out)

func _leave(code: String, id: int) -> void:
	var room: Dictionary = rooms[code] as Dictionary
	var peers: Dictionary = room["peers"] as Dictionary
	var nm: String = str((peers[id] as Dictionary)["name"])
	peers.erase(id)
	if id == 1:
		# the host is gone: the room ends
		for pid in peers:
			_send((peers[pid] as Dictionary)["ws"] as WebSocketPeer, {"t": "err", "m": "host_left"})
			((peers[pid] as Dictionary)["ws"] as WebSocketPeer).close()
		rooms.erase(code)
		print("room %s closed (host left)" % code)
		return
	for pid2 in peers:
		_send((peers[pid2] as Dictionary)["ws"] as WebSocketPeer, {"t": "peer", "id": id, "name": nm, "on": false})
	print("room %s: %s left" % [code, nm])
