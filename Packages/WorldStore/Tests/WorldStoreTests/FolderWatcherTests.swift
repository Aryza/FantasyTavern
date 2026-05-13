import XCTest
@testable import WorldStore

final class FolderWatcherTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func test_writingFileFires() throws {
        let expectation = XCTestExpectation(description: "watcher fires")
        let watcher = FolderWatcher(url: tmp, debounce: 0.1) { _ in
            expectation.fulfill()
        }
        try watcher.start()
        // mutate the dir
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            try? "hi".write(to: self.tmp.appendingPathComponent("x.txt"),
                            atomically: true, encoding: .utf8)
        }
        wait(for: [expectation], timeout: 3.0)
        watcher.stop()
    }
}
