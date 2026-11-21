extends Control
# 战略界面：地图 + 右侧人物/城池/行动面板 + 战报。

const MapViewScript = preload("res://scripts/MapView.gd")

var map
var date_lbl: Label
var me_lbl: Label
var city_lbl: Label
var actions: VBoxContainer
var hint_lbl: Label
var log_lbl: Label
var start_overlay: Control = null
var msg_overlay: Control = null
var selected := ""
var mode := ""
var first_btn: Button = null
var stick_cd := 0.0
var bag_focus := ""
var selling := false
var sel_slot := 0
var sel_gen := ""
var gift_focus := ""
var side_scroll: ScrollContainer
var keep_scroll := -1
var kill_confirm := ""
var sel_f := ""
var break_confirm := ""
var del_confirm := 0
var slot_overlay: Control = null
var sell_confirm := ""


func _ready() -> void:
	theme = Game.theme
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Sfx.music("map")
	_build()
	Game.changed.connect(refresh)
	if not Game.player.started:
		_start_view()
		_show_start()
	else:
		selected = Game.player.city
		map.center_on(selected)
	refresh()


func _label(parent: Node, size := 18, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _panel_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color("#8a6d3b")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	return sb


func _build() -> void:
	map = MapViewScript.new()
	add_child(map)
	map.city_clicked.connect(_on_city)

	var side := PanelContainer.new()
	side.position = Vector2(1200, 10)
	side.size = Vector2(390, 880)
	side.add_theme_stylebox_override("panel", _panel_style(Color(0.1, 0.08, 0.06, 0.93)))
	add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true      # 手柄把焦点移到看不见的按钮上时，面板跟着滚过去
	side.clip_contents = true
	side.add_child(scroll)
	side_scroll = scroll
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)
	date_lbl = _label(vb, 26, Color("#ffd98a"))
	me_lbl = _label(vb, 17)
	vb.add_child(HSeparator.new())
	city_lbl = _label(vb, 16, Color("#e8dcc0"))
	vb.add_child(HSeparator.new())
	hint_lbl = _label(vb, 15, Color("#ffe08a"))
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	vb.add_child(actions)

	var logp := PanelContainer.new()
	logp.position = Vector2(852, 610)      # 放在东边的海面上，不挡中南半岛
	logp.size = Vector2(338, 282)
	logp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logp.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0.55)))
	add_child(logp)
	log_lbl = _label(logp, 14, Color("#f0e6d0"))
	log_lbl.custom_minimum_size = Vector2(300, 0)
	log_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


func _btn(text: String, cb: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = Lang.fix(text)
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, 36)
	# 字多就折行，不把面板撑出窗口（中文没有空格，按字折；英文按词折）
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if Lang.en() else TextServer.AUTOWRAP_ARBITRARY
	if Lang.en():
		b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	actions.add_child(b)
	if first_btn == null and enabled:
		first_btn = b
	return b


func _do(result: String) -> void:
	mode = ""
	if result != "":
		Game.notices.append(result)
	refresh()


func _set_mode(m: String) -> void:
	mode = m
	refresh()


