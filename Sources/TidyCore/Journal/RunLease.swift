import Foundation
import Darwin

/// A process-wide advisory lease, released automatically on return or process exit.
public final class RunLease: Sendable {
    private let descriptor: Int32
    init(url: URL) throws {
        let fd = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw TidyError.io("Cannot open operation lease") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw TidyError.busy }
        descriptor = fd
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
