extends Node3D
# 3D 战场：按兵力比例生成两军，玩家以第三人称亲自上阵。
# 队伍 0 = 攻方（+Z 一侧），队伍 1 = 守方（-Z 一侧，攻城战时背靠城墙）。

const FighterScript = preload("res://scripts/Fighter.gd")
const HumanoidScript = preload("res://scripts/Humanoid.gd")
const MAX_AGENTS := 60

var b: Dictionary
var world: Node3D
var units := [[], []]
var initial := [0, 0]
var troops := [0, 0]
var had_gens := [false, false]
var gens_alive := [0, 0]
var names := ["", ""]
var colors := [Color.WHITE, Color.WHITE]
var scale_troops := 1.0
var z_min := -68.0
var player = null
var pteam := 0
var cam: Camera3D
var cam_target := Vector3.ZERO
var yaw := 0.0
var pitch := 0.32
var cam_dist := 7.0
var over := false
var winner := -1
var numeric := false
var retreated := false
var kills := 0
var gen_kills := 0
var player_down := false
var squad_order := 0
var squad_n := 0
var check_t := 0.0
var end_t := -1.0
var msg_t := 0.0
var result := {}
var arrows: Array = []
var weapon_lbl: Label
var wslots: Array = []          # 玩家带上阵的兵器（行囊里的主手、副手）
var loot: Array = []            # 本场缴获的物品
var gens_down: Array = []       # 被玩家亲手击破的敌将
var squad_res := {}             # 上阵的亲兵：名册序号 -> {alive, kills}
# 攻城战：城墙高度、云梯位置。区域 zone：0 城外 1 城头 2 城内
const WALL_Y := 10.0
const LADDER_X := [-48.0, -24.0, 24.0, 48.0]
const GATE_HP := 700.0
var siege := false
var palace := false
# 地势：若干土丘 + 缓坡起伏；城墙附近抹平
var hills: Array = []           # [x, z, 半径, 高]
var relief := 0.0
var ph := [0.0, 0.0, 0.0]
# 护城河：只能从桥上过
const MOAT_Z0 := -43.6
const MOAT_Z1 := -39.6
var moat := false
var bridges: Array = []         # [x 起, x 止]
var last_stand := false      # 守方只剩这一座城：背水一战，死战不退
var x_lim := 68.0
var z_max := 68.0
var bio := {}
var looks := ["", ""]         # 两军的装束（文化:年代）
var arch := {}                # 城郭样式
var links: Array = []           # 云梯与马道：{kind, a, b, t, za, zb, up}
var gate_hp := GATE_HP
var gate_open := false
var gate_node: Node3D
var clock := 0.0
var last_hit_t := 0.0
var obj_lbl: Label
var horse_prop: Node3D = null   # 玩家下马后留在原地的战马
var horse_zone := 0
var defense := "sortie"         # 玩家守城时的选择：sortie 出城迎击 / wall 城头迎击
var warn_t := 0.0
const HORSE_COATS := ["#6b4a2b", "#5a3a22", "#7a5a3c", "#3a2a20", "#8a6a48", "#4a4038"]

var bars := [null, null]
var bar_lbls := [null, null]
var hp_bar: ProgressBar
var hp_lbl: Label
var kills_lbl: Label
var order_lbl: Label
var msg_lbl: Label
var result_panel: Control
var pause_panel: Control
var hud: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.pending_battle == null:
		Game.pending_battle = Game.debug_battle()
	b = Game.pending_battle
	pteam = int(b.player_side)
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	names = [Game.fname(b.att_f), Game.fname(b.def_f)]
	colors = [Game.fcolor(b.att_f), Game.fcolor(b.def_f)]
	if b.type == "bandit":
		names[1] = Lang.t("官军") if b.def_f != "" else Lang.t("义勇")
		colors[0] = Color("#4a3a2a")
		if b.def_f == "":
			colors[1] = Color("#8a8a8a")
	troops = [int(b.att_troops), int(b.def_troops)]
	siege = b.type == "siege"
	palace = b.type == "palace"
	add_to_group("battle")
	last_stand = (siege or palace) and Game.faction_cities(str(b.def_f)).size() <= 1
	Sfx.music("battle")
	Sfx.play("horn")
	if siege and pteam == 1:
		defense = str(b.get("defense", "sortie"))
	looks = [Game.look_of(str(b.att_f), str(b.from) if str(b.from) != "" else str(b.to)), Game.look_of(str(b.def_f), str(b.to))]
	bio = _biome()
	arch = _arch()
	for k in ["wall", "house", "roof"]:
		if arch.has(k):
			var ac := Color(str(arch[k]))
			if ac.get_luminance() > 0.6:      # 浅色石墙在雪地、大漠的强光下会一片惨白，压暗些
				ac = ac.darkened(0.22)
			bio[k] = "#" + ac.to_html(false)
	if str(bio.name).begins_with("西凉大漠") and Game.cities.has(str(b.to)):
		var blon := float(Game.cities[b.to].lon)
		var blat := float(Game.cities[b.to].lat)
		if blon < 97.0:
			bio["name"] = str(bio.name).replace("西凉大漠", "大漠戈壁")
		elif blat >= 41.0:
			bio["name"] = str(bio.name).replace("西凉大漠", "漠北戈壁")
	_build_env()
	_spawn_all()
	if palace:      # 外城一战的伤带进宫城，不重新回满
		var carry: Dictionary = b.get("gen_hp", {})
		for team in 2:
			for u in units[team]:
				if u.is_general and carry.has(u.gname):
					u.hp = u.max_hp * clampf(float(carry[u.gname]), 0.15, 1.0)
		if is_instance_valid(player) and b.has("player_hp"):
			player.hp = player.max_hp * clampf(float(b.player_hp), 0.1, 1.0)
	if siege:
		_garrison()
	_build_hud()
	yaw = 0.0 if pteam == 0 else PI
	cam_target = player.position
	_update_cam(1.0)
	if not Game.autopilot and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ───────────── 场景 ─────────────

