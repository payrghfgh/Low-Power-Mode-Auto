import Foundation

enum MenuIconStyle: String, CaseIterable, Identifiable {
    case dynamic
    case monochrome
    case bolt

    var id: String { rawValue }
}

enum ChargeGuardPreset: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case work = "Work (80%)"
    case travel = "Travel (100%)"

    var id: String { rawValue }
}

@MainActor
final class LowPowerModeViewModel: ObservableObject {
    @Published var thresholdPercent: Int {
        didSet {
            let clamped = max(5, min(thresholdPercent, 100))
            if clamped != thresholdPercent {
                thresholdPercent = clamped
                return
            }
            defaults.set(thresholdPercent, forKey: DefaultsKeys.thresholdPercent)
            evaluateAndApplyPolicy()
        }
    }

    @Published var batteryPercent: Int?
    @Published var isCharging: Bool = false
    @Published var lowPowerModeEnabled: Bool = false

    @Published var chargeLimitEnabled: Bool {
        didSet {
            defaults.set(chargeLimitEnabled, forKey: DefaultsKeys.chargeLimitEnabled)
            applyChargeLimitIfNeeded(force: true)
        }
    }
    @Published var chargeLimitPercent: Int {
        didSet {
            let clamped = max(50, min(chargeLimitPercent, 100))
            if clamped != chargeLimitPercent {
                chargeLimitPercent = clamped
                return
            }
            defaults.set(chargeLimitPercent, forKey: DefaultsKeys.chargeLimitPercent)
            applyChargeLimitIfNeeded(force: true)
        }
    }
    @Published var chargeGuardPreset: ChargeGuardPreset {
        didSet {
            defaults.set(chargeGuardPreset.rawValue, forKey: DefaultsKeys.chargeGuardPreset)
            applyChargeGuardPreset()
        }
    }

    @Published var quietHoursEnabled: Bool {
        didSet {
            defaults.set(quietHoursEnabled, forKey: DefaultsKeys.quietHoursEnabled)
        }
    }
    @Published var quietStartHour: Int {
        didSet {
            quietStartHour = max(0, min(quietStartHour, 23))
            defaults.set(quietStartHour, forKey: DefaultsKeys.quietStartHour)
        }
    }
    @Published var quietEndHour: Int {
        didSet {
            quietEndHour = max(0, min(quietEndHour, 23))
            defaults.set(quietEndHour, forKey: DefaultsKeys.quietEndHour)
        }
    }

    @Published var menuIconStyle: MenuIconStyle {
        didSet {
            defaults.set(menuIconStyle.rawValue, forKey: DefaultsKeys.menuIconStyle)
            onStateUpdate?()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isMutatingLaunchAtLogin else { return }
            defaults.set(launchAtLogin, forKey: DefaultsKeys.launchAtLogin)
            do {
                try loginItemManager.setEnabled(launchAtLogin)
            } catch {
                isMutatingLaunchAtLogin = true
                launchAtLogin = loginItemManager.isEnabled()
                isMutatingLaunchAtLogin = false
                lastActionMessage = "Failed to change launch at login: \(error.localizedDescription)"
            }
        }
    }

    @Published var autoEnabled: Bool {
        didSet {
            defaults.set(autoEnabled, forKey: DefaultsKeys.autoEnabled)
            evaluateAndApplyPolicy()
        }
    }

    @Published var passwordlessSetupDone: Bool
    @Published var notificationsAllowed: Bool = false
    @Published var onboardingDismissed: Bool {
        didSet { defaults.set(onboardingDismissed, forKey: DefaultsKeys.onboardingDismissed) }
    }

    @Published var todayMaxPercent: Int = 0
    @Published var chargingMinutesToday: Int = 0
    @Published var softwareGuardAlertsToday: Int = 0

    @Published var activeChargeBackend: String = ChargeBackend.unknown.rawValue
    @Published var lastChargeError: String = "-"
    @Published var updateStatus: String = "Not checked"
    @Published var latestVersion: String = "-"
    @Published var updateURL: String = ""

    @Published var lastActionMessage: String = "Idle"

    var onStateUpdate: (() -> Void)?

    private let defaults: UserDefaults
    private let batteryMonitor = BatteryMonitor()
    private let lowPowerController = LowPowerModeController()
    private let chargeLimitAlertManager = ChargeLimitAlertManager()
    private let loginItemManager = LoginItemManager()
    private let statsManager = BatteryStatsManager()
    private let updateChecker = UpdateChecker()

