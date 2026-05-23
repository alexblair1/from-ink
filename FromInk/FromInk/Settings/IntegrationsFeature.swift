import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "Integrations")

/// TCA feature for the Integrations sub-screen of Settings.
///
/// **V1 scope: UI only.** The reducer's `addAccountTapped` effect
/// simulates the OAuth lifecycle locally — no `OAuthService` /
/// `KeychainService` calls. Each tap cycles through outcomes (success,
/// cancelled, permissions denied, network failure, state mismatch)
/// so every row state can be exercised on device without an OAuth
/// provider being reachable. When the OAuth layer integrates, the
/// mock effect inside `.addAccountTapped` / `.pendingAddRetapped`
/// is replaced with `oauthService.authorize(config)` + the same
/// error mapping; everything else stays.
///
/// Data model follows the Add-Account-Flow design's in-list state
/// machine: row mutations show every phase (connecting / verifying /
/// each error variant) rather than spawning auth-result modals.
///
struct IntegrationsFeature: Reducer {

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        /// One Connection per supported provider, regardless of how
        /// many accounts each has. Stable order = `OAuthProvider.allCases`.
        var connections: [Connection] = []

        /// In-flight add operations. Each PendingAdd renders as a row
        /// inside its provider's group. Stable `id` survives the
        /// connecting → failed → retry → connecting cycle without
        /// remounting the row.
        var pendingAdds: IdentifiedArrayOf<PendingAdd> = []

        /// "Make default?" prompt card — non-nil only just after a
        /// 2nd+ account is added for an already-populated provider.
        var pendingDefaultPrompt: DefaultPrompt?

        /// Per-provider default account IDs. Persisted via
        /// UserPreferences in the production wiring (V2 work);
        /// in-memory only for V1 UI scope.
        var defaults: [OAuthProvider: UUID] = [:]

