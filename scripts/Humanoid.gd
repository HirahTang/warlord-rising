extends Node3D
# 关节化的人物模型（髋-胸-头、肩-肘-手、髋-膝-脚）+ 基于关键姿势的程序化动作。
# 模型朝向 -Z。手中兵器沿手部局部 -Z 方向伸出。

static var _meshes := {}
static var _mats := {}

# 姿势 = [右肩x, 右肩y, 右肩z, 右肘, 右腕, 腰前倾, 腰扭转]
# 肩x 正值=手臂前举；肩y 正值=向左横摆；肘 正值=屈肘；腕 -PI/2=兵器与前臂成一线
const GUARD := {
	"dao": [0.55, -0.25, 0.15, 1.0, -0.6, 0.05, 0.0],
	"saber": [0.55, -0.25, 0.15, 1.0, -0.6, 0.05, 0.0],
	"spear": [0.15, -0.2, 0.1, 1.25, -1.4, 0.05, -0.25],
	"glaive": [0.4, -0.2, 0.1, 1.0, -0.75, 0.05, -0.2],
	"ji": [0.4, -0.2, 0.1, 1.0, -0.75, 0.05, -0.2],
	"bow": [0.2, 0.0, 0.1, 0.5, -0.8, 0.0, 0.0],
}
# 每招两个关键姿势：[蓄势, 收势]
const ANIMS := {
	"slash_r": [[1.5, -1.5, 0.0, 0.5, -1.2, 0.0, -0.6], [1.3, 1.0, 0.0, 0.25, -1.3, 0.12, 0.6]],
	"slash_l": [[1.5, 1.3, 0.0, 0.9, -1.2, 0.0, 0.6], [1.35, -1.3, 0.0, 0.15, -1.3, 0.12, -0.6]],
	"chop": [[2.9, 0.0, 0.0, 0.7, -0.3, -0.2, 0.0], [0.75, 0.0, 0.0, 0.15, -0.55, 0.35, 0.0]],
	"upper": [[-0.5, -0.3, 0.0, 0.3, -1.0, 0.25, -0.3], [2.3, 0.2, 0.0, 0.3, -0.9, -0.15, 0.3]],
	"thrust": [[-0.7, -0.15, 0.0, 1.8, -1.1, 0.0, -0.5], [1.35, 0.1, 0.0, 0.2, -1.55, 0.3, 0.35]],
	"dash": [[-0.7, -0.15, 0.0, 1.8, -1.1, 0.1, -0.5], [1.4, 0.1, 0.0, 0.1, -1.55, 0.4, 0.35]],
	"sweep": [[1.2, -1.9, 0.0, 0.3, -1.4, 0.1, -0.9], [1.2, 1.3, 0.0, 0.2, -1.4, 0.2, 0.9]],
	"spin": [[1.4, -1.2, 0.0, 0.2, -1.4, 0.0, -0.4], [1.4, -0.9, 0.0, 0.15, -1.4, 0.05, -0.2]],
	"shoot": [[1.5, 0.9, 0.0, 0.2, 0.0, 0.0, -1.0], [1.5, 0.35, 0.0, 2.1, 0.0, 0.0, -1.0]],
	"power_shot": [[1.5, 0.9, 0.0, 0.2, 0.0, 0.0, -1.0], [1.55, 0.25, 0.0, 2.3, 0.0, -0.08, -1.05]],
}

var hips: Node3D
var chest: Node3D
var head: Node3D
var thigh_l: Node3D
var thigh_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var sh_l: Node3D
var sh_r: Node3D
var el_l: Node3D
var el_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var weapon_node: Node3D
var off_node: Node3D
var shield_node: Node3D
var back_node: Node3D
var torso_mat: StandardMaterial3D
var color := Color.WHITE
var kind := "soldier"
var weapon := "dao"
var has_shield := false
var shield_kind := "round"
var look := {}
var two_handed := false
var phase := 0.0
var flinch := 0.0
var cur: Array = [0.5, 0.0, 0.1, 0.8, -0.6, 0.0, 0.0]
var mounted := false
var horse: Node3D
var horse_neck: Node3D
var horse_legs: Array = []
var horse_knees: Array = []
var _flash: Tween


# ───────────── 网格与材质缓存 ─────────────

static func box(sz: Vector3) -> Mesh:
	var k := "b%s" % sz
	if not _meshes.has(k):
		var m := BoxMesh.new()
		m.size = sz
		_meshes[k] = m
	return _meshes[k]


static func cyl(r_top: float, r_bot: float, h: float, seg := 8) -> Mesh:
	var k := "c%f_%f_%f_%d" % [r_top, r_bot, h, seg]
	if not _meshes.has(k):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bot
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		_meshes[k] = m
	return _meshes[k]


static func ball(r: float) -> Mesh:
	var k := "s%f" % r
	if not _meshes.has(k):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2
		m.radial_segments = 12
		m.rings = 7
		_meshes[k] = m
	return _meshes[k]


static func capsule(r: float, h: float) -> Mesh:
	var k := "p%f_%f" % [r, h]
	if not _meshes.has(k):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 8
		m.rings = 3
		_meshes[k] = m
	return _meshes[k]


static func mat(c: Color, metallic := 0.0) -> StandardMaterial3D:
	var k := "%s_%f" % [c.to_html(), metallic]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metallic
		m.roughness = 0.4 if metallic > 0.0 else 0.9
		_mats[k] = m
	return _mats[k]


