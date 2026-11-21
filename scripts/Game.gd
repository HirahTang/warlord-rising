extends Node
# 全局状态与战略层规则：时间、城池归属、AI 出兵、玩家成长、存档。

signal changed

const LEGACY_SAVE := "user://save.json"
const SLOTS := 6
var save_prefix := "user://save_"     # 自检时改到别处，免得覆盖玩家存档
var slot := 1                         # 当前存档栏位：每月自动存到这里
const SC = preload("res://scripts/Scenarios.gd")

var scenario := "sanguo"   # 当前剧本（年代）
var era := {}
var edges: Array = []      # 道路 [城, 城]
var regions: Array = []    # 地图上的地域名
var year := 190
var month := 1
var factions := {}   # id -> {name, color}
var cities := {}     # 城名 -> {lon, lat, f, troops, size, cap}
var gens := {}       # 姓名 -> {f, city, war, lead}
var adj := {}        # 城名 -> [相邻城名]
var player := {}
var log_lines: Array = []
var notices: Array = []       # 需要弹窗告知玩家的消息
var pending_battle = null     # 等待玩家亲自上阵的战斗
var last_result = null
var _def_vet := 0.0             # 败退守军的训练度（并入别城时用）
var squad_note := ""             # 最近一战亲兵的伤亡与晋级（给战报用）
var last_captured: Array = []   # 最近一战俘获的敌将（给战报用）
var _downed: Array = []        # 本场被玩家亲手击破的敌将
var autopilot := false        # 测试用：玩家由 AI 操控，不存档、不切场景
var rng := RandomNumberGenerator.new()
var font: SystemFont
var theme: Theme


func _ready() -> void:
	rng.randomize()
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Hiragino Sans GB", "Heiti SC", "STHeiti", "Songti SC", "Noto Sans CJK SC", "Microsoft YaHei"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	var styles := {
		"normal": [Color(0.2, 0.15, 0.1, 0.95), Color("#7a6238")],
		"hover": [Color(0.32, 0.23, 0.13, 0.98), Color("#d9b96a")],
		"pressed": [Color(0.45, 0.3, 0.14, 1.0), Color("#ffd98a")],
		"disabled": [Color(0.14, 0.12, 0.1, 0.7), Color("#4a4034")],
		"focus": [Color(0, 0, 0, 0), Color("#ffd98a")],
	}
	for k in styles:
		var sb := StyleBoxFlat.new()
		sb.bg_color = styles[k][0]
		sb.border_color = styles[k][1]
		sb.set_border_width_all(2 if k == "focus" else 1)
		sb.border_width_left = 4 if k != "focus" else 2
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 12
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		if k == "focus":
			sb.draw_center = false
		theme.set_stylebox(k, "Button", sb)
	theme.set_color("font_color", "Button", Color("#f0e6d0"))
	theme.set_color("font_hover_color", "Button", Color("#ffe9b0"))
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color("#ffe9b0"))
	theme.set_color("font_disabled_color", "Button", Color("#7a7062"))
	var sep := StyleBoxLine.new()
	sep.color = Color("#8a6d3b")
	sep.thickness = 1
	theme.set_stylebox("separator", "HSeparator", sep)
	_migrate_legacy()
	new_game()


func new_game(sid := "") -> void:
	if sid != "" and SC.ERAS.has(sid):
		scenario = sid
	era = SC.ERAS[scenario]
	year = int(era.year)
	month = int(era.month)
	regions = era.regions
	edges = era.edges.duplicate()
	factions.clear()
	cities.clear()
	gens.clear()
	adj.clear()
	log_lines.clear()
	notices.clear()
	pending_battle = null
	for f in era.factions:
		factions[f[0]] = {"name": f[0], "color": f[1], "lord": f[2], "capital": ""}
	for c in era.cities:
		var k := int(c[4])
		var size := 1
		if k >= 16:
			size = 3
		elif k >= 10:
			size = 2
		cities[c[0]] = {"lon": c[1], "lat": c[2], "f": c[3], "troops": k * 1000, "size": size, "cap": k * 1500 + 6000, "vet": 0.6 * (size - 1)}
		adj[c[0]] = []
	for e in edges:
		adj[e[0]].append(e[1])
		adj[e[1]].append(e[0])
	for g in era.generals:
		gens[g[0]] = {"f": g[1], "city": g[2], "war": int(g[3]), "lead": int(g[4])}
	for f in factions:
		_fix_capital(f)
	player = {
		"name": "无名氏", "started": false, "f": "", "city": "", "gov": "",
		"rank": 0, "merit": 0, "war": 30, "hp": 100, "gold": 50, "kills": 0,
		"hegemon": false, "unified": false,
		"items": DB.START_ITEMS.duplicate(), "eq": {"w1": "iron_dao", "w2": "wood_spear", "armor": "", "horse": ""},
		"squad": [], "explored": {}, "diplo": {},
	}


# ───────────── 手柄（兼容 Joy-Con 左右分开成两个设备的情况）─────────────

func _is_right_joycon(d: int) -> bool:
	var n := Input.get_joy_name(d)
	return Input.get_connected_joypads().size() > 1 and (n.contains("(R)") or n.contains("Right"))


# stick: 0 = 移动（左摇杆），1 = 视角（右摇杆）
func joy_stick(stick: int) -> Vector2:
	var out := Vector2.ZERO
	for d in Input.get_connected_joypads():
		var l := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		var r := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		if _is_right_joycon(d):   # 单独的右 Joy-Con：它唯一的摇杆当作视角
			r = r if r.length() > l.length() else l
			l = Vector2.ZERO
		var v := l if stick == 0 else r
		if v.length() > out.length():
			out = v
	return out if out.length() > 0.2 else Vector2.ZERO


func joy_btn(buttons: Array) -> bool:
	for d in Input.get_connected_joypads():
		for bt in buttons:
			if Input.is_joy_button_pressed(d, bt):
				return true
	return false


func joy_trigger(axis: int) -> bool:
	for d in Input.get_connected_joypads():
		if Input.get_joy_axis(d, axis) > 0.4:
			return true
	return false


func joy_names() -> String:
	var a: Array = []
	for d in Input.get_connected_joypads():
		a.append(Input.get_joy_name(d))
	return "、".join(a) if not a.is_empty() else Lang.t("未检测到")


# ───────────── 查询 ─────────────

func fname(f: String) -> String:
	if f == "":
		return Lang.t("在野")
	if factions.has(f):
		return factions[f].name
	return f


# 势力的君主姓名（旧存档里势力名就是君主名）
func lord_of(f: String) -> String:
	if factions.has(f):
		return str(factions[f].get("lord", f))
	return f


# 国都 = 君主所在的城
func capital_of(f: String) -> String:
	if factions.has(f):
		return str(factions[f].get("capital", ""))
	return ""


func is_capital(c: String) -> bool:
	return cities.has(c) and capital_of(str(cities[c].f)) == c


# 可以定都的城：手中规模最大的那一档（只有一座城时就是它）
func capital_choices(f: String) -> Array:
	var top := 0
	for c in faction_cities(f):
		top = maxi(top, int(cities[c].size))
	var out: Array = []
	for c in faction_cities(f):
		if int(cities[c].size) == top:
			out.append(c)
	return out


# 从可定都的城里挑兵力最多的一座
func _best_capital(f: String) -> String:
	var best := ""
	for c in capital_choices(f):
		if best == "" or int(cities[c].troops) > int(cities[best].troops):
			best = c
	return best


# 君主亲自指定国都（迁都）
func act_move_capital(c: String) -> String:
	if not is_lord():
		return Lang.t("只有君主可以定都。")
	if not cities.has(c) or cities[c].f != "player":
		return Lang.t("%s不在你手中。") % c
	if capital_of("player") == c:
		return Lang.t("%s已是国都。") % c
	if not capital_choices("player").has(c):
		return Lang.t("国都只能设在最大的城池里（%s）。") % "、".join(capital_choices("player"))
	var old := capital_of("player")
	factions["player"]["capital"] = c
	player.city = c
	add_log(Lang.t("%s 自%s迁都%s。") % [player.name, old, c])
	notices.append(Lang.t("【迁都】\n\n你将国都自%s迁至【%s】，銮驾随行。") % [old, c])
	end_month()
	return ""


# 国都缺失或已不在手中时重新确定：君主所在城优先，否则在最大的城里取兵力最多的一座
func _fix_capital(f: String) -> void:
	var cur := capital_of(f)
	if cur != "" and cities.has(cur) and cities[cur].f == f:
		return
	var lord := lord_of(f)
	var best := ""
	if gens.has(lord) and gens[lord].f == f and cities.has(gens[lord].city) and cities[gens[lord].city].f == f:
		best = gens[lord].city
	else:
		best = _best_capital(f)
	factions[f]["capital"] = best


func year_text() -> String:
	return (Lang.t("前%d年") % -year) if year < 0 else (Lang.t("%d年") % year)


# 帅旗的样子：{text, bg, fg, shape}
func emblem(f: String) -> Dictionary:
	if DB.EMBLEMS.has(f):
		var e: Array = DB.EMBLEMS[f]
		return {"text": e[0], "bg": Color(str(e[1])), "fg": Color(str(e[2])), "shape": e[3]}
	var nm := fname(f)
	if f == "player":
		nm = str(player.name)
	var bg := fcolor(f)
	return {"text": Lang.fix(nm).substr(0, 1), "bg": bg, "fg": Color("#1a1a1a") if bg.get_luminance() > 0.55 else Color("#f6f0dc"), "shape": ""}


func fcolor(f: String) -> Color:
	if factions.has(f):
		return Color(str(factions[f].color))
	return Color("#6b5a45")


func is_lord() -> bool:
	return player.f == "player"


func is_gov() -> bool:
	return player.gov != ""


func rank_name() -> String:
	if is_lord():
		return Lang.t("霸主") if player.hegemon else Lang.t("诸侯")
	if is_gov():
		return Lang.t("%s太守") % player.gov
	return DB.RANKS[int(player.rank)][0]


func squad_size() -> int:
	if is_lord():
		return DB.SQUAD_LORD
	if is_gov():
		return DB.SQUAD_GOV
	return int(DB.RANKS[int(player.rank)][2])


func can_lead() -> bool:
	return is_lord() or is_gov() or int(player.rank) >= DB.LEAD_RANK


func faction_cities(f: String) -> Array:
	var out: Array = []
	for c in cities:
		if cities[c].f == f:
			out.append(c)
	return out


func city_gens(c: String) -> Array:
	var out: Array = []
	for g in gens:
		if gens[g].city == c and gens[g].f == cities[c].f:
			out.append(g)
	out.sort_custom(func(a, b): return int(gens[a].lead) > int(gens[b].lead))
	return out


func best_lead(names: Array) -> int:
	var best := 40
	for g in names:
		if gens.has(g):
			best = maxi(best, int(gens[g].lead))
	return best


func add_log(s: String) -> void:
	log_lines.append(Lang.t("%s%d月　%s") % [year_text(), month, s])
	while log_lines.size() > 60:
		log_lines.pop_front()


