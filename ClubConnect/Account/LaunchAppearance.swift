import SwiftUI

struct LaunchAppearance: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.brandTheme) private var theme
    let onFinished: () -> Void

    var body: some View {
        Group {
            if reduceMotion || voiceOver {
                Color.clear.onAppear(perform: onFinished)
            } else {
                LaunchArtwork(ink: UIColor(theme.ink), onFinished: onFinished)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onFinished)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct LaunchArtwork: UIViewRepresentable {
    let ink: UIColor
    let onFinished: () -> Void

    func makeUIView(context: Context) -> AnimatedWordmark { AnimatedWordmark() }

    func updateUIView(_ view: AnimatedWordmark, context: Context) {
        view.wordmark.textColor = ink
        view.onFinished = onFinished
    }

    static func dismantleUIView(_ view: AnimatedWordmark, coordinator: ()) {
        view.stop()
    }
}

private final class AnimatedWordmark: UIView, CAAnimationDelegate {
    let wordmark = UILabel()
    var onFinished: (() -> Void)?
    private let lockup = UIView()
    private let mark = CALayer()
    private var displayLink: CADisplayLink?
    private var firstActiveFrame = false
    private var startTime: CFTimeInterval?
    private var lastSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "LaunchPaper")
        clipsToBounds = true
        addSubview(lockup)
        lockup.layer.opacity = 0
        lockup.layer.addSublayer(mark)
        let side = ClubConnectMark.side
        mark.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        for (path, color) in ClubConnectMark.parts {
            let shape = CAShapeLayer()
            shape.frame = mark.bounds
            shape.path = path
            shape.fillColor = color.cgColor
            mark.addSublayer(shape)
        }
        wordmark.text = "Club Connect"
        wordmark.textAlignment = .center
        lockup.addSubview(wordmark)
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { stop(); return }
        guard displayLink == nil, startTime == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(beginWhenVisible))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func beginWhenVisible() {
        guard window?.windowScene?.activationState == .foregroundActive, !bounds.isEmpty else {
            firstActiveFrame = false
            return
        }
        // Let UIKit present an active frame before starting the clock for the readable hold.
        guard firstActiveFrame else { firstActiveFrame = true; return }
        displayLink?.invalidate()
        displayLink = nil
        let start = layer.convertTime(CACurrentMediaTime(), from: nil)
        startTime = start
        animate(startingAt: start)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        lockup.frame = bounds
        let size = min(36, bounds.width * 0.1)
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        wordmark.font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        wordmark.sizeToFit()
        if let startTime { animate(startingAt: startTime) }
    }

    private func animate(startingAt start: CFTimeInterval) {
        let side = min(132, min(bounds.width, bounds.height) * 0.34)
        let initialScale = side / ClubConnectMark.side
        // The center disc extends past every corner, including on a landscape iPad.
        let cover = hypot(bounds.width, bounds.height) * 1.04 / (side * ClubConnectMark.centerFraction)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let markOrigin = CGPoint(x: center.x, y: center.y - 26)
        let nameOrigin = CGPoint(x: center.x, y: markOrigin.y + side * 0.39 + 31)
        let zoomStart = start + 1.05
        let zoomDuration = 1.05

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lockup.layer.opacity = 1
        mark.position = markOrigin
        wordmark.center = nameOrigin
        CATransaction.commit()

        animate(lockup.layer, "opacity", from: 0, to: 1, at: start, duration: 0.34)
        animate(mark, "position", from: markOrigin, to: center, at: zoomStart, duration: 0.5)
        let zoom = CAKeyframeAnimation(keyPath: "transform.scale")
        zoom.values = (0...60).map { index in
            let progress = CGFloat(index) / 60
            return initialScale * pow(cover, progress * (0.1 + 0.9 * progress))
        }
        zoom.beginTime = zoomStart
        zoom.duration = zoomDuration
        zoom.fillMode = .both
        zoom.isRemovedOnCompletion = false
        mark.add(zoom, forKey: "zoom")

        animate(wordmark.layer, "transform.scale", from: 1, to: 1.4, at: zoomStart, duration: 0.34)
        animate(wordmark.layer, "position.y", from: nameOrigin.y, to: nameOrigin.y + 16, at: zoomStart, duration: 0.34)
        animate(wordmark.layer, "opacity", from: 1, to: 0, at: zoomStart + 0.04, duration: 0.29)
        animate(layer, "opacity", from: 1, to: 0, at: zoomStart + zoomDuration, duration: 0.28, finishes: true)
    }

    private func animate(_ layer: CALayer, _ keyPath: String, from: Any, to: Any,
                         at start: CFTimeInterval, duration: CFTimeInterval, finishes: Bool = false) {
        let change = CABasicAnimation(keyPath: keyPath)
        change.fromValue = from
        change.toValue = to
        change.beginTime = start
        change.duration = duration
        change.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        change.fillMode = .both
        change.isRemovedOnCompletion = false
        if finishes { change.delegate = self }
        layer.add(change, forKey: keyPath)
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if flag { onFinished?() }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        onFinished = nil
        layer.removeAllAnimations()
    }
}
