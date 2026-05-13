import Foundation

public enum ZipError: Error {
    case zipFailed(Int32, String)
    case unzipFailed(Int32, String)
    case archiveMissing(URL)
}

public enum Zip {
    public static func create(folder: URL, to archive: URL, exclude: [String] = []) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        var args = ["-r", "-q", archive.path, "."]
        for pattern in exclude {
            args.append(contentsOf: ["-x", pattern])
        }
        proc.arguments = args
        proc.currentDirectoryURL = folder
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ZipError.zipFailed(proc.terminationStatus, msg)
        }
    }

    public static func extract(archive: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: archive.path) else {
            throw ZipError.archiveMissing(archive)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", "-o", archive.path, "-d", destination.path]
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ZipError.unzipFailed(proc.terminationStatus, msg)
        }
    }
}
