class_name MarsTerrain
extends StaticBody3D
## =============================================================================
##  A.V.A  "Mars Sandbox"  —  Procedural terrain that adapts to buildings
## =============================================================================
##  Created and driven by mars_world.gd. Produces:
##    • Rolling dune terrain (layered noise) with fine wind ripples.
##    • A raised crater rim with terraced, layered cliffs around the colony.
##    • A flat PAD under every building: the pad sits at the terrain's natural
##      height at that spot and blends back into the dunes with a smooth
##      slope, so buildings always sit cleanly on the ground.
##    • Graded ROADS between the Command Center plaza and every hub.
##    • Vertex colours (valleys, ridges, cliff strata, compacted dust on pads
##      and roads) and a scatter of low-poly boulders.
##    • A trimesh collider, which the navmesh bake parses to find walkable ground.
##
##  Call `set_features(pads, roads)` and then `build()`. Rebuild whenever a
##  building moves: the pads follow the buildings and the ground re-adapts.
## =============================================================================

@export_group("Shape")
@export var size := 170.0            ## World-space width/depth (metres)
@export var resolution := 1.0        ## Metres between vertices
@export var terrain_seed := 7
@export var dune_height := 2.4       ## Amplitude of the rolling dunes
@export var dune_frequency := 0.024
@export var ripple_height := 0.18    ## Fine wind ripples
@export var rim_start := 44.0        ## Crater rim starts rising at this radius
@export var rim_end := 78.0
@export var rim_height := 16.0
@export var rim_terrace_step := 2.2  ## Height of each cliff terrace

@export_group("Adaptation")
@export var pad_margin := 3.0        ## Flat ring beyond the building footprint
@export var pad_blend := 7.0         ## Width of the slope back into the dunes
@export var road_half_width := 1.8
@export var road_blend := 3.5

@export_group("Decoration")
@export var rock_count := 420

@export_group("Colours")
@export var color_low := Color("9e4a22")
@export var color_mid := Color("c4642e")
@export var color_high := Color("dc8a4e")
@export var color_dust := Color("d08a58")   ## pads and roads
@export var color_cliff := Color("7c3a1e")
@export var color_strata := Color("b8683c")

## Pads:  [{ "center": Vector2, "radius": float, "height": float }] ("height" is filled in by build())
var pads: Array = []
## Roads: [{ "from": int, "to": int }], indices into `pads`
var roads: Array = []

var _noise := FastNoiseLite.new()
var _ripple := FastNoiseLite.new()
var _mesa := FastNoiseLite.new()
var _tint := FastNoiseLite.new()
var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _rocks: MultiMeshInstance3D


func _init() -> void:
	name = "Terrain"


func _ready() -> void:
	_configure_noise()


# =============================================================================
#  Public API
# =============================================================================
## Declares where buildings and roads are. Each pad needs at least a
## "center" (Vector2 XZ) and a "radius" (building footprint radius).
func set_features(new_pads: Array, new_roads: Array) -> void:
	pads = new_pads
	roads = new_roads


## Settles each pad at the average natural ground height under its footprint,
## so the least amount of ground has to be moved. Returns the heights in pad order.
func compute_pad_heights() -> PackedFloat32Array:
	_configure_noise()
	var heights := PackedFloat32Array()
	for pad: Dictionary in pads:
		var c: Vector2 = pad.center
		var r: float = pad.radius
		var total := natural_height(c.x, c.y)
		for i in 8:
			var a := TAU * i / 8.0
			total += natural_height(c.x + cos(a) * r, c.y + sin(a) * r)
		pad["height"] = total / 9.0
		heights.append(pad.height)
	return heights


## (Re)generates the mesh, collider and rocks from the current features.
func build() -> void:
	compute_pad_heights()
	_build_mesh()
	_scatter_rocks()


## Final ground height at a world XZ position (pads and roads included).
func get_height(x: float, z: float) -> float:
	return _shaped_height(x, z)[0]


# =============================================================================
#  Height field
# =============================================================================
func _configure_noise() -> void:
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = dune_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.45

	_ripple.seed = terrain_seed + 1
	_ripple.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ripple.frequency = 0.22

	_mesa.seed = terrain_seed + 2
	_mesa.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mesa.frequency = 0.03
	_mesa.fractal_octaves = 3

	_tint.seed = terrain_seed + 3
	_tint.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_tint.frequency = 0.06
	_tint.fractal_octaves = 3