    private var isMutatingLaunchAtLogin = false
    private var lastAppliedChargeLimitPercent: Int?
    private var attemptedAutoPasswordlessRepair = false
    private var didAlertChargeLimitInCurrentCycle = false
    private var softwareGuardActive = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedThreshold = defaults.integer(forKey: DefaultsKeys.thresholdPercent)
        self.thresholdPercent = storedThreshold == 0 ? 20 : storedThreshold

        if defaults.object(forKey: DefaultsKeys.autoEnabled) == nil {
            self.autoEnabled = true
        } else {
            self.autoEnabled = defaults.bool(forKey: DefaultsKeys.autoEnabled)
        }

        if defaults.object(forKey: DefaultsKeys.chargeLimitEnabled) == nil {
            self.chargeLimitEnabled = false
        } else {
            self.chargeLimitEnabled = defaults.bool(forKey: DefaultsKeys.chargeLimitEnabled)
        }

        let storedChargeLimit = defaults.integer(forKey: DefaultsKeys.chargeLimitPercent)
        self.chargeLimitPercent = storedChargeLimit == 0 ? 80 : storedChargeLimit

        let presetRaw = defaults.string(forKey: DefaultsKeys.chargeGuardPreset) ?? ChargeGuardPreset.custom.rawValue
        self.chargeGuardPreset = ChargeGuardPreset(rawValue: presetRaw) ?? .custom

        self.quietHoursEnabled = defaults.bool(forKey: DefaultsKeys.quietHoursEnabled)
        let start = defaults.object(forKey: DefaultsKeys.quietStartHour) == nil ? 22 : defaults.integer(forKey: DefaultsKeys.quietStartHour)
        let end = defaults.object(forKey: DefaultsKeys.quietEndHour) == nil ? 7 : defaults.integer(forKey: DefaultsKeys.quietEndHour)
        self.quietStartHour = start
        self.quietEndHour = end

        let iconRaw = defaults.string(forKey: DefaultsKeys.menuIconStyle) ?? MenuIconStyle.dynamic.rawValue
        self.menuIconStyle = MenuIconStyle(rawValue: iconRaw) ?? .dynamic

