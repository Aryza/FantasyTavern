import XCTest
@testable import WorldStore

final class CalendarTests: XCTestCase {
    func test_emptyJSON_emptyEras() {
        let cal = WorldCalendar.load(from: nil)
        XCTAssertEqual(cal.eras, [])
        XCTAssertNil(cal.yearZeroLabel)
    }

    func test_loadsEras() throws {
        let data = """
        {
          "calendar": {
            "yearZeroLabel": "AE",
            "eras": [
              { "id":"first-age",  "name":"First Age",  "start":-2000, "end": 0 },
              { "id":"second-age", "name":"Second Age", "start": 0,    "end": 1500 }
            ]
          }
        }
        """.data(using: .utf8)!
        let cal = WorldCalendar.load(from: data)
        XCTAssertEqual(cal.yearZeroLabel, "AE")
        XCTAssertEqual(cal.eras.map(\.id), ["first-age", "second-age"])
        XCTAssertEqual(cal.eras.first?.end, 0)
    }
}