## Untouched landscape: dunes + ripples + terraced crater rim.
func natural_height(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * dune_height
	# Ripples are stretched along one axis, like wind-blown sand.
	h += _ripple.get_noise_2d(x * 0.6, z * 1.6) * ripple_height
	h += _rim_height(x, z)
	return h


func _rim_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var t := smoothstep(rim_start, rim_end, r + _mesa.get_noise_2d(x, z) * 10.0)
	if t <= 0.0:
		return 0.0
	var raw := t * rim_height * (0.75 + 0.25 * _mesa.get_noise_2d(x * 0.5, z * 0.5))
	# Terraces: blend a stepped profile over the smooth one for layered cliffs.
	var stepped := floorf(raw / rim_terrace_step) * rim_terrace_step
	var edge := smoothstep(0.55, 1.0, fposmod(raw / rim_terrace_step, 1.0))
	stepped += edge * rim_terrace_step
	return lerpf(raw, stepped, 0.8)


## Returns [height, pad_weight, road_weight] after applying pads and roads.
func _shaped_height(x: float, z: float) -> Array:
	var h := natural_height(x, z)
	var p := Vector2(x, z)

	# Roads first: graded ramps between the two pads they connect.
	var road_w := 0.0
	for road: Dictionary in roads:
		var a: Dictionary = pads[road.from]
		var b: Dictionary = pads[road.to]
		var ac: Vector2 = a.center
		var bc: Vector2 = b.center
		var seg := bc - ac
		var t := clampf((p - ac).dot(seg) / seg.length_squared(), 0.0, 1.0)
		var d := p.distance_to(ac + seg * t)
		var w := 1.0 - smoothstep(road_half_width, road_half_width + road_blend, d)
		if w > 0.0:
			var grade := lerpf(float(a.get("height", 0.0)), float(b.get("height", 0.0)), smoothstep(0.0, 1.0, t))
			h = lerpf(h, grade, w * 0.9)
			road_w = maxf(road_w, w)

	# Pads last so they always win: perfectly flat under the building.
	var pad_w := 0.0
	for pad: Dictionary in pads:
		var inner: float = pad.radius + pad_margin
		var d := p.distance_to(pad.center)
		var w := 1.0 - smoothstep(inner, inner + pad_blend, d)
		if w > 0.0:
			h = lerpf(h, float(pad.get("height", 0.0)), w)
			pad_w = maxf(pad_w, w)
	return [h, pad_w, road_w]


# =============================================================================
#  Mesh + collision
# =============================================================================
func _build_mesh() -> void:
	var cells := int(ceil(size / resolution))
	var verts := cells + 1
	var half := size * 0.5

	# Sample the height field once and keep it for normals and colours.
	var heights := PackedFloat32Array()
	var pad_ws := PackedFloat32Array()
	var road_ws := PackedFloat32Array()
	heights.resize(verts * verts)
	pad_ws.resize(verts * verts)
	road_ws.resize(verts * verts)
	for iz in verts:
		for ix in verts:
			var x := -half + ix * resolution
			var z := -half + iz * resolution
			var s := _shaped_height(x, z)
			var i := iz * verts + ix
			heights[i] = s[0]
			pad_ws[i] = s[1]
			road_ws[i] = s[2]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in verts:
		for ix in verts:
			var i := iz * verts + ix
			var x := -half + ix * resolution
			var z := -half + iz * resolution
			var h := heights[i]
			# Slope from neighbouring samples (for cliff colouring).
			var hx := heights[iz * verts + mini(ix + 1, cells)] - heights[iz * verts + maxi(ix - 1, 0)]
			var hz := heights[mini(iz + 1, cells) * verts + ix] - heights[maxi(iz - 1, 0) * verts + ix]
			var slope := Vector2(hx, hz).length() / (2.0 * resolution)
			st.set_color(_vertex_color(x, z, h, slope, pad_ws[i], road_ws[i]))
			st.set_uv(Vector2(x, z) * 0.08)
			st.add_vertex(Vector3(x, h, z))

	for iz in cells:
		for ix in cells:
			var a := iz * verts + ix
			var b := a + 1
			var c := a + verts
			var d := c + 1
			# Alternate the diagonal to avoid visible zig-zag banding.
			if (ix + iz) % 2 == 0:
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(b); st.add_index(d); st.add_index(c)
			else:
				st.add_index(a); st.add_index(d); st.add_index(c)
				st.add_index(a); st.add_index(b); st.add_index(d)
	st.generate_normals()
	var mesh := st.commit()

	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Mesh"
		add_child(_mesh_instance)
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _make_material()

	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "Collision"
		add_child(_collision)
	_collision.shape = mesh.create_trimesh_shape()


func _vertex_color(x: float, z: float, h: float, slope: float, pad_w: float, road_w: float) -> Color:
	# Height ramp: shadowed low valleys → terracotta → sun-bleached crests.
	var t := clampf((h + dune_height) / (dune_height * 2.0), 0.0, 1.0)
	var col := color_low.lerp(color_mid, smoothstep(0.0, 0.55, t)).lerp(color_high, smoothstep(0.55, 1.0, t))
	# Large, soft patches of colour variation.
	col = col.lerp(color_low, clampf(_tint.get_noise_2d(x, z) * 0.6, 0.0, 0.35))
	# Cliffs: dark rock with lighter sediment bands.
	var cliff := smoothstep(0.45, 1.1, slope)
	if cliff > 0.0:
		var band := 0.5 + 0.5 * sin(h * 2.6 + _tint.get_noise_2d(x * 2.0, z * 2.0) * 2.0)
		col = col.lerp(color_cliff.lerp(color_strata, band * 0.6), cliff)
	# Compacted dust where the colony has levelled the ground.
	col = col.lerp(color_dust, maxf(pad_w * 0.35, road_w * 0.5))
	return col


func _make_material() -> StandardMaterial3D:
	# A fine grain texture multiplied over the vertex colours.
	var grain_noise := FastNoiseLite.new()
	grain_noise.seed = terrain_seed + 10
	grain_noise.frequency = 0.08
	grain_noise.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.82, 0.8, 0.78))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	var grain := NoiseTexture2D.new()
	grain.width = 512
	grain.height = 512
	grain.seamless = true
	grain.noise = grain_noise
	grain.color_ramp = ramp

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = grain
	mat.roughness = 0.97
	mat.metallic = 0.0
	mat.metallic_specular = 0.2
	return mat


