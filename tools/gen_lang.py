#!/usr/bin/env python3
"""生成 scripts/LangData.gd（英文版词表）：
    python3 tools/gen_lang.py
TEXT  界面模板（tools/lang_text.json，键是代码里的中文原句）
NAMES 专名与术语（tools/lang_names.py 手写 + 其余自动转拼音）
CH    单字拼音（兜底：任何没收进 NAMES 的汉字串都按字转写）
拼音来自 macOS 自带的转写（tools/pinyin.swift），结果缓存在 tools/pinyin_cache.json。"""
import re, json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lang_names as LN

CJK = re.compile(r'[㐀-鿿]')

# ── 术语 ──
TERMS = {
 "铁刀": "Iron Saber", "百炼钢刀": "Tempered Steel Saber", "古锭刀": "Guding Saber", "七星宝刀": "Seven-Star Blade",
 "青釭剑": "Qinggang Sword", "倚天剑": "Heaven-Reliant Sword", "雌雄双股剑": "Paired Swords", "木枪": "Wooden Spear",
 "铁脊枪": "Iron-Spined Spear", "亮银枪": "Bright Silver Spear", "涯角枪": "Yajiao Spear", "丈八蛇矛": "Serpent Spear",
 "虎头湛金枪": "Tiger-Head Golden Spear", "朴刀": "Pudao", "偃月刀": "Crescent Glaive", "三尖两刃刀": "Three-Pointed Glaive",
 "青龙偃月刀": "Green Dragon Crescent Blade", "铁戟": "Iron Halberd", "镔铁双戟": "Twin Iron Halberds", "方天画戟": "Sky-Piercer Halberd",
 "猎弓": "Hunting Bow", "角弓": "Horn Bow", "雕弓": "Carved Bow", "麒麟弓": "Qilin Bow", "万石弓": "Ten-Thousand-Stone Bow",
 "皮甲": "Leather Armor", "铁札甲": "Iron Lamellar", "鱼鳞甲": "Scale Armor", "明光铠": "Bright-Mirror Armor",
 "兽面连环铠": "Beast-Face Chain Armor", "驽马": "Nag", "西凉马": "Xiliang Horse", "大宛马": "Ferghana Horse",
 "爪黄飞电": "Yellow Lightning", "的卢": "Dilu", "绝影": "Shadowless", "赤兔": "Red Hare",
 "凡品": "Common", "良品": "Fine", "精品": "Superior", "神兵": "Legendary",
 "刀盾": "Sword & Shield", "刀": "Saber", "长枪": "Spear", "大刀": "Glaive", "长戟": "Halberd", "弓": "Bow", "环首刀": "Ring-Pommel Saber",
 "刀盾兵": "Swordsmen", "长枪兵": "Spearmen", "弓兵": "Archers", "骑兵": "Cavalry",
 "新卒": "Recruit", "刀盾手": "Shieldman", "锐士": "Picked Swordsman", "先登": "Vanguard", "陷阵": "Stormer", "铁壁": "Iron Wall",
 "枪兵": "Spearman", "长戟士": "Halberdier", "拒马": "Pikeman", "锐枪": "Shock Spearman", "大戟士": "Great Halberdier",
 "弓手": "Bowman", "强弓手": "Strongbowman", "神射": "Marksman", "连弩士": "Repeating Crossbowman", "射声": "Sharpshooter",
 "轻骑": "Light Horse", "骁骑": "Lancer", "突骑": "Shock Cavalry", "铁骑": "Ironclad Cavalry", "虎豹骑": "Tiger and Leopard Cavalry",
 "忠义": "Loyal", "重利": "Mercenary", "刚烈": "Proud", "随和": "Easygoing", "野心": "Ambitious",
 "士卒": "Soldier", "伍长": "Corporal", "什长": "Sergeant", "百夫长": "Centurion", "校尉": "Colonel", "将军": "General",
 "新兵": "Raw recruits", "熟卒": "Trained", "老兵": "Veterans", "精锐": "Elite", "劲旅": "Crack troops", "百战之师": "Battle-hardened",
 "右斩": "Right slash", "左斩": "Left slash", "力劈": "Cleave", "上撩": "Rising cut", "突刺": "Thrust", "冲刺": "Lunge", "横扫": "Sweep",
 "回旋斩": "Spin slash", "射箭": "Shot", "蓄力箭": "Power shot",
 "中原": "Central Plains", "西凉大漠": "Western Desert", "大漠戈壁": "Desert", "漠北戈壁": "Gobi", "雪域高原": "Snowy Plateau",
 "岭南丛林": "Southern Jungle", "天竺丛林": "Indian Jungle", "江南水乡": "Riverlands", "恒河平原": "Ganges Plain",
 "北地草原": "Northern Steppe", "地中海岸": "Mediterranean Coast", "西陲高地": "Western Highlands", "欧陆林野": "European Woodland",
 "巴蜀山地": "Sichuan Mountains", "雪": "Snow",
 "战国": "Hellenistic Age", "汉末": "Roman Empire", "隋末": "Late Antiquity", "五代": "Viking Age",
 "府衙": "yamen", "王府": "prince's hall", "皇宫": "imperial palace", "在野": "Unaligned", "诸侯": "Warlord", "霸主": "Hegemon",
}
REGIONS = {
 "三韩": "Samhan", "不列颠": "Britannia", "东胡": "Donghu", "两河": "Mesopotamia", "两浙": "Liangzhe", "中原": "Central Plains",
 "乌孙": "Wusun", "云南": "Yunnan", "五天竺": "The Five Indias", "交州": "Jiaozhou", "伊比利亚": "Iberia", "倭": "Wa",
 "兖州": "Yanzhou", "关中": "Guanzhong", "冀州": "Jizhou", "利比亚": "Libya", "匈奴": "Xiongnu", "北非": "North Africa",
 "南中": "Nanzhong", "南印度": "South India", "南天竺": "South India", "占城": "Champa", "可萨": "Khazaria", "司隶": "Sili",
 "后三国": "Later Three Kingdoms", "吐火罗": "Tokharistan", "吐蕃": "Tibet", "吐谷浑": "Tuyuhun", "呼罗珊": "Khorasan",
 "埃及": "Egypt", "塞种": "Saka", "大夏": "Bactria", "大秦": "Roman East", "大食": "Arabia", "天竺": "India", "契丹": "Khitan",
 "安息": "Parthia", "小亚": "Asia Minor", "山东": "Shandong", "岭南": "Lingnan", "巴蜀": "Ba-Shu", "希腊": "Greece",
 "并州": "Bingzhou", "幽州": "Youzhou", "康居": "Kangju", "徐州": "Xuzhou", "意大利": "Italia", "扬州": "Yangzhou",
 "扶南": "Funan", "拂菻": "Byzantium", "新罗": "Silla", "日本": "Japan", "日耳曼": "Germania", "昭武九姓": "Sogdiana",
 "朝鲜": "Joseon", "条支": "Syria", "林邑": "Linyi", "楚": "Chu", "毛里塔尼亚": "Mauretania", "江南": "Jiangnan",
 "江淮": "Jianghuai", "河东": "Hedong", "河中": "Transoxiana", "河北": "Hebei", "河南": "Henan", "河西": "Hexi",
 "波斯": "Persia", "淮南": "Huainan", "渤海": "Balhae", "湖南": "Hunan", "漠北": "Mongolia", "潘诺尼亚": "Pannonia", "燕": "Yan",
 "百济": "Baekje", "百越": "Baiyue", "益州": "Yizhou", "真腊": "Chenla", "秦": "Qin", "突厥": "Turks", "粟特": "Sogdiana",
 "色雷斯": "Thrace", "荆州": "Jingzhou", "荆襄": "Jingxiang", "草原": "The Steppe", "葛逻禄": "Karluks", "蜀": "Shu",
 "西南夷": "Southwestern Tribes", "西域": "Western Regions", "西戎": "Xirong", "西突厥": "Western Turks", "象雄": "Zhangzhung",
 "豫州": "Yuzhou", "贵霜": "Kushan", "赵": "Zhao", "越": "Yue", "身毒": "India", "辽东": "Liaodong", "阿拉伯": "Arabia",
 "陇右": "Longyou", "雍凉": "Yong-Liang", "青州": "Qingzhou", "韩": "Han", "高卢": "Gaul", "高句丽": "Goguryeo", "高棉": "Khmer",
 "魏": "Wei", "鲜卑": "Xianbei", "齐": "Qi",
}
ERA_TEXT = {
 "战国 · 七雄争霸": "300 BC · Age of the Successors",
 "汉末 · 董卓进京": "AD 190 · Rome at Its Height",
 "隋末唐初 · 群雄竞起": "AD 617 · The Last War of Antiquity",
 "五代十国 · 朱温篡唐": "AD 907 · After Charlemagne",
 "周室衰微，七雄并立。赵武灵王胡服骑射，秦昭襄王初登大位，\\n齐、楚、燕、韩、魏各怀其志；四夷环伺，天下未定。":
  "Alexander is dead and his generals have carved up his empire: Seleucus holds Asia, Ptolemy Egypt, Lysimachus Thrace. In the west Rome is subduing Italy and Carthage rules the sea.\\nFar to the east Chandragupta has united India, and seven kingdoms fight for the mastery of China.",
 "董卓挟天子、乱朝纲，关东诸侯起兵讨之。\\n曹操、袁绍、孙坚、刘备各据一隅，三分天下的序幕就此拉开。":
  "Commodus misrules an empire that runs from Britain to the Euphrates; within three years five men will fight for his throne. Beyond the frontiers wait Parthia, the Kushans and the German tribes.\\nAt the far end of the Silk Road the Han dynasty is collapsing into the wars of the Three Kingdoms.",
 "隋炀帝三征高句丽，天下骚然，自己躲在江都醉生梦死。\\n瓦岗李密、太原李渊、河北窦建德……十八路反王并起，谁能再造一统？":
  "Heraclius and Khosrow II are locked in the war that will exhaust both Rome and Persia. Franks, Visigoths and Lombards rule the old western provinces, and in Arabia something new is stirring.\\nIn the east the Sui dynasty is falling, and the Tang is about to rise from its ruins.",
 "朱温废唐自立，是为后梁。晋王李克用誓不两立，\\n南方吴、蜀、吴越、楚、闽各自称雄，北方契丹阿保机方兴未艾。":
  "Charlemagne's heirs quarrel while Vikings, Magyars and Saracens raid their lands. Byzantium is recovering, the Abbasid caliphate is fraying, and the Rus hold Kiev.\\nIn China the Tang dynasty has just fallen, and the land splinters into the Five Dynasties and Ten Kingdoms.",
 "故主尚在则极难招降；一旦归心，忠诚稳固": "Almost impossible to recruit while his old lord lives; once won over, his loyalty holds firm",
 "厚礼与高俸最管用，薄待则离心": "Rich offers work best on him; stint him and he drifts away",
 "只服比自己强的人；亲手击败过他，或你武力不逊于他，才肯低头": "Bows only to his betters: beat him in person, or match his Might, before he will submit",
 "识时务，容易招降，也容易安抚": "A realist: easy to recruit and easy to keep content",
 "招之即来，但忠诚难久，俸禄稍薄便思去": "Comes at a word, but his loyalty does not last; neglect him and he looks elsewhere",
}
MORE = {"平原君赵胜": "Lord Pingyuan", "春申君黄歇": "Lord Chunshen", "信陵君魏无忌": "Lord Xinling", "太子丹": "Crown Prince Dan",
 "嬴政": "Ying Zheng", "隋": "Sui", "后梁": "Later Liang", "晋": "Jin", "吴": "Wu", "吴越": "Wuyue", "闽": "Min", "前蜀": "Former Shu",
 "南汉": "Southern Han", "楚": "Chu", "岐": "Qi", "燕": "Yan", "赵": "Zhao", "秦": "Qin", "齐": "Qi", "魏": "Wei", "韩": "Han",
 "周": "Zhou", "宋": "Song", "鲁": "Lu", "卫": "Wei", "越": "Yue", "中山": "Zhongshan", "义渠": "Yiqu", "林胡": "Linhu",
 "月氏": "Yuezhi", "羌": "Qiang", "滇": "Dian", "夜郎": "Yelang", "西瓯": "Xi'ou", "缚娄": "Fulou", "黑山": "Heishan Bandits",
 "白波": "Baibo Bandits", "瓦岗": "Wagang", "定难": "Dingnan", "归义军": "Guiyi Army", "甘州回鹘": "Ganzhou Uyghurs",
 "六谷部": "Liugu Tribes", "竹王": "Bamboo King", "邪马台": "Yamatai"}