# ───────────── 物品与兵种 ─────────────

func item(id: String) -> Dictionary:
	return DB.ITEMS.get(id, {})


func item_name(id: String) -> String:
	return str(item(id).get("name", Lang.t("无")))


func item_desc(id: String) -> String:
	var it := item(id)
	match str(it.get("slot", "")):
		"weapon":
			return Lang.t("%s　伤害+%d%%") % [DB.WEAPON_CN[it.w], roundi(float(it.atk) * 100.0)]
		"armor":
			return Lang.t("铠甲　生命+%d 减伤%d%%") % [int(it.hp), roundi(float(it.def) * 100.0)]
		"horse":
			return Lang.t("坐骑　速度+%d%%") % roundi((float(it.spd) - 1.0) * 100.0)
	return ""


func has_item(id: String) -> bool:
	return player.items.has(id)


# 获得物品，返回一句说明；已有的折成军资
func add_item(id: String) -> String:
	var it := item(id)
	if it.is_empty():
		return ""
	var tier: String = DB.TIER_NAMES[int(it.t)]
	if has_item(id):
		var g: int = DB.TIER_GOLD[int(it.t)]
		player.gold = int(player.gold) + g
		return Lang.t("【%s】（已有，折军资 %d）") % [it.name, g]
	player.items.append(id)
	# 空着的栏位自动装上
	var eq: Dictionary = player.eq
	if it.slot == "weapon":
		if str(eq.w1) == "":
			eq.w1 = id
		elif str(eq.w2) == "":
			eq.w2 = id
	elif str(eq[it.slot]) == "":
		eq[it.slot] = id
	return "【%s】（%s · %s）" % [it.name, tier, item_desc(id)]


# 行囊里点一下物品：兵器 未装备→主手→副手→卸下；铠甲、坐骑 装上/卸下
func equip_press(id: String) -> void:
	var it := item(id)
	if it.is_empty() or not has_item(id):
		return
	var eq: Dictionary = player.eq
	if it.slot == "weapon":
		if str(eq.w1) == id:
			eq.w1 = eq.w2
			eq.w2 = id
			if str(eq.w1) == "":
				eq.w1 = id
				eq.w2 = ""
		elif str(eq.w2) == id:
			eq.w2 = ""
		else:
			eq.w2 = eq.w1
			eq.w1 = id
	else:
		eq[it.slot] = "" if str(eq[it.slot]) == id else id
	changed.emit()


func sell_price(id: String) -> int:
	return int(DB.TIER_GOLD[int(item(id).get("t", 0))])


# 卖掉一件物品：装备着的先卸下，返回得到的军资（0 表示没有这件东西）
func sell_item(id: String) -> int:
	if not has_item(id):
		return 0
	var eq: Dictionary = player.eq
	for k in eq:
		if str(eq[k]) == id:
			eq[k] = ""
	if str(eq.w1) == "" and str(eq.w2) != "":
		eq.w1 = eq.w2
		eq.w2 = ""
	player.items.erase(id)
	var g := sell_price(id)
	player.gold = int(player.gold) + g
	add_log(Lang.t("你卖掉了%s，得军资 %d。") % [item_name(id), g])
	changed.emit()
	return g


func eq_tag(id: String) -> String:
	var eq: Dictionary = player.eq
	if str(eq.w1) == id:
		return Lang.t("主手")
	if str(eq.w2) == id:
		return Lang.t("副手")
	if str(eq.armor) == id:
		return Lang.t("已穿")
	if str(eq.horse) == id:
		return Lang.t("已骑")
	return ""


# 上阵时可轮换的兵器（至少有一把）
func weapon_slots() -> Array:
	var out: Array = []
	for k in ["w1", "w2"]:
		var id := str(player.eq[k])
		if id != "" and DB.ITEMS.has(id) and not out.has(id):
			out.append(id)
	if out.is_empty():
		out.append("iron_dao")
	return out


func _signature_free(id: String) -> bool:
	for tbl in [DB.GENERAL_ITEMS, DB.GENERAL_HORSES]:
		for g in tbl:
			if tbl[g] == id and gens.has(g):
				return false
	return true


# 随机挑一件尚未拥有的物品。wtype 仅对兵器有效（"" 不限）；名将随身之物只在其人不在世时才会流落民间
func random_item(slot: String, wtype: String, t_min: int, t_max: int) -> String:
	var pool: Array = []
	for id in DB.ITEMS:
		var it: Dictionary = DB.ITEMS[id]
		if slot != "" and it.slot != slot:
			continue
		if int(it.t) < t_min or int(it.t) > t_max or has_item(id):
			continue
		if it.slot == "weapon" and wtype != "" and it.w != wtype:
			continue
		if not _signature_free(id):
			continue
		pool.append(id)
	if pool.is_empty():
		return ""
	return pool[rng.randi() % pool.size()]


# ───────────── 军队的训练度：城里那支兵的平均水平，打仗会涨，补新兵会被冲淡 ─────────────

func vet(c: String) -> float:
	return float(cities[c].get("vet", 0.0)) if cities.has(c) else 0.0


func vet_name(v: float) -> String:
	return DB.VET_NAMES[clampi(roundi(v), 0, 5)]


# 往城里并入 n 名训练度为 v 的兵
func _merge_troops(c: String, n: int, v: float) -> void:
	var t := int(cities[c].troops)
	if t + n > 0:
		cities[c]["vet"] = clampf((vet(c) * t + v * n) / float(t + n), 0.0, 5.0)
	cities[c].troops = t + n


func act_train_city() -> String:
	var c: String = player.city
	if not (is_lord() or is_gov()) or cities[c].f != player.f:
		return Lang.t("你无权在此练兵。")
	if int(player.gold) < 100:
		return Lang.t("军资不足（操练守军需 100 金）。")
	if vet(c) >= 3.0:
		return Lang.t("%s的守军已是%s，再练也练不上去了，得靠实战。") % [c, vet_name(vet(c))]
	player.gold = int(player.gold) - 100
	cities[c]["vet"] = minf(3.0, vet(c) + 0.35)
	add_log(Lang.t("你在%s操练守军。") % c)
	notices.append(Lang.t("【练兵】\n\n%s守军操练一月，如今是：%s（%.1f）。") % [c, vet_name(vet(c)), vet(c)])
	end_month()
	return ""


# ───────────── 亲兵名册：每个兵各有兵种、经验、等级 ─────────────

const SQUAD_PATTERN := ["dao", "spear", "bow", "dao", "spear", "cav"]
const SURNAMES := "王李张刘陈杨赵黄周吴徐孙胡朱高林何郭马罗梁宋郑谢韩唐冯于董萧程曹袁邓许傅沈曾彭吕苏卢蒋蔡贾丁魏薛叶阎余潘杜戴夏钟汪田任姜范方石姚谭廖邹熊金陆郝孔白崔康毛邱秦江史顾侯邵孟龙万段雷钱汤尹黎易常武乔贺赖龚文"
const GIVEN := ["大", "二", "三", "四", "五", "六", "七", "八", "九", "十", "虎", "豹", "彪", "勇", "猛", "刚", "强", "山", "石", "铁", "牛", "柱", "栓", "福", "禄", "贵", "旺", "安", "平", "顺", "狗儿", "铁柱", "石头", "大牛", "二虎", "阿福", "长庚", "黑子", "老六", "小乙", "满仓", "得胜"]


func level_of(xp: int) -> int:
	var lv := 0
	for i in DB.TROOP_XP.size():
		if xp >= int(DB.TROOP_XP[i]):
			lv = i
	return lv


func _recruit(i: int, k := "") -> Dictionary:
	if k == "":
		k = SQUAD_PATTERN[i % SQUAD_PATTERN.size()]
		if k == "cav" and not squad_has_cav():
			k = "dao"
	return {"k": k, "xp": 0, "kills": 0, "name": SURNAMES[rng.randi() % SURNAMES.length()] + GIVEN[rng.randi() % GIVEN.size()]}


# 名册人数跟着军衔走：升了补新兵，降了裁掉资历最浅的
func squad() -> Array:
	var sq: Array = player.squad
	var want := squad_size()
	while sq.size() < want:
		sq.append(_recruit(sq.size()))
	while sq.size() > want:
		var worst := 0
		for i in sq.size():
			if int(sq[i].xp) < int(sq[worst].xp):
				worst = i
		sq.remove_at(worst)
	return sq


func soldier_rank(e: Dictionary) -> String:
	return str(DB.TROOP_TREE[e.k][level_of(int(e.xp))][0])


# 战后结算每个上阵亲兵：阵亡的由新兵顶替（从头练起），活下来的按各自斩获得经验
# res: [{i 名册序号, alive, kills}]
func apply_squad(res: Array, won: bool) -> void:
	var sq: Array = squad()
	var dead := 0
	var ups: Array = []
	for it in res:
		var i := int(it.i)
		if i < 0 or i >= sq.size():
			continue
		var e: Dictionary = sq[i]
		if not it.alive:
			dead += 1
			if level_of(int(e.xp)) >= 2:
				add_log(Lang.t("%s%s战死。") % [soldier_rank(e), e.name])
			sq[i] = _recruit(i, str(e.k))
			continue
		var before := level_of(int(e.xp))
		e.xp = int(e.xp) + 4 + int(it.kills) * 6 + (3 if won else 0)
		e.kills = int(e.get("kills", 0)) + int(it.kills)
		var after := level_of(int(e.xp))
		if after > before:
			ups.append("%s→%s" % [e.name, DB.TROOP_TREE[e.k][after][0]])
	var parts: Array = []
	if dead > 0:
		parts.append(Lang.t("阵亡 %d 人，已补入新兵") % dead)
	if not ups.is_empty():
		parts.append(Lang.t("晋级 %d 人：%s%s") % [ups.size(), "、".join(ups.slice(0, 4)), Lang.t(" 等") if ups.size() > 4 else ""])
	if not parts.is_empty():
		squad_note = (squad_note + "；" if squad_note != "" else "") + "；".join(parts)


func squad_has_cav() -> bool:
	return squad_size() >= DB.CAV_SQUAD


