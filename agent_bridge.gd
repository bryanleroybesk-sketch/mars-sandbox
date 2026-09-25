class_name AgentBridge
extends Node
## =============================================================================
##  A.V.A  "Mars Sandbox"  —  Godot ⇄ Python backend bridge (client side)
## =============================================================================
##  Add as a child of the MarsWorld root (main.tscn already does this).
##
##  Connects to the FastAPI engine (agent_bridge.py) over a WebSocket:
##      ws://127.0.0.1:8000/ws/godot
##  and keeps reconnecting with exponential back-off if the backend is down.
##
##  INBOUND  (Python → Godot), JSON objects with a "type" field:
##    {"type":"task", "agent":"CMO", "task":"Write Instagram Post",
##     "building":"social_hub", "duration":12, "task_id":"t-42"}
##    {"type":"meeting", "action":"start"|"end", "duration":30}
##    {"type":"review_result", "agent":"CMO", "task_id":"t-42",
##     "approved":true, "feedback":""}
##    {"type":"snapshot_request"}      {"type":"ping"}
##  Plain-text fallback: "CMO task received: Write Instagram Post"
##
##  OUTBOUND (Godot → Python):
##    hello, state, task_started, task_completed, snapshot, ack, pong and
##    review_request  ← the SAFETY HOOK: sent when an agent reaches the
##                      Review Terminal; Python speaks it on the Mac and
##                      waits for human voice/HTTP confirmation.
## =============================================================================

## Loaded by path (not via global class names) so this file parses even before
## Godot has built its class cache.
const MarsWorldScript := preload("res://mars_world.gd")
const MarsAgentScript := preload("res://mars_agent.gd")

signal connected
signal disconnected
signal message_received(message: Dictionary)
## Local safety hook: fired when an agent reaches the Review Terminal with
## finished work. Connect Mac-audio / UI logic here in addition to the WS.
signal human_review_requested(agent_name: String, task_title: String, payload: Dictionary)
signal review_resolved(agent_name: String, approved: bool)

@export var world_path: NodePath = ^".."
@export var server_url := "ws://127.0.0.1:8000/ws/godot"
@export var auto_connect := true
@export var reconnect_min_delay := 1.0
@export var reconnect_max_delay := 15.0
## Stream every agent state change to the backend (dashboards, LLM context).
@export var send_state_updates := true
@export var verbose := true

const MAX_OUTBOX := 200

var _world: MarsWorldScript
var _ws: WebSocketPeer
var _last_ready_state := WebSocketPeer.STATE_CLOSED
var _reconnect_delay := 1.0
var _reconnect_timer := 0.0
var _outbox: Array[String] = []
var _plaintext_task := RegEx.new()


func _ready() -> void:
	_plaintext_task.compile("(?i)^\\s*(?<agent>[A-Za-z _-]+?)\\s+task\\s+received\\s*:\\s*(?<task>.+)$")
	_world = get_node_or_null(world_path) as MarsWorldScript
	if _world == null:
		push_error("[AgentBridge] world_path does not point to a MarsWorld node.")
		return
	# Children are ready before their parent, so the colony isn't spawned yet:
	# subscribe to future agents, and wire any that already exist.
	_world.agent_spawned.connect(_wire_agent)
	for agent in _world.get_agents():
		_wire_agent(agent)
	_reconnect_delay = reconnect_min_delay
	if auto_connect:
		connect_to_backend()


