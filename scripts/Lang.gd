extends Node
# 语言：zh 中文（原文）/ en 英文。
# t()  把一句界面模板换成英文（查不到就原样返回）；
# fix() 用在把字写上屏幕的地方：把残留的汉字（城名、人名、术语）换成英文名或拼音，全角标点换成半角。
# 词表在 LangData.gd，由 tools/gen_lang.py 生成。

const SETTINGS := "user://settings.json"
var lang := "zh"
var LD = null
var _run: RegEx
var _gap: RegEx
var _date: RegEx
var _zh_date: RegEx
const MONTHS := ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
var _cache := {}
var misses := {}      # 没收进词表、只好按字转拼音的词（查漏用）
const PUNCT := {"　": "  ", "（": " (", "）": ")", "，": ", ", "：": ": ", "【": "[", "】": "]", "。": ". ", "！": "!", "？": "?",
	"、": ", ", "——": " — ", "…": "...", "〔": "[", "〕": "] ", "“": "\"", "”": "\"", "；": "; ", "｜": "|", "＋": "+", "−": "-", "·": "·"}


func _ready() -> void:
	_run = RegEx.new()
	_run.compile("[\\x{3400}-\\x{9fff}]+(?:·[\\x{3400}-\\x{9fff}]+)*")
	_gap = RegEx.new()
	_gap.compile("\\]([A-Za-z0-9])")
	_date = RegEx.new()
	_date.compile("(AD \\d+|\\d+ BC|Year \\d+), Month (\\d+)")
	_zh_date = RegEx.new()
	_zh_date.compile("(前?)(\\d+)年(\\d+)月")
	if ResourceLoader.exists("res://scripts/LangData.gd"):
		LD = load("res://scripts/LangData.gd")
	if FileAccess.file_exists(SETTINGS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
		if typeof(d) == TYPE_DICTIONARY and str(d.get("lang", "zh")) == "en":
			lang = "en"


func en() -> bool:
	return lang == "en" and LD != null


func set_lang(l: String) -> void:
	lang = l
	_cache.clear()
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"lang": lang}))
		f.close()


func t(s: String) -> String:
	if not en():
		return s
	return str(LD.TEXT.get(s, s))


# 一个名字（城、人、势力、术语）的英文写法
func name_of(r: String) -> String:
	if LD.NAMES.has(r):
		return str(LD.NAMES[r])
	misses[r] = int(misses.get(r, 0)) + 1
	var syl: Array = []
	for i in r.length():
		var ch := r.substr(i, 1)
		if ch == "·":
			syl.append(" ")
		else:
			syl.append(str(LD.CH.get(ch, ch)))
	if syl.is_empty():
		return r
	# 两三个字的多半是人名：姓 + 名；其余连写
	var out := ""
	if r.length() <= 3 and r.length() >= 2 and not r.contains("·"):
		out = str(syl[0]).capitalize() + " " + "".join(syl.slice(1)).capitalize()
	else:
		out = "".join(syl).capitalize()
	return out


func fix(s: String) -> String:
	if not en() or s == "":
		return s
	if _cache.has(s):
		return _cache[s]
	var out := str(LD.TEXT.get(s, s))
	# 存档说明、旧日志里的中文日期
	for m in _zh_date.search_all(out):
		out = out.replace(m.get_string(), ("%s BC, Month %s" if m.get_string(1) != "" else "AD %s, Month %s") % [m.get_string(2), m.get_string(3)])
	var res := ""
	var last := 0
	for m in _run.search_all(out):
		res += out.substr(last, m.get_start() - last) + name_of(m.get_string())
		last = m.get_end()
	res += out.substr(last)
	for k in PUNCT:
		res = res.replace(k, PUNCT[k])
	res = _gap.sub(res, "] $1", true)
	for m in _date.search_all(res):      # “AD 190, Month 5” → “May AD 190”
		var mi := clampi(int(m.get_string(2)), 1, 12)
		res = res.replace(m.get_string(), "%s %s" % [MONTHS[mi], m.get_string(1).replace("Year ", "AD ")])
	if _cache.size() > 4000:
		_cache.clear()
	_cache[s] = res
	return res


# 这一行是不是中文写成的句子（中文模式下记的旧日志）：英文版里不显示，免得变成一串拼音
func is_chinese_sentence(s: String) -> bool:
	for k in ["，", "。", "的", "了", "你", "于", "自", "为"]:
		if s.contains(k):
			return true
	return false


# 地图上的地域名（原文字间有空格）
func region(s: String) -> String:
	if not en():
		return s
	var k := s.replace(" ", "")
	return str(LD.NAMES.get(k, name_of(k))).to_upper()
