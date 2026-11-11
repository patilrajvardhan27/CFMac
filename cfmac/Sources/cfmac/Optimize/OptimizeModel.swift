import CfmacCore
import Foundation

@MainActor
final class OptimizeModel: ObservableObject {
    enum Phase { case idle, running, done }

    enum TaskState: Equatable {
        case pending, running, completed(String?), skipped(String), failed(String)

        var isCompleted: Bool {
            if case .completed = self { return true }
            return false
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var tasks: [OptimizeTask] = OptimizeCatalog.tasks(protected: [])
    @Published private(set) var states: [String: TaskState] = [:]
    @Published var enabled: Set<String> = Set(OptimizeCatalog.tasks(protected: []).map(\.id))
    @Published var showDetails = false
    @Published private(set) var currentStep = ""
    @Published private(set) var glitchResults: [String: String] = [:]

    var completedCount: Int { states.values.filter(\.isCompleted).count }

    func state(of task: OptimizeTask) -> TaskState { states[task.id] ?? .pending }

    func run() {
        guard phase != .running else { return }
        tasks = OptimizeCatalog.tasks(protected: AppSettings.shared.protectedSet)
        states = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, enabled.contains($0.id) ? .pending : .skipped("Turned off")) })
        phase = .running
        Task {
            await runUserTasks()
            await runAdministratorTasks()
            currentStep = ""
            UsageStats.shared.recordOptimize()
            phase = .done
            SoundPlayer.shared.playCompletion(for: .optimize)
        }
    }

    private func runUserTasks() async {
        for task in tasks where states[task.id] == .pending {
            guard case .user(let work) = task.work else { continue }
            states[task.id] = .running
            currentStep = task.group.runningTitle
            states[task.id] = await Task.detached(priority: .userInitiated) { () -> TaskState in
                do { return .completed(try work()) } catch let skipped as TaskSkipped { return .skipped(skipped.reason) } catch {
                    return .failed(error.localizedDescription)
                }
            }.value
        }
    }

    /// Every chosen root task runs behind one administrator prompt. Purging memory only
    /// helps under pressure, so it is skipped otherwise.
    private func runAdministratorTasks() async {
        var chosen: [OptimizeTask] = []
        for task in tasks where states[task.id] == .pending && task.needsAdministrator {
            if task.id == "purge", MemoryPressure.current() == .normal {
                states[task.id] = .skipped("Memory pressure is normal")
            } else {
                chosen.append(task)
            }
        }
        guard !chosen.isEmpty else { return }
        currentStep = "Requesting admin access…"
        chosen.forEach { states[$0.id] = .running }
        let script = OptimizeCatalog.administratorScript(for: chosen)
        let result = await Task.detached {
            Shell.runAsAdministrator(script: script, prompt: "cfmac runs optional maintenance tasks that need administrator access.")
        }.value
        let outcomes = OptimizeCatalog.administratorResults(result.output)
        for task in chosen {
            if result.wasCancelledByUser {
                states[task.id] = .skipped("Admin access not granted")
            } else if outcomes[task.id] == true {
                states[task.id] = .completed(nil)
            } else {
                states[task.id] = .failed("Could not complete this task right now")
            }
        }
    }

    /// Back to the start screen; results stay available until the next run.
    func reset() {
        phase = .idle
    }

    func runGlitchFix(_ fix: GlitchFix) {
        Task {
            let restarted = await Task.detached { fix.run() }.value
            glitchResults[fix.id] = restarted ? "Refreshed" : "Normal"
        }
    }
}