STATES = "秦楚齐燕赵魏韩周宋鲁卫越"
COMPOUND = ["夏侯", "诸葛", "司马", "公孙", "太史", "欧阳", "慕容", "宇文", "长孙", "尉迟", "耶律", "独孤", "令狐", "皇甫", "上官", "鲜于", "淳于",
            "阿史那", "乙支", "黑齿", "藤原", "渊", "拓跋", "呼延", "赫连", "单于", "东方", "南宫", "钟离", "轩辕", "完颜", "契苾"]


def load_scen():
    src = open(os.path.join(HERE, "gen_scenarios.py"), encoding="utf-8").read().replace("\nmain()\n", "\n")
    g = {}
    exec(compile(src, "gen", "exec"), g)
    facs, cities, gens = set(), set(), {}
    for era in g["ERAS"]:
        data, _, _ = g["build"](era)
        for f in data["factions"]:
            facs.add(f[0])
        for c in data["cities"]:
            cities.add(c[0])
        for x in data["generals"]:
            gens[x[0]] = x[1]
        for x in data["later"]:
            gens.setdefault(x[1], x[2])
    return facs, cities, gens


def pinyin_table(chars):
    cache_fn = os.path.join(HERE, "pinyin_cache.json")
    cache = json.load(open(cache_fn, encoding="utf-8")) if os.path.exists(cache_fn) else {}
    need = [c for c in sorted(chars) if c not in cache]
    if need:
        out = subprocess.run(["swift", os.path.join(HERE, "pinyin.swift")], input="\n".join(need), capture_output=True, text=True, check=True).stdout.split("\n")
        for c, p in zip(need, out):
            cache[c] = re.sub(r"[^a-z]", "", p.strip().lower().replace("ü", "u")) or c
        json.dump(cache, open(cache_fn, "w", encoding="utf-8"), ensure_ascii=False)
    return cache


