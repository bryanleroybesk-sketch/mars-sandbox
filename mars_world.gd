class_name MarsWorld
extends Node3D
## =============================================================================
##  A.V.A  "Mars Sandbox"  —  Environment Engine
## =============================================================================
##  Attach to the ROOT Node3D of the main scene.
##
##  Responsibilities
##  ----------------
##  1. Cinematic golden-hour lighting: low warm sun with soft shadows, cool sky
##     fill, dusty sky, AgX tonemapping, SSAO/SSIL, valley haze and bloom.
##  2. Fixed isometric camera rig (orthographic, 45° yaw / ~35° pitch) with
##     smooth zoom-to-cursor (wheel, trackpad pinch, +/- keys) and drag-pan.
##  3. Five operational hub anchors (Marker3D) + a Review Terminal anchor.
##     Higgsfield-generated GLB/FBX building scenes are instanced under each
##     anchor's "Model" child. Until then, low-poly placeholders are drawn.
##  4. Uneven procedural terrain (mars_terrain.gd) that flattens a pad under
##     every hub and grades roads between them, re-adapting when a hub moves.
##  5. Runtime-baked NavigationMesh (NavigationRegion3D) over that terrain,
##     carved around every hub's collider so agents path around buildings.
##  6. Agent roster: spawns one MarsAgent per executive role and exposes the
##     public API used by AgentBridge (dispatch_task, start_meeting, ...).
##
##  Scene tree produced at runtime (nodes that already exist in the .tscn with
##  the same names are REUSED, so you can also lay the scene out in the editor):
##
##  MarsWorld (Node3D, this script)
##  ├── WorldEnvironment
##  ├── Sun (DirectionalLight3D)
##  ├── CameraRig (Node3D)            ← yaw + pitch pivot
##  │   └── IsoCamera (Camera3D)      ← orthographic
##  ├── SkyFill (DirectionalLight3D)    ← cool bounce light, no shadows
##  ├── NavigationRegion3D
##  │   ├── Terrain (StaticBody3D, mars_terrain.gd) ← adapts to the hubs
##  │   └── Hubs (Node3D)
##  │       ├── CommandCenter (Marker3D)
##  │       │   ├── Model      (Node3D)        ← Higgsfield mesh goes here
##  │       │   ├── Obstacle   (StaticBody3D)  ← navmesh carve-out collider
##  │       │   └── Entrance   (Marker3D)      ← where agents stand to work
##  │       ├── SocialHub / CreativeLab / CommsTower / ServerFarm / ReviewTerminal
##  ├── Agents (Node3D)
##  └── AgentBridge (Node, agent_bridge.gd)   ← optional, added in main.tscn
## =============================================================================

# -----------------------------------------------------------------------------
#  Script dependencies
# -----------------------------------------------------------------------------
## Loaded by path rather than through the global `class_name` registry, so
## this file parses even before Godot has built its class cache (for example
## on the first open of a freshly unzipped project).
const MarsAgentScript := preload("res://mars_agent.gd")
const MarsTerrainScript := preload("res://mars_terrain.gd")

# -----------------------------------------------------------------------------
#  Signals
# -----------------------------------------------------------------------------
## Navigation mesh finished baking and the navigation map is synchronized.
signal navigation_ready
## A new agent was added to the colony (AgentBridge listens to this).
signal agent_spawned(agent: MarsAgentScript)
signal meeting_started(center: Vector3)
## Every attendee is physically inside the meeting radius.
signal meeting_assembled
signal meeting_ended

# -----------------------------------------------------------------------------
#  Hub identifiers (StringName keys used everywhere: world, agents, bridge)
# -----------------------------------------------------------------------------
const HUB_COMMAND_CENTER := &"command_center"
const HUB_SOCIAL_HUB := &"social_hub"
const HUB_CREATIVE_LAB := &"creative_lab"
const HUB_COMMS_TOWER := &"comms_tower"
const HUB_SERVER_FARM := &"server_farm"
const HUB_REVIEW_TERMINAL := &"review_terminal"

## Navmesh source group: every node in this group (and its children) is parsed
## for STATIC collision geometry when the navmesh bakes.
const NAV_SOURCE_GROUP := &"mars_nav_source"

## Physics layer 1 = world geometry (ground + hubs), layer 2 = agents.
const LAYER_WORLD := 1
const LAYER_AGENTS := 2

