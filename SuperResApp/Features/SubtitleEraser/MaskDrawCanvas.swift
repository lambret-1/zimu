import SwiftUI
import UIKit

struct MaskDrawCanvas: UIViewRepresentable {
    var committedStrokes: [MaskStroke]
    var tool: MaskBrushTool
    var brushWidth: CGFloat
    var isEnabled: Bool
    var onStrokeCommitted: (MaskStroke) -> Void
    var onDrawingChanged: ((Bool) -> Void)?

    func makeUIView(context: Context) -> MaskCanvasUIView {
        let view = MaskCanvasUIView()
        configure(view)
        return view
    }

    func updateUIView(_ uiView: MaskCanvasUIView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: MaskCanvasUIView) {
        view.tool = tool
        view.brushWidth = brushWidth
        view.committedStrokes = committedStrokes
        view.onStrokeCommitted = onStrokeCommitted
        view.onDrawingChanged = onDrawingChanged
        view.isUserInteractionEnabled = isEnabled
    }
}

final class MaskCanvasUIView: UIView, UIGestureRecognizerDelegate {
    var committedStrokes: [MaskStroke] = [] {
        didSet { setNeedsDisplay() }
    }
    var tool: MaskBrushTool = .brush
    var brushWidth: CGFloat = 20
    var onStrokeCommitted: ((MaskStroke) -> Void)?
    var onDrawingChanged: ((Bool) -> Void)?

    private var currentPoints: [NormalizedPoint] = []
    private var currentTool: MaskBrushTool = .brush
    private var currentNormalizedWidth: Double = 0

    private lazy var panRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        addGestureRecognizer(panRecognizer)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.clear(bounds)
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        committedStrokes.forEach { render($0, in: context) }
        if !currentPoints.isEmpty {
            render(MaskStroke(
                tool: currentTool,
                brushWidth: currentNormalizedWidth,
                points: currentPoints
            ), in: context)
        }
    }

    private func render(_ stroke: MaskStroke, in context: CGContext) {
        guard !stroke.points.isEmpty else { return }
        let width = MaskCanvasEngine.ptWidth(for: stroke.brushWidth, canvasSize: bounds.size)
        guard width > 0 else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(width)

        switch stroke.tool {
        case .brush:
            context.setBlendMode(.normal)
            context.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.45).cgColor)
            context.setFillColor(UIColor.systemRed.withAlphaComponent(0.45).cgColor)
        case .eraser:
            context.setBlendMode(.clear)
            context.setStrokeColor(UIColor.clear.cgColor)
            context.setFillColor(UIColor.clear.cgColor)
        }

        let points = stroke.points.map { $0.toCGPoint(in: bounds.size) }
        guard let first = points.first else { return }
        if points.count == 1 {
            let radius = width / 2
            context.fillEllipse(in: CGRect(
                x: first.x - radius, y: first.y - radius, width: width, height: width
            ))
            return
        }
        context.beginPath()
        context.move(to: first)
        points.dropFirst().forEach { context.addLine(to: $0) }
        context.strokePath()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let canvasSize = bounds.size
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

        switch recognizer.state {
        case .began:
            let location = recognizer.location(in: self)
            currentTool = tool
            currentNormalizedWidth = MaskCanvasEngine.normalizedBrushWidth(
                ptWidth: brushWidth, canvasSize: canvasSize
            )
            currentPoints = [MaskCanvasEngine.normalizedPoint(from: location, in: canvasSize)]
            onDrawingChanged?(true)
            setNeedsDisplay()
        case .changed:
            let location = recognizer.location(in: self)
            let point = MaskCanvasEngine.normalizedPoint(from: location, in: canvasSize)
            if MaskCanvasEngine.shouldAppend(point, after: currentPoints.last) {
                currentPoints.append(point)
                setNeedsDisplay()
            }
        case .ended:
            commitCurrentStroke()
        case .cancelled, .failed:
            clearCurrentStroke()
        default:
            break
        }
    }

    private func commitCurrentStroke() {
        defer { clearCurrentStroke() }
        guard !currentPoints.isEmpty else { return }
        let points = MaskCanvasEngine.smoothed(currentPoints)
        guard !points.isEmpty else { return }
        onStrokeCommitted?(MaskStroke(
            tool: currentTool,
            brushWidth: currentNormalizedWidth,
            points: points
        ))
    }

    private func clearCurrentStroke() {
        currentPoints.removeAll(keepingCapacity: true)
        onDrawingChanged?(false)
        setNeedsDisplay()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === panRecognizer else { return true }
        return touch.location(in: self).x >= 20
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
