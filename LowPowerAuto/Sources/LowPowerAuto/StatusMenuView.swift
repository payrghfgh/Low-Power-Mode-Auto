import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var viewModel: LowPowerModeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Low Power Auto")
                    .font(.headline)

                if viewModel.shouldShowOnboarding {
                    GroupBox("Quick Setup") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Run once: startup, permissions, and notifications.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Run quick setup") { viewModel.runOnboardingQuickSetup() }
                            Button("Dismiss") { viewModel.dismissOnboarding() }
                                .font(.caption)
                        }
                    }
                }

                GroupBox("Status") {
                    VStack(spacing: 8) {
                        row("Battery", viewModel.batteryPercent.map { "\($0)%" } ?? "--")
                        row("Charging", viewModel.isCharging ? "Yes" : "No")
                        row("Low Power Mode", viewModel.lowPowerModeEnabled ? "On" : "Off")
                    }
                }

                GroupBox("Power Controls") {
                    VStack(spacing: 8) {
                        Toggle("Auto enable below threshold", isOn: $viewModel.autoEnabled)
                        Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
                        HStack {
                            Text("Threshold")
                            Spacer()
                            Stepper(value: $viewModel.thresholdPercent, in: 5...100, step: 1) {
                                Text("\(viewModel.thresholdPercent)%").monospacedDigit()
                            }
                            .frame(width: 130)
                        }
                        HStack {
                            Button("Force Low Power") { viewModel.forceLowPowerMode() }
                            Button("Force Normal") { viewModel.forceNormalMode() }
                        }
                    }
                }

                GroupBox("Charge Guard") {
                    VStack(spacing: 8) {
                        Toggle("Stop charging at limit", isOn: $viewModel.chargeLimitEnabled)
                        Picker("Preset", selection: $viewModel.chargeGuardPreset) {
                            ForEach(ChargeGuardPreset.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        HStack {
                            Text("Charge limit")
                            Spacer()
                            Stepper(value: $viewModel.chargeLimitPercent, in: 50...100, step: 1) {
                                Text("\(viewModel.chargeLimitPercent)%").monospacedDigit()
                            }
                            .disabled(!viewModel.chargeLimitEnabled)
                            .frame(width: 130)
                        }
                        Toggle("Quiet hours", isOn: $viewModel.quietHoursEnabled)
                        HStack {
                            Text("Quiet start")
                            Spacer()
                            Stepper(value: $viewModel.quietStartHour, in: 0...23) {
                                Text("\(viewModel.quietStartHour):00")
                            }
                            .disabled(!viewModel.quietHoursEnabled)
                        }
                        HStack {
                            Text("Quiet end")
                            Spacer()
                            Stepper(value: $viewModel.quietEndHour, in: 0...23) {
                                Text("\(viewModel.quietEndHour):00")
                            }
                            .disabled(!viewModel.quietHoursEnabled)
                        }
                    }
                }

                GroupBox("Appearance") {
                    Picker("Menu icon", selection: $viewModel.menuIconStyle) {
                        ForEach(MenuIconStyle.allCases) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }
                }

                GroupBox("Stats Today") {
                    VStack(spacing: 8) {
                        row("Max battery", "\(viewModel.todayMaxPercent)%")
                        row("Charging time", "\(viewModel.chargingMinutesToday) min")
                        row("Guard alerts", "\(viewModel.softwareGuardAlertsToday)")
                    }
                }

                GroupBox("Diagnostics") {
                    VStack(spacing: 8) {
                        row("Charge backend", viewModel.activeChargeBackend)
                        row("Last error", viewModel.lastChargeError)
                        row("Notifications", viewModel.notificationsAllowed ? "Allowed" : "Not allowed")
                    }
                }

                GroupBox("Updates") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.updateStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !viewModel.updateURL.isEmpty {
                            Link("Open latest release", destination: URL(string: viewModel.updateURL)!)
                        }
                        Button("Check for updates") { viewModel.checkForUpdates() }
                    }
                }

                Text(viewModel.lastActionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Refresh") { viewModel.refreshState(reason: "Manual refresh") }
                    Button(viewModel.passwordlessSetupDone ? "Passwordless ready" : "Enable one-time admin setup") {
                        viewModel.setupPasswordlessControl()
                    }
                    .disabled(viewModel.passwordlessSetupDone)
                    Spacer()
                    Button("Apply now") { viewModel.applyNow() }
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
            }
            .padding()
        }
        .frame(width: 420, height: 560)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .monospacedDigit()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: LowPowerModeViewModel

    var body: some View {
        StatusMenuView(viewModel: viewModel)
            .frame(width: 440, height: 600)
    }
}
