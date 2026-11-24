import Foundation

@main struct RegionTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); print("PASS " + message)
    }
    static func main() throws {
        let tableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let names = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: tableURL))
        check(DYPublicationRegion.name(for: "440300") == "广东·深圳市", "bundled resource loads")
        check(names.count > 3000, "bundled table has domestic coverage")
        for (code, expected) in [("440300", "广东·深圳市"), ("110101", "北京市"), ("710000", "台湾"), ("810000", "香港特别行政区")] {
            check(DYPublicationRegion.name(for: code, country: nil, names: names) == expected, "maps " + code)
        }
        for (code, country) in [("0", ""), ("000000", "CN"), ("2197820", "FJ"), ("1859171", "JP"), ("440300", "US"), ("４４０３００", "CN"), ("999999", "CN"), (" 440300", "CN")] {
            check(DYPublicationRegion.name(for: code, country: country, names: names) == nil, "rejects " + code + "/" + country)
        }
        check(DYPublicationRegion.metadata("刚刚发布 · AI 声明", place: nil) == "刚刚发布 · AI 声明", "missing region preserves existing text")
        check(DYPublicationRegion.metadata(nil, place: nil) == nil, "missing metadata stays hidden")
        check(DYPublicationRegion.metadata("刚刚发布", place: "广东·深圳市") == "刚刚发布 · 发布地：广东·深圳市", "region follows original text")
        check(DYPublicationRegion.metadata(nil, place: "广东·深圳市") == "发布地：广东·深圳市", "region without timestamp")
    }
}
