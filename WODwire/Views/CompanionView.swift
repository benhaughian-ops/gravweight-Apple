import SwiftUI

/// BARBELL tab — the phone companion for the watch's plate loader.
struct CompanionView: View {
    @EnvironmentObject private var vm: PhoneViewModel
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Header ──
                VStack(spacing: 2) {
                    Text("WODwire")
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(Brand.cyanGlow)
                        .shadow(color: Brand.cyanGlow.opacity(0.5), radius: 8)
                    Text("companion")
                        .font(.system(size: 11, weight: .light))
                        .tracking(2)
                        .foregroundStyle(p.dim)
                }
                .padding(.top, 20)

                // Watch-connected pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.isWatchConnected ? Brand.cyanGlow : Brand.deepOrange)
                        .frame(width: 8, height: 8)
                    Text(vm.isWatchConnected ? "WATCH CONNECTED" : "WATCH DISCONNECTED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(vm.isWatchConnected ? Brand.cyanGlow : Brand.deepOrange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background((vm.isWatchConnected ? Brand.cyanGlow : Brand.deepOrange).opacity(0.12), in: Capsule())
                .padding(.top, 12)

                // ── Load readout ──
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(vm.state.totalLoadNumber)
                        .font(.system(size: 60, weight: .heavy))
                        .foregroundStyle(Brand.cyanGlow)
                        .shadow(color: Brand.cyanGlow.opacity(0.6), radius: 12)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.25), value: vm.state.totalLoad)
                    Text(vm.state.unitLabel)
                        .font(.system(size: 18, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Brand.electricBlue)
                }
                .padding(.top, 20)
                Text("BARBELL LOAD")
                    .font(.system(size: 11))
                    .tracking(2)
                    .foregroundStyle(p.dim)
                    .padding(.top, 2)

                // ── Plate rows ──
                VStack(spacing: 8) {
                    ForEach(vm.state.activePlates) { plate in
                        PhonePlateRow(
                            plate: plate,
                            count: vm.state.count(plate),
                            onAdd: { vm.addPlate(plate) },
                            onRemove: { vm.removePlate(plate) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                // ── Actions ──
                HStack(spacing: 12) {
                    Button {
                        vm.logWorkout()
                        vm.showToast("Log successful!")
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Label("LOG", systemImage: "checkmark")
                            .font(.system(size: 15, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(p.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(p.glass, in: RoundedRectangle(cornerRadius: 26))
                            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Brand.cyanGlow.opacity(0.55), lineWidth: 1.5))
                    }
                    Button {
                        vm.clear()
                    } label: {
                        Text("CLEAR")
                            .font(.system(size: 15, weight: .heavy))
                            .tracking(3)
                            .foregroundStyle(p.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(p.glass, in: RoundedRectangle(cornerRadius: 26))
                            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Brand.deepOrange.opacity(0.55), lineWidth: 1.5))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .background(p.bg)
    }
}

private struct PhonePlateRow: View {
    @Environment(\.palette) private var p
    let plate: PlateType
    let count: Int
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let active = count > 0
        HStack {
            RoundGlowButton(symbol: "minus", color: active ? Brand.electricBlue : p.dim.opacity(0.3), filled: active, action: onRemove)
            Spacer()
            VStack(spacing: 2) {
                Text(plate.displayLabel.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(active ? p.text : p.plate)
                Text(active ? "× \(count)/side" : "—")
                    .font(.system(size: 14, weight: active ? .bold : .light))
                    .foregroundStyle(active ? Brand.cyanGlow : p.dim.opacity(0.5))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: count)
            }
            Spacer()
            RoundGlowButton(symbol: "plus", color: Brand.cyanGlow, filled: true, action: onAdd)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(active ? p.glass : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(active ? Brand.cyanGlow.opacity(0.35) : p.dim.opacity(0.12), lineWidth: 1))
        .animation(.easeInOut(duration: 0.25), value: active)
    }
}

/// Round − / + button (44pt) with a soft glow fill.
struct RoundGlowButton: View {
    let symbol: String
    let color: Color
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(filled ? color.opacity(0.15) : Color.clear, in: Circle())
                .overlay(Circle().stroke(color.opacity(filled ? 0.7 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