func _mesh(mesh: Mesh, col: Color, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = HumanoidScript.mat(col)
	mi.position = pos
	(parent if parent != null else world).add_child(mi)
	return mi


# 按城池所在的地域与时令决定战场风貌
func _biome() -> Dictionary:
	var d := {"name": "中原", "g0": "#5d7a3a", "g1": "#8c9450", "t0": "#2f5a2c", "t1": "#4f7a34", "trees": 140,
		"round": false, "fog": "#c9d6dc", "fogd": 0.0035, "sky": "#4f7fb8", "rocks": 30, "mount": "#5f7458",
		"mh": 1.0, "wall": "#8d8576", "house": "#b9a98a", "roof": "#4a443c", "water": false, "snow": false}
	var ci = Game.cities.get(str(b.to), null)
	if ci == null:
		return d
	var lon := float(ci.lon)
	var lat := float(ci.lat)
	# 葱岭以西、天竺、雪域：另有风貌
	var west := ""
	if lon < 97.0:
		if lat < 22.0 and lon > 72.8:
			west = "jungle"
		elif lat < 27.3 and lon > 73.5:
			west = "plain"
		elif (lat < 33.5 and lon >= 78.0) or (lon > 70.0 and lon < 78.0 and lat > 33.0 and lat < 35.5):
			west = "plateau"
		elif lon < 30.0 and lat >= 43.0:
			west = "forest"
		elif lon < 50.0 and lat >= 36.5:
			west = "steppe"
		elif lon < 90.0 or lat > 33.5:
			west = "desert"
	if west == "plateau":
		d.merge({"name": "雪域高原", "g0": "#7f8658", "g1": "#a39f72", "t0": "#3a5234", "t1": "#55683f", "trees": 30,
			"fog": "#d6dee6", "fogd": 0.0045, "sky": "#4c7cc0", "rocks": 90, "mount": "#cfd6dc", "mh": 2.3,
			"wall": "#b9a88c", "house": "#d8cdb8", "roof": "#6a3a2c"}, true)
	elif west == "jungle":
		d.merge({"name": "岭南丛林", "g0": "#2f6a30", "g1": "#5f8f3a", "t0": "#1f5a26", "t1": "#3f8a34", "trees": 300,
			"round": true, "fog": "#bcd8c8", "fogd": 0.007, "sky": "#4f8ab0", "mount": "#3f6a48",
			"wall": "#8a6a58", "house": "#a88a68", "roof": "#6a4a34", "water": true}, true)
		d.name = "天竺丛林"
	elif west == "plain":
		d.merge({"name": "江南水乡", "g0": "#5a8236", "g1": "#93a04a", "t0": "#2f6a30", "t1": "#5f9440", "trees": 150,
			"round": true, "fog": "#dcdcc8", "fogd": 0.005, "sky": "#5a8fc0", "mount": "#5f7458",
			"wall": "#a8785c", "house": "#d8c8a8", "roof": "#7a4a34", "water": true}, true)
		d.name = "恒河平原"
	elif west == "steppe":
		d.merge({"name": "北地草原", "g0": "#7d8848", "g1": "#a8a562", "t0": "#243f2c", "t1": "#35553a", "trees": 70,
			"fog": "#d3dadd", "fogd": 0.004, "sky": "#5a82b4", "rocks": 45, "mount": "#6f7a6a",
			"wall": "#a89a84", "house": "#cfc4ae", "roof": "#8a4a34"}, true)
		d.name = "地中海岸" if lon < 30.0 else "西陲高地"
	elif west == "forest":
		d.merge({"name": "欧陆林野", "g0": "#4f7438", "g1": "#7f9448", "t0": "#234f2a", "t1": "#3f7234", "trees": 210,
			"fog": "#c6d4d8", "fogd": 0.0045, "rocks": 40, "mount": "#566e5a"}, true)
	elif west == "desert" or (lon < 108.0 and lat > 33.5):
		d.merge({"name": "西凉大漠", "g0": "#9c8250", "g1": "#bda66e", "t0": "#6a7a3a", "t1": "#8a8a4a", "trees": 22,
			"fog": "#e3d6b4", "fogd": 0.0055, "sky": "#7f9ab8", "rocks": 80, "mount": "#a89064", "mh": 1.2,
			"wall": "#b89a68", "house": "#c2a878", "roof": "#7a6240"}, true)
	elif lat >= 38.5:
		d.merge({"name": "北地草原", "g0": "#7d8848", "g1": "#a8a562", "t0": "#243f2c", "t1": "#35553a", "trees": 70,
			"fog": "#d3dadd", "fogd": 0.004, "sky": "#5a82b4", "rocks": 45, "mount": "#6f7a6a"}, true)
	elif lon < 106.5:
		d.merge({"name": "巴蜀山地", "g0": "#3f6a34", "g1": "#6f8a45", "t0": "#234f2a", "t1": "#3f7234", "trees": 230,
			"fog": "#b8cfc8", "fogd": 0.006, "sky": "#5f86a8", "rocks": 60, "mount": "#3f5f45", "mh": 1.9,
			"wall": "#7f7c72", "house": "#a89878", "roof": "#3a3f3c"}, true)
	elif lat < 26.0:
		d.merge({"name": "岭南丛林", "g0": "#2f6a30", "g1": "#5f8f3a", "t0": "#1f5a26", "t1": "#3f8a34", "trees": 300,
			"round": true, "fog": "#bcd8c8", "fogd": 0.007, "sky": "#4f8ab0", "mount": "#3f6a48",
			"wall": "#80786a", "house": "#9a8a68", "roof": "#5a4a34", "water": true}, true)
	elif lat < 31.6:
		d.merge({"name": "江南水乡", "g0": "#4a7f3a", "g1": "#7fa04a", "t0": "#2f6a30", "t1": "#5f9440", "trees": 200,
			"round": true, "fog": "#cfe0e0", "fogd": 0.0055, "sky": "#5a8fc0", "mount": "#4f7458",
			"wall": "#7c8088", "house": "#e8e4d8", "roof": "#33383e", "water": true}, true)
	if [12, 1, 2].has(Game.month) and lat > 33.0:
		d.merge({"name": str(d.name) + " · 雪", "g0": "#8b98a3", "g1": "#aeb9c2", "fog": "#cfd7de", "fogd": 0.0065,
			"sky": "#9fb2c4", "mount": "#c9d2d8", "snow": true}, true)
	return d


func _build_env() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(str(bio.sky))
	sm.sky_horizon_color = Color(str(bio.fog))
	sm.ground_horizon_color = Color(str(bio.fog))
	sm.ground_bottom_color = Color(str(bio.g0)).darkened(0.2)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(str(bio.fog))
	env.fog_density = float(bio.fogd)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 68
	cam.far = 900
	add_child(cam)
	cam.make_current()

	if palace:
		_build_palace()
		return
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	ground.mesh = pm
	ground.position.y = -0.08      # 远处的平地；近处由起伏的地形网格盖住
	var gm := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.seamless = true
	var grad := Gradient.new()
	grad.set_color(0, Color(str(bio.g0)))
	grad.set_color(1, Color(str(bio.g1)))
	nt.color_ramp = grad
	gm.albedo_texture = nt
	gm.uv1_scale = Vector3(30, 30, 1)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(b.to))
	_make_terrain(rng, gm)
	var snow: bool = bio.snow
	# 远山
	var mcol := Color(str(bio.mount))
	for i in 26:
		var a := TAU * i / 26.0 + rng.randf() * 0.2
		var r := rng.randf_range(260, 380)
		var h := rng.randf_range(50, 130) * float(bio.mh)
		_mesh(HumanoidScript.cyl(0.0, h * 1.4, h), mcol.lerp(Color("#8a9aa0"), rng.randf() * 0.5), Vector3(cos(a) * r, h / 2 - 2, sin(a) * r)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # 远山不投影，否则高山会把整片战场罩进阴影
	# 树：北方尖顶松，南方圆冠阔叶
	var trunk := HumanoidScript.cyl(0.18, 0.25, 2.4)
	var n_tree := int(bio.trees) + (80 if b.type == "bandit" else 0)
	for i in n_tree:
		var p := Vector3(rng.randf_range(-170, 170), 0, rng.randf_range(-170, 170))
		var inner := 26.0 if b.type == "bandit" else 64.0
		if absf(p.x) < inner and absf(p.z) < 75:
			continue
		if siege and p.z < -40 and absf(p.x) < 135:
			continue
		p.y = ground_y(p.x, p.z)
		var sc := rng.randf_range(0.8, 1.6)
		_mesh(trunk, Color("#5a4028"), p + Vector3(0, 1.2 * sc, 0)).scale = Vector3.ONE * sc
		var tc := Color(str(bio.t0)).lerp(Color(str(bio.t1)), rng.randf())
		if snow:
			tc = tc.lerp(Color.WHITE, 0.55)
		var crown: MeshInstance3D
		if bio.round:
			crown = _mesh(HumanoidScript.ball(1.9), tc, p + Vector3(0, 3.6 * sc, 0))
			crown.scale = Vector3(sc, sc * 0.85, sc)
		else:
			crown = _mesh(HumanoidScript.cyl(0.0, 1.7, 4.2), tc, p + Vector3(0, 4.2 * sc, 0))
			crown.scale = Vector3.ONE * sc
	# 石块
	for i in int(bio.rocks):
		var p2 := Vector3(rng.randf_range(-80, 80), 0.2, rng.randf_range(-80, 80))
		if siege and p2.z < -36:
			continue
		p2.y += ground_y(p2.x, p2.z)
		var rock := _mesh(HumanoidScript.ball(0.6), Color("#77736a") if not snow else Color("#b8bcc0"), p2)
		rock.scale = Vector3(rng.randf_range(0.6, 1.8), rng.randf_range(0.4, 0.9), rng.randf_range(0.6, 1.8))
	# 水塘
	if bio.water:
		for i in 7:
			var wp := Vector3(rng.randf_range(72, 150) * (1.0 if i % 2 == 0 else -1.0), 0.04, rng.randf_range(-30, 120))
			var pond := _mesh(HumanoidScript.cyl(1.0, 1.0, 0.04, 20), Color("#4f86b8"), wp)
			pond.scale = Vector3(rng.randf_range(8, 18), 1, rng.randf_range(6, 12))
	if siege:
		_build_wall()
		_build_city(rng)
		for i in 7:   # 攻方营帐
			var tp := Vector3(-36 + i * 12, 1.6, 58 + (i % 2) * 5)
			tp.y += ground_y(tp.x, tp.z)
			_mesh(HumanoidScript.cyl(0.0, 2.6, 3.2), Color("#d9cfb4"), tp)
	_banner(Vector3(-16, 0, 44), colors[0])
	_banner(Vector3(16, 0, 44), colors[0])
	if not palace:
		var sp := Vector3(0, 0, 50)
		sp.y = ground_y(sp.x, sp.z)
		_standard(sp, str(b.att_f), 9.0)      # 攻方本阵帅旗
	if not siege:
		_banner(Vector3(-16, 0, -40), colors[1])
		_banner(Vector3(16, 0, -40), colors[1])


# 生成地势并铺一张跟着起伏的地面网格
func _make_terrain(rng: RandomNumberGenerator, gm: StandardMaterial3D) -> void:
	var spec: Array = {"西凉大漠": [0.9, 4, 2.0, 4.0], "大漠戈壁": [0.9, 4, 2.0, 4.0], "漠北戈壁": [0.7, 3, 2.0, 4.0], "北地草原": [0.5, 3, 2.0, 4.0], "巴蜀山地": [0.8, 5, 4.0, 8.0],
		"岭南丛林": [0.6, 4, 3.0, 5.0], "江南水乡": [0.3, 2, 2.0, 3.0], "雪域高原": [0.9, 5, 4.0, 8.0],
		"天竺丛林": [0.6, 4, 3.0, 5.0], "恒河平原": [0.3, 2, 2.0, 3.0], "西陲高地": [0.6, 3, 2.0, 5.0], "地中海岸": [0.6, 3, 2.0, 5.0], "欧陆林野": [0.5, 3, 2.0, 4.0]}.get(str(bio.name).split(" ")[0], [0.35, 2, 2.0, 3.0])
	relief = float(spec[0])
	ph = [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	for i in int(spec[1]):
		var side := -1.0 if i % 2 == 0 else 1.0
		hills.append([side * rng.randf_range(16.0, 62.0), rng.randf_range(-22.0, 60.0), rng.randf_range(18.0, 34.0), rng.randf_range(float(spec[2]), float(spec[3]))])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 3.0
	var x0 := -123.0
	var z0 := -63.0
	for iz in 62:
		for ix in 82:
			var xa := x0 + ix * step
			var za := z0 + iz * step
			for o in [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]]:
				var x: float = xa + o[0] * step
				var z: float = za + o[1] * step
				var y := ground_y(x, z)
				st.set_normal(Vector3(ground_y(x - 1.0, z) - ground_y(x + 1.0, z), 2.0, ground_y(x, z - 1.0) - ground_y(x, z + 1.0)).normalized())
				st.set_uv(Vector2(x, z) / 30.0)
				st.add_vertex(Vector3(x, y, z))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m2: StandardMaterial3D = gm.duplicate()
	m2.uv1_scale = Vector3.ONE
	m2.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)


# 某处的地面高度（宫殿、城内、城墙根都是平的）
func ground_y(x: float, z: float) -> float:
	if palace or relief == 0.0:
		return 0.0
	var y := relief * ((sin(x * 0.13 + ph[0]) * cos(z * 0.11 + ph[1]) + 1.0) * 0.5 + (sin(x * 0.31 + z * 0.27 + ph[2]) + 1.0) * 0.2)
	for hl in hills:
		var d2: float = ((x - hl[0]) * (x - hl[0]) + (z - hl[1]) * (z - hl[1])) / (hl[2] * hl[2])
		if d2 < 3.0:
			y += hl[3] * exp(-d2 * 2.2)
	if siege:
		y *= smoothstep(-36.0, -20.0, z)
	return y * (1.0 - smoothstep(92.0, 116.0, absf(x))) * (1.0 - smoothstep(92.0, 116.0, z))


func _banner(pos: Vector3, col: Color) -> void:
	pos.y += ground_y(pos.x, pos.z)
	_mesh(HumanoidScript.cyl(0.05, 0.05, 7.0), Color("#3a2a1a"), pos + Vector3(0, 3.5, 0))
	_mesh(HumanoidScript.box(Vector3(1.3, 2.6, 0.05)), col, pos + Vector3(0.7, 5.6, 0))


# 帅旗：高杆大旗，旗面是该势力的名号或徽记
func _standard(pos: Vector3, f: String, h := 11.0) -> void:
	var em: Dictionary = Game.emblem(f)
	if b.type == "bandit" and not Game.factions.has(f):
		return
	var bg: Color = em.bg
	var fg: Color = em.fg
	var fw := 3.0
	var fh := 4.2
	_mesh(HumanoidScript.cyl(0.09, 0.11, h), Color("#3a2a1a"), pos + Vector3(0, h / 2, 0))
	_mesh(HumanoidScript.ball(0.2), Color("#d9b04a"), pos + Vector3(0, h + 0.1, 0))
	var c := pos + Vector3(fw / 2 + 0.1, h - fh / 2 - 0.2, 0)
	_mesh(HumanoidScript.box(Vector3(fw, fh, 0.06)), bg, c)
	for sy in [-1.0, 1.0]:      # 上下镶边
		_mesh(HumanoidScript.box(Vector3(fw, 0.16, 0.08)), fg.lerp(bg, 0.25), c + Vector3(0, sy * (fh / 2 - 0.08), 0))
	for k in 3:                 # 旗脚飘带
		_mesh(HumanoidScript.box(Vector3(0.5, 0.9, 0.05)), bg.darkened(0.15), c + Vector3(-fw / 2 + 0.55 + k * 0.95, -fh / 2 - 0.4, 0))
	var mid := c + Vector3(0, 0.1, 0)
	for sz in [-1.0, 1.0]:
		var at := mid + Vector3(0, 0, sz * 0.05)
		match str(em.shape):
			"ring":
				var tm := TorusMesh.new()
				tm.inner_radius = 1.0
				tm.outer_radius = 1.18
				tm.rings = 20
				tm.ring_segments = 6
				_mesh(tm, fg, at).rotation.x = PI / 2
			"disc":
				_mesh(HumanoidScript.cyl(1.0, 1.0, 0.03, 24), fg if str(em.text) == "" else Color("#ffd24a"), at).rotation.x = PI / 2
			"star":
				for k in 4:
					_mesh(HumanoidScript.box(Vector3(2.3, 0.3, 0.03)), fg, at).rotation.z = k * PI / 4
				_mesh(HumanoidScript.cyl(0.45, 0.45, 0.05, 16), fg, at).rotation.x = PI / 2
			"wheel":
				var wm := TorusMesh.new()
				wm.inner_radius = 0.9
				wm.outer_radius = 1.1
				wm.rings = 24
				wm.ring_segments = 6
				_mesh(wm, fg, at).rotation.x = PI / 2
				for k in 6:
					_mesh(HumanoidScript.box(Vector3(2.0, 0.09, 0.03)), fg, at).rotation.z = k * PI / 6
				_mesh(HumanoidScript.cyl(0.22, 0.22, 0.05, 12), fg, at).rotation.x = PI / 2
		if str(em.text) != "":
			var lb := Label3D.new()
			lb.text = Lang.fix(str(em.text))
			lb.font = Game.font
			lb.font_size = 220 if str(em.text).length() <= 1 else (120 if str(em.text).length() == 2 else 72)
			lb.pixel_size = 0.011
			lb.modulate = fg
			lb.outline_size = 0
			lb.double_sided = false
			lb.shaded = false
			lb.position = mid + Vector3(0, 0, sz * 0.09)
			lb.rotation.y = 0.0 if sz > 0 else PI
			world.add_child(lb)


