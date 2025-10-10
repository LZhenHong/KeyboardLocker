import Core

/// Application dependency container
/// Responsible for creating and managing all dependencies, ensuring single responsibility and clear dependency flow
final class AppDependencies {
  // MARK: - Core Dependencies (from Core module)

  let keyboardCore: KeyboardLockCore
  let coreConfiguration: CoreConfiguration
  let activityMonitor: UserActivityMonitor

  // MARK: - UI Layer Dependencies

  let notificationManager: NotificationManager
  let permissionManager: PermissionManager
  let urlHandler: URLCommandHandler
  let keyboardLockManager: KeyboardLockManager

  // MARK: - Initialization

  init() {
    // 1. Initialize Core dependencies (keep as singletons since they are system-level resources)
    keyboardCore = KeyboardLockCore.shared
    coreConfiguration = CoreConfiguration.shared
    activityMonitor = UserActivityMonitor.shared

    // 2. Initialize UI layer dependencies (prioritize those without dependencies)
    notificationManager = NotificationManager()

    // 3. Initialize components with dependencies
    permissionManager = PermissionManager(notificationManager: notificationManager)

    // 4. Initialize managers
    keyboardLockManager = KeyboardLockManager(
      core: keyboardCore,
      config: coreConfiguration,
      activityMonitor: activityMonitor,
      notificationManager: notificationManager
    )

    // 5. Initialize URL handler
    urlHandler = URLCommandHandler(
      keyboardLockManager: keyboardLockManager,
      notificationManager: notificationManager
    )
  }
}

/// Global application dependency instance
/// Created once at app startup and passed to components that need dependencies
let appDependencies = AppDependencies()