# =============================================================================
#  Boulders
# =============================================================================
func _scatter_rocks() -> void:
	var rock := SphereMesh.new()  # few segments → faceted low-poly boulder
	rock.radius = 0.5
	rock.height = 0.8
	rock.radial_segments = 7
	rock.rings = 4
	var rock_mat := StandardMaterial3D.new()
	rock_mat.vertex_color_use_as_albedo = true
	rock_mat.roughness = 0.9
	rock.material = rock_mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = rock

	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var half := size * 0.5 - 2.0
	var attempts := 0
	while transforms.size() < rock_count and attempts < rock_count * 12:
		attempts += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var shaped := _shaped_height(x, z)
		# Keep pads and roads clear; boulders get bigger out on the crater rim.
		if shaped[1] > 0.01 or shaped[2] > 0.05:
			continue
		var r := Vector2(x, z).length()
		var big := smoothstep(rim_start - 10.0, rim_end, r)
		if r < rim_start - 8.0 and rng.randf() < 0.55:
			continue  # sparser inside the colony
		var s := rng.randf_range(0.25, 0.9) * lerpf(1.0, 3.5, big)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) \
			* Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)) \
			* Basis.from_scale(Vector3(s * rng.randf_range(0.8, 1.5), s * rng.randf_range(0.5, 0.9), s))
		transforms.append(Transform3D(basis, Vector3(x, float(shaped[0]) - s * 0.15, z)))
		colors.append(color_cliff.lerp(color_mid, rng.randf_range(0.0, 0.5)))

	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	if _rocks == null:
		_rocks = MultiMeshInstance3D.new()
		_rocks.name = "Rocks"
		add_child(_rocks)
	_rocks.multimesh = mm