## Default hub layout (metres, Y-up). Command Center sits at the plaza origin.
##   node_name       : Marker3D node name in the scene tree
##   position        : anchor (building centre) position
##   footprint_radius: radius of the cylinder obstacle carved from the navmesh
##   height          : obstacle / placeholder height
##   shape           : placeholder silhouette ("dome", "block", "tower", "rack", "kiosk")
##   entrance_dir    : direction (XZ) from the centre to the working spot
const HUB_LAYOUT := {
	&"command_center": {
		"node_name": "CommandCenter", "label": "Command Center", "role": "CEO",
		"position": Vector3(0, 0, 0), "footprint_radius": 5.0, "height": 5.0,
		"shape": "dome", "entrance_dir": Vector3(0, 0, 1),
	},
	&"social_hub": {
		"node_name": "SocialHub", "label": "Social Hub", "role": "CMO",
		"position": Vector3(-17, 0, -11), "footprint_radius": 4.0, "height": 4.0,
		"shape": "dome", "entrance_dir": Vector3(1, 0, 0.6),
	},
	&"creative_lab": {
		"node_name": "CreativeLab", "label": "Creative Lab", "role": "CREATIVE_DIRECTOR",
		"position": Vector3(17, 0, -11), "footprint_radius": 4.0, "height": 4.5,
		"shape": "block", "entrance_dir": Vector3(-1, 0, 0.6),
	},
	&"comms_tower": {
		"node_name": "CommsTower", "label": "Comms Tower", "role": "OPERATOR",
		"position": Vector3(-17, 0, 12), "footprint_radius": 2.8, "height": 12.0,
		"shape": "tower", "entrance_dir": Vector3(1, 0, -0.4),
	},
	&"server_farm": {
		"node_name": "ServerFarm", "label": "Server Farm", "role": "ANALYST",
		"position": Vector3(17, 0, 12), "footprint_radius": 4.5, "height": 3.0,
		"shape": "rack", "entrance_dir": Vector3(-1, 0, -0.4),
	},
	&"review_terminal": {
		"node_name": "ReviewTerminal", "label": "Review Terminal", "role": "",
		"position": Vector3(0, 0, 12), "footprint_radius": 0.8, "height": 1.6,
		"shape": "kiosk", "entrance_dir": Vector3(0, 0, 1),
	},
}

## Executive roster. `name` is the canonical agent_name used by the backend.
const AGENT_ROSTER := [
	{"name": "CEO", "hub": &"command_center", "color": Color("e8b04a")},
	{"name": "CMO", "hub": &"social_hub", "color": Color("e0603a")},
	{"name": "CREATIVE_DIRECTOR", "hub": &"creative_lab", "color": Color("b67be0")},
	{"name": "OPERATOR", "hub": &"comms_tower", "color": Color("4fb3d9")},
	{"name": "ANALYST", "hub": &"server_farm", "color": Color("6cc46a")},
]

## Loose aliases the backend / LLM might use → canonical agent name.
const AGENT_ALIASES := {
	"ceo": "CEO", "chiefexecutive": "CEO", "boss": "CEO",
	"cmo": "CMO", "marketing": "CMO", "social": "CMO",
	"creativedirector": "CREATIVE_DIRECTOR", "creative": "CREATIVE_DIRECTOR",
	"cd": "CREATIVE_DIRECTOR", "designer": "CREATIVE_DIRECTOR",
	"operator": "OPERATOR", "ops": "OPERATOR", "logistics": "OPERATOR",
	"analyst": "ANALYST", "analytics": "ANALYST", "data": "ANALYST",
}

## Stylized palette sampled from the reference art.
const COLOR_HULL := Color("ddd6ca")
const COLOR_TRIM := Color("3b2b24")
const COLOR_ACCENT := Color("b5532a")

# -----------------------------------------------------------------------------
#  Inspector configuration
# -----------------------------------------------------------------------------
@export_group("Isometric Camera")
## Orthographic = crisp "diorama" isometric. Disable for a low-FOV perspective.
@export var use_orthographic := true
## Vertical world units visible on screen (orthographic zoom).
@export_range(10.0, 150.0) var ortho_size := 52.0
## Field of view used when use_orthographic == false (low FOV ≈ iso look).
@export_range(5.0, 40.0) var perspective_fov := 18.0
## Downward tilt. 35.264° is "true" isometric; 30°–45° all read well.
@export_range(20.0, 60.0) var camera_pitch_deg := 35.264
## Rotation around Y. 45° gives the classic diamond grid.
@export var camera_yaw_deg := 45.0
@export var camera_distance := 120.0
@export var camera_focus := Vector3.ZERO
## Zoom, pan and drag controls (rotation stays locked).
@export var enable_camera_controls := true
@export var camera_pan_speed := 25.0
## How far from the colony centre the camera may pan (metres).
@export var pan_limit := 60.0

@export_group("Camera Zoom")
## Closest zoom (orthographic size: smaller = closer).
@export_range(4.0, 60.0) var zoom_min := 12.0
## Farthest zoom.
@export_range(20.0, 200.0) var zoom_max := 115.0
## Fraction zoomed per mouse-wheel notch.
@export_range(0.02, 0.5) var zoom_step := 0.12
## Higher = snappier, lower = more cinematic glide.
@export_range(1.0, 30.0) var zoom_smoothing := 9.0
## Keep the point under the mouse fixed while zooming (like map apps).
@export var zoom_to_cursor := true

@export_group("Cinematic Lighting")
## Sun height above the horizon. Low = long golden-hour shadows.
@export_range(5.0, 85.0) var sun_elevation_deg := 30.0
## Sun compass direction.
@export_range(-180.0, 180.0) var sun_azimuth_deg := -40.0
@export var sun_color := Color(1.0, 0.87, 0.74)
@export_range(0.0, 8.0) var sun_energy := 2.0
## Cool blue bounce light from the opposite side (Mars skies go blue at sunset).
@export var fill_color := Color(0.55, 0.68, 1.0)
@export_range(0.0, 2.0) var fill_energy := 0.35
## Dust that settles in the low valleys.
@export_range(0.0, 1.0) var valley_haze := 0.18

@export_group("Terrain & Navigation")
@export var terrain_seed := 7
## Height of the rolling dunes (0 = flat).
@export_range(0.0, 6.0) var terrain_relief := 3.4
## Height of the crater rim that frames the colony.
@export_range(0.0, 40.0) var crater_rim_height := 16.0
## Navmesh agent radius: how far paths stay away from obstacle colliders.
## Keep radius/height multiples of the 0.25 m voxel cell size.
@export var nav_agent_radius := 0.75
@export var nav_agent_height := 2.0
## Radius of the ring agents stand on during a MEETING at the Command Center.
@export var meeting_radius := 9.0

