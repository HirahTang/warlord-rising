extends Control
# 大地图：按经纬度绘制海岸、江河、道路与城池。滚轮缩放，按住拖动，点击选城。

signal city_clicked(city)

const S := 34.0
const LON0 := 97.0
const LAT1 := 43.6
const LAT_STRETCH := 1.18

var zoom := 0.7
var offset := Vector2(139, 70)
const ZOOM_MIN := 0.14
var land_ll: PackedVector2Array
var isl_ll: Array = []
var sea_cache := {}
var targets: Array = []
var selected := ""
var dragging := false
var drag_moved := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_build_layers()


func geo(lon: float, lat: float) -> Vector2:
	return Vector2((lon - LON0) * S, (LAT1 - lat) * S * LAT_STRETCH) * zoom + offset


# 把某座城挪到视野正中
func center_on(c: String) -> void:
	if not Game.cities.has(c):
		return
	offset += Vector2(600, 420) - city_pos(c)
	queue_redraw()


func city_pos(c: String) -> Vector2:
	return geo(Game.cities[c].lon, Game.cities[c].lat)


func _poly(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(geo(flat[i], flat[i + 1]))
	return out


# 山脉走向：[起点经度, 纬度, 终点经度, 纬度, 山头数]
const RANGES := [
	[98.0, 39.6, 102.8, 37.4, 9], [104.2, 34.0, 111.0, 33.7, 12], [106.5, 32.2, 110.6, 31.4, 8],
	[113.9, 40.2, 113.6, 35.6, 9], [106.0, 41.6, 112.5, 41.2, 9], [115.6, 40.9, 119.4, 40.6, 6],
	[110.0, 25.6, 115.2, 25.1, 9], [116.6, 27.8, 118.6, 25.8, 6], [101.2, 33.4, 100.6, 26.5, 12],
	[99.0, 34.5, 99.4, 28.0, 10], [114.4, 31.4, 116.6, 30.9, 5], [117.0, 36.3, 118.0, 36.0, 3],
	[108.6, 29.6, 110.2, 27.0, 6], [103.0, 30.6, 103.4, 27.6, 6], [124.5, 41.8, 127.0, 43.4, 5],
	[128.2, 38.6, 128.9, 36.6, 5], [137.2, 36.6, 138.4, 35.5, 5], [104.6, 19.2, 107.4, 15.6, 9],
	[98.4, 23.6, 98.8, 18.4, 9], [93.6, 23.5, 94.2, 19.5, 6], [92.0, 31.5, 97.0, 31.0, 9], [92.0, 34.5, 97.5, 35.0, 8],
	[128.0, 41.5, 132.5, 44.5, 7], [132.0, 46.0, 136.0, 45.0, 5],
	# 喜马拉雅、昆仑、天山、阿尔泰、兴都库什、帕米尔、苏莱曼
	[77.0, 32.6, 94.0, 28.4, 18], [77.0, 36.0, 91.0, 36.0, 12], [74.0, 41.6, 94.0, 43.3, 16], [86.0, 46.8, 93.0, 45.2, 5],
	[66.0, 35.3, 74.0, 36.6, 8], [72.0, 38.6, 75.0, 37.2, 4], [69.6, 32.0, 67.6, 28.2, 4], [96.0, 46.6, 101.0, 46.2, 4],
	# 扎格罗斯、厄尔布尔士、高加索、托罗斯、西高止、汉志
	[45.5, 36.0, 55.0, 28.6, 12], [49.2, 36.4, 56.0, 36.9, 6], [40.0, 43.4, 48.0, 41.3, 8], [30.0, 37.2, 38.0, 37.9, 7],
	[73.9, 19.4, 76.8, 10.4, 8], [37.6, 27.0, 43.2, 16.8, 9],
	# 阿尔卑斯、比利牛斯、喀尔巴阡、巴尔干、亚平宁、阿特拉斯、乌拉尔、品都斯
	[6.5, 45.0, 14.0, 47.0, 10], [-1.5, 42.9, 2.5, 42.5, 5], [18.0, 49.3, 26.0, 45.6, 8], [22.0, 43.0, 27.0, 42.8, 5],
	[9.5, 44.3, 15.5, 40.6, 7], [-7.0, 31.6, 9.0, 35.4, 12], [59.0, 57.5, 58.0, 51.0, 7], [20.8, 40.5, 22.0, 38.6, 3],
]

var land_node: Polygon2D
var isl_nodes: Array = []
var tint: Node2D
var over: Node2D
var pulse: Node2D
var kai: SystemFont
var blob: GradientTexture2D
var paper: NoiseTexture2D
var peaks: Array = []      # [经度, 纬度, 大小]
var waves: Array = []      # [经度, 纬度]
var clock := 0.0


func _build_layers() -> void:
	kai = SystemFont.new()
	kai.font_names = PackedStringArray(["Kaiti SC", "STKaiti", "KaiTi", "Songti SC", "Hiragino Sans GB"])
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.55))
	blob = GradientTexture2D.new()
	blob.gradient = g
	blob.fill = GradientTexture2D.FILL_RADIAL
	blob.fill_from = Vector2(0.5, 0.5)
	blob.fill_to = Vector2(1.0, 0.5)
	blob.width = 128
	blob.height = 128
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color("#cdb884"))
	ramp.set_color(1, Color("#eadcb4"))
	paper = NoiseTexture2D.new()
	paper.noise = noise
	paper.seamless = true
	paper.width = 512
	paper.height = 512
	paper.color_ramp = ramp
	land_node = _land_poly()
	land_node.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	tint = Node2D.new()
	land_node.add_child(tint)
	tint.draw.connect(_draw_tint)
	for isl in DB.ISLANDS:
		isl_nodes.append(_land_poly())
	over = Node2D.new()
	add_child(over)
	over.draw.connect(_draw_over)
	pulse = Node2D.new()
	add_child(pulse)
	pulse.draw.connect(_draw_pulse)
	# 山头与海浪的位置只算一次
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	for r in RANGES:
		for k in int(r[4]):
			var t := (k + rng.randf() * 0.6) / float(r[4])
			var lon: float = lerpf(r[0], r[2], t) + rng.randf_range(-0.35, 0.35)
			var lat: float = lerpf(r[1], r[3], t) + rng.randf_range(-0.3, 0.3)
			peaks.append([lon, lat, rng.randf_range(0.8, 1.35)])
	peaks.sort_custom(func(a, b): return a[1] > b[1])
	land_ll = _flat(DB.LAND)
	for isl in DB.ISLANDS:
		isl_ll.append(_flat(isl))
	while waves.size() < 620:
		var pt := Vector2(rng.randf_range(-20.0, 150.0), rng.randf_range(5.0, 60.0))
		if _is_sea(pt):
			waves.append([pt.x, pt.y])


