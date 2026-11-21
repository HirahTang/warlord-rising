extends SceneTree
# 无界面自检： godot --headless --path . -s tools/smoke_test.gd
# 数据完整性 → 200 年 AI 推演 → 玩家成长全流程 → 一场由 AI 代打的 3D 战斗。

var G
var D
var fails := 0
var stage := 0
var battle = null
var start_frame := 0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _process(_d: float) -> bool:
	if stage == 0:
		stage = 1
		G = root.get_node("Game")
		D = root.get_node("DB")
		G.autopilot = true
		_data()
		_world_sim()
		_capitals()
		_items()
		_career()
		_start_battle("siege")
	elif stage == 1 or stage == 2:
		# 以 last_result 判断结束：打完后月末结算可能立刻又生成一场新战斗
		if G.last_result != null:
			var r = G.last_result
			var secs := (Engine.get_physics_frames() - start_frame) / 60.0
			print("  战斗结束：胜方 %d，攻余 %d 守余 %d，斩获 %d，用时 %.0f 秒" % [r.winner, r.att_left, r.def_left, r.kills, secs])
			check(r.winner == 0 or r.winner == 1, "3D 战斗（%s）分出胜负" % ("攻城" if stage == 1 else "剿匪"))
			check(r.has("loot") and (r.has("squad") or r.get("palace", false)), "战果带有缴获与亲兵战况")
			if stage == 1:
				check(not siege_cap or r.winner == 1 or r.get("palace", false), "攻破国都后打了宫城之战（国都=%s，宫城=%s）" % [siege_cap, r.get("palace", false)])
			if stage == 1:
				check(saw_cav >= 3 and player_mounted, "攻城战有骑兵（%d 骑），玩家骑马上阵" % saw_cav)
				var sq: Array = G.player.squad
				var xps := {}
				var tot_kills := 0
				for e in sq:
					xps[int(e.xp)] = true
					tot_kills += int(e.kills)
				check(sq.size() == G.squad_size() and xps.size() >= 2, "战后亲兵各人经验不同（%d 种取值，共斩 %d 人）" % [xps.size(), tot_kills])
				print("    缴获 %s" % str(r.loot))
			for nb in root.get_tree().get_nodes_in_group("battle"):
				nb.queue_free()
			if stage == 1:
				stage = 2
				_start_battle("bandit")
			else:
				print("失败项：%d" % fails)
				quit(fails)
				return true
		elif Engine.get_physics_frames() - start_frame > 60 * 300:
			check(false, "3D 战斗在 300 秒内结束")
			quit(1)
			return true
	return false


var saw_cav := 0
var siege_cap := false
var player_mounted := false


