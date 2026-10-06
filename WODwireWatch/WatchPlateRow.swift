import SwiftUI

/// One plate row:  ( − )  45 lb  × 2  ( + )
struct WatchPlateRow: View {
    let plate: PlateType
    let count: Int
    let onAdd: () -> Void
    let onRemove: () -> Void

    private var active: Bool { count > 0 }

    var body: some View {
        HStack(spacing: 6) {
            circleButton("minus", color: active ? Brand.electricBlue : Brand.dimText.opacity(0.3), action: onRemove)
                .disabled(!active)

            VStack(spacing: 0) {
                Text(plate.displayLabel.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active ? Brand.whiteText : Brand.plateGray)
                if active {
                    Text("× \(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Brand.cyanGlow)
                        .shadow(color: Brand.cyanGlow.opacity(0.6), radius: 4)
                        .contentTransition(.numericText())
                } else {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.dimText.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: count)

            circleButton("plus", color: Brand.cyanGlow, action: onAdd)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(active ? Brand.glass : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(active ? Brand.cyanGlow.opacity(0.35) : Brand.dimText.opacity(0.12), lineWidth: 1)
        )
    }

    private func circleButton(_ symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15), in: Circle())
                .overlay(Circle().stroke(color.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