        /// Cycles through simulated outcomes so the UI can demonstrate
        /// every row state without an OAuth provider being reachable.
        /// Removed when the OAuth layer integrates.
        var mockOutcomeIndex: Int = 0
    }

    /// Per-provider rollup of accounts + their health.
    struct Connection: Equatable, Identifiable {
        let provider: OAuthProvider
        var accounts: [AccountDisplay]
        var id: OAuthProvider { provider }
    }

    /// Account + its derived health state. Pairs the persisted record
    /// with the time-dependent "do I need to look in here?" signal
    /// the design's right column surfaces ("Re-authenticate").
    struct AccountDisplay: Equatable, Identifiable {
        let account: IntegrationAccount
        let health: TokenHealth
        var id: UUID { account.id }
    }

    /// In-flight add-account attempt.
    struct PendingAdd: Equatable, Identifiable {
        let id: UUID
        let provider: OAuthProvider
        var phase: Phase

        enum Phase: Equatable {
            case connecting                    // verifier + browser + token exchange
            case failed(AddAccountError)       // user sees a tappable error row
        }
    }

    /// Make-default question card. Only shown when adding the 2nd+
    /// account for a provider that already has a default.
    struct DefaultPrompt: Equatable {
        let provider: OAuthProvider
        let newAccountID: UUID
        let newAccountName: String
        let currentDefaultName: String
    }

    /// User-recoverable failure modes from the OAuth handoff. Each
    /// maps to a distinct row label + recovery semantic per the design.
    enum AddAccountError: Equatable {
        case userCancelled        // "Cancelled"           neutral, retry on tap
        case permissionsDenied    // "Permissions denied"  flag-red, retry on tap
        case network              // "No connection"       flag-red, retry on tap
        case stateMismatch        // "Couldn't verify"     flag-red, NO auto-retry
    }

    // MARK: - Action

    @CasePathable
    enum Action: Equatable {
        case appeared
        case mockConnectionsLoaded([Connection], defaults: [OAuthProvider: UUID])

        // Add-account lifecycle
        case addAccountTapped(OAuthProvider)
        case accountAdded(IntegrationAccount, pendingID: UUID, defaultExistedAlready: Bool)
        case addAccountFailed(pendingID: UUID, error: AddAccountError)
        case pendingAddRetapped(pendingID: UUID)
        case pendingAddDismissed(pendingID: UUID)

        // Defaults
        case makeDefaultTapped
        case keepCurrentDefaultTapped
        case defaultPromptDismissed

        // Existing-account interactions (stubs for V1; route into
        // detail screens / re-auth flows when those features land)
        case accountRowTapped(IntegrationAccount)
        case reauthenticateTapped(IntegrationAccount)
    }

    // MARK: - Dependencies

    /// Continuous clock injected so the simulated 1.5s delay can be
    /// advanced deterministically in tests. Production (`liveValue`)
    /// uses real time; tests pass a `TestClock` and call `advance(by:)`.
    @Dependency(\.continuousClock) var clock

    /// UUID generator injected so pendingAdd IDs are deterministic
    /// in tests. Production uses `.uuid` (random); tests pass
    /// `.incrementing` to receive sequential IDs starting at zero.
    @Dependency(\.uuid) var uuid

    // MARK: - Body

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                // V1: seed deterministic mock data so every row state
                // is visible on first load. Replace with
                // keychain + UserPreferences fetch when OAuth lands.
                return .run { send in
                    let mocks = mockSeedConnections()
                    let defaults = mockSeedDefaults(connections: mocks)
                    await send(.mockConnectionsLoaded(mocks, defaults: defaults))
                }
                .cancellable(id: "integrationsAppeared", cancelInFlight: true)

            case .mockConnectionsLoaded(let connections, let defaults):
                state.connections = connections
                state.defaults = defaults
                return .none

            case .addAccountTapped(let provider):
                let pendingID = uuid()
                state.pendingAdds.append(PendingAdd(
                    id: pendingID, provider: provider, phase: .connecting
                ))
                let outcome = MockOutcome.cycle(state.mockOutcomeIndex)
                state.mockOutcomeIndex += 1
                let defaultExisted = state.defaults[provider] != nil
                return simulateAddAccount(
                    clock: clock,
                    provider: provider,
                    pendingID: pendingID,
                    outcome: outcome,
                    defaultExisted: defaultExisted
                )

            case .accountAdded(let account, let pendingID, let defaultExistedAlready):
                state.pendingAdds.remove(id: pendingID)
                if let index = state.connections.firstIndex(where: { $0.provider == account.provider }) {
                    state.connections[index].accounts.append(
                        AccountDisplay(account: account, health: .healthy)
                    )
                }
                if defaultExistedAlready,
                   let currentDefaultID = state.defaults[account.provider],
                   let currentDefault = state.connections
                       .flatMap(\.accounts)
                       .first(where: { $0.id == currentDefaultID })?
                       .account
                {
                    state.pendingDefaultPrompt = DefaultPrompt(
                        provider: account.provider,
                        newAccountID: account.id,
                        newAccountName: account.displayName,
                        currentDefaultName: currentDefault.displayName
                    )
                } else {
                    // First account for this provider — silently default to it.
                    state.defaults[account.provider] = account.id
                }
                return .none

            case .addAccountFailed(let pendingID, let error):
                if let index = state.pendingAdds.index(id: pendingID) {
                    state.pendingAdds[index].phase = .failed(error)
                }
                return .none

            case .pendingAddRetapped(let pendingID):
                guard let pending = state.pendingAdds[id: pendingID] else { return .none }
                state.pendingAdds[id: pendingID]?.phase = .connecting
                let outcome = MockOutcome.cycle(state.mockOutcomeIndex)
                state.mockOutcomeIndex += 1
                let defaultExisted = state.defaults[pending.provider] != nil
                return simulateAddAccount(
                    clock: clock,
                    provider: pending.provider,
                    pendingID: pendingID,
                    outcome: outcome,
                    defaultExisted: defaultExisted
                )

            case .pendingAddDismissed(let pendingID):
                state.pendingAdds.remove(id: pendingID)
                return .none

            case .makeDefaultTapped:
                if let prompt = state.pendingDefaultPrompt {
                    state.defaults[prompt.provider] = prompt.newAccountID
                }
                state.pendingDefaultPrompt = nil
                return .none

            case .keepCurrentDefaultTapped,
                 .defaultPromptDismissed:
                state.pendingDefaultPrompt = nil
                return .none

            case .accountRowTapped, .reauthenticateTapped:
                // Stub. Detail navigation / re-auth flow land with the
                // OAuth integration. No state change for V1.
                return .none
            }
        }
    }
}

// MARK: - Effect: simulated add-account

/// Top-level so the reducer body stays declarative. Returns an
/// `Effect<Action>` that sleeps ~1.5s, then either reports success or
/// one of the four error modes per the cyclic outcome generator.
///
/// Replace this entire helper with a call to
/// `oauthService.authorize(OAuthProviderConfig.config(for: provider))`
/// when the OAuth layer integrates — error mapping in the catch arms
/// stays identical.
private func simulateAddAccount(
    clock: any Clock<Duration>,
    provider: OAuthProvider,
    pendingID: UUID,
    outcome: MockOutcome,
    defaultExisted: Bool
) -> Effect<IntegrationsFeature.Action> {
    .run { send in
        try? await clock.sleep(for: .seconds(1.5))
        switch outcome {
        case .success:
            let account = mockNewAccount(provider: provider)
            await send(.accountAdded(
                account,
                pendingID: pendingID,
                defaultExistedAlready: defaultExisted
            ))
        case .userCancelled:
            await send(.addAccountFailed(pendingID: pendingID, error: .userCancelled))
        case .permissionsDenied:
            await send(.addAccountFailed(pendingID: pendingID, error: .permissionsDenied))
        case .network:
            await send(.addAccountFailed(pendingID: pendingID, error: .network))
        case .stateMismatch:
            await send(.addAccountFailed(pendingID: pendingID, error: .stateMismatch))
        }
    }
    .cancellable(id: "oauthAuthorize-\(pendingID)", cancelInFlight: true)
}

