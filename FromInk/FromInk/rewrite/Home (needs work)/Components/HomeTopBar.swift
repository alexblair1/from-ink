import SwiftUI

/// Sticky top bar: settings (left), wordmark (center), import-PDF +
/// compose (right). The import slot is a SwiftUI `Menu` — tapping
/// surfaces a native pull-down menu anchored to the icon with two
/// items: "Import file" and "Scan document". Menu is the canonical
/// cross-platform primitive for "tap a button → pick one of N
/// actions": dropdown on iPhone/iPad, native menu on macOS, anchored
/// everywhere, zero per-platform code.
///
/// Component view — no TCA imports. The Model carries two action
/// closures and a `scanDocumentAvailable` flag; the wiring view
/// supplies them.
///
struct HomeTopBar: View {
    let model: Model

    var body: some View {
        HStack(spacing: 0) {
            Button(action: model.onSettings) {
                Image(systemName: model.leadingIcon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.hitTarget, height: model.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(model.title)
                .font(model.titleFont)
                .foregroundStyle(model.titleColor)
                .tracking(model.titleTracking)

            Spacer()

            // Focus-mode toggle. Eye / eye.slash semantic: open eye =
            // "everything is visible" (off, tap to enter focus), slash
            // eye = "things hidden" (on, tap to exit). Lives between
            // the masthead and the document Menu so the right-edge
            // anchor stays on the canonical compose icon.
            Button(action: model.onFocusModeToggled) {
                Image(systemName: model.focusModeIcon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.hitTarget, height: model.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.focusModeAccessibilityLabel)

            // Menu (pull-down) anchored to the doc icon. Apple HIG-
            // compliant on every platform; arrow / dropdown chrome
            // is system-provided.
            Menu {
                Button {
                    model.onImportPDF()
                } label: {
                    Label(model.importFileMenuLabel, systemImage: "doc")
                }

                if model.scanDocumentAvailable {
                    Button {
                        model.onScanDocument()
                    } label: {
                        Label(model.scanDocumentMenuLabel, systemImage: "doc.viewfinder")
                    }
                }
            } label: {
                Image(systemName: model.importPDFIcon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.hitTarget, height: model.hitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(model.importPDFAccessibilityLabel)

            Button(action: model.onCompose) {
                Image(systemName: model.trailingIcon)
                    .font(.system(size: model.iconSize, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(model.iconColor)
                    .frame(width: model.hitTarget, height: model.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.top, model.topPadding)
        .padding(.bottom, model.bottomPadding)
    }
}

// MARK: - Model

extension HomeTopBar {
    struct Model {
        let title: String
        let leadingIcon: String
        let importPDFIcon: String
        let importPDFAccessibilityLabel: String
        let importFileMenuLabel: String
        let scanDocumentMenuLabel: String
        /// Hide the Scan item when VisionKit's
        /// `VNDocumentCameraViewController.isSupported` returns
        /// false (Simulator, certain Mac configurations). Showing a
        /// disabled item would imply the user is one fix away from
        /// scanning, which they're not.
        let scanDocumentAvailable: Bool
        /// `eye` when focus mode is OFF (tap to enter), `eye.slash`
        /// when focus mode is ON (tap to exit). Resolved on the
        /// Model so the view stays declarative.
        let focusModeIcon: String
        let focusModeAccessibilityLabel: String
        let trailingIcon: String
        let onSettings: () -> Void
        let onFocusModeToggled: () -> Void
        let onImportPDF: () -> Void
        let onScanDocument: () -> Void
        let onCompose: () -> Void
        let titleFont: Font
        let titleColor: Color
        let titleTracking: CGFloat
        let iconColor: Color
        let iconSize: CGFloat
        let hitTarget: CGFloat
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
    }
}

// MARK: - Model init

extension HomeTopBar.Model {
    init(
        onSettings: @escaping () -> Void,
        onFocusModeToggled: @escaping () -> Void,
        isFocusMode: Bool,
        onImportPDF: @escaping () -> Void,
        onScanDocument: @escaping () -> Void,
        onCompose: @escaping () -> Void,
        scanDocumentAvailable: Bool,
        ds: DesignSystem = .standard
    ) {
        self.title = AppStrings.Home.title
        self.leadingIcon = "gearshape"
        self.importPDFIcon = "doc.badge.plus"
        self.importPDFAccessibilityLabel = AppStrings.Library.importPDFButton
        self.importFileMenuLabel = AppStrings.DocumentImport.importFileMenuItem
        self.scanDocumentMenuLabel = AppStrings.DocumentImport.scanDocumentMenuItem
        self.scanDocumentAvailable = scanDocumentAvailable
        self.focusModeIcon = isFocusMode ? "eye.slash" : "eye"
        self.focusModeAccessibilityLabel = isFocusMode
            ? AppStrings.Home.focusModeExitAccessibilityLabel
            : AppStrings.Home.focusModeEnterAccessibilityLabel
        self.trailingIcon = "square.and.pencil"
        self.onSettings = onSettings
        self.onFocusModeToggled = onFocusModeToggled
        self.onImportPDF = onImportPDF
        self.onScanDocument = onScanDocument
        self.onCompose = onCompose
        self.titleFont = ds.typography.wordmark
        self.titleColor = ds.colors.ink
        self.titleTracking = 0.4
        self.iconColor = ds.colors.ink
        self.iconSize = 17
        self.hitTarget = ds.layout.hitTarget
        self.horizontalPadding = ds.spacing.lg
        self.topPadding = ds.spacing.sm
        self.bottomPadding = ds.spacing.xs
    }
}
