import Foundation
import Darwin

enum HelperError: LocalizedError {
    case notInstalled
    case spawnFailed(Int32)
    case badOutput(String)
    case helper(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return String(localized: "The Voidy helper is missing. Reinstall Voidy from your package manager.")
        case .spawnFailed(let code):
            return String(localized: "Could not start the helper (error \(Int(code))).")
        case .badOutput(let text):
            return String(localized: "Unexpected helper response: \(text)")
        case .helper(let message):
            return message
        }
    }
}

/// Talks to `voidyhelper`, the root backend installed alongside the app.
final class HelperClient {
    static let shared = HelperClient()

    let jbroot: String
    let helperPath: String?

    var scheme: String {
        if jbroot.contains(".jbroot-") { return "roothide" }
        return jbroot.isEmpty ? "rootful" : "rootless"
    }

    private init() {
        // <jbroot>/Applications/Voidy.app -> <jbroot>
        let bundle = Bundle.main.bundlePath as NSString
        let root = (bundle.deletingLastPathComponent as NSString).deletingLastPathComponent
        let candidates = [root + "/usr/libexec/voidyhelper", "/var/jb/usr/libexec/voidyhelper", "/usr/libexec/voidyhelper"]
        let found = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        helperPath = found
        if let found = found {
            jbroot = String(found.dropLast("/usr/libexec/voidyhelper".count))
        } else {
            jbroot = root
        }
    }

    func jb(_ path: String) -> String { jbroot + path }

    // MARK: - Calls

    func call<T: Decodable>(_ type: T.Type, _ args: [String]) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            let data = try self.run(args)
            return try Self.decode(type, from: data)
        }.value
    }

    @discardableResult
    func perform(_ args: [String]) async throws -> String {
        try await call(OKResponse.self, args).message ?? ""
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let line = data.split(separator: UInt8(ascii: "\n")).last.map { Data($0) } ?? data
        if let failure = try? JSONDecoder().decode(ErrorResponse.self, from: line) {
            throw HelperError.helper(failure.error)
        }
        do {
            return try JSONDecoder().decode(type, from: line)
        } catch {
            throw HelperError.badOutput(String(decoding: line.prefix(200), as: UTF8.self))
        }
    }

    // MARK: - Spawning

    private func run(_ args: [String]) throws -> Data {
        guard let path = helperPath else { throw HelperError.notInstalled }
        do {
            return try spawn(path, args, asRoot: true)
        } catch HelperError.spawnFailed(let code) where code == EPERM || code == EINVAL {
            // No persona entitlement at runtime – fall back to the setuid bit.
            return try spawn(path, args, asRoot: false)
        }
    }

    private func spawn(_ path: String, _ args: [String], asRoot: Bool) throws -> Data {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw HelperError.spawnFailed(errno) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        posix_spawn_file_actions_addclose(&actions, fds[1])
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        if asRoot { Persona.applyRoot(&attr) }

        let argv: [UnsafeMutablePointer<CChar>?] = ([path] + args).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, &actions, &attr, argv, envp)
        close(fds[1])
        guard rc == 0 else {
            close(fds[0])
            throw HelperError.spawnFailed(rc)
        }

        let handle = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true)
        let data = handle.readDataToEndOfFile()
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return data
    }
}

/// Spawns with the root persona (requires com.apple.private.persona-mgmt).
private enum Persona {
    typealias SetPersona = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, uid_t, UInt32) -> Int32
    typealias SetID = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, uid_t) -> Int32

    static func applyRoot(_ attr: inout posix_spawnattr_t?) {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let setPersonaSym = dlsym(handle, "posix_spawnattr_set_persona_np"),
              let setUIDSym = dlsym(handle, "posix_spawnattr_set_persona_uid_np"),
              let setGIDSym = dlsym(handle, "posix_spawnattr_set_persona_gid_np") else { return }
        let setPersona = unsafeBitCast(setPersonaSym, to: SetPersona.self)
        let setUID = unsafeBitCast(setUIDSym, to: SetID.self)
        let setGID = unsafeBitCast(setGIDSym, to: SetID.self)
        _ = setPersona(&attr, 99, 1) // POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
        _ = setUID(&attr, 0)
        _ = setGID(&attr, 0)
    }
}