func _capitals() -> void:
	print("[国都与人物登场]")
	G.new_game("sanguo")
	check(G.capital_of("董卓") == "洛阳" and G.is_capital("洛阳") and not G.is_capital("长安"), "国都是君主所在城")
	G.notices.clear()
	G.enlist("陈留")
	G.capture_city("洛阳", "曹操", 5000, 1000)
	var cap: String = G.capital_of("董卓")
	check(cap != "洛阳" and cap != "" and G.gens["董卓"].city == cap and G.cities[cap].f == "董卓", "国都陷落后迁都（→%s），君主随迁" % cap)
	G.capture_city("长安", "曹操", 5000, 1000)
	G.capture_city("弘农", "曹操", 5000, 1000)
	var told := false
	for n in G.notices:
		if str(n).contains("【董卓】为【曹操】所灭"):
			told = true
	check(not G.factions.has("董卓") and told, "失尽城池则势力灭亡，并有全局提示")
	var stray := 0
	for g in G.gens:
		if G.gens[g].f == "董卓":
			stray += 1
	check(stray == 0, "灭国后原势力人物或降或流落，无人仍挂旧主名下")
	# 君主指定国都：只能在最大的城里选
	G.new_game("sanguo")
	G.enlist("陈留")
	G.factions["player"] = {"name": "测试", "color": "#ffd24a", "lord": "", "capital": "平原"}
	G.player.f = "player"
	for c in ["平原", "邺", "洛阳", "长安", "东莱"]:
		G.cities[c].f = "player"
	G.player.city = "平原"
	var ch: Array = G.capital_choices("player")
	check(ch.has("洛阳") and ch.has("长安") and ch.has("邺") and not ch.has("平原") and not ch.has("东莱"), "可定都的只有最大的城 %s" % str(ch))
	check(G.act_move_capital("东莱") != "" and G.capital_of("player") == "平原", "小城不能定都")
	check(G.act_move_capital("陈留") != "", "别人的城不能定都")
	check(G.act_move_capital("长安") == "" and G.capital_of("player") == "长安" and G.player.city == "长安", "迁都长安，君主随迁")
	_auto_pending()
	_court()
	_diplo()
	G.new_game("sanguo")
	G.enlist("陈留")
	G.factions["player"] = {"name": "测试", "color": "#ffd24a", "lord": "", "capital": "长安"}
	G.player.f = "player"
	for c in ["邺", "洛阳", "长安"]:
		G.cities[c].f = "player"
	if G.cities["长安"].f == "player" and G.cities["洛阳"].f == "player" and G.cities["邺"].f == "player":
		G.cities["洛阳"].troops = 90000
		G.capture_city("长安", "董卓", 5000, 0)
		check(G.capital_of("player") == "洛阳", "国都陷落后在最大的城里选兵最多的（→%s）" % G.capital_of("player"))
	# 人物登场
	G.new_game("sanguo")
	check(not G.gens.has("荀彧"), "开局时荀彧尚未出仕")
	for i in 12:
		G.end_month()
		_auto_pending()
	check(G.year == 191 and G.gens.has("荀彧") and G.factions.has(G.gens["荀彧"].f), "191 年荀彧出仕（投%s）" % (G.gens["荀彧"].f if G.gens.has("荀彧") else "?"))
	G.new_game("wudai")
	G.year = 947
	G.month = 12
	G.end_month()
	_auto_pending()
	check(G.gens.has("赵匡胤") and G.cities[G.gens["赵匡胤"].city].f == G.gens["赵匡胤"].f, "无主之人投奔家乡城的主人（赵匡胤→%s）" % (G.gens["赵匡胤"].f if G.gens.has("赵匡胤") else "?"))
	# 宫城之战的衔接
	G.new_game("sanguo")
	G.enlist("陈留")
	var b: Dictionary = G.make_battle("陈留", "濮阳")
	b.player_side = 0
	G.pending_battle = b
	G.last_result = null
	G.finish_battle({"winner": 0, "att_left": 4000, "def_left": 500, "kills": 2, "gen_kills": 0, "hp_pct": 0.8, "player_down": false})
	check(G.pending_battle != null and G.pending_battle.type == "palace" and G.cities["濮阳"].f == "刘岱" and G.last_result == null, "攻破国都外城后转入宫城之战，城尚未易手")
	G.finish_battle({"winner": 0, "att_left": 10, "def_left": 0, "kills": 3, "gen_kills": 1, "hp_pct": 0.5, "player_down": false})
	check(G.cities["濮阳"].f == "曹操" and int(G.last_result.kills) == 5 and G.last_result.palace, "宫城得胜后城池易手，两场战果合并")
	G.new_game("sanguo")
	G.notices.clear()