@export_group("Higgsfield Building Models")
## Drop the imported Higgsfield scenes (.glb/.fbx or an inherited .tscn) here.
## Leave empty to render the procedural low-poly placeholder.
@export var command_center_model: PackedScene
@export var social_hub_model: PackedScene
@export var creative_lab_model: PackedScene
@export var comms_tower_model: PackedScene
@export var server_farm_model: PackedScene
@export var review_terminal_model: PackedScene
## Keep the auto-generated cylinder obstacle even when a model is assigned.
## Disable only if your model scene ships its own StaticBody3D colliders.
@export var auto_obstacle_colliders := true

@export_group("Higgsfield Character Models")
## Rigged + animated character scenes, one per executive role.
@export var ceo_model: PackedScene
@export var cmo_model: PackedScene
@export var creative_director_model: PackedScene
@export var operator_model: PackedScene
@export var analyst_model: PackedScene
## Optional: a whole agent scene (CharacterBody3D + mars_agent.gd) to clone
## instead of building agents in code.
@export var agent_scene_template: PackedScene

@export_group("Debug")
## M = toggle meeting, T = dispatch a random test task, R = rebake navmesh.
@export var debug_hotkeys := true

# -----------------------------------------------------------------------------
#  Runtime state
# -----------------------------------------------------------------------------
var camera_rig: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var terrain: MarsTerrainScript
var nav_region: NavigationRegion3D
var hubs_root: Node3D
var agents_root: Node3D

## hub_id (StringName) → Marker3D anchor
var _hub_anchors: Dictionary = {}
## canonical agent_name (String) → MarsAgent
var _agents: Dictionary = {}

var is_navigation_ready := false
var is_meeting_active := false
var _meeting_attendees: Array[MarsAgentScript] = []
var _meeting_assembled_emitted := false
var _meeting_timer: SceneTreeTimer

var _zoom_target := 52.0
## Screen point that stays fixed while a zoom glides (zoom-to-cursor).
var _zoom_anchor: Variant = null
var _drag_button := MOUSE_BUTTON_NONE


# =============================================================================
#  Lifecycle
# =============================================================================
func _ready() -> void:
	_build_environment()
	_build_camera_rig()
	_build_navigation_region()
	_build_hubs()
	# The terrain is shaped AFTER the hubs are placed, so it can flatten a pad
	# under each building and lift every hub onto its pad.
	_build_terrain()
	agents_root = _get_or_create(self, "Agents", Node3D) as Node3D

	# Bake the navmesh around the hub colliders, THEN spawn the colony. Agents
	# issuing path queries before the map syncs would receive empty paths.
	await rebake_navigation()
	_spawn_agents()


func _process(delta: float) -> void:
	if enable_camera_controls:
		_update_camera_pan(delta)
		_update_zoom(delta)
	if is_meeting_active and not _meeting_assembled_emitted:
		_check_meeting_assembled()


func _unhandled_input(event: InputEvent) -> void:
	if enable_camera_controls:
		_handle_camera_input(event)

	if debug_hotkeys and event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_M:
				if is_meeting_active:
					end_meeting()
				else:
					start_meeting(20.0)
			KEY_T:
				var roster_entry: Dictionary = AGENT_ROSTER.pick_random()
				dispatch_task(roster_entry.name, "Debug task #%d" % randi_range(100, 999))
			KEY_R:
				rebake_navigation()


# =============================================================================
#  1. Cinematic lighting
# =============================================================================
## Golden-hour setup: a low warm key light with soft (PCSS) shadows, a cool
## blue fill from the opposite side, a dusty procedural sky that feeds the
## ambient and reflected light, AgX tonemapping, SSAO + SSIL for grounded
## contact shading and bounce light, height fog that pools in the valleys,
## and a touch of bloom on the hot highlights.
func _build_environment() -> void:
	var world_env := _get_or_create(self, "WorldEnvironment", WorldEnvironment) as WorldEnvironment
	if world_env.environment == null:
		world_env.environment = _make_environment()

	sun = _get_or_create(self, "Sun", DirectionalLight3D) as DirectionalLight3D
	sun.rotation_degrees = Vector3(-sun_elevation_deg, sun_azimuth_deg, 0.0)
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	# Angular size of the sun → physically soft, contact-hardening shadows.
	sun.light_angular_distance = 1.2
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 220.0

	var fill := _get_or_create(self, "SkyFill", DirectionalLight3D) as DirectionalLight3D
	fill.rotation_degrees = Vector3(-35.0, sun_azimuth_deg + 180.0, 0.0)
	fill.light_color = fill_color
	fill.light_energy = fill_energy
	fill.light_specular = 0.0
	fill.shadow_enabled = false


func _make_environment() -> Environment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("b9784e")
	sky_mat.sky_horizon_color = Color("e9b98f")
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color("4a2616")
	sky_mat.ground_horizon_color = Color("d9a47c")
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# ACES: filmic highlight roll-off with rich, saturated desert colours.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82

	# Contact shadows in creases and at the base of every building.
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	# Sunlit sand bounces warm light onto the white buildings.
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 1.1

	# Dust haze: barely any distance fog (the orthographic camera sees every
	# point from about the same distance) and denser fog pooling below the pads.
	env.fog_enabled = true
	env.fog_light_color = Color("d99a70")
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.0005
	env.fog_sky_affect = 0.4
	env.fog_height = -1.5
	env.fog_height_density = valley_haze

	# Soft bloom on the brightest highlights (domes, lit screens).
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.08
	return env


