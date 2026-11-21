extends SceneTree
# 手柄探测： godot --path . -s tools/joy_probe.gd [-- 秒数]
# 列出已连接手柄，并在限定时间内打印收到的按键/摇杆事件。
var t := 0.0
var secs := 3.0
var seen := {}

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if not a.is_empty():
		secs = float(a[0])

func _process(d: float) -> bool:
	if t == 0.0:
		for j in Input.get_connected_joypads():
			print("dev %d  name=[%s]  guid=%s  known=%s  info=%s" % [j, Input.get_joy_name(j), Input.get_joy_guid(j), Input.is_joy_known(j), Input.get_joy_info(j)])
		if Input.get_connected_joypads().is_empty():
			print("no joypads")
	t += d
	for j in Input.get_connected_joypads():
		for ax in 6:
			var v := Input.get_joy_axis(j, ax)
			if absf(v) > 0.5:
				var k := "dev%d axis%d %s" % [j, ax, "+" if v > 0 else "-"]
				if not seen.has(k):
					seen[k] = true
					print(k)
		for bt in 22:
			if Input.is_joy_button_pressed(j, bt):
				var k2 := "dev%d button%d" % [j, bt]
				if not seen.has(k2):
					seen[k2] = true
					print(k2)
	if t > secs:
		quit()
		return true
	return false
