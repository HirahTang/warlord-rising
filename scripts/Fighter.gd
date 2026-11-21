extends CharacterBody3D
# 战场上的一个作战单位：士兵、山贼、武将，或玩家本人。

const HumanoidScript = preload("res://scripts/Humanoid.gd")

# 招式：w 起手时间 s 总时长 d 伤害倍率 r 额外距离 arc 命中扇面(与正前方夹角的 cos 下限)
#       n 最多命中人数 kb 击退 brk 破防
const MOVES := {
	"slash_r": {"cn": "右斩", "w": 0.16, "s": 0.42, "d": 1.0, "r": 0.0, "arc": 0.2, "n": 3, "kb": 4.0},
	"slash_l": {"cn": "左斩", "w": 0.16, "s": 0.42, "d": 1.0, "r": 0.0, "arc": 0.2, "n": 3, "kb": 4.0},
	"chop": {"cn": "力劈", "w": 0.24, "s": 0.55, "d": 1.6, "r": 0.1, "arc": 0.75, "n": 1, "kb": 6.0},
	"upper": {"cn": "上撩", "w": 0.18, "s": 0.46, "d": 1.15, "r": 0.0, "arc": 0.5, "n": 2, "kb": 5.0},
	"thrust": {"cn": "突刺", "w": 0.18, "s": 0.45, "d": 1.25, "r": 0.6, "arc": 0.92, "n": 2, "kb": 5.0},
	"dash": {"cn": "冲刺", "w": 0.2, "s": 0.52, "d": 1.5, "r": 0.9, "arc": 0.88, "n": 3, "kb": 9.0, "brk": true},
	"sweep": {"cn": "横扫", "w": 0.3, "s": 0.7, "d": 0.95, "r": 0.3, "arc": -0.2, "n": 8, "kb": 9.0, "brk": true},
	"spin": {"cn": "回旋斩", "w": 0.3, "s": 0.8, "d": 1.5, "r": 0.2, "arc": -1.1, "n": 12, "kb": 8.0, "brk": true},
	"shoot": {"cn": "射箭", "w": 0.45, "s": 0.75, "d": 1.0, "shot": true},
	"power_shot": {"cn": "蓄力箭", "w": 0.9, "s": 1.2, "d": 2.4, "shot": true, "brk": true},
}
# 兵器：speed 为出招时间倍率（越大越慢），block 为格挡后承受的伤害比例
const WEAPONS := {
	"dao": {"name": "刀盾", "reach": 2.3, "dmg": 1.0, "speed": 1.0, "block": 0.1,
		"combo": ["slash_r", "slash_l", "chop"], "back": "upper", "heavy": "spin"},
	"saber": {"name": "环首刀", "reach": 2.3, "dmg": 1.0, "speed": 1.0, "block": 0.45,
		"combo": ["slash_r", "slash_l", "chop"], "back": "upper", "heavy": "spin"},
	"spear": {"name": "长枪", "reach": 3.3, "dmg": 0.95, "speed": 1.1, "block": 0.4,
		"combo": ["thrust", "thrust", "sweep"], "back": "chop", "heavy": "sweep"},
	"glaive": {"name": "大刀", "reach": 2.9, "dmg": 1.5, "speed": 1.5, "block": 0.4,
		"combo": ["slash_r", "slash_l", "chop"], "back": "upper", "heavy": "spin"},
	"ji": {"name": "长戟", "reach": 3.1, "dmg": 1.45, "speed": 1.4, "block": 0.4,
		"combo": ["thrust", "slash_r", "chop"], "back": "upper", "heavy": "spin"},
	"bow": {"name": "弓", "reach": 2.0, "dmg": 0.9, "speed": 1.0, "block": 0.8,
		"combo": ["shoot"], "back": "shoot", "heavy": "power_shot", "ranged": true},
}
const PLAYER_WEAPONS := ["dao", "spear", "glaive", "bow"]
const ARROW_SPEED := 42.0
const ARROW_G := 6.0

