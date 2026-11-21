#!/usr/bin/env python3
"""四个年代剧本的数据源。运行后生成 scripts/Scenarios.gd：
    python3 tools/gen_scenarios.py
城址（经纬度）各年代共用，城名、归属、是否设城随年代变化。
势力写法： (势力名, 颜色或"", 君主名, "城址=城名:兵力(千)[武将 武力 统率, ...] ...")
为了可玩性做了简化，并非严格史实。"""
import re, json, colorsys, sys, os

SITES = {
 # 中原与华北
 "xiangping": (123.2, 41.3), "beiping": (118.9, 40.0), "ji": (116.4, 39.9), "nanpi": (116.7, 38.0),
 "pingyuan": (116.4, 37.0), "ye": (114.5, 36.3), "jinyang": (112.5, 37.9), "shangdang": (113.1, 36.2),
 "beihai": (118.8, 36.7), "puyang": (115.0, 35.6), "chenliu": (114.3, 34.8), "xuchang": (113.8, 34.0),
 "xiaopei": (116.9, 34.7), "xiapi": (118.0, 34.2), "luoyang": (112.4, 34.7), "hongnong": (110.9, 34.5),
 "changan": (108.9, 34.3), "tianshui": (105.7, 34.6), "wuwei": (102.6, 37.9), "hanzhong": (107.0, 33.1),
 "wan": (112.5, 33.0), "runan": (114.4, 32.9), "shouchun": (116.8, 32.6), "lujiang": (117.3, 31.2),
 "jianye": (118.8, 32.1), "wu": (120.6, 31.3), "kuaiji": (120.6, 30.0), "chaisang": (116.0, 29.7),
 "yuzhang": (115.9, 28.6), "xiangyang": (112.1, 32.0), "jiangxia": (114.3, 30.6), "jiangling": (112.2, 30.3),
 "wuling": (111.7, 29.0), "changsha": (113.0, 28.2), "lingling": (111.6, 26.2), "guiyang": (113.0, 25.8),
 "yongan": (109.5, 31.0), "jiangzhou": (106.5, 29.6), "chengdu": (104.1, 30.7), "zitong": (105.2, 31.6),
 "jianning": (103.8, 25.5), "nanhai": (113.3, 23.1), "jiaozhi": (106.0, 21.0),
 "zhongshan": (114.5, 38.2), "pingcheng": (113.3, 40.1), "yunzhong": (111.7, 40.8), "jiuyuan": (109.8, 40.7),
 "xiazhou": (108.8, 37.6), "yiqu": (107.9, 36.0), "fengxiang": (107.4, 34.4), "anyi": (111.2, 35.3),
 "qufu": (117.0, 35.6), "ju": (118.8, 35.5), "jimo": (120.6, 36.9), "suiyang": (115.6, 34.4),
 "guangling": (119.5, 32.5), "jincheng": (103.8, 36.1), "xiping": (101.6, 36.6), "zhangye": (100.5, 38.9),
 "dunhuang": (94.7, 40.1), "lhasa": (91.4, 29.6),
 # 东北、朝鲜半岛、日本
 "liucheng": (120.4, 41.6), "linhuang": (119.4, 43.9), "fuyu": (125.4, 44.0), "shangjing": (129.2, 44.0),
 "guonei": (126.2, 41.1), "pyongyang": (125.75, 39.0), "songak": (126.9, 38.1), "hanseong": (127.0, 37.4),
 "sabi": (126.9, 36.3), "wansan": (127.1, 35.6), "gyeongju": (129.2, 35.8), "gimhae": (128.7, 35.2),
 "dazaifu": (130.5, 33.5), "kumaso": (130.8, 32.3), "izumo": (132.8, 35.4), "yamato": (135.8, 34.7),
 "kanto": (139.5, 35.9), "mutsu": (141.0, 38.4),
 # 华南、西南、中南半岛
 "wenzhou": (120.7, 28.0), "fuzhou": (119.3, 26.1), "quanzhou": (118.6, 24.9), "liuqiu": (121.0, 23.8),
 "guilin": (110.3, 25.3), "yongzhou": (108.3, 22.8), "gaoliang": (111.0, 21.9), "zhuya": (110.3, 19.9),
 "yelang": (105.9, 26.2), "kunming": (102.7, 25.0), "dali": (100.2, 25.7), "yongchang": (99.0, 24.6),
 "jiuzhen": (105.8, 19.6), "linyi": (108.3, 15.9), "vijaya": (109.1, 13.9), "funan": (105.2, 11.4),
 "angkor": (103.9, 13.4), "tangming": (102.6, 18.0), "dvaravati": (100.4, 14.4), "panpan": (99.5, 9.0),
 "pyu": (95.3, 19.2), "pagan": (94.9, 21.2), "pegu": (96.5, 17.3),
}

EDGES = """
xiangping-beiping beiping-ji beiping-nanpi ji-nanpi ji-jinyang nanpi-pingyuan nanpi-ye pingyuan-ye pingyuan-beihai
pingyuan-puyang ye-jinyang ye-shangdang ye-puyang jinyang-shangdang shangdang-luoyang beihai-xiapi beihai-puyang
puyang-chenliu puyang-xiaopei chenliu-xuchang chenliu-luoyang chenliu-xiaopei xuchang-luoyang xuchang-wan xuchang-runan
xiaopei-xiapi xiaopei-shouchun xiaopei-runan xiapi-shouchun xiapi-jianye luoyang-hongnong luoyang-wan hongnong-changan
changan-tianshui changan-hanzhong tianshui-wuwei tianshui-hanzhong hanzhong-zitong hanzhong-xiangyang wan-xiangyang
wan-runan runan-shouchun runan-jiangxia shouchun-lujiang shouchun-jianye lujiang-jianye lujiang-chaisang lujiang-jiangxia
jianye-wu wu-kuaiji kuaiji-yuzhang chaisang-yuzhang chaisang-jiangxia xiangyang-jiangling xiangyang-jiangxia
jiangxia-jiangling jiangxia-changsha jiangling-wuling jiangling-yongan wuling-changsha wuling-lingling changsha-yuzhang
changsha-guiyang changsha-lingling lingling-guiyang lingling-jiaozhi guiyang-nanhai nanhai-jiaozhi jiaozhi-jianning
yongan-jiangzhou jiangzhou-chengdu jiangzhou-zitong jiangzhou-jianning chengdu-zitong chengdu-jianning
xiangping-guonei xiangping-pyongyang xiangping-liucheng liucheng-beiping liucheng-linhuang linhuang-fuyu fuyu-xiangping
fuyu-guonei fuyu-shangjing shangjing-guonei guonei-pyongyang pyongyang-hanseong pyongyang-songak songak-hanseong
hanseong-sabi sabi-wansan hanseong-gyeongju sabi-gyeongju wansan-gyeongju gyeongju-gimhae wansan-gimhae sabi-gimhae
gimhae-dazaifu gyeongju-dazaifu gyeongju-izumo dazaifu-kumaso dazaifu-izumo dazaifu-yamato izumo-yamato yamato-kanto
kanto-mutsu pyongyang-jimo jimo-beihai jimo-hanseong jimo-sabi shangjing-izumo
yunzhong-pingcheng pingcheng-jinyang pingcheng-ji pingcheng-zhongshan zhongshan-ji zhongshan-ye zhongshan-jinyang
zhongshan-nanpi yunzhong-jiuyuan jiuyuan-xiazhou yunzhong-xiazhou yunzhong-jinyang xiazhou-yiqu xiazhou-changan
xiazhou-jinyang yiqu-changan yiqu-tianshui yiqu-fengxiang fengxiang-changan fengxiang-tianshui fengxiang-hanzhong
linhuang-pingcheng linhuang-yunzhong jincheng-tianshui jincheng-wuwei jincheng-xiping wuwei-zhangye zhangye-dunhuang
xiping-zhangye xiping-lhasa xiping-wuwei lhasa-dali lhasa-chengdu wuwei-xiazhou
anyi-hongnong anyi-luoyang anyi-jinyang anyi-shangdang anyi-changan qufu-puyang qufu-xiaopei qufu-beihai qufu-pingyuan
qufu-ju ju-beihai ju-xiapi ju-jimo suiyang-chenliu suiyang-xiaopei suiyang-puyang suiyang-runan suiyang-qufu
guangling-xiapi guangling-jianye guangling-shouchun guangling-wu
wenzhou-kuaiji wenzhou-fuzhou fuzhou-quanzhou fuzhou-yuzhang fuzhou-kuaiji quanzhou-nanhai liuqiu-fuzhou liuqiu-quanzhou
guilin-lingling guilin-guiyang guilin-nanhai guilin-yongzhou guilin-yelang yongzhou-nanhai yongzhou-jiaozhi
yongzhou-gaoliang gaoliang-nanhai gaoliang-zhuya yelang-jiangzhou yelang-jianning yelang-wuling yelang-kunming
kunming-jianning kunming-dali kunming-chengdu kunming-jiaozhi dali-yongchang kunming-yongchang dali-chengdu
yongchang-pyu yongchang-pagan pagan-pyu pyu-pegu pagan-pegu pegu-dvaravati pyu-dvaravati dvaravati-angkor
dvaravati-funan dvaravati-panpan dvaravati-tangming tangming-jiuzhen tangming-angkor tangming-funan tangming-linyi
tangming-jiaozhi jiaozhi-jiuzhen jiuzhen-linyi linyi-vijaya vijaya-funan vijaya-angkor linyi-funan linyi-angkor
angkor-funan funan-panpan jianning-guilin xiping-tianshui zhangye-tianshui zhangye-yiqu
"""

ERAS = []

ERAS.append(dict(id="zhanguo", name="战国 · 七雄争霸", label="战国", year=-300, month=1,
 intro="周室衰微，七雄并立。赵武灵王胡服骑射，秦昭襄王初登大位，\n齐、楚、燕、韩、魏各怀其志；四夷环伺，天下未定。",
 regions=[("燕", 117.6, 41.0), ("赵", 113.6, 39.0), ("齐", 118.9, 37.6), ("魏", 113.3, 35.6), ("韩", 112.6, 33.6),
  ("秦", 106.9, 35.2), ("楚", 113.6, 31.2), ("越", 119.6, 29.0), ("巴 蜀", 104.6, 29.4), ("百 越", 111.5, 23.8),
  ("朝 鲜", 126.8, 39.9), ("东 胡", 121.5, 43.0), ("匈 奴", 108.5, 42.2), ("西 戎", 102.0, 35.0), ("西 南 夷", 101.4, 26.6)],
 factions=[
 ("秦", "#3a3a44", "秦昭襄王", "changan=咸阳:20[秦昭襄王 60 90, 白起 95 100, 魏冉 70 88, 樗里疾 72 90, 任鄙 92 60, 乌获 94 50] fengxiang=雍:8[向寿 70 76] tianshui=上邽:6[] hongnong=函谷:9[甘茂 74 88] hanzhong=汉中:8[芈戎 72 74] chengdu=蜀:10[司马错 82 94, 张若 66 80] jiangzhou=巴:6[]"),
 ("魏", "#e07b2a", "魏襄王", "chenliu=大梁:18[魏襄王 50 66, 公孙衍 60 90, 芒卯 68 74, 惠施 20 76] anyi=安邑:11[公孙喜 78 80]"),
 ("韩", "#6b8e23", "韩襄王", "xuchang=新郑:13[韩襄王 48 62, 暴鸢 80 80, 公仲朋 40 72] shangdang=上党:8[] wan=宛:8[韩珉 55 68]"),
 ("周", "#e6d9a0", "周赧王", "luoyang=洛邑:6[周赧王 30 45, 周最 40 66]"),
 ("赵", "#2f5fd0", "赵武灵王", "ye=邯郸:16[赵武灵王 86 96, 肥义 60 86, 楼缓 45 78, 赵奢 82 90, 廉颇 90 92] jinyang=晋阳:9[赵固 70 72] pingcheng=代:7[赵章 78 68, 牛翦 82 80] yunzhong=云中:6[许钧 76 72]"),
 ("中山", "#a08f70", "中山王", "zhongshan=灵寿:10[中山王 55 62, 司马赒 50 84, 乐池 72 74]"),
 ("燕", "#9ad0e0", "燕昭王", "ji=蓟:13[燕昭王 62 86, 乐毅 80 98, 剧辛 72 82, 郭隗 25 78, 骑劫 76 55] beiping=无终:6[] xiangping=襄平:7[秦开 86 86]"),
 ("齐", "#d9b520", "齐湣王", "beihai=临淄:20[齐湣王 60 62, 田文 55 86, 匡章 84 94, 苏秦 30 90, 淳于髡 20 72] jimo=即墨:8[田单 78 96] pingyuan=高唐:8[触子 74 76] ju=莒:7[达子 78 72]"),
 ("楚", "#d23b3b", "楚怀王", "jiangling=郢:20[楚怀王 50 55, 屈原 30 80, 昭阳 76 86, 昭雎 50 78] xiangyang=鄢:9[景翠 78 82] runan=陈:9[唐眜 82 80] shouchun=寿春:8[景鲤 60 72] guangling=广陵:6[] wu=吴:8[淖齿 78 70] jiangxia=鄂:7[] lujiang=居巢:5[] chaisang=鄱阳:5[] changsha=长沙:7[庄蹻 86 86] wuling=黔中:6[] yongan=巫:5[] lingling=苍梧:4[]"),
 ("宋", "#b05cc8", "宋康王", "suiyang=睢阳:11[宋康王 82 70, 唐鞅 30 62, 田不禋 62 60] xiaopei=彭城:7[]"),
 ("鲁", "", "鲁平公", "qufu=曲阜:6[鲁平公 35 55, 乐正克 30 70]"),
 ("卫", "", "卫嗣君", "puyang=濮阳:5[卫嗣君 40 66, 如耳 35 68]"),
 ("越", "#3fb5b5", "越君", "kuaiji=会稽:8[越君 72 66, 公师隅 60 66] wenzhou=东瓯:4[] fuzhou=闽:4[]"),
 ("义渠", "", "义渠王", "yiqu=义渠:10[义渠王 84 78]"),
 ("林胡", "", "林胡王", "xiazhou=林胡:7[林胡王 82 70]"),
 ("匈奴", "", "匈奴单于", "jiuyuan=阴山:9[匈奴单于 84 80]"),
 ("东胡", "", "东胡王", "liucheng=东胡:9[东胡王 82 74]"),
 ("月氏", "", "月氏王", "zhangye=昭武:9[月氏王 80 76]"),
 ("乌孙", "", "乌孙昆莫", "dunhuang=敦煌:6[乌孙昆莫 78 70]"),
 ("羌", "", "羌豪忍", "xiping=湟中:7[羌豪忍 78 68, 羌豪舞 70 60]"),
 ("朝鲜", "#7fa0c8", "箕否", "pyongyang=王险:9[箕否 60 70, 箕准 66 66, 大夫礼 30 80]"),
 ("辰", "", "辰王", "sabi=辰国:6[辰王 60 62]"),
 ("濊貊", "", "濊王", "fuyu=濊城:6[濊王 72 66]"),
 ("肃慎", "", "肃慎君", "shangjing=肃慎:5[肃慎君 76 60]"),
 ("滇", "", "滇王", "kunming=滇:7[滇王 72 70]"),
 ("夜郎", "", "竹王", "yelang=夜郎:7[竹王 78 72]"),
 ("哀牢", "", "九隆", "yongchang=哀牢:6[九隆 80 72]"),
 ("文郎", "#4f8f6f", "雄王", "jiaozhi=峰州:8[雄王 70 72, 貉侯 62 62]"),
 ("西瓯", "", "蜀泮", "guilin=西瓯:7[蜀泮 82 84, 译吁宋 84 72, 皋通 50 86]"),
 ("缚娄", "", "缚娄君", "nanhai=番禺:5[缚娄君 66 62]"),
 ]))

