import SwiftUI

/// TRAINING tab: segmented Logs | Sessions (Android `TrainingScreen`).
struct TrainingView: View {
    @Environment(\.palette) private var p
    @Binding var subTab: Int
    @Binding var focusedSessionId: String?
    var onGoToSession: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                segment("Logs", index: 0)
                segment("Sessions", index: 1)
            }
            .padding(4)
            .background(p.glass, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if subTab == 0 {
                LogView(onGoToSession: onGoToSession)
            } else {
                SessionsView(focusedSessionId: $focusedSessionId)
            }
        }
        .background(subTab == 0 ? p.bg : p.session)
    }

    private func segment(_ title: String, index: Int) -> some View {
        let on = subTab == index
        return Button { withAnimation(.easeInOut(duration: 0.2)) { subTab = index } } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(on ? p.bg : p.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(on ? Brand.cyanGlow : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Logs

enum LiftCatalog {
    static let exercises = [
        "Deadlift", "Squat", "Front Squat", "Bulgarian Split Squat", "Bench Press",
        "Overhead Press", "Barbell Row", "Clean and Jerk", "Snatch"
    ]

    static let variants: [String: [String]] = [
        "Deadlift": ["Sumo DL", "RDL", "Deficit DL", "Block Pull"],
        "Squat": ["Cyclist Back Squat", "Zercher Squat", "Pause Squat", "Box Squat"],
        "Front Squat": ["Zombie Squat", "Pause Front Squat"],
        "Bulgarian Split Squat": ["Deficit BSS", "DB BSS"],
        "Bench Press": ["Close Grip Bench", "Incline Bench", "Pause Bench", "Floor Press", "Spoto Press"],
        "Overhead Press": ["Push Press", "Z Press"],
        "Barbell Row": ["Pendlay Row", "Yates Row"],
        "Clean and Jerk": ["Power Clean", "Hang Clean", "Split Jerk"],
        "Snatch": ["Power Snatch", "Hang Snatch", "Muscle Snatch"]
    ]

    static let tempos = ["20X1", "3010", "4010", "2020", "22X1", "3110", "0"]
}

struct LogView: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    var onGoToSession: (String) -> Void
    @State private var range = "All Time"
    @State private var editing: LogEntry?

    var body: some View {
        let filtered = filteredLogs
        VStack(spacing: 0) {
            ScreenTitle(text: "WORKOUT LOG").padding(.top, 16)
            RangeChips(ranges: ["1W", "1M", "All Time"], selected: $range)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if filtered.isEmpty {
                Spacer()
                Text("No sets logged yet.\nTap LOG on the Barbell tab or your watch.")
                    .font(.system(size: 14))
                    .foregroundStyle(p.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { log in
                            LogCard(log: log, onTap: { editing = log }, onInfo: { onGoToSession(log.id) }, onDelete: { vm.deleteLog(id: log.id) })
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(item: $editing) { log in
            EditLogSheet(log: log) { updated in vm.updateLog(updated) }
                .environment(\.palette, p)
                .presentationDetents([.large])
        }
    }

    private var filteredLogs: [LogEntry] {
        let days: Double = range == "1W" ? 7 : (range == "1M" ? 30 : 0)
        guard days > 0 else { return vm.logs }
        let threshold = Int64((Date().timeIntervalSince1970 - days * 86400) * 1000)
        return vm.logs.filter { $0.timestamp >= threshold }
    }
}

private struct LogCard: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    let log: LogEntry
    let onTap: () -> Void
    let onInfo: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.date(log.date, "MMM d, h:mm a"))
                    .font(.system(size: 12)).foregroundStyle(p.dim)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(Fmt.weight(log.weightLbs, metric: vm.isMetric))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Brand.cyanGlow)
                    if log.reps > 0 {
                        Text("× \(log.reps) reps").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.text)
                    }
                }
                if log.exercise.isEmpty {
                    Text("Tap to add exercise…").font(.system(size: 13)).foregroundStyle(p.dim)
                } else {
                    Text(log.variant.map { "\(log.exercise) - \($0)" } ?? log.exercise)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.electricBlue)
                }
                if let notes = log.notes, !notes.isEmpty {
                    Text(notes).font(.system(size: 12)).italic().foregroundStyle(p.dim)
                }
            }
            Spacer()
            Button(action: onInfo) {
                Image(systemName: "info.circle").font(.system(size: 18)).foregroundStyle(p.dim)
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Brand.deepOrange.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.dim.opacity(0.2), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Edit dialog: exercise, reps, notes + advanced (RPE, tempo, variant).
struct EditLogSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let log: LogEntry
    let onSave: (LogEntry) -> Void

    @State private var exercise = ""
    @State private var reps = 0
    @State private var notes = ""
    @State private var showAdvanced = false
    @State private var rpe: Int?
    @State private var tempo: String?
    @State private var variant: String?
    @State private var date: Date = Date()

    private var exerciseOptions: [String] {
        let custom = log.exercise.trimmingCharacters(in: .whitespaces)
        if custom.isEmpty || LiftCatalog.exercises.contains(custom) { return LiftCatalog.exercises }
        return LiftCatalog.exercises + [custom]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    Picker("Exercise", selection: $exercise) {
                        Text("Select…").tag("")
                        ForEach(exerciseOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: exercise) { _, _ in
                        if let v = variant, !(LiftCatalog.variants[exercise] ?? []).contains(v) { variant = nil }
                    }
                    Picker("Reps", selection: $reps) {
                        Text("—").tag(0)
                        ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        DatePicker("Time", selection: $date)
                        Picker("RPE", selection: $rpe) {
                            Text("—").tag(Int?.none)
                            ForEach(1...10, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                        }
                        Picker("Tempo", selection: $tempo) {
                            Text("—").tag(String?.none)
                            ForEach(LiftCatalog.tempos, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                        Picker("Variant", selection: $variant) {
                            Text("—").tag(String?.none)
                            ForEach(LiftCatalog.variants[exercise] ?? [], id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                        .disabled((LiftCatalog.variants[exercise] ?? []).isEmpty)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(p.bg)
            .tint(Brand.cyanGlow)
            .navigationTitle("Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(p.dim) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = log
                        updated.exercise = exercise
                        updated.reps = reps
                        updated.notes = notes.isEmpty ? nil : notes
                        updated.rpe = rpe
                        updated.tempo = tempo
                        updated.variant = variant
                        updated.timestamp = Int64(date.timeIntervalSince1970 * 1000)
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            exercise = log.exercise
            reps = log.reps
            notes = log.notes ?? ""
            rpe = log.rpe
            tempo = log.tempo
            variant = log.variant
            date = Date(timeIntervalSince1970: TimeInterval(log.timestamp) / 1000)
            showAdvanced = log.rpe != nil || log.tempo != nil || log.variant != nil
        }
    }
}