func _is_sea(pt: Vector2) -> bool:
	if Geometry2D.is_point_in_polygon(pt, land_ll):
		return false
	for ip in isl_ll:
		if Geometry2D.is_point_in_polygon(pt, ip):
			return false
	return true


# 一条路的中段在海上，就是海路
func _sea_route(a: String, b: String) -> bool:
	var key := a + "|" + b
	if not sea_cache.has(key):
		var pa := Vector2(Game.cities[a].lon, Game.cities[a].lat)
		var pb := Vector2(Game.cities[b].lon, Game.cities[b].lat)
		sea_cache[key] = _is_sea(pa.lerp(pb, 0.5)) or (_is_sea(pa.lerp(pb, 0.35)) and _is_sea(pa.lerp(pb, 0.65)))
	return sea_cache[key]


func _land_poly() -> Polygon2D:
	var pn := Polygon2D.new()
	pn.texture = paper
	pn.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(pn)
	return pn


func _flat(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(Vector2(flat[i], flat[i + 1]))
	return out


func _set_poly(pn: Polygon2D, flat: Array) -> void:
	var pts := _poly(flat)
	var uv := PackedVector2Array()
	for pt in pts:
		uv.append((pt - offset) / zoom * 0.9)     # 纸纹贴在地图上，随拖动缩放一起走
	pn.polygon = pts
	pn.uv = uv


func _process(delta: float) -> void:
	clock += delta
	pulse.queue_redraw()


func _text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, outline := Color(0.97, 0.93, 0.8, 0.9), font: Font = null) -> void:
	s = Lang.fix(s)
	var f: Font = font if font != null else Game.font
	var w := 300.0
	var p := pos - Vector2(w / 2, 0)
	if outline.a > 0.0:
		ci.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_CENTER, w, size, 5, outline)
	ci.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)