ERAS.append(dict(id="sanguo", name="汉末 · 董卓进京", label="汉末", year=190, month=1,
 intro="董卓挟天子、乱朝纲，关东诸侯起兵讨之。\n曹操、袁绍、孙坚、刘备各据一隅，三分天下的序幕就此拉开。",
 regions=[("幽 州", 119.5, 41.0), ("冀 州", 115.4, 38.8), ("并 州", 111.3, 38.9), ("青 州", 119.6, 36.2),
  ("兖 州", 116.0, 35.2), ("徐 州", 118.8, 33.6), ("豫 州", 115.3, 33.6), ("司 隶", 110.4, 35.5),
  ("雍 凉", 104.3, 35.4), ("荆 州", 111.0, 30.9), ("扬 州", 118.6, 29.4), ("益 州", 103.0, 28.6),
  ("交 州", 109.3, 23.6), ("辽 东", 124.3, 42.4), ("三 韩", 128.0, 36.8), ("倭", 133.6, 34.2),
  ("南 中", 101.0, 24.0), ("鲜 卑", 112.0, 42.2), ("扶 南", 103.6, 12.4)],
 factions=[
 ("董卓", "#555560", "董卓", "luoyang=洛阳:20[董卓 85 80, 吕布 100 87, 华雄 90 72, 李儒 25 78, 张辽 93 92] changan=长安:16[李傕 77 70, 郭汜 76 68, 贾诩 30 86, 樊稠 78 66] hongnong=弘农:9[徐荣 82 88, 张济 74 72, 张绣 86 78, 高顺 88 90]"),
 ("曹操", "#2f5fd0", "曹操", "chenliu=陈留:9[曹操 72 96, 夏侯惇 90 85, 夏侯渊 91 84, 曹仁 86 88, 曹洪 82 76, 乐进 84 80, 典韦 97 60]"),
 ("袁绍", "#d9b520", "袁绍", "nanpi=南皮:14[袁绍 69 83, 颜良 95 78, 文丑 94 76, 淳于琼 70 65, 田丰 28 82]"),
 ("韩馥", "#c8a070", "韩馥", "ye=邺:20[韩馥 40 55, 张郃 89 90, 沮授 30 80, 麴义 86 88, 潘凤 80 55, 高览 86 74]"),
 ("公孙瓒", "#f0f0f0", "公孙瓒", "beiping=北平:14[公孙瓒 86 82, 严纲 75 72, 田楷 68 70, 赵云 96 88]"),
 ("刘虞", "#9ad0e0", "刘虞", "ji=蓟:12[刘虞 35 70, 鲜于辅 72 74, 阎柔 78 76, 田畴 60 78]"),
 ("刘备", "#2e9e4f", "刘备", "pingyuan=平原:5[刘备 75 80, 关羽 97 93, 张飞 98 85, 简雍 35 45]"),
 ("公孙度", "#7fa0c8", "公孙度", "xiangping=襄平:9[公孙度 70 75, 柳毅 65 62, 公孙康 68 70] pyongyang=乐浪:5[阳仪 60 60]"),
 ("张杨", "#a08f70", "张杨", "shangdang=上党:7[张杨 72 68, 眭固 70 60]"),
 ("黑山", "#4a4a3a", "张燕", "jinyang=晋阳:10[张燕 84 80, 于毒 72 62, 白绕 70 60] zhongshan=常山:8[孙轻 68 60]"),
 ("白波", "", "杨奉", "anyi=河东:8[杨奉 76 70, 徐晃 91 88, 韩暹 70 62, 李乐 68 58]"),
 ("孔融", "#e6a3c0", "孔融", "beihai=北海:8[孔融 25 50, 武安国 82 55, 太史慈 93 82] jimo=东莱:4[王修 45 70]"),
 ("刘岱", "", "刘岱", "puyang=濮阳:10[刘岱 50 60, 鲍信 78 80, 于禁 78 86] qufu=昌邑:5[袁遗 50 62]"),
 ("陶谦", "#8fbf6a", "陶谦", "xiapi=下邳:10[陶谦 45 65, 曹豹 68 58, 糜竺 30 55] xiaopei=彭城:7[陈登 60 82, 糜芳 62 55] ju=琅琊:6[臧霸 85 80, 孙观 76 68] guangling=广陵:5[笮融 60 50]"),
 ("袁术", "#b05cc8", "袁术", "wan=宛:14[袁术 60 62, 纪灵 85 75, 张勋 73 74, 桥蕤 70 68] runan=汝南:8[雷薄 68 60, 陈兰 68 58]"),
 ("孔伷", "", "孔伷", "xuchang=颍川:6[孔伷 30 50, 李旻 60 58]"),
 ("孙坚", "#d23b3b", "孙坚", "changsha=长沙:10[孙坚 93 92, 程普 79 84, 黄盖 83 79, 韩当 85 76, 祖茂 80 68, 孙策 90 88] guiyang=桂阳:5[朱治 70 76]"),
 ("陈温", "", "陈温", "shouchun=寿春:10[陈温 40 55, 蒋钦 84 74, 周泰 91 75]"),
 ("陆康", "", "陆康", "lujiang=庐江:8[陆康 55 78, 周瑜 71 96]"),
 ("许贡", "", "许贡", "wu=吴:9[许贡 50 55, 严白虎 78 62, 朱桓 86 84] jianye=秣陵:8[周昕 65 68, 周昂 62 60]"),
 ("王朗", "", "王朗", "kuaiji=会稽:8[王朗 35 60, 虞翻 60 72, 贺齐 84 82] fuzhou=东冶:4[商升 60 55]"),
 ("华歆", "", "华歆", "yuzhang=豫章:7[华歆 30 62, 诸葛玄 40 55] chaisang=柴桑:5[僮芝 62 55]"),
 ("刘表", "#3fb5b5", "刘表", "xiangyang=襄阳:16[刘表 40 75, 蔡瑁 72 82, 蒯越 35 80, 文聘 84 86] jiangxia=江夏:10[黄祖 70 74, 甘宁 95 84] jiangling=江陵:11[黄忠 94 86, 王威 70 66] wuling=武陵:6[金旋 60 55] lingling=零陵:6[刘度 45 55, 邢道荣 80 50]"),
 ("刘焉", "#e07b2a", "刘焉", "chengdu=成都:18[刘焉 45 78, 张任 87 88, 贾龙 76 78, 刘璋 30 50] zitong=梓潼:8[吴懿 76 80, 李严 82 84] jiangzhou=江州:8[严颜 84 80] yongan=永安:6[赵韪 70 72] jianning=建宁:6[雍闿 70 62] yelang=牂牁:4[朱褒 66 58]"),
 ("张鲁", "#9bbf3a", "张鲁", "hanzhong=汉中:12[张鲁 45 72, 张卫 72 65, 杨任 74 68, 阎圃 30 74]"),
 ("南蛮", "#7a5a2a", "孟获", "yongchang=永昌:8[孟获 88 72, 祝融 84 60, 孟优 72 55] kunming=滇池:6[高定 76 64, 鄂焕 86 55]"),
 ("马腾", "#8c6239", "马腾", "wuwei=武威:11[马腾 84 80, 马超 97 86, 庞德 94 80]"),
 ("韩遂", "", "韩遂", "jincheng=金城:10[韩遂 72 82, 阎行 90 76, 成公英 65 78] tianshui=天水:7[杨秋 70 66, 梁兴 72 62]"),
 ("羌", "", "迷当", "xiping=西平:7[迷当 80 68, 俄何烧戈 82 60]"),
 ("士燮", "#4f8f6f", "士燮", "jiaozhi=交趾:8[士燮 40 70, 士徽 55 55] nanhai=南海:7[士武 58 56] yongzhou=郁林:4[士匡 55 52] jiuzhen=九真:4[士壹 55 58]"),
 ("高句丽", "#8a1f5c", "故国川王", "guonei=国内城:10[故国川王 70 76, 乙巴素 35 85, 发歧 72 62, 延优 70 65]"),
 ("夫余", "", "尉仇台", "fuyu=夫余:8[尉仇台 72 70, 简位居 66 62]"),
 ("乌桓", "", "蹋顿", "liucheng=柳城:9[蹋顿 86 78, 苏仆延 76 66, 楼班 70 60]"),
 ("鲜卑", "", "魁头", "yunzhong=弹汗山:10[魁头 78 70, 步度根 76 72, 轲比能 88 84, 扶罗韩 74 66]"),
 ("匈奴", "", "於夫罗", "pingcheng=美稷:7[於夫罗 82 74, 呼厨泉 76 70, 刘豹 80 68]"),
 ("马韩", "", "辰王", "hanseong=目支国:7[辰王 55 62, 臣智 68 58]"),
 ("斯卢", "", "伐休尼师今", "gyeongju=斯卢城:6[伐休尼师今 62 68, 仇道 78 76]"),
 ("伽倻", "", "首露王", "gimhae=狗邪:5[首露王 75 72, 居登 62 60]"),
 ("邪马台", "#f0a0a0", "卑弥呼", "yamato=邪马台:9[卑弥呼 30 80, 难升米 70 72, 都市牛利 62 60] dazaifu=奴国:6[伊声耆 60 58] izumo=投马国:5[弥弥 62 58]"),
 ("狗奴", "", "卑弥弓呼", "kumaso=狗奴国:7[卑弥弓呼 80 70, 狗古智卑狗 82 66]"),
 ("林邑", "", "区连", "linyi=象林:7[区连 80 72, 范熊 72 66]"),
 ("扶南", "#c8a070", "范师蔓", "funan=特牧城:9[范师蔓 88 84, 混盘况 60 70, 范旃 76 70] tangming=堂明:4[] dvaravati=金邻:5[范金生 70 62]"),
 ("骠", "", "骠王", "pyu=毗湿奴:6[骠王 65 62]"),
 ("顿逊", "", "顿逊王", "panpan=顿逊:4[顿逊王 60 58]"),
 ]))

ERAS.append(dict(id="suitang", name="隋末唐初 · 群雄竞起", label="隋末", year=617, month=7,
 intro="隋炀帝三征高句丽，天下骚然，自己躲在江都醉生梦死。\n瓦岗李密、太原李渊、河北窦建德……十八路反王并起，谁能再造一统？",
 regions=[("河 北", 115.8, 38.8), ("河 东", 111.6, 38.8), ("关 中", 108.2, 35.3), ("陇 右", 103.8, 35.0),
  ("河 南", 114.8, 34.3), ("山 东", 118.6, 36.0), ("江 淮", 117.6, 32.4), ("江 南", 119.4, 29.6),
  ("荆 襄", 111.2, 30.8), ("巴 蜀", 103.4, 29.6), ("岭 南", 111.0, 23.6), ("突 厥", 111.0, 42.4),
  ("高 句 丽", 125.6, 40.6), ("百 济", 126.0, 35.4), ("新 罗", 129.6, 36.9), ("倭", 134.2, 34.0),
  ("吐 蕃", 93.6, 31.2), ("吐 谷 浑", 99.2, 36.0), ("真 腊", 104.2, 13.0), ("林 邑", 108.0, 17.4), ("南 中", 101.2, 24.2)],
 factions=[
 ("隋", "#c22a2a", "杨广", "guangling=江都:20[杨广 55 60, 宇文化及 60 55, 来护儿 85 86, 陈棱 80 80, 司马德戡 78 70] changan=大兴:14[阴世师 70 74, 卫文升 68 80, 李靖 85 97] anyi=河东:9[屈突通 84 88, 桑显和 76 72] ye=魏郡:8[元宝藏 50 60, 魏征 30 85] xiangyang=襄阳:8[窦轶 60 62] chengdu=蜀郡:10[] hanzhong=汉川:6[] jiangzhou=巴郡:5[] zitong=金山:5[] jianye=丹阳:8[乐伯通 60 60] xiaopei=彭城:8[] fengxiang=扶风:6[窦琎 60 66] liucheng=柳城:5[邓暠 62 66] hongnong=弘农:6[]"),
 ("王世充", "#8a1f5c", "王世充", "luoyang=东都:18[王世充 70 82, 段达 60 60, 王仁则 76 66, 庞玉 74 74]"),
 ("瓦岗", "#2e9e4f", "李密", "chenliu=荥阳:18[李密 60 93, 翟让 80 72, 单雄信 93 76, 王伯当 86 78, 裴仁基 82 86, 裴行俨 95 74] puyang=黎阳:12[徐世勣 84 95, 秦琼 96 84, 程咬金 90 72, 罗士信 94 70] xuchang=颍川:7[邴元真 50 60] runan=淮阳:7[房彦藻 45 68] suiyang=梁郡:6[郝孝德 70 66]"),
 ("李渊", "#d9b520", "李渊", "jinyang=太原:16[李渊 70 90, 李世民 88 97, 李建成 72 76, 柴绍 84 80, 刘弘基 86 78, 殷开山 76 80, 段志玄 88 76] shangdang=上党:6[李神通 62 60]"),
 ("刘武周", "#a08f70", "刘武周", "pingcheng=马邑:10[刘武周 80 76, 尉迟恭 97 82, 宋金刚 86 88, 苑君璋 72 74]"),
 ("突厥", "#7fa0c8", "始毕可汗", "yunzhong=定襄:16[始毕可汗 82 84, 处罗 78 76, 颉利 80 74, 突利 76 72, 康鞘利 72 68]"),
 ("梁师都", "", "梁师都", "xiazhou=朔方:9[梁师都 74 72, 李正宝 68 60, 辛獠儿 70 60]"),
 ("薛举", "#8c6239", "薛举", "jincheng=金城:12[薛举 90 84, 薛仁杲 92 68, 宗罗睺 86 82, 郝瑗 30 82] tianshui=天水:8[常仲兴 70 68]"),
 ("李轨", "", "李轨", "wuwei=武威:10[李轨 68 72, 安修仁 72 74, 梁硕 30 80] zhangye=张掖:6[李赟 70 60]"),
 ("窦建德", "#3fb5b5", "窦建德", "nanpi=乐寿:14[窦建德 84 92, 王伏宝 90 86, 苏定方 92 90, 刘黑闼 91 88, 高雅贤 78 78, 凌敬 30 82] pingyuan=平原:7[曹旦 68 60]"),
 ("罗艺", "#f0f0f0", "罗艺", "ji=涿郡:12[罗艺 88 86, 薛万均 90 82, 薛万彻 92 80]"),
 ("高开道", "", "高开道", "beiping=渔阳:7[高开道 86 72, 张金树 70 60]"),
 ("魏刀儿", "", "魏刀儿", "zhongshan=博陵:8[魏刀儿 78 66, 甄翟儿 76 64]"),
 ("王薄", "", "王薄", "beihai=齐郡:7[王薄 76 70, 孟让 74 68] jimo=东莱:5[左孝友 72 62]"),
 ("徐圆朗", "", "徐圆朗", "qufu=鲁郡:9[徐圆朗 78 74, 刘世彻 60 72] ju=琅琊:6[]"),
 ("李子通", "", "李子通", "xiapi=东海:8[李子通 80 78, 毛文深 40 70]"),
 ("杜伏威", "#6b7fd6", "杜伏威", "lujiang=历阳:10[杜伏威 90 86, 辅公祏 76 84, 阚稜 93 74, 王雄诞 90 82] shouchun=淮南:8[西门君仪 70 70]"),
 ("沈法兴", "", "沈法兴", "wu=吴郡:9[沈法兴 62 66, 蒋元超 70 62] kuaiji=会稽:6[] fuzhou=建安:4[]"),
 ("林士弘", "#e6a3c0", "林士弘", "yuzhang=豫章:10[林士弘 78 76, 王戎 66 60] chaisang=九江:6[] nanhai=南海:7[邓文进 68 64]"),
 ("萧铣", "#b05cc8", "萧铣", "jiangling=江陵:14[萧铣 55 78, 董景珍 78 80, 岑文本 30 84] changsha=巴陵:9[文士弘 76 74, 雷世猛 74 72] wuling=武陵:5[] lingling=零陵:5[] guiyang=桂阳:5[] jiangxia=江夏:7[周法明 72 72] guilin=始安:5[李袭志 62 76] yongan=夷陵:5[许绍 60 78]"),
 ("朱粲", "", "朱粲", "wan=南阳:10[朱粲 82 62]"),
 ("冯盎", "#4f8f6f", "冯盎", "gaoliang=高凉:8[冯盎 84 84, 冯智戴 72 72] zhuya=崖州:4[]"),
 ("宁长真", "", "宁长真", "yongzhou=郁林:6[宁长真 72 70]"),
 ("丘和", "", "丘和", "jiaozhi=交趾:8[丘和 62 76, 高士廉 35 80] jiuzhen=九真:4[]"),
 ("爨", "", "爨弘达", "jianning=味县:7[爨弘达 70 68] kunming=昆州:5[爨归王 68 62]"),
 ("蒙舍", "", "细奴逻", "dali=蒙舍:6[细奴逻 76 76, 张乐进求 60 64] yongchang=永昌:4[]"),
 ("吐谷浑", "", "伏允", "xiping=伏俟城:10[伏允 76 74, 慕容顺 66 64, 天柱王 78 66]"),
 ("吐蕃", "#7a5a2a", "囊日论赞", "lhasa=匹播城:9[囊日论赞 80 82, 娘曾古 76 74, 韦义策 72 72, 噶尔东赞 60 92]"),
 ("高句丽", "#e07b2a", "婴阳王", "pyongyang=平壤:16[婴阳王 68 78, 乙支文德 86 97, 高建武 82 84, 渊太祚 70 76] xiangping=辽东城:12[渊盖苏文 92 86, 高延寿 76 74] guonei=国内城:8[] fuyu=扶余城:6[]"),
 ("百济", "#9bbf3a", "武王", "sabi=泗沘:11[武王 72 78, 阶伯 90 86, 允忠 80 80, 成忠 40 82] wansan=完山:5[]"),
 ("新罗", "#2f5fd0", "真平王", "gyeongju=月城:11[真平王 55 74, 金庾信 91 96, 金舒玄 76 78, 金春秋 60 90] hanseong=汉山:7[边品 72 70]"),
 ("倭", "#f0a0a0", "推古天皇", "yamato=飞鸟:10[推古天皇 20 70, 厩户王 50 92, 苏我马子 60 84, 秦河胜 70 70, 小野妹子 45 72] dazaifu=筑紫:6[当麻皇子 62 60] izumo=出云:4[] kanto=毛野:5[上毛野形名 78 68]"),
 ("虾夷", "", "虾夷魁帅", "mutsu=日高见:5[虾夷魁帅 78 60]"),
 ("靺鞨", "", "突地稽", "shangjing=粟末:7[突地稽 80 74]"),
 ("契丹", "", "大贺摩会", "linhuang=潢水:8[大贺摩会 78 72, 孙敖曹 76 70]"),
 ("林邑", "", "范梵志", "linyi=僧伽补罗:8[范梵志 74 74, 范头黎 68 66]"),
 ("真腊", "#c8a070", "伊奢那跋摩", "funan=伊奢那城:11[伊奢那跋摩 82 84, 拔婆跋摩 76 72] tangming=文单:5[]"),
 ("堕罗钵底", "", "堕罗钵底王", "dvaravati=堕罗钵底:6[堕罗钵底王 66 64]"),
 ("骠国", "", "骠王", "pyu=室利差呾罗:8[骠王 66 66]"),
 ("盘盘", "", "盘盘王", "panpan=盘盘:4[盘盘王 60 58]"),
 ("流求", "", "欢斯渴剌兜", "liuqiu=流求:4[欢斯渴剌兜 74 60, 老模 72 55]"),
 ]))