func refresh() -> void:
	var p: Dictionary = Game.player
	# 行囊、将领这类长列表：点完按钮后停在原来的位置，不跳回顶上
	var scroll_to := side_scroll.scroll_vertical if (keep_scroll == -2 and mode != "") else 0
	keep_scroll = -1
	date_lbl.add_theme_font_size_override("font_size", 21 if Lang.en() else 26)
	date_lbl.text = Lang.fix(Lang.t("%s　%s%d月") % [Lang.t(str(Game.era.label)), Game.year_text(), Game.month])
	if p.started:
		var next := ""
		if not Game.is_lord() and not Game.is_gov() and int(p.rank) < DB.RANKS.size() - 1:
			next = " / %d" % int(DB.RANKS[int(p.rank) + 1][1])
		me_lbl.text = Lang.t("%s　【%s】\n所属：%s　　所在：%s\n功勋 %d%s　　亲兵 %d\n武力 %d　体力 %d　军资 %d　斩获 %d") % [
			p.name, Game.rank_name(), Game.fname(p.f), p.city,
			int(p.merit), next, Game.squad_size(),
			int(p.war), int(p.hp), int(p.gold), int(p.kills)]
		me_lbl.text = Lang.fix(me_lbl.text)
		var eq: Dictionary = p.eq
		me_lbl.text += Lang.fix(Lang.t("\n兵器 %s / %s\n铠甲 %s　坐骑 %s") % [Game.item_name(str(eq.w1)), Game.item_name(str(eq.w2)), Game.item_name(str(eq.armor)), Game.item_name(str(eq.horse))])
	else:
		me_lbl.text = Lang.fix(Lang.t("一介布衣，尚未从军。"))

	if selected != "" and Game.cities.has(selected):
		var ci = Game.cities[selected]
		var gs: Array = Game.city_gens(selected)
		var gl := ""
		for g in gs:
			var tag := Lang.t("（君主）") if g == Game.lord_of(ci.f) else ""
			gl += Lang.t("\n　%s%s　武%d 统%d") % [g, tag, int(Game.gens[g].war), int(Game.gens[g].lead)]
		if selected == p.city and Game.is_lord() and ci.f == "player":
			gl = Lang.t("\n　%s（君主·你）") % p.name + gl
		if gl == "":
			gl = Lang.t("\n　（无名守将）")
		city_lbl.text = Lang.t("【%s】　%s%s\n兵力 %d　%s（训练 %.1f）\n将领：%s\n通往：%s") % [
			selected, Game.fname(ci.f) + (Lang.t("军") if ci.f != "" else "") + (Lang.t("（盟友）") if Game.allied(str(ci.f)) else ""), Lang.t("　★国都") if Game.is_capital(selected) else "",
			int(ci.troops), Game.vet_name(Game.vet(selected)), Game.vet(selected), gl, "、".join(Game.adj[selected])]
		city_lbl.text = Lang.fix(city_lbl.text)
	else:
		city_lbl.text = Lang.fix(Lang.t("点击地图上的城池查看详情。\n滚轮缩放，按住拖动。"))

	for c in actions.get_children():
		c.queue_free()
	first_btn = null
	map.targets = []
	hint_lbl.text = Lang.fix("")
	if not p.started:
		hint_lbl.text = Lang.fix(Lang.t("选择一座城池投军。\n大势力安稳，小势力更易出头；身处前线，仗才打得多。\n滚轮缩小、按住拖动：往西还有西域、天竺、波斯，直到地中海。"))
		if selected != "":
			_btn(Lang.t("在【%s】投军（%s军）") % [selected, Game.fname(Game.cities[selected].f)], func(): _do(Game.enlist(selected)))
	elif mode == "bag":
		_build_bag()
	elif mode == "saves":
		_build_saves()
	elif mode == "court":
		_build_court()
	elif mode == "diplo":
		_build_diplo()
	elif mode == "capital":
		var cur: String = Game.capital_of("player")
		for n in Game.capital_choices("player"):
			if n != cur:
				map.targets.append(n)
		hint_lbl.text = Lang.fix(Lang.t("现在的国都：%s。\n国都只能设在你最大的城池里，迁都耗时一月，你也随之移驾。\n国都若被攻破，还有一场殿堂之战可以翻盘。") % cur)
		if map.targets.is_empty():
			hint_lbl.text += Lang.fix(Lang.t("\n（没有别的城可选：最大的城只有%s）") % cur)
		for n in map.targets:
			_btn(Lang.t("迁都【%s】　%s 兵%d") % [n, ["", Lang.t("小城"), Lang.t("中城"), Lang.t("大城")][int(Game.cities[n].size)], int(Game.cities[n].troops)], _on_city.bind(n))
		_btn(Lang.t("取消"), func(): _set_mode(""))
	elif mode != "":
		var c: String = p.city
		for n in Game.adj[c]:
			var own: bool = Game.cities[n].f == p.f
			if mode == "move" and (p.f == "" or own):
				map.targets.append(n)
			elif mode == "attack" and not own:
				map.targets.append(n)
			elif mode == "transfer" and own:
				map.targets.append(n)
		hint_lbl.text = Lang.fix({"move": Lang.t("点击相邻城池前往。"), "attack": Lang.t("点击相邻的敌城发起进攻。"), "transfer": Lang.t("点击相邻的己方城池，调去一半兵力。")}[mode])
		if map.targets.is_empty():
			hint_lbl.text += Lang.fix(Lang.t("\n（没有可选的城池）"))
		var verb: String = {"move": Lang.t("前往"), "attack": Lang.t("进攻"), "transfer": Lang.t("调兵至")}[mode]
		for n in map.targets:
			var ally_tag := Lang.t("·盟友") if Game.allied(str(Game.cities[n].f)) else ""
			_btn(Lang.t("%s【%s】　%s%s 兵%d") % [Lang.t("亲征") if (mode == "attack" and Game.is_lord()) else verb, n, Game.fname(Game.cities[n].f), ally_tag, int(Game.cities[n].troops)], _on_city.bind(n))
			if mode == "attack" and Game.is_lord() and ally_tag == "":
				var ld: Array = Game.dispatch_gens(c)
				if not ld.is_empty():
					_btn(Lang.t("　↳ 遣%s代攻【%s】（%s）") % [ld[0], n, Game.odds_text(Game.odds(c, n, ld))], func(): _do(Game.act_dispatch(n)))
		if mode == "attack" and Game.is_lord():
			hint_lbl.text = Lang.fix(Lang.t("亲征：你亲自上阵打这一仗。\n遣将：由城中将领带兵去打，按兵力、统率、训练度结算，不必亲自上阵。\n两者都耗时一月。太守还可在“将领与俘虏”中令其伺机进取，自己找仗打。"))
			if Game.dispatch_gens(c).is_empty():
				hint_lbl.text += Lang.fix(Lang.t("\n（此城没有忠诚 40 以上的将领，无人可遣。）"))
		_btn(Lang.t("取消"), func(): _set_mode(""))
	else:
		var in_f: bool = p.f != ""
		var lord: bool = Game.is_lord()
		var gov: bool = Game.is_gov()
		_btn(Lang.t("训练武艺　（武力↑　体力-15）"), func(): _do(Game.act_train()))
		_btn(Lang.t("剿灭山贼　（亲自上阵·得功勋军资）"), func(): _do(Game.act_bandit()))
		_btn(Lang.t("休整养伤　（体力+50）"), func(): _do(Game.act_rest()))
		_btn(Lang.t("寻访探宝　（或得兵器、铠甲、战马）"), func(): _do(Game.act_explore()))
		if Game.squad_size() > 0:
			_btn(Lang.t("操练亲兵　（每人经验+5　军资-20）"), func(): _do(Game.act_drill()), int(p.gold) >= 20)
		_btn(Lang.t("行囊与部曲…　（%d 件）") % p.items.size(), func(): _set_mode("bag"))
		_btn(Lang.t("存档与读档…　（当前 %d 号栏位）") % Game.slot, func():
			sel_slot = Game.slot
			del_confirm = 0
			_set_mode("saves"))
		if not gov:
			_btn(Lang.t("前往他城…"), func(): _set_mode("move"))
		if in_f:
			_btn(Lang.t("领兵出征…") if Game.can_lead() else Lang.t("请战出征…"), func(): _set_mode("attack"))
		if lord or gov:
			_btn(Lang.t("征兵　（每100金募1000兵，至多3000）"), func(): _do(Game.act_recruit()), int(p.gold) >= 100)
			_btn(Lang.t("操练守军　（100 金，训练度 +0.35，最高练到精锐）"), func(): _do(Game.act_train_city()), int(p.gold) >= 100)
		if lord:
			_btn(Lang.t("调兵至邻城…"), func(): _set_mode("transfer"))
			_btn(Lang.t("迁都…　（国都：%s）") % Game.capital_of("player"), func(): _set_mode("capital"))
			var n_ally: int = Game.other_factions().filter(func(x): return Game.allied(x)).size()
			_btn(Lang.t("外交…　（盟友 %d）") % n_ally, func():
				break_confirm = ""
				_set_mode("diplo"))
			var nc: int = Game.my_captives().size() + Game.my_free_agents().size()
			_btn(Lang.t("将领与俘虏…　（将 %d%s）") % [Game.my_gens().size(), Lang.t("　待发落 %d") % nc if nc > 0 else ""], func():
				kill_confirm = ""
				_set_mode("court"))
		if gov:
			_btn(Lang.t("自立为主！"), func(): _do(Game.act_independent()))
		if not in_f:
			if Game.cities[p.city].f != "player":
				_btn(Lang.t("在此投军（%s军）") % Game.fname(Game.cities[p.city].f), func(): _do(Game.enlist(p.city)))
		elif not lord:
			_btn(Lang.t("挂印离去（成为在野）"), func(): _do(Game.act_leave()))
		if lord:
			hint_lbl.text = Lang.fix(Lang.t("你是一方诸侯：月入 %d 军资。坐拥十城即为霸主。") % Game.income())
		elif gov:
			hint_lbl.text = Lang.fix(Lang.t("你是太守：可征兵、领兵出征；时机成熟可自立为主。"))
		elif not in_f:
			hint_lbl.text = Lang.fix(Lang.t("你是在野之身，可自由行走，择主而事。"))
		elif Game.can_lead():
			hint_lbl.text = Lang.fix(Lang.t("你可自行领兵出征。") + (Lang.t("领兵攻下一城即可受封太守。") if int(p.rank) >= 5 else ""))
		else:
			hint_lbl.text = Lang.fix(Lang.t("每月可行动一次。主公出兵或敌军来犯时，你会随军上阵。"))
		var sep := HSeparator.new()
		actions.add_child(sep)
		_btn(Lang.t("回到主界面　（进度已存）"), _restart)

	var n_show := 7
	var all_lines: Array = Game.log_lines
	if Lang.en():
		all_lines = all_lines.filter(func(x): return not Lang.is_chinese_sentence(str(x)))
	var lines: Array = all_lines.slice(maxi(0, all_lines.size() - n_show))
	log_lbl.text = Lang.fix("\n".join(lines))
	if not Input.get_connected_joypads().is_empty():
		hint_lbl.text += Lang.fix(Lang.t("\n手柄：十字键/左摇杆 选按钮，A 或 B 确定，右摇杆 在地图上选城。"))
	map.selected = selected
	map.queue_redraw()
	_focus_actions.call_deferred()
	if scroll_to > 0:
		_restore_scroll.call_deferred(scroll_to)
	_pump.call_deferred()