func act_explore() -> String:
	var c: String = player.city
	var now := year * 12 + month
	if now - int(player.explored.get(c, -99)) < 6:
		return Lang.t("%s近来已寻访过，半年后再来吧。") % c
	if int(player.hp) < 15:
		return Lang.t("体力不支，先休整几日吧。")
	player.explored[c] = now
	player.hp = int(player.hp) - 10
	var size := int(cities[c].size)
	var place: String = [Lang.t("旧货摊"), Lang.t("城外古庙"), Lang.t("铁匠铺"), Lang.t("破败的武库"), Lang.t("当铺"), Lang.t("马市")][rng.randi() % 6]
	var roll := rng.randf()
	var id := ""
	if roll >= 0.45:
		var tr := rng.randf() * 100.0
		var tier := 0
		if tr < 2.0 + size * 2.0:
			tier = 3
		elif tr < 16.0 + size * 5.0:
			tier = 2
		elif tr < 52.0:
			tier = 1
		while tier >= 0 and id == "":
			id = random_item("", "", tier, tier)
			tier -= 1
	if id != "":
		var txt := add_item(id)
		add_log(Lang.t("你在%s的%s寻得%s。") % [c, place, item_name(id)])
		notices.append(Lang.t("【寻访】\n\n你在%s的%s转了许久，\n寻得 %s！\n\n可在“行囊与部曲”中更换装备。") % [c, place, txt])
	elif roll >= 0.25:
		var g := rng.randi_range(15, 40) + size * 10
		player.gold = int(player.gold) + g
		add_log(Lang.t("你在%s寻访，得了些钱财。") % c)
		notices.append(Lang.t("【寻访】\n\n你在%s的%s帮人排解了一桩纠纷，\n得谢仪 %d 金。") % [c, place, g])
	else:
		add_log(Lang.t("你在%s寻访一月，一无所获。") % c)
		notices.append(Lang.t("【寻访】\n\n你在%s转了一个月，一无所获。") % c)
	end_month()
	return ""


func act_drill() -> String:
	if squad_size() <= 0:
		return Lang.t("你还没有亲兵可练（升至伍长后方有部曲）。")
	if int(player.gold) < 20:
		return Lang.t("军资不足（操练一月需 20 金）。")
	player.gold = int(player.gold) - 20
	var ups := 0
	for e in squad():
		var before := level_of(int(e.xp))
		e.xp = int(e.xp) + 5
		if level_of(int(e.xp)) > before:
			ups += 1
	add_log(Lang.t("你操练亲兵一月。"))
	notices.append(Lang.t("【操练】\n\n校场上杀声震天。亲兵每人经验 +5%s。") % (Lang.t("，%d 人晋级") % ups if ups > 0 else ""))
	end_month()
	return ""


func _battle_spoils(r: Dictionary) -> String:
	var txt := ""
	var got: Array = []
	for id in r.get("loot", []):
		var s := add_item(str(id))
		if s != "":
			got.append(s)
			add_log(Lang.t("你缴获了%s。") % item_name(str(id)))
	if not got.is_empty():
		txt += Lang.t("\n缴获：") + "、".join(got)
	if squad_note != "":
		txt += Lang.t("\n亲兵：") + squad_note
		squad_note = ""
	return txt


# ───────────── 玩家行动（返回 "" 表示成功，否则为拒绝理由）─────────────

func enlist(city: String) -> String:
	if not cities.has(city):
		return Lang.t("没有这座城。")
	if player.started and player.city != city:
		return Lang.t("须先抵达该城。")
	if cities[city].f == "player":
		return Lang.t("这是你自己的城池。")
	player.city = city
	player.f = cities[city].f
	player.started = true
	add_log(Lang.t("%s 于%s投入%s军，军衔：%s。") % [player.name, city, fname(player.f), rank_name()])
	changed.emit()
	return ""


func act_train() -> String:
	if int(player.hp) < 20:
		return Lang.t("体力不支，先休整几日吧。")
	player.hp = int(player.hp) - 15
	var w := int(player.war)
	var gain := 0
	if w < 45:
		gain = 2
	elif w < 60 or rng.randf() < (105.0 - w) / 60.0:
		gain = 1
	player.war = mini(100, w + gain)
	if gain > 0:
		add_log(Lang.t("你苦练武艺，武力升至 %d。") % int(player.war))
	else:
		add_log(Lang.t("你苦练一月，未有寸进。"))
	end_month()
	return ""


func act_rest() -> String:
	player.hp = mini(100, int(player.hp) + 50)
	add_log(Lang.t("你休整养伤。"))
	end_month()
	return ""


func act_move(dest: String) -> String:
	if not adj[player.city].has(dest):
		return Lang.t("只能前往相邻的城池。")
	if is_gov():
		return Lang.t("你身为太守，不可擅离职守。")
	if player.f != "" and cities[dest].f != player.f:
		return Lang.t("%s是%s的地盘，身在军中不可擅入敌境。") % [dest, fname(cities[dest].f)]
	if is_lord():      # 随驾的将领跟着走
		for g in my_gens():
			if gens[g].city == player.city and is_follower(g):
				gens[g].city = dest
	player.city = dest
	add_log(Lang.t("你动身前往%s。") % dest)
	end_month()
	return ""


func act_bandit() -> String:
	if int(player.hp) < 25:
		return Lang.t("体力不支，先休整几日吧。")
	var r := int(player.rank)
	if is_lord() or is_gov():
		r = 6
	pending_battle = {
		"type": "bandit", "att_f": "山贼", "def_f": player.f, "from": "", "to": player.city,
		"att_troops": 5 + r * 3 + rng.randi_range(0, 3), "def_troops": squad_size() + 2,
		"att_gens": [], "def_gens": [], "player_side": 1, "leads": true, "then_end": true,
	}
	changed.emit()
	return ""


func act_attack(target: String) -> String:
	var c: String = player.city
	if player.f == "":
		return Lang.t("你尚无归属，无兵可用。")
	if cities[c].f != player.f:
		return Lang.t("此城不属我方。")
	if not adj[c].has(target):
		return Lang.t("只能进攻相邻的城池。")
	if cities[target].f == player.f:
		return Lang.t("%s是我方城池。") % target
	if allied(str(cities[target].f)):
		return Lang.t("%s是盟友的城池。要打，须先在“外交”中毁约。") % target
	if int(player.hp) < 25:
		return Lang.t("体力不支，先休整几日吧。")
	var force := int(int(cities[c].troops) * 0.65)
	if force < 2000:
		return Lang.t("%s兵力不足，无力出征。") % c
	if not can_lead() and force < int(cities[target].troops) * 0.7:
		var boss: String = fname(player.f)
		var gs := city_gens(c)
		if not gs.is_empty():
			boss = gs[0]
		return Lang.t("你向%s请战，被驳回：“敌众我寡，不可轻动。”\n（升至校尉后可自行领兵。）") % boss
	var b := make_battle(c, target)
	if is_lord():
		var cg: Array = _campaign_gens(c)
		b.att_gens = cg[0]
		b["declined"] = cg[1]
	b.player_side = 0
	b.leads = can_lead()
	b.then_end = true
	pending_battle = b
	if is_lord():
		_rel_add(str(b.def_f), -30)
	add_log(Lang.t("%s军自%s出兵 %d，进攻%s。") % [fname(player.f), c, force, target])
	changed.emit()
	return ""


func act_recruit() -> String:
	var c: String = player.city
	if not (is_lord() or is_gov()) or cities[c].f != player.f:
		return Lang.t("你无权在此征兵。")
	var n := mini(int(player.gold) / 100, 3)
	if n <= 0:
		return Lang.t("军资不足（每 100 金可募 1000 兵）。")
	player.gold = int(player.gold) - n * 100
	_merge_troops(c, n * 1000, 0.0)
	add_log(Lang.t("你在%s募得新兵 %d。") % [c, n * 1000])
	end_month()
	return ""


func act_transfer(dest: String) -> String:
	var c: String = player.city
	if not is_lord() or cities[c].f != "player":
		return Lang.t("只有君主可在自己的城池调兵。")
	if not adj[c].has(dest) or cities[dest].f != "player":
		return Lang.t("只能调往相邻的己方城池。")
	var n := int(cities[c].troops) / 2
	cities[c].troops = int(cities[c].troops) - n
	_merge_troops(dest, n, vet(c))
	add_log(Lang.t("自%s调兵 %d 至%s。") % [c, n, dest])
	end_month()
	return ""


func act_independent() -> String:
	if not is_gov():
		return Lang.t("须先成为一城太守。")
	var c: String = player.gov
	var oldf: String = cities[c].f
	factions["player"] = {"name": player.name, "color": "#ffd24a", "lord": "", "capital": c}
	cities[c].f = "player"
	var refuge := ""
	for n in faction_cities(oldf):
		refuge = n
		break
	for g in gens:
		if gens[g].city == c and gens[g].f == oldf:
			if refuge != "" and (g == lord_of(oldf) or rng.randf() < 0.5):
				gens[g].city = refuge
			else:
				gens[g]["loy"] = 55
				_join(g, "player")
	player.f = "player"
	player.gov = ""
	player["diplo"] = {}
	if factions.has(oldf):
		dip(oldf).rel = -50
	add_log(Lang.t("%s 据%s自立，天下又多一路诸侯！") % [player.name, c])
	notices.append(Lang.t("你据【%s】自立为主！\n\n从此%s军视你为叛逆，四邻皆是虎狼。\n每座城每月为你带来军资，可征兵、调兵、亲自领兵出征。\n坐拥十城，即为一方霸主。") % [c, fname(oldf)])
	end_month()
	return ""


func act_leave() -> String:
	if is_lord():
		return Lang.t("君主无处可去。")
	add_log(Lang.t("你挂印而去，离开了%s军。") % fname(player.f))
	player.f = ""
	player.gov = ""
	changed.emit()
	return ""


# ───────────── 战斗 ─────────────

func make_battle(from: String, to: String) -> Dictionary:
	var force := int(int(cities[from].troops) * 0.65)
	cities[from].troops = int(cities[from].troops) - force
	return {
		"type": "siege", "att_f": cities[from].f, "def_f": cities[to].f, "from": from, "to": to,
		"att_troops": force, "def_troops": int(cities[to].troops),
		"att_gens": city_gens(from).slice(0, 3), "def_gens": city_gens(to).slice(0, 3),
		"att_vet": vet(from), "def_vet": vet(to),
		"player_side": -1, "leads": false, "then_end": false,
	}


func debug_battle() -> Dictionary:
	if not player.started:
		player.city = "陈留"
		player.f = "曹操"
		player.started = true
		player.rank = 2
	var b := make_battle("陈留", "濮阳")
	b.player_side = 0
	return b


func auto_resolve(b: Dictionary) -> Dictionary:
	var att := float(b.att_troops)
	var def := maxf(float(b.def_troops), 300.0)
	var pa := att * (1.0 + best_lead(b.att_gens) / 150.0) * (1.0 + 0.07 * float(b.get("att_vet", 0.0))) * rng.randf_range(0.75, 1.25)
	var pd := def * (1.0 + best_lead(b.def_gens) / 150.0) * (1.0 + 0.07 * float(b.get("def_vet", 0.0))) * 1.15 * rng.randf_range(0.75, 1.25)
	var r := {"winner": 0, "att_left": 0, "def_left": 0, "kills": 0, "gen_kills": 0, "hp_pct": 1.0, "player_down": false}
	if b.type == "palace":
		r.winner = 0 if rng.randf() < 0.7 else 1
		return r
	if is_capital(str(b.to)):
		def *= 1.1      # 国都城防更坚
	if pa > pd:
		r.winner = 0
		r.att_left = int(att * (1.0 - 0.5 * pd / pa))
		r.def_left = int(def * 0.35)
	else:
		r.winner = 1
		r.def_left = int(def * (1.0 - 0.4 * pa / pd))
		r.att_left = int(att * 0.4)
	return r