# =============================================================================
#  2. Isometric camera with smooth zoom
# =============================================================================
## The rig is a pivot at the focus point. Euler order in Godot is YXZ, so the
## yaw (Y) is applied first and the pitch (X) tilts along the rotated axis —
## exactly the classic isometric construction. The camera is pushed back along
## the pivot's local +Z so it looks at the pivot down its own -Z axis.
func _build_camera_rig() -> void:
	camera_rig = _get_or_create(self, "CameraRig", Node3D) as Node3D
	camera = _get_or_create(camera_rig, "IsoCamera", Camera3D) as Camera3D
	_zoom_target = clampf(ortho_size, zoom_min, zoom_max)
	apply_camera_projection()
	camera.make_current()


## Re-applies projection settings (call after changing exports at runtime).
func apply_camera_projection() -> void:
	camera_rig.position = camera_focus
	camera_rig.rotation_degrees = Vector3(-camera_pitch_deg, camera_yaw_deg, 0.0)
	camera.position = Vector3(0.0, 0.0, camera_distance)
	camera.rotation = Vector3.ZERO
	camera.near = 1.0
	camera.far = camera_distance * 3.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if use_orthographic else Camera3D.PROJECTION_PERSPECTIVE
	_apply_zoom(_zoom_target)


## Current zoom, expressed as an orthographic size (also drives the FOV in
## perspective mode, so every control works the same in both modes).
func get_zoom() -> float:
	return camera.size if use_orthographic else camera.fov / perspective_fov * ortho_size


## Sets the zoom level (orthographic size). `instant` skips the smooth glide.
func set_zoom(value: float, instant: bool = false) -> void:
	_zoom_target = clampf(value, zoom_min, zoom_max)
	_zoom_anchor = null
	if instant:
		_apply_zoom(_zoom_target)


## Multiplies the zoom (factor < 1 zooms in). With `screen_point` the world
## point under it stays put, so you zoom toward the mouse.
func zoom_by(factor: float, screen_point: Variant = null) -> void:
	_zoom_target = clampf(_zoom_target * factor, zoom_min, zoom_max)
	_zoom_anchor = screen_point if zoom_to_cursor else null


func _apply_zoom(value: float) -> void:
	if use_orthographic:
		camera.size = value
	else:
		camera.fov = clampf(perspective_fov * value / ortho_size, 1.0, 80.0)
	# Keep shadow resolution focused on what is on screen.
	if sun:
		sun.directional_shadow_max_distance = camera_distance + value * 1.6


func _update_zoom(delta: float) -> void:
	var current := get_zoom()
	if is_equal_approx(current, _zoom_target):
		_zoom_anchor = null
		return
	var before: Variant = _ground_point(_zoom_anchor) if _zoom_anchor != null else null
	var next := lerpf(current, _zoom_target, 1.0 - exp(-zoom_smoothing * delta))
	if absf(next - _zoom_target) < 0.01:
		next = _zoom_target
	_apply_zoom(next)
	if before != null:
		var after: Variant = _ground_point(_zoom_anchor)
		if after != null:
			_move_focus((before as Vector3) - (after as Vector3))


func _handle_camera_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_by(1.0 - zoom_step * maxf(mb.factor, 0.2), mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_by(1.0 / (1.0 - zoom_step * maxf(mb.factor, 0.2)), mb.position)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				# Hold right or middle mouse and drag to pan.
				_drag_button = mb.button_index if mb.pressed else MOUSE_BUTTON_NONE
	elif event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		var mm := event as InputEventMouseMotion
		var from: Variant = _ground_point(mm.position - mm.relative)
		var to: Variant = _ground_point(mm.position)
		if from != null and to != null:
			_move_focus((from as Vector3) - (to as Vector3))
	elif event is InputEventMagnifyGesture:
		# Trackpad pinch (macOS).
		var mg := event as InputEventMagnifyGesture
		zoom_by(1.0 / maxf(mg.factor, 0.01), mg.position)
	elif event is InputEventPanGesture:
		# Two-finger trackpad scroll zooms, like most map apps.
		var pg := event as InputEventPanGesture
		zoom_by(1.0 + clampf(pg.delta.y, -3.0, 3.0) * 0.04, pg.position)
	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).physical_keycode:
			KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
				zoom_by(1.0 - zoom_step * 1.5)
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
				zoom_by(1.0 / (1.0 - zoom_step * 1.5))
			KEY_HOME:
				camera_focus = Vector3(0.0, camera_focus.y, 0.0)
				camera_rig.position = camera_focus
				set_zoom(ortho_size)


