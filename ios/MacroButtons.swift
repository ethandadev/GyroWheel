import SwiftUI
import UIKit

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum ButtonPalette {
    static let colors: [Color] = [.green, .red, .blue, .yellow, .orange, .purple, .teal, .pink]
    static let names  = ["Green", "Red", "Blue", "Yellow", "Orange", "Purple", "Teal", "Pink"]
    static func color(_ index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }
}

enum Haptics {
    private static let generator = UIImpactFeedbackGenerator(style: .medium)
    static func tap(_ enabled: Bool) { guard enabled else { return }; generator.impactOccurred() }
}

/// A single macro button. In edit mode it ignores presses (the parent handles
/// drag-to-reposition); otherwise it reports presses per its behavior mode.
struct MacroButton: View {
    let index: Int
    let editing: Bool
    @EnvironmentObject var controller: GameController
    @EnvironmentObject var settings: AppSettings
    @State private var latched = false

    private var isDown: Bool { controller.buttons[safe: index] ?? false }
    private var color: Color { ButtonPalette.color(settings.buttonColors[safe: index] ?? index) }
    private var label: String { settings.buttonLabels[safe: index] ?? "?" }
    private var diameter: CGFloat { CGFloat(settings.buttonSize[safe: index] ?? 86) }

    private var shape: AnyShape {
        settings.buttonShape == 0 ? AnyShape(Circle())
                                  : AnyShape(RoundedRectangle(cornerRadius: diameter * 0.24))
    }

    var body: some View {
        let s = shape
        let view = s
            .fill(color.opacity(isDown ? 0.95 : 0.30))
            .overlay(s.stroke(color, lineWidth: 3))
            .overlay(
                Text(label)
                    .font(.system(size: max(14, diameter * 0.30), weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.4).lineLimit(1)
                    .foregroundStyle(.white).padding(6)
            )
            .frame(width: diameter, height: diameter)
            .opacity(settings.controlOpacity * (editing ? 0.9 : 1.0))
            .scaleEffect(isDown ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isDown)
            .overlay(editing ? s.stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5])) : nil)

        if editing {
            view
        } else {
            view.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !latched {
                            latched = true
                            controller.buttonDown(index)
                            Haptics.tap(settings.hapticsEnabled)
                        }
                    }
                    .onEnded { _ in latched = false; controller.buttonUp(index) }
            )
        }
    }
}