func _court() -> void:
	print("[将领、俘虏与招募]")
	G.new_game("sanguo")
	G.enlist("陈留")
	G.factions["player"] = {"name": "测试", "color": "#ffd24a", "lord": "", "capital": "陈留"}
	G.player.f = "player"
	G.cities["陈留"].f = "player"
	for g in ["夏侯惇", "乐进"]:
		G.gens[g]["loy"] = 55
		G._join(g, "player")
	for g in ["曹操", "夏侯渊", "曹仁", "曹洪", "典韦"]:
		G.gens.erase(g)
	G.factions.erase("曹操")
	G.notices.clear()
	check(G.my_gens().size() == 2 and G.income() == 90 + 60, "岁入 %d（小城 90 + 国都 60）" % G.income())
	# 灭国：全员被俘，交给君主发落
	G.capture_city("平原", "player", 4000, 0)
	var caps: Array = G.my_captives()
	check(caps.has("刘备") and caps.has("关羽") and caps.has("张飞") and caps.has("简雍") and not G.factions.has("刘备"), "灭刘备后其人物尽数被俘 %s" % str(caps))
	check(G.city_gens("平原").is_empty() and G.my_gens().size() == 2, "俘虏不算麾下将领")
	var ps := {}
	for g in caps:
		ps[g] = "%s %d%%" % [G.trait_name(g), roundi(G.recruit_chance(g) * 100)]
	check(G.recruit_chance("刘备") < G.recruit_chance("张飞") + 0.3 and G.recruit_chance("关羽", true) > G.recruit_chance("关羽"), "性格不同招降难度不同 %s" % str(ps))
	G.player.gold = 0
	check(G.act_recruit_gen("关羽").contains("军资不足"), "没钱付招募金不能招降")
	G.player.gold = 100000
	G.act_recruit_gen("关羽")
	check(G.act_recruit_gen("关羽").contains("本月已经谈过") or not G.is_captive("关羽"), "同一人每月只能谈一次")
	G.rng.seed = 5
	var gold0: int = int(G.player.gold)
	var n0: int = G.my_gens().size()
	var fees := 0
	for i in 60:      # 反复劝，总会有人降；只有谈成才扣钱
		for g in G.my_captives():
			G.gens[g]["tried"] = -9999
			var f0: int = G.fee(g)
			G.act_recruit_gen(g, false)
			if G.gens[g].f == "player":
				fees += f0
	var joined: int = G.my_gens().size() - n0
	check(joined >= 2 and gold0 - int(G.player.gold) == fees, "多次招降后 %d 人归降，共付招募金 %d，没谈成的不花钱" % [joined, fees])
	G._make_captive("韩馥", "player", "陈留", false, false)
	G.act_release("韩馥")
	check(G.gens["韩馥"].f == "韩馥" and not G.is_captive("韩馥"), "释放后故主尚在者回归本势力")
	G._make_captive("颜良", "player", "陈留", false, true)
	var n_before: int = G.gens.size()
	G.act_execute("颜良")
	check(G.gens.size() == n_before - 1 and not G.gens.has("颜良"), "处斩俘虏")
	# 忠诚：赏赐立升，无人过问则滑落，过低出走
	var g0: String = "夏侯惇"
	G.gens[g0]["loy"] = 50
	G.player.gold = 500
	G.act_gift(g0)
	check(int(G.gens[g0].loy) > 50 and int(G.player.gold) == 450, "赏赐花 50 金，忠诚立升到 %d" % int(G.gens[g0].loy))
	G.gens[g0]["loy"] = 100
	gold0 = int(G.player.gold)
	G.act_gift(g0)
	check(int(G.player.gold) == gold0 and int(G.gens[g0].loy) == 100, "忠诚已满时赏赐不扣钱")
	gold0 = int(G.player.gold)
	G.gens[g0]["loy"] = 95
	G._court_month()
	check(int(G.player.gold) == gold0 + G.income() and int(G.gens[g0].loy) == 94, "每月结算：军资 +%d，忠诚向底线滑落 1 点" % G.income())
	G._morale(true)
	check(int(G.gens[g0].loy) == 97, "打胜仗忠诚 +3")
	# 太守留守，其余将领自由行动、随驾出征
	for c in ["陈留", "濮阳", "颍川", "汝南"]:
		G.cities[c].f = "player"
	G.player.city = "陈留"
	for g in G.my_gens():
		G.gens[g]["loy"] = 80
		G.gens[g]["gov"] = ""
		G.gens[g].city = "陈留"
	var mg: Array = G.my_gens()
	check(G.act_appoint(mg[0]) == "" and G.gov_of("陈留") == mg[0] and G.is_gov_gen(mg[0]), "任命 %s 为陈留太守" % mg[0])
	G.gens[mg[1]].city = "汝南"
	check(not G.is_follower(mg[1]) and G.is_follower(mg[2]) and not G.is_follower(mg[0]), "身边的非太守将领是随驾，太守与远处的不是")
	G.act_summon(mg[1])
	for i in 4:
		G._free_gens_month()
	check(G.gens[mg[1]].city == "陈留" and G.gens[mg[0]].city == "陈留", "奉召的将领沿己方城池赶到身边（%s 现于%s）" % [mg[1], G.gens[mg[1]].city])
	check(G.act_move("濮阳") == "" and G.gens[mg[2]].city == "濮阳" and G.gens[mg[0]].city == "陈留", "你动身时随驾者同行，太守留守")
	_auto_pending()
	G.player.city = "陈留"
	for g in mg:
		if not G.is_gov_gen(g):
			G.gens[g].city = "陈留"
			G.gens[g]["loy"] = 90
	G.gens[mg[3]]["loy"] = 0
	var cg: Array = G._campaign_gens("陈留")
	check(not cg[0].has(mg[0]) and cg[0].has(mg[1]) and cg[0].has(mg[2]), "出征：太守留守，忠心之将随征 %s，推托 %s" % [str(cg[0]), str(cg[1])])
	G.gens[mg[3]]["loy"] = 80
	if G.cities["洛阳"].f != "player":
		G.cities["陈留"].troops = 60000
		G.player.hp = 100
		check(G.act_attack("洛阳") == "" and not G.pending_battle.att_gens.has(mg[0]) and G.pending_battle.att_gens.size() >= 2, "亲征的将领名单来自随驾者 %s" % str(G.pending_battle.att_gens))
		var went: Array = G.pending_battle.att_gens.duplicate()
		var rr: Dictionary = {"winner": 0, "att_left": 30000, "def_left": 0, "kills": 1, "gen_kills": 0, "hp_pct": 1.0, "player_down": false}
		G.finish_battle(rr)
		if G.pending_battle != null and G.pending_battle.type == "palace":
			G.finish_battle(rr)
		check(G.cities["洛阳"].f == "player" and G.gens[went[0]].city == "洛阳" and G.gens[mg[0]].city == "陈留", "得胜后随征将领同你进驻新城，太守仍在原城")
		_auto_pending()
	for g in G.my_gens():
		G.gens[g]["loy"] = 5
	var n_gens: int = G.my_gens().size()
	for i in 12:
		for g in G.my_gens():
			G.gens[g]["loy"] = 5
		G._court_month()
	check(G.my_gens().size() < n_gens, "忠诚见底的将领出走（%d → %d）" % [n_gens, G.my_gens().size()])
	G.notices.clear()


