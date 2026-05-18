import SwiftUI

/// Drawer transition — animates a view's frame height from `0` to its
/// natural height (or vice versa), anchored at the top edge and clipped.
///
/// Unlike `.move(edge: .top)` or `.push(from: .top)`, this transition
/// actually changes the layout slot during the animation: subsequent
/// siblings in the parent stack are pushed down (or pulled up) smoothly
/// as the drawer grows or collapses. The wheel "unfolds" from its top
/// edge rather than sliding in from somewhere above.
///
/// Required because SwiftUI's built-in transitions are visual transforms
/// — they preserve the layout slot at its full size throughout the
/// animation. For the wheel, that means content below the wheel sits at
/// its post-expansion position throughout the open animation, leaving an
/// empty gap before the wheel finishes sliding in. The drawer transition
/// keeps the slot in sync with the visual height so there is no gap.
///
extension AnyTransition {
    /// - Parameter naturalHeight: The expanded height the drawer should
    ///   grow to. Pass the precise height of the view being transitioned;
    ///   smaller values clip content and larger values leave empty space.
    static func drawer(naturalHeight: CGFloat) -> AnyTransition {
        .modifier(
            active: DrawerModifier(progress: 0, naturalHeight: naturalHeight),
            identity: DrawerModifier(progress: 1, naturalHeight: naturalHeight)
        )
    }
}

/// `Animatable` `ViewModifier` that drives the drawer's height. The
/// `progress` value interpolates from `0` (collapsed) to `1` (expanded);
/// `animatableData` makes SwiftUI interpolate it smoothly when the modifier
/// is used as a transition.
///
struct DrawerModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let naturalHeight: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(height: max(0, progress * naturalHeight), alignment: .top)
            .clipped()
            .opacity(Double(progress))
    }
}
