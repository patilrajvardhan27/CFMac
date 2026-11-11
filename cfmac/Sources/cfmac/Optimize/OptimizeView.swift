import CfmacCore
import SwiftUI

struct OptimizeView: View {
    @EnvironmentObject private var model: OptimizeModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PlanetView(planet: settings.planet(for: .optimize), diameter: 240, busy: model.phase == .running)
            Spacer().frame(height: 56)
            heroText.frame(height: 130, alignment: .top)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $model.showDetails) { OptimizeDetails().environmentObject(model) }
    }

    @ViewBuilder
    private var heroText: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                Text("Tune up your Mac").font(.system(size: 28, weight: .bold))
                HeroSubtitle(text: "\(model.enabled.count) maintenance tasks ready ·", link: "Choose tasks") { model.showDetails = true }
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                Button("Optimize") { model.run() }
                    .buttonStyle(HeroButtonStyle())
                    .keyboardShortcut(.defaultAction)
            case .running:
                Text("Running maintenance").font(.system(size: 28, weight: .bold))
                Text(model.currentStep)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .padding(.top, 6)
                    .contentTransition(.opacity)
                    .animation(Motion.content, value: model.currentStep)
                ProgressView().controlSize(.small).padding(.top, 14)
            case .done:
                Text(model.completedCount > 0 ? "Maintenance complete" : "Nothing needed tuning")
                    .font(.system(size: 28, weight: .bold))
                HeroSubtitle(text: "\(model.completedCount) maintenance tasks completed ·", link: "Review results") { model.showDetails = true }
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                Button("Rest, \(settings.planet(for: .optimize).title)") { model.reset() }
                    .buttonStyle(HeroButtonStyle(prominent: false))
            }
        }
        .transition(.opacity)
        .animation(Motion.content, value: model.phase)
    }
}

struct OptimizeDetails: View {
    @EnvironmentObject private var model: OptimizeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.phase == .idle ? "Maintenance tasks" : "Optimize details").font(.title2.bold())
            List {
                ForEach(OptimizeTask.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(model.tasks.filter { $0.group == group }) { task in row(task) }
                    }
                }
                Section("Glitch fixes") {
                    ForEach(GlitchFix.all) { fix in
                        HStack {
                            Text("Restart \(fix.title)")
                            Spacer()
                            if let result = model.glitchResults[fix.id] {
                                Text(result).font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Restart") { model.runGlitchFix(fix) }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
    }

    @ViewBuilder
    private func row(_ task: OptimizeTask) -> some View {
        HStack(spacing: 10) {
            if model.phase == .idle {
                Toggle(
                    task.title,
                    isOn: Binding(
                        get: { model.enabled.contains(task.id) },
                        set: { isOn in if isOn { model.enabled.insert(task.id) } else { model.enabled.remove(task.id) } }
                    )
                )
                .toggleStyle(.checkbox)
            } else {
                stateIcon(model.state(of: task))
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                    Text(stateText(model.state(of: task))).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if task.needsAdministrator {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).help("Needs administrator access")
            }
        }
    }

    @ViewBuilder
    private func stateIcon(_ state: OptimizeModel.TaskState) -> some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.mini)
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentGreen)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Color.accentRed)
        }
    }

    private func stateText(_ state: OptimizeModel.TaskState) -> String {
        switch state {
        case .pending: "Waiting"
        case .running: "Running"
        case .completed(let detail): "Completed" + (detail.map { " · \($0)" } ?? "")
        case .skipped(let reason): "Skipped · \(reason)"
        case .failed(let reason): "Failed · \(reason)"
        }
    }
}
