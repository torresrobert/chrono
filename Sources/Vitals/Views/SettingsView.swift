import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    let store: Store
    @State private var launchAtLogin = Settings.shared.launchAtLogin

    var body: some View {
        Form {
            SwiftUI.Section("Menu Bar") {
                ForEach(Module.allCases) { module in
                    Toggle(isOn: Binding(get: { settings.isEnabled(module) },
                                         set: { settings.set(module, enabled: $0) })) {
                        Label(module.title, systemImage: module.symbol)
                    }
                    .disabled(module == .battery && store.battery == nil && !settings.isEnabled(.battery))
                }
                Toggle("Show captions (CPU, MEM…)", isOn: $settings.showLabels)
            }
            SwiftUI.Section("General") {
                Picker("Update every", selection: $settings.interval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                Picker("Temperature", selection: $settings.fahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        settings.launchAtLogin = on
                        launchAtLogin = settings.launchAtLogin
                    }
            }
            SwiftUI.Section {
                LabeledContent("Mac", value: SystemInfo.current.model)
                LabeledContent("Chip", value: SystemInfo.current.chip)
                LabeledContent("Memory", value: Format.bytes(SystemInfo.current.memory))
                LabeledContent("Cores", value: store.clusters.map { "\($0.cores.count) \($0.name)" }.joined(separator: " + "))
            } footer: {
                Text("⌘-drag menu bar items to reorder them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