func part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func joint(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# ───────────── 搭建 ─────────────

# 各地各代的装束。cul 文化区，era 年代。
static func look_for(cul: String, era: String) -> Dictionary:
	var d := {"skin": "#e2b88e", "shin": "iron", "arm": "iron", "skirt": "plates", "chest": "mirror", "sh": "ball",
		"metal": "#3a3c44", "helm": "han", "helm_g": "han_g", "shield": "round", "wrap": false, "feather": false}
	var late := era == "suitang" or era == "wudai"
	match cul:
		"han", "korea":
			if era == "zhanguo":      # 皮甲、发髻、青铜胄
				d.merge({"shin": "leather", "arm": "leather", "chest": "leather", "sh": "none", "metal": "#9a7a44", "helm": "bun", "helm_g": "pheasant"}, true)
			elif era == "suitang":    # 明光铠
				d.merge({"chest": "mirror2", "sh": "big"}, true)
			elif era == "wudai":      # 范阳笠、凤翅盔
				d.merge({"chest": "mirror2", "sh": "big", "helm": "li", "helm_g": "wing"}, true)
			d["feather"] = cul == "korea"
		"wa":
			if era == "zhanguo" or era == "sanguo":      # 弥生：贯头衣、美豆良、木盾
				d.merge({"shin": "skin", "arm": "skin", "chest": "none", "sh": "none", "skirt": "dhoti", "helm": "mizura", "helm_g": "bronze_g", "shield": "long", "metal": "#9a7a44"}, true)
			elif era == "suitang":                        # 古坟：短甲
				d.merge({"chest": "cuirass", "sh": "none", "shield": "long", "helm_g": "bronze_g"}, true)
			else:                                         # 平安：大铠、星兜
				d.merge({"chest": "leather", "sh": "sode", "helm": "kabuto", "helm_g": "kabuto_g", "shield": "none", "shin": "leather"}, true)
		"steppe":      # 皮袍、毡帽
			d.merge({"skin": "#d8a878", "shin": "leather", "arm": "leather", "chest": "leather", "sh": "none", "helm": "fur", "helm_g": "fur_g", "skirt": "long"}, true)
		"xiyu":        # 尖顶毡帽、长袍
			d.merge({"skin": "#dcae84", "shin": "cloth", "arm": "cloth", "chest": "scale", "sh": "none", "helm": "felt", "helm_g": "cone_g", "skirt": "long"}, true)
		"tibet":       # 长身札甲
			d.merge({"skin": "#c99a6e", "chest": "scale", "helm": "fur", "helm_g": "cone_g", "skirt": "long", "shin": "leather"}, true)
		"india":       # 缠头、白裙、赤足
			d.merge({"skin": "#a9774c", "shin": "skin", "arm": "skin", "chest": "none", "sh": "none", "helm": "turban", "helm_g": "turban_g", "skirt": "dhoti"}, true)
		"sea":         # 纱笼、长木盾、金冠
			d.merge({"skin": "#a87a50", "shin": "skin", "arm": "skin", "chest": "none", "sh": "none", "helm": "band", "helm_g": "crown", "skirt": "sarong", "shield": "long"}, true)
		"persia":
			d.merge({"skin": "#d2a274", "shin": "cloth", "arm": "iron", "chest": "scale", "sh": "none", "helm": "cone", "helm_g": "cone_g", "skirt": "long", "shield": "oval"}, true)
			if era == "zhanguo":
				d.merge({"helm": "bashlyk", "chest": "leather", "arm": "cloth"}, true)
			elif era == "suitang":
				d["helm_g"] = "korymbos"
			elif era == "wudai":
				d["wrap"] = true
		"arab":        # 缠头、长袍
			d.merge({"skin": "#c99766", "shin": "cloth", "arm": "cloth", "chest": "none", "sh": "none", "helm": "turban", "helm_g": "cone_g", "skirt": "robe", "wrap": true}, true)
		"rome":
			if era == "zhanguo":      # 希腊化：青铜盔、胸甲、大圆盾
				d.merge({"skin": "#dfb48c", "metal": "#b08a4a", "shin": "bronze", "arm": "skin", "chest": "cuirass", "sh": "none", "helm": "corinth", "helm_g": "crest_t", "skirt": "kilt", "shield": "big"}, true)
			elif era == "sanguo":     # 罗马军团：环片甲、方盾
				d.merge({"skin": "#dfb48c", "metal": "#8a8e96", "shin": "skin", "arm": "skin", "chest": "bands", "sh": "bands", "helm": "gallic", "helm_g": "crest_t", "skirt": "kilt", "shield": "rect"}, true)
			else:                     # 拜占庭：尖盔、札甲、长盾
				d.merge({"skin": "#dfb48c", "metal": "#8a8e96", "shin": "leather", "arm": "cloth", "chest": "scale", "sh": "none", "helm": "cone", "helm_g": "cone_g", "skirt": "long", "shield": "oval"}, true)
		"north":
			if late:      # 法兰克、维京：锁子甲、护鼻盔、圆盾
				d.merge({"skin": "#e6c0a0", "hair": "#8a5a2a", "metal": "#8a8e96", "shin": "leather", "arm": "cloth", "chest": "scale", "sh": "none", "helm": "nasal", "helm_g": "cone_g", "skirt": "long"}, true)
			else:         # 凯尔特、日耳曼：披发、格子裤、长木盾
				d.merge({"skin": "#e6c0a0", "hair": "#a8742a", "metal": "#9a7a44", "shin": "cloth", "arm": "skin", "chest": "none", "sh": "none", "helm": "wild", "helm_g": "bronze_g", "skirt": "sarong", "shield": "oval"}, true)
	if late and cul == "india":
		d["helm_g"] = "turban_g"
	return d


func build(p_color: Color, p_kind: String, p_weapon: String, gname := "", p_mounted := false, horse_col := Color("#6b4a2b"), p_look := "") -> void:
	color = p_color
	kind = p_kind
	mounted = p_mounted
	var lk := p_look.split(":")
	look = look_for(lk[0], lk[1]) if lk.size() >= 2 else look_for("han", "sanguo")
	var elite := kind == "general" or kind == "player"
	if elite:      # 将领总是披甲的
		if look.chest == "none":
			look["chest"] = "scale"
		if look.sh == "none":
			look["sh"] = "ball"
		if look.shin == "skin":
			look["shin"] = "leather"
	shield_kind = str(look.shield)
	var skin_c := Color(str(look.skin))
	var beard := 0.0
	if kind == "general":
		beard = [0.0, 0.1, 0.14, 0.0][absi(hash(gname)) % 4]
	if gname == "关羽":
		skin_c = Color("#b8553c")
		beard = 0.34
	elif gname == "张飞":
		skin_c = Color("#9a6a48")
		beard = 0.16
	var skin := mat(skin_c)
	var hair := mat(Color(str(look.get("hair", "#1c1a1a"))))
	var iron := mat(Color(str(look.metal)), 0.7)
	var steel := mat(Color("#cfd3da"), 0.85)
	var gold := mat(Color("#d9b04a"), 0.85)
	var leather := mat(Color("#4a3322"))
	var white := mat(Color("#ece4d2"))
	var cloth := mat(color.darkened(0.5))
	var limb := mat(color.darkened(0.12))
	var plate := mat(color.lightened(0.25), 0.3) if kind != "bandit" else mat(Color("#6a5a48"))
	var trim := gold if elite else iron
	var by := {"iron": iron, "bronze": iron, "leather": leather, "skin": skin, "cloth": cloth}
	var shin_m: Material = leather if kind == "bandit" else by[str(look.shin)]
	var arm_m: Material = leather if kind == "bandit" else by[str(look.arm)]
	var sk := str(look.skirt)
	var thigh_m: Material = cloth
	if kind != "bandit":
		if sk == "robe" or sk == "dhoti":
			thigh_m = white
		elif (sk == "kilt" or sk == "sarong") and look.shin == "skin":
			thigh_m = skin
	torso_mat = StandardMaterial3D.new()
	torso_mat.albedo_color = color
	torso_mat.roughness = 0.8
	torso_mat.emission_enabled = true
	torso_mat.emission = Color.WHITE
	torso_mat.emission_energy_multiplier = 0.0

	hips = joint(self, Vector3(0, 0.95, 0))
	# 腿：大腿-小腿-靴（靴尖朝前）
	thigh_l = joint(hips, Vector3(-0.11, 0, 0))
	thigh_r = joint(hips, Vector3(0.11, 0, 0))
	for th in [thigh_l, thigh_r]:
		part(th, capsule(0.085, 0.5), thigh_m, Vector3(0, -0.22, 0))
		var sh := joint(th, Vector3(0, -0.44, 0))
		part(sh, capsule(0.068, 0.46), shin_m, Vector3(0, -0.2, 0))
		part(sh, box(Vector3(0.11, 0.09, 0.27)), leather, Vector3(0, -0.46, -0.06))
		if th == thigh_l:
			shin_l = sh
		else:
			shin_r = sh
	# 腰带与下裳：裙甲 / 长袍 / 短裙 / 纱笼
	part(hips, box(Vector3(0.46, 0.08, 0.29)), leather, Vector3(0, 0.06, 0))
	if kind == "bandit":
		part(hips, box(Vector3(0.44, 0.22, 0.27)), cloth, Vector3(0, -0.08, 0))
	else:
		var ln: float = {"plates": 0.3, "long": 0.44, "robe": 0.56, "kilt": 0.26, "dhoti": 0.3, "sarong": 0.36}[sk]
		var fm: Material = plate
		var bm: Material = cloth
		var fw := 0.2
		if sk == "robe" or sk == "dhoti" or sk == "kilt":
			fm = white
			bm = white
			fw = 0.42
		elif sk == "sarong":
			fm = cloth
			fw = 0.42
		elif sk == "long":
			bm = plate
			fw = 0.3
		part(hips, box(Vector3(fw, ln, 0.03)), fm, Vector3(0, 0.02 - ln / 2, -0.14))
		part(hips, box(Vector3(fw + 0.02, ln - 0.02, 0.03)), bm, Vector3(0, 0.02 - ln / 2, 0.14))
		part(hips, box(Vector3(0.03, ln - 0.02, 0.2)), fm, Vector3(-0.23, 0.02 - ln / 2, 0))
		part(hips, box(Vector3(0.03, ln - 0.02, 0.2)), fm, Vector3(0.23, 0.02 - ln / 2, 0))
		if sk == "kilt":      # 皮条裙上压一道本色
			part(hips, box(Vector3(0.44, 0.07, 0.3)), limb, Vector3(0, -0.03, 0))

	chest = joint(hips, Vector3(0, 0.1, 0))
	part(chest, box(Vector3(0.44, 0.5, 0.26)), torso_mat, Vector3(0, 0.27, 0))
	if kind == "bandit":
		part(chest, box(Vector3(0.1, 0.5, 0.02)), skin, Vector3(0, 0.28, -0.135))                 # 敞怀
	else:
		var scale_m := mat(Color(str(look.metal)).lightened(0.25), 0.6)
		match str(look.chest):
			"mirror":
				part(chest, box(Vector3(0.36, 0.36, 0.03)), plate, Vector3(0, 0.3, -0.135))               # 胸甲
				part(chest, cyl(0.075, 0.075, 0.025, 12), steel, Vector3(0, 0.33, -0.155), Vector3(PI / 2, 0, 0))   # 护心镜
			"mirror2":
				part(chest, box(Vector3(0.38, 0.38, 0.03)), plate, Vector3(0, 0.3, -0.135))
				for sx in [-1.0, 1.0]:
					part(chest, cyl(0.065, 0.065, 0.025, 12), steel, Vector3(sx * 0.095, 0.36, -0.155), Vector3(PI / 2, 0, 0))
				part(chest, box(Vector3(0.46, 0.05, 0.28)), trim, Vector3(0, 0.12, 0))
			"leather":
				part(chest, box(Vector3(0.38, 0.4, 0.03)), mat(color.lerp(Color("#5a3a22"), 0.55)), Vector3(0, 0.29, -0.135))
				for y in [0.2, 0.32, 0.44]:
					part(chest, box(Vector3(0.38, 0.012, 0.035)), leather, Vector3(0, y, -0.136))
			"scale":
				part(chest, box(Vector3(0.4, 0.42, 0.03)), scale_m, Vector3(0, 0.29, -0.135))
				part(chest, box(Vector3(0.4, 0.42, 0.03)), scale_m, Vector3(0, 0.29, 0.135))
				part(chest, box(Vector3(0.46, 0.05, 0.28)), trim, Vector3(0, 0.1, 0))
			"bands":
				for y in [0.15, 0.26, 0.37]:
					part(chest, box(Vector3(0.47, 0.095, 0.29)), steel, Vector3(0, y, 0))
			"cuirass":
				part(chest, box(Vector3(0.42, 0.46, 0.035)), iron, Vector3(0, 0.28, -0.135))
				part(chest, box(Vector3(0.42, 0.46, 0.035)), iron, Vector3(0, 0.28, 0.135))
				for sx in [-1.0, 1.0]:
					part(chest, ball(0.075), iron, Vector3(sx * 0.095, 0.39, -0.15), Vector3.ZERO, Vector3(1, 0.85, 0.4))
			_:      # 不披甲：斜挎一条布带
				part(chest, box(Vector3(0.09, 0.6, 0.02)), white, Vector3(0, 0.28, -0.136), Vector3(0, 0, 0.62))
		match str(look.sh):
			"ball":
				for sx in [-1.0, 1.0]:
					part(chest, ball(0.115), trim, Vector3(sx * 0.28, 0.5, 0), Vector3.ZERO, Vector3(1, 0.6, 1.1))
			"big":
				for sx in [-1.0, 1.0]:
					part(chest, ball(0.13), trim, Vector3(sx * 0.29, 0.5, 0), Vector3.ZERO, Vector3(1.05, 0.62, 1.15))
					part(chest, box(Vector3(0.05, 0.16, 0.2)), plate, Vector3(sx * 0.34, 0.38, 0))
			"sode":
				for sx in [-1.0, 1.0]:
					part(chest, box(Vector3(0.05, 0.3, 0.26)), plate, Vector3(sx * 0.33, 0.38, 0))
					for y in [0.3, 0.4]:
						part(chest, box(Vector3(0.055, 0.02, 0.265)), trim, Vector3(sx * 0.33, y, 0))
			"bands":
				for sx in [-1.0, 1.0]:
					for k in 2:
						part(chest, box(Vector3(0.17, 0.035, 0.3)), steel, Vector3(sx * 0.27, 0.53 - k * 0.05, 0), Vector3(0, 0, -sx * 0.25))
	part(chest, cyl(0.05, 0.055, 0.1), skin, Vector3(0, 0.56, 0))
	back_node = joint(chest, Vector3(0, 0.3, 0.14))
	if elite:
		var cape_c := Color("#b01818") if kind == "player" else color.darkened(0.35)
		part(back_node, box(Vector3(0.54, 0.95, 0.03)), mat(cape_c), Vector3(0, -0.22, 0.04), Vector3(-0.12, 0, 0))

	# 头：五官朝 -Z
	head = joint(chest, Vector3(0, 0.71, 0))
	part(head, ball(0.13), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.08, 1))
	part(head, ball(0.021), hair, Vector3(-0.05, 0.025, -0.116))
	part(head, ball(0.021), hair, Vector3(0.05, 0.025, -0.116))
	part(head, box(Vector3(0.06, 0.012, 0.02)), hair, Vector3(-0.05, 0.06, -0.118), Vector3(0, 0, -0.2))
	part(head, box(Vector3(0.06, 0.012, 0.02)), hair, Vector3(0.05, 0.06, -0.118), Vector3(0, 0, 0.2))
	part(head, box(Vector3(0.028, 0.05, 0.035)), skin, Vector3(0, -0.01, -0.13))
	part(head, box(Vector3(0.06, 0.012, 0.01)), mat(Color("#7a3a30")), Vector3(0, -0.062, -0.118))
	if beard > 0.0:
		part(head, box(Vector3(0.13, beard, 0.05)), hair, Vector3(0, -0.09 - beard / 2, -0.095))
		part(head, box(Vector3(0.1, 0.02, 0.03)), hair, Vector3(0, -0.045, -0.122))
	match kind:
		"bandit":
			part(head, ball(0.132), hair, Vector3(0, 0.03, 0.02), Vector3.ZERO, Vector3(1, 1, 1))
			part(head, ball(0.05), hair, Vector3(0, 0.17, 0.02))
			part(head, cyl(0.134, 0.134, 0.04, 12), mat(Color("#8a2a1e")), Vector3(0, 0.065, 0))
		"soldier":
			_headgear(str(look.helm), iron, gold, mat(Color("#c22a2a")), hair)
		_:
			_headgear(str(look.helm_g), steel if kind == "player" else iron, gold, mat(Color("#ffd24a") if kind == "player" else Color("#d22a2a")), hair)

	# 手臂：肩-肘-手
	sh_l = joint(chest, Vector3(-0.3, 0.47, 0))
	sh_r = joint(chest, Vector3(0.3, 0.47, 0))
	for s in [sh_l, sh_r]:
		part(s, capsule(0.062, 0.36), limb, Vector3(0, -0.15, 0))
		var e := joint(s, Vector3(0, -0.3, 0))
		part(e, capsule(0.052, 0.32), arm_m, Vector3(0, -0.13, 0))
		var h := joint(e, Vector3(0, -0.29, 0))
		part(h, ball(0.055), skin, Vector3.ZERO)
		if s == sh_l:
			el_l = e
			hand_l = h
		else:
			el_r = e
			hand_r = h
	# 细小部件不投影，省渲染开销
	for n in [head, hips]:
		for c in n.get_children():
			if c is MeshInstance3D:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weapon_node = joint(hand_r, Vector3.ZERO)
	off_node = joint(hand_l, Vector3.ZERO)
	shield_node = joint(el_l, Vector3(-0.09, -0.16, 0))
	set_weapon(p_weapon)
	if mounted:
		_build_horse(horse_col)


