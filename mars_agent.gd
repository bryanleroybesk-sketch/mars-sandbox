class_name MarsAgent
extends CharacterBody3D
## =============================================================================
##  A.V.A  "Mars Sandbox"  —  Autonomous Agent Controller
## =============================================================================
##  Attach to a CharacterBody3D. Missing components (CollisionShape3D,
##  NavigationAgent3D, model, debug label) are created automatically, so the
##  node works both from `MarsAgent.new()` and from a hand-built .tscn.
##
##  STATE MACHINE
##  -------------
##      ┌──────────── task assigned ─────────────┐
##      │                                        ▼
##    IDLE ──boredom──▶ SOCIALIZING           WORKING ──done──▶ AWAITING_REVIEW
##      ▲                   │  ▲                 │                   │
##      │◀── tired / bored ─┘  └─ linger again   │                   │ approved
##      │◀──────────────── queue empty ──────────┴───────────────────┘
##
##    MEETING  ← start_meeting() interrupts ANY state; leave_meeting() resumes
##               whatever the agent was doing (task progress is kept).
##
##  • WORKING         Path to the task's hub entrance, then play "working"
##                    until progress reaches the task duration.
##  • AWAITING_REVIEW Safety gate: walk to the Review Terminal and emit
##                    `review_requested` → AgentBridge → Mac voice confirmation.
##                    Waits for resolve_review(approved).
##  • MEETING         Walk to an assigned ring slot around the Command Center,
##                    stop inside meeting_radius, face the centre, "talking".
##  • IDLE            Rest (energy regenerates) while boredom builds up.
##  • SOCIALIZING     Boredom threshold reached → pick another free agent,
##                    walk next to them and "hang out" (talking), then linger
##                    or drift to another group. Never just stands still long.
##
##  NEEDS
##  -----
##  energy  (0–100) drains while working, regenerates while idle/socializing.
##                  Low energy slows work and makes the agent rest.
##  boredom (0–100) grows while idle, drops while talking to someone.
## =============================================================================

# -----------------------------------------------------------------------------
#  Signals
# -----------------------------------------------------------------------------
signal state_changed(agent: MarsAgent, previous: State, current: State)
signal task_started(agent: MarsAgent, task: Dictionary)
signal task_completed(agent: MarsAgent, task: Dictionary)
## Reached the Review Terminal with finished work → needs human confirmation.
signal review_requested(agent: MarsAgent, task: Dictionary)
signal destination_reached(agent: MarsAgent, position: Vector3)
## Fired whenever the logical animation changes (hook audio/VFX here).
signal animation_changed(agent: MarsAgent, anim_key: StringName)

# -----------------------------------------------------------------------------
#  Types & constants
# -----------------------------------------------------------------------------
enum State { IDLE, WORKING, MEETING, SOCIALIZING, AWAITING_REVIEW }
enum WorkPhase { TRAVEL, PERFORM }

## Logical animation keys. Map them to real clip names via `animation_map`.
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_WORKING := &"working"
const ANIM_TALKING := &"talking"

# -----------------------------------------------------------------------------
#  Inspector configuration
# -----------------------------------------------------------------------------
@export_group("Identity")
## Canonical name used by the backend ("CEO", "CMO", …).
@export var agent_name: String = "Agent"
## Hub id this agent works at (see MarsWorld.HUB_LAYOUT).
@export var home_hub: StringName = &""
@export var accent_color: Color = Color.WHITE

@export_group("State")
@export var current_state: State = State.IDLE:
	set = _set_state
## Current navigation destination (task hub, meeting slot, hangout spot …).
@export var target_building: Vector3 = Vector3.ZERO
@export_range(0.0, 100.0) var energy: float = 100.0
@export_range(0.0, 100.0) var boredom: float = 0.0

@export_group("Movement")
@export var move_speed := 3.2
@export var turn_speed := 10.0
## Distance at which a destination counts as reached.
@export var arrival_distance := 0.6
## RVO avoidance between agents (smooth crowd flow around each other).
@export var use_avoidance := true
## Seconds of near-zero progress before the agent repaths / gives up.
@export var stuck_timeout := 2.5