func _process(delta: float) -> void:
	if _ws == null:
		if auto_connect:
			_reconnect_timer -= delta
			if _reconnect_timer <= 0.0:
				connect_to_backend()
		return

	_ws.poll()
	var ready_state := _ws.get_ready_state()
	if ready_state != _last_ready_state:
		_on_ready_state_changed(_last_ready_state, ready_state)
		_last_ready_state = ready_state

	match ready_state:
		WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				_handle_raw(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_ws = null
			_last_ready_state = WebSocketPeer.STATE_CLOSED
			_reconnect_timer = _reconnect_delay
			_reconnect_delay = minf(_reconnect_delay * 2.0, reconnect_max_delay)


# =============================================================================
#  Connection
# =============================================================================
func connect_to_backend() -> void:
	# A fresh peer per attempt avoids stale internal state after failures.
	_ws = WebSocketPeer.new()
	_last_ready_state = WebSocketPeer.STATE_CLOSED
	var err := _ws.connect_to_url(server_url)
	if err != OK:
		_log("connect_to_url failed (%s), retrying in %.1fs" % [error_string(err), _reconnect_delay])
		_ws = null
		_reconnect_timer = _reconnect_delay


func is_backend_connected() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _on_ready_state_changed(previous: int, current: int) -> void:
	if current == WebSocketPeer.STATE_OPEN:
		_log("connected to %s" % server_url)
		_reconnect_delay = reconnect_min_delay
		# Send hello + snapshot first, then anything queued while offline.
		var pending := _outbox.duplicate()
		_outbox.clear()
		send_json({"type": "hello", "client": "godot-mars-sandbox", "engine": Engine.get_version_info().string})
		send_json({"type": "snapshot", "data": _world.get_colony_snapshot()})
		for text in pending:
			_ws.send_text(text)
		connected.emit()
	elif current == WebSocketPeer.STATE_CLOSED and previous == WebSocketPeer.STATE_OPEN:
		_log("disconnected (code %d: %s)" % [_ws.get_close_code(), _ws.get_close_reason()])
		disconnected.emit()


## Sends a JSON message now, or queues it until the socket is open.
func send_json(message: Dictionary) -> void:
	var text := JSON.stringify(message)
	if is_backend_connected():
		_ws.send_text(text)
	else:
		_outbox.append(text)
		if _outbox.size() > MAX_OUTBOX:
			_outbox.pop_front()  # drop oldest telemetry first


# =============================================================================
#  Inbound routing
# =============================================================================
func _handle_raw(text: String) -> void:
	if not text.strip_edges().begins_with("{"):
		_handle_plaintext(text)
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		handle_message(parsed)
	else:
		_log("malformed JSON ignored: %s" % text.left(200))


## Public so tests / the debug console can inject messages directly.
func handle_message(msg: Dictionary) -> void:
	message_received.emit(msg)
	var kind := String(msg.get("type", ""))
	match kind:
		"task":
			var agent_name := String(msg.get("agent", ""))
			var title := String(msg.get("task", "Untitled task"))
			var ok := _world.dispatch_task(
				agent_name,
				title,
				String(msg.get("building", "")),
				float(msg.get("duration", -1.0)),
				{"task_id": String(msg.get("task_id", "")), "source": "backend"} if msg.has("task_id") else {"source": "backend"},
			)
			_log("task → %s: %s (%s)" % [agent_name, title, "ok" if ok else "REJECTED"])
			send_json({"type": "ack", "ref": "task", "ok": ok, "agent": agent_name, "task_id": msg.get("task_id", "")})
		"meeting":
			if String(msg.get("action", "start")) == "end":
				_world.end_meeting()
			else:
				_world.start_meeting(float(msg.get("duration", -1.0)))
			send_json({"type": "ack", "ref": "meeting", "ok": true})
		"review_result":
			var agent := _world.get_agent(String(msg.get("agent", "")))
			var ok := false
			if agent:
				ok = agent.resolve_review(bool(msg.get("approved", false)), String(msg.get("feedback", "")))
				if ok:
					review_resolved.emit(agent.agent_name, bool(msg.get("approved", false)))
			send_json({"type": "ack", "ref": "review_result", "ok": ok, "agent": msg.get("agent", "")})
		"snapshot_request":
			send_json({"type": "snapshot", "data": _world.get_colony_snapshot()})
		"ping":
			send_json({"type": "pong"})
		_:
			_log("unknown message type '%s'" % kind)


## "CMO task received: Write Instagram Post" / "meeting start" / "meeting end"
func _handle_plaintext(text: String) -> void:
	var m := _plaintext_task.search(text)
	if m:
		handle_message({"type": "task", "agent": m.get_string("agent"), "task": m.get_string("task")})
		return
	var lower := text.strip_edges().to_lower()
	if lower.begins_with("meeting"):
		handle_message({"type": "meeting", "action": "end" if lower.contains("end") else "start"})
	else:
		_log("ignored plain-text message: %s" % text)


# =============================================================================
#  Outbound: agent events + SAFETY REVIEW HOOK
# =============================================================================
func _wire_agent(agent: MarsAgentScript) -> void:
	if not agent.review_requested.is_connected(_on_agent_review_requested):
		agent.review_requested.connect(_on_agent_review_requested)
		agent.task_started.connect(_on_agent_task_event.bind("task_started"))
		agent.task_completed.connect(_on_agent_task_event.bind("task_completed"))
		agent.state_changed.connect(_on_agent_state_changed)


func _on_agent_review_requested(agent: MarsAgentScript, task: Dictionary) -> void:
	var title := String(task.get("title", ""))
	# Keep acronyms ("CMO") intact; "CREATIVE_DIRECTOR" → "Creative Director".
	var spoken := agent.agent_name if agent.agent_name.length() <= 3 else agent.agent_name.replace("_", " ").capitalize()
	var payload := {
		"type": "review_request",
		"agent": agent.agent_name,
		"task": title,
		"task_id": String(task.get("id", "")),
		"revisions": int(task.get("revisions", 0)),
		"prompt": "%s has finished %s. Do you approve?" % [spoken, title],
	}
	_log("REVIEW requested by %s for '%s'" % [agent.agent_name, title])
	human_review_requested.emit(agent.agent_name, title, payload)
	send_json(payload)


func _on_agent_task_event(agent: MarsAgentScript, task: Dictionary, kind: String) -> void:
	send_json({"type": kind, "agent": agent.agent_name, "task": task.get("title", ""), "task_id": task.get("id", "")})


func _on_agent_state_changed(agent: MarsAgentScript, _previous: int, _current: int) -> void:
	if send_state_updates:
		var data := agent.to_dict()
		data["type"] = "state"
		send_json(data)


func _log(text: String) -> void:
	if verbose:
		print("[AgentBridge] ", text)