        self.launchAtLogin = defaults.bool(forKey: DefaultsKeys.launchAtLogin)
        self.passwordlessSetupDone = defaults.bool(forKey: DefaultsKeys.passwordlessSetupDone)
        self.onboardingDismissed = defaults.bool(forKey: DefaultsKeys.onboardingDismissed)
    }

    var shouldShowOnboarding: Bool {
        !onboardingDismissed && (!launchAtLogin || !passwordlessSetupDone || !notificationsAllowed)
    }

    func start() {
        autoSetupPasswordlessIfNeeded()
        chargeLimitAlertManager.prepare()
        Task { await refreshNotificationPermissionState() }

        refreshState(reason: nil)
        refreshStats()
        applyChargeLimitIfNeeded(force: true)

        batteryMonitor.onBatteryUpdate = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.batteryPercent = state.percentage
                self.isCharging = state.isCharging
                self.statsManager.recordSample(percent: state.percentage, isCharging: state.isCharging)
                self.refreshStats()
                self.applyChargeLimitIfNeeded(force: false)
                self.evaluateAndApplyPolicy()
                self.onStateUpdate?()
            }
        }

        batteryMonitor.startMonitoring()
    }

    func refreshState(reason: String?) {
        if let state = batteryMonitor.currentBatteryState() {
            batteryPercent = state.percentage
            isCharging = state.isCharging
        } else {
            batteryPercent = nil
            isCharging = false
        }

        lowPowerModeEnabled = lowPowerController.isLowPowerModeEnabled()
        refreshDiagnostics()
        evaluateAndApplyPolicy(reason: reason)
    }

    func applyNow() {
        applyChargeLimitIfNeeded(force: true)
        evaluateAndApplyPolicy(reason: "Manual check")
    }

    func forceLowPowerMode() {
        let result = runWithAutoPasswordlessRepair { self.lowPowerController.setLowPowerMode(enabled: true) }
        switch result {
        case .success:
            autoEnabled = false
            lowPowerModeEnabled = true
            lastActionMessage = "Forced Low Power Mode ON"
        case let .failure(errorText):
            lastActionMessage = errorText
        }
        onStateUpdate?()
    }

    func forceNormalMode() {
        let result = runWithAutoPasswordlessRepair { self.lowPowerController.setLowPowerMode(enabled: false) }
        switch result {
        case .success:
            autoEnabled = false
            lowPowerModeEnabled = false
            lastActionMessage = "Forced Normal Mode"
        case let .failure(errorText):
            lastActionMessage = errorText
        }
        onStateUpdate?()
    }

    func setupPasswordlessControl() {
        let result = lowPowerController.configurePasswordlessSudo()
        switch result {
        case .success:
            passwordlessSetupDone = true
            defaults.set(true, forKey: DefaultsKeys.passwordlessSetupDone)
            defaults.set(true, forKey: DefaultsKeys.didAttemptAutoPasswordlessSetup)
            lastActionMessage = "Passwordless mode enabled for Low Power + charge limit control"
        case let .failure(errorText):
            lastActionMessage = errorText
        }
        onStateUpdate?()
    }

    func runOnboardingQuickSetup() {
        launchAtLogin = true
        setupPasswordlessControl()
        chargeLimitAlertManager.prepare()
        Task { await refreshNotificationPermissionState() }
        if launchAtLogin && passwordlessSetupDone {
            onboardingDismissed = true
        }
    }

    func dismissOnboarding() {
        onboardingDismissed = true
    }

    func checkForUpdates() {
        updateStatus = "Checking..."
        updateChecker.checkLatestRelease { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(info):
                    self.latestVersion = info.version
                    self.updateURL = info.url
                    self.updateStatus = "Latest release: \(info.version)"
                case let .failure(error):
                    switch error {
                    case let .message(message):
                        self.updateStatus = message
                    }
                }
            }
        }
    }

    private func autoSetupPasswordlessIfNeeded() {
        let didAttempt = defaults.bool(forKey: DefaultsKeys.didAttemptAutoPasswordlessSetup)
        guard !passwordlessSetupDone, !didAttempt else { return }
        defaults.set(true, forKey: DefaultsKeys.didAttemptAutoPasswordlessSetup)
        setupPasswordlessControl()
    }

    private func applyChargeGuardPreset() {
        switch chargeGuardPreset {
        case .custom:
            break
        case .work:
            chargeLimitEnabled = true
            chargeLimitPercent = 80
            quietHoursEnabled = true
        case .travel:
            chargeLimitEnabled = false
            chargeLimitPercent = 100
        }
        applyChargeLimitIfNeeded(force: true)
    }

    private func applyChargeLimitIfNeeded(force: Bool = false) {
        let desiredLimit = lowPowerController.effectiveChargeLimit(percent: chargeLimitPercent)

        if !force,
           lastAppliedChargeLimitPercent == desiredLimit,
           chargeLimitEnabled,
           softwareGuardActive {
            handleSoftwareChargeLimitFallback(limit: desiredLimit)
            return
        }

        let result = runWithAutoPasswordlessRepair {
            self.lowPowerController.applyChargeLimit(
                enabled: self.chargeLimitEnabled,
                percent: desiredLimit,
                batteryPercent: self.batteryPercent,
                isCharging: self.isCharging
            )
        }
        refreshDiagnostics()

        switch result {
        case .success:
            softwareGuardActive = false
            lastAppliedChargeLimitPercent = desiredLimit
            if !chargeLimitEnabled {
                didAlertChargeLimitInCurrentCycle = false
            }
            if chargeLimitEnabled {
                if isCharging && (batteryPercent ?? 0) >= desiredLimit {
                    lastActionMessage = "Charging paused at \(desiredLimit)%"
                } else {
                    lastActionMessage = "Charge limit active at \(desiredLimit)%"
                }
            } else {
                lastActionMessage = "Battery charge limit disabled"
            }
        case let .failure(errorText):
            if chargeLimitEnabled && lowPowerController.isUnsupportedChargeLimitError(errorText) {
                softwareGuardActive = true
                lowPowerController.markSoftwareGuardActive()
                refreshDiagnostics()
                handleSoftwareChargeLimitFallback(limit: desiredLimit)
            } else {
                lastActionMessage = errorText
            }
        }
    }

    private func handleSoftwareChargeLimitFallback(limit: Int) {
        let current = batteryPercent ?? 0
        let resetThreshold = max(0, limit - 3)

        if !chargeLimitEnabled || !isCharging || current <= resetThreshold {
            didAlertChargeLimitInCurrentCycle = false
            lastActionMessage = "Charge limit software guard active"
            return
        }

        if current >= limit {
            if !didAlertChargeLimitInCurrentCycle {
                if !isInQuietHours() {
                    chargeLimitAlertManager.notifyChargeLimitReached(limit: limit, current: current)
                }
                statsManager.recordSoftwareGuardAlert()
                refreshStats()
                didAlertChargeLimitInCurrentCycle = true
            }
            lastActionMessage = "Charge limit reached (\(current)%). Unplug charger to hold near \(limit)%"
            return
        }

        lastActionMessage = "Charge guard active (\(current)% / \(limit)%)"
    }

    private func evaluateAndApplyPolicy(reason: String? = nil) {
        defer { onStateUpdate?() }

        guard autoEnabled else {
            if let reason {
                lastActionMessage = "\(reason): Auto mode is off"
            }
            return
        }

        guard let batteryPercent else {
            lastActionMessage = "Battery state unavailable"
            return
        }

        let shouldEnable = batteryPercent <= thresholdPercent

        if shouldEnable == lowPowerModeEnabled {
            return
        }

        let result = runWithAutoPasswordlessRepair {
            self.lowPowerController.setLowPowerMode(enabled: shouldEnable)
        }
        switch result {
        case .success:
            lowPowerModeEnabled = shouldEnable
            lastActionMessage = shouldEnable ? "Enabled Low Power Mode" : "Disabled Low Power Mode"
        case let .failure(errorText):
            lastActionMessage = errorText
        }
    }

    private func runWithAutoPasswordlessRepair(_ operation: () -> CommandResult) -> CommandResult {
        let initial = operation()
        guard case let .failure(errorText) = initial else {
            return initial
        }
        guard errorText.localizedCaseInsensitiveContains("One-time admin setup required"),
              !attemptedAutoPasswordlessRepair else {
            return initial
        }

        attemptedAutoPasswordlessRepair = true
        let setupResult = lowPowerController.configurePasswordlessSudo()
        switch setupResult {
        case .success:
            passwordlessSetupDone = true
            defaults.set(true, forKey: DefaultsKeys.passwordlessSetupDone)
            defaults.set(true, forKey: DefaultsKeys.didAttemptAutoPasswordlessSetup)
            return operation()
        case let .failure(setupError):
            return .failure(setupError)
        }
    }

    private func refreshStats() {
        let stats = statsManager.currentStats()
        todayMaxPercent = stats.todayMaxPercent
        chargingMinutesToday = stats.chargingMinutesToday
        softwareGuardAlertsToday = stats.softwareGuardAlertsToday
    }

    private func refreshDiagnostics() {
        activeChargeBackend = lowPowerController.lastChargeBackend.rawValue
        lastChargeError = lowPowerController.lastChargeError ?? "-"
    }

    private func refreshNotificationPermissionState() async {
        notificationsAllowed = await chargeLimitAlertManager.refreshAuthorizationStatus()
    }

    private func isInQuietHours() -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        if quietStartHour == quietEndHour {
            return true
        }
        if quietStartHour < quietEndHour {
            return (quietStartHour..<quietEndHour).contains(hour)
        }
        return hour >= quietStartHour || hour < quietEndHour
    }
}

enum DefaultsKeys {
    static let thresholdPercent = "thresholdPercent"
    static let autoEnabled = "autoEnabled"
    static let launchAtLogin = "launchAtLogin"
    static let passwordlessSetupDone = "passwordlessSetupDone"
    static let didAttemptAutoPasswordlessSetup = "didAttemptAutoPasswordlessSetup"
    static let chargeLimitEnabled = "chargeLimitEnabled"
    static let chargeLimitPercent = "chargeLimitPercent"
    static let chargeGuardPreset = "chargeGuardPreset"
    static let quietHoursEnabled = "quietHoursEnabled"
    static let quietStartHour = "quietStartHour"
    static let quietEndHour = "quietEndHour"
    static let menuIconStyle = "menuIconStyle"
    static let onboardingDismissed = "onboardingDismissed"
}