# 头上戴的：hm 盔的材质，plume 缨的材质
func _headgear(id: String, hm: Material, gold: Material, plume: Material, hair: Material) -> void:
	var white := mat(Color("#ece4d2"))
	var fur := mat(Color("#8a6a48"))
	var brown := mat(Color("#5a4028"))
	var mail := mat(Color("#2e3036"), 0.5)
	var wrap: bool = look.get("wrap", false)
	match id:
		"han":
			part(head, ball(0.143), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1, 0.85, 1.05))
			part(head, cyl(0.175, 0.185, 0.02, 12), hm, Vector3(0, 0.05, -0.01))
			part(head, box(Vector3(0.24, 0.15, 0.03)), hm, Vector3(0, -0.04, 0.125))     # 护颈（背面）
			part(head, ball(0.03), plume, Vector3(0, 0.18, 0.01))
		"bun":      # 发髻、皮弁
			part(head, ball(0.134), hair, Vector3(0, 0.035, 0.02))
			part(head, ball(0.14), brown, Vector3(0, 0.07, 0.02), Vector3.ZERO, Vector3(1, 0.62, 1.02))
			part(head, ball(0.045), hair, Vector3(0, 0.185, 0.03))
			part(head, box(Vector3(0.05, 0.02, 0.12)), plume, Vector3(0, 0.175, 0.03))
		"li":       # 范阳笠
			part(head, ball(0.14), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1, 0.8, 1.05))
			part(head, cyl(0.06, 0.27, 0.08, 14), mat(Color("#3a3028")), Vector3(0, 0.12, 0))
			part(head, ball(0.035), plume, Vector3(0, 0.19, 0))
			part(head, box(Vector3(0.24, 0.14, 0.03)), hm, Vector3(0, -0.04, 0.125))
		"fur":      # 毡帽皮檐
			part(head, ball(0.146), brown, Vector3(0, 0.07, 0.01), Vector3.ZERO, Vector3(1, 0.9, 1.05))
			part(head, cyl(0.165, 0.165, 0.07, 12), fur, Vector3(0, 0.045, 0))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.03, 0.15, 0.1)), fur, Vector3(sx * 0.14, -0.05, 0.02))
		"felt":     # 尖顶毡帽
			part(head, cyl(0.0, 0.148, 0.3, 10), white, Vector3(0, 0.2, 0.01))
			part(head, cyl(0.155, 0.155, 0.035, 12), plume, Vector3(0, 0.05, 0))
			part(head, ball(0.132), hair, Vector3(0, 0.0, 0.03))
		"turban":   # 缠头
			part(head, ball(0.158), white, Vector3(0, 0.085, 0.01), Vector3.ZERO, Vector3(1.05, 0.62, 1.1))
			part(head, ball(0.105), white, Vector3(0, 0.15, 0.0), Vector3.ZERO, Vector3(1, 0.6, 1))
			part(head, ball(0.022), plume, Vector3(0, 0.1, -0.165))
			if wrap:
				part(head, box(Vector3(0.26, 0.2, 0.03)), white, Vector3(0, -0.06, 0.125))
		"band":     # 束发抹额
			part(head, ball(0.134), hair, Vector3(0, 0.035, 0.02))
			part(head, ball(0.05), hair, Vector3(0, 0.02, 0.15))
			part(head, cyl(0.136, 0.136, 0.04, 12), plume, Vector3(0, 0.065, 0))
		"corinth":  # 青铜盔，纵向马鬃冠
			part(head, ball(0.146), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1, 0.92, 1.05))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.03, 0.14, 0.1)), hm, Vector3(sx * 0.13, -0.035, -0.02))
			part(head, box(Vector3(0.02, 0.1, 0.02)), hm, Vector3(0, 0.0, -0.142))
			part(head, box(Vector3(0.04, 0.12, 0.34)), plume, Vector3(0, 0.21, 0.04))
		"gallic":   # 罗马盔：护颊、护颈
			part(head, ball(0.146), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1, 0.88, 1.05))
			part(head, box(Vector3(0.25, 0.025, 0.04)), hm, Vector3(0, 0.075, -0.135))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.03, 0.14, 0.1)), hm, Vector3(sx * 0.13, -0.035, -0.02))
			part(head, box(Vector3(0.3, 0.03, 0.13)), hm, Vector3(0, -0.04, 0.17), Vector3(0.35, 0, 0))
		"cone":     # 尖顶铁盔，垂锁子护颈
			part(head, ball(0.146), hm, Vector3(0, 0.035, 0.01), Vector3.ZERO, Vector3(1, 0.75, 1.05))
			part(head, cyl(0.02, 0.146, 0.2, 12), hm, Vector3(0, 0.15, 0.01))
			part(head, box(Vector3(0.27, 0.18, 0.03)), mail, Vector3(0, -0.06, 0.125))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.03, 0.15, 0.12)), mail, Vector3(sx * 0.135, -0.05, 0.05))
			if wrap:
				part(head, cyl(0.165, 0.165, 0.06, 12), white, Vector3(0, 0.05, 0.005))
			part(head, ball(0.025), plume, Vector3(0, 0.26, 0.01))
		"wild":     # 披发，唇上两撇
			part(head, ball(0.138), hair, Vector3(0, 0.04, 0.025), Vector3.ZERO, Vector3(1, 1.02, 1.05))
			part(head, box(Vector3(0.24, 0.2, 0.05)), hair, Vector3(0, -0.08, 0.12))
			part(head, box(Vector3(0.1, 0.02, 0.03)), hair, Vector3(0, -0.045, -0.122))
			part(head, cyl(0.136, 0.136, 0.025, 12), plume, Vector3(0, 0.07, 0))
		"nasal":    # 护鼻尖盔，垂锁子护颈
			part(head, ball(0.146), hm, Vector3(0, 0.035, 0.01), Vector3.ZERO, Vector3(1, 0.78, 1.05))
			part(head, cyl(0.03, 0.146, 0.16, 12), hm, Vector3(0, 0.14, 0.01))
			part(head, box(Vector3(0.022, 0.12, 0.02)), hm, Vector3(0, 0.0, -0.142))
			part(head, box(Vector3(0.27, 0.18, 0.03)), mail, Vector3(0, -0.06, 0.125))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.03, 0.15, 0.12)), mail, Vector3(sx * 0.135, -0.05, 0.05))
		"bashlyk":  # 软帽，垂护颊
			part(head, ball(0.15), white, Vector3(0, 0.06, 0.02), Vector3.ZERO, Vector3(1, 0.95, 1.05))
			part(head, ball(0.06), white, Vector3(0, 0.18, -0.04))
			part(head, box(Vector3(0.26, 0.18, 0.03)), white, Vector3(0, -0.06, 0.125))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.03, 0.16, 0.1)), white, Vector3(sx * 0.135, -0.05, 0.02))
		"mizura":   # 美豆良
			part(head, ball(0.134), hair, Vector3(0, 0.035, 0.02))
			for sx in [-1.0, 1.0]:
				part(head, ball(0.045), hair, Vector3(sx * 0.14, -0.05, 0.0), Vector3.ZERO, Vector3(0.8, 1.3, 0.8))
			part(head, cyl(0.136, 0.136, 0.03, 12), plume, Vector3(0, 0.07, 0))
		"kabuto", "kabuto_g":      # 星兜与𩊱
			part(head, ball(0.146), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1, 0.85, 1.05))
			part(head, box(Vector3(0.2, 0.015, 0.07)), hm, Vector3(0, 0.07, -0.15))
			part(head, box(Vector3(0.36, 0.11, 0.05)), mail, Vector3(0, -0.02, 0.16), Vector3(0.5, 0, 0))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.05, 0.11, 0.22)), mail, Vector3(sx * 0.18, -0.02, 0.04), Vector3(0, 0, sx * 0.5))
			if id == "kabuto_g":
				for sx in [-1.0, 1.0]:
					part(head, box(Vector3(0.022, 0.22, 0.012)), gold, Vector3(sx * 0.07, 0.22, -0.13), Vector3(0, 0, -sx * 0.38))
				part(head, ball(0.03), plume, Vector3(0, 0.2, 0.0))
		"pheasant": # 青铜胄，双鹖尾
			part(head, ball(0.146), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1, 0.9, 1.05))
			part(head, cyl(0.15, 0.15, 0.03, 12), gold, Vector3(0, 0.04, 0))
			part(head, box(Vector3(0.26, 0.16, 0.03)), hm, Vector3(0, -0.04, 0.13))
			for sx in [-1.0, 1.0]:
				part(head, cyl(0.004, 0.014, 0.4, 5), mat(Color("#6a4a2a")), Vector3(sx * 0.09, 0.34, 0.05), Vector3(-0.2, 0, -sx * 0.3))
			part(head, ball(0.03), plume, Vector3(0, 0.19, 0.01))
		"fur_g":    # 铁盔皮檐，垂马尾
			part(head, ball(0.146), hm, Vector3(0, 0.04, 0.01), Vector3.ZERO, Vector3(1, 0.78, 1.05))
			part(head, cyl(0.02, 0.146, 0.18, 12), hm, Vector3(0, 0.15, 0.01))
			part(head, cyl(0.168, 0.168, 0.065, 12), fur, Vector3(0, 0.045, 0))
			part(head, cyl(0.03, 0.006, 0.24, 6), plume, Vector3(0, 0.3, 0.04), Vector3(-0.5, 0, 0))
			part(head, box(Vector3(0.26, 0.16, 0.03)), fur, Vector3(0, -0.05, 0.13))
		"cone_g":   # 鎏金尖盔
			part(head, ball(0.146), hm, Vector3(0, 0.035, 0.01), Vector3.ZERO, Vector3(1, 0.75, 1.05))
			part(head, cyl(0.02, 0.146, 0.22, 12), hm, Vector3(0, 0.16, 0.01))
			part(head, cyl(0.152, 0.152, 0.035, 12), gold, Vector3(0, 0.045, 0.005))
			part(head, box(Vector3(0.27, 0.18, 0.03)), mail, Vector3(0, -0.06, 0.125))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.03, 0.15, 0.12)), mail, Vector3(sx * 0.135, -0.05, 0.05))
			if wrap:
				part(head, cyl(0.168, 0.168, 0.06, 12), white, Vector3(0, 0.09, 0.005))
			part(head, cyl(0.008, 0.014, 0.1), gold, Vector3(0, 0.31, 0.01))
			part(head, ball(0.05), plume, Vector3(0, 0.38, 0.03), Vector3.ZERO, Vector3(0.7, 1.5, 1.2))
		"turban_g": # 大缠头，金箍，额前翎
			part(head, ball(0.165), white, Vector3(0, 0.09, 0.01), Vector3.ZERO, Vector3(1.05, 0.66, 1.1))
			part(head, ball(0.11), white, Vector3(0, 0.17, 0.0), Vector3.ZERO, Vector3(1, 0.6, 1))
			part(head, cyl(0.168, 0.168, 0.03, 12), gold, Vector3(0, 0.055, 0.005))
			part(head, ball(0.03), gold, Vector3(0, 0.12, -0.17))
			part(head, ball(0.04), plume, Vector3(0, 0.25, -0.12), Vector3.ZERO, Vector3(0.6, 1.8, 0.8))
		"crown":    # 层叠金冠
			part(head, ball(0.134), hair, Vector3(0, 0.03, 0.02))
			part(head, cyl(0.1, 0.15, 0.1, 12), gold, Vector3(0, 0.11, 0.0))
			part(head, cyl(0.055, 0.1, 0.1, 12), gold, Vector3(0, 0.21, 0.0))
			part(head, cyl(0.0, 0.055, 0.16, 8), gold, Vector3(0, 0.34, 0.0))
			part(head, ball(0.022), plume, Vector3(0, 0.11, -0.14))
		"crest_t":  # 横冠
			part(head, ball(0.146), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1, 0.9, 1.05))
			part(head, cyl(0.15, 0.15, 0.03, 12), gold, Vector3(0, 0.04, 0))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.03, 0.14, 0.1)), hm, Vector3(sx * 0.13, -0.035, -0.02))
			part(head, box(Vector3(0.3, 0.03, 0.13)), hm, Vector3(0, -0.04, 0.17), Vector3(0.35, 0, 0))
			part(head, box(Vector3(0.4, 0.14, 0.045)), plume, Vector3(0, 0.23, 0.01))
		"korymbos": # 萨珊：盔顶大球，飘带
			part(head, ball(0.146), hm, Vector3(0, 0.035, 0.01), Vector3.ZERO, Vector3(1, 0.78, 1.05))
			part(head, cyl(0.152, 0.152, 0.05, 12), gold, Vector3(0, 0.05, 0.005))
			for k in 4:
				part(head, cyl(0.0, 0.03, 0.07, 4), gold, Vector3(cos(k * PI / 2) * 0.13, 0.11, sin(k * PI / 2) * 0.13))
			part(head, ball(0.085), plume, Vector3(0, 0.25, 0.0))
			part(head, box(Vector3(0.27, 0.18, 0.03)), mail, Vector3(0, -0.06, 0.125))
			for sx in [-1.0, 1.0]:
				part(head, box(Vector3(0.04, 0.3, 0.012)), white, Vector3(sx * 0.07, -0.1, 0.16), Vector3(0.3, 0, sx * 0.2))
		"bronze_g": # 青铜盔，小冠
			part(head, ball(0.146), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1, 0.9, 1.05))
			part(head, cyl(0.15, 0.15, 0.03, 12), gold, Vector3(0, 0.04, 0))
			part(head, box(Vector3(0.26, 0.16, 0.03)), hm, Vector3(0, -0.04, 0.13))
			part(head, box(Vector3(0.03, 0.1, 0.2)), plume, Vector3(0, 0.2, 0.02))
		_:          # han_g、wing：中原将盔
			part(head, ball(0.146), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1, 0.9, 1.05))
			part(head, cyl(0.15, 0.15, 0.03, 12), gold, Vector3(0, 0.04, 0))
			part(head, box(Vector3(0.03, 0.13, 0.11)), hm, Vector3(-0.13, -0.03, 0.01))    # 护颊
			part(head, box(Vector3(0.03, 0.13, 0.11)), hm, Vector3(0.13, -0.03, 0.01))
			part(head, box(Vector3(0.26, 0.16, 0.03)), hm, Vector3(0, -0.04, 0.13))
			part(head, cyl(0.012, 0.02, 0.12), gold, Vector3(0, 0.22, 0.01))
			part(head, ball(0.06), plume, Vector3(0, 0.3, 0.03), Vector3.ZERO, Vector3(0.7, 1.5, 1.2))
			if id == "wing":      # 凤翅
				for sx in [-1.0, 1.0]:
					part(head, box(Vector3(0.02, 0.1, 0.16)), gold, Vector3(sx * 0.155, 0.09, 0.03), Vector3(0.5, 0, -sx * 0.3))
	if look.get("feather", false):      # 鸟羽冠
		part(head, cyl(0.004, 0.012, 0.3, 5), mat(Color("#f2f2f2")), Vector3(0.06, 0.3, 0.02), Vector3(-0.15, 0, -0.2))
		part(head, cyl(0.004, 0.012, 0.3, 5), mat(Color("#f2f2f2")), Vector3(-0.06, 0.3, 0.02), Vector3(-0.15, 0, 0.2))