ERAS.append(dict(id="wudai", name="五代十国 · 朱温篡唐", label="五代", year=907, month=4,
 intro="朱温废唐自立，是为后梁。晋王李克用誓不两立，\n南方吴、蜀、吴越、楚、闽各自称雄，北方契丹阿保机方兴未艾。",
 regions=[("河 北", 116.0, 39.0), ("河 东", 111.6, 38.9), ("关 中", 108.4, 35.4), ("中 原", 114.6, 34.2),
  ("淮 南", 117.8, 32.6), ("两 浙", 120.4, 29.2), ("湖 南", 112.0, 27.2), ("蜀", 103.2, 29.8), ("岭 南", 111.6, 23.8),
  ("契 丹", 119.5, 45.0), ("渤 海", 127.6, 43.2), ("后 三 国", 128.2, 37.0), ("日 本", 135.0, 35.6),
  ("河 西", 98.4, 39.6), ("吐 蕃", 94.0, 31.2), ("云 南", 100.8, 24.0), ("高 棉", 104.0, 12.4), ("占 城", 108.0, 17.4)],
 factions=[
 ("后梁", "#c22a2a", "朱温", "chenliu=汴州:22[朱温 80 92, 王彦章 97 80, 葛从周 88 94, 敬翔 28 88, 朱友贞 50 55] luoyang=洛阳:12[张全义 50 76, 朱友珪 66 58] changan=京兆:8[刘知俊 90 86, 康怀贞 80 74] hongnong=陕州:6[] anyi=河中:8[朱友谦 76 76] xuchang=许州:7[冯行袭 72 68] xiaopei=徐州:9[刘鄩 78 93] qufu=兖州:8[牛存节 84 84] beihai=青州:8[贺德伦 70 68] jimo=登州:4[] puyang=滑州:8[贺瑰 80 82] ye=魏州:12[罗绍威 55 66, 杨师厚 90 92] xiangyang=襄州:8[王班 60 58] runan=蔡州:6[] wan=邓州:5[] suiyang=宋州:7[朱友谅 60 56] pingyuan=博州:5[] ju=沂州:4[]"),
 ("晋", "#1f3f8a", "李克用", "jinyang=太原:18[李克用 92 88, 李存勖 93 94, 李嗣源 92 88, 周德威 94 92, 李存审 86 90, 张承业 25 88] shangdang=潞州:9[李嗣昭 88 88, 李存璋 80 76] pingcheng=云州:7[李存进 80 78, 史建瑭 86 76]"),
 ("岐", "#8c6239", "李茂贞", "fengxiang=凤翔:12[李茂贞 78 80, 李继徽 76 72] tianshui=秦州:7[李继崇 70 66]"),
 ("前蜀", "#e07b2a", "王建", "chengdu=成都:20[王建 86 88, 王宗佶 78 74, 晋晖 80 76, 韦庄 20 80] zitong=梓州:8[王宗弼 76 72] hanzhong=兴元:9[王宗侃 80 78, 唐道袭 60 66] jiangzhou=渝州:6[] yongan=夔州:6[张武 76 74]"),
 ("吴", "#3fb5b5", "杨渥", "guangling=扬州:18[杨渥 66 50, 徐温 55 90, 张颢 76 62, 朱瑾 94 84, 徐知诰 60 86] jianye=昇州:9[李遇 80 76] lujiang=庐州:8[刘威 78 80] shouchun=寿州:7[柴再用 84 82] xiapi=泗州:5[] yuzhang=洪州:9[秦裴 82 80, 刘信 80 76] chaisang=江州:5[] jiangxia=鄂州:8[刘存 78 76, 周本 88 84]"),
 ("吴越", "#4f8f6f", "钱镠", "kuaiji=杭州:14[钱镠 84 90, 顾全武 86 90, 杜建徽 84 80, 钱元瓘 70 78] wu=苏州:8[钱镖 68 62, 成及 70 80] wenzhou=温州:5[钱元璙 70 70]"),
 ("闽", "#e6a3c0", "王审知", "fuzhou=福州:10[王审知 70 86, 王延翰 60 55, 张睦 30 78] quanzhou=泉州:6[王延彬 62 70]"),
 ("楚", "#b05cc8", "马殷", "changsha=潭州:14[马殷 80 86, 高郁 25 88, 许德勋 82 84, 秦彦晖 84 82] lingling=永州:5[] guiyang=郴州:5[李琼 86 78] guilin=桂州:7[姚彦章 80 82]"),
 ("雷彦恭", "", "雷彦恭", "wuling=朗州:6[雷彦恭 74 62]"),
 ("荆南", "#9bbf3a", "高季兴", "jiangling=江陵:9[高季兴 76 80, 倪可福 80 76, 梁震 25 86]"),
 ("清海", "#d9b520", "刘隐", "nanhai=广州:14[刘隐 72 84, 刘岩 76 82, 苏章 84 80, 梁克贞 80 76] gaoliang=高州:5[] zhuya=琼州:3[] yongzhou=邕州:5[叶广略 70 66]"),
 ("静海", "", "曲颢", "jiaozhi=大罗:9[曲颢 62 78, 曲承美 60 60, 杨廷艺 84 82, 矫公羡 78 66] jiuzhen=爱州:5[]"),
 ("燕", "#f0f0f0", "刘守光", "ji=幽州:16[刘守光 72 60, 元行钦 90 76, 单廷珪 88 70, 赵德钧 78 76, 李小喜 60 50] beiping=平州:6[] nanpi=沧州:9[刘守文 68 70, 孙鹤 30 80]"),
 ("赵", "#9ad0e0", "王镕", "zhongshan=镇州:11[王镕 40 62, 王德明 82 74, 符习 78 78]"),
 ("定难", "", "李思谏", "xiazhou=夏州:9[李思谏 74 76, 李仁福 78 78, 李彝昌 66 60]"),
 ("契丹", "#7fa0c8", "耶律阿保机", "linhuang=龙化州:18[耶律阿保机 90 96, 耶律曷鲁 88 90, 萧敌鲁 90 84, 述律平 70 88, 韩延徽 25 90, 耶律剌葛 80 66] liucheng=营州:7[耶律迭剌 72 70]"),
 ("渤海", "#6b7fd6", "大諲譔", "shangjing=上京:12[大諲譔 55 66, 大光显 72 72, 申德 76 72] fuyu=扶余府:7[] xiangping=辽东:7[] guonei=西京:6[大素贤 62 66]"),
 ("泰封", "#8a1f5c", "弓裔", "songak=铁原:12[弓裔 78 78, 高丽王建 86 96, 洪儒 82 78, 裴玄庆 84 76, 申崇谦 90 80, 卜智谦 80 76] pyongyang=浿西:6[庾黔弼 90 88] hanseong=汉州:6[]"),
 ("后百济", "#6b8e23", "甄萱", "wansan=完山:11[甄萱 90 88, 神剑 76 66, 朴英规 78 74, 能奂 60 76] sabi=熊州:5[]"),
 ("新罗", "#2f5fd0", "孝恭王", "gyeongju=金城:8[孝恭王 40 55, 朴景晖 66 70] gimhae=金海:4[金仁匡 68 64]"),
 ("日本", "#f0a0a0", "醍醐天皇", "yamato=平安京:12[醍醐天皇 30 72, 藤原时平 45 82, 藤原忠平 40 86, 藤原利仁 88 80, 纪贯之 20 60] dazaifu=大宰府:7[小野好古 76 80] izumo=出云:4[] kanto=武藏:7[平高望 80 78, 平良将 84 76, 藤原秀乡 92 84] mutsu=多贺城:5[]"),
 ("大长和", "#a08f70", "郑买嗣", "dali=阳苴咩:11[郑买嗣 70 78, 郑仁旻 72 70, 杨干贞 80 74, 赵善政 60 72] kunming=拓东:6[] yongchang=永昌:5[] jianning=石城:5[]"),
 ("甘州回鹘", "", "仁美可汗", "zhangye=甘州:9[仁美可汗 78 78, 狄银 80 70]"),
 ("归义军", "", "张承奉", "dunhuang=沙州:7[张承奉 66 66, 罗通达 78 74, 曹议金 70 84]"),
 ("六谷部", "", "折逋嘉施", "wuwei=凉州:7[折逋嘉施 74 70]"),
 ("吐蕃", "#7a5a2a", "贝考赞", "lhasa=逻些:7[贝考赞 68 66] xiping=鄯州:5[]"),
 ("占城", "", "跋陀罗跋摩", "linyi=因陀罗补罗:9[跋陀罗跋摩 76 76, 因陀罗跋摩 72 72] vijaya=佛逝:6[]"),
 ("高棉", "#c8a070", "耶输跋摩", "angkor=吴哥:14[耶输跋摩 88 90, 曷利沙跋摩 72 70, 伊奢那跋摩 70 68] tangming=文单:5[] funan=水真腊:6[]"),
 ("罗斛", "", "罗斛王", "dvaravati=罗斛:7[罗斛王 68 66]"),
 ("蒲甘", "", "蒲甘王", "pagan=蒲甘:7[蒲甘王 72 68]"),
 ("勃固", "", "孟王", "pegu=勃固:6[孟王 66 64]"),
 ("单马令", "", "单马令王", "panpan=单马令:5[单马令王 62 60]"),
 ]))


# 后续登场的人物： 年份 姓名 势力(可空) 城址 武力 统率。势力已亡或留空时，投奔该城址当时的主人。
LATER = {
"zhanguo": """
-290 蔺相如 赵 ye 30 88; -285 平原君赵胜 赵 ye 40 80; -280 鲁仲连 齐 beihai 40 82; -275 春申君黄歇 楚 shouchun 45 86
-275 晋鄙 魏 chenliu 82 80; -270 信陵君魏无忌 魏 chenliu 70 97; -270 范雎 秦 changan 30 92; -268 李牧 赵 pingcheng 92 97
-265 蒙骜 秦 changan 82 86; -262 赵括 赵 ye 70 55; -260 王翦 秦 changan 88 98; -255 吕不韦 秦 changan 30 90
-255 庞煖 赵 ye 76 90; -250 项燕 楚 shouchun 90 92; -250 韩非 韩 xuchang 20 80; -245 嬴政 秦 changan 70 99
-245 李斯 秦 changan 25 88; -240 蒙恬 秦 changan 86 92; -240 王贲 秦 changan 88 90; -240 太子丹 燕 ji 50 60
-235 李信 秦 changan 86 78; -235 荆轲 燕 ji 88 40
""",
"sanguo": """
191 荀彧 曹操 chenliu 30 96; 191 陈宫 曹操 puyang 40 88; 192 许褚 曹操 chenliu 96 65; 192 程昱 曹操 puyang 40 88
196 郭嘉 曹操 chenliu 20 97; 198 鲁肃 孙坚 lujiang 55 94; 198 马岱 马腾 wuwei 82 74; 200 吕蒙 孙坚 changsha 84 92
200 孙权 孙坚 wu 65 88; 200 徐盛 孙坚 wu 86 84; 201 徐庶 刘备 xiangyang 65 88; 203 陆逊 孙坚 wu 70 97
204 凌统 孙坚 wu 85 76; 207 诸葛亮 刘备 xiangyang 30 100; 208 庞统 刘备 xiangyang 35 96; 208 司马懿 曹操 luoyang 60 99
209 魏延 刘备 changsha 92 82; 210 曹彰 曹操 chenliu 92 76; 211 法正 刘焉 chengdu 30 92; 219 关平 刘备 jiangling 82 76
220 关兴 刘备 chengdu 84 74; 220 张苞 刘备 chengdu 86 72; 225 邓艾 曹操 xuchang 85 94; 228 姜维 曹操 tianshui 88 92
""",
"suitang": """
618 李孝恭 李渊 changan 78 92; 618 李道宗 李渊 changan 84 88; 618 张士贵 李渊 luoyang 88 82; 619 侯君集 李渊 changan 82 86
620 杜如晦 李渊 changan 20 94; 620 长孙无忌 李渊 changan 40 85; 621 房玄龄 李渊 changan 25 96; 630 松赞干布 吐蕃 lhasa 78 95
632 契苾何力 李渊 wuwei 90 84; 635 阿史那社尔 李渊 yunzhong 88 86; 640 杨万春 高句丽 xiangping 88 92
645 薛仁贵 李渊 anyi 97 86; 645 王玄策 李渊 luoyang 70 88; 645 中大兄皇子 倭 yamato 70 86; 645 中臣镰足 倭 yamato 40 92
650 裴行俭 李渊 changan 80 95; 650 金法敏 新罗 gyeongju 70 86; 655 刘仁轨 李渊 chenliu 70 94; 655 黑齿常之 百济 sabi 92 88
655 阿倍比罗夫 倭 kanto 86 80
""",
"wudai": """
910 郭崇韬 晋 jinyang 40 92; 910 夏鲁奇 晋 jinyang 92 78; 912 石敬瑭 晋 jinyang 86 84; 915 刘知远 晋 jinyang 88 82
915 高行周 晋 ji 88 82; 915 孟知祥 晋 jinyang 76 88; 918 耶律倍 契丹 linhuang 70 76; 920 耶律德光 契丹 linhuang 84 90
920 吴权 静海 jiaozhi 90 90; 925 郭威 晋 ye 88 92; 930 平将门 日本 kanto 94 82; 930 段思平 大长和 dali 86 92
930 马希范 楚 changsha 60 66; 935 藤原纯友 日本 dazaifu 86 78; 935 源经基 日本 yamato 78 76; 940 柴荣 - ye 86 97
945 丁部领 静海 jiaozhi 88 90; 948 赵匡胤 - chenliu 92 98; 950 杨业 - jinyang 96 88; 950 石守信 - chenliu 84 82
950 赵普 - chenliu 30 96; 952 潘美 - chenliu 84 88; 952 曹彬 - chenliu 82 92
""",
}


# ───────────── 西扩：西域、漠北、中亚、印度、波斯、中东 ─────────────
SITES.update({
 # 西域与漠北
 "hami": (93.5, 42.8), "turpan": (89.2, 42.9), "beiting": (89.2, 44.2), "yanqi": (86.6, 42.0), "kucha": (83.0, 41.7),
 "kashgar": (76.0, 39.5), "yarkand": (77.2, 38.2), "khotan": (79.9, 37.1), "loulan": (89.0, 39.4), "ili": (81.3, 43.9),
 "suyab": (75.3, 42.8), "jinshan": (88.2, 46.2), "mobei": (103.0, 45.6), "juyan": (101.0, 42.0), "zhangzhung": (80.4, 31.4),
 # 中亚
 "talas": (71.4, 42.9), "tashkent": (69.3, 41.3), "fergana": (72.0, 40.4), "samarkand": (67.0, 39.6), "bukhara": (64.4, 39.8),
 "khwarezm": (60.4, 42.0), "merv": (61.8, 37.6), "balkh": (66.9, 36.8), "herat": (62.2, 34.3), "kabul": (69.2, 34.5),
 "kandahar": (65.7, 31.6), "zaranj": (61.9, 31.0),
 # 印度
 "purushapura": (71.8, 33.9), "kashmir": (74.8, 34.1), "sakala": (74.4, 31.8), "multan": (71.5, 30.2), "sindh": (68.5, 25.6),
 "mathura": (77.6, 27.6), "kannauj": (80.2, 26.9), "pataliputra": (85.1, 25.6), "gauda": (88.1, 23.6), "ujjain": (75.8, 23.2),
 "gujarat": (72.6, 22.0), "pratishthana": (75.6, 19.3), "kalinga": (85.6, 20.4), "vengi": (80.9, 16.6), "badami": (75.7, 15.8),
 "kanchi": (79.5, 12.6), "madurai": (78.0, 9.9), "lanka": (80.6, 7.9), "kamarupa": (91.7, 26.2), "nepal": (85.3, 27.7),
 # 波斯与高加索
 "nishapur": (58.2, 36.3), "rayy": (51.6, 35.5), "hamadan": (48.5, 34.8), "isfahan": (51.9, 32.6), "persepolis": (52.9, 29.8),
 "kerman": (57.1, 30.3), "susa": (48.4, 32.0), "ctesiphon": (44.5, 33.1), "basra": (47.6, 30.6), "mosul": (43.3, 36.3),
 "tabriz": (46.5, 38.0), "armenia": (44.4, 40.1), "iberia": (44.9, 41.8), "alan": (43.6, 43.9), "khazar": (46.0, 45.8),
 # 中东
 "edessa": (38.9, 37.1), "antioch": (36.3, 36.2), "palmyra": (38.4, 34.6), "damascus": (36.4, 33.4), "jerusalem": (35.3, 31.7),
 "petra": (35.6, 30.2), "egypt": (31.0, 30.3), "thebes": (32.7, 25.8), "medina": (39.7, 24.6), "mecca": (40.0, 21.4),
 "sanaa": (44.4, 15.4), "axum": (38.7, 14.2), "oman": (57.0, 24.0), "gerrha": (49.5, 25.6),
 "caesarea": (35.5, 38.7), "ancyra": (32.9, 39.9), "sardis": (28.0, 38.3), "byzantium": (29.0, 41.1), "trebizond": (39.7, 40.9),
})

