import SwiftUI

/// Home dashboard: a calm summary of today — goal rings, heart, energy, the week, and training.
struct HomeView: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    var onOpenTraining: () -> Void
    var onOpenAccount: () -> Void

    var body: some View {
        let todayKey = HealthKitManager.dayKey(Date())
        // Fall back to the server copy if Apple Health isn't readable on this device.
        let serverToday = vm.healthMetrics.first { $0.date == todayKey }
        let steps = vm.today?.steps ?? serverToday?.steps ?? 0
        let activeKcal = vm.today?.activeKcal ?? serverToday?.activeCalories ?? 0
        let totalKcal = vm.today?.totalKcal ?? serverToday?.calories
        let activeMin = vm.today?.activeMinutes ?? serverToday?.activeMinutes ?? 0
        let hasData = vm.today != nil || serverToday != nil
        let goals = vm.goals

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(steps: steps, goal: goals.steps)

                // ── Rings ──
                GlassCard {
                    VStack(spacing: 0) {
                        ZStack {
                            GoalRings(rings: [
                                (Double(steps) / Double(goals.steps), Brand.stepGreen),
                                (Double(activeKcal) / Double(goals.activeKcal), Brand.kcalOrange),
                                (Double(activeMin) / Double(goals.activeMinutes), Brand.minuteBlue)
                            ], ringWidth: 18, gap: 6)
                            VStack(spacing: 0) {
                                Text(Fmt.thousands(steps))
                                    .font(.system(size: 34, weight: .heavy))
                                    .foregroundStyle(p.text)
                                    .contentTransition(.numericText())
                                Text("of \(Fmt.thousands(goals.steps)) steps")
                                    .font(.system(size: 12)).foregroundStyle(p.dim)
                                if steps >= goals.steps {
                                    Text("🎉 Goal hit!").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.stepGreen)
                                }
                            }
                        }
                        .frame(width: 230, height: 230)

                        HStack {
                            RingLegend(icon: "figure.walk", color: Brand.stepGreen, value: Fmt.thousands(steps), of: "/ \(Fmt.thousands(goals.steps))", label: "Steps")
                            RingLegend(icon: "flame.fill", color: Brand.kcalOrange, value: "\(activeKcal)", of: "/ \(goals.activeKcal)", label: "Active kcal")
                            RingLegend(icon: "timer", color: Brand.minuteBlue, value: "\(activeMin)", of: "/ \(goals.activeMinutes)", label: "Active min")
                        }
                        .padding(.top, 12)

                        if !hasData && !vm.healthRefreshing {
                            Button(action: onOpenAccount) {
                                Text("Connect Apple Health in Account to fill your rings →")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Brand.kcalOrange)
                                    .multilineTextAlignment(.center)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // ── Coaching Advice ──
                CoachingCard()

                // ── Heart + Energy ──
                HStack(alignment: .top, spacing: 12) {
                    HeartCard(today: vm.today, server: serverToday)
                    EnergyCard(active: activeKcal, total: totalKcal, goal: goals.activeKcal)
                }
                .fixedSize(horizontal: false, vertical: true)

                // ── Week strip ──
                if !vm.week.isEmpty || !vm.healthMetrics.isEmpty {
                    GlassCard {
                        Text("THIS WEEK")
                            .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(p.dim)
                            .padding(.bottom, 10)
                        WeekStrip(todaySteps: steps, goal: goals.steps)
                    }
                }

                // ── Training today ──
                TrainingTodayCard(onTap: onOpenTraining)

                Text(vm.healthRefreshing ? "Syncing…" : "Synced to web \(Fmt.ago(vm.lastHealthSync)) · pull to refresh")
                    .font(.system(size: 11))
                    .foregroundStyle(p.dim)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(p.bg)
        .refreshable { await vm.refreshHealth(force: true) }
        .task { await vm.refreshHealth(force: false) }
    }

    @ViewBuilder
    private func header(steps: Int, goal: Int) -> some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String = {
            switch hour {
            case 5...11: return "Good morning"
            case 12...16: return "Good afternoon"
            case 17...21: return "Good evening"
            default: return "Late night"
            }
        }()
        let first = vm.currentUser?.name.split(separator: " ").first.map(String.init)
        VStack(alignment: .leading, spacing: 0) {
            Text(Fmt.date(Date(), "EEEE, MMM d").uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(1.5)
                .foregroundStyle(p.dim)
            Text(first.map { "\(greeting), \($0)" } ?? greeting)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(p.text)
            if vm.isJokeMode {
                Text(Self.jokeLine(steps: steps, goal: goal))
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.kcalOrange)
                    .padding(.top, 2)
            }
        }
    }

    static func jokeLine(steps: Int, goal: Int) -> String {
        if steps == 0 { return "Your couch called. It says thanks for the loyalty." }
        if steps < goal / 4 { return "Warming up… for a nap, apparently." }
        if steps < goal / 2 { return "Halfway to halfway. Inspirational." }
        if steps < goal { return "So close your shoes can taste it." }
        return "Goal crushed. Your legs filed a complaint."
    }
}