# 将领与俘虏：先点人，再选怎么办
func _build_court() -> void:
	var mine: Array = Game.my_gens()
	var caps: Array = Game.my_captives()
	var free: Array = Game.my_free_agents()
	if sel_gen == "" or not Game.gens.has(sel_gen) or not (mine.has(sel_gen) or caps.has(sel_gen) or free.has(sel_gen)):
		sel_gen = ""
	var txt := Lang.t("府库 %d 金　月入 %d\n（小城 90、中城 150、大城 230，国都另加 60）") % [int(Game.player.gold), Game.income()]
	if sel_gen != "":
		var gg: Dictionary = Game.gens[sel_gen]
		var tr: Array = DB.TRAITS[Game.trait_of(sel_gen)]
		txt += Lang.t("\n\n【%s】武 %d　统 %d　现于%s\n性格 %s：%s") % [sel_gen, int(gg.war), int(gg.lead), gg.city, tr[0], Lang.t(str(tr[1]))]
		if mine.has(sel_gen):
			txt += Lang.t("\n%s\n忠诚 %d（无人过问会滑向 %d）") % [Game.role_text(sel_gen), int(gg.get("loy", 50)), Game.loyalty_floor(sel_gen)]
			if int(gg.get("loy", 50)) < 30:
				txt += Lang.t("\n⚠ 忠诚过低，随时可能出走。")
		else:
			var p0: float = Game.recruit_chance(sel_gen, false)
			var p1: float = Game.recruit_chance(sel_gen, true)
			txt += Lang.t("\n招降：%s（约 %d%%）　重金：%s（约 %d%%）\n招募金谈成才付，没谈成不花钱。") % [Game.chance_text(p0), roundi(p0 * 100), Game.chance_text(p1), roundi(p1 * 100)]
	else:
		txt += Lang.t("\n\n点一个人物查看详情。\n太守（★）留守本城，令其“伺机进取”后见有胜算会自己出兵；其余将领自己行动：或赶来随驾、与你一同出征，或去守边。\n忠诚每月向各人的底线滑落 1 点，打胜仗 +3，赏赐立升；低于 25 可能出走。")
	hint_lbl.text = Lang.fix(txt)
	var focus_btn: Button = null
	# 一键赏赐：全体，或只赏忠诚偏低的
	var low: Array = mine.filter(func(x): return int(Game.gens[x].get("loy", 50)) < 50)
	var gold := int(Game.player.gold)
	if not mine.is_empty():
		_btn(Lang.t("赏忠诚低于 50 的（%d 人 · %d 金）") % [low.size(), low.size() * 50], func(): _gift_many(low), not low.is_empty() and gold >= low.size() * 50)
		var needy: Array = mine.filter(func(x): return int(Game.gens[x].get("loy", 50)) < 100)      # 忠诚已满的不算
		var skipped: int = mine.size() - needy.size()
		_btn(Lang.t("赏全体（%d 人 · %d 金%s）") % [needy.size(), needy.size() * 50, Lang.t(" · %d 人已满") % skipped if skipped > 0 else ""],
			func(): _gift_many(needy), not needy.is_empty() and gold >= needy.size() * 50)
		actions.add_child(HSeparator.new())
	for g in mine:
		var loy := int(Game.gens[g].get("loy", 50))
		var where := ("★" + str(Game.gens[g].gov) + (Lang.t("·进取") if Game.gens[g].get("agg", false) else "")) if Game.is_gov_gen(g) else (Lang.t("随驾") if Game.is_follower(g) else str(Game.gens[g].city))
		var bt := _btn("%s%s　%s %d　%s" % ["▶ " if g == sel_gen else "", g, Game.trait_name(g), loy, where], _pick_gen.bind(g))
		bt.clip_text = true
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.add_theme_color_override("font_color", Color("#ff8a7a") if loy < 30 else (Color("#ffe08a") if loy < 50 else Color("#b8e6a0")))
		# 把这一行改成“名字 + 赏”两个按钮并排，赏赐不用再到别处找
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		actions.add_child(row)
		bt.reparent(row)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var gb := Button.new()
		gb.text = Lang.fix(Lang.t("赏 50"))
		gb.custom_minimum_size = Vector2(76, 36)
		gb.disabled = gold < 50 or loy >= 100
		gb.pressed.connect(_gift_one.bind(g))
		row.add_child(gb)
		if g == sel_gen:
			focus_btn = gb if gift_focus == g else bt
	for g in caps + free:
		var tag := Lang.t("〔俘〕") if caps.has(g) else Lang.t("〔在野〕")
		var bt2 := _btn(Lang.t("%s%s%s　%s　武%d 统%d") % ["▶ " if g == sel_gen else "", tag, g, Game.trait_name(g), int(Game.gens[g].war), int(Game.gens[g].lead)], _pick_gen.bind(g))
		bt2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt2.add_theme_color_override("font_color", Color("#c8b8ff") if caps.has(g) else Color("#b8d8ff"))
		if g == sel_gen:
			focus_btn = bt2
	var act_from := actions.get_child_count()
	if sel_gen != "":
		var g: String = sel_gen
		if mine.has(g):
			var here: String = Game.gens[g].city
			if Game.is_gov_gen(g):
				_btn(Lang.t("令其固守（现：伺机进取）") if Game.gens[g].get("agg", false) else Lang.t("令其伺机进取（现：固守）"), func(): _court_keep(Game.act_stance(g)))
				_btn(Lang.t("免去%s太守之职") % Game.gens[g].gov, func(): _court_keep(Game.act_dismiss(g)))
			else:
				var cur: String = Game.gov_of(here)
				_btn(Lang.t("任命为【%s】太守%s") % [here, Lang.t("（接替%s）") % cur if cur != "" else ""], func(): _court_keep(Game.act_appoint(g)))
				if here != Game.player.city:
					_btn(Lang.t("已奉召，正在赶来") if Game.gens[g].get("summon", false) else Lang.t("召到身边"), func(): _court_keep(Game.act_summon(g)), not Game.gens[g].get("summon", false))
		else:
			var tried: bool = int(Game.gens[g].get("tried", -9999)) == Game.year * 12 + Game.month
			var cost: int = Game.fee(g)
			if tried:
				_btn(Lang.t("本月已谈过，下月再试"), func(): pass, false)
			else:
				_btn(Lang.t("招降　（招募金 %d）") % cost, func(): _court(Game.act_recruit_gen(g, false)), int(Game.player.gold) >= cost)
				_btn(Lang.t("重金招降　（招募金 %d，更易成）") % (cost * 2), func(): _court(Game.act_recruit_gen(g, true)), int(Game.player.gold) >= cost * 2)
			if caps.has(g):
				_btn(Lang.t("释放"), func(): _court(Game.act_release(g)))
				_btn(Lang.t("确认处斩【%s】？再点一次") % g if kill_confirm == g else Lang.t("处斩"), func():
					if kill_confirm != g:
						kill_confirm = g
						refresh()
					else:
						kill_confirm = ""
						_court(Game.act_execute(g)))
		actions.add_child(HSeparator.new())
	# 把对所选人物的操作挪到名单上方，免得要滚到底才看得见
	var acts: Array = []
	for i in range(act_from, actions.get_child_count()):
		acts.append(actions.get_child(i))
	for i in acts.size():
		actions.move_child(acts[i], i)
	_btn(Lang.t("返回"), func(): _set_mode(""))
	if focus_btn != null:
		first_btn = focus_btn


