import Foundation

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
    @Published var lastActionMessage: String = "Idle"

    var onStateUpdate: (() -> Void)?

    private let defaults: UserDefaults
    private let batteryMonitor = BatteryMonitor()
    private let lowPowerController = LowPowerModeController()
    private let chargeLimitAlertManager = ChargeLimitAlertManager()
    private let loginItemManager = LoginItemManager()
    private var isMutatingLaunchAtLogin = false
    private var lastAppliedChargeLimitPercent: Int?
    private var attemptedAutoPasswordlessRepair = false
    private var didAlertChargeLimitInCurrentCycle = false

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
        self.launchAtLogin = defaults.bool(forKey: DefaultsKeys.launchAtLogin)
        self.passwordlessSetupDone = defaults.bool(forKey: DefaultsKeys.passwordlessSetupDone)
    }

    func start() {
        autoSetupPasswordlessIfNeeded()
        chargeLimitAlertManager.prepare()
        refreshState(reason: nil)
        applyChargeLimitIfNeeded(force: true)

        batteryMonitor.onBatteryUpdate = { [weak self] state in
            Task { @MainActor in
                self?.batteryPercent = state.percentage
                self?.isCharging = state.isCharging
                self?.applyChargeLimitIfNeeded(force: false)
                self?.evaluateAndApplyPolicy()
                self?.onStateUpdate?()
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
        evaluateAndApplyPolicy(reason: reason)
    }

    func applyNow() {
        applyChargeLimitIfNeeded(force: true)
        evaluateAndApplyPolicy(reason: "Manual check")
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

    private func autoSetupPasswordlessIfNeeded() {
        let didAttempt = defaults.bool(forKey: DefaultsKeys.didAttemptAutoPasswordlessSetup)
        guard !passwordlessSetupDone, !didAttempt else { return }
        defaults.set(true, forKey: DefaultsKeys.didAttemptAutoPasswordlessSetup)
        setupPasswordlessControl()
    }

    private func applyChargeLimitIfNeeded(force: Bool = false) {
        let desiredLimit = lowPowerController.effectiveChargeLimit(percent: chargeLimitPercent)
        if !force, lastAppliedChargeLimitPercent == desiredLimit {
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
        switch result {
        case .success:
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
            lastActionMessage = "Charge limit monitoring active"
            return
        }

        if current >= limit {
            if !didAlertChargeLimitInCurrentCycle {
                chargeLimitAlertManager.notifyChargeLimitReached(limit: limit, current: current)
                didAlertChargeLimitInCurrentCycle = true
            }
            lastActionMessage = "Charge limit reached (\(current)%). Unplug charger to hold near \(limit)%"
            return
        }

        lastActionMessage = "Charge limit monitoring active (\(current)% / \(limit)%)"
    }

    private func evaluateAndApplyPolicy(reason: String? = nil) {
        defer { onStateUpdate?() }

        guard autoEnabled else {
            if let reason {
                lastActionMessage = "\(reason): Auto mode is off"
            } else {
                lastActionMessage = "Auto mode is off"
            }
            return
        }

        guard let batteryPercent else {
            lastActionMessage = "Battery state unavailable"
            return
        }

        let shouldEnable = batteryPercent <= thresholdPercent

        if shouldEnable == lowPowerModeEnabled {
            lastActionMessage = shouldEnable ? "Low Power Mode already on" : "Battery above threshold"
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
}

enum DefaultsKeys {
    static let thresholdPercent = "thresholdPercent"
    static let autoEnabled = "autoEnabled"
    static let launchAtLogin = "launchAtLogin"
    static let passwordlessSetupDone = "passwordlessSetupDone"
    static let didAttemptAutoPasswordlessSetup = "didAttemptAutoPasswordlessSetup"
    static let chargeLimitEnabled = "chargeLimitEnabled"
    static let chargeLimitPercent = "chargeLimitPercent"
}
