extends Node

class_name NetworkManager

# Configuration constants
const CONNECTION_TIMEOUT := 3.0
const MAX_RECONNECTION_ATTEMPTS := 3
const RECONNECTION_DELAY := 2.0

# ENUMs
enum NetworkMode { SERVER, CLIENT, INTEGRATED, SPECTATOR }

# Signals
signal connection_established
signal connection_failed
signal server_ready
signal all_players_connected
signal player_connected(id: int)
signal player_disconnected(id: int)

# Dependencies
const map_base_script := preload("res://scripts/map/map.gd")

# Network configuration
var api_server: String = "https://api.open-champ.com"
var address: String = "127.0.0.1"
var port: int = 10000
var max_players: int = -1
var tickrate: int = 30
var game_mode: String = "openchamp:onslaught"
var server_map_id: Identifier
var jwt: String
var network_mode: NetworkMode = NetworkMode.INTEGRATED

# Server state
var players: Array[Dictionary] = []
var mode_manifest_data: Dictionary = {}
var server_map_config: Dictionary = {}
var server_pid: int = 0

# Client state
var connection_attempts: int = 0
var last_team: int = 1
var team_count: int = -1

# UI references
@onready var ui = $ConnectionUI
@onready var status_text = $ConnectionUI/Background/ConnectionStatus
@onready var reconnect_button = $ConnectionUI/Background/ReconnectButton
@onready var exit_button = $ConnectionUI/Background/ExitButton
@onready var host_button = $ConnectionUI/Background/HostButton
@onready var map_spawner = $MapSpawner

func _ready() -> void:
	_initialize()

func _initialize() -> void:
	_set_status("STARTUP:STATUS_CONNECTING")
	
	# Connect signals
	connection_established.connect(_on_connection_established)
	connection_failed.connect(_on_connection_failed)
	server_ready.connect(_on_server_ready)
	
	# Parse CLI arguments
	network_mode = _parse_command_line_args()
	
	# Setup spawners
	map_spawner.spawn_function = map_spawn_function
	
	# Connect mode-based signals
	if network_mode == NetworkMode.INTEGRATED || network_mode == NetworkMode.SERVER:
		all_players_connected.connect(_on_all_players_connected)
		
	# Start networking
	call_deferred("start_networking", network_mode)

# NETWORKING SETUP FUNCTIONS
func start_networking(mode: NetworkMode) -> void:
	var peer = ENetMultiplayerPeer.new()

	match mode:
		NetworkMode.INTEGRATED:
			ui.show()
			if not _setup_server(peer):
				_fail_server()
				return
				
			multiplayer.multiplayer_peer = peer
			_success_server()
			_add_player(multiplayer.multiplayer_peer.get_unique_id())
			_success_client()
			
		NetworkMode.SERVER:
			Config.is_dedicated_server = true
			if not _setup_server(peer):
				_fail_server()
				return
				
			multiplayer.multiplayer_peer = peer
			_success_server()
			
		NetworkMode.CLIENT:
			ui.show()
			if _setup_client(peer):
				connection_attempts = 0
				_start_connection_timeout()
			else:
				_fail_client()
		
		NetworkMode.SPECTATOR:
			# TODO: Implement spectator mode
			push_error("Spectator mode not implemented")

func _setup_client(peer: ENetMultiplayerPeer) -> bool:
	_set_status("STARTUP:STATUS_CONNECT_CLIENT")
	print("Attempting connection to: %s:%s" % [address, port])

	var err = peer.create_client(address, port)
	
	if err != OK:
		push_error("Failed to create client with error code: %d" % err)
		return false
	
	multiplayer.multiplayer_peer = peer
	_set_status("STARTUP:STATUS_CONNECTING")
	return true

func _setup_server(peer: ENetMultiplayerPeer) -> bool:
	_set_status("STARTUP:STATUS_CREATE_SERVER")

	_load_gamemode(game_mode)
	if max_players == -1:
		max_players = server_map_config.get("max_players", 4)
	if team_count == -1:
		team_count = server_map_config.get("teams", 2)

	# Connect Peer Signals
	peer.peer_connected.connect(_add_player)
	peer.peer_disconnected.connect(_remove_player)

	# Create Server
	var err = peer.create_server(port, max_players)
	if err != OK:
		if err == ERR_ALREADY_IN_USE:
			push_error("Port %d is already in use" % port)
		else:
			push_error("Server failed to start with error code: %d" % err)
		return false

	return true

func _success_client() -> void:
	_set_status("STARTUP:STATUS_CLIENT_CONNECTED")	
	# Get game mode from server
	rpc_id(get_multiplayer_authority(), "get_gamemode")
	_load_gamemode(game_mode)
	connection_established.emit()

func _success_server() -> void:
	print("Server started, beginning initialization")

	# Set tickrate
	if network_mode != NetworkMode.INTEGRATED:
		Engine.max_fps = tickrate
	
	# Wait for player connections
	var wait_timer = Timer.new()
	wait_timer.name = "WaitTimer"
	wait_timer.wait_time = 1.0
	wait_timer.autostart = true
	wait_timer.timeout.connect(_update_server_state)
	add_child(wait_timer)
	
	server_ready.emit()

