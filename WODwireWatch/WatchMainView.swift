import SwiftUI

/// Watch main screen — same layout as the Wear OS `WatchScreen`:
/// header + glowing total, one row per plate, LOG WEIGHT and CLEAR.
struct WatchMainView: View {
    @EnvironmentObject private var vm: WatchViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    header
                        .id("top")
                        .padding(.bottom, 4)

                    ForEach(vm.state.activePlates) { plate in
                        WatchPlateRow(
                            plate: plate,
                            count: vm.state.count(plate),
                            onAdd: { vm.addPlate(plate) },
                            onRemove: { vm.removePlate(plate) }
                        )
                    }

                    Button {
                        vm.logWeight()
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
                    } label: {
                        Text("LOG WEIGHT")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(Brand.cyanGlow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Brand.glass, in: RoundedRectangle(cornerRadius: 28))
                            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Brand.cyanGlow.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)

                    Button { vm.clear() } label: {
                        Text("CLEAR")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(3)
                            .foregroundStyle(Brand.deepOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Brand.glass, in: RoundedRectangle(cornerRadius: 28))
                            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Brand.deepOrange.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 6)
            }
        }
        .background(Brand.spaceBlack.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let toast = vm.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .overlay(Capsule().stroke(Brand.cyanGlow.opacity(0.6), lineWidth: 1))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 2)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("WODwire")
                .font(.system(size: 9, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(Brand.cyanGlow.opacity(0.75))
            Text("BARBELL LOAD")
                .font(.system(size: 8, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Brand.dimText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(vm.state.totalLoadNumber)
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(Brand.cyanGlow)
                    .shadow(color: Brand.cyanGlow.opacity(0.7), radius: 8)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.state.totalLoad)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(vm.state.unitLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.electricBlue)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
