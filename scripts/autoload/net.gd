extends Node
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Online transport (autoload "Net"): one WebSocket to a relay (relay/cloudflare/worker.js or tools/relay_server.gd).
## Star topology: clients only talk to the host, the host talks to everybody. Game messages are Dictionaries with a
## "k" (kind) key, delivered to the handler registered with `on(kind, callable)`.

signal joined(code: String)
signal roster_changed
signal closed(reason: String)

const PING_EVERY := 15.0
## Version of the relay envelope (hi / hello / peer / msg / err) and of its URL prefix. Raise it together with the relay
## (relay/cloudflare/worker.js RELAY_PROTO) only when that envelope changes in a way old relays / games cannot read.
const RELAY_PROTO := 1
## Version of the game-level sync (message kinds, shot / placement / snapshot formats, RNG usage). Raise it whenever a
## change would make two players on different builds drift apart. Players with different values cannot play together.
const NET_VERSION := 1

var active: bool = false            # in a room (handshake done)
var is_host: bool = false
var my_id: int = 0
var code: String = ""
var roster: Dictionary = {}         # peer id -> name
var last_error: String = ""
var bytes_out: int = 0
var bytes_in: int = 0

var _ws: WebSocketPeer
var _connecting: bool = false
var _hi: Dictionary = {}
var _handlers: Dictionary = {}
var _ping: float = 0.0
var _was_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_client() -> bool:
	return active and not is_host

## Register the handler of a message kind: callable(from: int, d: Dictionary)
func on(kind: String, cb: Callable) -> void:
	_handlers[kind] = cb

func host_game(relay_url: String, player_name: String) -> void:
	_open(relay_url.rstrip("/") + "/v1/host", {"t": "hi", "role": "host", "name": player_name, "ver": Cfg.game_version()})

func join_game(relay_url: String, room_code: String, player_name: String) -> void:
	_open(relay_url.rstrip("/") + "/v1/room/" + room_code.to_upper(), {"t": "hi", "role": "join", "code": room_code.to_upper(), "name": player_name, "ver": Cfg.game_version()})

func _open(url: String, hi: Dictionary) -> void:
	leave()
	last_error = ""
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 21
	_ws.outbound_buffer_size = 1 << 21
	_ws.max_queued_packets = 4096
	var err: int = _ws.connect_to_url(url)
	if err != OK:
		last_error = "connect_failed"
		closed.emit(last_error)
		_ws = null
		return
	_connecting = true
	_hi = hi
	_was_open = false

func leave() -> void:
	var was: bool = active or _connecting
	if _ws != null:
		_ws.close()
	_ws = null
	active = false
	_connecting = false
	is_host = false
	my_id = 0
	code = ""
	roster.clear()
	PlayerData.net_id = -1
	PlayerData.net_on = false
	if was:
		roster_changed.emit()

func peer_name(id: int) -> String:
	return str(roster.get(id, "?"))

## client -> host
func send_host(d: Dictionary) -> void:
	_send({"t": "msg", "to": 1, "d": d})

## host -> everybody else
func send_all(d: Dictionary) -> void:
	_send({"t": "msg", "to": 0, "d": d})

## host -> one peer
func send_to(id: int, d: Dictionary) -> void:
	_send({"t": "msg", "to": id, "d": d})

func _send(m: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var txt: String = JSON.stringify(m)
	bytes_out += txt.length()
	_ws.send_text(txt)

func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var st: int = _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			_ws.send_text(JSON.stringify(_hi))
		while _ws != null and _ws.get_available_packet_count() > 0:
			var txt: String = _ws.get_packet().get_string_from_utf8()
			bytes_in += txt.length()
			var m: Variant = JSON.parse_string(txt)
			if m is Dictionary:
				_on_frame(m as Dictionary)
		if _ws != null and active:
			_ping += delta
			if _ping >= PING_EVERY:
				_ping = 0.0
				_ws.send_text(JSON.stringify({"t": "ping"}))
	elif st == WebSocketPeer.STATE_CLOSED:
		var reason: String = last_error if last_error != "" else ("closed" if (_was_open or active) else "connect_failed")
		var was_active: bool = active or _connecting
		_ws = null
		leave()
		if was_active:
			last_error = reason
			closed.emit(reason)

func _on_frame(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"hello":
			if int(m.get("relay", 0)) != RELAY_PROTO:
				# an old (or too new) relay: leave with a clear message
				last_error = "relay_version"
				if _ws != null:
					_ws.close()
				return
			my_id = int(m["id"])
			code = str(m["code"])
			is_host = bool(m["host"])
			roster.clear()
			for k in (m["roster"] as Dictionary):
				roster[int(k)] = str((m["roster"] as Dictionary)[k])
			active = true
			_connecting = false
			PlayerData.net_on = true
			PlayerData.net_id = my_id
			joined.emit(code)
			roster_changed.emit()
		"peer":
			var pid: int = int(m["id"])
			if bool(m["on"]):
				roster[pid] = str(m["name"])
			else:
				roster.erase(pid)
			roster_changed.emit()
			var cb: Variant = _handlers.get("peer")
			if cb != null:
				(cb as Callable).call(pid, {"k": "peer", "on": bool(m["on"]), "name": str(m["name"])})
		"msg":
			var d: Dictionary = m.get("d", {}) as Dictionary
			var h: Variant = _handlers.get(str(d.get("k", "")))
			if h != null:
				(h as Callable).call(int(m["from"]), d)
		"err":
			last_error = str(m.get("m", "error"))