# 只有马、没有骑手（玩家下马后留在原地的战马）
func build_horse_only(team_col: Color, col: Color) -> void:
	color = team_col
	_build_horse(col)


# 兵种等级的外观：盔缨由白到红到金，高级的加护肩、披风和金盔箍
func set_rank(lv: int) -> void:
	if lv <= 0 or head == null:
		return
	var gold := mat(Color("#d9b04a"), 0.85)
	var plume := mat([Color.WHITE, Color("#f2f2f2"), Color("#e23a2a"), Color("#e23a2a"), Color("#ffd24a"), Color("#ffd24a")][clampi(lv, 0, 5)])
	var added: Array = []
	added.append(part(head, cyl(0.01, 0.018, 0.1 + 0.02 * lv, 6), mat(Color("#3a3c44"), 0.7), Vector3(0, 0.2, 0.01)))
	added.append(part(head, ball(0.04 + 0.006 * lv), plume, Vector3(0, 0.27 + 0.02 * lv, 0.03), Vector3.ZERO, Vector3(0.7, 1.4, 1.2)))
	if lv >= 3:
		for sx in [-1.0, 1.0]:
			added.append(part(chest, ball(0.135), mat(Color("#cfd3da"), 0.85), Vector3(sx * 0.29, 0.51, 0), Vector3.ZERO, Vector3(1.05, 0.62, 1.15)))
	if lv >= 4:
		added.append(part(chest, box(Vector3(0.46, 0.05, 0.28)), gold, Vector3(0, 0.1, 0)))
		added.append(part(back_node, box(Vector3(0.46, 0.7, 0.03)), mat(color.darkened(0.4)), Vector3(0, -0.12, 0.04), Vector3(-0.12, 0, 0)))
	if lv >= 5:
		added.append(part(head, cyl(0.152, 0.152, 0.03, 12), gold, Vector3(0, 0.04, 0)))
		for sx in [-1.0, 1.0]:
			added.append(part(chest, ball(0.14), gold, Vector3(sx * 0.29, 0.52, 0), Vector3.ZERO, Vector3(1.05, 0.5, 1.15)))
	for mi in added:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# 战马：头朝 -Z，骑手跨坐其上
