import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var viewModel: LowPowerModeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Low Power Auto")
                .font(.headline)

            HStack {
                Text("Battery")
                Spacer()
                Text(viewModel.batteryPercent.map { "\($0)%" } ?? "--")
                    .monospacedDigit()
            }

            HStack {
                Text("Charging")
                Spacer()
                Text(viewModel.isCharging ? "Yes" : "No")
            }

            HStack {
                Text("Low Power Mode")
                Spacer()
                Text(viewModel.lowPowerModeEnabled ? "On" : "Off")
                    .foregroundStyle(viewModel.lowPowerModeEnabled ? .green : .secondary)
            }

            Toggle("Auto enable below threshold", isOn: $viewModel.autoEnabled)
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
            Toggle("Stop charging at limit", isOn: $viewModel.chargeLimitEnabled)

            HStack {
                Text("Threshold")
                Spacer()
                Stepper(value: $viewModel.thresholdPercent, in: 5...100, step: 1) {
                    Text("\(viewModel.thresholdPercent)%")
                        .monospacedDigit()
                }
                .frame(width: 130)
            }

            HStack {
                Text("Charge limit")
                Spacer()
                Stepper(value: $viewModel.chargeLimitPercent, in: 50...100, step: 1) {
                    Text("\(viewModel.chargeLimitPercent)%")
                        .monospacedDigit()
                }
                .disabled(!viewModel.chargeLimitEnabled)
                .frame(width: 130)
            }

            Text(viewModel.lastActionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(viewModel.passwordlessSetupDone ? "Passwordless control enabled" : "Enable passwordless control (one-time)") {
                viewModel.setupPasswordlessControl()
            }
            .disabled(viewModel.passwordlessSetupDone)

            HStack {
                Button("Refresh") {
                    viewModel.refreshState(reason: "Manual refresh")
                }

                Spacer()

                Button("Apply now") {
                    viewModel.applyNow()
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 340)
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: LowPowerModeViewModel

    var body: some View {
        Form {
            Toggle("Enable automation", isOn: $viewModel.autoEnabled)
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
            Toggle("Stop charging at limit", isOn: $viewModel.chargeLimitEnabled)

            HStack {
                Text("Threshold")
                Spacer()
                Stepper(value: $viewModel.thresholdPercent, in: 5...100, step: 1) {
                    Text("\(viewModel.thresholdPercent)%")
                        .monospacedDigit()
                }
            }

            HStack {
                Text("Charge limit")
                Spacer()
                Stepper(value: $viewModel.chargeLimitPercent, in: 50...100, step: 1) {
                    Text("\(viewModel.chargeLimitPercent)%")
                        .monospacedDigit()
                }
                .disabled(!viewModel.chargeLimitEnabled)
            }

            HStack {
                Text("Current battery")
                Spacer()
                Text(viewModel.batteryPercent.map { "\($0)%" } ?? "--")
                    .monospacedDigit()
            }

            HStack {
                Text("Low Power Mode")
                Spacer()
                Text(viewModel.lowPowerModeEnabled ? "On" : "Off")
            }

            Text(viewModel.lastActionMessage)
                .foregroundStyle(.secondary)

            Button(viewModel.passwordlessSetupDone ? "Passwordless control enabled" : "Enable passwordless control (one-time)") {
                viewModel.setupPasswordlessControl()
            }
            .disabled(viewModel.passwordlessSetupDone)

            Button("Run check now") {
                viewModel.applyNow()
            }
        }
    }
}
