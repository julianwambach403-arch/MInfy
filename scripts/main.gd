extends Node
## Startpunkt. Entscheidet anhand der Startparameter, ob Server oder Client startet.
##   Server:  godot --headless --xr-mode off --path . -- --server [--port=7777]
##   Client:  normal starten (Quest/PC-VR), oder am PC ohne Brille: -- --desktop

const Cfg = preload("res://scripts/config.gd")


func _ready() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if opts.has("server") or OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless":
		Game.start_server(int(opts.get("port", Cfg.SERVER_PORT)))
	else:
		Game.start_client(self, opts)
