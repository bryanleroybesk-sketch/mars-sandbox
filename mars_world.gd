class_name MarsWorld
extends Node3D
## =============================================================================
##  A.V.A  "Mars Sandbox"  —  Environment Engine
## =============================================================================
##  Attach to the ROOT Node3D of the main scene.
##
##  Responsibilities
##  ----------------
##  1. Lighting / environment tuned for the stylized terracotta Mars look.
##  2. Fixed isometric camera rig (orthographic, 45° yaw / ~35° pitch).
##  3. Five operational hub anchors (Marker3D) + a Review Terminal anchor.
##     Higgsfield-generated GLB/FBX building scenes are instanced under each
##     anchor's "Model" child. Until then, low-poly placeholders are drawn.
##  4. Runtime-baked NavigationMesh (NavigationRegion3D) that carves around
##     every hub's collider so agents path around the buildings.
##  5. Agent roster: spawns one MarsAgent per executive role and exposes the
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
##  ├── NavigationRegion3D
##  │   ├── Ground (StaticBody3D)
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
const COLOR_TERRAIN := Color("c4642e")
const COLOR_TERRAIN_DARK := Color("a24f22")
const COLOR_HULL := Color("ebe6dc")
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
@export var camera_distance := 90.0
@export var camera_focus := Vector3.ZERO
## WASD / arrow-key pan + mouse-wheel zoom (rotation stays locked).
@export var enable_camera_controls := true
@export var camera_pan_speed := 25.0

@export_group("Terrain & Navigation")
@export var ground_size := Vector2(80, 80)
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


# =============================================================================
#  Lifecycle
# =============================================================================
func _ready() -> void:
	_build_environment()
	_build_camera_rig()
	_build_navigation_region()
	_build_ground()
	_build_hubs()
	agents_root = _get_or_create(self, "Agents", Node3D) as Node3D

	# Bake the navmesh around the hub colliders, THEN spawn the colony. Agents
	# issuing path queries before the map syncs would receive empty paths.
	await rebake_navigation()
	_spawn_agents()


func _process(delta: float) -> void:
	if enable_camera_controls:
		_update_camera_pan(delta)
	if is_meeting_active and not _meeting_assembled_emitted:
		_check_meeting_assembled()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse-wheel zoom (orthographic size or FOV).
	if enable_camera_controls and event is InputEventMouseButton and event.pressed:
		var step := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = 1.0
		if step != 0.0:
			if use_orthographic:
				camera.size = clampf(camera.size + step * 3.0, 12.0, 150.0)
			else:
				camera.fov = clampf(camera.fov + step, 5.0, 40.0)

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
#  1. Environment & lighting
# =============================================================================
func _build_environment() -> void:
	var world_env := _get_or_create(self, "WorldEnvironment", WorldEnvironment) as WorldEnvironment
	if world_env.environment == null:
		var env := Environment.new()
		# Warm dusty sky colour instead of a skybox — the iso camera never sees
		# the horizon, so a flat colour is cheaper and matches the reference.
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("d99a6c")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("f3cfae")
		env.ambient_light_energy = 0.55
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.05
		# Soft contact shadows give the matte "clay diorama" feel.
		env.ssao_enabled = true
		env.ssao_radius = 1.5
		env.ssao_intensity = 1.6
		# Very light dust haze.
		env.fog_enabled = true
		env.fog_light_color = Color("dfa276")
		env.fog_density = 0.0025
		env.adjustment_enabled = true
		env.adjustment_saturation = 1.1
		world_env.environment = env

	var sun := _get_or_create(self, "Sun", DirectionalLight3D) as DirectionalLight3D
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_color = Color("ffe4c8")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0


# =============================================================================
#  2. Fixed isometric camera
# =============================================================================
## The rig is a pivot at the focus point. Euler order in Godot is YXZ, so the
## yaw (Y) is applied first and the pitch (X) tilts along the rotated axis —
## exactly the classic isometric construction. The camera is pushed back along
## the pivot's local +Z so it looks at the pivot down its own -Z axis.
func _build_camera_rig() -> void:
	camera_rig = _get_or_create(self, "CameraRig", Node3D) as Node3D
	camera = _get_or_create(camera_rig, "IsoCamera", Camera3D) as Camera3D
	apply_camera_projection()
	camera.make_current()


## Re-applies projection settings (call after changing exports at runtime).
func apply_camera_projection() -> void:
	camera_rig.position = camera_focus
	camera_rig.rotation_degrees = Vector3(-camera_pitch_deg, camera_yaw_deg, 0.0)
	camera.position = Vector3(0.0, 0.0, camera_distance)
	camera.rotation = Vector3.ZERO
	camera.near = 0.5
	camera.far = camera_distance * 3.0
	if use_orthographic:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = ortho_size
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = perspective_fov


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
	# Pan on the ground plane, relative to the camera's fixed yaw.
	var yaw := deg_to_rad(camera_yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var half := ground_size * 0.5
	camera_focus += (right * input.x + forward * input.y).normalized() * camera_pan_speed * delta
	camera_focus.x = clampf(camera_focus.x, -half.x, half.x)
	camera_focus.z = clampf(camera_focus.z, -half.y, half.y)
	camera_rig.position = camera_focus


# =============================================================================
#  3. Terrain
# =============================================================================
func _build_navigation_region() -> void:
	nav_region = _get_or_create(self, "NavigationRegion3D", NavigationRegion3D) as NavigationRegion3D


func _build_ground() -> void:
	var ground := _get_or_create(nav_region, "Ground", StaticBody3D) as StaticBody3D
	ground.collision_layer = LAYER_WORLD
	ground.collision_mask = 0
	ground.add_to_group(NAV_SOURCE_GROUP)

	# Collider: a 1 m thick slab whose top face sits exactly at y = 0.
	if ground.get_node_or_null("Collision") == null:
		var col := CollisionShape3D.new()
		col.name = "Collision"
		var box := BoxShape3D.new()
		box.size = Vector3(ground_size.x, 1.0, ground_size.y)
		col.shape = box
		col.position.y = -0.5
		ground.add_child(col)

	# Visual: terracotta plane with triplanar noise for dusty variation.
	if ground.get_node_or_null("Mesh") == null:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		var plane := PlaneMesh.new()
		# Oversized so the orthographic frame never shows the edge.
		plane.size = ground_size * 2.5
		mesh_instance.mesh = plane
		mesh_instance.material_override = _make_terrain_material()
		ground.add_child(mesh_instance)


func _make_terrain_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 4

	var ramp := Gradient.new()
	ramp.set_color(0, COLOR_TERRAIN_DARK)
	ramp.set_color(1, COLOR_TERRAIN.lightened(0.08))

	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.05, 0.05, 0.05)
	return mat


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
	nav_mesh.agent_max_slope = 40.0

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
	for i in 180:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > iteration_before \
				and NavigationServer3D.map_get_closest_point_owner(map, Vector3.ZERO).is_valid():
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
