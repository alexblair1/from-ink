import Foundation

/// Typed error for required bootstrap stage failures.
/// Only required stages produce a BootstrapError — optional stages
/// express soft failure through BootstrapFeature.Degradation.
///
enum BootstrapError: Error {
    case storageUnavailable(any Error)
    case schemaMigrationFailed(any Error)
}

extension BootstrapError: Equatable {
    static func == (lhs: BootstrapError, rhs: BootstrapError) -> Bool {
        switch (lhs, rhs) {
        case (.storageUnavailable, .storageUnavailable),
             (.schemaMigrationFailed, .schemaMigrationFailed):
            return true
        default:
            return false
        }
    }
}
