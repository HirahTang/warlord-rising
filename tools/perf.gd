extends SceneTree
# 性能探针： godot --path . -s tools/perf.gd   每秒打印 帧数/最长帧/物理耗时/绘制调用/存活人数
var G
var t := 0.0
var stage := 0
var node = null
var acc := 0.0
var frames := 0
var worst := 0.0
var mode := ""
var spikes := 0

func _process(d: float) -> bool:
	t += d
	if stage == 0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		G = root.get_node("Game")
		G.autopilot = true
		G.new_game()
		G.enlist("陈留")
		G.player.rank = 5
		G.player.merit = 99999
		G.player.city = "陈留"
		G.player.f = G.cities["陈留"].f
		G.cities["陈留"].troops = 90000
		G.cities["濮阳"].troops = 90000
		var b: Dictionary = G.make_battle("陈留", "濮阳")
		b.player_side = 0
		G.pending_battle = b
		node = load("res://scenes/Battle.tscn").instantiate()
		root.add_child(node)
		stage = 1
		t = 0.0
		mode = ""
		for a in OS.get_cmdline_user_args():
			mode = a
		if mode == "noproc":
			node.set_process(false)
		elif mode == "nohud":
			node.hud.visible = false
		return false
	acc += d
	frames += 1
	worst = maxf(worst, d)
	if d > 0.02 and t > 2.0:
		spikes += 1
	if acc >= 1.0:
		var alive := 0
		for tm in node.units:
			for u in tm:
				if is_instance_valid(u) and not u.dead:
					alive += 1
		print("t=%2d fps=%4d worst=%5.1fms phys=%4.1fms proc=%4.1fms draws=%d nodes=%d alive=%d" % [int(t), frames, worst * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), alive])
		acc = 0.0
		frames = 0
		worst = 0.0
	if t > 60.0 or G.last_result != null:
		print("mode=%s spikes>20ms: %d in %.0fs" % [mode, spikes, t])
		quit()
		return true
	return false
