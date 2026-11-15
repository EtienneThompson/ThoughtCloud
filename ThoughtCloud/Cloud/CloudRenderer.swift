import SwiftUI
import ThoughtCloudKit

nonisolated extension GraphPoint {
    init(_ point: CGPoint) { self.init(Double(point.x), Double(point.y)) }
    init(_ size: CGSize) { self.init(Double(size.width), Double(size.height)) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// Draws one frame of the Cloud from plain values (no observation, no state).
nonisolated enum CloudRenderer {
    struct Frame {
        var graph: CloudGraph
        var positions: [GraphNodeID: GraphPoint]
        var camera: GraphCamera
        var viewSize: GraphPoint
        var selection: GraphNodeID?
        var highlighted: Set<GraphNodeID>
        var time: Double
    }

    static let hubRadius = 14.0
    static let itemRadius = 6.0

    static func draw(_ ctx: inout GraphicsContext, _ f: Frame) {
        let zoom = f.camera.zoom
        let hasSelection = f.selection != nil
        func screen(_ id: GraphNodeID) -> CGPoint? {
            f.positions[id].map { f.camera.toScreen($0, viewSize: f.viewSize).cgPoint }
        }

        // Edges
        for edge in f.graph.edges {
            guard let a = screen(edge.a), let b = screen(edge.b) else { continue }
            let lit = hasSelection && (edge.a == f.selection || edge.b == f.selection)
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            let opacity: Double = lit ? 0.6 : hasSelection ? 0.04 : (edge.kind == .membership ? 0.11 : 0.24)
            let style = StrokeStyle(lineWidth: lit ? 1.4 : (edge.kind == .membership ? 0.8 : 1), dash: edge.kind == .link && !lit ? [3, 3] : [])
            ctx.stroke(path, with: .color(.white.opacity(opacity)), style: style)
        }

        let labelOpacity = f.camera.labelOpacity
        let bounds = CGRect(x: -60, y: -60, width: f.viewSize.x + 120, height: f.viewSize.y + 120)

        // Items first, hubs on top.
        for node in f.graph.nodes.sorted(by: { !$0.isHub && $1.isHub }) {
            guard let p = screen(node.id), bounds.contains(p) else { continue }
            var c = ctx
            let dim = hasSelection && !f.highlighted.contains(node.id)
            c.opacity = dim ? 0.15 : 1

            switch node.role {
            case .hub(let emoji, let hex):
                let color = Color(hex: hex)
                let r = hubRadius * max(zoom, 0.6)
                let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                c.fill(circle, with: .color(color.opacity(0.22)))
                c.stroke(circle, with: .color(color), lineWidth: node.id == f.selection ? 2.5 : 1.5)
                c.draw(Text(emoji).font(.system(size: r * 1.05)), at: p)
                c.draw(Text(node.label).font(.system(size: 11, weight: .semibold)).foregroundColor(color), at: CGPoint(x: p.x, y: p.y + r + 9))

            case .item(let kind, let style):
                let s = max(2.5, itemRadius * zoom)
                if node.isFaded { c.opacity *= 0.35 }
                if node.isDue {
                    let pulse = (sin(f.time * 2 * .pi / 1.9) + 1) / 2
                    let rr = s + 3 + pulse * 3
                    c.stroke(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                             with: .color(style.primary.opacity(0.25 + pulse * 0.6)), lineWidth: 1.5)
                }
                if node.isOverdue {
                    let rr = s + 4
                    c.stroke(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                             with: .color(Theme.danger), style: StrokeStyle(lineWidth: 1.6, dash: [2, 2]))
                }
                let shape = shapePath(kind, p, s)
                c.fill(shape, with: fill(style, p, s))
                if case .many = style, labelOpacity > 0 {
                    let ring = style.ringHexes
                    let rr = s + 2.5
                    for (i, hex) in ring.enumerated() {
                        var arc = Path()
                        let start = Angle(radians: Double(i) / Double(ring.count) * 2 * .pi - .pi / 2)
                        let end = Angle(radians: Double(i + 1) / Double(ring.count) * 2 * .pi - .pi / 2)
                        arc.addArc(center: p, radius: rr, startAngle: start, endAngle: end, clockwise: false)
                        c.stroke(arc, with: .color(Color(hex: hex).opacity(labelOpacity)), lineWidth: 1.8)
                    }
                }
                if node.id == f.selection {
                    c.stroke(shapePath(kind, p, s + 3), with: .color(.white), lineWidth: 2)
                }
                let la = f.highlighted.contains(node.id) ? max(labelOpacity, 0.95) : labelOpacity
                if la > 0 {
                    var lc = c
                    lc.opacity *= la
                    drawLabel(&lc, node.label, at: CGPoint(x: p.x, y: p.y + s + 4), faded: node.isFaded)
                }
            }
        }
    }

    static func shapePath(_ kind: ItemKind, _ p: CGPoint, _ s: Double) -> Path {
        switch kind {
        case .thought:
            return Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: s * 2, height: s * 2))
        case .todo:
            return Path(roundedRect: CGRect(x: p.x - s * 0.9, y: p.y - s * 0.9, width: s * 1.8, height: s * 1.8), cornerRadius: s * 0.35)
        case .review:
            var path = Path()
            path.move(to: CGPoint(x: p.x, y: p.y - s * 1.2))
            path.addLine(to: CGPoint(x: p.x + s * 1.2, y: p.y))
            path.addLine(to: CGPoint(x: p.x, y: p.y + s * 1.2))
            path.addLine(to: CGPoint(x: p.x - s * 1.2, y: p.y))
            path.closeSubpath()
            return path
        case .event:
            // Hexagon.
            var path = Path()
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3
                let point = CGPoint(x: p.x + cos(angle) * s * 1.1, y: p.y + sin(angle) * s * 1.1)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }

    static func fill(_ style: CategoryStyle, _ p: CGPoint, _ s: Double) -> GraphicsContext.Shading {
        let colors = style.colors
        guard colors.count == 2 else { return .color(colors[0]) }
        let gradient = Gradient(stops: [
            .init(color: colors[0], location: 0), .init(color: colors[0], location: 0.5),
            .init(color: colors[1], location: 0.5), .init(color: colors[1], location: 1),
        ])
        return .linearGradient(gradient, startPoint: CGPoint(x: p.x - s * 1.2, y: p.y), endPoint: CGPoint(x: p.x + s * 1.2, y: p.y))
    }

    static func drawLabel(_ c: inout GraphicsContext, _ text: String, at top: CGPoint, faded: Bool) {
        let short = text.count > 28 ? String(text.prefix(27)) + "…" : text
        let resolved = c.resolve(Text(short).font(.system(size: 11)).foregroundColor(faded ? Theme.dim : Theme.text))
        let size = resolved.measure(in: CGSize(width: 220, height: 40))
        let rect = CGRect(x: top.x - size.width / 2 - 4, y: top.y, width: size.width + 8, height: size.height + 3)
        c.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(Theme.background.opacity(0.75)))
        c.draw(resolved, at: CGPoint(x: top.x, y: top.y + 1.5), anchor: .top)
    }
}