var battle
var team := 0
var kind := "soldier"
var is_player := false
var is_general := false
var gname := ""
var weapon := "dao"
var wp: Dictionary
var max_hp := 40.0
var hp := 40.0
var dmg := 9.0
var move_speed := 4.0
var reach := 2.3
var target = null
var dead := false
var blocking := false
var block_t := 0.0
var block_cd := 0.0
var cur_move := ""
var move: Dictionary = {}
var windup := 0.3
var swing := 0.6
var attack_t := -1.0
var hit_done := false
var finisher := false
var combo_i := 0
var combo_idle := 0.0
var cd := 0.0
var think := 0.0
var in_squad := false
var hold_pos := Vector3.ZERO
var fleeing := false
var kb := Vector3.ZERO
var model
var dodge_cd := 0.0
var invuln := 0.0
var death_t := 0.0
var face_yaw := 0.0
var last_mv := Vector3.ZERO
var sprinting := false
var hp_quad: MeshInstance3D = null
var label: Label3D = null
var mounted := false
var war := 50
var atk_mult := 1.0      # 手中兵器的品质加成
var armor_def := 0.0     # 铠甲减伤
var item_id := ""
var charge := false      # 骑兵带着速度出手：冲锋加成
var team_color := Color.WHITE
var horse_col := Color("#6b4a2b")
var foot_speed := 4.0
var horse_mult := 1.0
var body_shape: CapsuleShape3D
var zone := 0            # 攻城战：0 城外 1 城头 2 城内
var base_y := 0.0
var link_t := -1.0       # 正在攀云梯 / 走马道
var link_a := Vector3.ZERO
var link_b := Vector3.ZERO
var link_dur := 1.0
var link_zone := 0
var siege_role := randi() % 3     # 2 = 撞城门，其余登云梯
var siege_x := randf_range(-2.6, 2.6)
var flee_t := 0.0
var hoof_t := 0.0
var moat_side := 1       # 在护城河的哪一边：1 城外，-1 城墙根
var lod_id := randi() % 3
# 兵种专长（由 apply_troop 设置）
var troop_lv := 0
var roster_i := -1        # 在玩家亲兵名册里的序号
var block_p := 0.45
var block_mult := 1.0
var block_firm := false
var counter := false
var anti_cav := 1.0
var atk_time := 1.0
var shot_range := 0.0
var shot_cd := 1.0
var hit_brk := false
var charge_mult := 1.3
var stuck_t := 0.0
var side_t := 0.0
var side_dir := Vector3.ZERO


func setup(p_battle, p_team: int, color: Color, p_kind: String, p_name := "", p_war := 50, p_weapon := "dao", p_mounted := false, p_horse_col := Color("#6b4a2b")) -> void:
	battle = p_battle
	team = p_team
	kind = p_kind
	gname = p_name
	war = p_war
	mounted = p_mounted
	team_color = color
	horse_col = p_horse_col
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5 if mounted else 0.36
	cap.height = 1.8
	body_shape = cap
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	model = HumanoidScript.new()
	add_child(model)
	model.build(color, kind, p_weapon, gname, mounted, horse_col, str(battle.looks[team]) if battle != null else "")
	match kind:
		"soldier":
			max_hp = 70.0
			dmg = 8.0
			move_speed = randf_range(3.7, 4.3)
		"bandit":
			max_hp = 45.0
			dmg = 7.0
			move_speed = randf_range(3.5, 4.1)
		"general":
			is_general = true
			max_hp = 150.0 + war * 2.5
			dmg = 6.0 + war * 0.12
			move_speed = 4.6
			model.scale = Vector3.ONE * 1.18
		"player":
			is_player = true
			var w := int(Game.player.war)
			max_hp = 80.0 + w * 2.0
			dmg = 10.0 + w * 0.3
			move_speed = 5.6
			var arm: Dictionary = Game.item(str(Game.player.eq.armor))
			if not arm.is_empty():
				max_hp += float(arm.hp)
				armor_def = float(arm.def)
	foot_speed = move_speed
	if mounted:
		if is_player:
			horse_mult = float(Game.item(str(Game.player.eq.horse)).get("spd", 1.25))
			move_speed *= horse_mult
		else:
			max_hp *= 1.35
			move_speed *= 1.3 if is_general else 1.5
	set_weapon(p_weapon, false)
	hp = max_hp
	if is_player:
		hp = max_hp * clampf(int(Game.player.hp) / 100.0, 0.1, 1.0)
	if is_general or is_player:
		label = Label3D.new()
		label.text = Lang.fix(gname)
		label.font = Game.font
		label.font_size = 56
		label.outline_size = 14
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("#ffe08a") if is_player else Color.WHITE
		label.position.y = 3.3 if mounted else 2.75
		add_child(label)
	if is_general:
		hp_quad = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.3, 0.1)
		hp_quad.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("#e03030")
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		hp_quad.material_override = m
		hp_quad.position.y = 3.0 if mounted else 2.45
		add_child(hp_quad)


