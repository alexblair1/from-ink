import ComposableArchitecture
import Foundation

/// State + reducer for the slash command palette.
///
/// **Scope.** This feature owns the palette's open/close lifecycle,
/// the user-typed filter text, the currently-highlighted index for
/// keyboard navigation, and the resolved descriptor list under the
/// current filter. It does NOT execute the selected command — the
/// parent feature (`TextEditingFeature` / `NotebookFeature`) consumes
/// `delegate.commandSelected(SlashCommand)` and routes accordingly.
///
/// **Two surfaces, one reducer.** Same vocabulary drives the
/// caret-anchored popover on Mac + iPad regular AND the iPhone /
/// iPad-compact accessory bar surface (when it lands). The wiring
/// layer chooses which view to present; the reducer is presentation-
/// agnostic.
///
/// **Keyboard navigation.** Arrow up/down moves the highlight;
/// enter selects; escape dismisses. The popover view forwards
/// `keyboardNavigationKey` actions; the reducer keeps
/// `selectedIndex` clamped to the matched list.
struct SlashCommandPaletteFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        var isOpen: Bool = false

        /// User-typed filter text (the characters that follow the
        /// triggering `/`). Empty string means "show everything."
        var filterText: String = ""

        /// Index of the currently-highlighted descriptor in
        /// `matchedCommands`. Clamped on every filter / nav update.
        var selectedIndex: Int = 0

        /// Descriptors that match `filterText`, in declared order.
        /// Recomputed whenever filterText changes; cached on State so
        /// the view doesn't re-filter on every render.
        var matchedCommands: [SlashCommandDescriptor] = []

        /// Source registry the matcher reads from. Tests inject a
        /// smaller set; production uses `.standard()`.
        var registry: SlashCommandRegistry = .standard()

        /// True when no commands match the current filter. View
        /// renders the "no matches" empty state.
        var isEmpty: Bool { matchedCommands.isEmpty }

        /// The currently-highlighted descriptor, or nil if the
        /// matched list is empty.
        var selectedCommand: SlashCommandDescriptor? {
            guard !matchedCommands.isEmpty else { return nil }
            let idx = min(max(0, selectedIndex), matchedCommands.count - 1)
            return matchedCommands[idx]
        }
    }

    @CasePathable
    enum Action: Equatable {
        /// Open the palette. The triggering `/` character is already
        /// in the body; the editor handles its insertion/removal.
        case openRequested

        /// User typed more (or backspaced). The reducer recomputes
        /// `matchedCommands` and clamps `selectedIndex`.
        case filterChanged(String)

        /// Arrow up / down / enter / escape from the popover view's
        /// key-equivalent observers (Mac + iPad with hardware kbd).
        case keyboardNavigationKey(KeyDirection)

        /// Direct selection — fired by clicking a row, by tapping
        /// an accessory bar button, or by enter on the highlighted
        /// row. Parent feature observes via `delegate` and routes
        /// the command.
        case commandSelected(SlashCommand)

        /// User-initiated close (escape, tap-outside, body-edited
        /// past the triggering `/`).
        case dismissed

        enum KeyDirection: Equatable, Sendable {
            case up
            case down
            case enter
            case escape
        }
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .openRequested:
                state.isOpen = true
                state.filterText = ""
                state.matchedCommands = state.registry.filtered(by: "")
                state.selectedIndex = 0
                return .none

            case .filterChanged(let text):
                state.filterText = text
                state.matchedCommands = state.registry.filtered(by: text)
                // Clamp selection so a narrowed list doesn't leave
                // selectedIndex pointing past the end.
                if state.matchedCommands.isEmpty {
                    state.selectedIndex = 0
                } else {
                    state.selectedIndex = min(
                        state.selectedIndex,
                        state.matchedCommands.count - 1
                    )
                }
                return .none

            case .keyboardNavigationKey(let direction):
                switch direction {
                case .up:
                    state.selectedIndex = max(0, state.selectedIndex - 1)
                    return .none
                case .down:
                    state.selectedIndex = min(
                        state.matchedCommands.count - 1,
                        state.selectedIndex + 1
                    )
                    return .none
                case .enter:
                    guard let selected = state.selectedCommand else { return .none }
                    return .send(.commandSelected(selected.id))
                case .escape:
                    return .send(.dismissed)
                }

            case .commandSelected:
                // Parent observes this action via Scope + the
                // dispatching reducer. The palette closes itself
                // immediately so consecutive commands don't queue
                // against a stale popover.
                state.isOpen = false
                state.filterText = ""
                state.selectedIndex = 0
                return .none

            case .dismissed:
                state.isOpen = false
                state.filterText = ""
                state.selectedIndex = 0
                return .none
            }
        }
    }
}