# 玩家参与的攻城战若攻破的是国都，还要再打一场宫城之战
func hall_name(c: String) -> String:
	if not cities.has(c):
		return Lang.t("宫城")
	var k := clampi(int(cities[c].size), 1, 3)
	var cul := culture_of(c)
	if cul == "steppe":
		return [Lang.t("大帐"), Lang.t("大帐"), Lang.t("牙帐"), Lang.t("汗庭")][k]
	if ["han", "korea", "wa"].has(cul):
		return [Lang.t("府衙"), Lang.t("府衙"), Lang.t("王府"), Lang.t("皇宫")][k]
	return [Lang.t("官署"), Lang.t("官署"), Lang.t("王宫"), Lang.t("皇宫")][k]


# ───────────── 风土：按地域（和年代）分的文化区，决定衣甲与城郭的样式 ─────────────

func culture_at(lon: float, lat: float) -> String:
	var cul := "han"
	if lon >= 97.0:
		if lon >= 129.8 and lat < 42.0:
			cul = "wa"
		elif lon >= 124.5 and lat < 41.5 and lat > 33.0:
			cul = "korea"
		elif lat >= 41.5 or (lat >= 40.5 and lon < 116.0):
			cul = "steppe"
		elif (lat < 22.5 and lon < 110.5) or (lon < 101.0 and lat < 26.5):
			cul = "sea"
	elif lon >= 92.5 and lat < 25.0:
		cul = "sea"
	elif lat < 33.5 and lat >= 28.3 and lon >= 78.0:
		cul = "tibet"
	elif lon >= 66.5 and lat < 35.2:
		cul = "india"
	elif (lat >= 43.5 and lon >= 45.0) or (lat >= 43.5 and lat < 49.0 and lon >= 28.6) or (lat >= 42.5 and lon >= 70.0 and lon < 82.0):
		cul = "steppe"
	elif lon >= 94.0:
		cul = "han"
	elif lon >= 63.0 and lat >= 35.5:
		cul = "xiyu"
	elif (lat < 29.5 and lon >= 35.0) or (lat < 32.0 and lon < 28.0):
		cul = "arab"
	elif lon < 41.5 or lat >= 49.0:
		cul = "rome"
		# 罗马化之外的北方：凯尔特、日耳曼、斯拉夫
		var late := scenario == "suitang" or scenario == "wudai"
		if scenario == "zhanguo":
			if lat >= 44.4 or (lon < 3.6 and lat >= 39.0) or (lon >= 14.0 and lon < 30.0 and lat >= 41.8) or (lon < 9.5 and lat < 38.0 and lat > 33.0):
				cul = "north"
			if lon >= 4.0 and lon < 12.0 and lat < 44.0 and lat >= 43.0:
				cul = "rome"
		elif scenario == "sanguo":
			if lat >= 55.0 or lon < -5.5 and lat >= 51.0 or (lon >= 8.5 and lat >= 49.2) or (lon >= 24.0 and lat >= 46.5):
				cul = "north"
		elif late and lat >= 45.8:
			cul = "north"
	else:
		cul = "persia"
	# 五代之时，两河、叙利亚、埃及、北非、安达卢斯已是大食风貌
	if scenario == "wudai" and ((cul == "rome" and lat < 36.5 and lon >= 30.0) or (cul == "persia" and lon < 49.0 and lat < 37.0)
			or (cul == "rome" and lon < 30.0 and lon >= 7.0 and lat < 38.5 and not (lon > 14.0 and lat > 34.0))
			or (cul == "rome" and lon < 7.0 and lat < 40.5)):
		cul = "arab"
	return cul


func culture_of(c: String) -> String:
	if not cities.has(c):
		return "han"
	return culture_at(float(cities[c].lon), float(cities[c].lat))


# 一支军队的装束跟着本国走（看国都在哪），不跟着战场走
func faction_culture(f: String, fallback_city := "") -> String:
	var cap := capital_of(f) if factions.has(f) else ""
	return culture_of(cap if cap != "" else fallback_city)


func look_of(f: String, fallback_city := "") -> String:
	return "%s:%s" % [faction_culture(f, fallback_city), scenario]


func needs_palace(b: Dictionary, r: Dictionary) -> bool:
	return b.type == "siege" and int(r.winner) == 0 and int(b.player_side) >= 0 and is_capital(str(b.to))


func finish_battle(r: Dictionary) -> void:
	var b: Dictionary = pending_battle
	pending_battle = null
	if r.has("squad"):      # 亲兵的伤亡与历练当场结算，后面若还有宫城之战，上阵的就是补过员的队伍
		apply_squad(r.squad, int(r.winner) == int(b.player_side))
	if needs_palace(b, r):
		pending_battle = {
			"type": "palace", "att_f": b.att_f, "def_f": b.def_f, "from": b.from, "to": b.to,
			"att_troops": 16, "def_troops": 10 + int(cities[b.to].size) * 2,
			"att_gens": b.att_gens, "def_gens": city_gens(str(b.to)).slice(0, 3),
			"player_side": b.player_side, "leads": b.leads, "then_end": b.then_end,
			"parent_b": b, "parent_r": r,
			"gen_hp": r.get("gen_hp", {}), "player_hp": r.get("hp_pct", 1.0),
		}
		var hurt: Dictionary = pending_battle.gen_hp      # 外城已被击破的将领不再出现在宫城
		for k in ["att_gens", "def_gens"]:
			pending_battle[k] = pending_battle[k].filter(func(g): return float(hurt.get(g, 1.0)) > 0.0)
		changed.emit()
		return
	if b.type == "palace":
		# 把两场的战果并起来，按原来那场攻城战结算
		var pr: Dictionary = b.parent_r
		var att_won: bool = int(r.winner) == 0
		var loot: Array = pr.get("loot", []).duplicate()
		loot.append_array(r.get("loot", []))
		r = {
			"winner": r.winner, "kills": int(pr.kills) + int(r.kills), "gen_kills": int(pr.gen_kills) + int(r.gen_kills),
			"hp_pct": r.hp_pct, "player_down": bool(pr.player_down) or bool(r.player_down),
			"att_left": int(pr.att_left) if att_won else int(int(pr.att_left) * 0.5),
			"def_left": int(pr.def_left) if att_won else int(pr.def_left) + 800,
			"loot": loot, "palace": true,
			"gens_down": pr.get("gens_down", []) + r.get("gens_down", []),
		}
		b = b.parent_b
	last_result = r
	apply_battle(b, r)
	if b.then_end:
		end_month()
	else:
		check_victory()
		save_game()
		changed.emit()


func apply_battle(b: Dictionary, r: Dictionary) -> void:
	if b.type == "bandit":
		var won: bool = r.winner == 1
		var m := 6 + int(r.kills) * 2 + (10 if won else 0)
		var g := (8 + int(r.kills) * 3) if won else 0
		player.merit = int(player.merit) + m
		player.gold = int(player.gold) + g
		player.kills = int(player.kills) + int(r.kills)
		player.hp = clampi(int(float(r.hp_pct) * 100.0), 10, 100)
		if won:
			add_log(Lang.t("你在%s郊外剿灭山贼，斩 %d 人。") % [b.to, int(r.kills)])
			notices.append(Lang.t("山贼溃散！\n\n亲手斩获 %d 人\n功勋 +%d　军资 +%d%s") % [int(r.kills), m, g, _battle_spoils(r)])
		else:
			add_log(Lang.t("你剿匪失利，负伤而回。"))
			notices.append(Lang.t("剿匪失利，你负伤而回。\n\n功勋 +%d%s") % [m, _battle_spoils(r)])
		check_rank()
		return
	var att_won: bool = r.winner == 0
	last_captured = []
	_downed = r.get("gens_down", [])
	var aname := fname(b.att_f)
	var dname := fname(b.def_f)
	if att_won:
		add_log(Lang.t("%s军自%s攻克%s（原属%s）。") % [aname, b.from, b.to, dname])
		_def_vet = float(b.get("def_vet", 0.0)) + 0.1
		capture_city(b.to, b.att_f, int(r.att_left), int(r.def_left))
		cities[b.to]["vet"] = minf(5.0, float(b.get("att_vet", 0.0)) + 0.3)      # 进城的是打了胜仗的那支兵
		if b.att_f == "player" and int(b.player_side) == 0:
			# 你亲征得胜：随征的将领跟你一同进驻新城
			for g in b.att_gens:
				if gens.has(g) and gens[g].f == "player" and str(gens[g].get("gov", "")) == "":
					gens[g].city = b.to
		elif b.att_gens.size() > 1:
			var mover: String = b.att_gens[b.att_gens.size() - 1]
			if gens.has(mover) and gens[mover].f == b.att_f:
				gens[mover].city = b.to
	else:
		cities[b.to].troops = maxi(int(r.def_left), 300)
		cities[b.to]["vet"] = minf(5.0, float(b.get("def_vet", 0.0)) + 0.25)
		_merge_troops(str(b.from), int(r.att_left), float(b.get("att_vet", 0.0)) + 0.1)
		add_log(Lang.t("%s军攻%s不克，败退%s。") % [aname, b.to, b.from])
		_take_captives(b.att_gens, str(b.def_f), str(b.to), 0.1)
	if int(b.player_side) >= 0:
		_player_after_battle(b, r, att_won)


func _player_after_battle(b: Dictionary, r: Dictionary, att_won: bool) -> void:
	var side := int(b.player_side)
	var won: bool = int(r.winner) == side
	var m := 10 + int(r.kills) * 3 + int(r.gen_kills) * 40 + (20 if won else 0)
	if b.leads:
		m = int(m * 1.5)
	var g := int(r.kills) * 2 + (40 if won else 5)
	player.merit = int(player.merit) + m
	player.gold = int(player.gold) + g
	player.kills = int(player.kills) + int(r.kills)
	player.hp = clampi(int(float(r.hp_pct) * 100.0), 10, 100)
	var head := ""
	if side == 0:
		head = (Lang.t("攻克【%s】！") % b.to) if won else (Lang.t("进攻【%s】失利，全军退回%s。") % [b.to, b.from])
		if r.get("palace", false) and not won:
			head = Lang.t("已破【%s】外城，却在宫城折戟，全军退回%s。") % [b.to, b.from]
	else:
		head = (Lang.t("【%s】守住了！") % b.to) if won else (Lang.t("【%s】陷落……") % b.to)
	var txt := Lang.t("%s\n\n亲手斩获 %d 人，击破敌将 %d 员\n功勋 +%d　军资 +%d") % [head, int(r.kills), int(r.gen_kills), m, g]
	txt += _battle_spoils(r)
	if is_lord():
		_morale(won)
	if not last_captured.is_empty():
		txt += Lang.t("\n俘获：%s（到“将领与俘虏”中发落）") % "、".join(last_captured)
	if r.player_down:
		txt += Lang.t("\n你身负重伤，被袍泽拼死救下。")
	notices.append(txt)
	if side == 0 and att_won and not is_gov() and cities[b.to].f == player.f:
		player.city = b.to
		if b.leads and not is_lord() and int(player.rank) >= 5:
			player.gov = b.to
			add_log(Lang.t("%s 因功受封%s太守。") % [player.name, b.to])
			notices.append(Lang.t("主公论功行赏：封你为【%s太守】！\n\n你现在可以在此征兵、领兵出征，\n羽翼丰满之后，亦可……自立为主。") % b.to)
	check_rank()


