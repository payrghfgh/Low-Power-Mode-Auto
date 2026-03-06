import Foundation
import IOKit.ps

struct BatteryState {
    let percentage: Int
    let isCharging: Bool
}

final class BatteryMonitor {
    var onBatteryUpdate: ((BatteryState) -> Void)?

    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard runLoopSource == nil else { return }

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

        if let state = currentBatteryState() {
            onBatteryUpdate?(state)
        }
    }

    func stopMonitoring() {
        guard let runLoopSource else { return }

        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource.takeUnretainedValue(), .defaultMode)
        self.runLoopSource = nil
    }

    func currentBatteryState() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sourceList.first,
              let sourceDescription = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return nil
        }

        guard let currentCapacity = sourceDescription[kIOPSCurrentCapacityKey] as? Int,
              let maxCapacity = sourceDescription[kIOPSMaxCapacityKey] as? Int,
              maxCapacity > 0
        else {
            return nil
        }

        let percentage = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
        let isCharging = (sourceDescription[kIOPSIsChargingKey] as? Bool) ?? false

        return BatteryState(percentage: max(0, min(percentage, 100)), isCharging: isCharging)
    }
}
