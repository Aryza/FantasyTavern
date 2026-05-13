import Foundation
import CoreServices

public final class FolderWatcher {
    public let url: URL
    public let debounce: TimeInterval
    private let onChange: (URL) -> Void

    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "FolderWatcher.\(UUID().uuidString)")

    public init(url: URL, debounce: TimeInterval = 0.25, onChange: @escaping (URL) -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() throws {
        stop()
        let paths = [url.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags: UInt32 = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.schedule()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        ) else {
            throw NSError(domain: "FolderWatcher", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "FSEventStreamCreate failed"])
        }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
    }

    private func schedule() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onChange(self.url)
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    deinit { stop() }
}
