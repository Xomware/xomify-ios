import SwiftUI

/// Weekly Goals — targets for the current week, with a streak and recent
/// history. Web parity (`xomify-frontend/src/app/pages/goals`); the goals
/// themselves are the same records, shared through `/goals/*`.
struct GoalsView: View {

    @State private var viewModel = GoalsViewModel()
    @State private var showingCreate = false
    @State private var confirmingRemoval: Goal?

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()

            if viewModel.isLoading {
                XomifyLoaderPulse(size: 52)
            } else {
                content
            }
        }
        .navigationTitle("Weekly Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add goal")
                .disabled(viewModel.isSaving)
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showingCreate) {
            CreateGoalSheet { metric, target in
                Task { await viewModel.addGoal(metric: metric, target: target) }
            }
        }
        .alert(
            "Remove this goal?",
            isPresented: Binding(
                get: { confirmingRemoval != nil },
                set: { if !$0 { confirmingRemoval = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let goal = confirmingRemoval {
                    Task { await viewModel.removeGoal(id: goal.id) }
                }
                confirmingRemoval = nil
            }
            Button("Cancel", role: .cancel) { confirmingRemoval = nil }
        } message: {
            Text("\(confirmingRemoval?.label ?? "This goal") will be removed from every device.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: XomSpacing.lg) {
                header

                if viewModel.progressUnavailable {
                    unavailableNotice
                }

                if viewModel.goals.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.goals) { goal in
                        GoalCard(goal: goal) { confirmingRemoval = goal }
                    }
                }

                if !viewModel.history.isEmpty {
                    historySection
                }
            }
            .padding(XomSpacing.md)
        }
        .refreshable { await viewModel.load() }
    }

    private var header: some View {
        VStack(spacing: XomSpacing.xs) {
            Text("\(viewModel.metCount) of \(viewModel.goals.count) met this week")
                .font(.headline)
                .foregroundStyle(.white)

            if let streak = viewModel.streakLabel {
                Label(streak, systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.xomifyGreen)
            } else {
                Text("Set targets & build consistency")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XomSpacing.sm)
    }

    /// Progress could not be read. Saying so beats showing zeros, which look
    /// exactly like a week of listening to nothing.
    private var unavailableNotice: some View {
        Label(
            "Couldn't read this week's listening history — progress may be out of date.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(XomSpacing.sm)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: XomRadius.sm))
    }

    private var emptyState: some View {
        VStack(spacing: XomSpacing.sm) {
            Image(systemName: "target")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.35))
            Text("No goals yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Add a weekly target to start a streak.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            Button("Add a goal") { showingCreate = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.xomifyGreen)
                .padding(.top, XomSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XomSpacing.xl)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: XomSpacing.sm) {
            Text("RECENT WEEKS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            ForEach(viewModel.history.prefix(8)) { entry in
                HStack {
                    Text("Week of \(GoalsViewModel.weekLabel(entry.weekStart))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("\(entry.metCount)/\(entry.totalCount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(entry.allMet ? Color.xomifyGreen : .white.opacity(0.6))
                }
                .padding(.vertical, XomSpacing.xs)
            }
        }
        .padding(XomSpacing.md)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: XomRadius.md))
    }
}

// MARK: - Goal card

private struct GoalCard: View {
    let goal: Goal
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: XomSpacing.sm) {
            HStack(spacing: XomSpacing.sm) {
                Image(systemName: goal.metric.systemImage)
                    .font(.title3)
                    .foregroundStyle(goal.completed ? Color.xomifyGreen : .white.opacity(0.7))
                    .frame(width: 28)

                Text(goal.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                if goal.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.xomifyGreen)
                }
            }

            ProgressView(value: goal.fraction)
                .tint(goal.completed ? Color.xomifyGreen : Color.xomifyPurple)

            Text("\(goal.current) / \(goal.target)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(XomSpacing.md)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: XomRadius.md))
        // Swipe-to-delete is a list affordance and these are cards, so removal
        // lives in a context menu rather than a permanent ✕ on every row.
        .contextMenu {
            Button("Remove Goal", systemImage: "trash", role: .destructive, action: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(goal.label). \(goal.current) of \(goal.target)\(goal.completed ? ", met" : "")")
    }
}

// MARK: - Create sheet

struct CreateGoalSheet: View {
    /// Called with the chosen metric and target. The parent owns the save, so
    /// the sheet never has to know whether it succeeded.
    let onAdd: (GoalMetric, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var metric: GoalMetric = .minutesListened
    @State private var target: Int = GoalMetric.minutesListened.suggestedTarget

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Type") {
                    Picker("Metric", selection: $metric) {
                        ForEach(GoalMetric.allCases) { option in
                            Text(option.pickerLabel).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    // Switching metric carries the previous number over, and
                    // "300 genres" is not a goal anyone meant to set.
                    .onChange(of: metric) { _, new in target = new.suggestedTarget }
                }

                Section("Target") {
                    Stepper(value: $target, in: 1...10_000, step: stepSize) {
                        Text("\(target)")
                            .monospacedDigit()
                    }
                }

                Section {
                    Label(metric.label(target: target), systemImage: metric.systemImage)
                        .foregroundStyle(Color.xomifyGreen)
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Create Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(metric, target)
                        dismiss()
                    }
                }
            }
        }
    }

    /// Minutes move in useful chunks; a 1-at-a-time stepper from 300 is not a
    /// control anyone would use.
    private var stepSize: Int {
        switch metric {
        case .minutesListened: return 30
        case .uniqueTracks:    return 5
        default:               return 1
        }
    }
}