func _diplo() -> void:
	print("[遣将出征与外交]")
	G.new_game("sanguo")
	G.enlist("陈留")
	G.factions["player"] = {"name": "测试", "color": "#ffd24a", "lord": "", "capital": "陈留"}
	G.player.f = "player"
	G.player.city = "陈留"
	G.cities["陈留"].f = "player"
	for g in ["夏侯惇", "乐进", "典韦"]:
		G.gens[g]["loy"] = 80
		G._join(g, "player", "陈留")
	G.notices.clear()
	var nb: Array = G.adj["陈留"].filter(func(n): return G.cities[n].f != "player")
	var t: String = nb[0]
	var tf: String = G.cities[t].f
	G.cities["陈留"].troops = 80000
	G.cities[t].troops = 800
	check(G.odds("陈留", t, G.dispatch_gens("陈留")) > 1.5 and G.dispatch_gens("陈留").size() == 3, "遣将胜算估计：%s" % G.odds_text(G.odds("陈留", t, G.dispatch_gens("陈留"))))
	var msg: String = G.act_dispatch(t)
	_auto_pending()
	check(msg == "" and G.cities[t].f == "player" and str(G.notices).contains("捷报"), "遣将代攻 %s：不经亲自上阵即攻克，并有捷报" % t)
	check(not G.factions.has(tf) or int(G.dip(tf).rel) < 0, "攻打别家后关系交恶")
	G.gens["乐进"]["loy"] = 10
	G.gens["夏侯惇"]["loy"] = 10
	G.gens["典韦"]["loy"] = 10
	for g in ["夏侯惇", "乐进", "典韦"]:
		G.gens[g].city = "陈留"
	var nb2: Array = G.adj["陈留"].filter(func(n): return G.cities[n].f != "player")
	check(nb2.is_empty() or G.act_dispatch(nb2[0]).contains("没有肯领命"), "忠诚不足的将领不肯代你出征")
	# 太守伺机进取
	G.notices.clear()
	G.gens["夏侯惇"]["loy"] = 90
	G.act_appoint("夏侯惇")
	check(G.act_stance("夏侯惇") == "" and G.gens["夏侯惇"].agg and G.role_text("夏侯惇").contains("进取"), "太守可令其伺机进取")
	var n_city: int = G.faction_cities("player").size()
	if not nb2.is_empty():
		for i in 30:
			G.cities["陈留"].troops = 80000
			for n in nb2:
				if G.cities[n].f != "player":
					G.cities[n].troops = 800
			G._gov_campaigns()
		check(G.faction_cities("player").size() > n_city and G.gens["夏侯惇"].city == "陈留", "进取的太守自行出兵拓地（%d → %d 城），本人仍回任" % [n_city, G.faction_cities("player").size()])
	G.act_stance("夏侯惇")
	n_city = G.faction_cities("player").size()
	for i in 20:
		G._gov_campaigns()
	check(G.faction_cities("player").size() == n_city, "固守的太守不擅自出兵")
	# 结盟
	G.notices.clear()
	var af := ""
	for f in G.other_factions():
		if G.borders(f, "player"):
			af = f
			break
	check(af != "" and G.ally_chance(af) > 0.0 and G.ally_chance(af) < 1.0, "邻邦 %s 结盟成算 %d%%" % [G.fname(af), roundi(G.ally_chance(af) * 100)])
	G.player.gold = 300
	G.dip(af).rel = 0
	var p0: float = G.ally_chance(af)
	G.act_envoy_gift(af)
	check(int(G.player.gold) == 200 and int(G.dip(af).rel) == 15 and G.ally_chance(af) > p0 - 0.001, "送礼 100 金，关系 +15")
	G.dip(af).rel = 100
	for i in 40:
		G.dip(af).cool = 0
		if G.allied(af):
			break
		G.act_ally(af)
	check(G.allied(af) and int(G.dip(af).pact) == 24, "反复遣使后与 %s 结盟，为期 24 月" % G.fname(af))
	var ac := ""      # 盟友与我接壤的一座城
	var mc := ""
	for e in G.edges:
		for k in 2:
			if G.cities[e[k]].f == af and G.cities[e[1 - k]].f == "player":
				ac = e[k]
				mc = e[1 - k]
	G.player.city = mc
	G.player.hp = 100
	G.cities[mc].troops = 50000
	check(G.act_attack(ac).contains("盟友") and G.act_dispatch(ac).contains("盟友") and G.pending_battle == null, "盟约期内不能攻打盟友")
	var hit := false
	for c in G.faction_cities("player"):
		G.cities[c].troops = 300
	for c in G.faction_cities(af):
		G.cities[c].troops = 60000
	var plan: Array = G.plan_attack(af)
	hit = not plan.is_empty() and G.cities[plan[1]].f == "player"
	check(not hit, "盟友兵强也不来犯")
	var aided := false
	for i in 30:
		var fb := {"to": mc, "att_f": "山贼", "def_troops": 1000}
		G._ally_aid(fb)
		if fb.has("aid"):
			aided = int(fb.def_troops) > 1000
			break
	check(aided, "敌军来犯时接壤的盟友发兵相助")
	G.dip(af).pact = 1
	G._diplo_month()
	check(not G.allied(af) and str(G.notices).contains("盟约期满"), "盟约到期自动解除并提示")
	G.dip(af).pact = 10
	var loy0: int = int(G.gens["夏侯惇"].loy)
	check(G.act_break(af).contains("背盟") and not G.allied(af) and int(G.dip(af).rel) == -60 and int(G.gens["夏侯惇"].loy) < loy0, "毁约：关系骤降，将领离心")
	plan = []
	for c in G.faction_cities(af):
		G.cities[c].troops = 60000
	plan = G.plan_attack(af)
	check(not plan.is_empty(), "毁约之后对方可以来犯")
	G.pending_battle = null
	G.notices.clear()