EDGES += """
dunhuang-hami dunhuang-loulan hami-turpan hami-beiting hami-juyan turpan-beiting turpan-yanqi turpan-loulan loulan-yanqi
loulan-khotan yanqi-kucha kucha-kashgar kucha-ili kucha-khotan kashgar-yarkand yarkand-khotan kashgar-fergana kashgar-suyab
yarkand-kashmir khotan-zhangzhung beiting-ili ili-suyab beiting-jinshan jinshan-mobei mobei-juyan juyan-zhangye
mobei-jiuyuan mobei-yunzhong mobei-linhuang zhangzhung-lhasa zhangzhung-kashmir nepal-lhasa
suyab-talas talas-tashkent tashkent-fergana tashkent-samarkand fergana-samarkand samarkand-bukhara samarkand-balkh
bukhara-khwarezm bukhara-merv khwarezm-merv khwarezm-khazar merv-balkh merv-herat merv-nishapur balkh-kabul balkh-herat
herat-nishapur herat-kandahar herat-zaranj kandahar-zaranj kandahar-kabul kabul-purushapura kandahar-multan
purushapura-kashmir purushapura-sakala kashmir-sakala sakala-multan sakala-mathura multan-sindh sindh-gujarat
mathura-kannauj mathura-ujjain kannauj-ujjain kannauj-pataliputra kannauj-nepal pataliputra-nepal pataliputra-gauda
pataliputra-kalinga gauda-kalinga gauda-kamarupa kamarupa-pagan kamarupa-pyu kamarupa-yongchang gauda-pegu gauda-pyu
ujjain-gujarat ujjain-pratishthana gujarat-pratishthana pratishthana-badami pratishthana-vengi kalinga-vengi vengi-kanchi
badami-kanchi badami-madurai kanchi-madurai madurai-lanka kanchi-lanka sindh-oman
nishapur-rayy rayy-hamadan rayy-isfahan rayy-tabriz hamadan-isfahan hamadan-ctesiphon hamadan-tabriz hamadan-susa
isfahan-persepolis isfahan-susa persepolis-kerman persepolis-susa kerman-zaranj susa-basra basra-ctesiphon basra-gerrha
gerrha-oman ctesiphon-mosul mosul-tabriz mosul-edessa tabriz-armenia armenia-iberia armenia-trebizond armenia-caesarea
armenia-mosul iberia-alan alan-khazar iberia-trebizond edessa-antioch edessa-palmyra edessa-caesarea ctesiphon-palmyra
palmyra-damascus antioch-damascus damascus-jerusalem jerusalem-petra petra-medina jerusalem-egypt petra-egypt egypt-thebes
thebes-axum medina-mecca mecca-sanaa sanaa-axum sanaa-oman gerrha-medina antioch-caesarea caesarea-ancyra
caesarea-trebizond ancyra-byzantium ancyra-sardis sardis-byzantium persepolis-gerrha
"""

WEST = {}
WEST["zhanguo"] = dict(
 regions=[("西 域", 84.0, 40.3), ("塞 种", 77.5, 44.6), ("粟 特", 65.5, 40.9), ("大 夏", 66.0, 35.6), ("身 毒", 79.5, 24.4),
  ("波 斯", 53.5, 33.6), ("两 河", 43.6, 34.6), ("条 支", 37.6, 35.4), ("阿 拉 伯", 45.5, 22.5), ("埃 及", 29.6, 27.6),
  ("小 亚", 32.0, 38.6), ("漠 北", 100.0, 44.4), ("南 印 度", 77.4, 13.4)],
 extra={"匈奴": "mobei=龙城:8[] juyan=居延:5[]"},
 factions=[
 ("塞琉古", "#c9a227", "塞琉古", "ctesiphon=塞琉西亚:18[塞琉古 82 96, 帕特罗克勒斯 72 82] antioch=安条克:12[安条克一世 78 86] edessa=埃德萨:6[] mosul=阿尔贝拉:6[] palmyra=塔德莫:4[] hamadan=埃克巴坦那:10[尼卡诺尔 74 76] susa=苏萨:8[] basra=卡拉克斯:5[] isfahan=伽拜:6[] persepolis=波斯波利斯:9[佩乌塞斯塔斯 76 78] kerman=卡尔马尼亚:5[] rayy=剌伽:6[] nishapur=百门城:6[] merv=马尔吉亚那:6[] herat=阿里亚:5[] zaranj=德兰吉亚那:4[] balkh=巴克特拉:10[德摩达马斯 74 80] samarkand=马拉坎达:7[]"),
 ("托勒密", "#7a5c9e", "托勒密", "egypt=亚历山大:18[托勒密 78 94, 马加斯 72 74, 托勒密二世 50 84] thebes=底比斯:7[] jerusalem=耶路撒冷:6[] damascus=大马士革:7[]"),
 ("利西马科斯", "#5c8fa8", "利西马科斯", "byzantium=利西马基亚:12[利西马科斯 86 88, 阿加索克利斯 80 82] sardis=萨第斯:9[菲莱泰罗斯 50 82] ancyra=戈尔迪乌姆:6[]"),
 ("卡帕多细亚", "", "阿里阿拉特", "caesarea=马扎卡:7[阿里阿拉特 72 72]"),
 ("本都", "", "米特里达梯", "trebizond=特拉布宗:7[米特里达梯 76 82]"),
 ("亚美尼亚", "#b06a4a", "奥龙特斯", "armenia=阿尔马维尔:8[奥龙特斯 72 74]"),
 ("阿特罗帕特尼", "", "阿特罗帕特斯", "tabriz=甘扎克:7[阿特罗帕特斯 70 78]"),
 ("伊比利亚", "", "法尔纳瓦兹", "iberia=姆茨赫塔:6[法尔纳瓦兹 78 80]"),
 ("萨尔马提亚", "", "萨尔马特王", "khazar=塔奈斯:8[萨尔马特王 82 72] alan=奄蔡:6[]"),
 ("纳巴泰", "", "纳巴泰王", "petra=佩特拉:6[纳巴泰王 72 74]"),
 ("莱赫延", "", "莱赫延王", "medina=德丹:5[莱赫延王 68 66] mecca=麦加:3[]"),
 ("赛伯伊", "", "赛伯伊王", "sanaa=马里卜:7[赛伯伊王 66 72]"),
 ("格尔哈", "", "格尔哈王", "gerrha=格尔哈:5[格尔哈王 55 68] oman=马干:4[]"),
 ("达摩特", "", "达摩特王", "axum=耶哈:5[达摩特王 64 62]"),
 ("花剌子模", "", "法拉斯曼", "khwarezm=花剌子模:7[法拉斯曼 74 74]"),
 ("康居", "", "康居王", "tashkent=卑阗:8[康居王 78 72] bukhara=罽城:4[] talas=乐越匿:4[]"),
 ("大宛", "", "大宛王", "fergana=贵山:7[大宛王 72 72]"),
 ("塞种", "", "塞王", "suyab=塞地:9[塞王 84 76] ili=伊列:6[]"),
 ("呼揭", "", "呼揭王", "jinshan=金山:6[呼揭王 76 66] beiting=蒲类:4[]"),
 ("姑师", "", "姑师王", "turpan=交河:6[姑师王 68 64] hami=伊吾:3[]"),
 ("楼兰", "", "楼兰王", "loulan=楼兰:5[楼兰王 62 64]"),
 ("龟兹", "", "龟兹王", "kucha=龟兹:7[龟兹王 70 70] yanqi=焉耆:4[]"),
 ("疏勒", "", "疏勒王", "kashgar=疏勒:6[疏勒王 68 66] yarkand=莎车:4[]"),
 ("于阗", "", "于阗王", "khotan=于阗:6[于阗王 64 70]"),
 ("象雄", "", "象雄王", "zhangzhung=穹窿银城:5[象雄王 72 68]"),
 ("孔雀", "#2f9e8f", "旃陀罗笈多", "pataliputra=华氏城:20[旃陀罗笈多 86 97, 考底利耶 30 98, 宾头娑罗 74 84] kannauj=㤭赏弥:9[] mathura=秣菟罗:8[] ujjain=邬阇衍那:8[] sakala=奢羯罗:7[] purushapura=呾叉始罗:9[] multan=木尔坦:6[] sindh=帕塔拉:6[] kabul=高附:6[] kandahar=阿拉霍西亚:6[] gujarat=吉尔纳尔:6[] gauda=耽摩栗底:6[]"),
 ("羯陵伽", "", "羯陵伽王", "kalinga=陀娑离:10[羯陵伽王 80 80]"),
 ("案达罗", "", "案达罗王", "pratishthana=波提斯坦那:8[案达罗王 74 74] vengi=驮那羯磔迦:5[] badami=婆那婆私:4[]"),
 ("朱罗", "", "朱罗王", "kanchi=乌赖尤尔:7[朱罗王 76 72]"),
 ("潘地亚", "", "潘地亚王", "madurai=马杜赖:7[潘地亚王 72 74]"),
 ("僧伽罗", "", "天爱帝须", "lanka=阿努拉德普勒:6[天爱帝须 60 72]"),
 ("迦湿弥罗", "", "迦湿弥罗王", "kashmir=迦湿弥罗:5[迦湿弥罗王 66 66]"),
 ("基拉特", "", "基拉特王", "nepal=尼婆罗:5[基拉特王 72 66]"),
 ("东辉", "", "东辉王", "kamarupa=东辉:5[东辉王 68 64]"),
 ],
 later="""
-298 梅伽斯梯尼 塞琉古 ctesiphon 30 78; -285 皮洛士 利西马科斯 byzantium 94 92; -280 安提柯二世 利西马科斯 byzantium 76 88
-275 阿育王 孔雀 pataliputra 84 97; -256 狄奥多图斯 塞琉古 balkh 78 86; -250 阿尔沙克 塞琉古 nishapur 86 88
-245 托勒密三世 托勒密 egypt 76 88; -240 安条克三世 塞琉古 antioch 82 92
""")

WEST["sanguo"] = dict(
 regions=[("西 域", 84.0, 40.3), ("乌 孙", 79.0, 45.0), ("康 居", 67.5, 41.6), ("贵 霜", 70.0, 32.6), ("天 竺", 80.0, 24.4),
  ("安 息", 54.0, 33.8), ("条 支", 44.0, 31.4), ("大 秦", 34.0, 35.0), ("阿 拉 伯", 45.5, 22.5), ("漠 北", 100.0, 44.4),
  ("南 天 竺", 77.4, 13.4), ("小 亚", 32.0, 38.6)],
 extra={"鲜卑": "mobei=漠北:8[] juyan=居延:4[]", "马腾": "zhangye=张掖:5[] dunhuang=敦煌:4[]"},
 factions=[
 ("罗马", "#a32a2a", "康茂德", "antioch=安条克:16[康茂德 62 50, 尼格尔 80 80, 佩蒂纳克斯 76 86] byzantium=拜占庭:10[塞维鲁 84 94] sardis=以弗所:8[] ancyra=安卡拉:6[] caesarea=凯撒利亚:8[阿尔拜努斯 80 78] trebizond=特拉布宗:6[] damascus=大马士革:8[] palmyra=帕尔米拉:6[] jerusalem=埃利亚:6[] petra=佩特拉:5[] egypt=亚历山大:14[莱图斯 70 76] thebes=底比斯:5[]"),
 ("奥斯若恩", "", "阿布加尔", "edessa=埃德萨:6[阿布加尔 62 72]"),
 ("安息", "#8a6d3b", "沃洛吉斯", "ctesiphon=泰西封:16[沃洛吉斯 74 82, 阿尔达班 78 80] mosul=阿尔贝拉:7[] hamadan=埃克巴坦那:9[] susa=苏萨:7[] basra=卡拉克斯:5[] isfahan=阿斯帕达纳:6[] rayy=剌伽:7[] nishapur=尼萨:7[] merv=木鹿:7[] herat=阿里亚:5[] zaranj=塞斯坦:5[] kerman=卡尔马尼亚:5[] tabriz=甘扎克:6[]"),
 ("波斯", "#7a3b8a", "帕帕克", "persepolis=伊什塔克尔:8[帕帕克 72 82, 沙普尔王子 74 72]"),
 ("亚美尼亚", "#b06a4a", "霍斯罗夫", "armenia=阿尔塔沙特:9[霍斯罗夫 78 80]"),
 ("伊比利亚", "", "阿玛扎斯普", "iberia=姆茨赫塔:6[阿玛扎斯普 80 72]"),
 ("阿兰", "", "阿兰王", "alan=阿兰:8[阿兰王 82 74] khazar=奄蔡:5[]"),
 ("阿克苏姆", "", "加达拉特", "axum=阿克苏姆:8[加达拉特 78 78]"),
 ("希木叶尔", "", "希木叶尔王", "sanaa=采法尔:7[希木叶尔王 72 74]"),
 ("朱尔胡姆", "", "朱尔胡姆酋长", "mecca=麦加:4[朱尔胡姆酋长 68 62] medina=叶斯里卜:4[]"),
 ("阿兹德", "", "阿兹德酋长", "oman=苏哈尔:5[阿兹德酋长 70 66] gerrha=哈萨:4[]"),
 ("贵霜", "#d0703a", "波调", "purushapura=富楼沙:16[波调 76 82, 迦腻色伽二世 80 80] kabul=迦毕试:8[] balkh=蓝氏城:9[] kandahar=阿拉霍西亚:5[] kashmir=迦湿弥罗:6[] sakala=奢羯罗:7[] multan=木尔坦:5[] mathura=秣菟罗:10[] kannauj=㤭赏弥:7[]"),
 ("康居", "", "康居王", "samarkand=康居:9[康居王 78 74] tashkent=卑阗:6[] bukhara=罽城:5[] talas=乐越匿:4[]"),
 ("大宛", "", "大宛王", "fergana=贵山:7[大宛王 72 72]"),
 ("花剌子模", "", "花剌子模王", "khwarezm=花剌子模:6[花剌子模王 72 72]"),
 ("乌孙", "", "乌孙昆弥", "suyab=赤谷:9[乌孙昆弥 80 76] ili=伊列:6[]"),
 ("坚昆", "", "坚昆王", "jinshan=坚昆:6[坚昆王 78 66]"),
 ("车师", "", "车师王", "turpan=交河:6[车师王 66 66] beiting=务涂谷:4[] hami=伊吾:3[]"),
 ("鄯善", "", "鄯善王", "loulan=扜泥:5[鄯善王 62 66]"),
 ("焉耆", "", "焉耆王", "yanqi=焉耆:5[焉耆王 70 64]"),
 ("龟兹", "", "白英", "kucha=龟兹:8[白英 68 72]"),
 ("疏勒", "", "和得", "kashgar=疏勒:6[和得 72 66] yarkand=莎车:4[]"),
 ("于阗", "", "尉迟安国", "khotan=于阗:6[尉迟安国 68 70]"),
 ("象雄", "", "象雄王", "zhangzhung=穹窿银城:5[象雄王 72 68]"),
 ("百乘", "#2f9e8f", "耶若室利", "pratishthana=波提斯坦那:12[耶若室利 82 86] vengi=驮那羯磔迦:7[] badami=婆那婆私:5[]"),
 ("西萨特拉普", "", "鲁陀罗僧诃", "ujjain=邬阇衍那:10[鲁陀罗僧诃 78 82] gujarat=婆卢羯车:7[] sindh=信度:5[]"),
 ("摩揭陀", "", "摩揭陀王", "pataliputra=华氏城:9[摩揭陀王 66 70] gauda=耽摩栗底:5[]"),
 ("羯陵伽", "", "羯陵伽王", "kalinga=陀娑离:6[羯陵伽王 74 72]"),
 ("朱罗", "", "卡里卡拉", "kanchi=乌赖尤尔:9[卡里卡拉 88 90]"),
 ("潘地亚", "", "尼顿杰利扬", "madurai=马杜赖:8[尼顿杰利扬 84 82]"),
 ("狮子国", "", "狮子国王", "lanka=阿努拉德普勒:6[狮子国王 64 68]"),
 ("离车", "", "离车王", "nepal=尼婆罗:5[离车王 70 70]"),
 ("迦摩缕波", "", "迦摩缕波王", "kamarupa=东辉:5[迦摩缕波王 68 64]"),
 ],
 later="""
193 卡拉卡拉 罗马 antioch 78 66; 205 阿尔达希尔 波斯 persepolis 90 97; 210 梯里达底 亚美尼亚 armenia 80 78
220 沙普尔 波斯 persepolis 86 95; 222 亚历山大·塞维鲁 罗马 antioch 55 72; 235 奥登纳图斯 罗马 palmyra 86 92
240 室利笈多 摩揭陀 pataliputra 76 84; 245 芝诺比娅 罗马 palmyra 60 90; 250 奥勒良 罗马 byzantium 90 95
""")