@export_group("Needs")
@export var energy_drain_working := 2.5
@export var energy_regen_idle := 8.0
@export var energy_regen_social := 3.0
@export var boredom_gain_idle := 10.0
@export var boredom_decay_talking := 12.0
## Boredom level at which an IDLE agent goes looking for company.
@export var boredom_social_threshold := 30.0
@export var low_energy_threshold := 20.0

@export_group("Social")
## Distance at which two agents count as "hanging out" together.
@export var conversation_radius := 2.6
## Random roam radius when nobody else is free.
@export var wander_radius := 9.0
@export var linger_min := 4.0
@export var linger_max := 9.0
@export var idle_min := 1.5
@export var idle_max := 4.0

@export_group("Work")
@export var default_task_duration := 8.0
## Route finished work through the Review Terminal (human-in-the-loop gate).
@export var require_review := true

@export_group("Model & Animation")
## Higgsfield rigged character scene (GLB/FBX or inherited .tscn).
@export var model_scene: PackedScene
## glTF characters face +Z. Adjust if your rig faces another way.
@export var model_yaw_offset_deg := 0.0
@export var model_scale := 1.0
## Logical key → clip name inside the model's AnimationPlayer. Unmapped or
## missing clips fall back to a case-insensitive "contains" search, so
## "Armature|Walk_Cycle" still resolves for key "walk".
@export var animation_map: Dictionary = {
	"idle": "idle",
	"walk": "walk",
	"working": "working",
	"talking": "talking",
}
@export var anim_blend_time := 0.2
@export var show_debug_label := true

# -----------------------------------------------------------------------------
#  Runtime references & state
# -----------------------------------------------------------------------------
## Injected by MarsWorld before the agent enters the tree.
var world: MarsWorld
var nav_agent: NavigationAgent3D

var current_task: Dictionary = {}
var _task_queue: Array[Dictionary] = []
var _task_counter := 0
var _work_phase: WorkPhase = WorkPhase.TRAVEL
var _work_progress := 0.0
## True once review_requested was emitted for current_task.
var _review_pending := false

var _is_moving := false
var _arrival_radius := 0.6
var _stuck_timer := 0.0
var _stuck_strikes := 0
## Closest flat distance to the target reached so far (progress tracking).
var _best_distance := INF
## While > 0, RVO avoidance is bypassed so the agent can slip through a crowd.
var _avoidance_suspended := 0.0
var _state_timer := 0.0
var _look_at_point: Variant = null  # Vector3 or null

var _meeting_center := Vector3.ZERO
var _meeting_radius := 8.0
var _meeting_slot := Vector3.ZERO

var _conversation_partner: MarsAgent

var _model_root: Node3D
var _anim_player: AnimationPlayer
var _clip_cache: Dictionary = {}
var _current_anim: StringName = &""
var _placeholder_time := 0.0
var _debug_label: Label3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


# =============================================================================
#  Lifecycle
# =============================================================================
func _ready() -> void:
	collision_layer = 2  # agents
	collision_mask = 1   # world only — agents avoid each other via RVO
	_ensure_collision_shape()
	_ensure_navigation_agent()
	_build_model()
	_build_debug_label()
	_arrival_radius = arrival_distance
	_enter_idle()


func _physics_process(delta: float) -> void:
	# Before the navigation map has synced, path queries return nothing.
	if not _navigation_is_ready():
		_submit_velocity(Vector3.ZERO)
		return
	_update_needs(delta)
	_update_state(delta)
	_update_locomotion(delta)


func _process(delta: float) -> void:
	if _anim_player == null:
		_animate_placeholder(delta)
	if _debug_label:
		_debug_label.text = "%s\n%s  E%d B%d" % [agent_name, get_state_name(), roundi(energy), roundi(boredom)]