func set_weapon(w: String, rebuild := true) -> void:
	if attack_t >= 0.0:
		return
	weapon = w
	wp = WEAPONS[w]
	reach = float(wp.reach) + (0.3 if (is_general or is_player) else 0.0) + (0.3 if mounted else 0.0)
	combo_i = 0
	if rebuild:
		model.set_weapon(w)


# 玩家上马 / 下马：重建模型，换回相应的速度与身形
func set_mounted(on: bool) -> bool:
	if on == mounted or dead or attack_t >= 0.0 or link_t >= 0.0:
		return false
	mounted = on
	model.queue_free()
	model = HumanoidScript.new()
	add_child(model)
	model.build(team_color, kind, weapon, gname, mounted, horse_col, str(battle.looks[team]) if battle != null else "")
	move_speed = foot_speed * (horse_mult if on else 1.0)
	body_shape.radius = 0.5 if on else 0.36
	if label != null:
		label.position.y = 3.3 if on else 2.75
	set_weapon(weapon, false)
	return true


# 亲兵按兵种等级得到的加成与专长。k: dao / spear / bow / cav
func apply_troop(k: String, lv: int) -> void:
	troop_lv = lv
	max_hp *= 1.0 + 0.08 * lv
	dmg *= 1.0 + 0.06 * lv
	match k:
		"dao":
			if lv >= 1:
				block_p = 0.6
			if lv >= 2:
				block_mult = 0.5
			counter = lv >= 3
			if lv >= 4:
				max_hp *= 1.2
			if lv >= 5:
				block_p = 0.75
				block_firm = true
		"spear":
			if lv >= 1:
				reach += 0.3
			if lv >= 2:
				anti_cav = 1.5
			if lv >= 3:
				atk_time = 0.85
			if lv >= 4:
				dmg *= 1.2
			hit_brk = lv >= 5
		"bow":
			if lv >= 1:
				shot_range += 4.0
			if lv >= 2:
				dmg *= 1.15
			if lv >= 3:
				shot_cd = 0.75
			if lv >= 4:
				shot_range += 4.0
			hit_brk = lv >= 5
		"cav":
			if lv >= 1:
				move_speed *= 1.08
			if lv >= 2:
				charge_mult = 1.5
			if lv >= 3:
				max_hp *= 1.2
			if lv >= 4:
				armor_def = 0.2
			if lv >= 5:
				charge_mult = 1.7
				move_speed *= 1.08
	hp = max_hp
	model.set_rank(lv)


# 玩家换上行囊里的某件兵器
func set_item(id: String, rebuild := true) -> void:
	if attack_t >= 0.0:
		return
	var it: Dictionary = Game.item(id)
	item_id = id
	atk_mult = 1.0 + float(it.get("atk", 0.0))
	set_weapon(str(it.get("w", "dao")), rebuild)


func is_ranged() -> bool:
	return wp.has("ranged")


func face(dir: Vector3) -> void:
	if dir.length_squared() > 0.0001:
		face_yaw = atan2(-dir.x, -dir.z)


func forward() -> Vector3:
	return Vector3(-sin(rotation.y), 0, -cos(rotation.y))


