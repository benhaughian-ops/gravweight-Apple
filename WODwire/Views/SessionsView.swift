import SwiftUI

/// "WORKOUT SESSIONS" — Apple Health workouts with expandable details and an interactive HR graph.
struct SessionsView: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    @Binding var focusedSessionId: String?
    @State private var search = ""
    @State private var range = "All Time"
    @State private var expandedId: String?

    var body: some View {
        let filtered = filteredSessions
        VStack(spacing: 0) {
            ScreenTitle(text: "WORKOUT SESSIONS").padding(.top, 16)
            RangeChips(ranges: ["1W", "1M", "All Time"], selected: $range)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            OutlinedField(placeholder: "Search exercise...", text: $search)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

            if filtered.isEmpty {
                Spacer()
                Text("No sessions logged from Apple Health yet.")
                    .font(.system(size: 15))
                    .foregroundStyle(p.dim)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { s in
                                SessionCard(session: s, isExpanded: expandedId == s.id) {
                                    withAnimation(.easeInOut(duration: 0.25)) { expandedId = expandedId == s.id ? nil : s.id }
                                }
                                .id(s.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .refreshable { await vm.fetchSessions() }
                    .onAppear { applyFocus(proxy) }
                    .onChange(of: focusedSessionId) { _, _ in applyFocus(proxy) }
                }
            }
        }
        .background(p.session)
    }

    private func applyFocus(_ proxy: ScrollViewProxy) {
        guard let id = focusedSessionId else { return }
        expandedId = id
        focusedSessionId = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation { proxy.scrollTo(id, anchor: .top) }
        }
    }

    private var filteredSessions: [ExerciseSessionDto] {
        let q = search.lowercased()
        let days: Double = range == "1W" ? 7 : (range == "1M" ? 30 : 0)
        let threshold = Int64((Date().timeIntervalSince1970 - days * 86400) * 1000)
        return vm.sessions.filter { s in
            let sessionLogs = vm.logs.filter { $0.timestamp >= s.startTime && $0.timestamp <= s.endTime }
            let matches = q.isEmpty || s.displayTitle.lowercased().contains(q) || sessionLogs.contains { $0.exercise.lowercased().contains(q) }
            return matches && (days == 0 || s.startTime >= threshold)
        }
    }
}

struct NativeEmbedPayload: Codable {
    let session: ExerciseSessionDto
    let logs: [LogEntry]
}

