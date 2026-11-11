import FanService
import SwiftUI

/// Shown when the user turns fan control on: lists every change, then asks for approval.
struct FanEnableSheet: View {
    @EnvironmentObject private var fan: FanController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Turn on fan control?", systemImage: "fan").font(.title2.bold())
            Text("Cool and Max need a small helper that runs with administrator rights. It controls fans and nothing else, and it only answers your account.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("cfmac will:").font(.headline)
                ForEach(HelperInstallScript.plannedChanges(uid: getuid()), id: \.self) { change in
                    Label(change, systemImage: "checkmark.circle").font(.callout)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Safety").font(.headline)
                Text(
                    "Speeds stay within the limits your Mac reports. Fans return to macOS when you choose Auto, when you quit cfmac, when you turn fan control off, and on their own if cfmac stops responding for \(Int(HelperLayout.leaseSeconds)) seconds."
                )
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Higher speeds mean more noise, power use and wear. You use fan control at your own risk; see the Terms of Use. Turn it off any time in Settings › Fan, which removes the helper."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let message = fan.message {
                Text(message).font(.callout).foregroundStyle(Color.accentAmber)
            }

            HStack {
                Button("Not Now") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if fan.isWorking { ProgressView().controlSize(.small) }
                Button("Turn On…") {
                    Task {
                        if await fan.enable() { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fan.isWorking)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