WEST["suitang"] = dict(
 regions=[("西 域", 84.0, 40.3), ("西 突 厥", 77.5, 44.8), ("昭 武 九 姓", 66.0, 41.2), ("吐 火 罗", 66.0, 35.6), ("五 天 竺", 80.0, 24.4),
  ("波 斯", 54.0, 33.8), ("大 食", 44.5, 23.5), ("拂 菻", 32.0, 38.6), ("可 萨", 44.6, 46.4), ("漠 北", 100.0, 44.4),
  ("南 天 竺", 77.4, 13.4), ("象 雄", 82.0, 32.6)],
 extra={"突厥": "mobei=牙帐:9[] juyan=居延:4[]", "李轨": "dunhuang=敦煌:4[]", "吐谷浑": "loulan=鄯善:4[]"},
 factions=[
 ("拜占庭", "#7a3b8a", "希拉克略", "byzantium=君士坦丁堡:18[希拉克略 84 95, 狄奥多尔 76 78, 菲利皮科斯 70 82] sardis=以弗所:8[] ancyra=安卡拉:7[] caesarea=凯撒利亚:8[] trebizond=特拉布宗:6[] egypt=亚历山大:10[尼基塔斯 76 80] thebes=底比斯:4[]"),
 ("萨珊", "#8a6d3b", "库思老", "ctesiphon=泰西封:20[库思老 70 80, 沙欣 84 88, 拉扎特斯 80 78] antioch=安条克:9[沙赫尔巴拉兹 90 93] damascus=大马士革:7[] jerusalem=耶路撒冷:6[] edessa=埃德萨:6[] palmyra=塔德莫:4[] mosul=尼尼微:7[] tabriz=甘扎克:7[] armenia=德温:6[] hamadan=哈马丹:8[] susa=贡德沙普尔:7[] basra=乌剌:5[] isfahan=伊斯法罕:8[] persepolis=伊什塔克尔:8[] kerman=克尔曼:5[] zaranj=锡斯坦:5[] rayy=剌伊:7[] nishapur=尼沙普尔:7[] merv=木鹿:7[] herat=赫拉特:5[] gerrha=哈萨:4[] oman=马宗:4[] sanaa=萨那:5[巴赞 70 72]"),
 ("加萨尼", "", "贾巴拉", "petra=波斯特拉:6[贾巴拉 76 74]"),
 ("古莱什", "#3d7a3d", "阿布·苏富扬", "mecca=麦加:7[阿布·苏富扬 62 78, 哈立德 95 97, 阿慕尔 78 92]"),
 ("叶斯里卜", "", "萨阿德", "medina=叶斯里卜:6[萨阿德 80 78]"),
 ("阿克苏姆", "", "阿尔马赫", "axum=阿克苏姆:7[阿尔马赫 66 74]"),
 ("伊比利亚", "", "斯蒂芬", "iberia=第比利斯:6[斯蒂芬 70 72]"),
 ("可萨", "", "可萨可汗", "khazar=阿得水:10[可萨可汗 82 80] alan=阿兰:6[]"),
 ("西突厥", "#4a6fa5", "射匮可汗", "suyab=碎叶:14[射匮可汗 84 86, 统叶护 88 92] talas=怛罗斯:6[] tashkent=石国:7[] fergana=拔汗那:6[] ili=弓月:7[阿史那泥孰 78 78] beiting=可汗浮图:6[]"),
 ("康国", "", "屈术支", "samarkand=康国:8[屈术支 66 72] bukhara=安国:6[]"),
 ("火寻", "", "火寻王", "khwarezm=火寻:6[火寻王 70 70]"),
 ("吐火罗", "", "吐火罗叶护", "balkh=缚喝:8[吐火罗叶护 76 74]"),
 ("迦毕试", "", "迦毕试王", "kabul=迦毕试:8[迦毕试王 74 76] purushapura=健驮逻:6[] kandahar=漕矩吒:5[]"),
 ("薛延陀", "", "乙失钵", "jinshan=燕末山:8[乙失钵 80 80]"),
 ("高昌", "#c08a5a", "麴伯雅", "turpan=高昌:8[麴伯雅 50 70, 麴文泰 62 64] hami=伊吾:4[]"),
 ("焉耆", "", "龙突骑支", "yanqi=焉耆:5[龙突骑支 68 64]"),
 ("龟兹", "", "苏伐勃驶", "kucha=龟兹:8[苏伐勃驶 68 70]"),
 ("疏勒", "", "裴阿摩支", "kashgar=疏勒:6[裴阿摩支 70 66] yarkand=朱俱波:4[]"),
 ("于阗", "", "尉迟屋密", "khotan=于阗:6[尉迟屋密 68 72]"),
 ("象雄", "", "李迷夏", "zhangzhung=穹窿银城:7[李迷夏 72 72]"),
 ("戒日", "#2f9e8f", "戒日王", "kannauj=曲女城:16[戒日王 84 93, 婆尼 78 82] mathura=秣菟罗:8[] sakala=阇烂达罗:7[] pataliputra=华氏城:8[]"),
 ("高达", "", "设赏迦", "gauda=金耳国:10[设赏迦 84 86]"),
 ("迦摩缕波", "", "拘摩罗", "kamarupa=迦摩缕波:7[拘摩罗 74 80]"),
 ("尼婆罗", "", "鸯输伐摩", "nepal=尼婆罗:6[鸯输伐摩 72 86]"),
 ("迦湿弥罗", "", "杜尔拉巴", "kashmir=迦湿弥罗:7[杜尔拉巴 72 80]"),
 ("信度", "", "罗伊·萨哈西", "sindh=阿罗尔:8[罗伊·萨哈西 66 72] multan=茂罗三部卢:6[]"),
 ("伐腊毗", "", "尸罗阿迭多", "gujarat=伐腊毗:8[尸罗阿迭多 70 76] ujjain=邬阇衍那:6[]"),
 ("遮娄其", "#b5523b", "补罗稽舍", "badami=婆陀比:14[补罗稽舍 88 94] pratishthana=摩诃剌侘:8[] vengi=文耆:7[毗湿奴伐弹那 78 80]"),
 ("恭御陀", "", "恭御陀王", "kalinga=恭御陀:6[恭御陀王 74 72]"),
 ("帕拉瓦", "", "摩哂陀跋摩", "kanchi=建志:10[摩哂陀跋摩 74 86]"),
 ("潘地亚", "", "潘地亚王", "madurai=马杜赖:7[潘地亚王 74 74]"),
 ("狮子国", "", "狮子国王", "lanka=阿努拉德普勒:6[狮子国王 64 68]"),
 ],
 later="""
622 耶兹底格德 萨珊 ctesiphon 55 66; 625 罗斯塔姆 萨珊 ctesiphon 88 90; 628 肆叶护 西突厥 suyab 80 78
630 那罗僧诃跋摩 帕拉瓦 kanchi 88 92; 632 查奇 信度 sindh 78 88; 633 穆阿维叶 古莱什 mecca 70 94
634 赛义德·瓦卡斯 古莱什 mecca 86 90; 635 夷男 薛延陀 jinshan 84 86; 640 君士坦斯 拜占庭 byzantium 70 80
642 阿罗那顺 戒日 kannauj 78 74; 650 阿史那贺鲁 西突厥 suyab 86 84; 655 卑路斯 萨珊 merv 66 70
""")

WEST["wudai"] = dict(
 regions=[("西 域", 84.0, 40.3), ("葛 逻 禄", 77.5, 44.8), ("河 中", 66.0, 41.2), ("呼 罗 珊", 60.5, 35.0), ("天 竺", 80.0, 24.4),
  ("波 斯", 53.5, 32.4), ("大 食", 44.5, 23.5), ("拂 菻", 32.0, 38.6), ("可 萨", 44.6, 46.4), ("漠 北", 100.0, 44.4),
  ("南 天 竺", 77.4, 13.4), ("埃 及", 29.6, 27.6)],
 extra={},
 factions=[
 ("拜占庭", "#7a3b8a", "利奥六世", "byzantium=君士坦丁堡:20[利奥六世 40 80, 安德罗尼卡·杜卡斯 84 86, 希梅里奥斯 72 84] sardis=以弗所:8[] ancyra=安卡拉:8[] caesarea=凯撒利亚:9[尼基弗鲁斯·福卡斯 82 86] trebizond=特拉布宗:6[]"),
 ("阿拔斯", "#3a3a3a", "穆克塔菲", "ctesiphon=巴格达:20[穆克塔菲 55 80, 穆尼斯 86 88, 侯赛因·哈姆丹 82 80] basra=巴士拉:8[] mosul=摩苏尔:8[] susa=阿瓦士:6[] hamadan=哈马丹:7[] isfahan=伊斯法罕:8[] persepolis=设拉子:8[] kerman=克尔曼:5[] edessa=鲁哈:6[] antioch=安条克:7[] palmyra=塔德莫:4[] damascus=大马士革:9[] jerusalem=耶路撒冷:6[] petra=艾莱:4[] egypt=亚历山大:8[] thebes=库斯:5[] medina=麦地那:5[] mecca=麦加:6[]"),
 ("萨曼", "#2f7a6a", "伊斯玛仪", "bukhara=布哈拉:16[伊斯玛仪 84 94, 艾哈迈德 74 78] samarkand=撒马尔罕:10[] tashkent=赭时:7[] fergana=拔汗那:6[] balkh=巴里黑:8[] merv=木鹿:8[] herat=赫拉特:6[] nishapur=尼沙普尔:9[] rayy=剌伊:7[]"),
 ("萨法尔", "", "塔希尔", "zaranj=锡斯坦:8[塔希尔 66 66, 阿慕尔·莱斯 78 76] kandahar=鲁赫吉:5[]"),
 ("花剌子模", "", "花剌子模沙", "khwarezm=柯提:7[花剌子模沙 70 74]"),
 ("萨吉", "", "优素福", "tabriz=阿尔达比勒:9[优素福 82 84]"),
 ("亚美尼亚", "#b06a4a", "森巴特", "armenia=阿尼:8[森巴特 72 78]"),
 ("伊比利亚", "", "阿达尔纳塞", "iberia=第比利斯:6[阿达尔纳塞 70 72]"),
 ("阿兰", "", "阿兰王", "alan=阿兰:7[阿兰王 80 74]"),
 ("可萨", "", "本雅明", "khazar=伊蒂尔:11[本雅明 78 80]"),
 ("卡尔马特", "", "阿布·赛义德", "gerrha=哈萨:8[阿布·赛义德 82 86]"),
 ("阿曼", "", "阿曼伊玛目", "oman=苏哈尔:6[阿曼伊玛目 66 72]"),
 ("雅法尔", "", "雅法尔埃米尔", "sanaa=萨那:6[雅法尔埃米尔 70 70]"),
 ("阿克苏姆", "", "阿克苏姆王", "axum=阿克苏姆:5[阿克苏姆王 64 66]"),
 ("喀喇汗", "#4a6fa5", "毗伽阙", "suyab=八剌沙衮:12[毗伽阙 80 82, 奥古尔恰克 82 78] talas=怛罗斯:6[] kashgar=喀什噶尔:8[] ili=阿力麻里:5[]"),
 ("高昌回鹘", "#c08a5a", "毗伽天王", "turpan=高昌:10[毗伽天王 78 82] beiting=北庭:7[] yanqi=焉耆:5[] kucha=龟兹:7[] hami=伊州:4[]"),
 ("于阗", "", "尉迟僧乌波", "khotan=于阗:8[尉迟僧乌波 66 72] yarkand=鸭儿看:4[]"),
 ("仲云", "", "仲云王", "loulan=大屯城:5[仲云王 74 62]"),
 ("黠戛斯", "", "黠戛斯可汗", "jinshan=剑河:8[黠戛斯可汗 82 76]"),
 ("阻卜", "", "阻卜酋长", "mobei=可敦城:9[阻卜酋长 82 72] juyan=黑水:4[]"),
 ("古格", "", "吉德尼玛衮", "zhangzhung=札布让:6[吉德尼玛衮 76 80]"),
 ("普腊蒂哈腊", "#2f9e8f", "摩哂陀罗波罗", "kannauj=曲女城:18[摩哂陀罗波罗 80 88, 博阇二世 72 70] mathura=秣菟罗:8[] ujjain=邬阇衍那:8[] gujarat=阿纳希拉:7[] pataliputra=华氏城:7[]"),
 ("波罗", "", "那罗衍那波罗", "gauda=高达:9[那罗衍那波罗 60 72]"),
 ("迦摩缕波", "", "迦摩缕波王", "kamarupa=哈鲁佩斯瓦拉:6[迦摩缕波王 70 68]"),
 ("尼婆罗", "", "尼婆罗王", "nepal=加德满都:5[尼婆罗王 68 70]"),
 ("迦湿弥罗", "", "帕尔塔", "kashmir=迦湿弥罗:7[帕尔塔 50 60, 苏甘达 45 76]"),
 ("沙希", "", "卡马卢卡", "purushapura=乌铎迦汉荼:9[卡马卢卡 80 80] kabul=喀布尔:6[] sakala=拉合尔:6[]"),
 ("木尔坦", "", "木纳比", "multan=木尔坦:7[木纳比 66 70]"),
 ("曼苏拉", "", "哈巴尔", "sindh=曼苏拉:7[哈巴尔 66 68]"),
 ("罗湿陀罗拘陀", "#b5523b", "克里希那", "pratishthana=曼尼亚凯塔:14[克里希那 76 80] badami=婆陀比:7[]"),
 ("东遮娄其", "", "毗摩", "vengi=文耆:8[毗摩 80 80]"),
 ("东恒伽", "", "东恒伽王", "kalinga=羯陵伽:6[东恒伽王 74 72]"),
 ("朱罗", "#c98a2a", "波兰多迦", "kanchi=坦贾武尔:12[波兰多迦 88 90]"),
 ("潘地亚", "", "罗阇辛哈", "madurai=马杜赖:7[罗阇辛哈 76 72]"),
 ("狮子国", "", "迦叶波", "lanka=阿努拉德普勒:6[迦叶波 66 72]"),
 ],
 later="""
910 穆克塔迪尔 阿拔斯 ctesiphon 40 55; 912 李圣天 于阗 khotan 74 84; 912 摩醯波罗 普腊蒂哈腊 kannauj 78 82
914 纳斯尔二世 萨曼 bukhara 66 86; 915 因陀罗三世 罗湿陀罗拘陀 pratishthana 88 90; 915 阿绍特 亚美尼亚 armenia 88 86
920 罗曼努斯 拜占庭 byzantium 70 88; 920 萨图克 喀喇汗 kashgar 86 90; 923 阿布·塔希尔 卡尔马特 gerrha 88 88
925 库尔库阿斯 拜占庭 caesarea 86 95; 930 马尔达维季 萨吉 rayy 86 84; 935 伊赫什德 阿拔斯 egypt 78 86
945 赛义夫·道莱 阿拔斯 mosul 86 86; 950 罗阇罗阇 朱罗 kanchi 90 96
""")

for _e in ERAS:
    _w = WEST[_e["id"]]
    _x = dict(_w["extra"])
    _e["factions"] = [(n, c, l, s + " " + _x.pop(n, "")) for (n, c, l, s) in _e["factions"]] + _w["factions"]
    assert not _x, _x
    _e["regions"] = list(_e["regions"]) + _w["regions"]
    LATER[_e["id"]] += _w["later"]



# ───────────── 加密：两河、叙利亚、尼罗河谷、小亚细亚、伊朗、河中、恒河与德干 ─────────────
SITES.update({
 "egypt": (30.0, 31.1),
 "babylon": (44.4, 32.3), "nisibis": (41.2, 37.1), "hatra": (42.9, 35.3), "aleppo": (37.2, 36.2), "emesa": (36.8, 34.8),
 "tyre": (35.4, 33.3), "gaza": (34.6, 31.5), "dura": (40.7, 34.6), "raqqa": (39.0, 35.9),
 "memphis": (31.3, 29.8), "pelusium": (32.5, 30.9), "hermopolis": (30.8, 27.8), "syene": (32.9, 24.1), "nubia": (31.0, 18.6),
 "pergamon": (27.3, 39.1), "iconium": (32.5, 37.9), "tarsus": (34.9, 37.0), "sinope": (35.1, 41.6), "melitene": (38.3, 38.4),
 "attalia": (30.8, 37.0), "karin": (41.3, 39.9), "albania": (47.2, 40.4), "derbent": (48.0, 42.1),
 "gorgan": (54.6, 37.0), "yazd": (54.4, 31.9), "hormuz": (56.5, 27.7), "siraf": (52.1, 28.5), "daylam": (49.8, 36.5),
 "kermanshah": (47.0, 34.3), "makran": (62.3, 26.3),
 "khujand": (69.7, 40.2), "nasaf": (65.8, 38.8), "chaghaniyan": (68.0, 38.2), "amul": (63.5, 39.0), "badakhshan": (70.6, 37.1),
 "bamiyan": (67.8, 34.8), "otrar": (68.3, 42.9), "aksu": (80.3, 41.2), "qiemo": (85.5, 38.1),
 "varanasi": (83.0, 25.3), "ayodhya": (82.2, 26.8), "delhi": (76.9, 29.6), "ajmer": (74.6, 26.4), "champa": (87.0, 25.2),
 "vanga": (90.4, 23.7), "nasik": (73.8, 20.0), "vidisha": (77.8, 23.5), "tripuri": (79.9, 23.2), "kosala": (82.2, 21.2),
 "kerala": (76.6, 10.4),
})
for _old, _new in [("jerusalem-egypt", "jerusalem-gaza"), ("petra-egypt", "petra-gaza"), ("egypt-thebes", "egypt-memphis"),
                   ("thebes-axum", "nubia-axum"), ("persepolis-gerrha", "siraf-gerrha")]:
    assert _old in EDGES.split(), _old
    EDGES = EDGES.replace(_old, _new)
EDGES += """
babylon-ctesiphon babylon-basra babylon-dura dura-palmyra dura-raqqa dura-hatra raqqa-edessa raqqa-aleppo raqqa-palmyra
aleppo-antioch aleppo-edessa aleppo-emesa emesa-damascus emesa-palmyra emesa-antioch emesa-tyre tyre-damascus
tyre-jerusalem gaza-pelusium nisibis-edessa nisibis-mosul nisibis-hatra hatra-mosul hatra-ctesiphon
pelusium-memphis pelusium-egypt memphis-hermopolis hermopolis-thebes thebes-syene syene-nubia
pergamon-sardis pergamon-byzantium iconium-ancyra iconium-caesarea iconium-attalia iconium-tarsus tarsus-antioch
tarsus-caesarea attalia-sardis sinope-ancyra sinope-trebizond melitene-caesarea melitene-edessa melitene-karin
karin-trebizond karin-armenia albania-armenia albania-iberia albania-tabriz albania-derbent derbent-khazar derbent-alan
gorgan-nishapur gorgan-rayy gorgan-khwarezm daylam-rayy daylam-tabriz daylam-hamadan kermanshah-hamadan
kermanshah-ctesiphon kermanshah-susa kermanshah-mosul yazd-isfahan yazd-kerman yazd-persepolis siraf-persepolis
siraf-hormuz hormuz-kerman hormuz-oman hormuz-makran makran-kerman makran-sindh
khujand-tashkent khujand-fergana khujand-samarkand nasaf-samarkand nasaf-bukhara nasaf-chaghaniyan nasaf-amul
chaghaniyan-balkh chaghaniyan-badakhshan chaghaniyan-samarkand amul-bukhara amul-merv amul-khwarezm
badakhshan-balkh badakhshan-yarkand badakhshan-kabul bamiyan-balkh bamiyan-kabul bamiyan-herat otrar-talas
otrar-tashkent otrar-khwarezm aksu-kucha aksu-kashgar aksu-suyab qiemo-loulan qiemo-khotan
varanasi-pataliputra varanasi-ayodhya varanasi-tripuri ayodhya-kannauj ayodhya-nepal delhi-sakala delhi-mathura
delhi-ajmer ajmer-mathura ajmer-ujjain ajmer-gujarat ajmer-multan champa-pataliputra champa-gauda vanga-gauda
vanga-kamarupa nasik-gujarat nasik-pratishthana nasik-ujjain vidisha-ujjain vidisha-mathura vidisha-tripuri
tripuri-kosala tripuri-kannauj kosala-kalinga kosala-vengi kerala-madurai kerala-badami
"""

