import Foundation
// 每行一个汉字串 → 每个字的无调拼音，空格分隔
while let line = readLine() {
    var out: [String] = []
    for ch in line {
        let m = NSMutableString(string: String(ch))
        CFStringTransform(m, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(m, nil, kCFStringTransformStripDiacritics, false)
        out.append(m as String)
    }
    print(out.joined(separator: " "))
}