func capture_city(c: String, newf: String, garrison: int, def_left: int) -> void:
	var oldf: String = cities[c].f
	var was_capital := is_capital(c)
	var old_lord := lord_of(oldf)
	cities[c].f = newf
	cities[c].troops = maxi(garrison, 300)
	var left: Array = faction_cities(oldf)
	var old_gens: Array = []
	for g in gens:
		if gens[g].city == c and gens[g].f == oldf:
			old_gens.append(g)
	for g in gens.keys():      # 城中关押的俘虏趁乱脱身
		if str(gens[g].get("held", "")) == oldf and gens[g].city == c:
			var home := str(gens[g].get("from", ""))
			gens[g]["held"] = ""
			if home != "" and factions.has(home) and not faction_cities(home).is_empty():
				gens[g].f = home
				gens[g].city = capital_of(home)
	if not left.is_empty():
		_take_captives(old_gens, newf, c, 0.25)
		old_gens = old_gens.filter(func(g): return gens.has(g) and gens[g].f == oldf)
		# 国都陷落：迁都到剩下的城里兵力最多的一座
		if was_capital:
			var cap := _best_capital(oldf)
			factions[oldf]["capital"] = cap
			add_log(Lang.t("%s国都%s陷落，迁都%s。") % [fname(oldf), c, cap])
			if oldf == "player":
				notices.append(Lang.t("国都【%s】陷落！\n\n你率残部迁都【%s】，重整旗鼓。") % [c, cap])
			elif player.started and player.f == oldf:
				notices.append(Lang.t("国都【%s】陷落，%s迁都【%s】。") % [c, fname(oldf), cap])
		var refuge := ""
		for n in adj[c]:
			if cities[n].f == oldf:
				refuge = n
				break
		if refuge == "" or was_capital:
			refuge = capital_of(oldf) if capital_of(oldf) != "" else left[0]
		_merge_troops(refuge, def_left, _def_vet)
		for g in old_gens:
			gens[g].city = capital_of(oldf) if g == old_lord else refuge
		if player.started and player.f == oldf and player.city == c:
			player.city = refuge
			if player.gov == c:
				player.gov = ""
				notices.append(Lang.t("你丢了【%s】，太守之位不保，随军退往%s。") % [c, refuge])
	else:
		# 最后一城陷落：势力灭亡，昭告天下
		var all_gens: Array = []
		for g in gens:
			if gens[g].f == oldf:
				all_gens.append(g)
		var dead_name := fname(oldf)
		factions.erase(oldf)
		for g in all_gens:      # 国灭：上下人等尽数被俘
			_make_captive(g, newf, c, g == old_lord, _downed.has(g))
		add_log(Lang.t("【%s】为【%s】所灭。") % [dead_name, fname(newf)])
		if player.started:
			notices.append(Lang.t("【天下震动】\n\n%s%d月，%s陷落。\n【%s】为【%s】所灭！") % [year_text(), month, c, dead_name, fname(newf)])
		if oldf == "player":
			player.f = ""
			player["diplo"] = {}
			player.rank = 5
			player.hegemon = false
			notices.append(Lang.t("最后一座城池陷落，你的基业尽失……\n\n留得青山在：你以在野之身（将军衔）可另投明主，东山再起。"))
		elif player.f == oldf:
			player.f = ""
			player.gov = ""
			notices.append(Lang.t("主家【%s】覆灭，你流落在野。\n\n军衔与功勋仍在，可前往别处另投明主。") % dead_name)
	if cities[c].f == newf and capital_of(newf) == "":
		_fix_capital(newf)


# ───────────── 将领：性格、俘虏、忠诚、俸禄 ─────────────

func trait_of(g: String) -> String:
	if DB.GENERAL_TRAITS.has(g):
		return DB.GENERAL_TRAITS[g]
	var h := absi(hash(g)) % 100
	if h < 22:
		return "loyal"
	if h < 42:
		return "greedy"
	if h < 60:
		return "proud"
	if h < 85:
		return "easy"
	return "ambitious"


func trait_name(g: String) -> String:
	return DB.TRAITS[trait_of(g)][0]


# 招募金：招降成功时一次付清，本事越大越贵
func fee(g: String) -> int:
	return int((30 + (int(gens[g].war) + int(gens[g].lead)) / 2) / 5) * 5


func is_captive(g: String) -> bool:
	return gens.has(g) and str(gens[g].get("held", "")) != ""


func is_free_agent(g: String) -> bool:
	return gens.has(g) and str(gens[g].f) == "" and str(gens[g].get("held", "")) == ""


# 归入某势力麾下
func _join(g: String, f: String, city := "") -> void:
	gens[g].f = f
	gens[g]["held"] = ""
	gens[g]["gov"] = ""
	gens[g]["summon"] = false
	if city != "":
		gens[g].city = city
	if f == "player":
		gens[g]["loy"] = clampi(int(gens[g].get("loy", 50)), 40, 75)


func my_gens() -> Array:
	var out: Array = []
	for g in gens:
		if gens[g].f == "player":
			out.append(g)
	out.sort_custom(func(a, b): return int(gens[a].war) + int(gens[a].lead) > int(gens[b].war) + int(gens[b].lead))
	return out


func my_captives() -> Array:
	var out: Array = []
	for g in gens:
		if str(gens[g].get("held", "")) == "player":
			out.append(g)
	return out


# 流落在我方城中的在野人物
func my_free_agents() -> Array:
	var out: Array = []
	for g in gens:
		if is_free_agent(g) and cities.has(gens[g].city) and cities[gens[g].city].f == "player":
			out.append(g)
	return out


func income() -> int:
	var n := 0
	for c in faction_cities("player"):
		n += int(DB.CITY_INCOME[clampi(int(cities[c].size), 1, 3)])
		if capital_of("player") == c:
			n += DB.CAPITAL_INCOME
	return n


# 忠诚的底线：没有赏赐和胜仗撑着，每月会朝这个数滑落 1 点
func loyalty_floor(g: String) -> int:
	match trait_of(g):
		"loyal":
			return 70
		"easy":
			return 55
		"proud":
			return 58 if (int(player.war) >= int(gens[g].war) or player.hegemon) else 38
		"greedy":
			return 26
		"ambitious":
			return 18
	return 45


# 招降成功率
func recruit_chance(g: String, rich := false) -> float:
	var tr := trait_of(g)
	var p := float(DB.TRAITS[tr][2])
	var from := str(gens[g].get("from", ""))
	var home_alive: bool = from != "" and factions.has(from)
	match tr:
		"loyal":
			if not home_alive:
				p += 0.25
		"greedy":
			if rich:
				p += 0.25
		"proud":
			if gens[g].get("beaten", false) or int(player.war) >= int(gens[g].war):
				p += 0.3
	if rich:
		p += 0.2
	if gens[g].get("was_lord", false):
		p -= 0.2
	if is_free_agent(g):
		p += 0.25
	var held := year * 12 + month - int(gens[g].get("since", year * 12 + month))
	p += minf(0.2, held * 0.02)      # 关得越久越容易松口
	return clampf(p, 0.02, 0.95)


func chance_text(p: float) -> String:
	if p >= 0.6:
		return Lang.t("易")
	if p >= 0.35:
		return Lang.t("中")
	if p >= 0.18:
		return Lang.t("难")
	return Lang.t("极难")


# 俘获（或擒获）一名人物。玩家为君主时留待发落；别的势力当场劝降，不从则放归或流落在野
func _make_captive(g: String, captor: String, city: String, was_lord := false, beaten := false) -> void:
	if not gens.has(g):
		return
	var from := str(gens[g].f)
	gens[g]["gov"] = ""
	if captor == "player":
		gens[g]["from"] = from
		gens[g]["held"] = "player"
		gens[g]["since"] = year * 12 + month
		gens[g]["tried"] = -9999
		gens[g]["was_lord"] = was_lord
		gens[g]["beaten"] = beaten
		gens[g].f = ""
		gens[g].city = city
		last_captured.append(g)
		return
	var p := 0.15 if was_lord else float(DB.TRAITS[trait_of(g)][2]) * 0.6 + 0.2
	if from != "" and factions.has(from) and not faction_cities(from).is_empty():
		if rng.randf() < p * 0.6:
			_join(g, captor, city)
			add_log(Lang.t("%s 兵败被俘，降了%s。") % [g, fname(captor)])
		else:
			gens[g].city = capital_of(from)      # 逃归或被放还
	elif rng.randf() < p:
		_join(g, captor, city)
		add_log(Lang.t("%s 归降%s。") % [g, fname(captor)])
	else:
		gens[g].f = ""
		gens[g]["held"] = ""
		gens[g].city = city
		add_log(Lang.t("%s 不肯归降，流落在野。") % g)


# 一批战败的武将各自碰运气：p 为寻常几率，被玩家亲手击破的更难脱身
func _take_captives(names: Array, captor: String, city: String, p: float) -> void:
	if not factions.has(captor):
		return
	for g in names:
		if not gens.has(g) or gens[g].f == captor or g == lord_of(str(gens[g].f)):
			continue
		var beaten: bool = captor == "player" and _downed.has(g)
		if rng.randf() < (0.7 if beaten else p):
			_make_captive(g, captor, city, false, beaten)


# 君主对俘虏、在野人物、麾下将领的处置。返回要告诉玩家的话。
func act_recruit_gen(g: String, rich := false) -> String:
	if not is_lord() or not gens.has(g) or not (str(gens[g].get("held", "")) == "player" or is_free_agent(g)):
		return Lang.t("此人不在你掌握之中。")
	var now := year * 12 + month
	if int(gens[g].get("tried", -9999)) == now:
		return Lang.t("%s 本月已经谈过，下月再说。") % g
	var cost := fee(g) * (2 if rich else 1)
	if int(player.gold) < cost:
		return Lang.t("军资不足：招募金需 %d 金（谈成才付）。") % cost
	var p := recruit_chance(g, rich)
	gens[g]["tried"] = now
	if rng.randf() < p:
		player.gold = int(player.gold) - cost
		gens[g]["loy"] = 50 + (12 if rich else 0) + (8 if trait_of(g) == "easy" else 0)
		_join(g, "player")
		add_log(Lang.t("%s 归降，投入你麾下。") % g)
		changed.emit()
		return Lang.t("【%s】沉吟良久，终于拜倒：“愿效犬马之劳。”\n\n武力 %d　统率 %d　性格：%s\n付招募金 %d 金") % [g, int(gens[g].war), int(gens[g].lead), trait_name(g), cost]
	changed.emit()
	return Lang.t("【%s】%s\n\n（性格：%s。没谈成不花钱；下月可以再试，关得越久越容易松口。）") % [g, [Lang.t("冷笑不语。"), Lang.t("别过头去：“要杀便杀。”"), Lang.t("只说还要再想想。")][rng.randi() % 3], trait_name(g)]


