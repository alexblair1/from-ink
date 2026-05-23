import ComposableArchitecture

/// Bridge from `StoreOf<IntegrationsFeature>` into the stateless
/// `IntegrationsListView.Model`. Keeps the view tier TCA-free —
/// every callback resolves to `store.send(...)` once, here.
///
extension IntegrationsListView.Model {
    init(
        store: StoreOf<IntegrationsFeature>,
        header: SettingsDetailHeader.Model
    ) {
        self.header = header
        self.title = AppStrings.Settings.integrationsScreenTitle

        let totalProviders = OAuthProvider.allCases.count
        let connectedProviders = store.connections.filter { !$0.accounts.isEmpty }.count
        self.countChip = AppStrings.Settings.integrationsCountChip(connectedProviders, of: totalProviders)

        // Per-provider section construction — encapsulated below.
        self.providerSections = store.connections.map { connection in
            IntegrationProviderSection.Model(
                store: store,
                connection: connection
            )
        }

        // "Make default?" card — non-nil only when the feature's
        // pendingDefaultPrompt has data.
        if let prompt = store.pendingDefaultPrompt {
            self.defaultPromptCard = IntegrationDefaultPromptCard.Model(
                caption: AppStrings.Settings.integrationsDefaultCaption,
                question: AppStrings.Settings.integrationsDefaultQuestion(prompt.newAccountName),
                keepCurrentLabel: AppStrings.Settings.integrationsDefaultKeep(prompt.currentDefaultName),
                switchLabel: AppStrings.Settings.integrationsDefaultSwitch,
                onMakeDefault: { store.send(.makeDefaultTapped) },
                onKeepCurrent: { store.send(.keepCurrentDefaultTapped) }
            )
        } else {
            self.defaultPromptCard = nil
        }
    }
}

// MARK: - Provider section adapter

extension IntegrationProviderSection.Model {
    fileprivate init(
        store: StoreOf<IntegrationsFeature>,
        connection: IntegrationsFeature.Connection
    ) {
        let provider = connection.provider
        let pendingForProvider = store.pendingAdds.filter { $0.provider == provider }
        let isAdding = pendingForProvider.contains { $0.phase == .connecting }

        self.id = provider
        self.headerTitle = providerLabel(provider) + (isAdding ? AppStrings.Settings.integrationsAddingSuffix : "")

        let defaultID = store.defaults[provider]

        self.accounts = connection.accounts.map { display in
            IntegrationAccountRow.Model(
                display: display,
                isDefault: display.account.id == defaultID,
                store: store
            )
        }

        self.pendingRows = pendingForProvider.map { pending in
            IntegrationPendingRow.Model(pending: pending, store: store)
        }

        self.addAccountRow = IntegrationAddAccountRow.Model(
            label: AppStrings.Settings.integrationsAddAccount,
            onTap: { store.send(.addAccountTapped(provider)) }
        )
    }
}

// MARK: - Account row adapter

extension IntegrationAccountRow.Model {
    fileprivate init(
        display: IntegrationsFeature.AccountDisplay,
        isDefault: Bool,
        store: StoreOf<IntegrationsFeature>
    ) {
        let account = display.account
        self.id = account.id
        self.name = account.displayName
        self.email = account.token.scope ?? ""    // V1: scope acts as a placeholder
                                                  // for the email-like trailing text
                                                  // until real identity fetch lands.
        self.isDefault = isDefault
        self.reauthLabel = AppStrings.Settings.integrationsReauthenticate

        switch display.health {
        case .healthy, .expiringSoon:
            self.status = .healthy
        case .expired, .reconnectRequired:
            self.status = .reauthRequired
        }

        self.onTap = { store.send(.accountRowTapped(account)) }
        self.onReauthTap = { store.send(.reauthenticateTapped(account)) }
    }
}

// MARK: - Pending row adapter

extension IntegrationPendingRow.Model {
    fileprivate init(
        pending: IntegrationsFeature.PendingAdd,
        store: StoreOf<IntegrationsFeature>
    ) {
        self.id = pending.id
        self.title = AppStrings.Settings.integrationsPendingConnecting
        self.accessibilityLabel = "\(providerLabel(pending.provider)) — \(pending.phase.accessibilityDescription)"

        switch pending.phase {
        case .connecting:
            self.statusText = AppStrings.Settings.integrationsStatusPKCE
            self.statusKind = .live
            self.onPrimaryTap = { /* in-flight; tap is a no-op */ }
        case .failed(let error):
            switch error {
            case .userCancelled:
                self.statusText = AppStrings.Settings.integrationsStatusCancelled
                self.statusKind = .neutral
                self.onPrimaryTap = { store.send(.pendingAddRetapped(pendingID: pending.id)) }
            case .permissionsDenied:
                self.statusText = AppStrings.Settings.integrationsStatusPermissionsDenied
                self.statusKind = .attention
                self.onPrimaryTap = { store.send(.pendingAddRetapped(pendingID: pending.id)) }
            case .network:
                self.statusText = AppStrings.Settings.integrationsStatusNoConnection
                self.statusKind = .attention
                self.onPrimaryTap = { store.send(.pendingAddRetapped(pendingID: pending.id)) }
            case .stateMismatch:
                // No auto-retry per the design. Primary tap dismisses
                // the row; user must initiate a fresh "+ Add account".
                self.statusText = AppStrings.Settings.integrationsStatusCouldntVerify
                self.statusKind = .attention
                self.onPrimaryTap = { store.send(.pendingAddDismissed(pendingID: pending.id)) }
            }
        }
    }
}

// MARK: - Provider label

/// Localized provider name. Falls back to the rawValue, capitalized,
/// for any provider we don't have a translated string for yet.
private func providerLabel(_ provider: OAuthProvider) -> String {
    switch provider {
    case .linear: AppStrings.Settings.integrationsProviderLinear
    case .slack:  AppStrings.Settings.integrationsProviderSlack
    }
}

// MARK: - Phase accessibility

private extension IntegrationsFeature.PendingAdd.Phase {
    /// Spoken description for VoiceOver. Matches the visible status
    /// label semantically without re-reading the literal mono text.
    var accessibilityDescription: String {
        switch self {
        case .connecting:                  return AppStrings.Settings.integrationsPendingConnecting
        case .failed(.userCancelled):      return AppStrings.Settings.integrationsStatusCancelled
        case .failed(.permissionsDenied):  return AppStrings.Settings.integrationsStatusPermissionsDenied
        case .failed(.network):            return AppStrings.Settings.integrationsStatusNoConnection
        case .failed(.stateMismatch):      return AppStrings.Settings.integrationsStatusCouldntVerify
        }
    }
}