DENSE = {}
DENSE["zhanguo"] = dict(extra={
 "塞琉古": "babylon=巴比伦:12[] nisibis=尼西比斯:5[] hatra=亚述:4[] aleppo=贝罗亚:6[] emesa=埃美萨:4[] dura=杜拉:4[] raqqa=尼基弗里昂:4[] tarsus=塔尔苏斯:5[] gorgan=赫卡尼亚:5[] yazd=伊萨提斯:4[] hormuz=哈尔莫齐亚:4[] siraf=塔奥刻:4[] daylam=卡斯比亚:4[] kermanshah=贝希斯敦:5[] khujand=绝域亚历山大:5[] nasaf=瑙塔卡:4[] chaghaniyan=帕莱塔卡:4[] amul=奥克苏斯渡:4[] badakhshan=阿伊哈努姆:6[]",
 "托勒密": "memphis=孟菲斯:9[] pelusium=培琉喜阿姆:5[] hermopolis=赫尔摩波利斯:4[] syene=赛伊尼:4[] gaza=加沙:5[] tyre=推罗:6[]",
 "利西马科斯": "pergamon=帕加马:6[] iconium=以哥念:4[] attalia=潘菲利亚:4[]",
 "本都": "sinope=锡诺普:5[]", "卡帕多细亚": "melitene=梅利泰内:4[]", "亚美尼亚": "karin=卡林:4[]",
 "孔雀": "makran=格德罗西亚:4[] bamiyan=梵衍那:4[] varanasi=波罗奈:8[] ayodhya=阿逾陀:6[] delhi=因陀罗普拉斯塔:6[] ajmer=布什卡尔:4[] champa=瞻波:6[] vidisha=毗底沙:6[] tripuri=支提:5[] nasik=那西克:4[]",
 "羯陵伽": "kosala=南憍萨罗:5[]", "康居": "otrar=奥特拉尔:4[]", "龟兹": "aksu=姑墨:4[]", "楼兰": "qiemo=且末:3[]",
 }, factions=[
 ("库施", "", "库施王", "nubia=纳帕塔:7[库施王 70 72]"),
 ("阿尔巴尼亚", "", "阿尔巴尼亚王", "albania=卡巴拉:5[阿尔巴尼亚王 70 68] derbent=乔拉:4[]"),
 ("鹏伽", "", "鹏伽王", "vanga=鹏伽:6[鹏伽王 70 68]"),
 ("哲罗", "", "哲罗王", "kerala=万吉:6[哲罗王 72 70]"),
 ])
DENSE["sanguo"] = dict(extra={
 "罗马": "aleppo=贝罗亚:6[] emesa=埃美萨:6[] tyre=推罗:6[] gaza=加沙:5[] raqqa=卡利尼库姆:5[] dura=杜拉:5[] memphis=孟菲斯:8[] pelusium=培琉喜阿姆:5[] hermopolis=赫尔摩波利斯:4[] syene=赛伊尼:5[] pergamon=帕加马:7[] iconium=以哥念:5[] tarsus=塔尔苏斯:6[] sinope=锡诺普:5[] melitene=梅利泰内:7[] attalia=阿塔利亚:4[]",
 "安息": "nisibis=尼西比斯:6[] babylon=巴比伦:8[] gorgan=赫卡尼亚:6[] yazd=伊萨提斯:4[] hormuz=哈尔莫齐亚:4[] daylam=卡斯比亚:4[] kermanshah=贝希斯敦:5[] makran=格德罗西亚:4[] amul=阿没:4[]",
 "波斯": "siraf=塔奥刻:4[]", "亚美尼亚": "karin=卡林:4[]",
 "贵霜": "bamiyan=梵衍那:5[] badakhshan=钵铎创那:4[] chaghaniyan=石汗那:5[] delhi=因陀罗普拉斯塔:6[] varanasi=波罗奈:6[] ayodhya=阿逾陀:5[]",
 "康居": "khujand=俱战提:4[] nasaf=那色波:4[] otrar=奥特拉尔:4[]", "龟兹": "aksu=姑墨:4[]", "鄯善": "qiemo=且末:3[]",
 "西萨特拉普": "ajmer=布什卡尔:4[] vidisha=毗底沙:6[]", "百乘": "nasik=那西克:6[]",
 "摩揭陀": "champa=瞻波:5[] tripuri=支提:5[]", "羯陵伽": "kosala=南憍萨罗:5[]",
 }, factions=[
 ("库施", "", "库施王", "nubia=纳帕塔:7[库施王 70 72]"),
 ("哈特拉", "", "桑纳特鲁克", "hatra=哈特拉:8[桑纳特鲁克 76 84]"),
 ("阿尔巴尼亚", "", "阿尔巴尼亚王", "albania=卡巴拉:6[阿尔巴尼亚王 70 68] derbent=乔拉:4[]"),
 ("鹏伽", "", "鹏伽王", "vanga=三摩呾吒:5[鹏伽王 70 68]"),
 ("哲罗", "", "哲罗王", "kerala=万吉:7[哲罗王 74 72]"),
 ])
DENSE["suitang"] = dict(extra={
 "萨珊": "babylon=希拉:6[] nisibis=尼西比斯:7[] hatra=提克里特:5[] aleppo=贝罗亚:6[] emesa=埃美萨:5[] tyre=推罗:5[] gaza=加沙:4[] dura=色尔克西昂:5[] raqqa=卡利尼库姆:5[] tarsus=塔尔苏斯:5[] gorgan=戈尔甘:6[] yazd=亚兹德:4[] hormuz=霍尔木兹:4[] siraf=西拉夫:5[] daylam=德莱木:4[] kermanshah=克尔曼沙赫:6[] makran=莫克兰:4[] amul=阿没:4[] albania=帕特瓦:5[] derbent=打耳班:6[]",
 "拜占庭": "memphis=孟菲斯:7[] pelusium=培琉喜阿姆:5[] hermopolis=赫尔摩波利斯:4[] syene=赛伊尼:4[] pergamon=帕加马:6[] iconium=以哥念:5[] sinope=锡诺普:5[] melitene=梅利泰内:6[] attalia=阿塔利亚:5[] karin=卡林:5[]",
 "西突厥": "otrar=讹答剌:4[] khujand=俱战提:4[]", "康国": "nasaf=那色波:4[]",
 "吐火罗": "chaghaniyan=石汗那:5[] badakhshan=钵铎创那:4[]", "迦毕试": "bamiyan=梵衍那:5[]",
 "龟兹": "aksu=拨换:4[]", "吐谷浑": "qiemo=且末:3[]",
 "戒日": "delhi=萨他泥湿伐罗:9[] ayodhya=阿逾陀:6[] varanasi=波罗奈:7[] vidisha=毗底沙:5[]",
 "高达": "champa=瞻波:5[] vanga=三摩呾吒:6[]", "遮娄其": "nasik=那西克:6[]", "恭御陀": "kosala=南憍萨罗:6[]",
 }, factions=[
 ("马库里亚", "", "马库里亚王", "nubia=栋古拉:7[马库里亚王 72 74]"),
 ("瞿折罗", "", "瞿折罗王", "ajmer=毗罗摩罗:7[瞿折罗王 76 76]"),
 ("羯罗朱利", "", "佛陀罗阇", "tripuri=底里补罗:6[佛陀罗阇 72 74]"),
 ("哲罗", "", "哲罗王", "kerala=万吉:6[哲罗王 72 70]"),
 ])
DENSE["wudai"] = dict(extra={
 "阿拔斯": "babylon=库法:7[] nisibis=纳西宾:5[] hatra=萨马拉:8[] aleppo=阿勒颇:7[] emesa=霍姆斯:5[] tyre=苏尔:5[] gaza=加沙:4[] dura=拉赫巴:4[] raqqa=拉卡:6[] tarsus=塔尔苏斯:7[] melitene=马拉蒂亚:6[] karin=卡利卡拉:4[] memphis=福斯塔特:12[] pelusium=法拉玛:4[] hermopolis=乌什穆奈因:4[] syene=阿斯旺:5[] kermanshah=基尔米辛:5[] yazd=亚兹德:4[] siraf=西拉夫:7[] hormuz=霍尔木兹:5[] makran=莫克兰:4[]",
 "拜占庭": "pergamon=帕加马:6[] iconium=以哥念:6[] sinope=锡诺普:5[] attalia=阿塔利亚:6[]",
 "萨吉": "albania=巴尔达:6[]",
 "萨曼": "gorgan=戈尔甘:6[] khujand=俱战提:5[] nasaf=那色波:5[] chaghaniyan=石汗那:5[] amul=阿穆勒:5[] badakhshan=巴达赫尚:4[] bamiyan=巴米扬:4[] otrar=讹答剌:4[]",
 "喀喇汗": "aksu=拨换:5[]", "于阗": "qiemo=且末:3[]",
 "普腊蒂哈腊": "delhi=迪利卡:6[] ayodhya=阿逾陀:5[] varanasi=波罗奈:6[] ajmer=阿杰梅尔:6[] vidisha=毗底沙:5[]",
 "波罗": "champa=瞻波:5[] vanga=毗诃罗补罗:5[]", "罗湿陀罗拘陀": "nasik=那西克:6[]", "东恒伽": "kosala=南憍萨罗:5[]",
 }, factions=[
 ("马库里亚", "", "乔治二世", "nubia=栋古拉:8[乔治二世 72 78]"),
 ("希尔万", "", "希尔万沙", "derbent=打耳班:6[希尔万沙 72 74]"),
 ("德莱木", "", "查斯坦", "daylam=鲁德巴尔:6[查斯坦 80 76]"),
 ("卡拉丘里", "", "商羯罗伽那", "tripuri=底里补罗:9[商羯罗伽那 78 78]"),
 ("哲罗", "", "哲罗王", "kerala=摩诃陀耶:7[哲罗王 72 72]"),
 ])

for _e in ERAS:
    _d = DENSE[_e["id"]]
    _x = dict(_d["extra"])
    _e["factions"] = [(n, c, l, s + " " + _x.pop(n, "")) for (n, c, l, s) in _e["factions"]] + _d["factions"]
    assert not _x, _x



# ───────────── 欧洲与北非 ─────────────
SITES.update({
 # 意大利与诸岛
 "rome": (12.5, 41.9), "capua": (14.3, 41.0), "tarentum": (17.2, 40.6), "syracuse": (15.1, 37.3), "panormus": (13.4, 37.9),
 "ravenna": (12.1, 44.3), "mediolanum": (9.2, 45.4), "arretium": (11.5, 43.5), "aquileia": (13.2, 45.9), "caralis": (9.1, 39.6),
 # 希腊与巴尔干
 "athens": (23.6, 38.1), "sparta": (22.5, 37.3), "thessalonica": (23.0, 40.8), "dyrrhachium": (19.9, 41.3), "ambracia": (21.1, 39.3),
 "larissa": (22.3, 39.7), "philippopolis": (24.8, 42.1), "serdica": (23.3, 42.8), "adrianople": (26.6, 41.7), "naissus": (21.9, 43.3),
 "singidunum": (20.5, 44.8), "salona": (16.8, 43.8), "odessos": (27.3, 43.2), "tomis": (28.0, 44.4), "knossos": (25.1, 35.25),
 # 多瑙河中游
 "aquincum": (19.0, 47.5), "vindobona": (16.5, 48.1), "sarmizegetusa": (22.9, 45.7), "augusta": (10.9, 48.3),
 # 高卢
 "lugdunum": (4.8, 45.7), "massilia": (5.5, 43.6), "narbo": (2.8, 43.5), "tolosa": (1.4, 43.7), "burdigala": (-0.5, 44.8),
 "lutetia": (2.3, 48.8), "reims": (4.1, 49.3), "treveri": (6.5, 49.7), "colonia": (7.0, 50.9), "argentorate": (7.8, 48.5),
 "rotomagus": (1.0, 49.3), "armorica": (-2.2, 48.0), "avaricum": (2.2, 47.4), "pictavium": (0.3, 46.5), "dijon": (4.9, 47.2),
 # 伊比利亚
 "tarraco": (1.3, 41.6), "caesaraugusta": (-0.9, 41.7), "toletum": (-4.0, 39.9), "corduba": (-4.8, 37.9), "hispalis": (-6.0, 37.5),
 "carthagonova": (-1.3, 38.0), "emerita": (-6.4, 38.9), "olisipo": (-8.9, 38.8), "bracara": (-8.3, 41.5), "legio": (-5.6, 42.6),
 "pompaelo": (-1.7, 42.8),
 # 不列颠与爱尔兰
 "londinium": (-0.1, 51.6), "eboracum": (-1.1, 54.0), "mercia": (-1.7, 52.7), "isca": (-3.5, 50.8), "venta": (-1.3, 51.1),
 "caledonia": (-3.5, 56.5), "gwynedd": (-3.9, 52.9), "tara": (-6.7, 53.6), "cashel": (-7.9, 52.5),
 # 日耳曼、斯拉夫与罗斯
 "saxony": (9.6, 52.4), "thuringia": (11.0, 51.0), "bohemia": (14.4, 50.1), "bavaria": (12.1, 49.0), "frisia": (5.3, 52.2),
 "hedeby": (9.5, 54.6), "zealand": (11.9, 55.5), "scania": (13.4, 56.0), "gniezno": (17.6, 52.5), "pomerania": (18.8, 53.9),
 "moravia": (17.3, 49.2), "krakow": (20.0, 50.1), "kiev": (30.5, 50.5), "smolensk": (32.0, 54.8), "polotsk": (28.8, 55.5),
 "bolghar": (49.1, 55.0), "murom": (42.0, 55.6), "rostov": (39.4, 57.1), "sarkel": (42.1, 47.7), "tmutarakan": (37.2, 45.9),
 "chersonesus": (34.4, 45.1), "olbia": (31.9, 47.0),
 # 北非
 "carthage": (10.0, 36.7), "hadrumetum": (10.0, 35.6), "cirta": (6.6, 36.3), "iol": (2.3, 36.3), "tahert": (1.3, 35.3),
 "tingis": (-5.6, 35.4), "volubilis": (-5.0, 34.0), "sijilmasa": (-4.3, 31.3), "aghmat": (-7.8, 31.4), "leptis": (13.8, 32.5),
 "cyrene": (21.8, 32.5), "garama": (13.0, 26.6), "siwa": (25.5, 29.2), "theveste": (8.1, 35.3), "ghana": (-8.0, 16.0),
})
EDGES += """
rome-capua rome-arretium rome-ravenna rome-caralis capua-tarentum capua-panormus tarentum-dyrrhachium tarentum-syracuse
syracuse-panormus panormus-carthage arretium-ravenna arretium-mediolanum ravenna-mediolanum ravenna-aquileia
mediolanum-aquileia mediolanum-lugdunum mediolanum-massilia mediolanum-augusta aquileia-salona aquileia-vindobona
caralis-carthage salona-dyrrhachium salona-singidunum dyrrhachium-thessalonica dyrrhachium-ambracia ambracia-larissa
ambracia-sparta larissa-thessalonica larissa-athens athens-sparta sparta-knossos knossos-cyrene knossos-egypt
athens-pergamon thessalonica-philippopolis thessalonica-adrianople thessalonica-naissus adrianople-byzantium
adrianople-philippopolis adrianople-odessos philippopolis-serdica serdica-naissus naissus-singidunum odessos-tomis
tomis-olbia tomis-sarmizegetusa singidunum-aquincum singidunum-sarmizegetusa aquincum-vindobona aquincum-sarmizegetusa
vindobona-augusta vindobona-moravia augusta-argentorate augusta-bavaria bavaria-vindobona bavaria-bohemia
massilia-narbo massilia-lugdunum narbo-tolosa narbo-tarraco tolosa-burdigala burdigala-pictavium pictavium-avaricum
pictavium-armorica avaricum-lutetia avaricum-dijon dijon-lugdunum dijon-reims dijon-argentorate lutetia-reims
lutetia-rotomagus rotomagus-armorica rotomagus-venta reims-treveri treveri-colonia treveri-argentorate colonia-frisia
colonia-saxony colonia-reims londinium-reims burdigala-pompaelo tolosa-avaricum
tarraco-caesaraugusta caesaraugusta-pompaelo caesaraugusta-toletum pompaelo-legio legio-bracara legio-toletum
bracara-olisipo olisipo-emerita emerita-toletum emerita-hispalis hispalis-corduba corduba-toletum corduba-carthagonova
carthagonova-tarraco hispalis-tingis
londinium-venta venta-isca londinium-mercia mercia-eboracum mercia-gwynedd eboracum-caledonia gwynedd-tara tara-cashel
caledonia-tara londinium-frisia isca-armorica
frisia-saxony saxony-thuringia saxony-hedeby hedeby-zealand zealand-scania thuringia-bohemia thuringia-bavaria
bohemia-moravia moravia-krakow moravia-aquincum krakow-gniezno gniezno-pomerania gniezno-bohemia gniezno-saxony
pomerania-scania pomerania-polotsk krakow-kiev polotsk-smolensk smolensk-kiev smolensk-rostov rostov-murom
murom-bolghar bolghar-khazar kiev-olbia kiev-sarkel sarkel-khazar sarkel-tmutarakan sarkel-alan tmutarakan-chersonesus
tmutarakan-alan chersonesus-olbia chersonesus-sinope
carthage-hadrumetum carthage-cirta hadrumetum-theveste hadrumetum-leptis theveste-cirta cirta-iol iol-tahert
tahert-volubilis volubilis-tingis volubilis-sijilmasa volubilis-aghmat aghmat-sijilmasa sijilmasa-ghana sijilmasa-tahert
iol-tingis garama-siwa cashel-isca leptis-garama leptis-cyrene cyrene-egypt cyrene-siwa siwa-memphis
"""

