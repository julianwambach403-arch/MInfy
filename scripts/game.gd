extends Node
## Autoload "Game": Netzwerk-Knoten, der auf Server UND Clients unter /root/Game liegt.
## Alle RPCs laufen hierüber und werden an server.gd bzw. client.gd weitergereicht.

var is_server := false
var server = null
var client = null
var peer: ENetMultiplayerPeer = null


func start_server(port: int) -> void:
	is_server = true
	Engine.max_fps = 60
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 16)
	if err != OK:
		push_error("Server konnte nicht auf Port %d starten (Fehler %d)." % [port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	server = load("res://scripts/server.gd").new()
	server.name = "Server"
	add_child(server)
	multiplayer.peer_connected.connect(server.on_peer_connected)
	multiplayer.peer_disconnected.connect(server.on_peer_disconnected)
	print("[Server] MInfy-Server läuft auf UDP-Port %d" % port)


func start_client(root: Node, opts: Dictionary) -> void:
	client = load("res://scripts/client.gd").new()
	client.name = "Client"
	client.opts = opts
	root.add_child(client)


func connect_to(host: String, port: int) -> int:
	disconnect_peer()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_peer() -> void:
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null


func _sender() -> int:
	return multiplayer.get_remote_sender_id()


# ---------------- Client -> Server ----------------

@rpc("any_peer", "call_remote", "reliable")
func req_join(pname: String, color: int) -> void:
	if is_server:
		server.join(_sender(), pname, color)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func pose(h: Vector3, hq: Quaternion, l: Vector3, lq: Quaternion, r: Vector3, rq: Quaternion) -> void:
	if is_server:
		server.on_pose(_sender(), h, hq, l, lq, r, rq)


@rpc("any_peer", "call_remote", "reliable")
func req_hit(eid: int, power: float) -> void:
	if is_server:
		server.on_hit(_sender(), eid, power)


@rpc("any_peer", "call_remote", "reliable")
func req_cast(o: Vector3, dir: Vector3) -> void:
	if is_server:
		server.on_cast(_sender(), o, dir)


@rpc("any_peer", "call_remote", "reliable")
func req_interact(npc: String) -> void:
	if is_server:
		server.on_interact(_sender(), npc)


@rpc("any_peer", "call_remote", "reliable")
func req_recall() -> void:
	if is_server:
		server.on_recall(_sender())


# ---------------- Server -> Client ----------------

@rpc("authority", "call_remote", "reliable")
func joined(id: int, st: Dictionary) -> void:
	if client:
		client.on_joined(id, st)


@rpc("authority", "call_remote", "reliable")
func join_failed(reason: String) -> void:
	if client:
		client.on_join_failed(reason)


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(pl: Array, en: Array) -> void:
	if client:
		client.on_snapshot(pl, en)


@rpc("authority", "call_remote", "reliable")
func stats(st: Dictionary) -> void:
	if client:
		client.on_stats(st)


@rpc("authority", "call_remote", "reliable")
func fx_damage(pos: Vector3, amount: int, kind: int) -> void:
	if client:
		client.on_damage(pos, amount, kind)


@rpc("authority", "call_remote", "reliable")
func fx(kind: int, pos: Vector3) -> void:
	if client:
		client.on_fx(kind, pos)


@rpc("authority", "call_remote", "reliable")
func fx_fireball(id: int, o: Vector3, dir: Vector3) -> void:
	if client:
		client.on_fireball(id, o, dir)


@rpc("authority", "call_remote", "reliable")
func fx_explode(id: int, pos: Vector3) -> void:
	if client:
		client.on_explode(id, pos)


@rpc("authority", "call_remote", "reliable")
func msg(text: String) -> void:
	if client:
		client.on_msg(text)


@rpc("authority", "call_remote", "reliable")
func dialog(npc: String, text: String) -> void:
	if client:
		client.on_dialog(npc, text)


@rpc("authority", "call_remote", "reliable")
func teleport(pos: Vector3) -> void:
	if client:
		client.on_teleport(pos)