func _items() -> void:
	print("[物品与兵种]")
	for id in D.ITEMS:
		var it: Dictionary = D.ITEMS[id]
		if not (it.has("name") and it.has("slot") and it.has("t")) or G.item_desc(id) == "":
			check(false, "物品 %s 定义完整" % id)
	for tbl in [D.GENERAL_ITEMS, D.GENERAL_HORSES]:
		for g in tbl:
			if not D.ITEMS.has(tbl[g]):
				check(false, "%s 的随身之物存在" % g)
	G.new_game()
	G.enlist("洛阳")
	check(G.weapon_slots() == ["iron_dao", "wood_spear"], "开局带铁刀与木枪")
	check(G.add_item("qinglong").contains("青龙偃月刀") and G.has_item("qinglong"), "获得物品")
	var gold0 := int(G.player.gold)
	G.add_item("qinglong")
	check(int(G.player.gold) == gold0 + 200 and G.player.items.count("qinglong") == 1, "重复物品折成军资")
	G.equip_press("qinglong")
	check(G.weapon_slots() == ["qinglong", "iron_dao"], "点一下装到主手，原主手退到副手")
	G.equip_press("qinglong")
	check(G.weapon_slots() == ["iron_dao", "qinglong"], "再点换到副手")
	G.equip_press("qinglong")
	check(G.weapon_slots() == ["iron_dao"], "再点卸下")
	G.add_item("chitu")
	G.add_item("mingguang")
	check(G.player.eq.horse == "chitu" and G.player.eq.armor == "mingguang", "空栏位自动装上坐骑与铠甲")
	check(G.random_item("weapon", "ji", 3, 3) == "", "吕布在世时方天画戟不会流落民间")
	check(G.act_drill() != "", "没有亲兵不能操练")
	G.player.rank = 3
	var all5: bool = G.act_drill() == ""
	var has_cav := false
	for e in G.player.squad:
		all5 = all5 and int(e.xp) == 5
		has_cav = has_cav or e.k == "cav"
	check(all5 and G.player.squad.size() == 20 and has_cav, "操练：20 名亲兵每人 +5 经验，名册里有骑兵")
	_auto_pending()
	# 个体结算：0 号斩 5 人晋级，1 号阵亡换新兵，2 号没上阵不变
	var s0: Dictionary = G.player.squad[0]
	var n1: String = G.player.squad[1].name
	G.player.squad[1].xp = 200
	var k1: String = G.player.squad[1].k
	G.apply_squad([{"i": 0, "alive": true, "kills": 5}, {"i": 1, "alive": false, "kills": 2}], true)
	check(int(s0.xp) == 5 + 4 + 30 + 3 and G.level_of(int(s0.xp)) == 1 and int(s0.kills) == 5, "活下来的按各自斩获得经验并晋级（%s：%s）" % [s0.name, G.soldier_rank(s0)])
	check(int(G.player.squad[1].xp) == 0 and G.player.squad[1].k == k1 and int(G.player.squad[2].xp) == 5, "阵亡的老兵由同兵种新兵顶替，没上阵的不变")
	check(G.squad_note.contains("阵亡 1 人") and G.squad_note.contains("晋级 1 人"), "战报：%s" % G.squad_note)
	G.squad_note = ""
	G.player.rank = 2
	check(G.squad().size() == 12 and G.player.squad.has(s0), "降衔裁员先裁资历浅的，老兵留下")
	G.player.rank = 3
	G.squad()
	# 军队训练度：打胜仗涨，补新兵被冲淡，练兵有上限
	var c0: String = G.player.city
	G.cities[c0]["vet"] = 2.0
	G.cities[c0].troops = 10000
	G._merge_troops(c0, 10000, 0.0)
	check(absf(G.vet(c0) - 1.0) < 0.01 and int(G.cities[c0].troops) == 20000, "并入等量新兵，训练度减半（%.2f）" % G.vet(c0))
	var bb: Dictionary = G.make_battle(c0, G.adj[c0][0])
	var tgt: String = bb.to
	G.apply_battle(bb, {"winner": 0, "att_left": 9000, "def_left": 100, "kills": 0, "gen_kills": 0, "hp_pct": 1.0, "player_down": false})
	check(absf(G.vet(tgt) - 1.3) < 0.01, "得胜之师进驻新城，训练度 +0.3（%s：%s %.1f）" % [tgt, G.vet_name(G.vet(tgt)), G.vet(tgt)])
	G.notices.clear()
	# 探宝：多座城各找一次，应当有所得，且同城半年内不能再找
	var found := 0
	var n0: int = G.player.items.size()
	for c in ["洛阳", "长安", "邺", "许昌", "襄阳", "成都", "建业", "寿春", "下邳", "北海", "宛", "汝南"]:
		if not G.cities.has(c):
			continue
		G.player.city = c
		G.player.hp = 100
		if G.act_explore() == "":
			found += 1
		_auto_pending()
	check(found >= 8 and G.player.items.size() > n0, "探宝 %d 次，新得 %d 件" % [found, G.player.items.size() - n0])
	check(G.act_explore() != "", "同一座城半年内不能重复寻访")
	var g1 := int(G.player.gold)
	check(G.sell_item("chitu") == 200 and not G.has_item("chitu") and G.player.eq.horse == "" and int(G.player.gold) == g1 + 200, "卖掉坐骑：卸下并得军资")
	G.player.eq.w1 = "iron_dao"
	G.player.eq.w2 = "qinglong"
	G.sell_item("iron_dao")
	check(G.weapon_slots() == ["qinglong"] and G.sell_item("iron_dao") == 0, "卖掉主手后副手顶上；没有的东西卖不了")
	G.add_item("chitu")
	G.notices.clear()
	# 存档往返
	G.autopilot = false
	G.save_prefix = "user://selftest_"
	for n in range(1, G.SLOTS + 1):
		G.delete_slot(n)
	check(not G.has_save() and G.first_free_slot() == 1, "自检栏位起初为空")
	G.slot = 1
	G.save_game()
	var items: Array = G.player.items.duplicate()
	G.new_game()
	check(G.load_game() and G.player.items == items and G.player.eq.horse == "chitu" and int(G.player.squad[0].xp) == 42 and G.player.squad.size() == 20, "行囊与亲兵名册可存读")
	G.autopilot = true
	# 多栏位：存到 3 号，改动后再存 1 号，两边互不影响
	G.autopilot = false
	var name1: String = G.player.name
	G.save_game(3)
	G.player.name = "另一局"
	G.player.gold = 4321
	G.save_game(1)
	check(G.slot == 1 and G.slot_exists(1) and G.slot_exists(3) and not G.slot_exists(2) and G.first_free_slot() == 2, "两个栏位各有存档，2 号仍空")
	check(G.slot_text(3).contains(name1) and G.slot_text(1).contains("另一局") and G.slot_text(2) == "", "栏位说明：%s" % G.slot_text(1))
	check(G.load_game(3) and G.player.name == name1 and G.slot == 3 and int(G.player.gold) != 4321, "读 3 号栏位得到原来那一局，并成为当前栏位")
	check(G.load_game(1) and G.player.name == "另一局" and int(G.player.gold) == 4321, "读 1 号栏位得到另一局")
	check(not G.load_game(2), "空栏位读不出来")
	G.delete_slot(3)
	check(not G.slot_exists(3) and G.slot_exists(1), "删除只影响所选栏位")
	for n in range(1, G.SLOTS + 1):
		G.delete_slot(n)
	G.autopilot = true
	G.save_prefix = "user://save_"
	G.slot = 1


