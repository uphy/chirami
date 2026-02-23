import Testing
@testable import Chirami

@Suite("DurationParser")
struct DurationParserTests {

    @Test("時間単位をパースする")
    func parseHours() {
        #expect(DurationParser.parse("2h") == 7200)
    }

    @Test("分単位をパースする")
    func parseMinutes() {
        #expect(DurationParser.parse("30m") == 1800)
    }

    @Test("ゼロをパースする")
    func parseZero() {
        #expect(DurationParser.parse("0") == 0)
    }

    @Test("nil は 0 を返す")
    func parseNil() {
        #expect(DurationParser.parse(nil) == 0)
    }

    @Test("空文字列は 0 を返す")
    func parseEmpty() {
        #expect(DurationParser.parse("") == 0)
    }

    @Test("不正な文字列は 0 を返す")
    func parseInvalid() {
        #expect(DurationParser.parse("abc") == 0)
    }

    @Test("1時間をパースする")
    func parseOneHour() {
        #expect(DurationParser.parse("1h") == 3600)
    }

    @Test("1分をパースする")
    func parseOneMinute() {
        #expect(DurationParser.parse("1m") == 60)
    }
}
