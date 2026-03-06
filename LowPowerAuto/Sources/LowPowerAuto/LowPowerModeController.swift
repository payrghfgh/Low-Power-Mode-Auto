import Foundation
import Darwin

enum CommandResult {
    case success
    case failure(String)
}

enum ChargeBackend: String {
    case nativeBclm = "Native bclm"
    case pmsetBclm = "pmset bclm"
    case pmsetInhibit = "pmset chargeInhibit"
    case softwareGuard = "Software guard"
    case disabled = "Disabled"
    case unknown = "Unknown"
}

final class LowPowerModeController {
    private(set) var lastChargeBackend: ChargeBackend = .unknown
    private(set) var lastChargeError: String?

    func effectiveChargeLimit(percent: Int) -> Int {
        let clamped = max(50, min(percent, 100))
        if isAppleSilicon() {
            return clamped <= 80 ? 80 : 100
        }
        return clamped
    }

    func isLowPowerModeEnabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: outputData, encoding: .utf8) else { return false }

            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("lowpowermode") {
                    return trimmed.hasSuffix("1")
                }
            }
        } catch {
            return false
        }

        return false
    }

    func setLowPowerMode(enabled: Bool) -> CommandResult {
        let target = enabled ? "1" : "0"
        let result = runPrivilegedPmset(arguments: ["-a", "lowpowermode", target])
        switch result {
        case .success:
            return .success
        case let .failure(errorText):
            return .failure("Failed to set Low Power Mode: \(errorText)")
        }
    }

    func applyChargeLimit(
        enabled: Bool,
        percent: Int,
        batteryPercent: Int?,
        isCharging: Bool
    ) -> CommandResult {
        let clamped = effectiveChargeLimit(percent: percent)
        if enabled {
            let bclmResult = runPrivilegedBclmWrite(limit: clamped)
            if case .success = bclmResult {
                lastChargeBackend = .nativeBclm
                lastChargeError = nil
                return .success
            }

            let pmsetBclmResult = runPrivilegedPmset(arguments: ["-a", "bclm", "\(clamped)"])
            if case .success = pmsetBclmResult {
                lastChargeBackend = .pmsetBclm
                lastChargeError = nil
                return .success
            }

            let shouldInhibit = isCharging && (batteryPercent ?? 0) >= clamped
            let inhibitValue = shouldInhibit ? "1" : "0"
            let inhibitResult = runPrivilegedPmset(arguments: ["-b", "chargeInhibit", inhibitValue])
            switch inhibitResult {
            case .success:
                lastChargeBackend = .pmsetInhibit
                lastChargeError = nil
                return .success
            case let .failure(inhibitError):
                if case let .failure(pmsetBclmError) = pmsetBclmResult {
                    if isPmsetUnsupportedError(pmsetBclmError) && isPmsetUnsupportedError(inhibitError) {
                        lastChargeBackend = .unknown
                        lastChargeError = "Charge limiting isn't supported by pmset on this Mac"
                        return .failure("Charge limiting isn't supported by pmset on this Mac")
                    }
                    if case let .failure(nativeBclmError) = bclmResult {
                        let message = "Failed to set charge limit (bclm: \(nativeBclmError), pmset bclm: \(pmsetBclmError), chargeInhibit: \(inhibitError))"
                        lastChargeBackend = .unknown
                        lastChargeError = message
                        return .failure(message)
                    }
                    let message = "Failed to set charge limit (pmset bclm: \(pmsetBclmError), chargeInhibit: \(inhibitError))"
                    lastChargeBackend = .unknown
                    lastChargeError = message
                    return .failure(message)
                }
                let message = "Failed to set charge limit: \(inhibitError)"
                lastChargeBackend = .unknown
                lastChargeError = message
                return .failure(message)
            }
        } else {
            // Best effort reset: clear charge-inhibit and charge limit cap.
            _ = runPrivilegedBclmWrite(limit: 100)
            let inhibitReset = runPrivilegedPmset(arguments: ["-b", "chargeInhibit", "0"])
            if case .success = inhibitReset {
                _ = runPrivilegedPmset(arguments: ["-a", "bclm", "100"])
                lastChargeBackend = .disabled
                lastChargeError = nil
                return .success
            }

            let bclmReset = runPrivilegedPmset(arguments: ["-a", "bclm", "100"])
            switch bclmReset {
            case .success:
                lastChargeBackend = .disabled
                lastChargeError = nil
                return .success
            case let .failure(bclmError):
                if case let .failure(inhibitError) = inhibitReset {
                    if isPmsetUnsupportedError(bclmError) && isPmsetUnsupportedError(inhibitError) {
                        lastChargeBackend = .disabled
                        lastChargeError = nil
                        return .success
                    }
                    let message = "Failed to disable charge limit (bclm: \(bclmError), chargeInhibit: \(inhibitError))"
                    lastChargeBackend = .unknown
                    lastChargeError = message
                    return .failure(message)
                }
                let message = "Failed to disable charge limit: \(bclmError)"
                lastChargeBackend = .unknown
                lastChargeError = message
                return .failure(message)
            }
        }
    }

    func isUnsupportedChargeLimitError(_ text: String) -> Bool {
        let lower = text.lowercased()
        if isPmsetUnsupportedError(lower) {
            return true
        }
        return lower.contains("failedtoopen") ||
            lower.contains("smcresult") ||
            lower.contains("kiorreturn: 268435459")
    }

    func markSoftwareGuardActive() {
        lastChargeBackend = .softwareGuard
        lastChargeError = nil
    }

    func configurePasswordlessSudo() -> CommandResult {
        let username = NSUserName()
        let bundledBclmPath = "/Applications/LowPowerAuto.app/Contents/Resources/bclm"
        let rule = "\(username) ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode *, /usr/bin/pmset -a bclm *, /usr/bin/pmset -b chargeInhibit *, \(bundledBclmPath) write *"
        let escapedRule = shellSingleQuoted(rule)
        let shellCommand = "printf %s\\\\n '\(escapedRule)' > /etc/sudoers.d/lowpowerauto && chmod 440 /etc/sudoers.d/lowpowerauto"
        let escapedShellCommand = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = "do shell script \"\(escapedShellCommand)\" with administrator privileges"
        let result = runProcess("/usr/bin/osascript", ["-e", appleScript])

        if result.status == 0 {
            return .success
        }

        let errorText = sanitizeError(result.stderr.isEmpty ? "Failed to configure passwordless mode" : result.stderr)
        if errorText.localizedCaseInsensitiveContains("User canceled") {
            return .failure("Admin prompt canceled")
        }
        return .failure("Passwordless setup failed: \(errorText)")
    }

    private func runPrivilegedPmset(arguments: [String]) -> CommandResult {
        let noPromptResult = runProcess("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + arguments)
        if noPromptResult.status == 0 {
            return .success
        }
        if noPromptResult.stderr.localizedCaseInsensitiveContains("a password is required") ||
            noPromptResult.stderr.localizedCaseInsensitiveContains("not allowed") {
            return .failure("One-time admin setup required. Click 'Enable passwordless control (one-time)'.")
        }
        let rawError = noPromptResult.stderr.isEmpty ? noPromptResult.stdout : noPromptResult.stderr
        let errorText = sanitizeError(rawError.isEmpty ? "Command failed" : rawError)
        return .failure(errorText)
    }

    private func runPrivilegedBclmWrite(limit: Int) -> CommandResult {
        let bclmPath = "/Applications/LowPowerAuto.app/Contents/Resources/bclm"
        guard FileManager.default.isExecutableFile(atPath: bclmPath) else {
            return .failure("bclm backend not installed")
        }
        let result = runProcess("/usr/bin/sudo", ["-n", bclmPath, "write", "\(limit)"])
        if result.status == 0 {
            return .success
        }
        if result.stderr.localizedCaseInsensitiveContains("a password is required") ||
            result.stderr.localizedCaseInsensitiveContains("not allowed") {
            return .failure("One-time admin setup required. Click 'Enable passwordless control (one-time)'.")
        }
        let rawError = result.stderr.isEmpty ? result.stdout : result.stderr
        return .failure(sanitizeError(rawError.isEmpty ? "bclm command failed" : rawError))
    }

    private func runProcess(_ executablePath: String, _ arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, "", error.localizedDescription)
        }

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private func shellSingleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private func sanitizeError(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "execution error:", options: .caseInsensitive) {
            let suffix = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let codeStart = suffix.lastIndex(of: "("), suffix.hasSuffix(")") {
                return String(suffix[..<codeStart]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(suffix)
        }
        return trimmed
    }

    private func isPmsetUnsupportedError(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("usage: pmset") ||
            lower.contains("invalid") ||
            lower.contains("not supported")
    }

    private func isAppleSilicon() -> Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine.contains("arm64")
    }
}