func _build_horse(col: Color) -> void:
	horse = joint(self, Vector3.ZERO)
	var coat := mat(col)
	var dark := mat(col.darkened(0.6))
	var hoof := mat(Color("#1c1a1a"))
	var leather := mat(Color("#4a3322"))
	var cloth := mat(color.darkened(0.15))
	part(horse, capsule(0.3, 1.6), coat, Vector3(0, 1.05, 0.05), Vector3(PI / 2, 0, 0))
	part(horse, ball(0.33), coat, Vector3(0, 1.08, -0.52), Vector3.ZERO, Vector3(0.95, 1.05, 1))
	part(horse, ball(0.34), coat, Vector3(0, 1.1, 0.6))
	horse_neck = joint(horse, Vector3(0, 1.22, -0.66))
	var small: Array = []
	part(horse_neck, capsule(0.15, 0.8), coat, Vector3(0, 0.28, -0.17), Vector3(-0.55, 0, 0))
	small.append(part(horse_neck, box(Vector3(0.05, 0.62, 0.1)), dark, Vector3(0, 0.36, -0.03), Vector3(-0.55, 0, 0)))   # 鬃毛
	part(horse_neck, box(Vector3(0.17, 0.21, 0.5)), coat, Vector3(0, 0.6, -0.52), Vector3(-0.5, 0, 0))                   # 头
	small.append(part(horse_neck, box(Vector3(0.13, 0.14, 0.14)), dark, Vector3(0, 0.49, -0.74), Vector3(-0.5, 0, 0)))   # 口鼻
	for sx in [-1.0, 1.0]:
		small.append(part(horse_neck, cyl(0.0, 0.035, 0.11, 5), coat, Vector3(sx * 0.06, 0.8, -0.36)))
		small.append(part(horse_neck, ball(0.022), hoof, Vector3(sx * 0.088, 0.66, -0.47)))
	small.append(part(horse, capsule(0.05, 0.72), dark, Vector3(0, 0.9, 0.97), Vector3(-0.3, 0, 0)))                     # 尾
	# 鞍与鞍鞯（鞍鞯用本方颜色，便于分辨敌我）
	small.append(part(horse, box(Vector3(0.5, 0.07, 0.6)), leather, Vector3(0, 1.38, 0.02)))
	part(horse, box(Vector3(0.64, 0.03, 0.72)), cloth, Vector3(0, 1.345, 0.02))
	for sx in [-1.0, 1.0]:
		part(horse, box(Vector3(0.03, 0.38, 0.72)), cloth, Vector3(sx * 0.315, 1.16, 0.02))
	for z in [-0.5, 0.6]:
		for sx in [-1.0, 1.0]:
			var leg := joint(horse, Vector3(sx * 0.17, 0.86, z))
			part(leg, capsule(0.078, 0.5), coat, Vector3(0, -0.22, 0))
			var knee := joint(leg, Vector3(0, -0.44, 0))
			part(knee, capsule(0.055, 0.44), coat, Vector3(0, -0.2, 0))
			small.append(part(knee, box(Vector3(0.1, 0.08, 0.12)), hoof, Vector3(0, -0.39, 0)))
			horse_legs.append(leg)
			horse_knees.append(knee)
	for mi in small:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if thigh_l != null:
		thigh_l.rotation.z = -0.5
		thigh_r.rotation.z = 0.5