func act_release(g: String) -> String:
	if not is_captive(g) or str(gens[g].held) != "player":
		return Lang.t("此人不是你的俘虏。")
	var from := str(gens[g].get("from", ""))
	gens[g]["held"] = ""
	var where := Lang.t("流落在野")
	if from != "" and factions.has(from) and not faction_cities(from).is_empty():
		gens[g].f = from
		gens[g].city = capital_of(from)
		where = Lang.t("回%s去了") % fname(from)
	for o in my_gens():      # 仁义之举，忠义之士看在眼里
		if trait_of(o) == "loyal":
			gens[o]["loy"] = mini(100, int(gens[o].get("loy", 50)) + 3)
	add_log(Lang.t("你释放了%s。") % g)
	changed.emit()
	return Lang.t("你命人解开绳索，放【%s】离去。他%s。") % [g, where]


func act_execute(g: String) -> String:
	if not is_captive(g) or str(gens[g].held) != "player":
		return Lang.t("此人不是你的俘虏。")
	gens.erase(g)
	for o in my_gens():
		gens[o]["loy"] = maxi(0, int(gens[o].get("loy", 50)) - (8 if trait_of(o) == "loyal" else 4))
	add_log(Lang.t("你下令处斩%s。") % g)
	changed.emit()
	return Lang.t("【%s】伏诛。\n\n帐下诸将默然，人人自危（忠诚下降）。") % g


func act_gift(g: String) -> String:
	if not gens.has(g) or gens[g].f != "player":
		return Lang.t("此人不在你麾下。")
	if int(gens[g].get("loy", 50)) >= 100:
		return ""      # 忠诚已满，不必再赏，也不花钱
	if int(player.gold) < 50:
		return Lang.t("军资不足（赏赐需 50 金）。")
	player.gold = int(player.gold) - 50
	var up: int = {"greedy": 15, "loyal": 5}.get(trait_of(g), 8)
	gens[g]["loy"] = mini(100, int(gens[g].get("loy", 50)) + up)
	changed.emit()
	return ""


# ───────────── 太守与自由行动的将领 ─────────────

func gov_of(c: String) -> String:
	for g in gens:
		if gens[g].f == "player" and str(gens[g].get("gov", "")) == c:
			return g
	return ""


func is_gov_gen(g: String) -> bool:
	return gens.has(g) and str(gens[g].get("gov", "")) != ""


# 在你身边、愿意跟着你走的将领
func is_follower(g: String) -> bool:
	return gens.has(g) and gens[g].f == "player" and not is_gov_gen(g) and gens[g].city == player.city and int(gens[g].get("loy", 50)) >= 40


func role_text(g: String) -> String:
	if is_gov_gen(g):
		return Lang.t("%s太守（%s）") % [gens[g].gov, Lang.t("伺机进取") if gens[g].get("agg", false) else Lang.t("固守")]
	if gens[g].get("summon", false) and gens[g].city != player.city:
		return Lang.t("奉召赶来（现于%s）") % gens[g].city
	if gens[g].city == player.city:
		return Lang.t("随驾") if is_follower(g) else Lang.t("在%s（心怀不满，不肯随行）") % gens[g].city
	return Lang.t("自行驻于%s") % gens[g].city


func act_appoint(g: String) -> String:
	if not is_lord() or not gens.has(g) or gens[g].f != "player":
		return Lang.t("此人不在你麾下。")
	var c: String = gens[g].city
	if not cities.has(c) or cities[c].f != "player":
		return Lang.t("%s不在你手中。") % c
	var cur := gov_of(c)
	if cur != "":
		gens[cur]["gov"] = ""
	gens[g]["gov"] = c
	gens[g]["summon"] = false
	gens[g]["loy"] = mini(100, int(gens[g].get("loy", 50)) + 4)      # 委以重任
	add_log(Lang.t("你任命%s为%s太守。") % [g, c])
	changed.emit()
	return ""


func act_dismiss(g: String) -> String:
	if not is_gov_gen(g) or gens[g].f != "player":
		return Lang.t("此人并非太守。")
	gens[g]["gov"] = ""
	changed.emit()
	return ""


# 召到身边：此后每月朝你所在的城赶一程
func act_summon(g: String) -> String:
	if not gens.has(g) or gens[g].f != "player":
		return Lang.t("此人不在你麾下。")
	if is_gov_gen(g):
		return Lang.t("%s身为太守，须先免职才能调动。") % g
	if gens[g].city == player.city:
		return Lang.t("%s已在你身边。") % g
	gens[g]["summon"] = true
	changed.emit()
	return ""


# 从 a 城沿己方城池走向 b 城的下一站；走不通返回 ""
func _step_toward(a: String, b: String) -> String:
	if a == b:
		return ""
	var prev := {b: ""}
	var queue: Array = [b]
	while not queue.is_empty():
		var c: String = queue.pop_front()
		for n in adj[c]:
			if not prev.has(n) and cities[n].f == "player":
				prev[n] = c
				if n == a:
					return c
				queue.append(n)
	return ""


func _is_frontier(c: String) -> bool:
	for n in adj[c]:
		if cities[n].f != "player":
			return true
	return false


# 每月：不是太守的将领自己拿主意——赶去随驾，或去守边，或留在原地
func _free_gens_month() -> void:
	for g in my_gens():
		if is_gov_gen(g):
			if not cities.has(gens[g].gov) or cities[gens[g].gov].f != "player":
				gens[g]["gov"] = ""      # 城丢了，太守之职自然没了
			else:
				gens[g].city = gens[g].gov
			continue
		var here: String = gens[g].city
		if not cities.has(here) or cities[here].f != "player":
			gens[g].city = capital_of("player")
			continue
		var loy := int(gens[g].get("loy", 50))
		if here == player.city:
			gens[g]["summon"] = false
			continue
		var p := 0.7 if loy >= 70 else (0.45 if loy >= 50 else 0.15)
		if trait_of(g) == "proud":
			p += 0.1
		if gens[g].get("summon", false) or rng.randf() < p:
			var nxt := _step_toward(here, str(player.city))
			if nxt != "":
				gens[g].city = nxt
				if nxt == player.city:
					gens[g]["summon"] = false
					add_log(Lang.t("%s 赶到%s，随驾听用。") % [g, nxt])
		elif not _is_frontier(here) and rng.randf() < 0.35:
			# 腹地无事，自行去邻近的边城驻防
			for n in adj[here]:
				if cities[n].f == "player" and _is_frontier(n):
					gens[g].city = n
					break


# 你亲自出征时谁跟着去：本城的太守留守，其余将领按忠诚决定；邻城的忠心之将也可能赶来
# 返回 [随征, 推托不去]
func _campaign_gens(c: String) -> Array:
	var joined: Array = []
	var declined: Array = []
	for g in city_gens(c):
		if is_gov_gen(g):
			continue
		var loy := int(gens[g].get("loy", 50))
		var p := 1.0 if loy >= 60 else (0.75 if loy >= 40 else 0.3)
		if rng.randf() < p:
			joined.append(g)
		else:
			declined.append(g)
	for n in adj[c]:
		if cities[n].f != "player":
			continue
		for g in city_gens(n):
			if not is_gov_gen(g) and int(gens[g].get("loy", 50)) >= 60 and rng.randf() < 0.5:
				gens[g].city = c
				joined.append(g)
	joined.sort_custom(func(a, b): return int(gens[a].war) + int(gens[a].lead) > int(gens[b].war) + int(gens[b].lead))
	return [joined.slice(0, 4), declined]


# 每月：收税；忠诚朝底线滑落；离心者出走
func _court_month() -> void:
	player.gold = int(player.gold) + income()
	for g in my_gens():
		var loy := int(gens[g].get("loy", 50))
		var fl := loyalty_floor(g)
		if loy > fl:
			loy -= 1
		elif loy < fl:
			loy += 1
		gens[g]["loy"] = loy
		if loy < 25 and rng.randf() < 0.12:
			# 出走：投奔邻近的别家，没有就流落在野
			var dest := ""
			for n in adj[gens[g].city]:
				if cities[n].f != "player":
					dest = n
					break
			if dest != "":
				_join(g, str(cities[dest].f), dest)
				add_log(Lang.t("%s 弃你而去，投了%s。") % [g, fname(cities[dest].f)])
				notices.append(Lang.t("【将领出走】\n\n%s 对你心怀不满，连夜出奔，投了%s。\n（忠诚过低。可在“将领与俘虏”中赏赐。）") % [g, fname(cities[dest].f)])
			else:
				gens[g].f = ""
				add_log(Lang.t("%s 挂印而去。") % g)
				notices.append(Lang.t("【将领出走】\n\n%s 对你心怀不满，挂印而去。") % g)


# 胜败牵动军心
func _morale(won: bool) -> void:
	for g in my_gens():
		gens[g]["loy"] = clampi(int(gens[g].get("loy", 50)) + (3 if won else -2), 0, 100)


# 每年正月：到了登场年份的人物出仕
func _arrivals() -> void:
	for g in gens.keys():
		if is_free_agent(g) and cities.has(gens[g].city):
			var owner := str(cities[gens[g].city].f)
			if owner != "player" and rng.randf() < 0.4:
				_join(g, owner)
				add_log(Lang.t("在野的%s出仕%s。") % [g, fname(owner)])
	for a in era.get("later", []):
		if int(a[0]) != year or gens.has(a[1]):
			continue
		var f := str(a[2])
		var c := str(a[3])
		if f == "" or not factions.has(f) or faction_cities(f).is_empty():
			# 原定的主家不在了：投奔家乡所在城的主人，再不然去最大的一家
			f = ""
			if cities.has(c):
				f = str(cities[c].f)
			else:
				for ff in factions:
					if f == "" or faction_cities(ff).size() > faction_cities(f).size():
						f = ff
		if f == "" or not factions.has(f):
			continue
		if not cities.has(c) or cities[c].f != f:
			c = capital_of(f)
		if c == "":
			continue
		gens[a[1]] = {"f": f, "city": c, "war": int(a[4]), "lead": int(a[5])}
		add_log(Lang.t("%s 出仕%s，现于%s。") % [a[1], fname(f), c])
		if player.started and player.f == f:
			notices.append(Lang.t("【人才来投】\n\n%s 前来投效我军，现于%s。\n武力 %d　统率 %d") % [a[1], c, int(a[4]), int(a[5])])


func check_rank() -> void:
	if is_lord() or is_gov():
		return
	while int(player.rank) < DB.RANKS.size() - 1 and int(player.merit) >= int(DB.RANKS[int(player.rank) + 1][1]):
		player.rank = int(player.rank) + 1
		var rk: Array = DB.RANKS[int(player.rank)]
		add_log(Lang.t("%s 晋升为%s。") % [player.name, rk[0]])
		var extra := ""
		if int(player.rank) == DB.LEAD_RANK:
			extra = Lang.t("\n从此可自行领兵出征，不必再看上官脸色。")
		elif int(player.rank) == DB.RANKS.size() - 1:
			extra = Lang.t("\n亲自领兵攻下一城，即可受封太守。")
		notices.append(Lang.t("积功晋升：【%s】\n\n麾下亲兵 %d 人。%s") % [rk[0], int(rk[2]), extra])


