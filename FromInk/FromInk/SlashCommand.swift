import ComposableArchitecture
import Foundation

/// The shared command vocabulary that drives both the slash menu
/// (Mac + iPad regular, keyboard-typed `/`) and the iPhone /
/// iPad-compact accessory bar (touch-tapped buttons). Per EDD §13.1
/// the two surfaces are presentations of the same underlying set —
/// the wiring layer chooses which is visible based on
/// `horizontalSizeClass` and hardware-keyboard presence.
///
/// **Availability discipline.** Not every command in the vocabulary
/// has a working action handler in this commit; the menu is wired
/// end-to-end (filter, navigate, select) so the visual and
/// interaction patterns ship complete, while command-specific
/// handlers land as their dependencies come online:
///
///   • Block format (`heading1` / `heading2` / `heading3` / `body`)
///     — wired NOW via `TextEditingFeature.applyBlockFormat`.
///   • Lists (`bulletedList` / `numberedList` / `checklist`) — defer
///     to the same commit that lands the list-typing-flow chrome.
///   • Inserts (`divider` / `region` / `link` / `event` / `pdfAttach`
///     / `voiceMemo` / `image`) — each defers to the commit that
///     ships its dependency (selection menu, EventKit picker, file
///     picker, SpeechService, PhotosPicker).
///   • `dispatch` — defers to the selection-menu / DispatchFeature
///     integration in the next chrome commit.
///
/// A command's `SlashCommandDescriptor.availability` field
/// distinguishes the two states for the wiring layer; the palette
/// surfaces unavailable commands as visibly dimmed so the user has
/// a roadmap rather than a wall of fully-active rows.
enum SlashCommand: String, Codable, Hashable, CaseIterable, Sendable {
    // MARK: Block format
    case heading1
    case heading2
    case heading3
    case body
    case blockQuote
    case code

    // MARK: Lists
    case bulletedList
    case numberedList
    case checklist

    // MARK: Inserts
    case divider
    case region
    case link
    case event
    case pdfAttach
    case voiceMemo
    case image

    // MARK: Dispatch
    case dispatch
}

/// Resolved descriptor for a single slash command — the SF Symbol,
/// localized title, availability state, and (optional) keyboard
/// shortcut hint that the palette / accessory bar surface.
///
/// Adding a new command is one enum case + one descriptor row in
/// `SlashCommandRegistry.standard`; no view-layer code needs to know
/// the command exists.
struct SlashCommandDescriptor: Equatable, Identifiable, Sendable {
    let id: SlashCommand
    let icon: String
    let title: String
    let shortcutHint: String?
    let availability: Availability

    /// Whether the command's action handler is wired in the current
    /// build. The wiring view filters / dims unavailable commands
    /// rather than hiding them entirely so the user sees the full
    /// roadmap.
    enum Availability: Equatable, Sendable {
        case available
        case comingSoon
    }
}

// MARK: - Registry

/// Source of truth for the slash-command descriptor table. The
/// palette + accessory bar both read from `.standard`; tests that
/// need a smaller set can build their own.
struct SlashCommandRegistry: Equatable, Sendable {
    let descriptors: [SlashCommandDescriptor]

    /// Look up a descriptor by command id.
    func descriptor(for command: SlashCommand) -> SlashCommandDescriptor? {
        descriptors.first { $0.id == command }
    }

    /// Filter the registry by a user-typed query. Empty filter
    /// returns every available descriptor in declared order;
    /// non-empty filter narrows by `localizedStandardContains`
    /// against the localized title so non-English locales match
    /// naturally ("/üb" → "Überschrift 1" in de_DE).
    func filtered(by query: String) -> [SlashCommandDescriptor] {
        guard !query.isEmpty else { return descriptors }
        return descriptors.filter { descriptor in
            descriptor.title.localizedStandardContains(query)
        }
    }
}