func set_weapon(w: String) -> void:
	weapon = w
	for n in [weapon_node, off_node, shield_node]:
		for c in n.get_children():
			c.queue_free()
	for c in back_node.get_children():
		if c.has_meta("quiver"):
			c.queue_free()
	var steel := mat(Color("#d6dae0"), 0.85)
	var wood := mat(Color("#6b4a2b"))
	var dark := mat(Color("#2b2b30"), 0.6)
	var red := mat(Color("#c22a2a"))
	var gold := mat(Color("#d9b04a"), 0.85)
	has_shield = w == "dao" and shield_kind != "none"
	two_handed = w == "spear" or w == "glaive" or w == "ji"
	var wn := weapon_node
	match w:
		"dao", "saber":
			part(wn, cyl(0.02, 0.02, 0.2), wood, Vector3(0, 0, 0.02), Vector3(PI / 2, 0, 0))
			part(wn, cyl(0.03, 0.03, 0.015, 10), gold, Vector3(0, 0, 0.13), Vector3(PI / 2, 0, 0))   # 环首
			part(wn, box(Vector3(0.1, 0.03, 0.025)), dark, Vector3(0, 0, -0.09))
			part(wn, box(Vector3(0.012, 0.055, 0.6)), steel, Vector3(0, 0, -0.4))
			part(wn, box(Vector3(0.012, 0.045, 0.28)), steel, Vector3(0, 0.012, -0.82), Vector3(0.12, 0, 0))
		"spear":
			part(wn, cyl(0.02, 0.02, 2.7), wood, Vector3(0, 0, -0.75), Vector3(PI / 2, 0, 0))
			part(wn, cyl(0.0, 0.045, 0.34), steel, Vector3(0, 0, -2.27), Vector3(-PI / 2, 0, 0))
			part(wn, ball(0.055), red, Vector3(0, 0, -2.06), Vector3.ZERO, Vector3(1, 1, 1.5))        # 红缨
		"glaive":
			part(wn, cyl(0.024, 0.024, 2.3), wood, Vector3(0, 0, -0.55), Vector3(PI / 2, 0, 0))
			part(wn, box(Vector3(0.014, 0.2, 0.62)), steel, Vector3(0, 0.05, -1.98))
			part(wn, box(Vector3(0.014, 0.13, 0.26)), steel, Vector3(0, 0.02, -2.38), Vector3(0.45, 0, 0))
			part(wn, cyl(0.04, 0.04, 0.05, 8), gold, Vector3(0, 0, -1.67), Vector3(PI / 2, 0, 0))
			part(wn, ball(0.05), red, Vector3(0, -0.06, -1.72))
			part(wn, cyl(0.0, 0.03, 0.14), dark, Vector3(0, 0, 0.67), Vector3(PI / 2, 0, 0))
		"ji":
			part(wn, cyl(0.024, 0.024, 2.5), wood, Vector3(0, 0, -0.6), Vector3(PI / 2, 0, 0))
			part(wn, cyl(0.0, 0.045, 0.42), steel, Vector3(0, 0, -2.05), Vector3(-PI / 2, 0, 0))
			part(wn, box(Vector3(0.014, 0.05, 0.4)), steel, Vector3(0, 0.15, -1.75))                # 月牙刃
			part(wn, box(Vector3(0.014, 0.13, 0.04)), steel, Vector3(0, 0.08, -1.6))
			part(wn, box(Vector3(0.014, 0.13, 0.04)), steel, Vector3(0, 0.08, -1.9))
			part(wn, ball(0.05), red, Vector3(0, -0.05, -1.55))
		"bow":
			# 弓在左手：沿局部 Z 轴，前举时自然竖直
			var on := off_node
			part(on, box(Vector3(0.025, 0.03, 0.62)), wood, Vector3(0, -0.07, -0.3), Vector3(0.24, 0, 0))
			part(on, box(Vector3(0.025, 0.03, 0.62)), wood, Vector3(0, -0.07, 0.3), Vector3(-0.24, 0, 0))
			part(on, cyl(0.004, 0.004, 1.2, 4), mat(Color("#e8e2d0")), Vector3(0, -0.145, 0), Vector3(PI / 2, 0, 0))
			var q := part(back_node, cyl(0.06, 0.05, 0.5), mat(Color("#4a3322")), Vector3(0.1, 0.05, 0.05), Vector3(0, 0, -0.45))
			q.set_meta("quiver", true)
			var f := part(back_node, cyl(0.055, 0.03, 0.1), mat(Color("#e8e2d0")), Vector3(0.22, 0.31, 0.05), Vector3(0, 0, -0.45))
			f.set_meta("quiver", true)
	if has_shield:
		var face := mat(color.darkened(0.25))
		match shield_kind:
			"rect":      # 罗马方盾
				part(shield_node, box(Vector3(0.04, 0.86, 0.52)), face, Vector3.ZERO)
				part(shield_node, box(Vector3(0.02, 0.9, 0.56)), gold, Vector3(0.012, 0, 0))
				part(shield_node, ball(0.075), steel, Vector3(-0.03, 0, 0), Vector3.ZERO, Vector3(0.6, 1, 1))
			"long":      # 长木盾
				part(shield_node, box(Vector3(0.04, 0.8, 0.34)), wood, Vector3.ZERO)
				part(shield_node, box(Vector3(0.045, 0.14, 0.345)), face, Vector3(0, 0.12, 0))
				part(shield_node, box(Vector3(0.045, 0.14, 0.345)), face, Vector3(0, -0.2, 0))
			"big":       # 希腊大圆盾
				part(shield_node, cyl(0.43, 0.43, 0.04, 16), mat(Color("#b08a4a"), 0.7), Vector3(0.008, 0, 0), Vector3(0, 0, PI / 2))
				part(shield_node, cyl(0.36, 0.36, 0.045, 16), face, Vector3.ZERO, Vector3(0, 0, PI / 2))
				part(shield_node, ball(0.11), mat(Color("#b08a4a"), 0.7), Vector3(-0.02, 0, 0), Vector3.ZERO, Vector3(0.4, 1, 1))
			"oval":      # 椭圆长盾
				part(shield_node, cyl(0.33, 0.33, 0.04, 14), face, Vector3.ZERO, Vector3(0, 0, PI / 2), Vector3(1.4, 1, 0.82))
				part(shield_node, cyl(0.34, 0.34, 0.02, 14), dark, Vector3(0.01, 0, 0), Vector3(0, 0, PI / 2), Vector3(1.4, 1, 0.82))
				part(shield_node, ball(0.07), steel, Vector3(-0.03, 0, 0), Vector3.ZERO, Vector3(0.6, 1, 1))
			_:
				part(shield_node, cyl(0.33, 0.33, 0.04, 14), face, Vector3.ZERO, Vector3(0, 0, PI / 2))
				part(shield_node, cyl(0.34, 0.34, 0.02, 14), dark, Vector3(0.01, 0, 0), Vector3(0, 0, PI / 2))
				part(shield_node, ball(0.07), steel, Vector3(-0.03, 0, 0), Vector3.ZERO, Vector3(0.6, 1, 1))
	cur = GUARD[w].duplicate()