func _city_half(c: String) -> float:
	return (5.5 + 2.0 * int(Game.cities[c].size)) * sqrt(zoom)


# 底层：海面。随后刷新各图层。
func _draw() -> void:
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([Color("#5d8fb0"), Color("#6f9fbd"), Color("#3f6f96"), Color("#356088")]))
	for w in waves:
		var p := geo(w[0], w[1])
		if p.x < -20 or p.y < -20 or p.x > size.x + 20 or p.y > size.y + 20:
			continue
		var r := 7.0 * sqrt(zoom)
		draw_arc(p + Vector2(-r, 0), r, PI * 1.15, PI * 1.85, 8, Color(1, 1, 1, 0.22), 1.5, true)
		draw_arc(p + Vector2(r, 0), r, PI * 1.15, PI * 1.85, 8, Color(1, 1, 1, 0.22), 1.5, true)
	# 浅滩：沿海岸一圈由宽到窄的亮色
	var shapes: Array = [DB.LAND]
	shapes.append_array(DB.ISLANDS)
	for flat in shapes:
		var pl := _poly(flat)
		pl.append(pl[0])
		draw_polyline(pl, Color(0.75, 0.9, 0.95, 0.10), 30.0 * zoom, true)
		draw_polyline(pl, Color(0.75, 0.9, 0.95, 0.14), 18.0 * zoom, true)
		draw_polyline(pl, Color(0.85, 0.95, 0.97, 0.22), 8.0 * zoom, true)
	_set_poly(land_node, DB.LAND)
	for i in isl_nodes.size():
		_set_poly(isl_nodes[i], DB.ISLANDS[i])
	tint.queue_redraw()
	over.queue_redraw()


# 陆地内部（被海岸线裁剪）：势力范围晕染、海岸内侧的阴影
func _draw_tint() -> void:
	for c in Game.cities:
		var ci = Game.cities[c]
		var r := (52.0 + 14.0 * int(ci.size)) * zoom
		var col := Game.fcolor(ci.f)
		col.a = 0.42
		tint.draw_texture_rect(blob, Rect2(city_pos(c) - Vector2(r, r), Vector2(r, r) * 2), false, col)
	var pl := _poly(DB.LAND)
	pl.append(pl[0])
	tint.draw_polyline(pl, Color(0.45, 0.33, 0.15, 0.16), 26.0 * zoom, true)
	tint.draw_polyline(pl, Color(0.45, 0.33, 0.15, 0.22), 10.0 * zoom, true)


func _mountain(p: Vector2, k: float) -> void:
	var w := 11.0 * k
	var h := 15.0 * k
	var top := p + Vector2(0, -h)
	over.draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), top, p + Vector2(-w * 0.1, 0)]), Color(0.62, 0.55, 0.4, 0.85))
	over.draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.1, 0), top, p + Vector2(w, 0)]), Color(0.42, 0.36, 0.26, 0.85))
	over.draw_colored_polygon(PackedVector2Array([top, top + Vector2(-w * 0.3, h * 0.3), top + Vector2(0, h * 0.22), top + Vector2(w * 0.3, h * 0.3)]), Color(0.96, 0.95, 0.9, 0.8))
	over.draw_polyline(PackedVector2Array([p + Vector2(-w, 0), top, p + Vector2(w, 0)]), Color(0.25, 0.2, 0.12, 0.7), 1.2, true)


