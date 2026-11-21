extends Node
# 配乐与音效（自动加载为 Sfx）。声音文件由 tools/gen_audio.py 合成，放在 res://audio。
# M 键开关配乐。

const NAMES := ["swing", "swing_heavy", "hit", "clang", "bow", "die", "gate_hit", "gate_break", "click",
	"horn", "gong", "victory", "defeat", "loot", "gallop"]
const MUSIC_DB := -9.0
const SFX_DB := -3.0

var streams := {}
var pool: Array = []
var next_i := 0
var last_played := {}
var mus: Array = []          # 两个播放器，交替淡入淡出
var mus_i := 0
var mus_name := ""
var music_on := true
var listener := Vector3.ZERO     # 战场上以玩家位置为听者


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var st = _load(n)
		if st != null:
			streams[n] = st
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = -60.0
		add_child(m)
		mus.append(m)
	get_tree().node_added.connect(_on_node)


func _load(n: String):
	var path := "res://audio/%s.wav" % n
	if not FileAccess.file_exists(path):
		return null
	return AudioStreamWAV.load_from_file(path)


# 所有按钮按下都响一声
func _on_node(n: Node) -> void:
	if n is Button and not n.pressed.is_connected(_click):      # 按钮被挪动位置时会再次进树，别重复绑定
		n.pressed.connect(_click)


func _click() -> void:
	play("click", -6.0)


func play(n: String, db := 0.0, pitch_var := 0.0) -> void:
	if not streams.has(n):
		return
	var now := Time.get_ticks_msec()
	if now - int(last_played.get(n, -1000)) < 45:     # 同一种声音不叠在同一瞬间
		return
	last_played[n] = now
	var p: AudioStreamPlayer = pool[next_i]
	next_i = (next_i + 1) % pool.size()
	p.stream = streams[n]
	p.volume_db = SFX_DB + db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


# 战场上的声音：离玩家越远越轻，太远就不响
func play_at(n: String, pos: Vector3, db := 0.0, pitch_var := 0.1) -> void:
	var d := pos.distance_to(listener)
	if d > 42.0:
		return
	play(n, db - d * 0.55, pitch_var)


func music(n: String) -> void:
	if n == mus_name:
		return
	mus_name = n
	var old: AudioStreamPlayer = mus[mus_i]
	mus_i = 1 - mus_i
	var cur: AudioStreamPlayer = mus[mus_i]
	create_tween().tween_property(old, "volume_db", -60.0, 1.2)
	var st = _load("music_" + n)
	if st == null:
		return
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = int(st.get_length() * st.mix_rate)
	cur.stream = st
	cur.volume_db = -40.0
	cur.play()
	create_tween().tween_property(cur, "volume_db", MUSIC_DB if music_on else -60.0, 1.5)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_M:
		music_on = not music_on
		create_tween().tween_property(mus[mus_i], "volume_db", MUSIC_DB if music_on else -60.0, 0.4)