func check_victory() -> void:
	if not is_lord():
		return
	var n := faction_cities("player").size()
	if n >= cities.size() and not player.unified:
		player.unified = true
		notices.append(Lang.t("天下一统！\n\n%s%d月，%s 自一介士卒起于行伍，终扫平群雄，四海归一。") % [year_text(), month, player.name])
	elif n >= 10 and not player.hegemon:
		player.hegemon = true
		notices.append(Lang.t("坐拥十城——你已是威震天下的【一方霸主】！\n\n可以继续征战，直至一统天下。"))


# ───────────── 遣将出征 ─────────────

# 胜算（攻守战力之比）
func odds(c: String, target: String, leaders: Array) -> float:
	var pa := int(cities[c].troops) * 0.65 * (1.0 + best_lead(leaders) / 150.0) * (1.0 + 0.07 * vet(c))
	var pd := maxf(float(cities[target].troops), 300.0) * (1.0 + best_lead(city_gens(target)) / 150.0) * (1.0 + 0.07 * vet(target)) * 1.15
	if is_capital(target):
		pd *= 1.1
	return pa / pd


func odds_text(x: float) -> String:
	if x >= 1.5:
		return Lang.t("胜算很大")
	if x >= 1.15:
		return Lang.t("胜算较大")
	if x >= 0.9:
		return Lang.t("五五开")
	if x >= 0.65:
		return Lang.t("胜算较小")
	return Lang.t("凶多吉少")


# 本城可以派出去的将领（统率高的在前；太守也能带兵，打完回任）
func dispatch_gens(c: String) -> Array:
	var out: Array = []
	for g in city_gens(c):
		if gens[g].f == "player" and int(gens[g].get("loy", 50)) >= 40:
			out.append(g)
	out.sort_custom(func(a, b): return int(gens[a].lead) > int(gens[b].lead))
	out = out.slice(0, 3)
	out.sort_custom(func(a, b): return is_gov_gen(a) and not is_gov_gen(b))      # 太守排前，进驻新城的是别人
	return out


# 一支不由你亲率的军队出征：按数值结算，回报战果
func _send_army(c: String, target: String, leaders: Array, own_idea: bool) -> bool:
	var b := make_battle(c, target)
	b.att_gens = leaders
	var df := str(b.def_f)
	var dn := fname(df)
	_rel_add(df, -30)
	var force := int(b.att_troops)
	var r := auto_resolve(b)
	apply_battle(b, r)
	var won: bool = int(r.winner) == 0
	var chief: String = leaders[0]
	for g in leaders:
		if gens.has(g) and gens[g].f == "player":
			gens[g]["loy"] = clampi(int(gens[g].get("loy", 50)) + (3 if won else -1), 0, 100)
	var how := Lang.t("见有机可乘，自行") if own_idea else Lang.t("奉命")
	var txt := ""
	if won:
		txt = Lang.t("【捷报】\n\n%s %s率兵 %d 自%s出征，攻克%s的【%s】！\n入城之兵 %d。") % [chief, how, force, c, dn, target, int(cities[target].troops)]
		if not last_captured.is_empty():
			txt += Lang.t("\n俘获：%s（到“将领与俘虏”中发落）") % "、".join(last_captured)
	else:
		txt = Lang.t("【败报】\n\n%s %s率兵 %d 自%s进攻%s的【%s】，不克而还。\n残兵 %d 退回%s。") % [chief, how, force, c, dn, target, int(r.att_left), c]
	notices.append(txt)
	return won


func act_dispatch(target: String) -> String:
	var c: String = player.city
	if not is_lord() or cities[c].f != "player":
		return Lang.t("只有君主可在自己的城池遣将出征。")
	if not adj[c].has(target) or cities[target].f == "player":
		return Lang.t("只能进攻相邻的敌城。")
	if allied(str(cities[target].f)):
		return Lang.t("%s是盟友的城池。要打，须先在“外交”中毁约。") % target
	if int(int(cities[c].troops) * 0.65) < 2000:
		return Lang.t("%s兵力不足，无力出征。") % c
	var ld := dispatch_gens(c)
	if ld.is_empty():
		return Lang.t("%s城中没有肯领命的将领。\n（忠诚 40 以上的将领才会替你带兵；可把人召到身边。）") % c
	add_log(Lang.t("你命%s自%s出兵，进攻%s。") % [ld[0], c, target])
	_send_army(c, target, ld, false)
	end_month()
	return ""


func act_stance(g: String) -> String:
	if not is_gov_gen(g) or gens[g].f != "player":
		return Lang.t("此人并非太守。")
	gens[g]["agg"] = not gens[g].get("agg", false)
	changed.emit()
	return ""


# 每月：奉命“伺机进取”的太守，看准了就自己出兵
func _gov_campaigns() -> void:
	for g in my_gens():
		if not is_gov_gen(g) or not gens[g].get("agg", false):
			continue
		var c: String = gens[g].gov
		if not cities.has(c) or cities[c].f != "player" or gens[g].city != c or int(cities[c].troops) < 4000:
			continue
		if int(gens[g].get("loy", 50)) < 40 or rng.randf() > 0.5:
			continue
		var ld: Array = [g]
		for o in dispatch_gens(c):
			if o != g and ld.size() < 3:
				ld.append(o)
		var need := 1.0 if ["proud", "ambitious"].has(trait_of(g)) else 1.2      # 心高气傲的更敢赌
		var best := ""
		for n in adj[c]:
			var f := str(cities[n].f)
			if f == "player" or allied(f):
				continue
			var x := odds(c, n, ld)
			if x > need:
				need = x
				best = n
		if best != "":
			add_log(Lang.t("%s太守%s自行出兵，进攻%s。") % [c, g, best])
			_send_army(c, best, ld, true)


# ───────────── 外交 ─────────────

const PACT_MONTHS := 24


func dip(f: String) -> Dictionary:
	if not player.has("diplo"):
		player["diplo"] = {}
	if not player.diplo.has(f):
		player.diplo[f] = {"rel": 0, "pact": 0, "cool": 0}
	return player.diplo[f]


func allied(f: String) -> bool:
	return player.f == "player" and f != "player" and factions.has(f) and player.get("diplo", {}).has(f) and int(player.diplo[f].pact) > 0


func _rel_add(f: String, d: int) -> void:
	if player.f != "player" or f == "player" or not factions.has(f):
		return
	dip(f).rel = clampi(int(dip(f).rel) + d, -100, 100)


func rel_name(v: int) -> String:
	if v >= 60:
		return Lang.t("亲厚")
	if v >= 25:
		return Lang.t("友善")
	if v > -25:
		return Lang.t("平淡")
	if v > -60:
		return Lang.t("交恶")
	return Lang.t("仇深")


func borders(a: String, b: String) -> bool:
	for e in edges:
		var x := str(cities[e[0]].f)
		var y := str(cities[e[1]].f)
		if (x == a and y == b) or (x == b and y == a):
			return true
	return false


# 别家势力，城多的在前
func other_factions() -> Array:
	var out: Array = []
	for f in factions:
		if f != "player" and not faction_cities(f).is_empty():
			out.append(f)
	out.sort_custom(func(a, b): return faction_cities(a).size() > faction_cities(b).size())
	return out


# 对方肯不肯结盟：看交情、看有没有共同的强邻、看除了你它还有没有别的出路
func ally_chance(f: String) -> float:
	var p := 0.3 + int(dip(f).rel) / 150.0
	var mine := faction_cities("player").size()
	var theirs := faction_cities(f).size()
	var other_nb := 0
	var threat := false
	for o in factions:
		if o == f or o == "player" or not borders(o, f):
			continue
		other_nb += 1
		if faction_cities(o).size() > theirs:
			threat = true
	if threat:
		p += 0.2
	if not borders(f, "player"):
		p += 0.1      # 远交近攻：不接壤的好谈
	elif other_nb == 0:
		p -= 0.3      # 它只能朝你扩张
	if theirs >= mine * 3:
		p -= 0.15     # 瞧不上你
	elif mine >= theirs * 2:
		p += 0.1      # 畏你兵威
	if allied(f):
		p += 0.25     # 续盟
	return clampf(p, 0.03, 0.92)


func act_envoy_gift(f: String) -> String:
	if not is_lord() or not factions.has(f):
		return Lang.t("无从遣使。")
	if int(player.gold) < 100:
		return Lang.t("军资不足（送礼需 100 金）。")
	player.gold = int(player.gold) - 100
	_rel_add(f, 15)
	add_log(Lang.t("你遣使向%s送礼。") % fname(f))
	changed.emit()
	return ""


func act_ally(f: String) -> String:
	if not is_lord() or not factions.has(f):
		return Lang.t("无从遣使。")
	var d := dip(f)
	if int(d.cool) > 0:
		return Lang.t("%s刚回绝过你，%d 个月后再议。") % [fname(f), int(d.cool)]
	var renew := allied(f)
	if rng.randf() < ally_chance(f):
		d.pact = PACT_MONTHS
		d.rel = maxi(int(d.rel), 40)
		add_log(Lang.t("你与%s%s，为期两年。") % [fname(f), Lang.t("续盟") if renew else Lang.t("结盟")])
		changed.emit()
		return Lang.t("【盟约】\n\n%s答应与你%s，为期 %d 个月。\n\n盟约期内两家互不侵犯；\n敌军来犯你与盟友接壤的城池时，盟友可能发兵相助。") % [fname(f), Lang.t("续盟") if renew else Lang.t("结盟"), PACT_MONTHS]
	d.cool = 3
	d.rel = maxi(-100, int(d.rel) - 3)
	changed.emit()
	return Lang.t("%s婉拒了你的%s之请。\n\n（多送几次礼，或等它被强邻逼急了再谈。）") % [fname(f), Lang.t("续盟") if renew else Lang.t("结盟")]


# 背盟：天下人都看着
func act_break(f: String) -> String:
	if not allied(f):
		return Lang.t("两家并无盟约。")
	var d := dip(f)
	d.pact = 0
	d.rel = -60
	d.cool = 12
	for o in factions:
		if o != f:
			_rel_add(o, -15)
	for g in my_gens():
		gens[g]["loy"] = maxi(0, int(gens[g].get("loy", 50)) - (10 if trait_of(g) == "loyal" else 4))
	add_log(Lang.t("你撕毁了与%s的盟约。") % fname(f))
	changed.emit()
	return Lang.t("【背盟】\n\n你撕毁了与%s的盟约。\n\n各家对你的观感都差了一截，麾下将领也颇有微词（重义之人尤甚）。") % fname(f)


