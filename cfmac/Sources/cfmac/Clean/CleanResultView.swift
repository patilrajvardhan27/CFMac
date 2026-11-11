import CfmacCore
import SwiftUI

struct CleanResultView: View {
    @EnvironmentObject private var model: CleanModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 12) {
                PlanetView(planet: settings.planet(for: .clean), diameter: 160)
                Text("\(Format.bytes(model.freedTotal)) cleaned")
                    .font(.system(size: 24, weight: .bold))
                    .contentTransition(.numericText())
                if model.outcomes.contains(where: { $0.kind == .movedToTrash }) {
                    Text("Moved to Trash. Empty the Trash to free the space.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .multilineTextAlignment(.center)
                }
                if !model.lastRestorable.isEmpty {
                    Button("Put Back \(model.lastRestorable.count) Items") { model.putBack() }
                        .buttonStyle(PillButtonStyle())
                        .help("Move everything this clean put in the Trash back where it was")
                }
                if let message = model.putBackMessage {
                    Text(message).font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                }
                Button("Done") { model.finish() }
                    .buttonStyle(HeroButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 8)
            }
            .frame(width: 300)
            .padding(.top, 40)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(CleanOutcome.Kind.allCases.enumerated()), id: \.element) { index, kind in
                        let group = model.outcomes.filter { $0.kind == kind }
                        if !group.isEmpty {
                            outcomeGroup(kind, group).appearEffect(order: index)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 24)
    }

    private func outcomeGroup(_ kind: CleanOutcome.Kind, _ group: [CleanOutcome]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(kind.rawValue) · \(group.count)").font(.system(size: 14, weight: .semibold))
            ForEach(group) { outcome in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outcome.item.label).font(.system(size: 13))
                        if let reason = outcome.reason {
                            Text(reason).font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                        }
                    }
                    Spacer()
                    if outcome.freed > 0 {
                        Text(Format.bytes(outcome.freed)).monospacedDigit().font(.system(size: 12))
                    }
                }
                .contextMenu { Button("Reveal in Finder") { SystemActions.reveal(outcome.item.path) } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.cardFill))
    }
}
