import SwiftUI

/// Vertical throttle/brake control with spring-back-to-center. Fills whatever
/// frame the parent gives it. In edit mode it ignores drags (parent repositions).
struct ThrottleBrakeSlider: View {
    let editing: Bool
    @EnvironmentObject var controller: GameController
    @EnvironmentObject var settings: AppSettings
    private let thumbRadius: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let center = h / 2
            let travel = max(1, center - thumbRadius)
            let value = controller.throttle - controller.brake          // -1...1
            let thumbY = center - CGFloat(value) * travel
            let trackW = min(w, 54)

            let thrColor = ButtonPalette.color(settings.throttleColorIndex)
            let brkColor = ButtonPalette.color(settings.brakeColorIndex)
            let stack = ZStack {
                Capsule().fill(Color.white.opacity(0.08)).frame(width: trackW)
                Capsule().fill(thrColor.opacity(0.6))
                    .frame(width: trackW, height: CGFloat(controller.throttle) * travel)
                    .position(x: w / 2, y: center - CGFloat(controller.throttle) * travel / 2)
                Capsule().fill(brkColor.opacity(0.6))
                    .frame(width: trackW, height: CGFloat(controller.brake) * travel)
                    .position(x: w / 2, y: center + CGFloat(controller.brake) * travel / 2)
                Rectangle().fill(Color.white.opacity(0.4)).frame(width: trackW, height: 2)
                    .position(x: w / 2, y: center)
                Text("THR").font(.caption2).foregroundStyle(.white.opacity(0.6)).position(x: w / 2, y: thumbRadius)
                Text("BRK").font(.caption2).foregroundStyle(.white.opacity(0.6)).position(x: w / 2, y: h - thumbRadius)
                Circle().fill(Color.white).frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .shadow(radius: 4).position(x: w / 2, y: thumbY)
            }
            .frame(width: w, height: h)
            .opacity(settings.controlOpacity)
            .contentShape(Rectangle())
            .overlay(editing ? RoundedRectangle(cornerRadius: 12).stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5])) : nil)

            if editing {
                stack
            } else {
                stack.gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let y = min(max(g.location.y, thumbRadius), h - thumbRadius)
                            let v = min(max(Double((center - y) / travel), -1), 1)
                            if v >= 0 { controller.setThrottleBrake(throttle: v, brake: 0) }
                            else      { controller.setThrottleBrake(throttle: 0, brake: -v) }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                controller.setThrottleBrake(throttle: 0, brake: 0)
                            }
                        }
                )
            }
        }
    }
}