func _update_camera_pan(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if input == Vector2.ZERO:
		return
	# Pan on the ground plane, relative to the camera's fixed yaw. Speed scales
	# with zoom so panning feels the same close up and far away.
	var yaw := deg_to_rad(camera_yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var speed := camera_pan_speed * get_zoom() / ortho_size
	_move_focus((right * input.x + forward * input.y).normalized() * speed * delta)


func _move_focus(offset: Vector3) -> void:
	offset.y = 0.0
	camera_focus += offset
	var flat := Vector2(camera_focus.x, camera_focus.z).limit_length(pan_limit)
	camera_focus.x = flat.x
	camera_focus.z = flat.y
	camera_rig.position = camera_focus


## World point on the focus plane under a screen position (null if none).
func _ground_point(screen_pos: Variant) -> Variant:
	if screen_pos == null or camera == null:
		return null
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	return Plane(Vector3.UP, camera_focus.y).intersects_ray(origin, dir)


# =============================================================================
#  3. Terrain that adapts to the buildings
# =============================================================================
func _build_navigation_region() -> void:
	nav_region = _get_or_create(self, "NavigationRegion3D", NavigationRegion3D) as NavigationRegion3D


func _build_terrain() -> void:
	terrain = nav_region.get_node_or_null("Terrain") as MarsTerrainScript
	if terrain == null:
		terrain = MarsTerrainScript.new()
		nav_region.add_child(terrain)
	terrain.collision_layer = LAYER_WORLD
	terrain.collision_mask = 0
	terrain.add_to_group(NAV_SOURCE_GROUP)
	terrain.terrain_seed = terrain_seed
	terrain.dune_height = terrain_relief
	terrain.rim_height = crater_rim_height
	rebuild_terrain()


## Re-shapes the ground around the hubs' CURRENT positions: a flat pad under
## every building, graded roads to the Command Center, and every hub anchor
## lifted onto its pad. Call rebake_navigation() afterwards (move_hub() does).
func rebuild_terrain() -> void:
	var hub_ids: Array[StringName] = []
	var pads: Array = []
	for hub_id: StringName in _hub_anchors:
		var anchor: Marker3D = _hub_anchors[hub_id]
		hub_ids.append(hub_id)
		pads.append({
			"center": Vector2(anchor.position.x, anchor.position.z),
			"radius": float(anchor.get_meta(&"footprint_radius", 3.0)),
		})
	# Roads: every hub connects to the Command Center plaza.
	var roads: Array = []
	var hub_index := hub_ids.find(HUB_COMMAND_CENTER)
	for i in hub_ids.size():
		if hub_index >= 0 and i != hub_index:
			roads.append({"from": hub_index, "to": i})
	terrain.set_features(pads, roads)
	terrain.build()
	# Sit each building on its pad.
	for i in hub_ids.size():
		var anchor: Marker3D = _hub_anchors[hub_ids[i]]
		anchor.position.y = float(pads[i].height)
	camera_focus.y = get_hub_center(HUB_COMMAND_CENTER).y
	if camera_rig:
		camera_rig.position = camera_focus


## Moves a hub and lets the terrain re-adapt: the old pad fills back in,
## a new pad is levelled, roads are re-graded and the navmesh is rebaked.
func move_hub(hub_id: StringName, new_position: Vector3) -> void:
	var anchor := get_hub_anchor(hub_id)
	if anchor == null:
		push_warning("[MarsWorld] move_hub: unknown hub '%s'." % hub_id)
		return
	anchor.position = Vector3(new_position.x, 0.0, new_position.z)
	rebuild_terrain()
	await rebake_navigation()


## Ground height at any world XZ position.
func get_ground_height(x: float, z: float) -> float:
	return terrain.get_height(x, z) if terrain else 0.0


# =============================================================================
#  4. Operational hubs (Marker3D anchors + obstacles + Higgsfield model slots)
# =============================================================================
func _build_hubs() -> void:
	hubs_root = _get_or_create(nav_region, "Hubs", Node3D) as Node3D
	for hub_id: StringName in HUB_LAYOUT:
		_build_hub(hub_id, HUB_LAYOUT[hub_id])


func _build_hub(hub_id: StringName, spec: Dictionary) -> void:
	# --- Anchor --------------------------------------------------------------
	# If a Marker3D with this name already exists (placed in the editor), its
	# transform wins over HUB_LAYOUT. This lets level designers move hubs.
	var anchor := hubs_root.get_node_or_null(spec.node_name) as Marker3D
	if anchor == null:
		anchor = Marker3D.new()
		anchor.name = spec.node_name
		anchor.position = spec.position
		anchor.gizmo_extents = 2.0
		hubs_root.add_child(anchor)
	anchor.set_meta(&"hub_id", hub_id)
	anchor.set_meta(&"label", spec.label)
	anchor.set_meta(&"footprint_radius", spec.footprint_radius)
	# Parse the anchor AND all its children for navmesh obstacles. This means
	# any StaticBody3D inside an imported Higgsfield scene is carved too.
	anchor.add_to_group(NAV_SOURCE_GROUP)
	_hub_anchors[hub_id] = anchor

	# --- Model slot ----------------------------------------------------------
	var model_root := _get_or_create(anchor, "Model", Node3D) as Node3D
	var model_scene := _get_hub_model_scene(hub_id)
	if model_root.get_child_count() == 0:
		if model_scene:
			model_root.add_child(model_scene.instantiate())
		else:
			_build_placeholder_building(model_root, spec)

	# --- Navmesh obstacle ----------------------------------------------------
	if auto_obstacle_colliders or model_scene == null:
		var obstacle := _get_or_create(anchor, "Obstacle", StaticBody3D) as StaticBody3D
		obstacle.collision_layer = LAYER_WORLD
		obstacle.collision_mask = 0
		if obstacle.get_child_count() == 0:
			var col := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = spec.footprint_radius
			cyl.height = spec.height
			col.shape = cyl
			col.position.y = spec.height * 0.5
			obstacle.add_child(col)

	# --- Entrance (the "work spot" agents actually walk to) ------------------
	if anchor.get_node_or_null("Entrance") == null:
		var entrance := Marker3D.new()
		entrance.name = "Entrance"
		var dir: Vector3 = (spec.entrance_dir as Vector3).normalized()
		entrance.position = dir * (spec.footprint_radius + nav_agent_radius + 1.0)
		anchor.add_child(entrance)


func _get_hub_model_scene(hub_id: StringName) -> PackedScene:
	match hub_id:
		HUB_COMMAND_CENTER: return command_center_model
		HUB_SOCIAL_HUB: return social_hub_model
		HUB_CREATIVE_LAB: return creative_lab_model
		HUB_COMMS_TOWER: return comms_tower_model
		HUB_SERVER_FARM: return server_farm_model
		HUB_REVIEW_TERMINAL: return review_terminal_model
	return null


## Procedural low-poly stand-ins so the sandbox is playable before the
## Higgsfield assets land. They sit inside the obstacle cylinder footprint.
func _build_placeholder_building(parent: Node3D, spec: Dictionary) -> void:
	var r: float = spec.footprint_radius
	var h: float = spec.height
	var hull := _make_flat_material(COLOR_HULL, 0.9)
	var trim := _make_flat_material(COLOR_TRIM, 0.8)
	var accent := _make_flat_material(COLOR_ACCENT, 0.85)

	# Concrete foundation that sinks into the pad, so the building meets the
	# ground cleanly even where the terrain blends away.
	if spec.shape != "kiosk":
		var plinth := CylinderMesh.new()
		plinth.top_radius = r * 1.08
		plinth.bottom_radius = r * 1.15
		plinth.height = 1.6
		plinth.radial_segments = 16
		_add_mesh(parent, plinth, _make_flat_material(Color("d8c9b6"), 0.95), Vector3(0, -0.6, 0))

	match spec.shape:
		"dome":
			# Geodesic-ish dome: low radial segment count = faceted look.
			var dome := SphereMesh.new()
			dome.radius = r * 0.92
			dome.height = r * 1.84
			dome.radial_segments = 12
			dome.rings = 6
			_add_mesh(parent, dome, hull, Vector3(0, 0.3, 0))
			var ring := CylinderMesh.new()
			ring.top_radius = r
			ring.bottom_radius = r
			ring.height = 0.6
			ring.radial_segments = 12
			_add_mesh(parent, ring, trim, Vector3(0, 0.3, 0))
		"block":
			var body := BoxMesh.new()
			body.size = Vector3(r * 1.3, h, r * 1.1)
			_add_mesh(parent, body, hull, Vector3(0, h * 0.5, 0))
			var band := BoxMesh.new()
			band.size = Vector3(r * 1.32, 0.35, r * 1.12)
			_add_mesh(parent, band, accent, Vector3(0, h * 0.7, 0))
			var roof := BoxMesh.new()
			roof.size = Vector3(r * 0.6, 0.8, r * 0.5)
			_add_mesh(parent, roof, trim, Vector3(0, h + 0.4, 0))
		"tower":
			var shaft := CylinderMesh.new()
			shaft.top_radius = r * 0.25
			shaft.bottom_radius = r * 0.7
			shaft.height = h
			shaft.radial_segments = 8
			_add_mesh(parent, shaft, hull, Vector3(0, h * 0.5, 0))
			var dish := SphereMesh.new()
			dish.radius = r * 0.55
			dish.height = r * 0.35
			dish.radial_segments = 10
			_add_mesh(parent, dish, trim, Vector3(0, h, 0))
			var base := CylinderMesh.new()
			base.top_radius = r
			base.bottom_radius = r
			base.height = 0.8
			base.radial_segments = 8
			_add_mesh(parent, base, accent, Vector3(0, 0.4, 0))
		"rack":
			# Row of cylindrical tanks, like the reference's server/storage rows.
			for i in 3:
				var tank := CylinderMesh.new()
				tank.top_radius = 0.9
				tank.bottom_radius = 0.9
				tank.height = r * 1.3
				tank.radial_segments = 10
				var mi := _add_mesh(parent, tank, hull, Vector3(0, 1.0, (i - 1) * 2.0))
				mi.rotation_degrees.z = 90.0
				var cap := BoxMesh.new()
				cap.size = Vector3(r * 0.5, 1.2, 1.9)
				_add_mesh(parent, cap, accent, Vector3(0, 1.0, (i - 1) * 2.0))
		"kiosk":
			var post := BoxMesh.new()
			post.size = Vector3(0.9, h, 0.5)
			_add_mesh(parent, post, trim, Vector3(0, h * 0.5, 0))
			var screen := BoxMesh.new()
			screen.size = Vector3(1.1, 0.7, 0.1)
			var glow := _make_flat_material(Color("7fe0ff"), 0.4)
			glow.emission_enabled = true
			glow.emission = Color("7fe0ff")
			glow.emission_energy_multiplier = 1.5
			_add_mesh(parent, screen, glow, Vector3(0, h * 0.85, 0.3))


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _make_flat_material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	return mat


# =============================================================================
#  5. Navigation mapping
# =============================================================================
## (Re)bakes the navmesh from the ground + hub colliders. Call this again
## whenever a building is added, moved or swapped for a Higgsfield model.
## Awaitable: `await world.rebake_navigation()`.
func rebake_navigation() -> void:
	var nav_mesh := nav_region.navigation_mesh
	if nav_mesh == null:
		nav_mesh = NavigationMesh.new()
		nav_region.navigation_mesh = nav_mesh

	# Parse COLLIDERS (not render meshes): cheap, deterministic, and the
	# Higgsfield visual meshes can be as detailed as they like.
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = LAYER_WORLD
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = NAV_SOURCE_GROUP
	# Must match the navigation map cell size (project default 0.25).
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_radius = nav_agent_radius
	nav_mesh.agent_height = nav_agent_height
	nav_mesh.agent_max_climb = 0.25
	nav_mesh.agent_max_slope = 35.0
	# Only bake the colony basin, not the crater rim cliffs (much faster).
	nav_mesh.filter_baking_aabb = AABB(Vector3(-52.0, -20.0, -52.0), Vector3(104.0, 60.0, 104.0))

	is_navigation_ready = false
	var map := get_navigation_map()
	var iteration_before := NavigationServer3D.map_get_iteration_id(map)
	# Parsing happens on the main thread; the heavy voxel bake runs threaded.
	nav_region.bake_navigation_mesh(true)
	await nav_region.bake_finished
	# The navigation map only applies region changes on a later sync, and how
	# many syncs that takes differs between Godot versions (4.7 needs one more
	# than 4.4). Wait until the map has moved on AND a query really lands on
	# baked polygons; otherwise every query would return (0, 0, 0).
	# Wall-clock deadline, not a frame count: a big terrain navmesh can take a
	# while to reach the map, and frame rates vary a lot between machines.
	var deadline := Time.get_ticks_msec() + 15000
	while true:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > iteration_before \
				and NavigationServer3D.map_get_closest_point_owner(map, Vector3.ZERO).is_valid():
			break
		if Time.get_ticks_msec() > deadline:
			push_warning("[MarsWorld] Navigation map still empty after 15 s; agents may not path correctly.")
			break
	is_navigation_ready = true
	navigation_ready.emit()
	print("[MarsWorld] Navigation baked: %d polygons." % nav_mesh.get_polygon_count())


func get_navigation_map() -> RID:
	return get_world_3d().navigation_map


## Closest point on the navmesh to `point` (keeps random targets walkable).
func snap_to_navmesh(point: Vector3) -> Vector3:
	if not is_navigation_ready:
		return point
	return NavigationServer3D.map_get_closest_point(get_navigation_map(), point)


## Random walkable point within `radius` of `center`.
func random_nav_point_near(center: Vector3, radius: float) -> Vector3:
	var angle := randf() * TAU
	var dist := sqrt(randf()) * radius  # sqrt → uniform over the disc
	return snap_to_navmesh(center + Vector3(cos(angle), 0.0, sin(angle)) * dist)


# =============================================================================
#  Hub queries
# =============================================================================
func get_hub_anchor(hub_id: StringName) -> Marker3D:
	return _hub_anchors.get(hub_id)


## Building centre (for facing / look-at).
func get_hub_center(hub_id: StringName) -> Vector3:
	var anchor := get_hub_anchor(hub_id)
	return anchor.global_position if anchor else Vector3.ZERO


## Walkable working spot in front of the hub — this is what agents path to.
func get_hub_work_position(hub_id: StringName) -> Vector3:
	var anchor := get_hub_anchor(hub_id)
	if anchor == null:
		push_warning("[MarsWorld] Unknown hub '%s'." % hub_id)
		return Vector3.ZERO
	var entrance := anchor.get_node_or_null("Entrance") as Node3D
	var pos := entrance.global_position if entrance else anchor.global_position
	return snap_to_navmesh(pos)


func get_review_terminal_position() -> Vector3:
	return get_hub_work_position(HUB_REVIEW_TERMINAL)


## Accepts "social_hub", "Social Hub", "SocialHub", "CMO" … → hub id.
func resolve_hub_id(value: String) -> StringName:
	var key := value.strip_edges().to_lower().replace(" ", "_").replace("-", "_")
	if HUB_LAYOUT.has(StringName(key)):
		return StringName(key)
	var squashed := key.replace("_", "")
	for hub_id: StringName in HUB_LAYOUT:
		var spec: Dictionary = HUB_LAYOUT[hub_id]
		if String(spec.node_name).to_lower() == squashed or String(spec.role).to_lower().replace("_", "") == squashed:
			return hub_id
	return &""


# =============================================================================
#  Agent roster
# =============================================================================
func _spawn_agents() -> void:
	var i := 0
	for entry: Dictionary in AGENT_ROSTER:
		var agent: MarsAgentScript
		if agent_scene_template:
			agent = agent_scene_template.instantiate() as MarsAgentScript
		else:
			agent = MarsAgentScript.new()
		agent.name = String(entry.name).to_pascal_case()
		agent.agent_name = entry.name
		agent.home_hub = entry.hub
		agent.accent_color = entry.color
		var model := _get_agent_model_scene(entry.name)
		if model:
			agent.model_scene = model
		# Wire the agent to the world BEFORE it enters the tree so _ready()
		# can already query hubs and the navmesh.
		agent.world = self
		agents_root.add_child(agent)
		# Scatter them around the plaza in front of the Command Center.
		var angle := TAU * float(i) / AGENT_ROSTER.size()
		agent.global_position = snap_to_navmesh(Vector3(cos(angle), 0.0, sin(angle)) * 8.0 + Vector3(0, 0, 3))
		register_agent(agent)
		i += 1


func _get_agent_model_scene(agent_name: String) -> PackedScene:
	match agent_name:
		"CEO": return ceo_model
		"CMO": return cmo_model
		"CREATIVE_DIRECTOR": return creative_director_model
		"OPERATOR": return operator_model
		"ANALYST": return analyst_model
	return null


## Public so hand-placed agents (in the .tscn) can register themselves too.
func register_agent(agent: MarsAgentScript) -> void:
	if agent.world == null:
		agent.world = self
	_agents[agent.agent_name] = agent
	agent_spawned.emit(agent)


func get_agents() -> Array[MarsAgentScript]:
	var result: Array[MarsAgentScript] = []
	for agent: MarsAgentScript in _agents.values():
		result.append(agent)
	return result


## Case/format-insensitive lookup: "cmo", "Creative Director", "ops" …
func get_agent(agent_name: String) -> MarsAgentScript:
	if _agents.has(agent_name):
		return _agents[agent_name]
	var key := agent_name.strip_edges().to_lower().replace(" ", "").replace("_", "").replace("-", "")
	for canonical: String in _agents:
		if canonical.to_lower().replace("_", "") == key:
			return _agents[canonical]
	if AGENT_ALIASES.has(key):
		return _agents.get(AGENT_ALIASES[key])
	return null


## Agents available for socializing (IDLE or SOCIALIZING), excluding `asker`.
func get_free_agents(asker: MarsAgentScript = null) -> Array[MarsAgentScript]:
	var result: Array[MarsAgentScript] = []
	for agent: MarsAgentScript in _agents.values():
		if agent != asker and agent.is_free():
			result.append(agent)
	return result


## Main entry point for the backend bridge.
##   agent_name : "CMO", "cmo", "Creative Director" …
##   task_title : human-readable task ("Write Instagram Post")
##   hub        : optional override hub id/name; defaults to the agent's home
##   duration   : seconds of "working" animation (<= 0 → agent default)
## Returns false when the agent or hub cannot be resolved.
func dispatch_task(agent_name: String, task_title: String, hub: String = "", duration: float = -1.0, extra: Dictionary = {}) -> bool:
	var agent := get_agent(agent_name)
	if agent == null:
		push_warning("[MarsWorld] dispatch_task: unknown agent '%s'." % agent_name)
		return false
	var hub_id := agent.home_hub
	if hub != "":
		var resolved := resolve_hub_id(hub)
		if resolved != &"":
			hub_id = resolved
	agent.assign_task(task_title, get_hub_work_position(hub_id), duration, get_hub_center(hub_id), extra)
	return true


# =============================================================================
#  Global MEETING orchestration
# =============================================================================
## Summons every agent to the Command Center. `duration` <= 0 → until
## end_meeting() is called (e.g. by the backend).
func start_meeting(duration: float = -1.0) -> void:
	var center := get_hub_center(HUB_COMMAND_CENTER)
	var attendees := get_agents()
	if attendees.is_empty():
		return
	is_meeting_active = true
	_meeting_assembled_emitted = false
	_meeting_attendees = attendees

	# Spread attendees on a ring slot each so they don't pile up at one point.
	# The ring sits just inside `meeting_radius`, outside the dome footprint.
	var ring_radius: float = minf(meeting_radius - 1.0, HUB_LAYOUT[HUB_COMMAND_CENTER].footprint_radius + nav_agent_radius + 1.5)
	# Sort attendees by their current angle around the dome and hand out slots
	# in that same order, so nobody has to cross the crowd around the dome.
	var angle_of := func(a: MarsAgentScript) -> float:
		var d := a.global_position - center
		return fposmod(atan2(d.z, d.x), TAU)
	attendees.sort_custom(func(a: MarsAgentScript, b: MarsAgentScript) -> bool: return angle_of.call(a) < angle_of.call(b))
	var start_angle: float = angle_of.call(attendees[0])
	for i in attendees.size():
		var angle := start_angle + TAU * float(i) / attendees.size()
		var slot := snap_to_navmesh(center + Vector3(cos(angle), 0.0, sin(angle)) * ring_radius)
		attendees[i].join_meeting(slot, center, meeting_radius)

	meeting_started.emit(center)
	print("[MarsWorld] Meeting started with %d agents." % attendees.size())

	if duration > 0.0:
		_meeting_timer = get_tree().create_timer(duration)
		var timer := _meeting_timer
		timer.timeout.connect(func():
			# Ignore stale timers from an earlier meeting.
			if is_meeting_active and _meeting_timer == timer:
				end_meeting())


func end_meeting() -> void:
	if not is_meeting_active:
		return
	is_meeting_active = false
	_meeting_timer = null
	for agent in _meeting_attendees:
		if is_instance_valid(agent):
			agent.leave_meeting()
	_meeting_attendees.clear()
	meeting_ended.emit()
	print("[MarsWorld] Meeting ended.")


func _check_meeting_assembled() -> void:
	for agent in _meeting_attendees:
		if is_instance_valid(agent) and not agent.is_in_meeting_zone():
			return
	_meeting_assembled_emitted = true
	meeting_assembled.emit()


# =============================================================================
#  Snapshot (sent to the backend on request)
# =============================================================================
func get_colony_snapshot() -> Dictionary:
	var agents := []
	for agent: MarsAgentScript in _agents.values():
		agents.append(agent.to_dict())
	return {
		"meeting_active": is_meeting_active,
		"navigation_ready": is_navigation_ready,
		"agents": agents,
	}


# =============================================================================
#  Utilities
# =============================================================================
## Returns the child `node_name` of `parent`, creating it with `type` if missing.
func _get_or_create(parent: Node, node_name: String, type: Variant) -> Node:
	var node := parent.get_node_or_null(node_name)
	if node == null:
		node = type.new()
		node.name = node_name
		parent.add_child(node)
	return node
