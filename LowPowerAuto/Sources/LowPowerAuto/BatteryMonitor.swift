import Foundation
import IOKit.ps

struct BatteryState {
    let percentage: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let minutesToFullCharge: Int?
}

final class BatteryMonitor {
    var onBatteryUpdate: ((BatteryState) -> Void)?

    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard runLoopSource == nil, pollTimer == nil else { return }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            if let state = monitor.currentBatteryState() {
                monitor.onBatteryUpdate?(state)
            }
        }

        let source = IOPSNotificationCreateRunLoopSource(callback, context)
        runLoopSource = source

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source.takeUnretainedValue(), .defaultMode)
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self, let state = self.currentBatteryState() else { return }
            self.onBatteryUpdate?(state)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        if let state = currentBatteryState() {
            onBatteryUpdate?(state)
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil

        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource.takeUnretainedValue(), .defaultMode)
        self.runLoopSource = nil
    }

    func currentBatteryState() -> BatteryState? {
        if let pmsetState = currentBatteryStateFromPMSet() {
            return pmsetState
        }

        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sourceList {
            guard let sourceDescription = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let powerSourceType = sourceDescription[kIOPSTypeKey] as? String
            if powerSourceType != kIOPSInternalBatteryType {
                continue
            }

            guard let currentCapacity = sourceDescription[kIOPSCurrentCapacityKey] as? Int,
                  let maxCapacity = sourceDescription[kIOPSMaxCapacityKey] as? Int,
                  maxCapacity > 0
            else {
                continue
            }

            let percentage = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
            let isCharging = (sourceDescription[kIOPSIsChargingKey] as? Bool) ?? false
            let powerSourceState = (sourceDescription[kIOPSPowerSourceStateKey] as? String) ?? ""
            let isPluggedIn = (powerSourceState == kIOPSACPowerValue)
            let minutesToFullCharge: Int? = {
                guard let value = sourceDescription[kIOPSTimeToFullChargeKey] as? Int, value >= 0 else {
                    return nil
                }
                return value
            }()

            return BatteryState(
                percentage: max(0, min(percentage, 100)),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                minutesToFullCharge: minutesToFullCharge
            )
        }

        return nil
    }

    private func currentBatteryStateFromPMSet() -> BatteryState? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "batt"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        guard let percentRange = text.range(of: #"(\d+)%"#, options: .regularExpression) else {
            return nil
        }
        let percentString = String(text[percentRange]).replacingOccurrences(of: "%", with: "")
        guard let percent = Int(percentString) else { return nil }

        let battLine = text
            .split(separator: "\n")
            .first(where: { $0.contains("%") })
            .map(String.init) ?? ""

        let statusToken: String = {
            guard let range = battLine.range(of: #"%\s*;\s*([^;]+)\s*;"#, options: .regularExpression) else {
                return ""
            }
            let segment = String(battLine[range])
            return segment
                .replacingOccurrences(of: "%;", with: "")
                .replacingOccurrences(of: ";", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }()

        let charging: Bool
        if statusToken.contains("not charging") || statusToken.contains("discharging") || statusToken.contains("charged") {
            charging = false
        } else if statusToken.contains("charging") || statusToken.contains("finishing charge") {
            charging = true
        } else {
            charging = false
        }

        let lowered = text.lowercased()
        let isPluggedIn = lowered.contains("now drawing from 'ac power'") || lowered.contains("ac attached")
        let minutesToFullCharge: Int? = {
            guard charging else { return nil }
            guard let match = battLine.range(of: #"(\d+):(\d+)"#, options: .regularExpression) else {
                return nil
            }
            let segment = String(battLine[match])
            let parts = segment.split(separator: ":")
            guard parts.count == 2,
                  let hours = Int(parts[0]),
                  let minutes = Int(parts[1]) else {
                return nil
            }
            return (hours * 60) + minutes
        }()

        return BatteryState(
            percentage: max(0, min(percent, 100)),
            isCharging: charging,
            isPluggedIn: isPluggedIn,
            minutesToFullCharge: minutesToFullCharge
        )
    }
}
