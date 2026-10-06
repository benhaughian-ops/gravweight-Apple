import SwiftUI

/// Head-to-head comparison with a friend (Android VersusScreen.kt).
struct VersusView: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: PhoneViewModel
    let friendId: String

    static let meColor = Color(hex: 0xFF8A1F)
    static let themColor = Color(hex: 0x38BDF8)

    @State private var data: CompareResponse?
    @State private var errorText: String?
    @State private var loading = true
    @State private var animate = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(p.text)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("VERSUS").font(.system(size: 14, weight: .heavy)).tracking(3).foregroundStyle(Brand.cyanGlow)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 8)

            if loading && data == nil {
                Spacer()
                ProgressView().tint(Brand.cyanGlow)
                Spacer()
            } else if let errorText {
                Spacer()
                Text(errorText).font(.system(size: 15)).foregroundStyle(p.dim).multilineTextAlignment(.center).padding(32)
                Spacer()
            } else if let data {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        faceOff(data)
                        let cats = data.categories ?? []
                        if !cats.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionLabel(text: "THIS MONTH")
                                ForEach(cats) { c in TugBar(category: c, animate: animate) }
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "LIFT DUEL · BEST e1RM")
                            let lifts = data.lifts ?? []
                            if lifts.isEmpty {
                                Text("No shared lifts yet — log the same exercise to start a duel.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(p.dim)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .multilineTextAlignment(.center)
                                    .padding(20)
                                    .background(p.glass, in: RoundedRectangle(cornerRadius: 14))
                            } else {
                                ForEach(lifts) { l in DuelRow(lift: l, themName: firstName(data.them?.name)) }
                            }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await load() }
            }
        }
        .background(p.bg.ignoresSafeArea())
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            data = try await vm.compare(friendId: friendId)
            errorText = nil
            animate = false
            withAnimation(.easeOut(duration: 0.9).delay(0.1)) { animate = true }
        } catch let e as APIClient.HTTPError where e.code == 403 {
            errorText = "You need to be friends to compare"
        } catch {
            errorText = "Couldn't load comparison"
        }
    }

    private func firstName(_ name: String?) -> String {
        let n = (name ?? "Them").split(separator: " ").first.map { "\($0)" } ?? "Them"
        return n.isEmpty ? "Them" : n
    }

    private func faceOff(_ d: CompareResponse) -> some View {
        let me = d.score?.me ?? 0
        let them = d.score?.them ?? 0
        let verdict = me > them ? "You're ahead 🔥" : (them > me ? "\(firstName(d.them?.name)) leads — time to train 😤" : "Dead even ⚖️")
        return VStack(spacing: 14) {
            HStack(alignment: .center) {
                fighter(d.me?.name ?? "You", d.me?.avatarUrl, Self.meColor, label: "You")
                Spacer()
                HStack(spacing: 6) {
                    Text("\(me)").foregroundStyle(Self.meColor)
                    Text(":").foregroundStyle(p.dim)
                    Text("\(them)").foregroundStyle(Self.themColor)
                }
                .font(.system(size: 30, weight: .heavy))
                .contentTransition(.numericText())
                Spacer()
                fighter(d.them?.name ?? "Them", d.them?.avatarUrl, Self.themColor, label: firstName(d.them?.name))
            }
            Text(verdict)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(p.text)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Self.meColor.opacity(0.22), Self.themColor.opacity(0.22)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private func fighter(_ name: String, _ avatar: String?, _ color: Color, label: String) -> some View {
        VStack(spacing: 6) {
            UserAvatar(avatarUrl: avatar, name: name, size: 68)
                .overlay(Circle().stroke(color, lineWidth: 3))
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(p.text).lineLimit(1)
        }
        .frame(width: 90)
    }
}

/// Animated split bar for one category; 👑 marks the winner.
struct TugBar: View {
    @Environment(\.palette) private var p
    let category: CompareCategoryDto
    let animate: Bool

    var body: some View {
        let total = category.me + category.them
        let share = total > 0 ? category.me / total : 0.5
        let unit = category.unit.isEmpty ? "" : " (\(category.unit))"
        VStack(spacing: 6) {
            HStack {
                Text((category.winner == "me" ? "👑 " : "") + Fmt.trim(category.me.rounded()))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(VersusView.meColor)
                Spacer()
                Text(category.label + unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.dim)
                Spacer()
                Text(Fmt.trim(category.them.rounded()) + (category.winner == "them" ? " 👑" : ""))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(VersusView.themColor)
            }
            GeometryReader { geo in
                let meW = geo.size.width * CGFloat(animate ? share : 0.5)
                HStack(spacing: 2) {
                    Capsule().fill(VersusView.meColor).frame(width: max(meW - 1, 4))
                    Capsule().fill(VersusView.themColor)
                }
            }
            .frame(height: 10)
        }
        .padding(14)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// One shared lift: best e1RM per side, trophy on the winner.
struct DuelRow: View {
    @Environment(\.palette) private var p
    let lift: SharedLiftDto
    let themName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lift.exercise.uppercased())
                .font(.system(size: 13, weight: .heavy)).tracking(1).foregroundStyle(p.text)
            side("You", lift.me?.best ?? 0, VersusView.meColor, won: lift.winner == "me")
            side(themName, lift.them?.best ?? 0, VersusView.themColor, won: lift.winner == "them")
        }
        .padding(14)
        .background(p.glass, in: RoundedRectangle(cornerRadius: 14))
    }

    private func side(_ name: String, _ value: Double, _ color: Color, won: Bool) -> some View {
        let maxV = max(lift.me?.best ?? 0, lift.them?.best ?? 0, 1)
        return HStack(spacing: 10) {
            Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.dim).frame(width: 60, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                Capsule().fill(color.opacity(won ? 1 : 0.55))
                    .frame(width: max(geo.size.width * CGFloat(value / maxV), 4))
            }
            .frame(height: 8)
            Text("\(Fmt.trim(value.rounded())) lb" + (won ? " 🏆" : ""))
                .font(.system(size: 13, weight: .bold)).foregroundStyle(color)
                .frame(width: 92, alignment: .trailing)
        }
    }
}
