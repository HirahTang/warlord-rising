extends SceneTree
# 截图： godot --path . -s tools/screenshot.gd   （需要窗口）
var G
var t := 0.0
var stage := 0
var node = null
const OUT := "user://"      # 截图存到 Godot 的用户数据目录

func shot(name: String) -> void:
	root.get_texture().get_image().save_png(OUT + name)

func _process(d: float) -> bool:
	t += d
	if stage == 0:
		G = root.get_node("Game")
		G.autopilot = true
		G.new_game()
		G.player.name = "韩当归"
		G.enlist("陈留")
		G.player.rank = 3
		G.player.merit = 300
		for id in ["qinglong", "liangyin", "diao_bow", "mingguang", "chitu", "xiliang"]:
			G.add_item(id)
		G.equip_press("qinglong")
		var sqd: Array = G.squad()
		for i in sqd.size():
			sqd[i].xp = [0, 12, 35, 90, 170, 300, 460][i % 7]
			sqd[i].kills = i
		for i in 6:
			G.end_month()
		if G.pending_battle != null:
			G.finish_battle(G.auto_resolve(G.pending_battle))
		G.notices.clear()
		node = load("res://scenes/Main.tscn").instantiate()
		root.add_child(node)
		stage = 1
		t = 0.0
	elif stage == 1 and t > 1.0:
		shot("map.png")
		node._set_mode("bag")
		stage = 10
		t = 0.0
	elif stage == 10 and t > 0.6:
		shot("bag.png")
		node.queue_free()
		G.player.city = "陈留"
		G.player.f = G.cities["陈留"].f
		var b: Dictionary = G.make_battle("陈留", "濮阳")
		b.player_side = 0
		G.pending_battle = b
		node = load("res://scenes/Battle.tscn").instantiate()
		root.add_child(node)
		stage = 2
		t = 0.0
	elif stage == 2 and t > 1.2:
		shot("battle_start.png")
		node.yaw = PI * 0.68      # 绕到侧前方看人和马
		node.pitch = 0.16
		node.cam_dist = 5.5
		stage = 3
	elif stage == 3 and t > 1.6:
		shot("closeup.png")
		node.yaw = 0.0
		node.pitch = 0.32
		node.cam_dist = 7.0
		stage = 4
	elif stage == 4 and t > 9.0:
		shot("battle_mid.png")
		print("fps ", Engine.get_frames_per_second())
		quit()
		return true
	return false
