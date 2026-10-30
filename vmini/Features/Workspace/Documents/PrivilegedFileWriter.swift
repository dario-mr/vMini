import AppKit
import Darwin

enum PrivilegedFileWriter {
    @MainActor private static var stagingDirectoryURL: URL?
    @MainActor private static var stagedURLsByDestination: [String: URL] = [:]
    @MainActor private static var scriptsByDestination: [String: NSAppleScript] = [:]

    @MainActor
    static func write(_ data: Data, to url: URL) throws {
        let destinationURL = url.standardizedFileURL
        try validate(destinationURL)

        let fileManager = FileManager.default
        let key = destinationURL.path
        let sourceURL = try stagedURL(for: key)
        guard fileManager.createFile(
            atPath: sourceURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? fileManager.removeItem(at: sourceURL) }

        let script = try authorizationScript(for: key, from: sourceURL, to: destinationURL)
        var scriptError: NSDictionary?
        _ = script.executeAndReturnError(&scriptError)
        if let scriptError {
            let errorNumber = scriptError["NSAppleScriptErrorNumber"] as? Int ?? 1
            if errorNumber == -128 {
                throw CocoaError(.userCancelled)
            }
            throw NSError(
                domain: "NSAppleScriptErrorDomain",
                code: errorNumber,
                userInfo: [NSLocalizedDescriptionKey: scriptError["NSAppleScriptErrorMessage"] as? String ?? "Authorization failed."]
            )
        }
    }

    @MainActor
    private static func stagedURL(for key: String) throws -> URL {
        if let url = stagedURLsByDestination[key] { return url }

        let fileManager = FileManager.default
        if stagingDirectoryURL == nil {
            let directoryURL = fileManager.temporaryDirectory
                .appendingPathComponent("vmini-save-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            stagingDirectoryURL = directoryURL
        }

        guard let stagingDirectoryURL else { throw CocoaError(.fileWriteUnknown) }
        let url = stagingDirectoryURL.appendingPathComponent("payload-\(UUID().uuidString)")
        stagedURLsByDestination[key] = url
        return url
    }

    @MainActor
    private static func authorizationScript(for key: String, from sourceURL: URL, to destinationURL: URL) throws -> NSAppleScript {
        if let script = scriptsByDestination[key] { return script }
        guard let script = NSAppleScript(source: authorizationScript(from: sourceURL, to: destinationURL)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        scriptsByDestination[key] = script
        return script
    }

    static func authorizationScript(from sourceURL: URL, to destinationURL: URL) -> String {
        let sourcePath = appleScriptString(sourceURL.path)
        let destinationPath = appleScriptString(destinationURL.path)
        let prompt = appleScriptString("vmini needs permission to save \(destinationURL.lastPathComponent).")

        return """
        on run
            set sourcePath to \(sourcePath)
            set destinationPath to \(destinationPath)
            set shellCommand to "/bin/cat " & quoted form of sourcePath & " > " & quoted form of destinationPath
            do shell script shellCommand with administrator privileges with prompt \(prompt)
        end run
        """
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func validate(_ url: URL) throws {
        guard url.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }

        var destinationAttributes = stat()
        if url.path.withCString({ Darwin.lstat($0, &destinationAttributes) }) == 0 {
            guard destinationAttributes.st_mode & S_IFMT == S_IFREG else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            return
        }

        let destinationError = errno
        guard destinationError == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: destinationError) ?? .EIO)
        }

        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw CocoaError(.fileNoSuchFile)
        }
    }
}