# 城池图标：城墙（势力色）+ 城楼。大城多一层楼阁。
func _city_icon(pos: Vector2, h: float, col: Color, sz: int, cul := "han") -> void:
	var ink := Color(0.1, 0.07, 0.04)
	var roof := Color("#4a2418")
	over.draw_circle(pos + Vector2(2, h * 0.95), h * 1.15, Color(0, 0, 0, 0.18))
	var wall := Rect2(pos.x - h, pos.y - h * 0.15, h * 2, h * 1.05)
	over.draw_rect(wall, col)
	over.draw_rect(Rect2(wall.position, Vector2(wall.size.x, wall.size.y * 0.3)), col.lightened(0.25))
	var cw := h * 2 / 7.0
	for i in 4:
		var cr := Rect2(wall.position.x + i * 2 * cw, wall.position.y - h * 0.22, cw, h * 0.24)
		over.draw_rect(cr, col.lightened(0.25))
		over.draw_rect(cr, ink, false, 1.0)
	over.draw_rect(wall, ink, false, 1.6)
	over.draw_rect(Rect2(pos.x - h * 0.2, pos.y + h * 0.35, h * 0.4, h * 0.55), ink)     # 城门
	var y := pos.y - h * 0.37
	var tiers := 1 if sz <= 1 else (2 if sz == 2 else 3)
	var w := h * 0.95
	var late: bool = Game.scenario == "suitang" or Game.scenario == "wudai"
	var top := "pagoda"
	if cul == "steppe":
		top = "yurt"
	elif cul == "india" or cul == "sea":
		top = "shikhara"
	elif cul == "arab" or ((cul == "persia" or cul == "rome" or cul == "xiyu") and late):
		top = "dome"
	elif cul == "rome":
		top = "temple"
	elif cul == "persia" or cul == "xiyu" or cul == "tibet" or cul == "north":
		top = "keep"
	if top != "pagoda":
		var by := pos.y - h * 0.37
		match top:
			"yurt":
				for k in (1 if tiers == 1 else 3):
					var cx := pos.x + (0.0 if k == 0 else (-1.0 if k == 1 else 1.0) * h * 0.75)
					var r := h * (0.62 if k == 0 else 0.4)
					var pts := PackedVector2Array()
					for i in 9:
						var a := PI + i * PI / 8.0
						pts.append(Vector2(cx + cos(a) * r, by + sin(a) * r * 0.8))
					over.draw_colored_polygon(pts, Color("#ece2c8"))
					pts.append(pts[0])
					over.draw_polyline(pts, ink, 1.2, true)
					over.draw_line(Vector2(cx - r * 0.7, by - r * 0.45), Vector2(cx + r * 0.7, by - r * 0.45), Color("#a8442e"), 1.6)
			"dome":
				var r2 := h * (0.5 + 0.1 * tiers)
				var dp := PackedVector2Array()
				for i in 11:
					var a2 := PI + i * PI / 10.0
					dp.append(Vector2(pos.x + cos(a2) * r2, by + sin(a2) * r2 * 1.05))
				over.draw_colored_polygon(dp, Color("#3f9a9a") if cul != "rome" else Color("#c8683a"))
				dp.append(dp[0])
				over.draw_polyline(dp, ink, 1.2, true)
				over.draw_line(Vector2(pos.x, by - r2 * 1.05), Vector2(pos.x, by - r2 * 1.05 - h * 0.3), Color("#d9b04a"), 2.0)
				if tiers >= 2:
					for sx in [-1.0, 1.0]:
						var tr := Rect2(pos.x + sx * h * 0.95 - h * 0.09, by - h * 0.9, h * 0.18, h * 0.9)
						over.draw_rect(tr, Color("#e6dcc0"))
						over.draw_rect(tr, ink, false, 1.0)
			"temple":
				var tw := h * (1.1 + 0.15 * tiers)
				var th := h * 0.5
				for k in 4:
					var cr2 := Rect2(pos.x - tw + k * tw * 2 / 3.0 - h * 0.07, by - th, h * 0.14, th)
					over.draw_rect(cr2, Color("#f0ead8"))
					over.draw_rect(cr2, ink, false, 0.8)
				var pedi := PackedVector2Array([Vector2(pos.x - tw * 1.1, by - th), Vector2(pos.x, by - th - h * 0.5), Vector2(pos.x + tw * 1.1, by - th)])
				over.draw_colored_polygon(pedi, Color("#c8683a"))
				pedi.append(pedi[0])
				over.draw_polyline(pedi, ink, 1.2, true)
			"keep":
				var kw := h * 0.75
				var kh := h * (0.4 + 0.25 * tiers)
				var kr := Rect2(pos.x - kw, by - kh, kw * 2, kh)
				over.draw_rect(kr, Color("#dcc9a0") if cul != "tibet" else Color("#f0ead8"))
				over.draw_rect(kr, ink, false, 1.2)
				for k in 3:
					var mr := Rect2(pos.x - kw + k * kw * 0.8, by - kh - h * 0.2, kw * 0.4, h * 0.2)
					over.draw_rect(mr, Color("#dcc9a0") if cul != "tibet" else Color("#8a2a22"))
					over.draw_rect(mr, ink, false, 0.8)
			"shikhara":
				var sw := h * 0.95
				var sy := by
				for k in tiers + 2:
					var rr := Rect2(pos.x - sw, sy - h * 0.26, sw * 2, h * 0.26)
					over.draw_rect(rr, Color("#c8785a"))
					over.draw_rect(rr, ink, false, 1.0)
					sy -= h * 0.26
					sw *= 0.72
				over.draw_circle(Vector2(pos.x, sy - 2.0), 2.4, Color("#ffd24a"))
		return
	for t in tiers:
		var eave := PackedVector2Array([Vector2(pos.x - w * 1.3, y), Vector2(pos.x - w * 0.7, y - h * 0.5), Vector2(pos.x + w * 0.7, y - h * 0.5), Vector2(pos.x + w * 1.3, y)])
		over.draw_colored_polygon(eave, roof)
		eave.append(eave[0])
		over.draw_polyline(eave, ink, 1.2, true)
		y -= h * 0.5
		if t < tiers - 1:
			var body := Rect2(pos.x - w * 0.55, y - h * 0.26, w * 1.1, h * 0.26)
			over.draw_rect(body, Color("#c8442e"))
			over.draw_rect(body, ink, false, 1.0)
			y -= h * 0.26
			w *= 0.78
	if sz >= 3:
		over.draw_circle(Vector2(pos.x, y - 2.0), 2.6, Color("#ffd24a"))