func _data() -> void:
	print("[数据]")
	var flat: Array = D.LAND
	var pts := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		pts.append(Vector2(flat[i], flat[i + 1]))
	check(not Geometry2D.triangulate_polygon(pts).is_empty(), "大陆轮廓可三角化")
	for isl in D.ISLANDS:
		var p2 := PackedVector2Array()
		for i in range(0, isl.size(), 2):
			p2.append(Vector2(isl[i], isl[i + 1]))
		check(not Geometry2D.triangulate_polygon(p2).is_empty(), "岛屿轮廓可三角化")
	for id in G.SC.ORDER:
		G.new_game(id)
		var bad := 0
		for e in G.edges:
			if not G.cities.has(e[0]) or not G.cities.has(e[1]):
				bad += 1
		for g in G.gens:
			var gg = G.gens[g]
			if not G.cities.has(gg.city) or G.cities[gg.city].f != gg.f:
				bad += 1
				print("    武将错位：", g)
		for f in G.factions:
			if G.faction_cities(f).is_empty() or not G.gens.has(G.lord_of(f)) or G.gens[G.lord_of(f)].f != f:
				bad += 1
				print("    势力无城或无君主：", f)
		for c in G.cities:
			if not G.factions.has(G.cities[c].f):
				bad += 1
		var first: String = G.cities.keys()[0]
		var seen := {first: true}
		var queue := [first]
		while not queue.is_empty():
			var c = queue.pop_back()
			for n in G.adj[c]:
				if not seen.has(n):
					seen[n] = true
					queue.append(n)
		check(bad == 0 and seen.size() == G.cities.size(), "%s：%d 势力 %d 城，数据自洽且地图连通" % [G.era.name, G.factions.size(), G.cities.size()])
		# 每个年代推演 30 年
		for i in 360:
			G.end_month()
			if G.pending_battle != null:
				G.finish_battle(G.auto_resolve(G.pending_battle))
		var ok := true
		for c in G.cities:
			if not G.factions.has(G.cities[c].f) or int(G.cities[c].troops) < 0:
				ok = false
		check(ok, "　推演 30 年后合法（%s，剩 %d 家）" % [G.year_text(), G.factions.size()])
	G.new_game("sanguo")