func _physics_process(delta: float) -> void:
	if dead:
		death_t += delta
		var k := minf(1.0, death_t / 0.45)
		if mounted:
			model.rotation.z = PI / 2 * k      # 连人带马侧翻
			model.position.y = 0.3 * k
		else:
			model.rotation.x = -PI / 2 * k
			model.position.y = 0.22 * k
		if death_t > 14.0:
			queue_free()
		return
	if link_t >= 0.0:
		link_t += delta
		var lk := minf(1.0, link_t / link_dur)
		position = link_a.lerp(link_b, lk)
		rotation.y = lerp_angle(rotation.y, face_yaw, minf(1.0, delta * 12.0))
		model.animate(delta, 3.5, "", 0.0, 0.0, false)
		if lk >= 1.0:
			link_t = -1.0
			base_y = link_b.y
			zone = link_zone
		return
	cd -= delta
	dodge_cd -= delta
	invuln -= delta
	block_t -= delta
	block_cd -= delta
	var desired := Vector3.ZERO
	if battle.over and not fleeing:
		blocking = false
	elif is_player and not Game.autopilot:
		desired = _player_input()
	else:
		desired = _ai(delta)
	if attack_t >= 0.0:
		attack_t += delta
		if not hit_done and attack_t >= windup:
			hit_done = true
			_do_hit()
		if attack_t >= swing:
			attack_t = -1.0
			combo_idle = 0.0
		elif not is_player or cur_move == "spin" or cur_move == "sweep":
			desired *= 0.25      # 出招时脚下放慢
	else:
		combo_idle += delta
		if combo_idle > 0.75:
			combo_i = 0
	# 城内被房屋挡住时，横向绕一下
	if zone == 2 and not (is_player and not Game.autopilot):
		if side_t > 0.0:
			side_t -= delta
			desired = side_dir * move_speed
		elif desired.length() > 1.0 and get_real_velocity().length() < 0.5:
			stuck_t += delta
			if stuck_t > 0.35:
				stuck_t = 0.0
				side_t = 0.8
				var want := -1.0 if position.x > 0.0 else 1.0     # 朝中央大街绕
				side_dir = Vector3(want, 0, 0) if absf(desired.z) > absf(desired.x) else Vector3(0, 0, 1.0 if randf() < 0.5 else -1.0)
		else:
			stuck_t = 0.0
	kb = kb.move_toward(Vector3.ZERO, delta * 32.0)
	velocity = desired + kb
	velocity.y = 0
	move_and_slide()
	if zone != 1:
		base_y = battle.ground_y(position.x, position.z)      # 脚下的地势
	position.y = base_y
	if battle.siege:
		position.x = clampf(position.x, -68, 68)
		battle.constrain(self)
	elif not fleeing:
		position.x = clampf(position.x, -battle.x_lim, battle.x_lim)
		position.z = clampf(position.z, battle.z_min, battle.z_max)
	rotation.y = lerp_angle(rotation.y, face_yaw, minf(1.0, delta * 12.0))
	if is_player and mounted and desired.length() > 2.0:
		hoof_t -= delta
		if hoof_t <= 0.0:
			hoof_t = 0.21
			Sfx.play("gallop", -8.0, 0.15)
	var anim := cur_move if attack_t >= 0.0 else ""
	# 离玩家远的人每三帧才摆一次姿势，人多时省不少开销
	var lod := 1 if (is_player or position.distance_squared_to(Sfx.listener) < 1600.0) else 3
	if lod == 1 or (Engine.get_physics_frames() + lod_id) % 3 == 0:
		model.animate(delta * lod, desired.length(), anim, attack_t / swing if attack_t >= 0.0 else 0.0, windup / swing, blocking)


# ───────────── AI ─────────────