func _draw_over() -> void:
	var o := over
	var shapes: Array = [DB.LAND]
	shapes.append_array(DB.ISLANDS)
	for flat in shapes:
		var pl := _poly(flat)
		pl.append(pl[0])
		o.draw_polyline(pl, Color("#5e4a28"), 2.4, true)
	for lk in DB.LAKES:      # 内陆的海与湖
		var lp := _poly(lk)
		o.draw_colored_polygon(lp, Color("#5f93b4"))
		lp.append(lp[0])
		o.draw_polyline(lp, Color(0.85, 0.95, 0.97, 0.35), 6.0 * zoom, true)
		o.draw_polyline(lp, Color("#5e4a28"), 2.0, true)
	for r in DB.RIVERS:
		var rp := _poly(r)
		o.draw_polyline(rp, Color(0.2, 0.38, 0.6, 0.55), 5.5 * sqrt(zoom), true)
		o.draw_polyline(rp, Color("#7fb2dc"), 2.6 * sqrt(zoom), true)
	for pk in peaks:
		var clear := true
		for c in Game.cities:
			if absf(float(Game.cities[c].lon) - float(pk[0])) < 0.75 and absf(float(Game.cities[c].lat) - float(pk[1])) < 0.6:
				clear = false
				break
		if clear:
			_mountain(geo(pk[0], pk[1]), float(pk[2]) * sqrt(zoom))
	for rg in Game.regions:
		_text(o, geo(rg[1], rg[2]), Lang.region(str(rg[0])), int((22 if Lang.en() else 34) * sqrt(zoom)), Color(0.32, 0.2, 0.08, 0.42), Color(0, 0, 0, 0), kai)
	for e in Game.edges:
		if not Game.cities.has(e[0]) or not Game.cities.has(e[1]):
			continue
		var a := city_pos(e[0])
		var b := city_pos(e[1])
		if _sea_route(e[0], e[1]):
			o.draw_dashed_line(a, b, Color(0.95, 0.98, 1.0, 0.75), 1.8, 3.0)      # 海路
		else:
			o.draw_line(a, b, Color(0.95, 0.9, 0.75, 0.35), 3.2, true)
			o.draw_dashed_line(a, b, Color(0.35, 0.22, 0.1, 0.75), 1.6, 5.0)

	for c in Game.cities:
		var ci = Game.cities[c]
		var pos := city_pos(c)
		var half := _city_half(c)
		_city_icon(pos, half, Game.fcolor(ci.f), int(ci.size), Game.culture_of(c))
		if Game.is_capital(c):      # 国都：城楼上一颗金星
			var tiers := clampi(int(ci.size), 1, 3)
			var sp := pos + Vector2(0, -half * (0.95 + tiers * 0.66) - 7.0)
			var star := PackedVector2Array()
			for k in 10:
				var rr := 7.0 if k % 2 == 0 else 3.0
				star.append(sp + Vector2(sin(k * PI / 5.0), -cos(k * PI / 5.0)) * rr * sqrt(zoom) * 1.2)
			o.draw_colored_polygon(star, Color("#ffd24a"))
			star.append(star[0])
			o.draw_polyline(star, Color(0.2, 0.12, 0.02), 1.2, true)
		# 缩得很小时城名会糊成一片：只留大城、国都和选中的城
		if zoom >= 0.34 or c == selected or (zoom >= 0.22 and (int(ci.size) >= 3 or Game.is_capital(c) and int(ci.size) >= 2)):
			_text(o, pos + Vector2(0, half + 19), c, int(clampf(17 * sqrt(zoom), 13 if zoom < 0.34 else 15, 26)), Color("#1c120a"), Color(0.98, 0.94, 0.82, 0.95), kai)
		if zoom >= 1.15:
			_text(o, pos + Vector2(0, half + 36), ("%s %dk" % [Game.fname(ci.f), int(ci.troops) / 1000]) if Lang.en() else Lang.t("%s %.1f万") % [Game.fname(ci.f), int(ci.troops) / 10000.0], 13, Color("#4a2a10"))

	# 四边压暗，中间透亮
	var e0 := Color(0.05, 0.03, 0.0, 0.0)
	var e1 := Color(0.05, 0.03, 0.0, 0.42)
	var d := 90.0
	o.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, d), Vector2(0, d)]), PackedColorArray([e1, e1, e0, e0]))
	o.draw_polygon(PackedVector2Array([Vector2(0, size.y - d), Vector2(size.x, size.y - d), size, Vector2(0, size.y)]), PackedColorArray([e0, e0, e1, e1]))
	o.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(d, 0), Vector2(d, size.y), Vector2(0, size.y)]), PackedColorArray([e1, e0, e0, e1]))
	_compass(Vector2(1126, 540), 42.0)

	# 图例：各势力城数
	var counts := {}
	for c in Game.cities:
		counts[Game.cities[c].f] = int(counts.get(Game.cities[c].f, 0)) + 1
	var fs: Array = counts.keys()
	fs.sort_custom(func(a, b): return counts[a] > counts[b])
	var more: int = maxi(0, fs.size() - 14)
	fs = fs.slice(0, 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.82)
	sb.border_color = Color("#b08d4a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	o.draw_style_box(sb, Rect2(8, 8, 150, fs.size() * 22.0 + 46 + (22 if more > 0 else 0)))
	o.draw_string(kai, Vector2(8, 34), Lang.t("天下大势"), HORIZONTAL_ALIGNMENT_CENTER, 150, 22, Color("#ffd98a"))
	o.draw_line(Vector2(20, 42), Vector2(146, 42), Color("#b08d4a"), 1.0)
	var y := 50.0
	for f in fs:
		o.draw_rect(Rect2(20, y, 14, 14), Game.fcolor(f))
		o.draw_rect(Rect2(20, y, 14, 14), Color("#e8dcc0"), false, 1.0)
		o.draw_string(Game.font, Vector2(42, y + 13), Lang.fix(Game.fname(f)), HORIZONTAL_ALIGNMENT_LEFT, 84 if Lang.en() else -1, 13 if Lang.en() else 15, Color.WHITE)
		o.draw_string(Game.font, Vector2(8, y + 13), ("%d" % counts[f]) if Lang.en() else Lang.t("%d 城") % counts[f], HORIZONTAL_ALIGNMENT_RIGHT, 138, 15, Color("#e8dcc0"))
		y += 22.0
	if more > 0:
		o.draw_string(Game.font, Vector2(8, y + 13), Lang.t("…… 另有 %d 家") % more, HORIZONTAL_ALIGNMENT_CENTER, 150, 14, Color("#b8ad98"))


func _compass(c: Vector2, r: float) -> void:
	var o := over
	var gold := Color("#d9b96a")
	var ink := Color(0.12, 0.08, 0.04)
	o.draw_circle(c, r * 1.02, Color(0.1, 0.08, 0.05, 0.45))
	o.draw_arc(c, r, 0, TAU, 48, gold, 2.0, true)
	o.draw_arc(c, r * 0.78, 0, TAU, 48, Color(gold, 0.6), 1.0, true)
	for i in 16:
		var a := TAU * i / 16.0
		o.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.78, c + Vector2(cos(a), sin(a)) * r, Color(gold, 0.7), 1.0)
	for pass_i in 2:
		for i in 4:
			var a := TAU * i / 4.0 + (PI / 4 if pass_i == 0 else 0.0) - PI / 2
			var ln := r * (0.5 if pass_i == 0 else 0.95)
			var tip := c + Vector2(cos(a), sin(a)) * ln
			var s1 := c + Vector2(cos(a + PI / 2), sin(a + PI / 2)) * r * 0.14
			var s2 := c - Vector2(cos(a + PI / 2), sin(a + PI / 2)) * r * 0.14
			o.draw_colored_polygon(PackedVector2Array([c, s1, tip]), Color("#f1e3b8") if pass_i == 1 else gold.darkened(0.2))
			o.draw_colored_polygon(PackedVector2Array([c, s2, tip]), Color("#8a2a1e") if (pass_i == 1 and i == 0) else ink)
	o.draw_circle(c, 3.0, gold)
	o.draw_string_outline(kai, c + Vector2(-20, -r - 6), Lang.t("北"), HORIZONTAL_ALIGNMENT_CENTER, 40, 20, 5, Color(0.1, 0.08, 0.05, 0.8))
	o.draw_string(kai, c + Vector2(-20, -r - 6), Lang.t("北"), HORIZONTAL_ALIGNMENT_CENTER, 40, 20, Color("#ffd98a"))