func _world_sim() -> void:
	print("[AI 推演]")
	for years in [10, 30, 200]:
		G.new_game()
		for i in years * 12:
			G.end_month()
		var bad := 0
		for c in G.cities:
			if not G.factions.has(G.cities[c].f) or int(G.cities[c].troops) < 0:
				bad += 1
		var top := ""
		var top_n := 0
		for f in G.factions:
			var n: int = G.faction_cities(f).size()
			if n > top_n:
				top_n = n
				top = f
		print("  %d 年后：剩 %d 势力，最大 %s（%d 城）" % [years, G.factions.size(), top, top_n])
		check(bad == 0, "%d 年推演后城池归属与兵力合法" % years)


func _auto_pending() -> void:
	# 用数值结算代替亲自上阵
	var guard := 0
	while G.pending_battle != null and guard < 20:
		guard += 1
		var b: Dictionary = G.pending_battle
		var r: Dictionary = G.auto_resolve(b)
		if b.type == "bandit":
			r.winner = 1
		r.kills = 3
		r.hp_pct = 0.8
		G.finish_battle(r)


func _career() -> void:
	print("[玩家流程]")
	G.new_game()
	G.player.name = "测试"
	check(G.enlist("邺") == "" and G.player.f == "韩馥", "投军")
	check(G.act_train() == "" and int(G.player.war) > 30, "训练")
	_auto_pending()
	check(G.act_bandit() == "" and G.pending_battle != null, "剿匪生成战斗")
	_auto_pending()
	check(int(G.player.merit) > 0, "剿匪得功勋")
	G.notices.clear()
	G.player.merit = 2000
	G.check_rank()
	check(int(G.player.rank) == 5 and G.squad_size() == 40, "积功升至将军")
	# 领兵强攻一座邻城，直到拿下受封太守
	var tries := 0
	while not G.is_gov() and tries < 300:
		tries += 1
		_auto_pending()
		if G.player.f == "":
			G.enlist(G.player.city)
		var c: String = G.player.city
		var tgt := ""
		for n in G.adj[c]:
			if G.cities[n].f != G.player.f:
				tgt = n
		G.player.hp = 100
		if tgt != "":
			G.cities[c].troops = 60000
			if G.act_attack(tgt) == "":
				_auto_pending()
				continue
		G.act_rest()
	check(G.is_gov(), "领兵破城后受封太守（%s，尝试 %d 次）" % [G.player.gov, tries])
	_auto_pending()
	if G.is_gov():
		check(G.act_independent() == "" and G.is_lord(), "自立为主")
		_auto_pending()
	if G.is_lord():
		G.player.gold = 500
		var before := int(G.cities[G.player.city].troops)
		check(G.act_recruit() == "" or G.pending_battle != null, "征兵")
		_auto_pending()
		# 一路打下去，验证霸主判定
		var guard := 0
		while G.is_lord() and not G.player.hegemon and guard < 2000:
			guard += 1
			_auto_pending()
			if not G.is_lord():
				break
			var c2: String = G.player.city
			if G.cities[c2].f != "player":
				break
			G.cities[c2].troops = 200000
			G.player.hp = 100
			var t2 := ""
			for n in G.adj[c2]:
				if G.cities[n].f != "player":
					t2 = n
			if t2 == "":
				# 四邻都是自己人，换个前线城
				for n in G.adj[c2]:
					G.act_move(n)
					break
				continue
			G.act_attack(t2)
		_auto_pending()
		check(G.player.hegemon, "坐拥十城成为霸主（%d 城）" % G.faction_cities("player").size())
		print("    before=%d" % before)
	var bad := 0
	for c in G.cities:
		if not G.factions.has(G.cities[c].f):
			bad += 1
	check(bad == 0, "流程结束后城池归属合法")


func _start_battle(kind: String) -> void:
	print("[3D 战斗：%s]" % kind)
	G.new_game()
	G.notices.clear()
	G.player.name = "测试"
	G.enlist("陈留")
	G.player.rank = 3
	G.player.war = 60
	G.add_item("xiliang")
	G.add_item("iron_armor")
	if kind == "siege":
		siege_cap = G.is_capital("濮阳")
		var b: Dictionary = G.make_battle("陈留", "濮阳")
		b.player_side = 0
		G.pending_battle = b
	else:
		G.act_bandit()
	G.last_result = null
	start_frame = Engine.get_physics_frames()
	battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	if kind == "siege":
		saw_cav = 0
		for tm in battle.units:
			for u in tm:
				if u.mounted and not u.is_player and not u.is_general:
					saw_cav += 1
		player_mounted = battle.player.mounted and battle.player.armor_def > 0.0