# 外交：选一家，送礼、结盟或毁约
func _build_diplo() -> void:
	var fs: Array = Game.other_factions()
	# 盟友在前，其次是接壤的邻邦，最后才是远方各国
	var rank := {}
	for i in fs.size():
		rank[fs[i]] = (0 if Game.allied(fs[i]) else (1000 if Game.borders(fs[i], "player") else 2000)) + i
	fs.sort_custom(func(a, b): return rank[a] < rank[b])
	if not fs.has(sel_f):
		sel_f = ""
	var txt := Lang.t("府库 %d 金\n结盟两年：互不侵犯，敌军来犯时接壤的盟友可能发兵相助。\n关系每月向平淡回落；送礼可拉近，攻打则交恶。") % int(Game.player.gold)
	if sel_f != "":
		var f: String = sel_f
		var d: Dictionary = Game.dip(f)
		var ally: bool = Game.allied(f)
		txt += Lang.t("\n\n【%s】%d 城　国都 %s\n关系：%s（%d）%s") % [Game.fname(f), Game.faction_cities(f).size(), Game.capital_of(f), Game.rel_name(int(d.rel)), int(d.rel),
			Lang.t("　盟约余 %d 月") % int(d.pact) if ally else (Lang.t("　与你接壤") if Game.borders(f, "player") else Lang.t("　不接壤"))]
		_btn(Lang.t("遣使送礼　（100 金，关系 +15）"), func(): _diplo(Game.act_envoy_gift(f)), int(Game.player.gold) >= 100)
		var pc: float = Game.ally_chance(f)
		if int(d.cool) > 0 and not ally:
			_btn(Lang.t("刚被回绝，%d 个月后再议") % int(d.cool), func(): pass, false)
		else:
			_btn(Lang.t("%s　（%s，约 %d%%）") % [Lang.t("续盟两年") if ally else Lang.t("缔结盟约"), Game.chance_text(pc), roundi(pc * 100)], func(): _diplo(Game.act_ally(f)), int(d.cool) <= 0)
		if ally:
			_btn(Lang.t("确认撕毁盟约？再点一次") if break_confirm == f else Lang.t("撕毁盟约"), func():
				if break_confirm != f:
					break_confirm = f
					keep_scroll = -2
					refresh()
				else:
					break_confirm = ""
					_diplo(Game.act_break(f)))
		actions.add_child(HSeparator.new())
	else:
		txt += Lang.t("\n\n点一家势力查看详情。")
	hint_lbl.text = Lang.fix(txt)
	for f in fs:
		var d2: Dictionary = Game.dip(f)
		var ally2: bool = Game.allied(f)
		var bt := _btn(Lang.t("%s%s　%d城　%s%s") % ["▶ " if f == sel_f else "", Game.fname(f), Game.faction_cities(f).size(),
			Lang.t("盟友·余%d月") % int(d2.pact) if ally2 else Game.rel_name(int(d2.rel)), "" if Game.borders(f, "player") else Lang.t("　远")], _pick_f.bind(f))
		bt.clip_text = true
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var rv := int(d2.rel)
		bt.add_theme_color_override("font_color", Color("#8ad8ff") if ally2 else (Color("#b8e6a0") if rv >= 25 else (Color("#ff8a7a") if rv <= -25 else Color("#e8e0d0"))))
	_btn(Lang.t("返回"), func(): _set_mode(""))