// MARK: - Goal rings

/// Concentric, animated progress rings. Each pair is (progress 0..n, colour); >1 wraps brighter.
struct GoalRings: View {
    let rings: [(Double, Color)]
    let ringWidth: CGFloat
    let gap: CGFloat
    @State private var anim: Double = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.offset) { item in
                    ringView(index: item.offset, progress: item.element.0, color: item.element.1, side: side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { anim = 1 } }
    }

    @ViewBuilder
    private func ringView(index: Int, progress: Double, color: Color, side: CGFloat) -> some View {
        let inset = CGFloat(index) * (ringWidth + gap)
        let d = side - inset * 2 - ringWidth
        let pr = min(max(progress.isFinite ? progress : 0, 0), 2) * anim
        if d > 0 {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: ringWidth)
                Circle()
                    .trim(from: 0, to: min(pr, 1))
                    .stroke(
                        AngularGradient(colors: [color.opacity(0.75), color, color.opacity(0.75)], center: .center),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if pr > 1 {
                    Circle()
                        .trim(from: 0, to: pr - 1)
                        .stroke(color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                        .overlay(
                            Circle().trim(from: 0, to: pr - 1)
                                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: d, height: d)
        }
    }
}

private struct RingLegend: View {
    @Environment(\.palette) private var p
    let icon: String
    let color: Color
    let value: String
    let of: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(p.text)
                Text(" \(of)").font(.system(size: 11)).foregroundStyle(p.dim)
            }
            Text(label).font(.system(size: 11)).foregroundStyle(p.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Heart / Energy

private struct HeartCard: View {
    @Environment(\.palette) private var p
    let today: HealthKitManager.TodaySummary?
    let server: HealthMetricDto?
    @State private var pulse = false

    var body: some View {
        let latest = today?.latestHr ?? server?.avgHeartRate
        let resting = today?.restingHr ?? server?.restingHeartRate
        let maxHr = today?.maxHr ?? server?.maxHeartRate
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Brand.heartRed)
                    .scaleEffect(latest != nil && pulse ? 1.18 : 1)
                Text("HEART").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(p.dim)
            }
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(latest.map { "\($0)" } ?? "--").font(.system(size: 28, weight: .heavy)).foregroundStyle(p.text)
                Text(" bpm").font(.system(size: 12)).foregroundStyle(p.dim)
            }
            .padding(.top, 6)
            let hourly = today?.hourlyHr ?? []
            if hourly.contains(where: { $0 != nil }) {
                Sparkline(values: hourly, color: Brand.heartRed)
                    .frame(height: 36)
                    .padding(.vertical, 4)
            } else {
                Spacer().frame(height: 8)
            }
            Spacer(minLength: 0)
            Text("Rest \(resting.map { "\($0)" } ?? "--") · Max \(maxHr.map { "\($0)" } ?? "--")")
                .font(.system(size: 11)).foregroundStyle(p.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 22))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private struct Sparkline: View {
    let values: [Int?]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts: [(Int, Double)] = values.enumerated().compactMap { item in item.element.map { (item.offset, Double($0)) } }
            if pts.count >= 2 {
                let lo = pts.map { $0.1 }.min()!
                let hiRaw = pts.map { $0.1 }.max()!
                let hi = hiRaw == lo ? lo + 1 : hiRaw
                let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))
                Path { path in
                    for (idx, pt) in pts.enumerated() {
                        let x = CGFloat(pt.0) * stepX
                        let y = geo.size.height - CGFloat((pt.1 - lo) / (hi - lo)) * geo.size.height
                        if idx == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct EnergyCard: View {
    @Environment(\.palette) private var p
    let active: Int
    let total: Int?
    let goal: Int

    var body: some View {
        let frac = min(max(Double(active) / Double(max(goal, 1)), 0), 1)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.system(size: 16)).foregroundStyle(Brand.kcalOrange)
                Text("ENERGY").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(p.dim)
            }
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(active)").font(.system(size: 28, weight: .heavy)).foregroundStyle(p.text)
                Text(" active kcal").font(.system(size: 12)).foregroundStyle(p.dim)
            }
            .padding(.top, 6)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Brand.kcalOrange.opacity(0.18))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Brand.kcalOrange, Brand.heartRed], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 8)
            .padding(.vertical, 8)
            Spacer(minLength: 0)
            Text(total.map { "Total burn \(Fmt.thousands($0)) kcal" } ?? "Total burn --")
                .font(.system(size: 11)).foregroundStyle(p.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Week strip

private struct WeekStrip: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    let todaySteps: Int
    let goal: Int

    @State private var selectedDayTarget: DayTarget? = nil

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0...6).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        HStack {
            ForEach(days, id: \.self) { d in
                let key = HealthKitManager.dayKey(d)
                let isToday = d == today
                let m = vm.week.first { $0.date == key } ?? vm.healthMetrics.first { $0.date == key }
                let s = isToday ? todaySteps : (m?.steps ?? 0)
                VStack(spacing: 4) {
                    ZStack {
                        GoalRings(rings: [(Double(s) / Double(max(goal, 1)), Brand.stepGreen)], ringWidth: 5, gap: 0)
                        if s >= goal {
                            Text("✓").font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.stepGreen)
                        }
                    }
                    .frame(width: 36, height: 36)
                    Text(Fmt.date(d, "EEEEE"))
                        .font(.system(size: 11, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? p.text : p.dim)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedDayTarget = DayTarget(id: key, date: d)
                }
            }
        }
        .sheet(item: $selectedDayTarget) { target in
            DaySummarySheet(date: target.date, dateKey: target.id)
                .environmentObject(vm)
                .environment(\.palette, p)
        }
    }
}

