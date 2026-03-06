import Foundation

struct BatteryStats {
    let todayMaxPercent: Int
    let chargingMinutesToday: Int
    let softwareGuardAlertsToday: Int
}

@MainActor
final class BatteryStatsManager {
    private let defaults: UserDefaults
    private var lastSampleDate: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordSample(percent: Int?, isCharging: Bool) {
        rotateIfDateChanged()

        if let percent {
            let currentMax = defaults.integer(forKey: StatsKeys.todayMaxPercent)
            if percent > currentMax {
                defaults.set(percent, forKey: StatsKeys.todayMaxPercent)
            }
        }

        defer { lastSampleDate = Date() }
        guard isCharging else { return }
        guard let lastSampleDate else { return }

        let deltaMinutes = max(0, Int(Date().timeIntervalSince(lastSampleDate) / 60.0))
        guard deltaMinutes > 0 else { return }

        let total = defaults.integer(forKey: StatsKeys.chargingMinutesToday) + deltaMinutes
        defaults.set(total, forKey: StatsKeys.chargingMinutesToday)
    }

    func recordSoftwareGuardAlert() {
        rotateIfDateChanged()
        let count = defaults.integer(forKey: StatsKeys.softwareGuardAlertsToday) + 1
        defaults.set(count, forKey: StatsKeys.softwareGuardAlertsToday)
    }

    func currentStats() -> BatteryStats {
        rotateIfDateChanged()
        return BatteryStats(
            todayMaxPercent: defaults.integer(forKey: StatsKeys.todayMaxPercent),
            chargingMinutesToday: defaults.integer(forKey: StatsKeys.chargingMinutesToday),
            softwareGuardAlertsToday: defaults.integer(forKey: StatsKeys.softwareGuardAlertsToday)
        )
    }

    private func rotateIfDateChanged() {
        let today = Self.dateStamp(Date())
        let stored = defaults.string(forKey: StatsKeys.dateStamp)
        guard stored != today else { return }

        defaults.set(today, forKey: StatsKeys.dateStamp)
        defaults.set(0, forKey: StatsKeys.todayMaxPercent)
        defaults.set(0, forKey: StatsKeys.chargingMinutesToday)
        defaults.set(0, forKey: StatsKeys.softwareGuardAlertsToday)
    }

    private static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

enum StatsKeys {
    static let dateStamp = "statsDateStamp"
    static let todayMaxPercent = "statsTodayMaxPercent"
    static let chargingMinutesToday = "statsChargingMinutesToday"
    static let softwareGuardAlertsToday = "statsSoftwareGuardAlertsToday"
}