func _fail_client() -> void:
	_set_status("STARTUP:STATUS_CLIENT_FAILED")
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	
	connection_failed.emit()

func _fail_server() -> void:
	push_error("Server failed to start")
	get_tree().quit(1)

# CONNECTION MANAGEMENT
func _start_connection_timeout() -> void:
	# Remove any existing connection timer (no if exists check needed)
	var existing_timer = get_node_or_null("CheckConnectionTimer")
	if existing_timer:
		existing_timer.queue_free()
	
	# Create new connection check timer
	var timer = Timer.new()
	timer.name = "CheckConnectionTimer"
	timer.wait_time = CONNECTION_TIMEOUT
	timer.one_shot = true
	timer.timeout.connect(_on_connection_timer_timeout)
	add_child(timer)
	timer.start()
	
	# Update status
	_set_status("STARTUP:STATUS_CONNECTING")
	print("Connection attempt %d/%d starting..." % [connection_attempts + 1, MAX_RECONNECTION_ATTEMPTS])

func _on_connection_timer_timeout() -> void:
	var timer = get_node("CheckConnectionTimer")
	
	if _check_connection():
		print("Connection successful!")
		_success_client()
		timer.queue_free()
	else:
		print("Connection attempt %d failed" % (connection_attempts + 1))
		connection_attempts += 1
		
		if connection_attempts >= MAX_RECONNECTION_ATTEMPTS:
			push_error("Max reconnection attempts reached")
			_fail_client()
			timer.queue_free()

			if network_mode == NetworkMode.CLIENT:
				reconnect_button.show()
				exit_button.show()
		else:
			print("Retrying in %d seconds..." % RECONNECTION_DELAY)
			_set_status("STARTUP:STATUS_RETRY_CONNECTING")
			timer.wait_time = RECONNECTION_DELAY
			timer.start()
	

func _check_connection() -> bool:
	if not multiplayer.multiplayer_peer:
		return false
		
	var connection_status = multiplayer.multiplayer_peer.get_connection_status()
	return connection_status == MultiplayerPeer.CONNECTION_CONNECTED

func _update_server_state() -> void:
	var timer = get_node("WaitTimer")

	# Count connected players
	var connected_players = multiplayer.get_peers().size()
	if network_mode == NetworkMode.INTEGRATED:
		connected_players += 1
		
	print("%d/%d players connected" % [connected_players, max_players])

	# Player Check
	if connected_players == 0:
		print("No players connected")
		return
	
	if server_map_config.get("require_all_players", false) and connected_players != max_players:
		print("Waiting for more players...")
		return

	print("All required players connected, server ready!")

	# Clean up timer
	timer.stop()
	timer.timeout.disconnect(_update_server_state)
	timer.queue_free()

	# Prevent new connections
	# TODO: Reconnection logic/support for disconnected players
	multiplayer.multiplayer_peer.refuse_new_connections = true

	# Disconnect signals (Memory Leak Prevention)
	var peer = multiplayer.multiplayer_peer
	if peer.peer_connected.is_connected(_add_player):
		peer.peer_connected.disconnect(_add_player)
	if peer.peer_disconnected.is_connected(_remove_player):
		peer.peer_disconnected.disconnect(_remove_player)

	# Load map with connected players
	_change_map(players)
	all_players_connected.emit()

# PLAYER MANAGEMENT
func _add_player(id: int) -> void:
	print("Player connected: %d" % id)
	player_connected.emit(id)
	rpc_id(id, "get_jwt")

func _remove_player(id: int) -> void:
	print("Player disconnected: %d" % id)
	for i in range(players.size()):
		if players[i].peer_id == id:
			players.remove_at(i)
			break
	
	player_disconnected.emit(id)

# RESOURCE LOADING
func _load_gamemode(gamemode_id: String) -> void:
	# Skip if already loaded
	if not server_map_config.is_empty():
		return
		
	# Load gamemode manifest
	var manifest_path = "gamemode://" + gamemode_id
	var manifest_json = load(manifest_path)
	if not manifest_json:
		push_error("Failed to load gamemode manifest from: %s" % manifest_path)
		return
		
	mode_manifest_data = manifest_json.data

	# Load map configuration
	server_map_config = RegistryManager.load_manifest(mode_manifest_data, gamemode_id)

	# Add map to spawner if not in dedicated server mode
	if not Config.is_dedicated_server:
		var map_path = "map://" + server_map_config.get("id", "")
		server_map_id = Identifier.for_resource(map_path)
		map_spawner.add_spawnable_scene(AssetIndexer.get_asset_path(server_map_id))

# MAP MANAGEMENT
func _change_map(player_list: Array) -> void:
	var map = $Map

	# Remove existing map children
	for child in map.get_children():
		map.remove_child(child)
		child.queue_free()

	# Set up new map configuration
	server_map_config["players"] = player_list
	map_spawner.spawn(server_map_config)

	# Notify clients
	rpc("map_loaded")