EUR_REGIONS = [("高 卢", 2.5, 46.4), ("伊 比 利 亚", -4.0, 40.8), ("日 耳 曼", 11.5, 53.2), ("不 列 颠", -1.8, 53.3),
 ("意 大 利", 12.8, 42.9), ("希 腊", 21.6, 38.6), ("色 雷 斯", 25.6, 42.6), ("潘 诺 尼 亚", 18.2, 46.4),
 ("北 非", 7.0, 33.6), ("利 比 亚", 18.0, 29.4), ("毛 里 塔 尼 亚", -5.5, 32.6), ("草 原", 36.0, 49.0)]

EUR = {}
EUR["zhanguo"] = dict(extra={
 "托勒密": "cyrene=昔兰尼:8[] siwa=阿蒙绿洲:3[]",
 "利西马科斯": "adrianople=乌斯库达玛:5[] odessos=奥德索斯:5[]",
 }, factions=[
 ("罗马", "#a32a2a", "库尔索尔", "rome=罗马:14[库尔索尔 84 90, 法比乌斯 82 90, 德西乌斯 80 82, 登塔图斯 82 86] capua=卡普阿:8[]"),
 ("伊特鲁里亚", "", "伊特鲁里亚王", "arretium=阿雷提乌姆:7[伊特鲁里亚王 66 70]"),
 ("塞农", "", "塞农王", "ravenna=塞纳加利卡:6[塞农王 80 70]"),
 ("因苏布雷", "", "因苏布雷王", "mediolanum=梅迪奥拉努姆:8[因苏布雷王 80 72]"),
 ("维内蒂", "", "维内蒂王", "aquileia=帕塔维乌姆:5[维内蒂王 68 66]"),
 ("塔兰托", "", "塔兰托执政", "tarentum=塔兰托:8[塔兰托执政 60 70]"),
 ("叙拉古", "#3a8fb5", "阿加托克利斯", "syracuse=叙拉古:14[阿加托克利斯 84 90]"),
 ("迦太基", "#6a3a8a", "汉诺", "carthage=迦太基:20[汉诺 70 80, 希米尔科 78 80, 马戈 76 78] hadrumetum=哈德鲁梅图姆:7[] panormus=帕诺尔莫斯:8[] caralis=卡拉利斯:6[] leptis=大莱普提斯:6[] carthagonova=马斯提亚:5[] hispalis=加地尔:6[]"),
 ("努米底亚", "", "努米底亚王", "cirta=锡尔塔:8[努米底亚王 78 74] theveste=特维斯特:4[] iol=伊奥尔:5[]"),
 ("毛里", "", "毛里王", "tingis=廷吉斯:5[毛里王 72 68] volubilis=沃卢比利斯:5[]"),
 ("加拉曼特", "", "加拉曼特王", "garama=加拉马:6[加拉曼特王 74 68]"),
 ("马其顿", "#2a4a8a", "卡山德", "thessalonica=佩拉:14[卡山德 78 88, 菲利普四世 60 62] larissa=拉里萨:7[]"),
 ("雅典", "", "奥林匹奥多罗斯", "athens=雅典:9[奥林匹奥多罗斯 76 80]"),
 ("斯巴达", "", "阿瑞乌斯", "sparta=斯巴达:8[阿瑞乌斯 78 76]"),
 ("伊庇鲁斯", "", "尼奥普托列墨斯", "ambracia=安布拉基亚:8[尼奥普托列墨斯 70 70] dyrrhachium=埃皮达姆诺斯:5[]"),
 ("克里特", "", "克里特首领", "knossos=克诺索斯:5[克里特首领 72 66]"),
 ("奥德里西亚", "", "塞乌西斯", "philippopolis=塞乌索波利斯:7[塞乌西斯 78 78] serdica=塞尔迪卡:4[]"),
 ("盖塔", "", "德罗米凯特斯", "sarmizegetusa=盖塔:7[德罗米凯特斯 80 82] tomis=希斯特里亚:5[]"),
 ("伊利里亚", "", "格劳基亚斯", "salona=萨罗纳:6[格劳基亚斯 78 80]"),
 ("特里巴利", "", "特里巴利王", "naissus=纳伊苏斯:5[特里巴利王 76 68] singidunum=辛吉敦:5[]"),
 ("潘诺尼", "", "潘诺尼王", "aquincum=阿昆库姆:5[潘诺尼王 72 66]"),
 ("博伊", "", "博伊王", "bohemia=博伊哈艾姆:6[博伊王 78 70] vindobona=诺里库姆:5[] bavaria=曼兴:5[] moravia=博伊边地:4[]"),
 ("赫尔维蒂", "", "赫尔维蒂王", "augusta=文德利基:4[赫尔维蒂王 76 70] argentorate=阿根托拉特:4[]"),
 ("阿维尔尼", "", "阿维尔尼王", "avaricum=阿瓦里库姆:8[阿维尔尼王 80 74] pictavium=皮克塔维:5[]"),
 ("埃杜伊", "", "埃杜伊王", "dijon=比布拉克特:7[埃杜伊王 76 72] lugdunum=卢格杜努姆:5[]"),
 ("马萨利亚", "", "马萨利亚执政", "massilia=马萨利亚:8[马萨利亚执政 60 72]"),
 ("沃尔卡", "", "沃尔卡王", "tolosa=托洛萨:6[沃尔卡王 76 68] narbo=纳尔博:5[]"),
 ("阿奎塔尼", "", "阿奎塔尼王", "burdigala=布尔迪加拉:5[阿奎塔尼王 74 66]"),
 ("贝尔盖", "", "贝尔盖王", "reims=杜罗科尔托鲁姆:7[贝尔盖王 82 72] lutetia=卢泰西亚:5[] treveri=特雷维里:5[] rotomagus=罗托马古斯:4[]"),
 ("阿摩里卡", "", "阿摩里卡王", "armorica=达里奥里图姆:5[阿摩里卡王 72 66]"),
 ("苏维汇", "", "苏维汇王", "saxony=切鲁西:6[苏维汇王 82 72] colonia=乌比:5[] thuringia=赫蒙杜里:5[]"),
 ("弗里西", "", "弗里西王", "frisia=弗里西:4[弗里西王 70 64]"),
 ("辛布里", "", "辛布里王", "hedeby=辛布里:6[辛布里王 84 72] zealand=条顿:4[]"),
 ("苏约内", "", "苏约内王", "scania=斯堪的亚:4[苏约内王 76 66]"),
 ("维内德", "", "维内德王", "gniezno=卢吉:5[维内德王 72 64] pomerania=维内德:4[] krakow=科蒂尼:4[]"),
 ("斯基泰", "", "斯基泰王", "sarkel=王族斯基泰:7[斯基泰王 82 76] olbia=奥尔比亚:5[] kiev=盖洛诺斯:5[]"),
 ("博斯普鲁斯", "", "斯巴托库斯", "tmutarakan=潘提卡彭:8[斯巴托库斯 70 76] chersonesus=克森尼索:5[]"),
 ("凯尔特伊比利亚", "", "凯尔特伊比利亚王", "toletum=托莱图姆:5[凯尔特伊比利亚王 80 72] caesaraugusta=萨尔杜巴:5[] legio=瓦凯伊:4[]"),
 ("卢西塔尼亚", "", "卢西塔尼亚王", "emerita=卢西塔尼亚:5[卢西塔尼亚王 80 72] olisipo=奥利西波:5[] bracara=加莱基:4[]"),
 ("图尔德塔尼", "", "图尔德塔尼王", "corduba=科尔杜巴:6[图尔德塔尼王 68 68]"),
 ("伊莱尔格特", "", "伊莱尔格特王", "tarraco=凯塞:5[伊莱尔格特王 74 68] pompaelo=瓦斯科内斯:4[]"),
 ("卡图维劳尼", "", "卡图维劳尼王", "londinium=韦鲁拉米恩:5[卡图维劳尼王 78 70] venta=阿特雷巴特:4[]"),
 ("布里甘特", "", "布里甘特王", "eboracum=布里甘提亚:5[布里甘特王 78 68] mercia=科里塔尼:4[]"),
 ("杜姆诺尼", "", "杜姆诺尼王", "isca=杜姆诺尼亚:4[杜姆诺尼王 70 64]"),
 ("奥陶维斯", "", "奥陶维斯王", "gwynedd=奥陶维斯:4[奥陶维斯王 76 64]"),
 ("喀里多尼亚", "", "喀里多尼亚王", "caledonia=喀里多尼亚:5[喀里多尼亚王 80 66]"),
 ("埃林", "", "埃林至高王", "tara=塔拉:5[埃林至高王 76 68] cashel=芒斯特:4[]"),
 ], later="""
-280 雷古卢斯 罗马 rome 78 84; -275 哈米尔卡 迦太基 carthage 88 94; -272 希伦 叙拉古 syracuse 76 88
-250 汉尼拔 迦太基 carthage 96 100; -245 哈斯德鲁巴 迦太基 carthage 84 88; -240 费边 罗马 rome 70 94
-240 马塞勒斯 罗马 rome 90 88; -238 西庇阿 罗马 rome 88 99; -240 马西尼萨 努米底亚 cirta 86 88
-235 腓力五世 马其顿 thessalonica 80 84
""")

EUR["sanguo"] = dict(extra={
 "罗马": "rome=罗马:20[康茂德 62 50, 朱利安努斯 50 55] capua=卡普阿:5[] tarentum=塔兰托:4[] syracuse=叙拉古:5[] panormus=帕诺尔姆斯:4[] ravenna=拉文纳:6[] mediolanum=梅迪奥拉努姆:7[] arretium=佛罗伦提亚:4[] aquileia=阿奎莱亚:7[] caralis=卡拉利斯:4[] athens=雅典:5[] sparta=科林斯:4[] thessalonica=塞萨洛尼卡:6[] dyrrhachium=都拉基乌姆:4[] ambracia=尼科波利斯:4[] larissa=拉里萨:4[] philippopolis=菲利普波利斯:5[] serdica=塞尔迪卡:5[] adrianople=哈德良堡:5[] naissus=纳伊苏斯:5[] singidunum=辛吉敦:8[] salona=萨罗纳:5[] odessos=马尔西安堡:6[] tomis=托米斯:6[] knossos=戈尔廷:4[] aquincum=阿昆库姆:9[] vindobona=卡农图姆:9[] sarmizegetusa=萨尔米泽格图萨:8[] augusta=奥古斯塔:6[] lugdunum=卢格杜努姆:8[] massilia=马萨利亚:5[] narbo=纳尔博:5[] tolosa=托洛萨:4[] burdigala=布尔迪加拉:4[] lutetia=卢泰西亚:4[] reims=杜罗科尔托鲁姆:5[] treveri=特雷维里:7[] colonia=科隆尼亚:9[] argentorate=阿根托拉特:8[] rotomagus=罗托马古斯:4[] armorica=孔达特:4[] avaricum=阿瓦里库姆:4[] pictavium=利摩努姆:4[] dijon=奥古斯托杜努姆:5[] tarraco=塔拉科:6[] caesaraugusta=凯撒奥古斯塔:4[] toletum=托莱图姆:4[] corduba=科尔杜巴:5[] hispalis=希斯帕利斯:5[] carthagonova=新迦太基:5[] emerita=埃梅里塔:5[] olisipo=奥利西波:4[] bracara=布拉卡拉:4[] legio=莱吉奥:6[] pompaelo=庞培洛:4[] londinium=伦蒂尼恩:7[] eboracum=埃博拉库姆:9[] mercia=林杜姆:5[] isca=伊斯卡:5[] venta=文塔:4[] gwynedd=德瓦:7[] carthage=迦太基:10[] hadrumetum=哈德鲁梅图姆:5[] cirta=锡尔塔:5[] iol=约尔:5[] tingis=廷吉斯:5[] volubilis=沃卢比利斯:5[] leptis=大莱普提斯:6[] cyrene=昔兰尼:5[] theveste=兰拜西斯:8[] siwa=阿蒙绿洲:3[]",
 }, factions=[
 ("博斯普鲁斯", "", "萨乌罗马特斯", "tmutarakan=潘提卡彭:7[萨乌罗马特斯 72 76] chersonesus=克森尼索:5[] olbia=奥尔比亚:4[]"),
 ("喀里多尼亚", "", "阿根托科克苏斯", "caledonia=喀里多尼亚:7[阿根托科克苏斯 80 70]"),
 ("希伯尼亚", "", "孔恩", "tara=塔拉:6[孔恩 84 76] cashel=芒斯特:4[]"),
 ("卡蒂", "", "卡蒂王", "thuringia=卡蒂:7[卡蒂王 80 70] bavaria=赫蒙杜里:5[]"),
 ("萨克森", "", "萨克森王", "saxony=萨克森:6[萨克森王 78 68] hedeby=盎格鲁:5[]"),
 ("弗里西", "", "弗里西王", "frisia=弗里西:4[弗里西王 70 64]"),
 ("马科曼尼", "", "巴洛马尔", "bohemia=马科曼尼:8[巴洛马尔 82 78] moravia=夸迪:6[]"),
 ("哥特", "", "菲利莫尔", "pomerania=哥提斯坎扎:7[菲利莫尔 84 76]"),
 ("汪达尔", "", "汪达尔王", "gniezno=汪达尔:5[汪达尔王 80 70] krakow=卢吉:4[]"),
 ("苏约内", "", "苏约内王", "scania=斯堪的亚:4[苏约内王 76 66] zealand=赫鲁利:4[]"),
 ("维内德", "", "维内德王", "kiev=维内德:5[维内德王 70 62]"),
 ("罗克索拉尼", "", "罗克索拉尼王", "sarkel=罗克索拉尼:7[罗克索拉尼王 82 72]"),
 ("加拉曼特", "", "加拉曼特王", "garama=加拉马:6[加拉曼特王 74 68]"),
 ], later="""
211 盖塔帝 罗马 rome 50 55; 218 埃拉伽巴路斯 罗马 rome 30 30; 235 马克西米努斯 罗马 colonia 94 76
250 克尼瓦 哥特 pomerania 86 88; 253 加里恩努斯 罗马 rome 76 82; 260 波斯图穆斯 罗马 colonia 82 86
268 克劳狄二世 罗马 naissus 86 88
""")