private struct SessionCard: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p
    let session: ExerciseSessionDto
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var showWebView = false

    var body: some View {
        let sessionLogs = vm.logs.filter { $0.timestamp >= session.startTime && $0.timestamp <= session.endTime }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(session.displayTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Brand.cyanGlow)
                Spacer()
                Text(isExpanded ? "▲" : "▼").font(.system(size: 12)).foregroundStyle(p.dim)
            }
            Text(Fmt.date(session.startDate, "MMM d, yyyy h:mm a"))
                .font(.system(size: 12)).foregroundStyle(p.dim)
                .padding(.top, 4)
            HStack {
                Text("\(session.durationMinutes) min").foregroundStyle(p.text)
                Spacer()
                Text("\(session.calories.map { "\($0)" } ?? "--") kcal").foregroundStyle(Brand.deepOrange)
                Spacer()
                Text("Avg HR: \(session.avgHeartRate.map { "\($0)" } ?? "--") bpm").foregroundStyle(p.text)
            }
            .font(.system(size: 14))
            .padding(.top, 8)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        stat("Avg HR", "\(session.avgHeartRate.map { "\($0)" } ?? "--") bpm", Brand.electricBlue)
                        stat("Peak HR", "\(session.peakHeartRate.map { "\($0)" } ?? "--") bpm", Brand.deepOrange)
                        stat("Calories", "\(session.calories.map { "\($0)" } ?? "--") kcal", p.text)
                    }
                    .padding(12)
                    .background(p.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                    let samples = session.hrSamples ?? []
                    if !samples.isEmpty {
                        let minHr = min(samples.map { $0.bpm }.min() ?? 60, 60)
                        let maxHr = max(samples.map { $0.bpm }.max() ?? 180, 180)
                        Text("Heart Rate").font(.system(size: 11)).foregroundStyle(p.dim).padding(.top, 12).padding(.bottom, 6)
                        HStack(spacing: 8) {
                            VStack(alignment: .trailing) {
                                Text("\(maxHr)")
                                Spacer()
                                Text("\((maxHr + minHr) / 2)")
                                Spacer()
                                Text("\(minHr)")
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(p.dim)
                            .frame(width: 32)
                            .padding(.vertical, 4)
                            InteractiveHRGraph(
                                samples: samples,
                                durationSec: max(Int((session.endTime - session.startTime) / 1000), 1),
                                minHr: minHr, maxHr: maxHr, interactive: true
                            )
                        }
                        .frame(height: 120)
                        .padding(8)
                        .background(p.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("No detailed HR data available.").font(.system(size: 12)).foregroundStyle(p.dim).padding(.top, 8)
                    }

                    if !sessionLogs.isEmpty {
                        Text("Logged Sets").font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.electricBlue)
                            .padding(.top, 12).padding(.bottom, 4)
                        ForEach(sessionLogs) { log in
                            Text("• \(log.exercise.isEmpty ? "Lifting" : log.exercise) - \(Fmt.weight(log.weightLbs, metric: vm.isMetric)) x \(log.reps)")
                                .font(.system(size: 13)).foregroundStyle(p.text)
                        }
                    }

                    Button(action: { showWebView = true }) {
                        Text("View Detailed Analysis ✨")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Brand.cyanGlow.opacity(0.15))
                            .foregroundStyle(Brand.cyanGlow)
                            .cornerRadius(8)
                    }
                    .padding(.top, 16)
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isExpanded ? Brand.cyanGlow.opacity(0.4) : p.dim.opacity(0.2), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            // Toggle expansion when tapping the card (but button taps will be captured by the Button)
            onToggle()
        }
        .sheet(isPresented: $showWebView) {
            let payload = NativeEmbedPayload(session: session, logs: sessionLogs)
            if let data = try? JSONEncoder().encode(payload) {
                ZStack(alignment: .topTrailing) {
                    p.bg.ignoresSafeArea()
                    SessionAnalysisWebView(sessionData: data)
                    
                    Button(action: { showWebView = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(p.text)
                            .padding()
                    }
                }
            } else {
                Text("Error preparing session data.")
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(p.dim)
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Heart-rate line with the Android gradient stroke (red→orange→green→blue→orange top-to-bottom),
/// a soft fill, and a draggable crosshair showing the nearest bpm.
struct InteractiveHRGraph: View {
    @Environment(\.palette) private var p
    let samples: [HrSample]
    let durationSec: Int
    let minHr: Int
    let maxHr: Int
    var interactive: Bool = true
    var paddingX: CGFloat = 20
    @State private var selected: (CGPoint, Int)?

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack(alignment: .topLeading) {
                if let first = pts.first, let last = pts.last {
                    // Fill
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: geo.size.height))
                        for pt in pts { path.addLine(to: CGPoint(x: pt.x, y: pt.y)) }
                        path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Brand.cyanGlow.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))

                    // Stroke
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: first.y))
                        for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: pt.x, y: pt.y)) }
                    }
                    .stroke(
                        LinearGradient(colors: [.red, Brand.deepOrange, .green, Brand.electricBlue, Brand.cyanGlow], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                }

                if let (pt, bpm) = selected {
                    Path { path in
                        path.move(to: CGPoint(x: pt.x, y: 0))
                        path.addLine(to: CGPoint(x: pt.x, y: geo.size.height))
                    }
                    .stroke(p.dim.opacity(0.6), lineWidth: 0.75)
                    Circle().fill(Brand.cyanGlow.opacity(0.3)).frame(width: 14, height: 14).position(pt)
                    Circle().fill(Brand.cyanGlow).frame(width: 7, height: 7).position(pt)
                    Circle().fill(Brand.whiteText).frame(width: 4, height: 4).position(pt)
                    let pillOnRight = pt.x + 90 < geo.size.width
                    Text("\(bpm) bpm")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Brand.whiteText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.12).opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                        .position(x: pillOnRight ? pt.x + 50 : max(40, pt.x - 50), y: min(max(pt.y, 14), geo.size.height - 14))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard interactive else { return }
                        selected = nearest(to: g.location.x, in: pts)
                    }
            )
        }
    }

    private struct Pt { let x: CGFloat; let y: CGFloat; let bpm: Int }

    private func points(in size: CGSize) -> [Pt] {
        let w = size.width - 2 * paddingX
        let range = CGFloat(max(maxHr - minHr, 1))
        return samples.sorted { $0.timeOffsetSec < $1.timeOffsetSec }.map { s in
            let x = paddingX + CGFloat(s.timeOffsetSec) / CGFloat(max(durationSec, 1)) * w
            let y = size.height - CGFloat(s.bpm - minHr) / range * size.height
            return Pt(x: x, y: y, bpm: s.bpm)
        }
    }

    private func nearest(to x: CGFloat, in pts: [Pt]) -> (CGPoint, Int)? {
        guard let best = pts.min(by: { abs($0.x - x) < abs($1.x - x) }), abs(best.x - x) < 30 else { return nil }
        return (CGPoint(x: best.x, y: best.y), best.bpm)
    }
}