def main():
    facs, cities, gens = load_scen()
    text = json.load(open(os.path.join(HERE, "lang_text.json"), encoding="utf-8"))
    text.update(ERA_TEXT)
    chars = set()
    scripts = os.path.join(HERE, "..", "scripts")
    for fn in os.listdir(scripts):
        if fn.endswith(".gd") and fn != "LangData.gd":
            chars |= set(CJK.findall(open(os.path.join(scripts, fn), encoding="utf-8").read()))
    for s in list(facs) + list(cities) + list(gens):
        chars |= set(CJK.findall(s))
    ch = pinyin_table(chars)

    def py(s):
        return "".join(ch.get(c, c) for c in s)

    def person(s):
        if "·" in s:
            return " ".join(py(p).capitalize() for p in s.split("·"))
        for cs in COMPOUND:
            if s.startswith(cs) and len(s) > len(cs):
                return py(cs).capitalize() + " " + py(s[len(cs):]).capitalize()
        if len(s) >= 3 and s[0] in STATES and s[-1] in "王公君侯":
            return {"王": "King", "公": "Duke", "君": "Lord", "侯": "Marquis"}[s[-1]] + " " + py(s[1:-1]).capitalize() + " of " + py(s[0]).capitalize()
        if len(s) == 1:
            return py(s).capitalize()
        return py(s[0]).capitalize() + " " + py(s[1:]).capitalize()

    names = {}
    manual = {}
    for d in (TERMS, MORE, LN.FAC, LN.CITY, LN.GEN, LN.FIXES):
        manual.update(d)
    # 势力
    for f in facs:
        names[f] = manual.get(f) or (person(f) if f in gens else py(f).capitalize())
    # 城
    for c in cities:
        if c not in names:
            names[c] = manual.get(c) or py(c).capitalize()
    # 人
    for gname, f in gens.items():
        if gname in manual:
            names[gname] = manual[gname]
            continue
        done = False
        for t, pat in LN.TITLES.items():
            if f and gname == f + t:
                names[gname] = pat % names.get(f, py(f).capitalize())
                done = True
        if not done and gname not in names:
            if gname.endswith("王") and len(gname) >= 3 and gname[0] not in STATES:
                names[gname] = "King of " + py(gname[:-1]).capitalize()
            else:
                names[gname] = person(gname)
    for k, v in manual.items():
        names.setdefault(k, v)
    for k, v in REGIONS.items():
        names.setdefault(k, v)

    def lit(s):
        return json.dumps(s, ensure_ascii=False)
    out = ["extends RefCounted", "# 由 tools/gen_lang.py 生成，请改 tools/lang_text.json 与 tools/lang_names.py。", ""]
    # TEXT 的键是 GDScript 源码里的原样字面量（含 \n 转义），这里照搬
    out.append("const TEXT := {")
    for k, v in text.items():
        out.append('\t"%s": "%s",' % (k, v))
    out.append("}")
    out.append("const NAMES := {")
    for k in sorted(names):
        out.append("\t%s: %s," % (lit(k), lit(names[k])))
    out.append("}")
    out.append("const CH := {")
    out.append("\t" + ", ".join("%s: %s" % (lit(c), lit(ch[c])) for c in sorted(ch)))
    out.append("}")
    open(os.path.join(scripts, "LangData.gd"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    auto = [k for k in names if k not in manual and k not in REGIONS]
    print("TEXT %d  NAMES %d（手写 %d，自动拼音 %d）  CH %d" % (len(text), len(names), len(names) - len(auto), len(auto), len(ch)))


main()
