import BackgroundTasks
import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "BackgroundRefresh")

/// Task identifier registered in Info.plist BGTaskSchedulerPermittedIdentifiers.
let backgroundTokenRefreshTaskID = "com.fromink.app.token-refresh"

/// 24-hour sweep threshold — refresh any token expiring within the next day.
/// This keeps Slack's 30-day refresh token alive as long as iOS schedules
/// the task at least once every ~29 days (typically runs daily).
private let backgroundSweepThreshold: TimeInterval = 24 * 3600

/// TCA dependency for background token refresh scheduling.
/// Wraps BGTaskScheduler registration and submission.
///
struct BackgroundTokenRefreshService: Sendable {
    var register: @Sendable () -> Void
    var scheduleNext: @Sendable () -> Void
}

// MARK: - DependencyKey

extension BackgroundTokenRefreshService: DependencyKey {
    static let liveValue = BackgroundTokenRefreshService(
        register: {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: backgroundTokenRefreshTaskID,
                using: nil
            ) { task in
                guard let refreshTask = task as? BGAppRefreshTask else { return }
                handleBackgroundRefresh(refreshTask)
            }
            log.info("Registered background token refresh task")
        },
        scheduleNext: {
            let request = BGAppRefreshTaskRequest(
                identifier: backgroundTokenRefreshTaskID
            )
            // Request earliest: 12 hours from now. iOS decides the actual timing.
            request.earliestBeginDate = Date(
                timeIntervalSinceNow: 12 * 3600
            )
            do {
                try BGTaskScheduler.shared.submit(request)
                log.info("Scheduled next background token refresh")
            } catch {
                log.error("Failed to schedule background refresh: \(error)")
            }
        }
    )

    static let testValue = BackgroundTokenRefreshService(
        register: { },
        scheduleNext: { }
    )
}

// MARK: - DependencyValues

extension DependencyValues {
    var backgroundTokenRefresh: BackgroundTokenRefreshService {
        get { self[BackgroundTokenRefreshService.self] }
        set { self[BackgroundTokenRefreshService.self] = newValue }
    }
}

// MARK: - Task handler

private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
    @Dependency(\.oauthService) var oauthService

    let workTask = Task {
        await oauthService.sweepExpiring(backgroundSweepThreshold)
    }

    task.expirationHandler = {
        workTask.cancel()
    }

    Task {
        await workTask.value
        task.setTaskCompleted(success: true)

        // Re-schedule the next run.
        @Dependency(\.backgroundTokenRefresh) var bgRefresh
        bgRefresh.scheduleNext()

        log.info("Background token refresh completed")
    }
}