func _ai(delta: float) -> Vector3:
	if fleeing:
		var d := Vector3(0, 0, 1.0 if team == 0 else -1.0)
		face(d)
		blocking = false
		flee_t += delta
		if absf(position.z) > 85.0 or ((battle.siege or battle.palace) and flee_t > 3.0):   # 逃出战场：隐藏但仍算幸存
			visible = false
			set_physics_process(false)
		return d * move_speed * 1.35
	think -= delta
	if think <= 0.0:
		think = randf_range(0.35, 0.6)
		target = battle.nearest_enemy(self)
	var has_t: bool = target != null and is_instance_valid(target) and not target.dead
	var td := INF
	if has_t:
		td = position.distance_to(target.position)
	blocking = block_t > 0.0 and attack_t < 0.0
	if in_squad and is_instance_valid(battle.player) and not battle.player.dead and battle.player.zone == zone:
		if battle.squad_order == 1:
			var dp: Vector3 = battle.moat_route(position, battle.player.position) - position
			dp.y = 0
			if (battle.player.position - position).length() > 5.0 and td > (26.0 if is_ranged() else 5.0):
				face(dp)
				return dp.normalized() * move_speed * 1.2
		elif battle.squad_order == 2:
			if not has_t or (not is_ranged() and target.position.distance_to(hold_pos) > 7.0):
				var dh := hold_pos - position
				if dh.length() > 1.0:
					face(dh)
					return dh.normalized() * move_speed
				return Vector3.ZERO
	if has_t and battle.siege and target.zone != zone and not is_ranged():
		has_t = false
	if not has_t:
		return _siege_move() if battle.siege else Vector3.ZERO
	var to: Vector3 = target.position - position
	to.y = 0
	face(to)
	var mv_to := to      # 实际迈步的方向：隔着护城河时先奔桥
	if battle.moat and zone == 0 and not is_ranged():
		mv_to = battle.moat_route(position, target.position) - position
		mv_to.y = 0
	if is_ranged():
		if td <= (36.0 if zone == 1 else 27.0) + shot_range:
			if cd <= 0.0 and attack_t < 0.0:
				start_attack("shoot")
			return Vector3.ZERO
		return to.normalized() * move_speed
	# 刀盾兵见对手起手，有几分机会举盾
	if weapon == "dao" and not is_general and td < 4.5 and block_cd <= 0.0 and attack_t < 0.0 \
			and target.attack_t >= 0.0 and not target.hit_done:
		block_cd = 1.6
		if randf() < block_p:
			block_t = 0.8
	if td <= reach:
		if cd <= 0.0 and attack_t < 0.0 and not blocking:
			if is_general and randf() < 0.25:
				start_attack(wp.heavy)
			else:
				start_attack("")
		return Vector3.ZERO
	return mv_to.normalized() * move_speed * (0.5 if blocking else 1.0)


# ───────────── 攻城：登城、破门、入巷 ─────────────

func place(pos: Vector3, z: int) -> void:
	position = pos
	base_y = pos.y
	zone = z


func start_link(a: Vector3, bb: Vector3, dur: float, z_after: int) -> void:
	link_a = a
	link_b = bb
	link_dur = dur
	link_zone = z_after
	link_t = 0.0
	attack_t = -1.0
	blocking = false
	var d := bb - a
	d.y = 0
	face(d)


func _goto(p: Vector3, sp := 1.0) -> Vector3:
	if (p - position).length() < 0.6:
		return Vector3.ZERO
	var d: Vector3 = battle.moat_route(position, p) - position
	d.y = 0
	if d.length() < 0.6:
		return Vector3.ZERO
	face(d)
	return d.normalized() * move_speed * sp


# 眼前没有够得着的敌人时，按所在区域推进
func _siege_move() -> Vector3:
	var bt = battle
	if zone == 1:
		if team == 0 or (bt.enemy_in_zone(team, 2) and not bt.enemy_in_zone(team, 0)):
			var st = bt.nearest_link(self, "stairs")
			if position.distance_to(st.a) < 1.2:
				start_link(st.a, st.b, float(st.t), 2)
				return Vector3.ZERO
			return _goto(st.a)
		return Vector3.ZERO
	if zone == 2:
		if team == 0:
			return _goto(Vector3(siege_x * 2.0, 0, -106.0))
		if bt.gate_open and bt.enemy_in_zone(team, 0) and not bt.enemy_in_zone(team, 2) and not bt.enemy_in_zone(team, 1):
			return _goto(Vector3(0, 0, -44.0))
		return Vector3.ZERO
	# 城外
	if bt.gate_open and (team == 0 or not bt.enemy_in_zone(team, 0)):
		return _goto(Vector3(0, 0, -58.0), 1.15)
	if team == 0:
		if mounted or siege_role == 2:
			var gp := Vector3(siege_x, 0, -45.7)
			if position.distance_to(gp) < 1.3:
				face(Vector3(0, 0, -1))
				if cd <= 0.0 and attack_t < 0.0:
					start_attack("")
				return Vector3.ZERO
			return _goto(gp)
		var ld = bt.ladder_for(self)
		if position.distance_to(ld.a) < 1.3:
			bt.raise_ladder(ld)
			start_link(ld.a, ld.b, float(ld.t), 1)
			return Vector3.ZERO
		return _goto(ld.a, 1.1)
	if not mounted:
		var back = bt.nearest_link(self, "ladder", true)
		if back != null:
			if position.distance_to(back.a) < 1.3:
				start_link(back.a, back.b, float(back.t), 1)
				return Vector3.ZERO
			return _goto(back.a)
	return Vector3.ZERO