func _pick_f(f: String) -> void:
	sel_f = f
	break_confirm = ""
	keep_scroll = -2
	refresh()


func _diplo(msg: String) -> void:
	keep_scroll = -2
	_court(msg)


func _pick_gen(g: String) -> void:
	sel_gen = g
	gift_focus = ""
	kill_confirm = ""
	keep_scroll = -2
	refresh()


func _court_keep(msg: String) -> void:
	keep_scroll = -2
	_court(msg)


func _gift_one(g: String) -> void:
	sel_gen = g
	gift_focus = g
	keep_scroll = -2
	_court(Game.act_gift(g))


func _gift_many(list: Array) -> void:
	for g in list:
		Game.act_gift(g)
	keep_scroll = -2
	_court("")


# 处置的结果：有话就弹窗（留在本页），顺手存档
func _court(msg: String) -> void:
	if msg != "":
		Game.notices.append(msg)
	Game.save_game()
	refresh()


func _slot_label(n: int) -> String:
	var t: String = Game.slot_text(n)
	return Lang.t("%d 号　%s") % [n, t if t != "" else Lang.t("（空）")]


# 存档与读档：先点栏位，再选存入、读取或删除
func _build_saves() -> void:
	hint_lbl.text = Lang.fix(Lang.t("共 %d 个栏位。每月结束时自动存到当前栏位（%d 号）。\n先点一个栏位，再选要做的事。") % [Game.SLOTS, Game.slot])
	var focus_btn: Button = null
	for n in range(1, Game.SLOTS + 1):
		var mark := "▶ " if n == sel_slot else ("● " if n == Game.slot else "　 ")
		var bt := _btn(mark + _slot_label(n), _pick_slot.bind(n))
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.clip_text = true
		if n == Game.slot:
			bt.add_theme_color_override("font_color", Color("#ffd24a"))
		if n == sel_slot:
			focus_btn = bt
	actions.add_child(HSeparator.new())
	var has: bool = Game.slot_exists(sel_slot)
	_btn(Lang.t("存到 %d 号栏位%s") % [sel_slot, Lang.t("（覆盖）") if has and sel_slot != Game.slot else ""], func():
		Game.save_game(sel_slot)
		Game.notices.append(Lang.t("已存到 %d 号栏位。\n此后每月自动存到这里。") % sel_slot)
		_set_mode(""))
	_btn(Lang.t("读取 %d 号栏位") % sel_slot, func():
		if Game.load_game(sel_slot):
			selected = Game.player.city
			Game.notices.clear()
		_set_mode(""), has)
	_btn(Lang.t("确认删除 %d 号栏位？再点一次") % sel_slot if del_confirm == sel_slot else Lang.t("删除 %d 号栏位") % sel_slot, func():
		if del_confirm != sel_slot:
			del_confirm = sel_slot
		else:
			Game.delete_slot(sel_slot)
			del_confirm = 0
		refresh(), has)
	_btn(Lang.t("返回"), func(): _set_mode(""))
	if focus_btn != null:
		first_btn = focus_btn


func _pick_slot(n: int) -> void:
	sel_slot = n
	del_confirm = 0
	refresh()