extension SlashCommandRegistry {
    /// Standard descriptor table. Titles resolve through
    /// `AppStrings.SlashMenu` at first access; the registry caches
    /// the resolved descriptors as a `static let` so subsequent
    /// reads don't re-run 17 NSLocalizedString lookups per state
    /// init. A runtime locale change won't update the cached
    /// strings — a known v1 limitation; relaunch resolves it. The
    /// registry lives in a TCA dependency (see `DependencyValues.
    /// slashCommandRegistry`) rather than on reducer State so its
    /// Equatable cost doesn't show up in state-diff hot paths.
    static let standard: SlashCommandRegistry = SlashCommandRegistry(descriptors: [
            // MARK: Block format
            .init(
                id: .heading1,
                icon: "textformat.size.larger",
                title: AppStrings.SlashMenu.heading1,
                shortcutHint: "⌘⌥1",
                availability: .available
            ),
            .init(
                id: .heading2,
                icon: "textformat.size",
                title: AppStrings.SlashMenu.heading2,
                shortcutHint: "⌘⌥2",
                availability: .available
            ),
            .init(
                id: .heading3,
                icon: "textformat.size.smaller",
                title: AppStrings.SlashMenu.heading3,
                shortcutHint: "⌘⌥3",
                availability: .available
            ),
            .init(
                id: .body,
                icon: "text.alignleft",
                title: AppStrings.SlashMenu.body,
                shortcutHint: "⌘⌥0",
                availability: .available
            ),
            .init(
                id: .blockQuote,
                icon: "quote.opening",
                title: AppStrings.SlashMenu.blockQuote,
                shortcutHint: nil,
                availability: .available
            ),
            .init(
                id: .code,
                icon: "curlybraces",
                title: AppStrings.SlashMenu.code,
                shortcutHint: nil,
                availability: .available
            ),
            // MARK: Lists
            .init(
                id: .bulletedList,
                icon: "list.bullet",
                title: AppStrings.SlashMenu.bulletedList,
                shortcutHint: "⌘⇧8",
                availability: .available
            ),
            .init(
                id: .numberedList,
                icon: "list.number",
                title: AppStrings.SlashMenu.numberedList,
                shortcutHint: "⌘⇧7",
                availability: .available
            ),
            .init(
                id: .checklist,
                icon: "checklist",
                title: AppStrings.SlashMenu.checklist,
                shortcutHint: "⌘⇧9",
                availability: .comingSoon
            ),
            // MARK: Inserts
            .init(
                id: .divider,
                icon: "minus",
                title: AppStrings.SlashMenu.divider,
                shortcutHint: nil,
                availability: .available
            ),
            .init(
                id: .region,
                icon: "rectangle.dashed",
                title: AppStrings.SlashMenu.region,
                shortcutHint: "⌘⇧R",
                availability: .comingSoon
            ),
            .init(
                id: .link,
                icon: "link",
                title: AppStrings.SlashMenu.link,
                shortcutHint: "⌘K",
                availability: .comingSoon
            ),
            .init(
                id: .event,
                icon: "calendar",
                title: AppStrings.SlashMenu.event,
                shortcutHint: nil,
                availability: .comingSoon
            ),
            .init(
                id: .pdfAttach,
                icon: "doc",
                title: AppStrings.SlashMenu.pdfAttach,
                shortcutHint: nil,
                availability: .comingSoon
            ),
            .init(
                id: .voiceMemo,
                icon: "waveform",
                title: AppStrings.SlashMenu.voiceMemo,
                shortcutHint: "⌘⇧V",
                availability: .comingSoon
            ),
            .init(
                id: .image,
                icon: "photo",
                title: AppStrings.SlashMenu.image,
                shortcutHint: nil,
                availability: .comingSoon
            ),
            // MARK: Dispatch
            .init(
                id: .dispatch,
                icon: "paperplane",
                title: AppStrings.SlashMenu.dispatch,
                shortcutHint: "⌘⇧D",
                availability: .comingSoon
            ),
        ])
}

// MARK: - Dependency

extension SlashCommandRegistry: DependencyKey {
    static let liveValue: SlashCommandRegistry = .standard
    static let testValue: SlashCommandRegistry = .standard
}

extension DependencyValues {
    /// The slash-command vocabulary the palette + accessory bar
    /// surfaces draw from. Lives as a dependency so reducer State
    /// stays small — the registry never mutates during a session.
    var slashCommandRegistry: SlashCommandRegistry {
        get { self[SlashCommandRegistry.self] }
        set { self[SlashCommandRegistry.self] = newValue }
    }
}