# 顶层动效：可选目标的光圈、选中框、玩家所在
func _draw_pulse() -> void:
	var k := 0.5 + 0.5 * sin(clock * 4.0)
	for c in targets:
		if not Game.cities.has(c):
			continue
		var pos := city_pos(c)
		var half := _city_half(c)
		pulse.draw_circle(pos, half + 10.0 + k * 5.0, Color(1, 0.86, 0.2, 0.18 + 0.14 * k))
		pulse.draw_arc(pos, half + 10.0 + k * 5.0, 0, TAU, 40, Color(1, 0.9, 0.3, 0.9), 2.5, true)
	if selected != "" and Game.cities.has(selected):
		var pos2 := city_pos(selected)
		var r := _city_half(selected) + 12.0
		for i in 4:
			var a := clock * 1.2 + TAU * i / 4.0
			pulse.draw_arc(pos2, r, a, a + 1.0, 12, Color.WHITE, 3.0, true)
	var p_city: String = Game.player.city
	if Game.player.started and Game.cities.has(p_city):
		var base := city_pos(p_city)
		var ring := fmod(clock * 0.8, 1.0)
		pulse.draw_arc(base, _city_half(p_city) + 6.0 + ring * 22.0, 0, TAU, 40, Color(1, 0.82, 0.29, 0.8 * (1.0 - ring)), 2.5, true)
		var pp := base + Vector2(0, -_city_half(p_city) * 2.3 - 16.0 - k * 4.0)
		pulse.draw_colored_polygon(PackedVector2Array([pp + Vector2(-7, 6), pp + Vector2(7, 6), pp + Vector2(0, 19)]), Color(0.1, 0.08, 0.05))
		pulse.draw_circle(pp, 12.5, Color(0.1, 0.08, 0.05))
		pulse.draw_circle(pp, 10.5, Color("#ffd24a"))
		pulse.draw_string(Game.font, pp + (Vector2(-5.0, 5.5) if Lang.en() else Vector2(-7.5, 5.5)), Lang.t("你"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.BLACK)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var old := zoom
			zoom = clampf(zoom * (1.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), ZOOM_MIN, 3.0)
			offset = e.position - (e.position - offset) * (zoom / old)
			queue_redraw()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				dragging = true
				drag_moved = 0.0
			else:
				dragging = false
				if drag_moved < 6.0:
					_pick(e.position)
	elif e is InputEventMouseMotion and dragging:
		offset += e.relative
		drag_moved += e.relative.length()
		queue_redraw()
	elif e is InputEventMagnifyGesture:
		var old2 := zoom
		zoom = clampf(zoom * e.factor, ZOOM_MIN, 3.0)
		offset = e.position - (e.position - offset) * (zoom / old2)
		queue_redraw()
	elif e is InputEventPanGesture:
		offset -= e.delta * 8.0
		queue_redraw()


func _pick(at: Vector2) -> void:
	var best := ""
	var best_d := 26.0
	for c in Game.cities:
		var d := city_pos(c).distance_to(at)
		if d < best_d:
			best_d = d
			best = c
	if best != "":
		city_clicked.emit(best)