# 开局界面上的栏位选择（读档，或栏位全满时选一个覆盖）
func _show_slots(title: String, only_used: bool, on_pick: Callable) -> void:
	slot_overlay = _dim()
	var center := CenterContainer.new()
	slot_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(0.13, 0.1, 0.07, 0.98)))
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	var t := _label(vb, 26, Color("#ffd98a"))
	t.text = Lang.fix(title)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var first: Button = null
	for n in range(1, Game.SLOTS + 1):
		var bt := Button.new()
		bt.text = Lang.fix(_slot_label(n))
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.custom_minimum_size = Vector2(620, 44)
		bt.disabled = only_used and not Game.slot_exists(n)
		vb.add_child(bt)
		bt.pressed.connect(func():
			slot_overlay.queue_free()
			slot_overlay = null
			on_pick.call(n))
		if first == null and not bt.disabled:
			first = bt
	var cancel := Button.new()
	cancel.text = Lang.fix(Lang.t("取消"))
	cancel.custom_minimum_size = Vector2(0, 42)
	vb.add_child(cancel)
	cancel.pressed.connect(func():
		slot_overlay.queue_free()
		slot_overlay = null)
	(first if first != null else cancel).grab_focus.call_deferred()


# 行囊：每件物品一个按钮，点一下切换装备状态
func _build_bag() -> void:
	var p: Dictionary = Game.player
	var roster: Array = Game.squad()
	var txt := Lang.t("部曲（亲兵 %d 人，各人有各人的经验与等级）：") % roster.size()
	for k in DB.TROOPS:
		var by_lv := {}
		var n := 0
		for e in roster:
			if e.k == k:
				n += 1
				var lv: int = Game.level_of(int(e.xp))
				by_lv[lv] = int(by_lv.get(lv, 0)) + 1
		if n == 0:
			if k == "cav":
				txt += Lang.t("\n　骑兵　升至百夫长后，新补的兵里才有")
			continue
		var bits: Array = []
		for lv in range(5, -1, -1):
			if by_lv.has(lv):
				bits.append("%s×%d" % [DB.TROOP_TREE[k][lv][0], by_lv[lv]])
		txt += Lang.t("\n　%s %d 人：%s") % [DB.TROOPS[k], n, " ".join(bits)]
	var vets: Array = roster.duplicate()
	vets.sort_custom(func(a, b): return int(a.xp) > int(b.xp))
	if not vets.is_empty() and int(vets[0].xp) > 0:
		txt += Lang.t("\n老兵：")
		for e in vets.slice(0, 5):
			if int(e.xp) <= 0:
				break
			var lv2: int = Game.level_of(int(e.xp))
			var nx := Lang.t("满级") if lv2 >= 5 else "%d/%d" % [int(e.xp), int(DB.TROOP_XP[lv2 + 1])]
			txt += Lang.t("\n　%s　%s·%s　斩%d　经验 %s") % [e.name, DB.TROOPS[e.k], DB.TROOP_TREE[e.k][lv2][0], int(e.get("kills", 0)), nx]
	txt += Lang.t("\n亲兵上限随军衔：伍长 6、什长 12、百夫长 20、校尉 30、将军 40、太守 50、诸侯 60。")
	txt += Lang.t("\n上阵活下来 +4 经验，每斩一人 +6，得胜 +3；阵亡则由新兵顶替。\n\n行囊：点兵器 → 主手 → 副手 → 卸下；\n点铠甲、坐骑 → 装上 / 卸下。\n战斗中可在主手、副手间切换。")
	if selling:
		txt = Lang.t("出售：点物品即卖掉，换成军资（现有 %d）。\n凡品 10　良品 30　精品 80　神兵 200\n装备着的会先卸下；神兵需再点一次确认。\n卖掉的东西拿不回来。") % int(p.gold)
	hint_lbl.text = Lang.fix(txt)
	var ids: Array = p.items.duplicate()
	var order := {"weapon": 0, "armor": 1, "horse": 2}
	ids.sort_custom(func(a, b):
		var ia: Dictionary = Game.item(a)
		var ib: Dictionary = Game.item(b)
		if ia.slot != ib.slot:
			return order[ia.slot] < order[ib.slot]
		if int(ia.t) != int(ib.t):
			return int(ia.t) > int(ib.t)
		return str(a) < str(b))
	var focus_btn: Button = null
	for id in ids:
		var tag: String = Game.eq_tag(id)
		var head := ("〔%s〕" % tag) if tag != "" else "　　　"
		var label := "%s%s　%s" % [head, Game.item_name(id), Game.item_desc(id)]
		if selling:
			label = Lang.t("%s%s　卖 %d 金") % [head, Game.item_name(id), Game.sell_price(id)]
			if id == sell_confirm:
				label = Lang.t("确认卖掉【%s】？再点一次") % Game.item_name(id)
		var bt := _btn(label, _bag_press.bind(id))
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var tier := int(Game.item(id).t)
		if tier > 0:
			bt.add_theme_color_override("font_color", [Color.WHITE, Color("#8fd0ff"), Color("#d9a0ff"), Color("#ffd24a")][tier])
		if id == bag_focus:
			focus_btn = bt
	var toggle := _btn(Lang.t("结束出售") if selling else Lang.t("出售物品…"), _toggle_sell, not p.items.is_empty() or selling)
	_btn(Lang.t("返回"), func():
		selling = false
		sell_confirm = ""
		_set_mode(""))
	if selling and focus_btn == null:
		focus_btn = toggle
	if focus_btn != null:
		first_btn = focus_btn


func _toggle_sell() -> void:
	selling = not selling
	sell_confirm = ""
	bag_focus = ""
	refresh()


func _bag_press(id: String) -> void:
	bag_focus = id
	keep_scroll = -2
	if selling:
		if int(Game.item(id).t) >= 3 and sell_confirm != id:
			sell_confirm = id
			refresh()
			return
		sell_confirm = ""
		Game.sell_item(id)
	else:
		Game.equip_press(id)
	Game.save_game()


func _restore_scroll(v: int) -> void:
	await get_tree().process_frame
	side_scroll.scroll_vertical = v


func _focus_actions() -> void:
	if msg_overlay == null and start_overlay == null and first_btn != null and is_instance_valid(first_btn) \
			and not Input.get_connected_joypads().is_empty():
		first_btn.grab_focus()