# ───────────── 动作 ─────────────

func _mix(a: Array, b: Array, t: float) -> Array:
	var out: Array = []
	for i in a.size():
		out.append(lerpf(a[i], b[i], t))
	return out


# anim: 招式名（"" 表示未出招）；frac: 出招进度 0..1；hit_frac: 命中时刻
func animate(delta: float, speed: float, anim: String, frac: float, hit_frac: float, blocking: bool) -> void:
	var moving := speed > 0.3
	if moving:
		phase += delta * speed * (1.25 if mounted else 2.1)
	else:
		phase = lerpf(phase, 0.0, 0.2)
	var s := sin(phase)
	var c := cos(phase)
	var stride := clampf(speed / 5.0, 0.0, 1.2) * 0.7
	var tl := s * stride
	var tr := -s * stride
	var kl := -0.15 - maxf(0.0, c) * stride * 1.3
	var kr := -0.15 - maxf(0.0, -c) * stride * 1.3
	var hip_y := 0.95 + absf(s) * 0.04 * stride
	if not moving:
		tl = 0.12
		tr = -0.12

	var guard: Array = GUARD[weapon]
	var pose: Array = guard
	var attacking := anim != "" and ANIMS.has(anim)
	var spin_k := 0.0
	var strike := 0.0
	if attacking:
		var a: Array = ANIMS[anim][0]
		var b: Array = ANIMS[anim][1]
		var t1 := hit_frac * 0.75
		var t2 := hit_frac + (1.0 - hit_frac) * 0.22
		if anim == "shoot" or anim == "power_shot":
			if frac < hit_frac * 0.3:
				pose = _mix(guard, a, frac / (hit_frac * 0.3))
			elif frac < hit_frac:
				pose = _mix(a, b, (frac - hit_frac * 0.3) / (hit_frac * 0.7))
			else:
				pose = _mix(a, guard, smoothstep(hit_frac + 0.05, 1.0, frac))
		elif frac < t1:
			pose = _mix(guard, a, ease(frac / t1, 0.5))
		elif frac < t2:
			strike = (frac - t1) / (t2 - t1)
			pose = _mix(a, b, strike)
		else:
			strike = 1.0
			pose = _mix(b, guard, smoothstep(t2, 1.0, frac))
		if anim == "spin":
			spin_k = smoothstep(t1, minf(1.0, t2 + 0.25), frac)
		if not mounted and (anim == "thrust" or anim == "dash" or anim == "chop") and frac > t1 * 0.5:
			var lunge := sin(clampf((frac - t1 * 0.5) / (1.0 - t1 * 0.5), 0.0, 1.0) * PI)
			tl = lerpf(tl, 0.75, lunge)
			tr = lerpf(tr, -0.55, lunge)
			kl = lerpf(kl, -0.5, lunge)
			hip_y -= 0.09 * lunge
		cur = pose
	else:
		var tgt: Array = guard.duplicate()
		if moving and not two_handed:
			tgt[0] += -s * 0.15
		if blocking and not has_shield:
			tgt = [1.25, 0.75, 0.0, 0.9, -0.2, 0.0, 0.2]     # 横兵器架挡
		cur = _mix(cur, tgt, minf(1.0, delta * 14.0))

	flinch = maxf(0.0, flinch - delta * 4.0)
	var spin_a := TAU * spin_k if spin_k < 1.0 else 0.0
	if mounted:
		# 骑手跨坐，马腿交替奔跑；回旋斩只转上身
		var g := clampf(speed / 7.0, 0.0, 1.2) if moving else 0.0
		var bob := absf(s) * 0.06 * g
		horse.position.y = bob
		horse_neck.rotation.x = sin(phase * 2.0) * 0.06 * g
		for i in 4:
			var ph: float = phase + [0.0, PI, PI * 0.55, PI * 1.55][i]
			horse_legs[i].rotation.x = lerpf(horse_legs[i].rotation.x, sin(ph) * 0.75 * g, 0.5)
			horse_knees[i].rotation.x = lerpf(horse_knees[i].rotation.x, -maxf(0.0, cos(ph)) * 1.0 * g, 0.5)
		hip_y = 1.5 + bob
		tl = 0.95
		tr = 0.95
		kl = -1.15
		kr = -1.15
	else:
		rotation.y = spin_a
	hips.position.y = hip_y
	thigh_l.rotation.x = lerpf(thigh_l.rotation.x, tl, 0.45)
	thigh_r.rotation.x = lerpf(thigh_r.rotation.x, tr, 0.45)
	shin_l.rotation.x = lerpf(shin_l.rotation.x, kl, 0.45)
	shin_r.rotation.x = lerpf(shin_r.rotation.x, kr, 0.45)
	var lean := 0.12 * clampf(speed / 5.0, 0.0, 1.3) if moving else 0.0
	chest.rotation = Vector3(-(cur[5] + lean) + flinch * 0.35, cur[6] + (spin_a if mounted else 0.0), 0)
	head.rotation = Vector3((cur[5] + lean) * 0.6, -cur[6] * 0.85, 0)
	sh_r.rotation = Vector3(cur[0], cur[1], cur[2])
	el_r.rotation.x = cur[3]
	hand_r.rotation.x = cur[4]

	# 左臂：盾 / 双手握持 / 持弓 / 自然摆动
	var sl := Vector3(s * 0.3 * stride, 0, -0.1)
	var el := 0.25
	var hl := 0.0
	if weapon == "bow":
		if attacking:
			sl = Vector3(1.52, 1.0, 0)
			el = 0.05
		else:
			sl = Vector3(0.7, 0.2, -0.1)
			el = 0.7
	elif has_shield:
		if blocking:
			sl = Vector3(1.25, -0.55, 0)
			el = 1.25
		else:
			sl = Vector3(0.45, -0.2, -0.15)
			el = 1.15
	elif two_handed:
		sl = Vector3(cur[0] * 0.8 + 0.2, cur[1] - 0.6, 0)
		el = clampf(cur[3] + 0.5, 0.6, 1.6)
	var k := minf(1.0, delta * 16.0)
	sh_l.rotation = sh_l.rotation.lerp(sl, k)
	el_l.rotation.x = lerpf(el_l.rotation.x, el, k)
	hand_l.rotation.x = lerpf(hand_l.rotation.x, hl, k)


func flash() -> void:
	flinch = 1.0
	if _flash != null:
		_flash.kill()
	torso_mat.emission_energy_multiplier = 2.5
	_flash = create_tween()
	_flash.tween_property(torso_mat, "emission_energy_multiplier", 0.0, 0.25)