# 城郭样式：跟着城池所在的文化区和年代走
func _arch() -> Dictionary:
	var cul: String = Game.culture_of(str(b.to))
	var era: String = Game.scenario
	var late := era == "suitang" or era == "wudai"
	var a := {"cul": cul, "merlon": "square", "tower": "pavilion", "homes": "gable", "hall": "chinese",
		"pillar": "#7a3524", "eave": "#4a443c", "dome": "#3a9a9a", "pal": {}}
	match cul:
		"han", "korea":
			if era == "zhanguo":      # 夯土城、茅茨土阶
				a.merge({"wall": "#b59a6a", "roof": "#7a6a44", "house": "#c2a878", "pillar": "#5a3a24", "eave": "#4a3a2a", "homes": "thatch"}, true)
		"wa":
			a.merge({"wall": "#8a6a48", "house": "#a88a62", "roof": "#7a6a44", "merlon": "spike", "pillar": "#5a3a24", "eave": "#5a4a34",
				"homes": "gable" if era == "wudai" else "thatch", "pal": {"pillar": "#6b4a2b", "wall": "#d8cdb4", "floor": "#7a6240"}}, true)
			if era == "wudai":
				a["roof"] = "#3a3a3c"
		"steppe":
			a.merge({"wall": "#8a7250", "merlon": "spike", "homes": "yurt", "hall": "yurt", "pillar": "#5a3a24", "eave": "#6a5a44",
				"house": "#e6dcc4", "roof": "#c8b890", "pal": {"pillar": "#6b4a2b", "wall": "#d8cdb4", "floor": "#7a6a4a"}}, true)
		"xiyu":
			a.merge({"wall": "#c2a070", "house": "#cdb080", "roof": "#b89a68", "tower": "block", "homes": "flat", "merlon": "step",
				"hall": "dome" if era == "wudai" else "fort", "pal": {"pillar": "#a8703a", "wall": "#c2a070", "floor": "#8a7250"}}, true)
		"tibet":
			a.merge({"wall": "#e6e0d2", "house": "#ece6d8", "roof": "#6a2a22", "tower": "block", "homes": "flat", "hall": "fort",
				"pal": {"pillar": "#9a2418", "wall": "#e6e0d2", "floor": "#6a4a3a"}}, true)
		"india":
			a.merge({"wall": "#b4654a", "house": "#d8c4a0", "roof": "#a85a3a", "tower": "block", "homes": "flat", "hall": "shikhara",
				"merlon": "round", "dome": "#d8c4a0", "pal": {"pillar": "#b4654a", "wall": "#a85a44", "floor": "#6a4a3a"}}, true)
		"sea":
			a.merge({"wall": "#8a5a44", "house": "#a88a62", "roof": "#8a7a4a", "tower": "pavilion", "homes": "stilt", "hall": "shikhara",
				"merlon": "spike", "pillar": "#5a3a24", "eave": "#6a5a34", "pal": {"pillar": "#6b4a2b", "wall": "#8a5a44", "floor": "#5a4030"}}, true)
		"persia":
			a.merge({"wall": "#c8a878", "house": "#d4bc90", "roof": "#c2a878", "tower": "block", "merlon": "step",
				"homes": "dome" if era == "wudai" else "flat", "hall": "dome" if late else "column",
				"pal": {"pillar": "#d8c8a0", "wall": "#3f8a8a" if late else "#c8a878", "floor": "#8a7a5c"}}, true)
		"arab":
			a.merge({"wall": "#d8c8a0", "house": "#e6dcc0", "roof": "#d0c0a0", "tower": "block", "merlon": "step",
				"homes": "dome" if era == "wudai" else "flat", "hall": "dome" if era == "wudai" else "fort", "dome": "#3f8f5a",
				"pal": {"pillar": "#e6dcc0", "wall": "#d8c8a0", "floor": "#8a7a5c"}}, true)
		"north":
			if late:      # 石基木堡、茅顶长屋
				a.merge({"wall": "#8f8a80", "house": "#a89a80", "roof": "#7a6a44", "tower": "block", "homes": "thatch", "hall": "longhouse",
					"pillar": "#5a3a24", "eave": "#5a4a34", "pal": {"pillar": "#6b4a2b", "wall": "#8a7a62", "floor": "#6a5a44"}}, true)
			else:         # 土垒木栅
				a.merge({"wall": "#7a6448", "house": "#9a8662", "roof": "#8a7a4a", "merlon": "spike", "homes": "thatch", "hall": "longhouse",
					"pillar": "#5a3a24", "eave": "#6a5a34", "pal": {"pillar": "#6b4a2b", "wall": "#8a7250", "floor": "#6a5a44"}}, true)
		"rome":
			a.merge({"wall": "#d8d0bc", "house": "#e0d4bc", "roof": "#b4553a", "tower": "block", "homes": "gable",
				"hall": "dome" if late else "column", "dome": "#b4553a" if late else "#d8d0bc",
				"pal": {"pillar": "#e6e0d0", "wall": "#cfc6b0", "floor": "#8a8478"}}, true)
	return a


