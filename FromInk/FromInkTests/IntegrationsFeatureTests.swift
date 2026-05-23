import ComposableArchitecture
import XCTest
@testable import FromInk

/// TestStore coverage for `IntegrationsFeature` — the Settings sub-
/// screen feature backing the Integrations list.
///
/// **V1 scope:** the OAuth layer is not yet integrated. Each
/// `addAccountTapped` runs a mock effect that sleeps 1.5s on the
/// injected `continuousClock`, then deterministically yields one of
/// success / cancelled / permissions-denied / network / state-mismatch
/// per `MockOutcome.cycle`. Tests use `TestClock` to advance time
/// without sleeping.
///
/// Each test exercises one slice of the state machine documented in
/// `IntegrationsFeature.swift`. Where multiple cycle outcomes are
/// reachable from a single action (e.g. `addAccountTapped`), each
/// outcome has its own test rather than parameterizing — keeps the
/// failure messages specific.
///
final class IntegrationsFeatureTests: XCTestCase {

    // MARK: - .appeared

    @MainActor
    func test_appeared_loadsMockConnections() async {
        let store = TestStore(initialState: IntegrationsFeature.State()) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }

        await store.send(.appeared)

        // Mock seed is deterministic: 2 providers, 4 accounts, with
        // one Linear account flagged `.reconnectRequired`.
        await store.receive(\.mockConnectionsLoaded) { state in
            XCTAssertEqual(state.connections.count, 2)
            XCTAssertEqual(state.connections[0].provider, .linear)
            XCTAssertEqual(state.connections[0].accounts.count, 3)
            XCTAssertEqual(state.connections[1].provider, .slack)
            XCTAssertEqual(state.connections[1].accounts.count, 1)
            // Defaults are seeded from the first healthy account in
            // each provider — Linear "From Ink", Slack "Acme".
            XCTAssertNotNil(state.defaults[.linear])
            XCTAssertNotNil(state.defaults[.slack])
            // Quartz Labs is the reconnectRequired account; it must
            // not be the default.
            let quartzID = state.connections[0].accounts
                .first(where: { $0.health == .reconnectRequired })?.id
            XCTAssertNotEqual(state.defaults[.linear], quartzID)
        }
    }

    // MARK: - .addAccountTapped — synchronous setup

    @MainActor
    func test_addAccountTapped_insertsConnectingPendingAndAdvancesCycle() async {
        let clock = TestClock()
        let store = TestStore(initialState: seededState()) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.addAccountTapped(.linear)) { state in
            // .incrementing starts at all-zeros; first call yields
            // 00000000-0000-0000-0000-000000000000.
            let expectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            XCTAssertEqual(state.pendingAdds.count, 1)
            XCTAssertEqual(state.pendingAdds[0].id, expectedID)
            XCTAssertEqual(state.pendingAdds[0].provider, .linear)
            XCTAssertEqual(state.pendingAdds[0].phase, .connecting)
            XCTAssertEqual(state.mockOutcomeIndex, 1)
        }
    }

    // MARK: - .addAccountTapped — cycle index drives outcome

    /// Outcome at index 1 is `.userCancelled` per `MockOutcome.cycle`.
    /// Verifies the effect resolves to a failed-row state with the
    /// matching error variant when the 1.5s clock advance fires.
    @MainActor
    func test_addAccountTapped_outcomeUserCancelled_setsFailedPhase() async {
        let clock = TestClock()
        var seeded = seededState()
        seeded.mockOutcomeIndex = 1                    // → .userCancelled
        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.addAccountTapped(.linear))
        await clock.advance(by: .seconds(1.5))

        await store.receive(\.addAccountFailed) { state in
            XCTAssertEqual(state.pendingAdds.count, 1)
            XCTAssertEqual(
                state.pendingAdds[0].phase,
                .failed(.userCancelled)
            )
        }
    }

    /// Outcome at index 2 is `.permissionsDenied`.
    @MainActor
    func test_addAccountTapped_outcomePermissionsDenied_setsFailedPhase() async {
        let clock = TestClock()
        var seeded = seededState()
        seeded.mockOutcomeIndex = 2
        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.addAccountTapped(.linear))
        await clock.advance(by: .seconds(1.5))

        await store.receive(\.addAccountFailed) { state in
            XCTAssertEqual(
                state.pendingAdds[0].phase,
                .failed(.permissionsDenied)
            )
        }
    }

    /// Outcome at index 3 is `.network`.
    @MainActor
    func test_addAccountTapped_outcomeNetwork_setsFailedPhase() async {
        let clock = TestClock()
        var seeded = seededState()
        seeded.mockOutcomeIndex = 3
        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.addAccountTapped(.linear))
        await clock.advance(by: .seconds(1.5))

        await store.receive(\.addAccountFailed) { state in
            XCTAssertEqual(state.pendingAdds[0].phase, .failed(.network))
        }
    }

    /// Outcome at index 4 is `.stateMismatch` — the only failure
    /// that does NOT auto-retry. The pending row stays failed; only
    /// `.pendingAddDismissed` removes it (see test below).
    @MainActor
    func test_addAccountTapped_outcomeStateMismatch_setsFailedPhase() async {
        let clock = TestClock()
        var seeded = seededState()
        seeded.mockOutcomeIndex = 4
        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.addAccountTapped(.linear))
        await clock.advance(by: .seconds(1.5))

        await store.receive(\.addAccountFailed) { state in
            XCTAssertEqual(state.pendingAdds[0].phase, .failed(.stateMismatch))
        }
    }

    // MARK: - .accountAdded

    @MainActor
    func test_accountAdded_firstForProvider_silentlyBecomesDefault() async {
        // Provider has no existing accounts, no existing default.
        var seeded = IntegrationsFeature.State()
        seeded.connections = [
            IntegrationsFeature.Connection(provider: .linear, accounts: []),
            IntegrationsFeature.Connection(provider: .slack, accounts: []),
        ]
        let pendingID = UUID()
        seeded.pendingAdds = [
            IntegrationsFeature.PendingAdd(
                id: pendingID,
                provider: .linear,
                phase: .connecting
            )
        ]

        let newAccount = makeAccount(provider: .linear, displayName: "Acme Robotics")

        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }

        await store.send(.accountAdded(newAccount, pendingID: pendingID, defaultExistedAlready: false)) { state in
            state.pendingAdds = []
            state.connections[0].accounts = [
                IntegrationsFeature.AccountDisplay(account: newAccount, health: .healthy)
            ]
            state.defaults[.linear] = newAccount.id
            // No prompt — silently defaulted.
            state.pendingDefaultPrompt = nil
        }
    }

    @MainActor
    func test_accountAdded_secondForProvider_showsMakeDefaultPrompt() async {
        // Provider already has 1 account + a default.
        let existing = makeAccount(provider: .linear, displayName: "From Ink")
        var seeded = IntegrationsFeature.State()
        seeded.connections = [
            IntegrationsFeature.Connection(
                provider: .linear,
                accounts: [
                    IntegrationsFeature.AccountDisplay(account: existing, health: .healthy)
                ]
            ),
            IntegrationsFeature.Connection(provider: .slack, accounts: []),
        ]
        seeded.defaults = [.linear: existing.id]
        let pendingID = UUID()
        seeded.pendingAdds = [
            IntegrationsFeature.PendingAdd(
                id: pendingID,
                provider: .linear,
                phase: .connecting
            )
        ]

        let newAccount = makeAccount(provider: .linear, displayName: "Personal")

        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }

        await store.send(.accountAdded(newAccount, pendingID: pendingID, defaultExistedAlready: true)) { state in
            state.pendingAdds = []
            state.connections[0].accounts.append(
                IntegrationsFeature.AccountDisplay(account: newAccount, health: .healthy)
            )
            // Default stays on the original account; prompt offered.
            state.pendingDefaultPrompt = IntegrationsFeature.DefaultPrompt(
                provider: .linear,
                newAccountID: newAccount.id,
                newAccountName: "Personal",
                currentDefaultName: "From Ink"
            )
        }
    }

    // MARK: - .addAccountFailed

    @MainActor
    func test_addAccountFailed_transitionsConnectingToFailed() async {
        let pendingID = UUID()
        var seeded = seededState()
        seeded.pendingAdds = [
            IntegrationsFeature.PendingAdd(
                id: pendingID,
                provider: .linear,
                phase: .connecting
            )
        ]

        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }

        await store.send(.addAccountFailed(pendingID: pendingID, error: .permissionsDenied)) { state in
            state.pendingAdds[id: pendingID]?.phase = .failed(.permissionsDenied)
        }
    }

    // MARK: - .pendingAddRetapped

    @MainActor
    func test_pendingAddRetapped_resetsToConnecting() async {
        let pendingID = UUID()
        var seeded = seededState()
        seeded.pendingAdds = [
            IntegrationsFeature.PendingAdd(
                id: pendingID,
                provider: .linear,
                phase: .failed(.userCancelled)
            )
        ]
        seeded.mockOutcomeIndex = 0

        let clock = TestClock()
        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.pendingAddRetapped(pendingID: pendingID)) { state in
            // Phase resets and the cycle advances.
            state.pendingAdds[id: pendingID]?.phase = .connecting
            state.mockOutcomeIndex = 1
        }
    }

    // MARK: - .pendingAddDismissed

    @MainActor
    func test_pendingAddDismissed_removesRow() async {
        let pendingID = UUID()
        var seeded = seededState()
        seeded.pendingAdds = [
            IntegrationsFeature.PendingAdd(
                id: pendingID,
                provider: .linear,
                phase: .failed(.stateMismatch)
            )
        ]

        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }

        await store.send(.pendingAddDismissed(pendingID: pendingID)) { state in
            state.pendingAdds = []
        }
    }

    // MARK: - .makeDefaultTapped

    @MainActor
    func test_makeDefaultTapped_updatesDefaultAndClearsPrompt() async {
        let existing = makeAccount(provider: .linear, displayName: "From Ink")
        let newAccount = makeAccount(provider: .linear, displayName: "Personal")

        var seeded = IntegrationsFeature.State()
        seeded.connections = [
            IntegrationsFeature.Connection(
                provider: .linear,
                accounts: [
                    .init(account: existing,   health: .healthy),
                    .init(account: newAccount, health: .healthy),
                ]
            )
        ]
        seeded.defaults = [.linear: existing.id]
        seeded.pendingDefaultPrompt = IntegrationsFeature.DefaultPrompt(
            provider: .linear,
            newAccountID: newAccount.id,
            newAccountName: "Personal",
            currentDefaultName: "From Ink"
        )

        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }

        await store.send(.makeDefaultTapped) { state in
            state.defaults[.linear] = newAccount.id
            state.pendingDefaultPrompt = nil
        }
    }

    // MARK: - .keepCurrentDefaultTapped

    @MainActor
    func test_keepCurrentDefaultTapped_clearsPromptOnly() async {
        let existing = makeAccount(provider: .linear, displayName: "From Ink")
        let newAccount = makeAccount(provider: .linear, displayName: "Personal")

        var seeded = IntegrationsFeature.State()
        seeded.connections = [
            IntegrationsFeature.Connection(
                provider: .linear,
                accounts: [
                    .init(account: existing,   health: .healthy),
                    .init(account: newAccount, health: .healthy),
                ]
            )
        ]
        seeded.defaults = [.linear: existing.id]
        seeded.pendingDefaultPrompt = IntegrationsFeature.DefaultPrompt(
            provider: .linear,
            newAccountID: newAccount.id,
            newAccountName: "Personal",
            currentDefaultName: "From Ink"
        )

        let store = TestStore(initialState: seeded) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }

        await store.send(.keepCurrentDefaultTapped) { state in
            state.pendingDefaultPrompt = nil
            // Default unchanged.
        }
        XCTAssertEqual(
            store.state.defaults[.linear], existing.id,
            "keepCurrentDefaultTapped must NOT mutate defaults"
        )
    }

    // MARK: - Account row stubs are no-ops in V1

    @MainActor
    func test_accountRowTapped_isNoOp() async {
        let account = makeAccount(provider: .linear, displayName: "From Ink")
        let store = TestStore(initialState: seededState()) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }

        await store.send(.accountRowTapped(account))
    }

    @MainActor
    func test_reauthenticateTapped_isNoOp() async {
        let account = makeAccount(provider: .linear, displayName: "From Ink")
        let store = TestStore(initialState: seededState()) {
            IntegrationsFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        }

        await store.send(.reauthenticateTapped(account))
    }

    // MARK: - Fixtures

    /// State with the production mock-seed already applied. Convenient
    /// for tests that exercise interactions on top of the canonical
    /// "first launch" snapshot rather than starting from empty.
    private func seededState() -> IntegrationsFeature.State {
        var state = IntegrationsFeature.State()
        let baseDate = Date(timeIntervalSince1970: 1_777_000_000)
        let fromInk = makeAccount(
            provider: .linear, displayName: "From Ink", baseDate: baseDate
        )
        let personal = makeAccount(
            provider: .linear, displayName: "Personal", baseDate: baseDate
        )
        state.connections = [
            IntegrationsFeature.Connection(
                provider: .linear,
                accounts: [
                    .init(account: fromInk,  health: .healthy),
                    .init(account: personal, health: .healthy),
                ]
            ),
            IntegrationsFeature.Connection(provider: .slack, accounts: []),
        ]
        state.defaults = [.linear: fromInk.id]
        return state
    }

    private func makeAccount(
        provider: OAuthProvider,
        displayName: String,
        baseDate: Date = Date(timeIntervalSince1970: 1_777_000_000)
    ) -> IntegrationAccount {
        IntegrationAccount(
            provider: provider,
            displayName: displayName,
            token: OAuthToken(
                accessToken: "fixture-\(displayName)",
                refreshToken: "refresh",
                expiresAt: baseDate.addingTimeInterval(86_400),
                tokenType: "Bearer",
                scope: "read write"
            ),
            connectedAt: baseDate
        )
    }
}