func map_spawn_function(data: Variant) -> Node:
	if not data or not data.has("id"):
		push_error("Invalid map data")
		return null
		
	var map_id = Identifier.for_resource("map://" + data["id"])

	# Load map scene
	var scene = load(AssetIndexer.get_asset_path(map_id))
	if not scene:
		push_error("Failed to load map scene")
		return null
		
	var new_map = scene.instantiate()

	# Set up map with configuration
	new_map.set_script(map_base_script)
	new_map.map_configuration = server_map_config
	new_map.add_to_group("Map")
	new_map.connected_players = data.get("players", [])

	return new_map

# USER AUTHENTICATION
@rpc("any_peer")
func set_jwt(token: String) -> void:
	var user: Dictionary
	
	if token.is_empty():
		# Create default user with no token
		user = _create_default_user()
	else:
		user = await _fetch_user(token)
		if user.is_empty():
			user = _create_default_user()

	players.append(user)

func _fetch_user(token: String) -> Dictionary:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var url = api_server + "/user"
	var headers = ["Authorization: Bearer " + token]
	
	var error = http_request.request(url, headers)
	if error != OK:
		push_error("HTTP request failed with error: %d" % error)
		http_request.queue_free()
		return {}
		
	var result = await http_request.request_completed
	http_request.queue_free()
	
	var response_code = result[1]
	var response_body = result[3]
	
	if response_code != 200:
		push_error("API request failed with status code: %d" % response_code)
		return {}
		
	var response_text = response_body.get_string_from_utf8()
	var json = JSON.new()
	error = json.parse(response_text)
	
	if error != OK:
		push_error("Failed to parse API response: %s" % json.get_error_message())
		return {}
		
	return json.get_data()

func _create_default_user() -> Dictionary:
	# Assign team using round-robin
	var team = last_team + 1
	if team > team_count:
		team = 1
	last_team = team

	# Create user data
	var peer_id = multiplayer.get_remote_sender_id()
	return {
		"id": "0",  # Local user, no user in DB
		"peer_id": peer_id,
		"name": "Player_%d" % peer_id,
		"character": "openchamp:orion",
		"team": team
	}

# RPC METHODS
@rpc("authority", "call_local")
func map_loaded() -> void:
	ui.hide()

@rpc("authority", "call_local")
func get_jwt() -> void:
	rpc("set_jwt", jwt if jwt else "")

@rpc("any_peer")
func get_gamemode() -> void:
	rpc_id(multiplayer.get_remote_sender_id(), "set_gamemode", game_mode)

@rpc("authority", "call_local")
func set_gamemode(gamemode_id: String) -> void:
	game_mode = gamemode_id

# UTILITY FUNCTIONS
func _parse_command_line_args() -> NetworkMode:
	var args = Array(OS.get_cmdline_args())
	var mode = NetworkMode.INTEGRATED
	
	# Set default mode for headless
	if DisplayServer.get_name() == "headless":
		mode = NetworkMode.SERVER

	# Parse arguments
	for i in range(args.size()):
		var arg = args[i]
		
		match arg:
			# Mode flags
			"-S":
				mode = NetworkMode.SERVER
			"-I":
				mode = NetworkMode.INTEGRATED
			"-C":
				mode = NetworkMode.CLIENT
			"-G":
				mode = NetworkMode.SPECTATOR
				
			# Server configuration
			"-tr":
				if i + 1 < args.size():
					tickrate = int(args[i + 1])
					Engine.physics_ticks_per_second = tickrate
					i += 1
			"-pl":
				if i + 1 < args.size():
					max_players = int(args[i + 1])
					i += 1
			"-gm":
				if i + 1 < args.size():
					game_mode = args[i + 1]
					i += 1
					
			# Client configuration
			"-s":
				if i + 1 < args.size():
					address = args[i + 1]
					i += 1
			"-p":
				if i + 1 < args.size():
					port = int(args[i + 1])
					i += 1
			"-t":
				if i + 1 < args.size():
					jwt = args[i + 1]
					i += 1

	return mode

func _set_status(message: String) -> void:
	status_text.text = "[center]" + tr(message) + "[/center]"

# UI EVENT HANDLERS
func _on_reconnect_button_pressed() -> void:
	_set_status("STARTUP:STATUS_RECONNECTING")
	connection_attempts = 0
	
	# Create new peer and attempt connection
	var peer = ENetMultiplayerPeer.new()
	
	if _setup_client(peer):
		_start_connection_timeout()
	else:
		_fail_client()
		
	# Hide buttons until we know the result
	reconnect_button.hide()
	exit_button.hide()

func _on_exit_button_pressed() -> void:
	get_tree().quit()

# SIGNAL HANDLERS
func _on_connection_established() -> void:
	print("Connection established successfully")

func _on_connection_failed() -> void:
	print("Connection failed")

func _on_server_ready() -> void:
	print("Server is ready")

func _on_all_players_connected() -> void:
	print("All players are connected")

# CLEANUP
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if server_pid != 0:
			OS.kill(server_pid)
		get_tree().quit()
