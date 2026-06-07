import Foundation

extension AppStrings {
    enum Bootstrap { 
        static let unableToStart = NSLocalizedString(
            "bootstrap.unableToStart",
            value: "Unable to Start",
            comment: "Title shown when the app fails to launch"
        )
        static let tryAgain = NSLocalizedString(
            "bootstrap.tryAgain",
            value: "Try Again",
            comment: "Retry button on bootstrap failure screen"
        )
        static let storageError = NSLocalizedString(
            "bootstrap.storageError",
            value: "From Ink could not open its data store. Please try again or restart the app.",
            comment: "Error message when SwiftData storage fails to initialize"
        )
        static let migrationError = NSLocalizedString(
            "bootstrap.migrationError",
            value: "A data update could not be applied. Please try again or contact support.",
            comment: "Error message when schema migration fails"
        )
        static let unknownError = NSLocalizedString(
            "bootstrap.unknownError",
            value: "An unexpected error occurred.",
            comment: "Fallback error message for unrecognized bootstrap failures"
        )
    }
}