# =============================================================================
#  PUBLIC API  (used by MarsWorld / AgentBridge)
# =============================================================================
## Queues a task. Starts it right away if the agent is free.
##   destination : walkable work position (hub entrance)
##   look_at     : point to face while working (hub centre)
func assign_task(title: String, destination: Vector3, duration: float = -1.0, look_at: Variant = null, extra: Dictionary = {}) -> Dictionary:
	_task_counter += 1
	var task_id := String(extra.get("task_id", ""))
	if task_id.is_empty():
		task_id = "%s-%d" % [agent_name, _task_counter]
	var task := {
		"id": task_id,
		"title": title,
		"destination": destination,
		"look_at": look_at,
		"duration": duration if duration > 0.0 else default_task_duration,
		"done": false,
		"revisions": 0,
		"started": false,
		"extra": extra,
	}
	if is_free():
		_start_task(task)
	else:
		# Busy (working, reviewing or in a meeting) → run after current duty.
		_task_queue.append(task)
	return task


## Called by MarsWorld.start_meeting(). Interrupts everything.
func join_meeting(slot: Vector3, center: Vector3, radius: float) -> void:
	_meeting_slot = slot
	_meeting_center = center
	_meeting_radius = radius
	current_state = State.MEETING
	_conversation_partner = null
	_move_to(slot)


## Called by MarsWorld.end_meeting(). Resumes previous duties.
func leave_meeting() -> void:
	if current_state == State.MEETING:
		_resume_duties()


## Human verdict from the Mac voice confirmation loop.
## Approved → task completes. Rejected → agent goes back and redoes it.
func resolve_review(approved: bool, feedback: String = "") -> bool:
	if current_task.is_empty() or not current_task.done:
		return false
	_review_pending = false
	if approved:
		var finished := current_task
		current_task = {}
		task_completed.emit(self, finished)
		if current_state != State.MEETING:
			_resume_duties()
	else:
		current_task.done = false
		current_task.revisions += 1
		current_task["feedback"] = feedback
		_work_progress = 0.0
		if current_state != State.MEETING:
			_begin_work()
	return true


## Available for socializing / immediate tasks.
func is_free() -> bool:
	return current_state == State.IDLE or current_state == State.SOCIALIZING


func is_in_meeting_zone() -> bool:
	return current_state == State.MEETING and not _is_moving \
		and _flat_distance(global_position, _meeting_center) <= _meeting_radius


func get_state_name() -> String:
	return State.keys()[current_state]


func get_queue_size() -> int:
	return _task_queue.size()


func to_dict() -> Dictionary:
	return {
		"agent": agent_name,
		"state": get_state_name(),
		"energy": snappedf(energy, 0.1),
		"boredom": snappedf(boredom, 0.1),
		"task": current_task.get("title", ""),
		"task_id": current_task.get("id", ""),
		"queue": _task_queue.size(),
		"position": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
	}


# =============================================================================
#  STATE MACHINE
# =============================================================================
func _set_state(new_state: State) -> void:
	var previous := current_state
	current_state = new_state
	if nav_agent:
		# Agents on duty don't yield to socializers; the crowd yields to them.
		var on_duty := new_state in [State.WORKING, State.MEETING, State.AWAITING_REVIEW]
		nav_agent.avoidance_priority = 1.0 if on_duty else 0.5
	if previous != new_state and is_inside_tree():
		state_changed.emit(self, previous, new_state)


func _update_state(delta: float) -> void:
	match current_state:
		State.IDLE:
			_tick_idle(delta)
		State.SOCIALIZING:
			_tick_socializing(delta)
		State.WORKING:
			_tick_working(delta)
		State.MEETING, State.AWAITING_REVIEW:
			pass  # purely event-driven (arrival / resolve_review / leave_meeting)


## Called when locomotion reaches `target_building`.
func _on_destination_reached() -> void:
	destination_reached.emit(self, target_building)
	match current_state:
		State.WORKING:
			_work_phase = WorkPhase.PERFORM
			_look_at_point = current_task.get("look_at")
			_play(ANIM_WORKING)
		State.AWAITING_REVIEW:
			_look_at_point = world.get_hub_center(MarsWorld.HUB_REVIEW_TERMINAL) if world else null
			_play(ANIM_TALKING)
			if not _review_pending:
				_review_pending = true
				review_requested.emit(self, current_task)
		State.MEETING:
			_look_at_point = _meeting_center
			_play(ANIM_TALKING)
		State.SOCIALIZING:
			_on_hangout_spot_reached()
		State.IDLE:
			_play(ANIM_IDLE)