func _process(delta: float) -> void:
	# 右摇杆：朝所指方向跳到最近的城池
	stick_cd -= delta
	if msg_overlay != null or start_overlay != null or stick_cd > 0.0:
		return
	var v: Vector2 = Game.joy_stick(1)
	if v.length() < 0.6:
		return
	var from: String = selected
	if from == "":
		from = Game.player.city if Game.player.city != "" else str(Game.cities.keys()[0])
	var origin: Vector2 = map.city_pos(from)
	var best := ""
	var best_score := INF
	for c in Game.cities:
		if c == from:
			continue
		var d: Vector2 = map.city_pos(c) - origin
		var cosv := d.normalized().dot(v.normalized())
		if cosv < 0.5:
			continue
		var score := d.length() / (cosv * cosv)
		if score < best_score:
			best_score = score
			best = c
	if best != "":
		stick_cd = 0.28
		selected = best
		refresh()


func _input(e: InputEvent) -> void:
	# Switch 的 A（右键）和 B（下键）都当确定
	if e is InputEventJoypadButton and e.pressed and (e.button_index == JOY_BUTTON_A or e.button_index == JOY_BUTTON_B):
		var f := get_viewport().gui_get_focus_owner()
		if f is Button and not f.disabled:
			get_viewport().set_input_as_handled()
			f.pressed.emit()


func _on_city(c: String) -> void:
	if msg_overlay != null or start_overlay != null:
		return
	if mode == "move":
		_do(Game.act_move(c))
		selected = Game.player.city
		refresh()
	elif mode == "attack":
		_do(Game.act_attack(c))
	elif mode == "transfer":
		_do(Game.act_transfer(c))
	elif mode == "capital":
		_do(Game.act_move_capital(c))
		selected = Game.player.city
		refresh()
	else:
		selected = c
		refresh()


# ───────────── 弹窗 ─────────────

func _pump() -> void:
	if msg_overlay != null or start_overlay != null:
		return
	if not Game.notices.is_empty():
		_show_msg(Game.notices.pop_front(), Lang.t("确定"), _pump)
	elif Game.pending_battle != null:
		var pb: Dictionary = Game.pending_battle
		var cap_note := Lang.t("\n\n★ 此城是%s的国都：城破之后还有一场%s之战。") % [Game.fname(pb.def_f), Game.hall_name(str(pb.to))] if (pb.type == "siege" and Game.is_capital(str(pb.to))) else ""
		if pb.type == "siege" and Game.faction_cities(str(pb.def_f)).size() <= 1:
			cap_note += Lang.t("\n\n这是%s最后一座城：守军无路可退，必将死战到底。") % Game.fname(pb.def_f)
		if pb.type == "siege" and int(pb.player_side) == 1:
			# 守城：选在哪里迎敌
			var note := Lang.t("\n\n你主持守城：城头迎击则全军不出城，凭城墙固守；\n出城迎击则分兵在城外列阵。") if pb.leads \
				else Lang.t("\n\n主将自有部署，你只需选自己的位置：\n上城头据守，或随出城的队伍迎战。")
			_show_msg(_battle_text(pb) + cap_note + note, Lang.t("城头迎击"), _start_battle.bind("wall"), Lang.t("出城迎击"), _start_battle.bind("sortie"))
		else:
			_show_msg(_battle_text(pb) + cap_note, Lang.t("出战！"), _start_battle.bind(""))


func _battle_text(b: Dictionary) -> String:
	if b.type == "palace":
		return Lang.t("【%s之战】\n\n【%s】外城已破，%s退守%s。") % [Game.hall_name(str(b.to)), b.to, Game.fname(b.def_f), Game.hall_name(str(b.to))]
	if b.type == "bandit":
		return Lang.t("【剿匪】\n\n%s郊外有山贼约 %d 人啸聚。\n你带 %d 名弟兄前去清剿。") % [b.to, int(b.att_troops), int(b.def_troops)]
	var s := ""
	if int(b.player_side) == 0:
		if b.then_end:
			s = Lang.t("【出征】\n\n我军自%s出兵，进攻%s的【%s】！") % [b.from, Game.fname(b.def_f), b.to]
		else:
			s = Lang.t("【军令】\n\n%s下令：自%s出兵，进攻%s的【%s】！\n你随军出征。") % [Game.fname(b.att_f), b.from, Game.fname(b.def_f), b.to]
	else:
		s = Lang.t("【敌袭】\n\n%s军自%s来犯【%s】！\n全城将士登城迎战。") % [Game.fname(b.att_f), b.from, b.to]
		if b.has("aid"):
			s += "\n" + str(b.aid)
	s += Lang.t("\n\n攻方 %s军　兵 %d（%s）　将：%s\n守方 %s军　兵 %d（%s）　将：%s") % [
		Game.fname(b.att_f), int(b.att_troops), Game.vet_name(float(b.get("att_vet", 0.0))), _names(b.att_gens),
		Game.fname(b.def_f), int(b.def_troops), Game.vet_name(float(b.get("def_vet", 0.0))), _names(b.def_gens)]
	var dec: Array = b.get("declined", [])
	if not dec.is_empty():
		s += Lang.t("\n（%s 推托不去——忠诚不足）") % "、".join(dec)
	return s


func _names(a: Array) -> String:
	return "、".join(a) if not a.is_empty() else Lang.t("无名之将")


func _start_battle(defense: String) -> void:
	if defense != "" and Game.pending_battle != null:
		Game.pending_battle["defense"] = defense
	get_tree().change_scene_to_file("res://scenes/Battle.tscn")


func _dim() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, 0.55)
	add_child(d)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return d


