import ComposableArchitecture
import Foundation
import UIKit
import VisionKit
import os

private let log = Logger(subsystem: "com.fromink.app", category: "DocumentScanner")

/// TCA dependency wrapping VisionKit's `VNDocumentCameraViewController`
/// — Apple's canonical multi-page document scanner with edge detection,
/// auto-capture, perspective correction, and B/W / colour filters.
///
/// **Why a service abstraction at all?** `VNDocumentCameraViewController`
/// is a `UIKit` modal controller with a delegate-based callback shape.
/// Reducers cannot present view controllers directly, so the wiring
/// view presents it and the reducer treats the scan as an async
/// operation that emits one of `success(images:)` / `cancelled` /
/// `failed(error:)`. This service is the boundary that converts the
/// delegate callbacks into that async shape; the wiring view consumes
/// it via the SwiftUI `DocumentScannerRepresentable` and forwards the
/// outcome through TCA actions.
///
/// Camera permission: `VNDocumentCameraViewController` prompts on
/// first present. If the user has previously denied camera access the
/// controller fails to present and we surface `Outcome.failed` — the
/// reducer routes to a "Camera access required" message with a
/// system-Settings deep link, same UX as `PermissionsFeature`.
///
/// iOS 26 status: VisionKit's scanner remains the canonical Apple
/// path; no replacement API has shipped. Verified against
/// developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller
/// (May 2026).
///
struct DocumentScannerService: Sendable {
    /// True iff the device can present `VNDocumentCameraViewController`.
    /// Mirrors VisionKit's static `isSupported` — false on Simulator
    /// (no camera), false on macOS catalyst, false on iPad models
    /// without rear-facing camera APIs available.
    var isAvailable: @Sendable () -> Bool
}

// MARK: - Outcome

enum DocumentScanOutcome: Sendable {
    /// User completed the scan with N >= 1 pages. Images are in
    /// scan order (first page captured first).
    case success(images: [UIImage])
    /// User dismissed the scanner without capturing anything.
    case cancelled
    /// VisionKit returned an error (camera unavailable, permission
    /// denied at present time, internal failure). The underlying
    /// error is preserved for logging; the reducer surfaces a
    /// localized message rather than the raw string.
    case failed(error: Error)
}

// MARK: - Live

extension DocumentScannerService: DependencyKey {
    static let liveValue = DocumentScannerService(
        isAvailable: { VNDocumentCameraViewController.isSupported }
    )
}

// MARK: - Test

extension DocumentScannerService: TestDependencyKey {
    /// Default: scanner unavailable. Tests that exercise the scan
    /// branch must opt in by overriding with `.preview(...)`.
    static let testValue = DocumentScannerService(
        isAvailable: { false }
    )

    /// Convenience override — tests + previews can dictate availability.
    static func preview(isAvailable: Bool) -> DocumentScannerService {
        DocumentScannerService(isAvailable: { isAvailable })
    }
}

// MARK: - DependencyValues

extension DependencyValues {
    var documentScannerService: DocumentScannerService {
        get { self[DocumentScannerService.self] }
        set { self[DocumentScannerService.self] = newValue }
    }
}