// MARK: - Mock outcome cycler

/// V1 helper. Cycles through every distinct add-account outcome so
/// the user can tap "+ Add account" repeatedly and see each row
/// state on device. Removed when the OAuth layer integrates.
enum MockOutcome: Equatable {
    case success
    case userCancelled
    case permissionsDenied
    case network
    case stateMismatch

    static let cycle: [MockOutcome] = [
        .success,
        .userCancelled,
        .permissionsDenied,
        .network,
        .stateMismatch
    ]

    static func cycle(_ index: Int) -> MockOutcome {
        cycle[index % cycle.count]
    }
}

// MARK: - Mock seed data

/// Two providers, four accounts. One Linear account has expired
/// tokens so the "Re-authenticate" row state is visible on first
/// load without any user interaction.
private func mockSeedConnections() -> [IntegrationsFeature.Connection] {
    let baseDate = Date(timeIntervalSince1970: 1_777_000_000)

    let linearFromInk = IntegrationsFeature.AccountDisplay(
        account: IntegrationAccount(
            provider: .linear,
            displayName: "From Ink",
            token: OAuthToken(
                accessToken: "stub-linear-fromink",
                refreshToken: "refresh",
                expiresAt: baseDate.addingTimeInterval(86_400),
                tokenType: "Bearer",
                scope: "read write"
            ),
            connectedAt: baseDate
        ),
        health: .healthy
    )

    let linearPersonal = IntegrationsFeature.AccountDisplay(
        account: IntegrationAccount(
            provider: .linear,
            displayName: "Personal",
            token: OAuthToken(
                accessToken: "stub-linear-personal",
                refreshToken: "refresh",
                expiresAt: baseDate.addingTimeInterval(86_400),
                tokenType: "Bearer",
                scope: "read write"
            ),
            connectedAt: baseDate
        ),
        health: .healthy
    )

    let linearQuartz = IntegrationsFeature.AccountDisplay(
        account: IntegrationAccount(
            provider: .linear,
            displayName: "Quartz Labs",
            token: OAuthToken(
                accessToken: "stub-linear-quartz",
                refreshToken: nil,                    // refresh missing → reconnect required
                expiresAt: baseDate.addingTimeInterval(-86_400),
                tokenType: "Bearer",
                scope: "read write"
            ),
            connectedAt: baseDate
        ),
        health: .reconnectRequired
    )

    let slackAcme = IntegrationsFeature.AccountDisplay(
        account: IntegrationAccount(
            provider: .slack,
            displayName: "Acme",
            token: OAuthToken(
                accessToken: "stub-slack-acme",
                refreshToken: nil,
                expiresAt: nil,
                tokenType: "Bearer",
                scope: "channels:read"
            ),
            connectedAt: baseDate
        ),
        health: .healthy
    )

    return [
        IntegrationsFeature.Connection(
            provider: .linear,
            accounts: [linearFromInk, linearPersonal, linearQuartz]
        ),
        IntegrationsFeature.Connection(
            provider: .slack,
            accounts: [slackAcme]
        ),
    ]
}

/// First-listed healthy account per provider becomes the default.
/// In production this comes from UserPreferences.
private func mockSeedDefaults(
    connections: [IntegrationsFeature.Connection]
) -> [OAuthProvider: UUID] {
    var defaults: [OAuthProvider: UUID] = [:]
    for connection in connections {
        if let healthy = connection.accounts.first(where: { $0.health == .healthy }) {
            defaults[connection.provider] = healthy.id
        }
    }
    return defaults
}

/// Cycling display names so repeated mock successes don't all show
/// the same fake account. Removed with the OAuth integration.
private func mockNewAccount(provider: OAuthProvider) -> IntegrationAccount {
    let candidates: [String]
    switch provider {
    case .linear: candidates = ["Acme Robotics", "Atlas Foundry", "North Star", "Wayfinder"]
    case .slack:  candidates = ["Indigo Co.", "Wavelength", "Quartz Labs", "Northwind"]
    }
    let pick = candidates.randomElement() ?? "New Workspace"
    return IntegrationAccount(
        provider: provider,
        displayName: pick,
        token: OAuthToken(
            accessToken: "stub-new-\(UUID().uuidString)",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            tokenType: "Bearer",
            scope: "read write"
        ),
        connectedAt: Date()
    )
}
