import SwiftUI

/// Feature view for the floating-capsule toolbar.
///
/// Two stacked capsules:
///   • Top capsule — drag handle, scrollable tool list, ink readout pinned
///     at the bottom of the capsule (outside the scroll region).
///   • Bottom capsule — utility actions (undo / redo / template / settings
///     / dispatch). Intrinsic height; never scrolls; always fully visible.
///
/// Layout rule on tight viewports: the bottom capsule takes priority and
/// shows all its content; the top capsule occupies the remaining height,
/// and its internal ScrollView activates when the tool list exceeds that
/// height. The capsule chrome (drag handle + ink readout) stays pinned.
///
/// Component / feature view — no TCA imports.
struct ToolbarView: View {
    let model: Model

    var body: some View {
        VStack(spacing: model.minCapsuleGap) {
            topCapsule
                .frame(maxHeight: .infinity, alignment: .top)

            bottomCapsule
        }
        .padding(.horizontal, model.outerHorizontalInset)
        .padding(.vertical, model.outerVerticalInset)
        .frame(maxWidth: .infinity, alignment: model.alignment)
    }

    // MARK: - Top capsule

    private var topCapsule: some View {
        VStack(spacing: 0) {
            if let dragHandle = model.dragHandle {
                DragHandleView(model: dragHandle)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: model.interItemSpacing) {
                    ForEach(model.topItems) { item in
                        toolbarItem(item)
                    }
                }
                .padding(.vertical, model.dragHandle == nil ? 0 : model.interItemSpacing)
            }
            .scrollBounceBehavior(.basedOnSize)

            if let readout = model.inkReadout {
                capsuleDivider
                    .padding(.bottom, model.interItemSpacing)
                InkReadoutView(model: readout)
            }
        }
        .padding(.horizontal, model.capsulePaddingHorizontal)
        .padding(.vertical, model.capsulePaddingVertical)
        .background(capsuleBackground)
        .overlay(capsuleBorder)
        .shadow(
            color: model.shadowPrimary.color,
            radius: model.shadowPrimary.radius,
            x: model.shadowPrimary.x,
            y: model.shadowPrimary.y
        )
        .shadow(
            color: model.shadowAmbient.color,
            radius: model.shadowAmbient.radius,
            x: model.shadowAmbient.x,
            y: model.shadowAmbient.y
        )
    }

    // MARK: - Bottom capsule

    @ViewBuilder
    private var bottomCapsule: some View {
        if !model.bottomItems.isEmpty {
            VStack(spacing: model.interItemSpacing) {
                ForEach(model.bottomItems) { item in
                    toolbarItem(item)
                }
            }
            .padding(.horizontal, model.capsulePaddingHorizontal)
            .padding(.vertical, model.capsulePaddingVertical)
            .background(capsuleBackground)
            .overlay(capsuleBorder)
            .shadow(
                color: model.shadowPrimary.color,
                radius: model.shadowPrimary.radius,
                x: model.shadowPrimary.x,
                y: model.shadowPrimary.y
            )
            .shadow(
                color: model.shadowAmbient.color,
                radius: model.shadowAmbient.radius,
                x: model.shadowAmbient.x,
                y: model.shadowAmbient.y
            )
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func toolbarItem(_ item: Model.Item) -> some View {
        switch item {
        case .toolButton(let buttonModel):
            ToolButtonView(model: buttonModel)
        case .actionButton(let buttonModel):
            ActionButtonView(model: buttonModel)
        }
    }

    private var capsuleBackground: some View {
        RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
            .fill(model.capsuleFill)
    }

    private var capsuleBorder: some View {
        RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
            .stroke(model.capsuleBorder, lineWidth: model.borderWidth)
    }

    private var capsuleDivider: some View {
        Rectangle()
            .fill(model.capsuleBorder)
            .frame(width: model.internalRuleWidth, height: 1)
            .opacity(0.7)
            .padding(.top, model.interItemSpacing)
    }
}

// MARK: - Model

extension ToolbarView {
    struct Model {
        /// Optional drag handle pinned at the top of the top capsule.
        let dragHandle: DragHandleView.Model?
        /// Tools (and bolt) rendered inside the scrollable region of the
        /// top capsule, in order.
        let topItems: [Item]
        /// Ink readout pinned to the bottom of the top capsule. nil hides
        /// the readout and its divider (e.g. when no settings are loaded
        /// yet on first launch).
        let inkReadout: InkReadoutView.Model?
        /// Actions rendered inside the bottom capsule, in order.
        let bottomItems: [Item]

        let alignment: Alignment
        let outerHorizontalInset: CGFloat
        let outerVerticalInset: CGFloat
        let minCapsuleGap: CGFloat
        let capsulePaddingHorizontal: CGFloat
        let capsulePaddingVertical: CGFloat
        let interItemSpacing: CGFloat
        let internalRuleWidth: CGFloat
        let cornerRadius: CGFloat
        let borderWidth: CGFloat
        let capsuleFill: Color
        let capsuleBorder: Color
        let shadowPrimary: ShadowTokens.Shadow
        let shadowAmbient: ShadowTokens.Shadow

        enum Item: Identifiable {
            case toolButton(ToolButtonView.Model)
            case actionButton(ActionButtonView.Model)

            var id: String {
                switch self {
                case .toolButton(let m):   "tool-\(m.id)"
                case .actionButton(let m): "action-\(m.id)"
                }
            }
        }
    }
}

// MARK: - Model init

extension ToolbarView.Model {
    init(
        dragHandle: DragHandleView.Model?,
        topItems: [Item],
        inkReadout: InkReadoutView.Model?,
        bottomItems: [Item],
        side: ToolbarSide,
        ds: DesignSystem = .standard
    ) {
        self.dragHandle = dragHandle
        self.topItems = topItems
        self.inkReadout = inkReadout
        self.bottomItems = bottomItems
        self.alignment = side == .left ? .leading : .trailing
        self.outerHorizontalInset = ds.layout.toolbarCapsuleHorizontalInset
        self.outerVerticalInset = ds.layout.toolbarCapsuleVerticalInset
        self.minCapsuleGap = ds.layout.toolbarCapsuleMinPillGap
        self.capsulePaddingHorizontal = ds.layout.toolbarCapsulePaddingHorizontal
        self.capsulePaddingVertical = ds.layout.toolbarCapsulePaddingVertical
        self.interItemSpacing = ds.layout.toolbarCapsuleInterItemSpacing
        self.internalRuleWidth = ds.layout.toolbarCapsuleInternalRuleWidth
        self.cornerRadius = ds.layout.toolbarCapsuleCornerRadius
        self.borderWidth = ds.layout.borderWidth
        self.capsuleFill = ds.colors.paper
        self.capsuleBorder = ds.colors.rule
        self.shadowPrimary = ds.shadow.toolbarCapsulePrimary
        self.shadowAmbient = ds.shadow.toolbarCapsuleAmbient
    }
}