# ───────────── 玩家 ─────────────

func _player_input() -> Vector3:
	var yaw: float = battle.yaw
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	var r := Vector3(cos(yaw), 0, -sin(yaw))
	var mv := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		mv += f
	if Input.is_physical_key_pressed(KEY_S):
		mv -= f
	if Input.is_physical_key_pressed(KEY_D):
		mv += r
	if Input.is_physical_key_pressed(KEY_A):
		mv -= r
	var js: Vector2 = Game.joy_stick(0)
	mv += r * js.x - f * js.y
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var want_block := (captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) \
		or Game.joy_trigger(JOY_AXIS_TRIGGER_LEFT) or Game.joy_btn([JOY_BUTTON_LEFT_SHOULDER])
	var want_attack := (captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) \
		or Game.joy_trigger(JOY_AXIS_TRIGGER_RIGHT) or Game.joy_btn([JOY_BUTTON_RIGHT_SHOULDER])
	var want_heavy := Input.is_physical_key_pressed(KEY_F) or (captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)) \
		or Game.joy_btn([JOY_BUTTON_X])
	blocking = want_block and attack_t < 0.0
	sprinting = Input.is_physical_key_pressed(KEY_SHIFT) or Game.joy_btn([JOY_BUTTON_LEFT_STICK])
	var sp := move_speed
	if sprinting:
		sp *= 1.35
	if blocking:
		sp *= 0.45
	if mv.length() > 1.0:
		mv = mv.normalized()
	if mv.length() > 0.05:
		face(mv)
		last_mv = mv.normalized()
	if blocking or attack_t >= 0.0:
		face(f)
	if not blocking and attack_t < 0.0 and cd <= 0.0:
		if want_heavy:
			start_attack(wp.heavy)
		elif want_attack:
			start_attack(_pick_player_move(mv.dot(f), mv.dot(r)))
	if battle.siege and mv.length() > 0.3 and attack_t < 0.0:
		battle.try_link(self, mv)
	return mv * sp


# 按出手瞬间的方向键决定招式：左右=横斩方向，后=变招，疾跑前冲=冲刺，其余走连招
func _pick_player_move(fz: float, rx: float) -> String:
	if is_ranged():
		return "shoot"
	if sprinting and fz > 0.5:
		return "dash"
	if absf(rx) > 0.35 and absf(rx) >= absf(fz):
		return "slash_r" if rx > 0.0 else "slash_l"
	if fz < -0.35:
		return wp.back
	return ""


func start_attack(move_name: String) -> void:
	if dead or attack_t >= 0.0 or cd > 0.0:
		return
	finisher = false
	if move_name == "":
		var combo: Array = wp.combo
		if is_player:
			move_name = combo[combo_i % combo.size()]
			combo_i += 1
			finisher = combo.size() > 1 and combo_i % combo.size() == 0
		else:
			move_name = combo[randi() % combo.size()]
	cur_move = move_name
	move = MOVES[move_name]
	# AI 出招更慢，留给玩家反应的时间
	var tm: float = float(wp.speed) * (1.0 if is_player else (1.5 if is_general else 1.8)) * atk_time
	windup = float(move.w) * tm
	swing = float(move.s) * tm
	attack_t = 0.0
	hit_done = false
	charge = mounted and not move.has("shot") and velocity.length() > move_speed * 0.7
	if not move.has("shot"):
		Sfx.play_at("swing_heavy" if move.has("brk") else "swing", position, 0.0 if is_player else -5.0)
	cd = swing + 0.06 if is_player else swing + randf_range(0.7, 1.5)
	if move.has("shot") and not is_player:
		cd = swing + randf_range(1.2, 2.2) * shot_cd
	if is_player and not Game.autopilot:
		rotation.y = atan2(sin(battle.yaw), cos(battle.yaw))
		face_yaw = rotation.y
	if move_name == "dash":
		kb = forward() * 13.0
		invuln = 0.2


