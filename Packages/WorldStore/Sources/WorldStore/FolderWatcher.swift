import Foundation

public final class FolderWatcher {
    public let url: URL
    public let debounce: TimeInterval
    private let onChange: (URL) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "FolderWatcher.\(UUID().uuidString)")

    public init(url: URL, debounce: TimeInterval = 0.25, onChange: @escaping (URL) -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() throws {
        stop()
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { throw NSError(domain: "FolderWatcher", code: Int(errno)) }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.schedule() }
        src.setCancelHandler { [weak self] in
            if let f = self?.fd, f >= 0 { close(f); self?.fd = -1 }
        }
        src.resume()
        source = src
    }

    public func stop() {
        source?.cancel()
        source = nil
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
