import Testing
@testable import Chirami

@Suite("DurationParser")
struct DurationParserTests {

    @Test("parses hours")
    func parseHours() {
        #expect(DurationParser.parse("2h") == 7200)
    }

    @Test("parses minutes")
    func parseMinutes() {
        #expect(DurationParser.parse("30m") == 1800)
    }

    @Test("parses zero")
    func parseZero() {
        #expect(DurationParser.parse("0") == 0)
    }

    @Test("returns 0 for nil")
    func parseNil() {
        #expect(DurationParser.parse(nil) == 0)
    }

    @Test("returns 0 for empty string")
    func parseEmpty() {
        #expect(DurationParser.parse("") == 0)
    }

    @Test("returns 0 for invalid string")
    func parseInvalid() {
        #expect(DurationParser.parse("abc") == 0)
    }

    @Test("parses one hour")
    func parseOneHour() {
        #expect(DurationParser.parse("1h") == 3600)
    }

    @Test("parses one minute")
    func parseOneMinute() {
        #expect(DurationParser.parse("1m") == 60)
    }
}