func dodge() -> void:
	if dead or dodge_cd > 0.0:
		return
	var d := last_mv
	if d == Vector3.ZERO:
		d = -forward()
	kb = d * 17.0
	invuln = 0.35
	dodge_cd = 0.9


func _do_hit() -> void:
	var power: float = dmg * float(wp.dmg) * float(move.d) * (1.25 if finisher else 1.0) * atk_mult
	var brk: bool = move.has("brk") or hit_brk
	if charge:
		power *= charge_mult
	# 攻方在城门前出手：砍门
	if battle.siege and team == 0 and zone == 0 and not battle.gate_open and absf(position.x) < 5.0 and position.z < -43.0 and forward().z < -0.3:
		battle.hit_gate(power)
	if move.has("shot"):
		_shoot(power, brk)
		return
	var fwd := forward()
	var r: float = reach + float(move.r) + 0.4
	var kbf: float = float(move.kb) * (1.6 if charge else 1.0)
	if not is_player and not is_general:
		# 小兵只打眼前的对手
		if target != null and is_instance_valid(target) and not target.dead and position.distance_to(target.position) < r + 0.2:
			target.take_damage(power * randf_range(0.8, 1.2) * (anti_cav if target.mounted else 1.0), self, position, brk, kbf)
		return
	var maxn := int(move.n)
	if is_general:
		maxn = mini(maxn, 4 if brk else 2)
	var cands: Array = []
	for e in battle.units[1 - team]:
		if e.dead:
			continue
		var to: Vector3 = e.position - position
		var d := to.length()
		if d < r and (d < 0.9 or fwd.dot(to / d) > float(move.arc)):
			cands.append([d, e])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(maxn, cands.size()):
		cands[i][1].take_damage(power * randf_range(0.9, 1.1), self, position, brk, kbf)


func _shoot(power: float, brk: bool) -> void:
	var origin := position + Vector3(0, 1.95 if mounted else 1.45, 0) + forward() * (0.9 if mounted else 0.5)
	var aim := origin + forward() * 40.0
	var tgt = target
	if is_player and not Game.autopilot:
		tgt = battle.player_aim()
	if tgt != null and is_instance_valid(tgt) and not tgt.dead:
		var d := origin.distance_to(tgt.position)
		var t := d / ARROW_SPEED
		aim = tgt.position + tgt.velocity * t * 0.6 + Vector3(0, 1.15 + 0.5 * ARROW_G * t * t, 0)
	var dir := (aim - origin).normalized()
	if not is_player:
		dir = dir.rotated(Vector3.UP, randf_range(-0.045, 0.045))
	battle.spawn_arrow(origin, dir * ARROW_SPEED, power, team, self, brk)
	Sfx.play_at("bow", position, 0.0 if is_player else -4.0)


func take_damage(amount: float, from, from_pos: Vector3, brk := false, kbf := 4.0) -> void:
	if dead or invuln > 0.0:
		return
	var to := from_pos - position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	var blocked := false
	if blocking and forward().dot(dir) > 0.2:
		if brk and not block_firm:
			block_t = 0.0
			blocking = false
			cd = maxf(cd, 0.7)      # 被破防，硬直
		else:
			blocked = true
			amount *= float(wp.block) * block_mult
			kbf *= 0.3
			if counter:
				cd = 0.0      # 先登：挡住就还手
				block_t = 0.0
	amount *= 1.0 - armor_def
	hp -= amount
	Sfx.play_at("clang" if blocked else "hit", position, 2.0 if (is_player or from == battle.player) else -3.0)
	battle.last_hit_t = battle.clock
	kb -= dir * kbf * (0.5 if (is_general or is_player) else 1.0)
	if not is_player and not is_general and not blocked and attack_t >= 0.0 and not hit_done:
		attack_t = -1.0            # 小兵挨打会被打断出招
		cd = maxf(cd, 0.4)
	model.flash()
	if hp_quad != null:
		hp_quad.scale.x = clampf(hp / max_hp, 0.02, 1.0)
	if hp <= 0.0:
		dead = true
		blocking = false
		collision_layer = 0
		collision_mask = 0
		if label != null:
			label.visible = false
		if hp_quad != null:
			hp_quad.visible = false
		Sfx.play_at("die", position, -2.0)
		battle.on_death(self, from)