func _show_msg(text: String, ok: String, cb: Callable, ok2 := "", cb2 := Callable()) -> void:
	msg_overlay = _dim()
	var has := func(keys: Array) -> bool:
		for k in keys:
			if text.contains(k):
				return true
		return false
	if has.call(["所灭", "陷落", "destroyed", "has fallen"]):
		Sfx.play("gong")
	elif has.call(["晋升", "封你", "自立为主", "天下一统", "霸主", "Promoted", "appoints you", "your own banner", "unified", "Hegemon"]):
		Sfx.play("victory")
	elif has.call(["寻得", "缴获", "you found", "Spoils"]):
		Sfx.play("loot")
	elif has.call(["【敌袭】", "【出征】", "【军令】", "[Enemy Attack]", "[Campaign]", "[Orders]"]):
		Sfx.play("horn", -4.0)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(0.13, 0.1, 0.07, 0.98)))
	pc.custom_minimum_size = Vector2(560, 0)
	var center := CenterContainer.new()
	msg_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	pc.add_child(vb)
	var l := _label(vb, 20)
	l.text = Lang.fix(text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(520, 0)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	vb.add_child(hb)
	var choices: Array = [[ok, cb]]
	if ok2 != "":
		choices.append([ok2, cb2])
	for ch in choices:
		var b := Button.new()
		b.text = Lang.fix(ch[0])
		b.custom_minimum_size = Vector2(160, 42)
		hb.add_child(b)
		var fn: Callable = ch[1]
		b.pressed.connect(func():
			msg_overlay.queue_free()
			msg_overlay = null
			fn.call()
			_focus_actions.call_deferred())
	hb.get_child(0).grab_focus.call_deferred()


func _show_start() -> void:
	start_overlay = _dim()
	var center := CenterContainer.new()
	start_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(0.13, 0.1, 0.07, 0.98)))
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	pc.add_child(vb)
	var lang_btn := Button.new()
	lang_btn.text = "中文" if Lang.en() else "English"
	lang_btn.custom_minimum_size = Vector2(120, 34)
	lang_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	vb.add_child(lang_btn)
	lang_btn.pressed.connect(func():
		Lang.set_lang("zh" if Lang.en() else "en")
		_start_view()
		start_overlay.queue_free()
		start_overlay = null
		_show_start())
	var t := _label(vb, 54, Color("#ffd98a"))
	t.text = Lang.fix(Lang.t("乱 世 从 戎"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := _label(vb, 18, Color("#e8dcc0"))
	s.text = Lang.fix(Lang.t("你只是行伍间的一名士卒——\n积功升迁，受封太守，据城自立，终成一方霸主。\n\n选择年代："))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.custom_minimum_size = Vector2(620, 0)
	# 年代：点一下就换背后的地图
	var era_box := GridContainer.new()
	era_box.columns = 2
	era_box.add_theme_constant_override("h_separation", 10)
	era_box.add_theme_constant_override("v_separation", 8)
	vb.add_child(era_box)
	var intro := _label(vb, 16, Color("#ffe9b0"))
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.custom_minimum_size = Vector2(620, 70)
	var grp := ButtonGroup.new()
	var show_era := func(id: String):
		Game.new_game(id)
		selected = ""
		var e: Dictionary = Game.era
		intro.text = Lang.fix(Lang.t("%s　%s\n%s\n%d 家势力　%d 座城池") % [Lang.t(str(e.name)), "" if Lang.en() else Game.year_text(), Lang.t(str(e.intro)), e.factions.size(), e.cities.size()])
		refresh()
	for id in Game.SC.ORDER:
		var eb := Button.new()
		eb.text = Lang.fix(Lang.t(str(Game.SC.ERAS[id].name)))
		eb.toggle_mode = true
		eb.button_group = grp
		eb.custom_minimum_size = Vector2(305, 42)
		eb.button_pressed = id == Game.scenario
		eb.pressed.connect(show_era.bind(id))
		era_box.add_child(eb)
	show_era.call(Game.scenario)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = Lang.fix(Lang.t("你的姓名（默认：无名氏）"))
	name_edit.max_length = 8
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(0, 42)
	vb.add_child(name_edit)
	var go := Button.new()
	go.text = Lang.fix(Lang.t("踏上征途"))
	go.custom_minimum_size = Vector2(0, 46)
	vb.add_child(go)
	go.grab_focus.call_deferred()
	var begin := func(n: int):
		Game.new_game()
		Game.slot = n
		var nm := name_edit.text.strip_edges()
		if nm != "":
			Game.player.name = nm
		_close_start()
	go.pressed.connect(func():
		# 新的一局用第一个空栏位，免得盖掉别的存档；全满时让玩家挑一个覆盖
		var free: int = Game.first_free_slot()
		if free > 0:
			begin.call(free)
		else:
			_show_slots(Lang.t("栏位已满——新的一局覆盖哪一个？"), false, begin))
	if Game.has_save():
		var ld := Button.new()
		ld.text = Lang.fix(Lang.t("读取存档"))
		ld.custom_minimum_size = Vector2(0, 46)
		vb.add_child(ld)
		ld.pressed.connect(func():
			_show_slots(Lang.t("读取存档"), true, func(n: int):
				if Game.load_game(n):
					selected = Game.player.city
					_close_start()))


# 开局画面看哪里：中文版看中原，英文版看地中海
func _start_view() -> void:
	if Lang.en():
		map.zoom = 0.62
		map.offset = Vector2.ZERO
		map.offset = Vector2(600, 430) - map.geo(15.0, 40.0)
	else:
		map.zoom = 0.7
		map.offset = Vector2(139, 70)
	map.queue_redraw()


func _close_start() -> void:
	start_overlay.queue_free()
	start_overlay = null
	if Game.player.started:
		selected = Game.player.city
		map.center_on(selected)
	refresh()


func _restart() -> void:
	Game.save_game()
	Game.new_game()
	selected = ""
	mode = ""
	_start_view()
	_show_start()
	refresh()