// MARK: - Training today

private struct TrainingTodayCard: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    var onTap: () -> Void

    var body: some View {
        let cal = Calendar.current
        let logsToday = vm.logs.filter { cal.isDateInToday($0.date) }
        let sessionsToday = vm.sessions.filter { !$0.isHidden && cal.isDateInToday($0.startDate) }
        let volume = logsToday.reduce(0.0) { $0 + $1.weightLbs * Double(max($1.reps, 1)) }
        let sub: String = {
            if logsToday.isEmpty && sessionsToday.isEmpty { return "Nothing logged yet — rest day or go time?" }
            var parts: [String] = []
            if !sessionsToday.isEmpty {
                let mins = sessionsToday.reduce(0) { $0 + $1.durationMinutes }
                parts.append("\(sessionsToday.count) session\(sessionsToday.count > 1 ? "s" : "") · \(mins) min")
            }
            if !logsToday.isEmpty {
                parts.append("\(logsToday.count) set\(logsToday.count > 1 ? "s" : "") · \(Fmt.thousands(volume)) lb")
            }
            return parts.joined(separator: "  •  ")
        }()
        let lifts = Self.distinctLifts(logsToday)

        Button(action: onTap) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Brand.kcalOrange, Brand.heartRed], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "bolt.fill").foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's training").font(.system(size: 16, weight: .bold)).foregroundStyle(p.text)
                    Text(sub).font(.system(size: 13)).foregroundStyle(p.dim)
                    if !lifts.isEmpty {
                        Text(lifts.prefix(3).joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Brand.kcalOrange)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(p.dim)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.glass, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private static func distinctLifts(_ logs: [LogEntry]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for l in logs where !l.exercise.isEmpty && !seen.contains(l.exercise) {
            seen.insert(l.exercise)
            out.append(l.exercise)
        }
        return out
    }
}

// MARK: - Coaching

private struct CoachingCard: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var vm: PhoneViewModel
    
    var body: some View {
        let insight: String = {
            let cal = Calendar.current
            let now = Date().timeIntervalSince1970 * 1000
            let sevenDaysAgo = now - 7 * 86400 * 1000
            var activeDays = Set<Date>()
            for log in vm.logs where Double(log.timestamp) > sevenDaysAgo { activeDays.insert(cal.startOfDay(for: log.date)) }
            for s in vm.sessions where Double(s.startTime) > sevenDaysAgo { activeDays.insert(cal.startOfDay(for: s.startDate)) }
            
            let recentLogs = vm.logs.filter { Double($0.timestamp) > now - 3 * 86400 * 1000 }
            let highRpeCount = recentLogs.filter { ($0.rpe ?? 0) >= 9 }.count
            
            if activeDays.count >= 5 {
                return "You've pushed hard with \(activeDays.count) active days this week! Make sure to prioritize recovery, drink plenty of water, and consider a light mobility day."
            } else if highRpeCount >= 3 {
                return "You've logged several near-max sets recently. If you feel fatigued, consider a deload or technique-focused session to let your nervous system recover."
            } else if activeDays.isEmpty {
                return "It's been a little while since your last session. Don't worry about hitting PRs today; just focus on getting moving and slowly rebuilding your momentum."
            } else if activeDays.count >= 3 {
                return "You're building a great rhythm! Keep that momentum going, but remember to listen to your body and fuel your recovery with plenty of protein."
            } else {
                return "Consistency is the secret to progress. Focus on solid form today, stay hydrated, and take adequate rest between your sets."
            }
        }()
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(Brand.cyanGlow)
                Text("COACHING INSIGHT").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(p.dim)
            }
            Text(insight)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(p.text)
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - DayTarget & DaySummarySheet