func _build_wall() -> void:
	var stone := Color(str(bio.wall))
	var dark := Color(str(arch.eave))
	var pillar := Color(str(arch.pillar))
	# 城墙分左右两段，中间留出门洞
	for sx in [-1.0, 1.0]:
		_mesh(HumanoidScript.box(Vector3(126, WALL_Y, 6)), stone, Vector3(sx * 67.0, WALL_Y / 2, -51))
	_mesh(HumanoidScript.box(Vector3(8, WALL_Y - 6.0, 6)), stone, Vector3(0, 6.0 + (WALL_Y - 6.0) / 2, -51))
	for i in 65:
		var mp := Vector3(-128 + i * 4.0, WALL_Y + 0.65, -48.4)
		_mesh(HumanoidScript.box(Vector3(2.0, 1.3, 0.8)), stone.lightened(0.08), mp)
		match str(arch.merlon):
			"step":      # 阶梯形雉堞
				_mesh(HumanoidScript.box(Vector3(1.0, 0.6, 0.8)), stone.lightened(0.08), mp + Vector3(0, 0.95, 0))
			"round":     # 圆顶雉堞
				_mesh(HumanoidScript.cyl(1.0, 1.0, 0.8, 12), stone.lightened(0.08), mp + Vector3(0, 0.65, 0)).rotation.x = PI / 2
			"spike":     # 木栅尖桩
				for dx in [-0.6, 0.6]:
					_mesh(HumanoidScript.cyl(0.0, 0.3, 1.4, 5), Color("#5a4028"), mp + Vector3(dx, 1.35, 0))
	_mesh(HumanoidScript.box(Vector3(260, 0.9, 0.5)), stone.darkened(0.1), Vector3(0, WALL_Y + 0.45, -53.75))   # 内侧女墙
	gate_node = Node3D.new()
	world.add_child(gate_node)
	for sx in [-1.0, 1.0]:
		_mesh(HumanoidScript.box(Vector3(3.9, 6.0, 0.5)), Color("#3a2416"), Vector3(sx * 2.0, 3.0, -48.2), gate_node)
		for k in 3:
			_mesh(HumanoidScript.box(Vector3(3.9, 0.25, 0.56)), Color("#2a2a2e"), Vector3(sx * 2.0, 1.2 + k * 1.8, -48.2), gate_node)
	# 城楼架在柱子上，不挡城头走道
	for x in [0.0, -60.0, 60.0, -120.0, 120.0]:
		var w := 22.0 if x == 0.0 else 11.0
		var blk: bool = str(arch.tower) == "block"
		for px in [-w / 2 + 0.6, w / 2 - 0.6]:
			for pz in [-48.6, -53.4]:
				_mesh(HumanoidScript.cyl(0.5, 0.55, 4.0, 10) if blk else HumanoidScript.cyl(0.3, 0.3, 4.0), stone.darkened(0.08) if blk else pillar, Vector3(x + px, WALL_Y + 2.0, pz))
		if blk:      # 石砌平顶敌楼，顶上再起一圈雉堞
			_mesh(HumanoidScript.box(Vector3(w + 2, 1.0, 8)), stone, Vector3(x, WALL_Y + 4.5, -51))
			var n_m := int((w + 2) / 2.4)
			for k in n_m:
				var cx: float = float(x) - (w + 2) / 2 + 1.0 + k * (w / maxf(1.0, n_m - 1.0))
				for cz in [-47.3, -54.7]:
					_mesh(HumanoidScript.box(Vector3(1.2, 1.0, 0.6)), stone.lightened(0.08), Vector3(cx, WALL_Y + 5.5, cz))
			if str(arch.hall) == "dome" and x == 0.0:
				var dm := _mesh(HumanoidScript.ball(1.0), Color(str(arch.dome)), Vector3(x, WALL_Y + 5.0, -51))
				dm.scale = Vector3(4.6, 3.6, 3.2)
		else:
			_mesh(HumanoidScript.box(Vector3(w + 4, 0.6, 11)), dark, Vector3(x, WALL_Y + 4.3, -51))
			_mesh(HumanoidScript.box(Vector3(w - 4, 2.4, 6)), pillar, Vector3(x, WALL_Y + 5.8, -51))
			_mesh(HumanoidScript.box(Vector3(w, 0.6, 9)), dark, Vector3(x, WALL_Y + 7.3, -51))
		if x == 0.0:      # 城门楼两侧：守方帅旗
			_standard(Vector3(-w / 2 - 2.5, WALL_Y, -50), str(b.def_f))
			_standard(Vector3(w / 2 + 2.5, WALL_Y, -50), str(b.def_f))
		else:
			_banner(Vector3(x + w / 2 + 1.5, WALL_Y, -50), colors[1])
	# 护城河：中等以上的城才有，大漠里没有。城门前是石桥，各云梯位有攻方搭的壕桥
	moat = int(Game.cities[b.to].size) >= 2 and not str(bio.name).contains("漠")
	if moat:
		var water := Color("#3f7fae") if not bio.snow else Color("#9fc4d8")
		var mz := (MOAT_Z0 + MOAT_Z1) / 2.0
		var mw := MOAT_Z1 - MOAT_Z0
		_mesh(HumanoidScript.box(Vector3(260, 0.06, mw)), water, Vector3(0, 0.02, mz)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for ez in [MOAT_Z0 - 0.2, MOAT_Z1 + 0.2]:
			_mesh(HumanoidScript.box(Vector3(260, 0.3, 0.4)), stone.darkened(0.15), Vector3(0, 0.1, ez))
		bridges.append([-3.8, 3.8])
		_mesh(HumanoidScript.box(Vector3(7.6, 0.3, mw + 1.4)), stone.lightened(0.05), Vector3(0, 0.12, mz))
		for sx in [-1.0, 1.0]:
			_mesh(HumanoidScript.box(Vector3(0.35, 0.8, mw + 1.4)), stone, Vector3(sx * 3.8, 0.55, mz))
		for x in LADDER_X:
			bridges.append([x - 1.6, x + 1.6])
			_mesh(HumanoidScript.box(Vector3(3.2, 0.16, mw + 1.0)), Color("#6b4a2b"), Vector3(x, 0.1, mz))
			for k in 5:
				_mesh(HumanoidScript.box(Vector3(3.3, 0.05, 0.12)), Color("#4a3322"), Vector3(x, 0.2, MOAT_Z0 - 0.2 + k * (mw + 0.4) / 4.0))
	# 云梯（攻方架起后才出现）与内侧马道
	for x in LADDER_X:
		links.append({"kind": "ladder", "a": Vector3(x, 0, -45.2), "b": Vector3(x, WALL_Y, -49.7), "t": 2.6, "za": 0, "zb": 1, "up": false})
		var top := Vector3(x, WALL_Y, -52.9)
		var bot := Vector3(x, 0, -58.5)
		links.append({"kind": "stairs", "a": top, "b": bot, "t": 1.8, "za": 1, "zb": 2, "up": true})
		var ramp := _mesh(HumanoidScript.box(Vector3(2.4, 0.3, top.distance_to(bot) + 1.0)), stone.darkened(0.12), (top + bot) / 2 + Vector3(0, -0.25, -0.3))
		ramp.look_at(bot + Vector3(0, -0.25, -0.3))
		_mesh(HumanoidScript.box(Vector3(2.4, WALL_Y * 0.5, 2.6)), stone.darkened(0.12), Vector3(x, WALL_Y * 0.25, -55.2))


# 国都的殿堂按城池规模分三等：小城是木构的府衙正堂，中城是王府，大城是重檐列柱的皇宫大殿
const HALLS := {
	1: {"name": "府衙", "w": 11.0, "back": -16.0, "front": 20.0, "h": 7.0, "rows": [6.5], "gap": 7.0,
		"pillar": "#6b4a2b", "wall": "#8a7a5c", "floor": "#6a5a44", "carpet": false, "dais": 0.3, "grand": false},
	2: {"name": "王府", "w": 14.5, "back": -22.0, "front": 26.0, "h": 9.5, "rows": [8.5], "gap": 8.0,
		"pillar": "#8a2a1e", "wall": "#8a3a2a", "floor": "#5a3a2a", "carpet": true, "dais": 0.6, "grand": false},
	3: {"name": "皇宫", "w": 21.0, "back": -30.0, "front": 36.0, "h": 13.0, "rows": [8.0, 15.5], "gap": 8.0,
		"pillar": "#9a2418", "wall": "#8a2a1e", "floor": "#4a2e22", "carpet": true, "dais": 1.0, "grand": true},
}
var hall := {}


func _build_palace() -> void:
	hall = HALLS[clampi(int(Game.cities[b.to].size), 1, 3)].duplicate()
	hall.merge(arch.get("pal", {}), true)
	hall["name"] = Game.hall_name(str(b.to))
	var w: float = hall.w
	var back: float = hall.back
	var front: float = hall.front
	var h: float = hall.h
	var grand: bool = hall.grand
	x_lim = w - 1.0
	z_min = back + 1.0
	z_max = front - 2.0
	var red := Color(str(hall.pillar))
	var wallc := Color(str(hall.wall))
	var gold := Color("#d9b04a")
	var stone := Color("#6f685c")
	var mid := (back + front) / 2.0
	var ln := front - back + 16.0
	var floor := _mesh(HumanoidScript.box(Vector3(w * 2 + 20, 0.2, ln + 20)), Color(str(hall.floor)), Vector3(0, -0.1, mid))
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if hall.carpet:
		_mesh(HumanoidScript.box(Vector3(6 if grand else 4, 0.03, front - back)), Color("#a8321e"), Vector3(0, 0.02, mid)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if grand:
			for sx in [-1.0, 1.0]:
				_mesh(HumanoidScript.box(Vector3(0.3, 0.035, front - back)), gold, Vector3(sx * 3.2, 0.02, mid)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-1.0, 1.0]:
		_mesh(HumanoidScript.box(Vector3(1.2, h, ln)), wallc, Vector3(sx * (w + 1.0), h / 2, mid))
		_mesh(HumanoidScript.box(Vector3(1.4, 1.2, ln)), stone, Vector3(sx * (w + 0.9), 0.6, mid))
		for px in hall.rows:
			var z := back + 4.0
			while z < front - 2.0:
				var r := 0.6 if grand else (0.5 if hall.carpet else 0.38)
				_mesh(HumanoidScript.cyl(r * 0.92, r, h, 12), red, Vector3(sx * px, h / 2, z))
				_mesh(HumanoidScript.cyl(r * 1.4, r * 1.4, 0.5, 12), stone, Vector3(sx * px, 0.25, z))
				if hall.carpet:
					_mesh(HumanoidScript.cyl(r * 1.25, r, 0.5, 12), gold, Vector3(sx * px, h - 0.4, z))
				if grand:
					_mesh(HumanoidScript.cyl(r * 1.03, r * 1.03, 0.25, 12), gold, Vector3(sx * px, h * 0.5, z))
				_solid(Vector3(sx * px, 2.0, z), Vector3(r * 2.2, 4, r * 2.2))
				_mesh(HumanoidScript.box(Vector3(1.3, minf(3.2, h * 0.3), 0.05)), colors[1], Vector3(sx * (w + 0.3), h * 0.58, z + hall.gap / 2))     # 壁上挂旗
				z += float(hall.gap)
		var lz := back + 6.0
		while lz < front - 4.0:      # 灯
			var lx: float = sx * (w - 2.0)
			_mesh(HumanoidScript.cyl(0.07, 0.1, 2.4), Color("#3a2a1a"), Vector3(lx, 1.2, lz))
			_mesh(HumanoidScript.box(Vector3(0.5, 0.6, 0.5)), Color("#e8a83a"), Vector3(lx, 2.7, lz))
			lz += 13.0 if hall.carpet else 16.0
		if grand:      # 殿前两尊铜鼎
			var dz := front - 8.0
			_mesh(HumanoidScript.cyl(1.1, 0.8, 1.2, 10), Color("#6a5a34"), Vector3(sx * 5.5, 1.3, dz))
			for k in 3:
				var a := TAU * k / 3.0
				_mesh(HumanoidScript.cyl(0.12, 0.12, 0.8, 6), Color("#6a5a34"), Vector3(sx * 5.5 + cos(a) * 0.7, 0.4, dz + sin(a) * 0.7))
			_solid(Vector3(sx * 5.5, 1.0, dz), Vector3(2.2, 2, 2.2))
	var bz := back - 2.0
	while bz < front + 4.0:      # 横梁
		_mesh(HumanoidScript.box(Vector3(w * 2 + 3, 0.7, 0.7)), red.darkened(0.25), Vector3(0, h + 0.2, bz))
		if grand:
			_mesh(HumanoidScript.box(Vector3(w * 2 + 3, 0.25, 0.9)), gold.darkened(0.2), Vector3(0, h - 0.4, bz))
		bz += float(hall.gap)
	_mesh(HumanoidScript.box(Vector3(w * 2 + 3, h, 1.2)), wallc, Vector3(0, h / 2, back - 8.0))
	var door := 5.5 if grand else 4.0
	for sx in [-1.0, 1.0]:      # 殿门两侧
		_mesh(HumanoidScript.box(Vector3(w + 1.0 - door, h, 1.2)), wallc, Vector3(sx * (door + (w + 1.0 - door) / 2), h / 2, front + 4.0))
	_mesh(HumanoidScript.box(Vector3(door * 2, h * 0.3, 1.2)), wallc, Vector3(0, h * 0.85, front + 4.0))
	# 高台与座位：府衙是一张公案，王府、皇宫是宝座与屏风
	var dh: float = hall.dais
	var dzc := back - 3.5
	var dw := w * (1.2 if grand else 1.0)
	_mesh(HumanoidScript.box(Vector3(dw, dh, 9)), stone, Vector3(0, dh / 2, dzc))
	if grand:
		for k in 3:      # 丹陛
			_mesh(HumanoidScript.box(Vector3(dw * 0.6, dh * (0.75 - k * 0.25), 1.2)), stone.lightened(0.12), Vector3(0, dh * (0.75 - k * 0.25) / 2, dzc + 4.9 + k * 1.1))
	_solid(Vector3(0, 1.0, dzc), Vector3(dw, 2, 9))
	var seat := gold if hall.carpet else Color("#4a3322")
	var sc := 1.4 if grand else 1.0
	_mesh(HumanoidScript.box(Vector3(2.6 * sc, 0.7, 1.8)), seat, Vector3(0, dh + 0.35, dzc - 0.5))
	_mesh(HumanoidScript.box(Vector3(2.8 * sc, 2.6 * sc, 0.3)), seat, Vector3(0, dh + 1.3 * sc, dzc - 1.5))
	for sx in [-1.0, 1.0]:
		_mesh(HumanoidScript.box(Vector3(0.3, 1.2, 1.8)), seat, Vector3(sx * 1.45 * sc, dh + 0.9, dzc - 0.5))
	if hall.carpet:
		var sw := 9.0 * sc
		_mesh(HumanoidScript.box(Vector3(sw, h * 0.55, 0.25)), Color("#2a2420"), Vector3(0, dh + h * 0.3, dzc - 3.2))
		_mesh(HumanoidScript.box(Vector3(sw - 0.6, h * 0.5, 0.1)), (gold.darkened(0.15) if grand else colors[1].darkened(0.2)), Vector3(0, dh + h * 0.3, dzc - 3.0))
		_mesh(HumanoidScript.cyl(1.4 * sc, 1.4 * sc, 0.06, 20), Color("#a8321e") if grand else gold, Vector3(0, dh + h * 0.33, dzc - 2.9), null).rotation.x = PI / 2
	else:
		_mesh(HumanoidScript.box(Vector3(3.6, 0.9, 1.2)), Color("#3a2a1a"), Vector3(0, dh + 0.45, dzc + 1.6))       # 公案
		_mesh(HumanoidScript.box(Vector3(5.0, 1.4, 0.1)), Color("#2a2420"), Vector3(0, h * 0.72, dzc - 4.2))         # 匾额
		_mesh(HumanoidScript.box(Vector3(4.6, 1.0, 0.12)), gold.darkened(0.3), Vector3(0, h * 0.72, dzc - 4.15))


func _solid(pos: Vector3, sz: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = sz
	cs.shape = bx
	sb.add_child(cs)
	sb.position = pos
	world.add_child(sb)


# 城内：门内横街、中央大街、十字街、府衙前广场；四片街坊是整块的障碍
func _build_city(rng: RandomNumberGenerator) -> void:
	var wallc := Color(str(bio.wall))
	var housec := Color(str(bio.house))
	var roofc := Color(str(bio.roof))
	var pave := _mesh(HumanoidScript.box(Vector3(124, 0.06, 70)), Color("#8a8272") if not bio.snow else Color("#cfd4d8"), Vector3(0, 0.03, -89))
	pave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh(HumanoidScript.box(Vector3(130, 7, 2)), wallc, Vector3(0, 3.5, -123))
	for sx in [-1.0, 1.0]:
		_mesh(HumanoidScript.box(Vector3(2, 7, 70)), wallc, Vector3(sx * 62.0, 3.5, -89))
	for blk in [[-66.0, -76.0], [-100.0, -86.0]]:
		for sx in [-1.0, 1.0]:
			var z0: float = blk[0]
			var z1: float = blk[1]
			var depth := absf(z1 - z0)
			_solid(Vector3(sx * 32.0, 2.0, (z0 + z1) / 2), Vector3(50, 4, depth))
			for k in 4:
				var hw := rng.randf_range(9.5, 11.5)
				var hh := rng.randf_range(3.0, 4.4)
				var c := Vector3(sx * (13.0 + k * 12.6), 0, (z0 + z1) / 2)
				var hc := housec.darkened(rng.randf() * 0.12)
				var homes := str(arch.homes)
				var door_z := (depth / 2 - 0.25) * (1.0 if k % 2 == 0 else -1.0)
				if homes == "yurt":          # 毡帐
					for dz in [-depth * 0.24, depth * 0.24]:
						var yr := minf(hw, depth * 0.5) * 0.42
						_mesh(HumanoidScript.cyl(yr, yr, 2.2, 14), hc, c + Vector3(0, 1.1, dz))
						_mesh(HumanoidScript.cyl(0.5, yr * 1.06, 1.4, 14), roofc, c + Vector3(0, 2.9, dz))
						_mesh(HumanoidScript.cyl(yr * 1.02, yr * 1.02, 0.18, 14), colors[1].darkened(0.2), c + Vector3(0, 2.1, dz))
					continue
				if homes == "stilt":         # 干栏：架空的茅屋
					for px in [-hw * 0.4, hw * 0.4]:
						for pz in [-depth * 0.38, depth * 0.38]:
							_mesh(HumanoidScript.cyl(0.18, 0.18, 1.8, 6), Color("#4a3322"), c + Vector3(px, 0.9, pz))
					_mesh(HumanoidScript.box(Vector3(hw, hh * 0.7, depth - 0.6)), hc, c + Vector3(0, 1.8 + hh * 0.35, 0))
					var sr := _mesh(HumanoidScript.cyl(0.0, 1.0, 1.0, 4), roofc, c + Vector3(0, 1.8 + hh * 0.7 + 1.4, 0))
					sr.rotation.y = PI / 4
					sr.scale = Vector3(hw * 0.85, 2.8, depth * 0.85)
					continue
				_mesh(HumanoidScript.box(Vector3(hw, hh, depth - 0.6)), hc, c + Vector3(0, hh / 2, 0))
				if homes == "flat" or homes == "dome":      # 平顶土屋，或其上起穹顶
					_mesh(HumanoidScript.box(Vector3(hw + 0.4, 0.35, depth - 0.2)), roofc, c + Vector3(0, hh + 0.17, 0))
					if homes == "dome" and k % 2 == 0:
						var dm := _mesh(HumanoidScript.ball(1.0), Color(str(arch.dome)) if k == 0 else hc.lightened(0.1), c + Vector3(0, hh + 0.2, 0))
						dm.scale = Vector3(hw * 0.32, 1.9, depth * 0.3)
					elif k % 2 == 1:
						_mesh(HumanoidScript.box(Vector3(hw * 0.45, 1.6, depth * 0.4)), hc.darkened(0.06), c + Vector3(hw * 0.15, hh + 1.1, depth * 0.1))
				else:
					var roof := _mesh(HumanoidScript.cyl(0.0, 1.0, 1.0, 4), roofc, c + Vector3(0, hh + (1.3 if homes == "thatch" else 0.9), 0))
					roof.rotation.y = PI / 4
					roof.scale = Vector3(hw * 0.78, 2.6 if homes == "thatch" else 1.8, depth * 0.78)
				_mesh(HumanoidScript.box(Vector3(1.2, 2.0, 0.1)), Color("#3a2416"), c + Vector3(0, 1.0, door_z))
	# 府衙
	var hall := Vector3(0, 0, -115)
	_solid(hall + Vector3(0, 3, 0), Vector3(26, 6, 9))
	_mesh(HumanoidScript.box(Vector3(28, 1.0, 11)), wallc.darkened(0.1) if str(arch.hall) != "chinese" else Color("#8d8576"), hall + Vector3(0, 0.5, 0))
	match str(arch.hall):
		"column":      # 列柱神殿
			var marble := wallc.lightened(0.12)
			_mesh(HumanoidScript.box(Vector3(22, 5.6, 6)), marble.darkened(0.08), hall + Vector3(0, 3.8, -1.0))
			for k in 8:
				_mesh(HumanoidScript.cyl(0.5, 0.58, 5.6, 12), marble, hall + Vector3(-12.25 + k * 3.5, 3.8, 4.0))
			_mesh(HumanoidScript.box(Vector3(29, 0.9, 12)), marble, hall + Vector3(0, 7.05, 0))
			var ped := _mesh(HumanoidScript.cyl(0.0, 1.0, 1.0, 4), roofc, hall + Vector3(0, 8.6, 0))
			ped.rotation.y = PI / 4
			ped.scale = Vector3(20.5, 2.2, 8.5)
		"dome":        # 穹顶大殿，两侧高塔
			_mesh(HumanoidScript.box(Vector3(22, 6, 8.5)), housec, hall + Vector3(0, 4.0, 0))
			_mesh(HumanoidScript.box(Vector3(6, 7.4, 9.0)), housec.lightened(0.08), hall + Vector3(0, 4.7, 0))
			_mesh(HumanoidScript.box(Vector3(3.2, 5.0, 0.3)), Color("#2a2420"), hall + Vector3(0, 3.5, 4.5))
			var dm := _mesh(HumanoidScript.ball(1.0), Color(str(arch.dome)), hall + Vector3(0, 7.2, 0))
			dm.scale = Vector3(6.2, 5.2, 4.2)
			_mesh(HumanoidScript.cyl(0.0, 0.25, 1.6, 6), Color("#d9b04a"), hall + Vector3(0, 13.0, 0))
			for sx in [-1.0, 1.0]:
				_mesh(HumanoidScript.cyl(0.6, 0.8, 12.0, 10), housec.lightened(0.05), hall + Vector3(sx * 13.0, 7.0, 0))
				_mesh(HumanoidScript.cyl(1.0, 1.0, 0.4, 10), housec.darkened(0.1), hall + Vector3(sx * 13.0, 11.0, 0))
				var md := _mesh(HumanoidScript.ball(1.0), Color(str(arch.dome)), hall + Vector3(sx * 13.0, 13.0, 0))
				md.scale = Vector3(0.9, 1.3, 0.9)
		"shikhara":    # 层叠塔庙
			for k in 5:
				_mesh(HumanoidScript.box(Vector3(20 - k * 3.6, 2.0, 8.6 - k * 1.3)), wallc.lightened(0.04 * k), hall + Vector3(0, 2.0 + k * 2.0, 0))
				_mesh(HumanoidScript.box(Vector3(20.6 - k * 3.6, 0.3, 9.2 - k * 1.3)), wallc.darkened(0.15), hall + Vector3(0, 3.0 + k * 2.0, 0))
			_mesh(HumanoidScript.cyl(0.0, 1.6, 3.0, 8), Color("#d9b04a"), hall + Vector3(0, 12.6, 0))
			for sx in [-1.0, 1.0]:
				_mesh(HumanoidScript.cyl(0.0, 1.4, 4.5, 8), wallc.lightened(0.06), hall + Vector3(sx * 11.5, 4.2, 0))
		"yurt":        # 汗帐
			_mesh(HumanoidScript.cyl(8.0, 8.0, 4.0, 20), housec, hall + Vector3(0, 3.0, 0))
			_mesh(HumanoidScript.cyl(1.0, 8.5, 3.6, 20), roofc, hall + Vector3(0, 6.8, 0))
			_mesh(HumanoidScript.cyl(8.1, 8.1, 0.5, 20), colors[1], hall + Vector3(0, 4.6, 0))
			_mesh(HumanoidScript.cyl(1.1, 1.1, 0.4, 12), Color("#d9b04a"), hall + Vector3(0, 8.8, 0))
			_mesh(HumanoidScript.box(Vector3(2.6, 3.2, 0.3)), colors[1].darkened(0.3), hall + Vector3(0, 2.6, 8.0))
		"longhouse":   # 茅顶长屋
			_mesh(HumanoidScript.box(Vector3(24, 3.6, 8)), housec.darkened(0.1), hall + Vector3(0, 2.8, 0))
			var lr := _mesh(HumanoidScript.cyl(0.0, 1.0, 1.0, 4), roofc, hall + Vector3(0, 7.4, 0))
			lr.rotation.y = PI / 4
			lr.scale = Vector3(19.5, 5.6, 8.2)
			for sx in [-1.0, 1.0]:
				_mesh(HumanoidScript.box(Vector3(0.35, 5.0, 0.35)), Color("#4a3322"), hall + Vector3(sx * 2.0, 3.5, 4.2))
				_mesh(HumanoidScript.box(Vector3(0.3, 3.4, 0.3)), Color("#4a3322"), hall + Vector3(sx * 1.2, 9.4, 4.2)).rotation.z = -sx * 0.45
			_mesh(HumanoidScript.box(Vector3(2.6, 3.2, 0.3)), Color("#2a2420"), hall + Vector3(0, 2.6, 4.1))
		"fort":        # 层台碉楼
			_mesh(HumanoidScript.box(Vector3(24, 6, 8)), wallc, hall + Vector3(0, 4.0, 0))
			_mesh(HumanoidScript.box(Vector3(15, 3.6, 6.4)), wallc.lightened(0.06), hall + Vector3(0, 8.8, 0))
			_mesh(HumanoidScript.box(Vector3(15.4, 0.9, 6.8)), roofc, hall + Vector3(0, 10.9, 0))
			_mesh(HumanoidScript.box(Vector3(24.4, 0.8, 8.4)), roofc, hall + Vector3(0, 7.2, 0))
			for k in 7:
				_mesh(HumanoidScript.box(Vector3(0.9, 1.4, 0.2)), Color("#2a2420"), hall + Vector3(-9 + k * 3.0, 4.6, 4.05))
		_:
			_mesh(HumanoidScript.box(Vector3(24, 5, 8)), Color(str(arch.pillar)), hall + Vector3(0, 3.5, 0))
			_mesh(HumanoidScript.box(Vector3(29, 0.7, 12)), roofc, hall + Vector3(0, 6.3, 0))
			_mesh(HumanoidScript.box(Vector3(18, 2.2, 6)), Color(str(arch.pillar)), hall + Vector3(0, 7.7, 0))
			_mesh(HumanoidScript.box(Vector3(22, 0.7, 9)), roofc, hall + Vector3(0, 9.1, 0))
	_standard(Vector3(-16.5, 0, -108), str(b.def_f), 9.0)
	_standard(Vector3(13.5, 0, -108), str(b.def_f), 9.0)
	for sx in [-1.0, 1.0]:      # 街口灯柱
		for z in [-64.0, -78.0, -84.0, -100.0]:
			_mesh(HumanoidScript.cyl(0.08, 0.1, 2.6), Color("#3a2a1a"), Vector3(sx * 6.4, 1.3, z))
			_mesh(HumanoidScript.box(Vector3(0.4, 0.5, 0.4)), Color("#d8a03a"), Vector3(sx * 6.4, 2.7, z))


# 守军分兵：三成上城头（弓手优先），三成半留守城内，其余出城迎战；最强的武将坐镇府衙
func _garrison() -> void:
	# 玩家主持守城并选了城头迎击：全军不出城，一半上城头，其余（含骑兵、武将）在城内待命
	var hold: bool = defense == "wall" and bool(b.leads)
	var sol: Array = []
	var rest: Array = []
	for u in units[1]:
		if u.is_player:
			continue
		if not u.is_general and not u.mounted:
			sol.append(u)
		else:
			rest.append(u)
	sol.sort_custom(func(x, y): return int(x.weapon == "bow") > int(y.weapon == "bow"))
	var n := sol.size()
	var n_wall := int(n * (0.5 if hold else 0.3))
	var n_in := (n - n_wall) if hold else int(n * 0.35)
	for i in n_wall:
		sol[i].place(Vector3(lerpf(-44.0, 44.0, (i + 0.5) / n_wall), WALL_Y, -49.9), 1)
	for i in n_in:
		sol[n - 1 - i].place(Vector3((i % 6 - 2.5) * 2.0, 0, -86.0 - (i / 6) * 2.4), 2)
	var best = null
	for u in rest:
		if u.is_general and (best == null or u.war > best.war):
			best = u
	if best != null and n_in > 0:
		best.place(Vector3(0, 0, -103), 2)
	if hold:
		var k := 0
		for u in rest:
			if u != best:
				u.place(Vector3((k % 8 - 3.5) * 3.2, 0, -61.0 - (k / 8) * 3.0), 2)
				k += 1
	if defense == "wall":
		player.place(Vector3(6, WALL_Y, -51), 1)


func zone_name(z: int) -> String:
	return [Lang.t("城外"), Lang.t("城头"), Lang.t("城内")][z]


func enemy_in_zone(team: int, z: int) -> bool:
	for e in units[1 - team]:
		if not e.dead and e.zone == z and not e.fleeing:
			return true
	return false


func nearest_link(f, kind: String, raised_only := false):
	var best = null
	var best_d := INF
	for l in links:
		if l.kind != kind or (raised_only and not l.up):
			continue
		var d: float = f.position.distance_squared_to(l.a)
		if d < best_d:
			best_d = d
			best = l
	return best


# 攻方各队分头去不同的云梯，中间两架人多些
func ladder_for(f) -> Dictionary:
	var want: float = LADDER_X[[1, 2, 1, 2, 0, 3][f.get_instance_id() % 6]]
	for l in links:
		if l.kind == "ladder" and is_equal_approx(l.a.x, want):
			return l
	return nearest_link(f, "ladder")


func raise_ladder(l: Dictionary) -> void:
	if l.up:
		return
	l.up = true
	var a: Vector3 = l.a
	var top: Vector3 = l.b + Vector3(0, 0.6, 1.2)
	var n := Node3D.new()
	world.add_child(n)
	var ln := a.distance_to(top)
	for sx in [-1.0, 1.0]:
		_mesh(HumanoidScript.box(Vector3(0.09, 0.09, ln)), Color("#6b4a2b"), Vector3(sx * 0.38, 0, 0), n)
	for k in int(ln / 0.55):
		_mesh(HumanoidScript.box(Vector3(0.76, 0.06, 0.06)), Color("#7a5a3c"), Vector3(0, 0, -ln / 2 + 0.4 + k * 0.55), n)
	n.look_at_from_position((a + top) / 2, top)
	_msg(Lang.t("云梯架起！登城！"))
	Sfx.play_at("gate_hit", a, -4.0)


func hit_gate(power: float) -> void:
	if gate_open:
		return
	gate_hp -= power
	last_hit_t = clock
	Sfx.play_at("gate_hit", Vector3(0, 0, -47))
	if gate_hp <= 0.0:
		gate_open = true
		gate_node.queue_free()
		for k in 5:      # 碎门板
			var pl := _mesh(HumanoidScript.box(Vector3(1.6, 0.12, 2.6)), Color("#3a2416"), Vector3(randf_range(-3.5, 3.5), 0.08, randf_range(-58, -45)))
			pl.rotation.y = randf() * TAU
		_msg(Lang.t("城门已破！杀入城中！"))
		Sfx.play("gate_break")


# 城墙、门洞、城内的活动范围（代替碰撞体）。顺带更新所在区域。
func constrain(f) -> void:
	var p: Vector3 = f.position
	if f.zone == 1:
		p.x = clampf(p.x, -58.0, 58.0)
		p.z = clampf(p.z, -53.2, -49.2)
	else:
		var in_gate: bool = gate_open and absf(p.x) < 3.4
		if f.zone == 0:
			if moat:
				if p.z >= MOAT_Z1:
					f.moat_side = 1
				elif p.z <= MOAT_Z0:
					f.moat_side = -1
				else:      # 河面上：在桥上就沿桥走，否则退回原来那一岸
					var on_bridge := false
					for br in bridges:
						if p.x > br[0] - 0.5 and p.x < br[1] + 0.5:
							p.x = clampf(p.x, br[0] + 0.25, br[1] - 0.25)
							on_bridge = true
							break
					if not on_bridge:
						p.z = (MOAT_Z1 + 0.02) if f.moat_side >= 0 else (MOAT_Z0 - 0.02)
			if p.z < -46.6:
				if in_gate:
					if p.z < -55.4:
						f.zone = 2
				else:
					p.z = -46.6
			p.z = minf(p.z, 68.0)
		else:
			if p.z > -55.4:
				if in_gate:
					if p.z > -46.6:
						f.zone = 0
				else:
					p.z = -55.4
			p.z = maxf(p.z, -109.5 if absf(p.x) < 14.5 else -121.0)
			p.x = clampf(p.x, -60.0, 60.0)
		if in_gate and p.z < -46.6 and p.z > -55.4:
			p.x = clampf(p.x, -3.1, 3.1)
	f.position = p


# 要去的地方隔着护城河时，先奔最顺路的桥。返回眼下该朝哪个点走。
func moat_route(p: Vector3, t: Vector3) -> Vector3:
	if not moat:
		return t
	var ps := 1 if p.z >= MOAT_Z1 else (-1 if p.z <= MOAT_Z0 else 0)
	var ts := 1 if t.z >= MOAT_Z1 else (-1 if t.z <= MOAT_Z0 else 0)
	if ps == ts and ps != 0:
		return t
	var best := 0.0
	var bd := INF
	for br in bridges:
		var c: float = (br[0] + br[1]) / 2.0
		var d: float = absf(p.x - c) + absf(t.x - c)
		if d < bd:
			bd = d
			best = c
	var far_z := (MOAT_Z0 - 1.2) if t.z < (MOAT_Z0 + MOAT_Z1) / 2.0 else (MOAT_Z1 + 1.2)
	if ps == 0 or absf(p.x - best) < 1.0:
		return Vector3(best, 0, far_z)
	return Vector3(best, 0, (MOAT_Z1 + 0.7) if ps > 0 else (MOAT_Z0 - 0.7))


# 玩家走到云梯或马道口并朝另一头走，就自动上下
func try_link(f, mv: Vector3) -> void:
	for l in links:
		for rev in [false, true]:
			var a: Vector3 = l.b if rev else l.a
			var bb: Vector3 = l.a if rev else l.b
			var za: int = l.zb if rev else l.za
			var zb: int = l.za if rev else l.zb
			if f.zone != za or f.position.distance_to(a) > 1.5:
				continue
			var dir := bb - a
			dir.y = 0
			if mv.normalized().dot(dir.normalized()) < 0.5:
				continue
			if f.mounted:
				if warn_t <= 0.0:
					warn_t = 3.0
					_msg(Lang.t("战马上不了城墙——下马（R / 手柄 −），或走城门"))
				return
			if l.kind == "ladder" and not l.up:
				if f.team != 0:
					return
				raise_ladder(l)
			f.start_link(a, bb, float(l.t), zb)
			return


# ───────────── 布阵 ─────────────

func _general_weapon(gname: String) -> String:
	if DB.GENERAL_WEAPONS.has(gname):
		return DB.GENERAL_WEAPONS[gname]
	return ["glaive", "spear", "dao"][absi(hash(gname)) % 3]


func _add_unit(team: int, kind: String, pos: Vector3, gname := "", war := 50, weapon := "dao", mounted := false, coat := ""):
	var f = FighterScript.new()
	world.add_child(f)
	if coat == "":
		coat = HORSE_COATS[randi() % HORSE_COATS.size()]
	f.setup(self, team, colors[team], kind, gname, war, weapon, mounted, Color(coat))
	f.position = pos
	f.rotation.y = 0.0 if team == 0 else PI
	f.face_yaw = f.rotation.y
	f.think = randf() * 0.5
	f.cd = randf() * 1.0
	units[team].append(f)
	return f


func _spawn_all() -> void:
	var n := [0, 0]
	if b.type == "bandit" or palace:
		n = [troops[0], troops[1]]
		scale_troops = 1.0
	else:
		scale_troops = maxf(1.0, maxi(troops[0], troops[1]) / float(MAX_AGENTS))
		for t in 2:
			n[t] = clampi(roundi(troops[t] / scale_troops), 2, MAX_AGENTS)
	var gen_lists: Array = [b.att_gens, b.def_gens]
	var spread := 22.0 if b.type == "bandit" else (30.0 if not palace else (float(hall.front) - float(hall.back)) * 0.3)
	var cols := 15 if not palace else (6 if x_lim < 12.0 else (8 if x_lim < 16.0 else 10))
	for team in 2:
		var back := 1.0 if team == 0 else -1.0
		var z0 := spread * back
		var gl: Array = gen_lists[team]
		for i in gl.size():
			var g = Game.gens.get(gl[i], null)
			var war := int(g.war) if g != null else 60
			var gcoat := str(Game.item(str(DB.GENERAL_HORSES.get(gl[i], ""))).get("col", ""))
			_add_unit(team, "general", Vector3((i - (gl.size() - 1) / 2.0) * 6.0, 0, z0 - back * 2.0), gl[i], war, _general_weapon(gl[i]), (war >= 80 or gcoat != "") and not palace, gcoat)
			gens_alive[team] += 1
			had_gens[team] = true
		var soldier_kind := "bandit" if (b.type == "bandit" and team == 0) else "soldier"
		var big_squad: bool = team == pteam and Game.squad_size() > 24      # 亲兵多了就居中列阵
		var px := (x_lim - 6.5) if palace else (0.0 if big_squad else 13.0)
		var sq_cols := 6 if (palace or not big_squad) else 12
		var vet_lv := float(b.get("att_vet" if team == 0 else "def_vet", 0.0))
		var pz := z0 - back * 3.0
		var sq := 0
		if team == pteam:
			wslots = Game.weapon_slots()
			var horse: Dictionary = Game.item(str(Game.player.eq.horse))
			player = _add_unit(team, "player", Vector3(px, 0, pz), str(Game.player.name), 50,
				str(Game.item(wslots[0]).w), not horse.is_empty() and defense != "wall" and not palace, str(horse.get("col", "")))
			player.set_item(wslots[0], false)
			sq = mini(Game.squad_size(), n[team])
			squad_n = sq
		var roster: Array = Game.squad() if team == pteam else []
		var rest: int = n[team] - sq
		var n_cav := 0 if (b.type == "bandit" or palace) else int(rest * 0.15)
		for i in n[team]:
			var pos: Vector3
			var wpn := "spear"
			var mt := false
			if i < sq:
				pos = Vector3(px + (i % sq_cols - (sq_cols - 1) / 2.0) * 1.6, 0, pz + back * (1.8 + (i / sq_cols) * 1.6))
				var rk := str(roster[i].k)      # 亲兵按名册上各人的兵种上阵
				wpn = "spear" if rk == "cav" else rk
				mt = rk == "cav" and not palace
			else:
				var j: int = i - sq
				if j < n_cav:
					# 骑兵列于两翼
					var side := -1.0 if j % 2 == 0 else 1.0
					pos = Vector3(side * (19.0 + (j / 2) * 2.4), 0, z0 + back * 1.0)
					wpn = "spear" if j % 3 != 2 else "glaive"
					mt = true
				else:
					j -= n_cav
					var foot: int = rest - n_cav
					pos = Vector3((j % cols - (cols - 1) / 2.0) * 1.8 + randf_range(-0.2, 0.2), 0, z0 + back * (1.5 + (j / cols) * 1.8))
					# 前排刀盾与长枪相间，最后两成是弓手
					if j >= foot - int(foot * 0.22):
						wpn = "bow"
					else:
						wpn = "dao" if (j % 5 < 2) else "spear"
			if soldier_kind == "bandit":
				wpn = "bow" if i % 6 == 5 else "saber"
				mt = false
			var u = _add_unit(team, soldier_kind, pos, "", 50, wpn, mt)
			u.in_squad = i < sq
			if u.in_squad:
				# 每个亲兵按自己的等级得到加成与专长
				u.roster_i = i
				squad_res[i] = {"i": i, "alive": true, "kills": 0}
				u.apply_troop(str(roster[i].k), Game.level_of(int(roster[i].xp)))
			elif soldier_kind == "soldier" and vet_lv > 0.0:
				# 不是亲兵的士兵：按所在军队的训练度定等级，同样有加成、专长和外观
				var slv := clampi(int(vet_lv) + (1 if randf() < vet_lv - int(vet_lv) else 0), 0, 5)
				if slv > 0:
					u.apply_troop(_troop_key(u), slv)
			if palace and team == 1:      # 宫中禁卫是百里挑一的精锐
				u.max_hp *= 1.4
				u.hp = u.max_hp
				u.dmg *= 1.15
			if b.type == "bandit" and team == 0:
				u.position += Vector3(randf_range(-4, 4), 0, randf_range(-3, 3))
		initial[team] = units[team].size()


func _troop_key(u) -> String:
	if u.mounted:
		return "cav"
	return "bow" if u.weapon == "bow" else ("dao" if u.weapon == "dao" or u.weapon == "saber" else "spear")


func nearest_enemy(f):
	var best = null
	var best_d := INF
	var ranged: bool = f.is_ranged()
	for e in units[1 - f.team]:
		if e.dead:
			continue
		# 攻城战里只打够得着的：近战同一区域，弓箭可及相邻区域
		if siege and e.zone != f.zone and not (ranged and absi(e.zone - f.zone) == 1):
			continue
		var d: float = f.position.distance_squared_to(e.position)
		if e.is_player:
			d *= 1.3
		if d < best_d:
			best_d = d
			best = e
	return best


# 玩家放箭时的辅助瞄准：镜头正前方小夹角内最近的敌人
func player_aim():
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	var best = null
	var best_s := INF
	for e in units[1 - pteam]:
		if e.dead:
			continue
		var to: Vector3 = e.position - player.position
		var d := to.length()
		if d > 60.0 or d < 0.5:
			continue
		var c := f.dot(to / d)
		if c < 0.95:
			continue
		var s := d * (1.0 + (1.0 - c) * 40.0)
		if s < best_s:
			best_s = s
			best = e
	return best


func spawn_arrow(origin: Vector3, vel: Vector3, dmg: float, team: int, from, brk: bool) -> void:
	var n := Node3D.new()
	world.add_child(n)
	n.position = origin
	var shaft := MeshInstance3D.new()
	shaft.mesh = HumanoidScript.cyl(0.012, 0.012, 0.85, 4)
	shaft.material_override = HumanoidScript.mat(Color("#e8dcc0") if not brk else Color("#ffd24a"))
	shaft.rotation.x = PI / 2
	n.add_child(shaft)
	var tip := MeshInstance3D.new()
	tip.mesh = HumanoidScript.cyl(0.0, 0.03, 0.12, 4)
	tip.material_override = HumanoidScript.mat(Color("#cfd3da"), 0.8)
	tip.rotation.x = -PI / 2
	tip.position.z = -0.48
	n.add_child(tip)
	n.look_at(origin + vel)
	arrows.append({"n": n, "v": vel, "dmg": dmg, "team": team, "from": from, "brk": brk, "life": 3.0, "stuck": false})


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	for a in arrows.duplicate():
		var n: Node3D = a.n
		a.life -= delta
		if a.life <= 0.0:
			n.queue_free()
			arrows.erase(a)
			continue
		if a.stuck:
			continue
		a.v.y -= FighterScript.ARROW_G * delta
		var p0: Vector3 = n.position
		var p1: Vector3 = p0 + a.v * delta
		var hit = null
		for e in units[1 - int(a.team)]:
			if e.dead:
				continue
			var c: Vector3 = e.position + Vector3(0, 1.0, 0)
			var q := Geometry3D.get_closest_point_to_segment(c, p0, p1)
			var dv := q - c
			if absf(dv.y) < 1.0 and Vector2(dv.x, dv.z).length() < 0.5:
				hit = e
				break
		if hit != null:
			var shooter = a.from if is_instance_valid(a.from) else null
			hit.take_damage(a.dmg, shooter, p0, a.brk, 3.0)
			n.queue_free()
			arrows.erase(a)
		elif p1.y <= ground_y(p1.x, p1.z) + 0.05:
			p1.y = ground_y(p1.x, p1.z) + 0.05
			n.position = p1
			a.stuck = true
			a.life = 6.0
		else:
			n.position = p1
			n.look_at(p1 + a.v)


func soldiers_alive(team: int) -> int:
	var c := 0
	for u in units[team]:
		if not u.is_general and not u.is_player:
			c += 1
	return c


func on_death(f, from) -> void:
	units[f.team].erase(f)
	if f.is_general:
		gens_alive[f.team] -= 1
		_msg(Lang.t("%s军大将【%s】败退！") % [names[f.team], f.gname])
	if from != null and is_instance_valid(from) and from.roster_i >= 0 and f.team != pteam:
		squad_res[from.roster_i].kills += 1
	if f.roster_i >= 0:
		squad_res[f.roster_i].alive = false
	if from == player and f.team != pteam:
		kills += 1
		if f.is_general:
			gen_kills += 1
			gens_down.append(f.gname)
			_msg(Lang.t("你击破了敌将【%s】！") % f.gname)
		_roll_loot(f)
	if f == player:
		player_down = true
		_msg(Lang.t("你身负重伤，倒下了……"))
		_finish_numeric()


# 亲手击破的敌人有机会留下兵器或战马
func _roll_loot(f) -> void:
	var id := ""
	if f.is_general:
		var sig := str(DB.GENERAL_ITEMS.get(f.gname, ""))
		var hsig := str(DB.GENERAL_HORSES.get(f.gname, ""))
		var top := 2 if f.war >= 85 else 1
		if sig != "" and not Game.has_item(sig) and not loot.has(sig) and randf() < 0.25:
			id = sig
		elif hsig != "" and not Game.has_item(hsig) and not loot.has(hsig) and randf() < 0.25:
			id = hsig
		elif randf() < 0.4:
			id = _fresh(Game.random_item("weapon", "dao" if f.weapon == "saber" else f.weapon, 1, top))
		elif f.mounted and randf() < 0.45:
			id = _fresh(Game.random_item("horse", "", 1, top))
		elif randf() < 0.25:
			id = _fresh(Game.random_item("armor", "", 1, top))
	elif f.mounted and randf() < 0.12:
		id = _fresh(Game.random_item("horse", "", 0, 1))
	elif randf() < 0.03:
		id = _fresh(Game.random_item("", "", 0, 1))
	if id != "":
		loot.append(id)
		_msg(Lang.t("缴获【%s】！") % Game.item_name(id))
		Sfx.play("loot")


func _fresh(id: String) -> String:
	return "" if loot.has(id) else id


# ───────────── 胜负 ─────────────

func _check_rout() -> void:
	for team in 2:
		var cnt: int = units[team].size()
		var frac := cnt / float(maxi(1, initial[team]))
		var routed: bool = frac <= 0.2 or (had_gens[team] and gens_alive[team] <= 0 and frac <= 0.5)
		if team == 1 and last_stand:
			routed = false      # 无路可退，战至最后一人
		if cnt == 0 or routed:
			over = true
			winner = 1 - team
			for u in units[team]:
				u.fleeing = true
			_msg((Lang.t("%s军全军覆没！") if cnt == 0 else Lang.t("%s军溃败！")) % names[team])
			end_t = 2.8
			return


func _finish_numeric() -> void:
	if over:
		return
	over = true
	numeric = true
	var pw := [0.0, 0.0]
	for team in 2:
		for u in units[team]:
			if not u.dead:
				pw[team] += u.hp * u.dmg
	if retreated and b.leads:
		winner = 1 - pteam
	else:
		winner = 0 if pw[0] * randf_range(0.8, 1.2) > pw[1] * randf_range(0.8, 1.2) else 1
	end_t = 1.8


func _make_result() -> void:
	var left := [0, 0]
	for team in 2:
		var alive := minf(troops[team], soldiers_alive(team) * scale_troops)
		if team == winner:
			alive = alive * 0.75 if numeric else alive + 0.3 * (troops[team] - alive)
		else:
			alive = alive * (0.35 if numeric else 0.7)
		left[team] = int(alive)
	var pct := 0.0
	if is_instance_valid(player) and not player.dead:
		pct = player.hp / player.max_hp
	var gen_hp := {}      # 各将收兵时的伤势：若还有宫城之战，带伤上阵
	for team in 2:
		for u in units[team]:
			if u.is_general:
				gen_hp[u.gname] = 0.0 if u.dead else clampf(u.hp / u.max_hp, 0.0, 1.0)
	result = {
		"gen_hp": gen_hp,
		"winner": winner, "att_left": left[0], "def_left": left[1], "kills": kills,
		"gen_kills": gen_kills, "hp_pct": pct, "player_down": player_down,
		"loot": loot, "squad": squad_res.values(), "gens_down": gens_down,
	}


func _show_result() -> void:
	_make_result()
	if Game.autopilot:
		_leave()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var won := winner == pteam
	Sfx.play("victory" if won else "defeat")
	var title := Lang.t("胜　利") if won else Lang.t("败　北")
	var body := Lang.t("%s军 余 %d　｜　%s军 余 %d\n\n亲手斩获 %d 人　击破敌将 %d 员") % [names[0], int(result.att_left), names[1], int(result.def_left), kills, gen_kills]
	if not loot.is_empty():
		var ln: Array = []
		for id in loot:
			ln.append(Game.item_name(id))
		body += Lang.t("\n缴获：") + "、".join(ln)
	if player_down:
		body += Lang.t("\n你身负重伤，战局由余部自行了结。")
	elif retreated:
		body += Lang.t("\n你下令鸣金收兵。") if b.leads else Lang.t("\n你退出了战阵。")
	var next := Lang.t("返回")
	if Game.needs_palace(b, result):
		title = Lang.t("城　破") if pteam == 0 else Lang.t("外城失守")
		var hn: String = Game.hall_name(str(b.to))
		body += Lang.t("\n\n%s是%s的国都——%s退守%s，尚有最后一战！") % [b.to, names[1], names[1], hn]
		next = (Lang.t("杀入") if pteam == 0 else Lang.t("退守")) + hn
	result_panel = _panel(title, Color("#ffd98a") if won else Color("#c06060"), body, [[next, _leave]])


func _leave() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.finish_battle(result)
	if Game.pending_battle != null and Game.pending_battle.type == "palace":
		# 国都外城已破：接着打宫城
		if Game.autopilot:
			get_parent().add_child(load("res://scenes/Battle.tscn").instantiate())
			queue_free()
		else:
			get_tree().change_scene_to_file("res://scenes/Battle.tscn")
		return
	if not Game.autopilot:
		get_tree().change_scene_to_file("res://scenes/Main.tscn")


# ───────────── 每帧 ─────────────

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	clock += delta
	warn_t -= delta
	if is_instance_valid(player):
		Sfx.listener = player.position
	if not over and clock - last_hit_t > 45.0:
		_finish_numeric()      # 两军久不接战：按余部实力了结
	var js: Vector2 = Game.joy_stick(1)
	yaw -= js.x * delta * 2.8
	pitch = clampf(pitch + js.y * delta * 1.6, -0.05, 1.15)
	_update_cam(minf(1.0, delta * 14.0))
	if not over:
		check_t -= delta
		if check_t <= 0.0:
			check_t = 0.4
			_check_rout()
	elif end_t > 0.0:
		end_t -= delta
		if end_t <= 0.0:
			_show_result()
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			msg_lbl.text = Lang.fix("")
	_update_hud()


func _update_cam(k: float) -> void:
	if is_instance_valid(player):
		cam_target = cam_target.lerp(player.position, k)
	var t := cam_target + Vector3(0, 2.2 if (is_instance_valid(player) and player.mounted) else 1.7, 0)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * cam_dist
	var p := t + off
	p.y = maxf(p.y, ground_y(p.x, p.z) + 0.4)
	cam.position = p
	cam.look_at(t + Vector3(0, 0.3, 0))


func _input(e: InputEvent) -> void:
	if (get_tree().paused or (over and end_t <= 0.0)) and e is InputEventJoypadButton and e.pressed \
			and (e.button_index == JOY_BUTTON_A or e.button_index == JOY_BUTTON_B):
		var f := get_viewport().gui_get_focus_owner()
		if f is Button:
			get_viewport().set_input_as_handled()
			f.pressed.emit()
		return
	if over and end_t <= 0.0:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.004
		pitch = clampf(pitch + e.relative.y * 0.003, -0.05, 1.15)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(3.5, cam_dist - 0.6)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(16.0, cam_dist + 0.6)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE:
				_toggle_pause()
			KEY_SPACE:
				if is_instance_valid(player) and not get_tree().paused:
					player.dodge()
			KEY_Q:
				_cycle_weapon()
			KEY_R:
				_toggle_mount()
			KEY_1:
				_set_order(0)
			KEY_2:
				_set_order(1)
			KEY_3:
				_set_order(2)
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_START:
				_toggle_pause()
			JOY_BUTTON_A, JOY_BUTTON_B:
				if is_instance_valid(player) and not get_tree().paused:
					player.dodge()
			JOY_BUTTON_Y:
				_cycle_weapon()
			JOY_BUTTON_BACK:
				_toggle_mount()
			JOY_BUTTON_DPAD_UP:
				_set_order(0)
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
				_set_order(1)
			JOY_BUTTON_DPAD_DOWN:
				_set_order(2)


func _cycle_weapon() -> void:
	if not is_instance_valid(player) or player.dead or player.attack_t >= 0.0 or get_tree().paused:
		return
	if wslots.size() < 2:
		_msg(Lang.t("只带了一件兵器（可在行囊里装备副手）"))
		return
	var id: String = wslots[(wslots.find(player.item_id) + 1) % wslots.size()]
	player.set_item(id)
	_msg(Lang.t("换用：%s") % Game.item_name(id))


# 下马：战马留在原地；回到马旁再按一次上马
func _toggle_mount() -> void:
	if not is_instance_valid(player) or player.dead or get_tree().paused or over:
		return
	if player.mounted:
		if not player.set_mounted(false):
			return
		horse_prop = HumanoidScript.new()
		world.add_child(horse_prop)
		horse_prop.build_horse_only(colors[pteam], player.horse_col)
		horse_prop.position = player.position
		horse_prop.rotation.y = player.rotation.y
		horse_zone = player.zone
		player.position += Vector3(cos(player.rotation.y), 0, -sin(player.rotation.y)) * 1.2
		_msg(Lang.t("下马步战"))
	elif horse_prop != null:
		if player.zone != horse_zone or player.position.distance_to(horse_prop.position) > 4.0:
			_msg(Lang.t("战马不在身边"))
			return
		var at := horse_prop.position
		var ry := horse_prop.rotation.y
		if player.set_mounted(true):
			horse_prop.queue_free()
			horse_prop = null
			player.position = at
			player.rotation.y = ry
			player.face_yaw = ry
			_msg(Lang.t("上马"))
	else:
		_msg(Lang.t("你没有带战马上阵"))


func _set_order(o: int) -> void:
	squad_order = o
	if o == 2:
		for u in units[pteam]:
			if u.in_squad:
				u.hold_pos = u.position


func _toggle_pause() -> void:
	if over:
		return
	if get_tree().paused:
		get_tree().paused = false
		pause_panel.queue_free()
		pause_panel = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var help := Lang.t("键鼠：WASD 移动　鼠标 视角　左键 攻击　F/中键 重击　右键 格挡\nQ 换兵器　R 上马/下马　空格 闪避　Shift 疾跑　滚轮 远近　1/2/3 亲兵号令\n\n手柄：左摇杆 移动　右摇杆 视角　ZR/R 攻击　Y 重击　ZL/L 格挡\nX 换兵器　− 上马/下马　B/A 闪避　按下左摇杆 疾跑　十字键 亲兵号令　＋ 暂停\n\n招式：原地或前进连按 = 三连招（末招加成）\n出手时按 左/右 = 向该侧横斩　按 后 = 变招　疾跑中攻击 = 冲刺突刺\n重击可破盾防；弓会自动瞄向镜头正前方的敌人\n骑马时带着速度出手 = 冲锋（伤害+30%，击退更远）\n攻城：走到云梯脚下朝城墙走 = 登城；城头内侧有马道下到城里；城门可以砍破\n换兵器在主手、副手之间切换；亲手击破敌人有机会缴获兵器战马\n\n已连接手柄：") + Game.joy_names()
		pause_panel = _panel(Lang.t("暂　停"), Color.WHITE, help, [[Lang.t("继续"), _toggle_pause], [Lang.t("鸣金收兵") if b.leads else Lang.t("退出战阵"), _retreat], [Lang.t("回到主界面　（放弃此战）"), _quit_to_menu]])


# 丢下这一仗回主界面：进度停在开战前自动存的那一档
func _quit_to_menu() -> void:
	get_tree().paused = false
	Game.pending_battle = null
	Game.new_game()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _retreat() -> void:
	_toggle_pause()
	retreated = true
	_finish_numeric()


# ───────────── HUD ─────────────

func _lbl(pos: Vector2, sz: Vector2, font_size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	hud.add_child(l)
	return l


func _bar(pos: Vector2, sz: Vector2, col: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.position = pos
	p.size = sz
	p.show_percentage = false
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.border_color = Color(0, 0, 0, 0.9)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	p.add_theme_stylebox_override("fill", fill)
	p.add_theme_stylebox_override("background", bg)
	hud.add_child(p)
	return p


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.theme = Game.theme
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 左：我方  右：敌方
	var order := [pteam, 1 - pteam]
	for i in 2:
		var t: int = order[i]
		var x := 60.0 if i == 0 else 940.0
		bars[t] = _bar(Vector2(x, 44), Vector2(600, 22), colors[t])
		bars[t].max_value = maxi(1, initial[t])
		if i == 1:
			bars[t].fill_mode = ProgressBar.FILL_END_TO_BEGIN
		bar_lbls[t] = _lbl(Vector2(x, 12), Vector2(600, 30), 22, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
	kills_lbl = _lbl(Vector2(660, 38), Vector2(280, 30), 20, HORIZONTAL_ALIGNMENT_CENTER)
	msg_lbl = _lbl(Vector2(300, 150), Vector2(1000, 50), 34, HORIZONTAL_ALIGNMENT_CENTER)
	msg_lbl.add_theme_color_override("font_color", Color("#ffe08a"))
	hp_bar = _bar(Vector2(60, 838), Vector2(420, 26), Color("#c8372d"))
	hp_lbl = _lbl(Vector2(60, 806), Vector2(420, 30), 20)
	order_lbl = _lbl(Vector2(60, 772), Vector2(700, 30), 18)
	var hint := _lbl(Vector2(800, 838), Vector2(760, 30), 16, HORIZONTAL_ALIGNMENT_RIGHT)
	hint.text = Lang.fix(Lang.t("左键 攻击　F 重击　右键 格挡　Q 换兵器　R 上下马　空格 闪避　M 配乐　Esc 暂停/说明"))
	if not Input.get_connected_joypads().is_empty():
		hint.text = Lang.fix(Lang.t("ZR 攻击　Y 重击　ZL 格挡　X 换兵器　− 上下马　B 闪避　＋ 暂停/说明"))
	weapon_lbl = _lbl(Vector2(500, 838), Vector2(300, 30), 20)
	obj_lbl = _lbl(Vector2(300, 74), Vector2(1000, 30), 18, HORIZONTAL_ALIGNMENT_CENTER)
	obj_lbl.add_theme_color_override("font_color", Color("#ffe9b0"))
	var kind := (Lang.t("攻城") if pteam == 0 else Lang.t("守城")) if siege else Lang.t("剿匪")
	if palace:
		_msg(Lang.t("%s · %s之战") % [b.to, hall.name])
	else:
		_msg("%s · %s　%s" % [b.to, kind, bio.name])
	if last_stand:
		msg_lbl.text += Lang.fix(Lang.t("\n%s已无路可退——背水一战！") % names[1])
		msg_t = 5.0


func _update_hud() -> void:
	for t in 2:
		bars[t].value = units[t].size()
		var est := int(minf(troops[t], soldiers_alive(t) * scale_troops))
		if palace:
			bar_lbls[t].text = Lang.fix(Lang.t("%s%s　%d 人") % [names[t], (Lang.t("禁卫") if hall.grand else Lang.t("亲卫")) if t == 1 else Lang.t("军"), units[t].size()])
		elif b.type == "bandit":
			bar_lbls[t].text = Lang.fix(Lang.t("%s　%d 人") % [names[t] if t == 1 else "山贼", units[t].size()])
		else:
			bar_lbls[t].text = Lang.fix(Lang.t("%s军　%d") % [names[t], est])
	kills_lbl.text = Lang.fix(Lang.t("斩获 %d") % kills)
	if is_instance_valid(player):
		hp_bar.max_value = player.max_hp
		hp_bar.value = maxf(0.0, player.hp)
		hp_lbl.text = Lang.fix("%s　%d / %d" % [Game.player.name, int(maxf(0.0, player.hp)), int(player.max_hp)])
	if is_instance_valid(player):
		var mv_name := ""
		if player.attack_t >= 0.0:
			mv_name = "　" + str(FighterScript.MOVES[player.cur_move].cn)
		weapon_lbl.text = Lang.fix("【%s】%s%s" % [Game.item_name(player.item_id), Lang.t("·骑") if player.mounted else "", mv_name])
	if siege and is_instance_valid(player):
		var gate_s := Lang.t("城门已破") if gate_open else Lang.t("城门 %d%%") % int(maxf(0.0, gate_hp) / GATE_HP * 100.0)
		var zs: String = zone_name(player.zone)
		if pteam == 0:
			obj_lbl.text = Lang.fix("【%s】%s　%s" % [zs, [Lang.t("击退出城之敌，走到云梯下登城，或砍破城门"), Lang.t("肃清城头，从内侧马道下城"), Lang.t("巷战：杀向府衙，击溃守军")][player.zone], gate_s])
		else:
			obj_lbl.text = Lang.fix("【%s】%s　%s" % [zs, [Lang.t("城外迎敌；可从云梯或城门回城"), Lang.t("守住城头，把登城之敌砍下去"), Lang.t("巷战：守住府衙")][player.zone], gate_s])
	if squad_n > 0:
		order_lbl.text = Lang.fix(Lang.t("亲兵 %d 人：%s　　[1 冲锋　2 跟随　3 坚守]") % [squad_n, [Lang.t("冲锋"), Lang.t("跟随"), Lang.t("坚守")][squad_order]])
	else:
		order_lbl.text = Lang.fix("")


func _msg(s: String) -> void:
	if msg_lbl != null:
		msg_lbl.text = Lang.fix(s)
		msg_t = 3.0


func _panel(title: String, title_col: Color, body: String, buttons: Array) -> Control:
	var center := CenterContainer.new()
	hud.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.94)
	sb.border_color = Color("#8a6d3b")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(22)
	pc.add_theme_stylebox_override("panel", sb)
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	pc.add_child(vb)
	var t := Label.new()
	t.text = Lang.fix(title)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 52)
	t.add_theme_color_override("font_color", title_col)
	vb.add_child(t)
	var l := Label.new()
	l.text = Lang.fix(body)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(620, 0)
	l.add_theme_font_size_override("font_size", 20)
	vb.add_child(l)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	vb.add_child(hb)
	for bt in buttons:
		var btn := Button.new()
		btn.text = Lang.fix(bt[0])
		btn.custom_minimum_size = Vector2(180, 46)
		btn.pressed.connect(bt[1])
		hb.add_child(btn)
	hb.get_child(0).grab_focus.call_deferred()
	return center