EUR["suitang"] = dict(extra={
 "拜占庭": "thessalonica=塞萨洛尼基:9[] athens=雅典:5[] sparta=科林斯:5[] adrianople=哈德良堡:7[] odessos=奥德索斯:5[] tomis=小斯基提亚:4[] philippopolis=菲利普波利斯:5[] serdica=塞尔迪卡:5[] dyrrhachium=都拉基乌姆:5[] ambracia=尼科波利斯:4[] larissa=拉里萨:4[] knossos=戈尔廷:4[] salona=萨罗纳:5[] ravenna=拉文纳:9[埃莱夫塞里奥斯 72 70] rome=罗马:7[] capua=那不勒斯:6[] tarentum=塔兰托:5[] syracuse=叙拉古:7[] panormus=巴勒莫:5[] caralis=卡拉利斯:4[] carthage=迦太基:10[格里高利 72 78] hadrumetum=哈德鲁梅图姆:5[] cirta=君士坦丁娜:5[] iol=约尔:4[] leptis=的黎波里:4[] cyrene=昔兰尼:4[] siwa=阿蒙绿洲:3[] carthagonova=卡塔赫纳:5[] tingis=塞普特姆:4[] chersonesus=克尔松:5[]",
 }, factions=[
 ("伦巴第", "#3a7a4a", "阿达洛尔德", "mediolanum=帕维亚:10[阿达洛尔德 50 60, 阿里奥尔德 78 78] aquileia=弗留利:6[] arretium=斯波莱托:6[]"),
 ("法兰克", "#3a5aa8", "克洛泰尔", "lutetia=巴黎:12[克洛泰尔 76 84, 丕平 70 84, 阿努尔夫 60 82] reims=兰斯:7[] treveri=梅斯:9[] colonia=科隆:7[] argentorate=斯特拉斯堡:5[] rotomagus=鲁昂:5[] avaricum=奥尔良:7[] pictavium=普瓦捷:6[] dijon=第戎:6[] lugdunum=里昂:7[] massilia=马赛:6[] tolosa=图卢兹:6[] burdigala=波尔多:6[] thuringia=图林根:5[] bavaria=雷根斯堡:6[] augusta=阿勒曼尼亚:5[]"),
 ("西哥特", "#b5762a", "西塞布特", "toletum=托莱多:12[西塞布特 78 86, 苏因提拉 84 84] narbo=纳博讷:6[] tarraco=塔拉戈纳:6[] caesaraugusta=萨拉戈萨:6[] corduba=科尔多瓦:7[] hispalis=塞维利亚:7[] emerita=梅里达:6[] olisipo=里斯本:4[] bracara=布拉加:5[] legio=莱昂:4[]"),
 ("巴斯克", "", "巴斯克首领", "pompaelo=潘普洛纳:5[巴斯克首领 76 66]"),
 ("布列塔尼", "", "朱迪卡埃尔", "armorica=瓦讷:5[朱迪卡埃尔 76 74]"),
 ("诺森布里亚", "", "埃德温", "eboracum=约克:8[埃德温 80 84]"),
 ("麦西亚", "", "切尔", "mercia=塔姆沃思:6[切尔 70 70]"),
 ("肯特", "", "伊德鲍尔德", "londinium=坎特伯雷:6[伊德鲍尔德 60 66]"),
 ("威塞克斯", "", "基内吉尔斯", "venta=温切斯特:6[基内吉尔斯 74 72]"),
 ("杜姆诺尼亚", "", "杜姆诺尼亚王", "isca=埃克塞特:4[杜姆诺尼亚王 70 64]"),
 ("格温内斯", "", "卡德凡", "gwynedd=格温内斯:5[卡德凡 70 70]"),
 ("皮克特", "", "皮克特王", "caledonia=福特里乌:5[皮克特王 78 68]"),
 ("乌伊尼尔", "", "苏布内", "tara=塔拉:6[苏布内 74 70]"),
 ("芒斯特", "", "芒斯特王", "cashel=卡舍尔:5[芒斯特王 72 66]"),
 ("萨克森", "", "萨克森公", "saxony=萨克森:6[萨克森公 78 68]"),
 ("弗里西亚", "", "弗里西亚王", "frisia=多雷斯塔德:5[弗里西亚王 72 66]"),
 ("丹麦", "", "丹麦王", "hedeby=海泽比:5[丹麦王 78 70] zealand=莱尔:5[] scania=乌珀克拉:4[]"),
 ("阿瓦尔", "#7a5a2a", "阿瓦尔可汗", "aquincum=阿瓦尔汗帐:12[阿瓦尔可汗 84 82] vindobona=卡农图姆:5[] singidunum=辛吉敦:6[] sarmizegetusa=格皮德:5[] naissus=纳伊苏斯:5[]"),
 ("斯拉夫", "", "德尔万", "bohemia=波希米亚:6[德尔万 72 70] moravia=摩拉维亚:5[] krakow=维斯瓦:4[] gniezno=波兰尼:4[] pomerania=波美拉尼亚:4[]"),
 ("安特", "", "安特首领", "kiev=基辅:5[安特首领 74 66]"),
 ("保加尔", "", "库布拉特", "tmutarakan=法纳戈里亚:8[库布拉特 84 86] sarkel=顿河:5[] olbia=第聂伯:4[]"),
 ("奥雷斯", "", "奥雷斯王", "theveste=奥雷斯:5[奥雷斯王 78 72]"),
 ("阿尔塔瓦", "", "阿尔塔瓦王", "tahert=阿尔塔瓦:5[阿尔塔瓦王 74 68]"),
 ("奥雷巴", "", "奥雷巴首领", "volubilis=瓦利拉:5[奥雷巴首领 76 66]"),
 ("桑哈贾", "", "桑哈贾首领", "sijilmasa=塔菲拉勒特:4[桑哈贾首领 78 66]"),
 ("加拉曼特", "", "加拉曼特王", "garama=加拉马:5[加拉曼特王 74 68]"),
 ("加纳", "", "加纳王", "ghana=昆比:6[加纳王 74 72]"),
 ], later="""
623 萨莫 斯拉夫 bohemia 80 84; 623 达戈贝尔特 法兰克 lutetia 78 86; 625 卡德瓦隆 格温内斯 gwynedd 84 78
626 彭达 麦西亚 mercia 88 82; 634 奥斯瓦尔德 诺森布里亚 eboracum 80 82; 636 罗塔里 伦巴第 mediolanum 80 84
642 辛达斯文特 西哥特 toletum 76 84; 650 阿斯巴鲁赫 保加尔 tmutarakan 82 84
""")

EUR["wudai"] = dict(extra={
 "拜占庭": "thessalonica=塞萨洛尼基:9[] athens=雅典:5[] sparta=科林斯:5[] adrianople=哈德良堡:8[] dyrrhachium=都拉基乌姆:6[] ambracia=尼科波利斯:5[] larissa=拉里萨:5[] tarentum=巴里:6[] chersonesus=克尔松:5[]",
 "阿拔斯": "cyrene=巴尔卡:5[] siwa=锡瓦:3[]",
 "可萨": "sarkel=萨克尔:6[] tmutarakan=塔曼:5[]",
 }, factions=[
 ("克里特酋长国", "", "克里特埃米尔", "knossos=汉达克斯:6[克里特埃米尔 78 72]"),
 ("保加利亚", "#5a8a3a", "西美昂", "odessos=普雷斯拉夫:14[西美昂 84 94, 狄奥多尔·西格里察 78 80] philippopolis=普罗夫迪夫:6[] serdica=斯雷德茨:7[] naissus=尼什:5[] singidunum=贝尔格莱德:5[] tomis=多罗斯托隆:6[] sarmizegetusa=特兰西瓦尼亚:4[]"),
 ("马扎尔", "#8a5a2a", "阿尔帕德", "aquincum=匈牙利:12[阿尔帕德 86 86, 佐尔坦 70 70, 布尔丘 84 76] moravia=尼特拉:5[]"),
 ("克罗地亚", "", "穆蒂米尔", "salona=尼恩:6[穆蒂米尔 70 72]"),
 ("意大利", "#3a7a4a", "贝伦加尔", "mediolanum=帕维亚:10[贝伦加尔 76 74] ravenna=拉文纳:5[] arretium=托斯卡纳:6[阿达尔贝特 74 72]"),
 ("威尼斯", "", "特里布诺", "aquileia=威尼斯:6[特里布诺 60 78]"),
 ("教皇国", "#e6d9a0", "塞尔吉乌斯", "rome=罗马:7[塞尔吉乌斯 40 66, 狄奥菲拉克特 66 76]"),
 ("贝内文托", "", "阿特努尔夫", "capua=卡普阿:7[阿特努尔夫 76 78]"),
 ("阿格拉布", "#2a6a4a", "齐亚达特", "hadrumetum=凯鲁万:14[齐亚达特 50 55, 伊布拉欣 76 74] carthage=突尼斯:7[] panormus=巴勒莫:8[] syracuse=叙拉古:5[] leptis=的黎波里:5[] theveste=泰贝萨:4[] cirta=君士坦丁:5[]"),
 ("撒丁", "", "撒丁判官", "caralis=卡利亚里:4[撒丁判官 66 66]"),
 ("鲁斯塔姆", "", "叶格赞", "tahert=塔赫特:8[叶格赞 60 70] iol=阿尔及尔:4[]"),
 ("伊德里斯", "", "叶海亚", "volubilis=非斯:9[叶海亚 64 70] tingis=丹吉尔:5[]"),
 ("米德拉尔", "", "米德拉尔埃米尔", "sijilmasa=西吉尔马萨:7[米德拉尔埃米尔 70 70]"),
 ("马斯穆达", "", "马斯穆达首领", "aghmat=阿格马特:5[马斯穆达首领 76 66]"),
 ("加纳", "", "加纳王", "ghana=昆比萨利赫:8[加纳王 76 76]"),
 ("哈塔布", "", "哈塔布埃米尔", "garama=泽维拉:5[哈塔布埃米尔 68 68]"),
 ("后倭马亚", "#e8e8e8", "阿卜杜拉", "corduba=科尔多瓦:16[阿卜杜拉 60 66, 巴德尔 76 80] hispalis=塞维利亚:8[] toletum=托莱多:8[] emerita=梅里达:6[] caesaraugusta=萨拉戈萨:7[] carthagonova=穆尔西亚:6[] olisipo=里斯本:5[]"),
 ("巴塞罗那", "", "威尔弗雷德", "tarraco=巴塞罗那:6[威尔弗雷德 72 72]"),
 ("阿斯图里亚斯", "", "阿方索三世", "legio=奥维耶多:9[阿方索三世 80 86] bracara=波尔图:5[]"),
 ("纳瓦拉", "", "桑乔", "pompaelo=潘普洛纳:6[桑乔 82 82]"),
 ("西法兰克", "#3a5aa8", "查理三世", "reims=兰斯:8[查理三世 60 70] lutetia=巴黎:9[罗贝尔 84 82] rotomagus=鲁昂:5[] avaricum=奥尔良:6[] pictavium=普瓦捷:7[埃布勒 74 72] tolosa=图卢兹:6[] burdigala=波尔多:5[] narbo=纳博讷:5[] dijon=第戎:6[理查 82 80]"),
 ("布列塔尼", "", "古尔马埃隆", "armorica=雷恩:5[古尔马埃隆 74 70]"),
 ("勃艮第", "", "鲁道夫", "lugdunum=维埃纳:7[鲁道夫 74 76] massilia=阿尔勒:6[盲者路易 60 66]"),
 ("东法兰克", "#c8a020", "孩童路易", "bavaria=雷根斯堡:9[孩童路易 30 40, 哈托 40 86, 阿努尔夫公 84 80] colonia=科隆:7[] treveri=梅斯:7[] argentorate=斯特拉斯堡:5[] augusta=奥格斯堡:6[] saxony=萨克森:8[奥托公 78 84] thuringia=爱尔福特:5[康拉德 76 76] frisia=乌得勒支:5[] vindobona=东方边区:5[]"),
 ("波希米亚", "", "斯皮季赫涅夫", "bohemia=布拉格:7[斯皮季赫涅夫 72 74]"),
 ("波兰尼", "", "莱斯特克", "gniezno=格涅兹诺:6[莱斯特克 74 72] krakow=维斯瓦兰:5[]"),
 ("波美拉尼亚", "", "波美拉尼亚公", "pomerania=沃林:5[波美拉尼亚公 72 66]"),
 ("丹麦", "", "哈德克努特", "hedeby=海泽比:7[哈德克努特 78 74] zealand=莱尔:6[] scania=隆德:5[]"),
 ("威塞克斯", "#b02a2a", "长者爱德华", "venta=温切斯特:9[长者爱德华 84 88] londinium=伦敦:7[] isca=埃克塞特:5[]"),
 ("麦西亚", "", "埃塞尔雷德", "mercia=塔姆沃思:7[埃塞尔雷德 74 76, 埃塞尔弗莱德 70 88]"),
 ("约维克", "", "哈夫丹", "eboracum=约维克:8[哈夫丹 82 72]"),
 ("格温内斯", "", "阿纳劳德", "gwynedd=格温内斯:5[阿纳劳德 76 76]"),
 ("阿尔巴", "", "君士坦丁二世", "caledonia=斯昆:7[君士坦丁二世 78 82]"),
 ("爱尔兰", "", "弗兰", "tara=塔拉:7[弗兰 80 80]"),
 ("芒斯特", "", "科马克", "cashel=卡舍尔:5[科马克 60 78]"),
 ("罗斯", "#8a2a2a", "奥列格", "kiev=基辅:12[奥列格 86 90, 伊戈尔 76 74] smolensk=斯摩棱斯克:6[] polotsk=波洛茨克:5[] rostov=罗斯托夫:5[] murom=穆罗姆:4[]"),
 ("伏尔加保加利亚", "", "阿尔米什", "bolghar=保加尔:8[阿尔米什 76 80]"),
 ("佩切涅格", "", "佩切涅格可汗", "olbia=第聂伯:7[佩切涅格可汗 84 76]"),
 ], later="""
909 阿布·阿卜杜拉 阿格拉布 hadrumetum 86 90; 910 托米斯拉夫 克罗地亚 salona 82 84; 910 奥多尼奥 阿斯图里亚斯 legio 82 80
911 罗洛 西法兰克 rotomagus 90 84; 912 阿卜杜·拉赫曼 后倭马亚 corduba 80 96; 912 捕鸟者亨利 东法兰克 saxony 86 92
921 瓦茨拉夫 波希米亚 bohemia 70 80; 924 埃塞尔斯坦 威塞克斯 venta 88 92; 932 阿尔贝里克 教皇国 rome 78 80
936 奥托一世 东法兰克 saxony 84 94; 936 老戈姆 丹麦 hedeby 76 78; 945 奥丽加 罗斯 kiev 50 88
955 蓝牙哈拉尔 丹麦 hedeby 82 86; 958 斯维亚托斯拉夫 罗斯 kiev 94 88; 958 梅什科 波兰尼 gniezno 82 88
""")

for _e in ERAS:
    _d = EUR[_e["id"]]
    _x = dict(_d["extra"])
    _e["factions"] = [(n, c, l, s + " " + _x.pop(n, "")) for (n, c, l, s) in _e["factions"]] + _d["factions"]
    assert not _x, _x
    _e["regions"] = list(_e["regions"]) + EUR_REGIONS
    LATER[_e["id"]] += _d["later"]
# 皮洛士是伊庇鲁斯人；罗马皇帝坐镇罗马
LATER["zhanguo"] = LATER["zhanguo"].replace("皮洛士 利西马科斯 byzantium", "皮洛士 伊庇鲁斯 ambracia")
for _e in ERAS:
    if _e["id"] == "sanguo":
        _f = []
        for (n, c, l, s) in _e["factions"]:
            if n == "罗马":
                assert "antioch=安条克:16[康茂德 62 50, " in s
                s = s.replace("antioch=安条克:16[康茂德 62 50, ", "antioch=安条克:16[")
            _f.append((n, c, l, s))
        _e["factions"] = _f



def auto_color(i):
    h = (i * 0.618034) % 1.0
    r, g, b = colorsys.hsv_to_rgb(h, 0.42, 0.72)
    return "#%02x%02x%02x" % (int(r * 255), int(g * 255), int(b * 255))


def build(era):
    factions, cities, gens, site_name = [], [], [], {}
    errs = []
    for i, (fname, col, lord, spec) in enumerate(era["factions"]):
        factions.append([fname, col or auto_color(i), lord])
        found_lord = False
        for m in re.finditer(r"(\w+)=([^:\s]+):(\d+)\[([^\]]*)\]", spec):
            site, cname, k, gl = m.group(1), m.group(2), int(m.group(3)), m.group(4)
            if site not in SITES:
                errs.append("未知城址 %s" % site)
                continue
            if site in site_name:
                errs.append("城址重复 %s (%s / %s)" % (site, site_name[site], cname))
            site_name[site] = cname
            lon, lat = SITES[site]
            cities.append([cname, lon, lat, fname, k])
            for g in [x.strip() for x in gl.split(",") if x.strip()]:
                parts = g.split()
                if len(parts) != 3:
                    errs.append("武将格式 %s" % g)
                    continue
                gens.append([parts[0], fname, cname, int(parts[1]), int(parts[2])])
                found_lord |= parts[0] == lord
        if not found_lord:
            errs.append("%s 缺君主 %s" % (fname, lord))
    for lst, what in [([c[0] for c in cities], "城名"), ([g[0] for g in gens], "武将"), ([f[0] for f in factions], "势力")]:
        dup = {x for x in lst if lst.count(x) > 1}
        if dup:
            errs.append("%s重复 %s" % (what, dup))
    edges, seen = [], set()
    for e in EDGES.split():
        a, b = e.split("-")
        for s in (a, b):
            if s not in SITES:
                errs.append("道路用到未知城址 %s" % s)
        key = tuple(sorted((a, b)))
        if a in site_name and b in site_name and key not in seen:
            seen.add(key)
            edges.append([site_name[a], site_name[b]])
    # 连通性
    adj = {c[0]: set() for c in cities}
    for a, b in edges:
        adj[a].add(b); adj[b].add(a)
    start = cities[0][0]
    todo, done = [start], {start}
    while todo:
        for n in adj[todo.pop()]:
            if n not in done:
                done.add(n); todo.append(n)
    if len(done) != len(cities):
        errs.append("不连通：%s" % sorted(set(adj) - done))
    lonely = [c for c in adj if len(adj[c]) < 2]
    later = []
    names = {g[0] for g in gens}
    fnames = {f[0] for f in factions}
    for ent in LATER[era["id"]].replace("\n", ";").split(";"):
        p = ent.split()
        if not p:
            continue
        if len(p) != 6 or p[3] not in SITES or p[1] in names or (p[2] != "-" and p[2] not in fnames):
            errs.append("后续人物有误 %s" % ent)
            continue
        names.add(p[1])
        later.append([int(p[0]), p[1], "" if p[2] == "-" else p[2], site_name.get(p[3], ""), int(p[4]), int(p[5])])
    return dict(name=era["name"], label=era["label"], year=era["year"], month=era["month"], intro=era["intro"],
                factions=factions, cities=cities, edges=edges, generals=gens,
                regions=[list(r) for r in era["regions"]], later=later), errs, lonely


def main():
    out = ["extends RefCounted", "# 由 tools/gen_scenarios.py 生成，请改那个脚本而不是这里。", "",
           "const ORDER := %s" % json.dumps([e["id"] for e in ERAS]), "", "const ERAS := {"]
    bad = False
    for era in ERAS:
        data, errs, lonely = build(era)
        print("%s：%d 势力 %d 城 %d 路 %d 将；只有一条路的城 %s" % (era["id"], len(data["factions"]), len(data["cities"]), len(data["edges"]), len(data["generals"]), lonely))
        for e in errs:
            bad = True
            print("  错误：", e)
        out.append("\t%s: %s," % (json.dumps(era["id"]), json.dumps(data, ensure_ascii=False)))
    out.append("}")
    if bad:
        sys.exit(1)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "Scenarios.gd")
    open(path, "w").write("\n".join(out) + "\n")

main()