## Decides what to do after an interruption / completion.
func _resume_duties() -> void:
	if not current_task.is_empty():
		if current_task.done:
			_go_to_review()
		else:
			_begin_work()
	elif not _task_queue.is_empty():
		_start_task(_task_queue.pop_front())
	else:
		_enter_idle()


# ---------------------------------------------------------------- IDLE ------
func _enter_idle() -> void:
	current_state = State.IDLE
	_stop_moving()
	_conversation_partner = null
	_look_at_point = null
	_play(ANIM_IDLE)
	_state_timer = randf_range(idle_min, idle_max)


func _tick_idle(delta: float) -> void:
	_state_timer -= delta
	if _state_timer > 0.0 and boredom < boredom_social_threshold:
		return
	if energy < low_energy_threshold:
		# Too tired to socialize — keep resting a bit longer.
		_state_timer = randf_range(idle_min, idle_max)
		return
	# Either bored enough, or idled long enough: go find company.
	_enter_socializing()


# --------------------------------------------------------- SOCIALIZING ------
func _enter_socializing() -> void:
	current_state = State.SOCIALIZING
	_pick_hangout_spot()


## Chooses where to hang out:
##  1. Prefer a free agent that is already standing somewhere (joins a group).
##  2. If they are walking to a hangout spot, head for THEIR destination so
##     groups converge instead of chasing each other.
##  3. Nobody free → roam to a random walkable point nearby.
func _pick_hangout_spot() -> void:
	_conversation_partner = null
	_look_at_point = null
	var spot := Vector3.INF

	if world:
		var peers := world.get_free_agents(self)
		if not peers.is_empty():
			# Favour the nearest few, but keep some randomness.
			peers.sort_custom(func(a: MarsAgent, b: MarsAgent) -> bool:
				return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
			var partner: MarsAgent = peers[randi() % mini(3, peers.size())]
			var anchor := partner.target_building if partner._is_moving else partner.global_position
			# Stand on a random point of a small ring around the partner.
			var angle := randf() * TAU
			var offset := Vector3(cos(angle), 0.0, sin(angle)) * conversation_radius * 0.6
			spot = world.snap_to_navmesh(anchor + offset)
			_conversation_partner = partner
		else:
			spot = world.random_nav_point_near(global_position, wander_radius)

	if spot == Vector3.INF:
		spot = global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * wander_radius * 0.5

	_move_to(spot, conversation_radius * 0.4)


func _on_hangout_spot_reached() -> void:
	_conversation_partner = _find_nearby_free_agent()
	if _conversation_partner:
		_play(ANIM_TALKING)
		_state_timer = randf_range(linger_min, linger_max)
	else:
		# Alone: shorter linger so the agent keeps moving around.
		_play(ANIM_IDLE)
		_state_timer = randf_range(linger_min, linger_max) * 0.5


func _tick_socializing(delta: float) -> void:
	if _is_moving:
		return

	# Keep facing (and keep checking) the conversation partner.
	if _conversation_partner and (not is_instance_valid(_conversation_partner)
			or not _conversation_partner.is_free()
			or _flat_distance(global_position, _conversation_partner.global_position) > conversation_radius * 1.5):
		_conversation_partner = null
		_play(ANIM_IDLE)
	if _conversation_partner == null:
		# Somebody may have walked up to us in the meantime.
		_conversation_partner = _find_nearby_free_agent()
		if _conversation_partner:
			_play(ANIM_TALKING)
	_look_at_point = _conversation_partner.global_position if _conversation_partner else null

	_state_timer -= delta
	if _state_timer > 0.0:
		return
	if energy < low_energy_threshold or (boredom <= 1.0 and randf() < 0.4):
		_enter_idle()  # socially satisfied or tired → rest
	else:
		_pick_hangout_spot()  # drift to another group


func _find_nearby_free_agent() -> MarsAgent:
	if world == null:
		return null
	var best: MarsAgent = null
	var best_dist := conversation_radius
	for other in world.get_free_agents(self):
		var d := _flat_distance(global_position, other.global_position)
		if d <= best_dist:
			best = other
			best_dist = d
	return best


# ------------------------------------------------------------- WORKING ------
func _start_task(task: Dictionary) -> void:
	current_task = task
	_work_progress = 0.0
	_review_pending = false
	_begin_work()


func _begin_work() -> void:
	current_state = State.WORKING
	_conversation_partner = null
	_work_phase = WorkPhase.TRAVEL
	if not current_task.started:
		current_task.started = true
		task_started.emit(self, current_task)
	_move_to(current_task.destination)


func _tick_working(delta: float) -> void:
	if _work_phase != WorkPhase.PERFORM:
		return
	# Tired agents work slower (50 % speed at 0 energy).
	_work_progress += delta * lerpf(0.5, 1.0, energy / 100.0)
	if _work_progress >= current_task.duration:
		_finish_work()


func _finish_work() -> void:
	current_task.done = true
	if require_review and world:
		_go_to_review()
	else:
		var finished := current_task
		current_task = {}
		task_completed.emit(self, finished)
		_resume_duties()


# ----------------------------------------------------- AWAITING_REVIEW ------
func _go_to_review() -> void:
	current_state = State.AWAITING_REVIEW
	_move_to(world.get_review_terminal_position())


# =============================================================================
#  NEEDS
# =============================================================================
func _update_needs(delta: float) -> void:
	match current_state:
		State.WORKING:
			var drain := energy_drain_working if _work_phase == WorkPhase.PERFORM else energy_drain_working * 0.3
			energy -= drain * delta
			boredom -= 2.0 * delta
		State.IDLE:
			energy += energy_regen_idle * delta
			boredom += boredom_gain_idle * delta
		State.SOCIALIZING:
			energy += energy_regen_social * delta
			if _conversation_partner:
				boredom -= boredom_decay_talking * delta
			else:
				boredom += boredom_gain_idle * 0.25 * delta
		State.MEETING:
			energy -= 0.5 * delta
			boredom += 0.5 * delta
		State.AWAITING_REVIEW:
			boredom += boredom_gain_idle * 0.3 * delta
	energy = clampf(energy, 0.0, 100.0)
	boredom = clampf(boredom, 0.0, 100.0)


# =============================================================================
#  LOCOMOTION  (NavigationAgent3D steering + RVO avoidance)
# =============================================================================
func _move_to(destination: Vector3, radius: float = -1.0) -> void:
	target_building = destination
	_arrival_radius = radius if radius > 0.0 else arrival_distance
	nav_agent.target_desired_distance = _arrival_radius
	nav_agent.target_position = destination
	_is_moving = true
	_stuck_timer = 0.0
	_stuck_strikes = 0
	_best_distance = INF
	_look_at_point = null
	_play(ANIM_WALK)


func _stop_moving() -> void:
	_is_moving = false
	_stuck_timer = 0.0


func _update_locomotion(delta: float) -> void:
	if not _is_moving:
		_submit_velocity(Vector3.ZERO)
		return

	if nav_agent.is_navigation_finished() or _flat_distance(global_position, target_building) <= _arrival_radius:
		_stop_moving()
		_submit_velocity(Vector3.ZERO)
		_on_destination_reached()
		return

	var next := nav_agent.get_next_path_position()
	var to_next := next - global_position
	to_next.y = 0.0
	var desired := Vector3.ZERO
	if to_next.length_squared() > 0.0001:
		desired = to_next.normalized() * move_speed * _speed_multiplier()
	_submit_velocity(desired)
	_avoidance_suspended = maxf(0.0, _avoidance_suspended - delta)

	# Stuck detection by PROGRESS, not speed: RVO can make a boxed-in agent
	# oscillate at full speed without getting any closer to its target.
	var remaining := _flat_distance(global_position, target_building)
	if remaining < _best_distance - 0.25:
		_best_distance = remaining
		_stuck_timer = 0.0
	else:
		_stuck_timer += delta
		if _stuck_timer >= stuck_timeout:
			_handle_stuck(remaining)


func _handle_stuck(remaining: float) -> void:
	_stuck_timer = 0.0
	_best_distance = INF
	_stuck_strikes += 1
	if current_state == State.SOCIALIZING:
		_pick_hangout_spot()  # just go somewhere else
	elif _stuck_strikes >= 3 and remaining <= 3.0:
		# Close enough — treat as arrived rather than jitter forever.
		_stop_moving()
		_on_destination_reached()
	else:
		# Walk through the crowd for a moment (agents don't physically collide
		# with each other) and force a fresh path.
		_avoidance_suspended = 1.5
		nav_agent.target_position = target_building


func _speed_multiplier() -> float:
	# Exhausted agents shuffle; bored socializers stroll.
	var m := lerpf(0.7, 1.0, energy / 100.0)
	if current_state == State.SOCIALIZING:
		m *= 0.75
	return m


## Routes the desired velocity through RVO avoidance when enabled; the
## avoidance-safe velocity comes back via `velocity_computed`.
func _submit_velocity(desired: Vector3) -> void:
	if desired == Vector3.ZERO:
		# Standing agents must not be shoved around by RVO; they act as a
		# static obstacle for the others instead of drifting off their spot.
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity_forced(Vector3.ZERO)
		_apply_velocity(Vector3.ZERO)
	elif use_avoidance and nav_agent.avoidance_enabled and _avoidance_suspended <= 0.0:
		nav_agent.velocity = desired
	else:
		_apply_velocity(desired)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	# Stationary agents are handled directly in _submit_velocity; applying the
	# RVO "dodge" result to them would make them drift away from their spot.
	if _is_moving and _avoidance_suspended <= 0.0:
		_apply_velocity(safe_velocity)


func _apply_velocity(horizontal: Vector3) -> void:
	var dt := get_physics_process_delta_time()
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * dt
	move_and_slide()
	_update_facing(horizontal, dt)


func _update_facing(horizontal: Vector3, dt: float) -> void:
	if _model_root == null:
		return
	var dir := Vector3.ZERO
	if Vector2(horizontal.x, horizontal.z).length() > 0.2:
		dir = horizontal
	elif _look_at_point is Vector3:
		dir = (_look_at_point as Vector3) - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	# atan2(x, z) = yaw for a +Z-forward model (glTF convention).
	var target_yaw := atan2(dir.x, dir.z) + deg_to_rad(model_yaw_offset_deg)
	_model_root.rotation.y = lerp_angle(_model_root.rotation.y, target_yaw, clampf(turn_speed * dt, 0.0, 1.0))


func _navigation_is_ready() -> bool:
	if world and not world.is_navigation_ready:
		return false
	return NavigationServer3D.map_get_iteration_id(nav_agent.get_navigation_map()) > 0


# =============================================================================
#  ANIMATION HOOKS  (Higgsfield rig → AnimationPlayer)
# =============================================================================
## Plays a logical animation (ANIM_IDLE / WALK / WORKING / TALKING).
func _play(key: StringName) -> void:
	if key == _current_anim:
		return
	_current_anim = key
	animation_changed.emit(self, key)
	if _anim_player == null:
		return  # placeholder body animates procedurally in _process
	var clip := _resolve_clip(key)
	if clip != &"":
		_anim_player.play(clip, anim_blend_time)


## Finds the real clip for a logical key and caches it.
func _resolve_clip(key: StringName) -> StringName:
	if _clip_cache.has(key):
		return _clip_cache[key]
	var result: StringName = &""
	var mapped := String(animation_map.get(String(key), String(key)))
	if _anim_player.has_animation(mapped):
		result = StringName(mapped)
	else:
		# Fuzzy fallback: "Armature|Walk_Cycle", "library/Idle01", …
		var needle := mapped.to_lower()
		for clip_name in _anim_player.get_animation_list():
			if String(clip_name).to_lower().contains(needle):
				result = clip_name
				break
	if result == &"":
		push_warning("[MarsAgent:%s] No clip for '%s' (mapped '%s')." % [agent_name, key, mapped])
	else:
		# Locomotion/loop clips must loop even if the importer didn't flag it.
		var anim := _anim_player.get_animation(result)
		if anim and anim.loop_mode == Animation.LOOP_NONE:
			anim.loop_mode = Animation.LOOP_LINEAR
	_clip_cache[key] = result
	return result


## Simple bob/sway so placeholder capsules visibly show their state.
func _animate_placeholder(delta: float) -> void:
	if _model_root == null:
		return
	_placeholder_time += delta
	var t := _placeholder_time
	match _current_anim:
		ANIM_WALK:
			_model_root.position.y = absf(sin(t * 10.0)) * 0.12
			_model_root.rotation.z = sin(t * 10.0) * 0.05
		ANIM_WORKING:
			_model_root.position.y = absf(sin(t * 16.0)) * 0.05
			_model_root.rotation.z = 0.0
		ANIM_TALKING:
			_model_root.position.y = 0.0
			_model_root.rotation.z = sin(t * 3.0) * 0.08
		_:
			_model_root.position.y = sin(t * 2.0) * 0.02
			_model_root.rotation.z = 0.0


# =============================================================================
#  COMPONENT SETUP
# =============================================================================
func _ensure_collision_shape() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			return
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	col.shape = capsule
	col.position.y = 0.9
	add_child(col)


func _ensure_navigation_agent() -> void:
	nav_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if nav_agent == null:
		nav_agent = NavigationAgent3D.new()
		nav_agent.name = "NavigationAgent3D"
		add_child(nav_agent)
	# The baked navmesh floats ~0.5 m above the ground (cell_height rounding)
	# while this body's origin is at its feet. Waypoint checks are 3D, so
	# without this offset the vertical gap alone could keep a waypoint from
	# ever counting as "reached" and the agent would orbit it forever.
	nav_agent.path_height_offset = 0.5
	nav_agent.path_desired_distance = 0.75
	nav_agent.target_desired_distance = arrival_distance
	nav_agent.path_max_distance = 3.0
	nav_agent.height = 1.8
	nav_agent.radius = 0.5
	nav_agent.max_speed = move_speed
	nav_agent.avoidance_enabled = use_avoidance
	nav_agent.neighbor_distance = 6.0
	nav_agent.max_neighbors = 8
	nav_agent.time_horizon_agents = 1.0
	if not nav_agent.velocity_computed.is_connected(_on_velocity_computed):
		nav_agent.velocity_computed.connect(_on_velocity_computed)


func _build_model() -> void:
	_model_root = get_node_or_null("ModelRoot") as Node3D
	if _model_root == null:
		_model_root = Node3D.new()
		_model_root.name = "ModelRoot"
		add_child(_model_root)
	_model_root.scale = Vector3.ONE * model_scale

	if _model_root.get_child_count() == 0:
		if model_scene:
			_model_root.add_child(model_scene.instantiate())
		else:
			_build_placeholder_body()

	# Grab the first AnimationPlayer anywhere inside the imported rig.
	var players := _model_root.find_children("*", "AnimationPlayer", true, false)
	_anim_player = players[0] as AnimationPlayer if not players.is_empty() else null


## White suit + coloured visor capsule matching the colony palette.
func _build_placeholder_body() -> void:
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color("f1ede6")
	suit.roughness = 0.85
	var accent := StandardMaterial3D.new()
	accent.albedo_color = accent_color
	accent.roughness = 0.6

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.7
	body.mesh = capsule
	body.material_override = suit
	body.position.y = 0.85
	_model_root.add_child(body)

	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.4
	band_mesh.bottom_radius = 0.4
	band_mesh.height = 0.14
	band.mesh = band_mesh
	band.material_override = accent
	band.position.y = 0.95
	_model_root.add_child(band)

	# Visor on the +Z side = "forward" for the facing logic.
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.44, 0.18, 0.12)
	visor.mesh = visor_mesh
	visor.material_override = accent
	visor.position = Vector3(0.0, 1.45, 0.32)
	_model_root.add_child(visor)


func _build_debug_label() -> void:
	if not show_debug_label:
		return
	_debug_label = Label3D.new()
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.fixed_size = true
	_debug_label.pixel_size = 0.0012
	_debug_label.font_size = 28
	_debug_label.outline_size = 8
	_debug_label.modulate = accent_color.lightened(0.3)
	_debug_label.position.y = 2.4
	add_child(_debug_label)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