struct DayTarget: Identifiable {
    let id: String
    let date: Date
}

struct DaySummarySheet: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let dateKey: String

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        let mLocal = vm.week.first { $0.date == dateKey }
        let mServer = vm.healthMetrics.first { $0.date == dateKey }
        
        let steps = mLocal?.steps ?? mServer?.steps ?? 0
        let activeKcal = mLocal?.activeCalories ?? mServer?.activeCalories ?? 0
        let totalKcal = mLocal?.calories ?? mServer?.calories
        let activeMin = mLocal?.activeMinutes ?? mServer?.activeMinutes ?? 0
        let restingHr = mLocal?.restingHeartRate ?? mServer?.restingHeartRate
        let maxHr = mLocal?.maxHeartRate ?? mServer?.maxHeartRate
        let hourlyHr: [Int?] = [] // Server copy does not store hourly heart rates yet
        
        let logs = vm.logs.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        let sessions = vm.sessions.filter { !$0.isHidden && Calendar.current.isDate($0.startDate, inSameDayAs: date) }
        let volume = logs.reduce(0.0) { $0 + $1.weightLbs * Double(max($1.reps, 1)) }
        let sessionMins = sessions.reduce(0) { $0 + $1.durationMinutes }

        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Rings
                    ZStack {
                        GoalRings(rings: [
                            (Double(steps) / Double(vm.goals.steps), Brand.stepGreen),
                            (Double(activeKcal) / Double(vm.goals.activeKcal), Brand.kcalOrange),
                            (Double(activeMin) / Double(vm.goals.activeMinutes), Brand.minuteBlue)
                        ], ringWidth: 16, gap: 4)
                        
                        VStack {
                            Text(Fmt.thousands(steps))
                                .font(.system(size: 32, weight: .heavy))
                                .foregroundStyle(p.text)
                            Text("Steps")
                                .font(.system(size: 13))
                                .foregroundStyle(p.dim)
                        }
                    }
                    .frame(width: 200, height: 200)
                    .padding(.top, 20)

                    HStack(spacing: 20) {
                        MetricBox(title: "Active kcal", value: "\(activeKcal)", color: Brand.kcalOrange)
                        MetricBox(title: "Active min", value: "\(activeMin)", color: Brand.minuteBlue)
                        MetricBox(title: "Total burn", value: totalKcal != nil ? "\(totalKcal!)" : "--", color: .gray)
                    }

                    // Heart
                    if restingHr != nil || maxHr != nil || hourlyHr.contains(where: { $0 != nil }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HEART").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(Brand.heartRed)
                            HStack {
                                Text("Resting: \(restingHr.map { "\($0)" } ?? "--") bpm")
                                Spacer()
                                Text("Max: \(maxHr.map { "\($0)" } ?? "--") bpm")
                            }
                            .font(.system(size: 14)).foregroundStyle(p.text)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.glass, in: RoundedRectangle(cornerRadius: 16))
                    }

                    // Training
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRAINING").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(Brand.minuteBlue)
                        if logs.isEmpty && sessions.isEmpty {
                            Text("No training logged.")
                                .font(.system(size: 14)).foregroundStyle(p.dim)
                        } else {
                            if !sessions.isEmpty {
                                Text("\(sessions.count) Session(s) · \(sessionMins) min")
                                    .font(.system(size: 14)).foregroundStyle(p.text)
                            }
                            if !logs.isEmpty {
                                Text("\(logs.count) Set(s) · \(Fmt.thousands(volume)) lbs volume")
                                    .font(.system(size: 14)).foregroundStyle(p.text)
                                
                                let lifts = Array(Set(logs.map { $0.exercise })).sorted()
                                Text("Exercises: \(lifts.joined(separator: ", "))")
                                    .font(.system(size: 13)).foregroundStyle(p.dim)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.glass, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .background(p.bg.ignoresSafeArea())
            .navigationTitle(isToday ? "Today" : Fmt.date(date, "EEEE, MMM d"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MetricBox: View {
    @Environment(\.palette) private var p
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(p.text)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 12))
    }
}