func _diplo_month() -> void:
	if not player.has("diplo"):
		player["diplo"] = {}
	for f in player.diplo.keys():
		if not factions.has(f):
			player.diplo.erase(f)
			continue
		var d: Dictionary = player.diplo[f]
		d.cool = maxi(0, int(d.cool) - 1)
		if int(d.pact) > 0:
			d.pact = int(d.pact) - 1
			if int(d.rel) < 70:
				d.rel = int(d.rel) + 1
			if int(d.pact) == 0:
				add_log(Lang.t("与%s的盟约期满。") % fname(f))
				notices.append(Lang.t("【盟约期满】\n\n你与%s的盟约到期了。\n从此两家各凭本事；想续，就到“外交”里再遣使。") % fname(f))
			elif int(d.pact) == 3:
				notices.append(Lang.t("与%s的盟约还剩 3 个月。可到“外交”里续盟。") % fname(f))
		elif int(d.rel) != 0:
			d.rel = int(d.rel) - signi(int(d.rel))


# 敌军来犯：接壤的盟友可能发兵相助
func _ally_aid(b: Dictionary) -> void:
	for n in adj[b.to]:
		var f := str(cities[n].f)
		if not allied(f) or f == str(b.att_f) or int(cities[n].troops) < 3000:
			continue
		if rng.randf() > 0.6 + int(dip(f).rel) / 250.0:
			continue
		var send := int(int(cities[n].troops) * 0.25)
		cities[n].troops = int(cities[n].troops) - send
		b.def_troops = int(b.def_troops) + send
		b["aid"] = Lang.t("盟友%s自%s发兵 %d 来援！") % [fname(f), n, send]
		add_log(Lang.t("%s军自%s发兵 %d，助守%s。") % [fname(f), n, send, b.to])
		return


# ───────────── 月末结算与 AI ─────────────

func plan_attack(f: String) -> Array:
	var best: Array = []
	var best_score := 0.95
	for c in faction_cities(f):
		var t := int(cities[c].troops)
		if t < 5000 or c == player.gov:
			continue
		var pa := t * 0.65 * (1.0 + best_lead(city_gens(c)) / 150.0)
		for n in adj[c]:
			if cities[n].f == f or (cities[n].f == "player" and allied(f)):
				continue
			var pd := maxf(float(cities[n].troops), 300.0) * (1.0 + best_lead(city_gens(n)) / 150.0) * 1.15
			var score := pa / pd
			if score > best_score:
				best_score = score
				best = [c, n]
	return best


func end_month() -> void:
	month += 1
	if month > 12:
		month = 1
		year += 1
		if year == 0:      # 没有公元 0 年
			year = 1
		_arrivals()
	for c in cities:
		var t := int(cities[c].troops)
		if t < int(cities[c].cap):
			_merge_troops(c, mini(int(cities[c].cap), t + 150 + int(t * 0.03)) - t, 0.0)      # 新补的都是新兵
	if player.started:
		player.hp = mini(100, int(player.hp) + 8)
		if is_lord():
			_court_month()
			_free_gens_month()
			_diplo_month()
			_gov_campaigns()
		elif is_gov():
			player.gold = int(player.gold) + 100
		elif player.f != "":
			player.gold = int(player.gold) + 5 + int(player.rank) * 5
	for f in factions.keys():
		if f == "player" or not factions.has(f):
			continue
		if rng.randf() > 0.13:
			continue
		var plan := plan_attack(f)
		if plan.is_empty():
			continue
		if pending_battle != null:
			var busy: Array = [pending_battle.from, pending_battle.to]
			if busy.has(plan[0]) or busy.has(plan[1]):
				continue
		var b := make_battle(plan[0], plan[1])
		if b.def_f == "player" and is_lord():
			_rel_add(f, -10)
			_ally_aid(b)
		var involved: bool = player.started and player.f != "" and pending_battle == null \
			and ((player.f == b.att_f and player.city == b.from) or (player.f == b.def_f and player.city == b.to))
		if involved:
			b.player_side = 0 if player.f == b.att_f else 1
			b.leads = b.player_side == 1 and (is_lord() or is_gov())
			pending_battle = b
		else:
			apply_battle(b, auto_resolve(b))
	check_victory()
	if pending_battle == null:
		save_game()
	changed.emit()


# ───────────── 存档 ─────────────

func slot_path(n: int) -> String:
	return "%s%d.json" % [save_prefix, n]


func slot_exists(n: int) -> bool:
	return FileAccess.file_exists(slot_path(n))


func has_save() -> bool:
	for n in range(1, SLOTS + 1):
		if slot_exists(n):
			return true
	return false


# 第一个空栏位；全满返回 0
func first_free_slot() -> int:
	for n in range(1, SLOTS + 1):
		if not slot_exists(n):
			return n
	return 0


# 栏位的一行说明；空栏位返回 ""
func slot_text(n: int) -> String:
	if not slot_exists(n):
		return ""
	var data = JSON.parse_string(FileAccess.get_file_as_string(slot_path(n)))
	if typeof(data) != TYPE_DICTIONARY or not data.has("player"):
		return Lang.t("（存档损坏）")
	var pl: Dictionary = data.player
	var sid := str(data.get("scenario", "sanguo"))
	var label := Lang.t(str(SC.ERAS[sid].label)) if SC.ERAS.has(sid) else ""
	var y := int(data.year)
	var yt := (Lang.t("前%d年") % -y) if y < 0 else (Lang.t("%d年") % y)
	var pf := str(pl.get("f", ""))
	var rk := str(DB.RANKS[clampi(int(pl.get("rank", 0)), 0, DB.RANKS.size() - 1)][0])
	var mine := ""
	if pf == "player":
		rk = Lang.t("霸主") if pl.get("hegemon", false) else Lang.t("诸侯")
		var n_c := 0
		for c in data.cities:
			if str(data.cities[c].f) == "player":
				n_c += 1
		mine = Lang.t("　%d 城") % n_c
	elif str(pl.get("gov", "")) != "":
		rk = Lang.t("%s太守") % str(pl.gov)
	var fn := Lang.t("在野")
	if pf != "" and data.factions.has(pf):
		fn = str(data.factions[pf].name)
	return Lang.t("%s %s%d月　%s【%s】%s%s") % [label, yt, int(data.month), str(pl.get("name", "")), rk, fn, mine]


func delete_slot(n: int) -> void:
	if slot_exists(n):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(n)))


# 早先只有一个存档：挪到 1 号栏位
func _migrate_legacy() -> void:
	if FileAccess.file_exists(LEGACY_SAVE) and not slot_exists(1):
		var f := FileAccess.open(slot_path(1), FileAccess.WRITE)
		if f != null:
			f.store_string(FileAccess.get_file_as_string(LEGACY_SAVE))
			f.close()


# 旧存档里没有后来才加进剧本的地方（比如西域以西）：照开局的样子补进去
func _add_new_lands(base_f: Dictionary, base_c: Dictionary, base_g: Dictionary) -> void:
	var known := {}      # 存档那时就已经在剧本里的势力
	for c in base_c:
		if cities.has(c):
			known[base_c[c].f] = true
			cities[c].lon = base_c[c].lon      # 城址若在剧本里挪过，跟着挪
			cities[c].lat = base_c[c].lat
	var added: Array = []
	for c in base_c:
		if cities.has(c):
			continue
		var f: String = base_c[c].f
		cities[c] = base_c[c]
		added.append(c)
		if not known.has(f) and not factions.has(f):
			factions[f] = base_f[f]
	if added.is_empty():
		return
	# 原主已亡的新城：并给相邻城池的主人
	for c in added:
		if factions.has(cities[c].f):
			continue
		var owner := ""
		for e in era.edges:
			var o := ""
			if e[0] == c:
				o = e[1]
			elif e[1] == c:
				o = e[0]
			if o != "" and cities.has(o) and factions.has(cities[o].f):
				owner = cities[o].f
				break
		if owner == "":
			owner = factions.keys()[0]
		cities[c].f = owner
	for g in base_g:
		if not gens.has(g) and added.has(base_g[g].city):
			gens[g] = base_g[g]
			if not factions.has(gens[g].f):
				gens[g].f = cities[gens[g].city].f
	add_log(Lang.t("天下舆图西扩：新添 %d 座城池。") % added.size())


# n < 0 表示存到当前栏位
func save_game(n := -1) -> void:
	if autopilot or not player.started:
		return
	if n > 0:
		slot = n
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		return
	var mine := (Lang.t("　%d 城") % faction_cities("player").size()) if is_lord() else ""
	var meta := Lang.t("%s %s%d月　%s【%s】%s%s") % [era.label, year_text(), month, player.name, rank_name(), fname(player.f), mine]
	f.store_string(JSON.stringify({
		"meta": meta, "scenario": scenario, "year": year, "month": month, "factions": factions, "cities": cities,
		"gens": gens, "player": player, "log": log_lines,
	}))
	f.close()


func load_game(n := -1) -> bool:
	if n < 0:
		n = slot
	if not slot_exists(n):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(slot_path(n)))
	if typeof(data) != TYPE_DICTIONARY or not data.has("cities"):
		return false
	new_game(str(data.get("scenario", "sanguo")))
	var base_f: Dictionary = factions.duplicate(true)
	var base_c: Dictionary = cities.duplicate(true)
	var base_g: Dictionary = gens.duplicate(true)
	year = int(data.year)
	month = int(data.month)
	factions = data.factions
	cities = data.cities
	gens = data.gens
	log_lines = data.log
	for k in data.player:
		player[k] = data.player[k]
	# JSON 把数字都读成浮点，这里转回整数
	for k in ["rank", "merit", "war", "hp", "gold", "kills"]:
		player[k] = int(player[k])
	# 旧存档没有行囊：补一套基础兵器
	if not data.player.has("items"):
		player.items = ["iron_dao", "wood_spear", "pu_dao", "hunt_bow"]
	# 旧存档按兵种记经验：折算到每个兵头上
	var old_xp: Dictionary = player.get("troop_xp", {})
	player.erase("troop_xp")
	if player.squad.is_empty() and not old_xp.is_empty():
		for e in squad():
			e.xp = int(old_xp.get(e.k, 0))
	for e in player.squad:
		e.xp = int(e.xp)
		e.kills = int(e.get("kills", 0))
	for k in player.explored:
		player.explored[k] = int(player.explored[k])
	if not player.has("diplo"):
		player["diplo"] = {}
	for f in player.diplo:
		for k in player.diplo[f]:
			player.diplo[f][k] = int(player.diplo[f][k])
	for c in cities:
		for k in ["troops", "size", "cap"]:
			cities[c][k] = int(cities[c][k])
		cities[c]["vet"] = float(cities[c].get("vet", 0.0))
	_add_new_lands(base_f, base_c, base_g)
	for f in factions:
		_fix_capital(f)
	# 道路按存档里实际存在的城重建（旧存档的城比现在的剧本少）
	adj.clear()
	edges = []
	for c in cities:
		adj[c] = []
	for e in era.edges:
		if cities.has(e[0]) and cities.has(e[1]):
			edges.append(e)
			adj[e[0]].append(e[1])
			adj[e[1]].append(e[0])
	for g in gens:
		gens[g].war = int(gens[g].war)
		gens[g].lead = int(gens[g].lead)
	slot = n
	changed.emit()
	return true
