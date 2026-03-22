//
//  CouplingView.swift
//  codewake
//
//  Created by Luis Resendez on 22/03/2026.
//

import CodewakeKit
import SwiftUI

/// The coupling map: which files keep changing together, across the whole snapshot.
///
/// The inspector already answers this for one file, but only once you have guessed which
/// file to click. This is the same fact without the guess — every group of files that moves
/// as a unit, laid out so a region of the codebase that is quietly welded together shows up
/// on its own.
///
/// Deliberately not a treemap. The other three views are about a property each file has;
/// this one is about a relation between files, and rectangles cannot draw a relation.
struct CouplingView: View {
    let report: CouplingReport
    let isLoading: Bool
    let selection: FileID?
    let onSelect: (FileID?) -> Void

    @State private var hovered: FileID?
    @State private var pointer: CGPoint = .zero

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 14, dy: 14)
            let nodes = layout(in: bounds)

            Canvas { context, _ in
                draw(nodes, in: &context)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    pointer = point
                    hovered = node(at: point, in: nodes)?.id
                case .ended:
                    hovered = nil
                }
            }
            .onTapGesture { point in onSelect(node(at: point, in: nodes)?.id) }
            .overlay(alignment: .topLeading) {
                if let hovered, let node = nodes.first(where: { $0.id == hovered }) {
                    tooltip(for: node)
                        .fixedSize()
                        .offset(
                            x: min(pointer.x + 12, max(proxy.size.width - 300, 0)),
                            y: min(pointer.y + 12, max(proxy.size.height - 60, 0))
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Palette.canvas)
        .overlay {
            if isLoading {
                ProgressView().controlSize(.small)
            } else if report.clusters.isEmpty {
                emptyState
            }
        }
    }

    // MARK: - Layout

    private struct Node: Identifiable {
        let id: FileID
        let name: String
        let center: CGPoint
        let radius: CGFloat
        let cluster: Int
        /// Unit vector pointing away from the ring's middle, which is the only direction a
        /// label can grow without landing on a neighbour's.
        let outward: CGVector
    }

    private struct Edge {
        let from: CGPoint
        let to: CGPoint
        let degree: Double
    }

    /// Room set aside outside each ring for the names hanging off it.
    private static let labelWidth: CGFloat = 100
    private static let labelHeight: CGFloat = 26

    /// Clusters are packed into a grid of cells, strongest first, and each cluster's files
    /// are placed on a circle inside its cell. A circle rather than a force simulation
    /// because the arrangement has to be the same every frame — this view is redrawn on
    /// every scrub tick, and a layout that drifted would make the map impossible to read
    /// while the playhead moves.
    private func layout(in bounds: CGRect) -> [Node] {
        let clusters = report.clusters
        guard !clusters.isEmpty, bounds.width > 40, bounds.height > 40 else { return [] }

        let columns = clusters.count <= 2 ? clusters.count : Int(ceil(sqrt(Double(clusters.count))))
        let rows = Int(ceil(Double(clusters.count) / Double(columns)))
        let cell = CGSize(width: bounds.width / CGFloat(columns), height: bounds.height / CGFloat(rows))

        return clusters.enumerated().flatMap { index, cluster -> [Node] in
            let origin = CGPoint(
                x: bounds.minX + CGFloat(index % columns) * cell.width,
                y: bounds.minY + CGFloat(index / columns) * cell.height
            )
            let center = CGPoint(x: origin.x + cell.width / 2, y: origin.y + cell.height / 2)
            let nodeRadius = min(max(min(cell.width, cell.height) * 0.07, 4), 11)
            // Labels sit outside the ring and grow outward, so the ring has to leave room
            // for a whole name to the left and right of it, not just above and below.
            // Without this the names of one cluster run into the next one's.
            let ringRadius = max(
                min(
                    cell.height / 2 - nodeRadius - Self.labelHeight,
                    cell.width / 2 - nodeRadius - Self.labelWidth
                ),
                16
            )

            return cluster.files.enumerated().map { offset, id in
                let position: CGPoint
                var outward = CGVector(dx: 0, dy: 1)
                if cluster.files.count == 1 {
                    position = center
                } else {
                    // Start at the top and go clockwise, so the busiest file is always at
                    // twelve o'clock and the shape is recognisable from one frame to the next.
                    let angle = -.pi / 2 + 2 * .pi * Double(offset) / Double(cluster.files.count)
                    position = CGPoint(
                        x: center.x + ringRadius * cos(angle),
                        y: center.y + ringRadius * sin(angle)
                    )
                    outward = CGVector(dx: cos(angle), dy: sin(angle))
                }
                return Node(
                    id: id,
                    name: Self.shortened(String(report.path(id).split(separator: "/").last ?? "")),
                    center: position,
                    radius: nodeRadius,
                    cluster: index,
                    outward: outward
                )
            }
        }
    }

    // MARK: - Drawing

    private func draw(_ nodes: [Node], in context: inout GraphicsContext) {
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for cluster in report.clusters {
            for pair in cluster.pairs {
                guard let from = byID[pair.a], let to = byID[pair.b] else { continue }
                // Weight and brightness both carry the degree, so a tight pair reads as one
                // even where the diagram is dense.
                let emphasis = (pair.degree - 0.5) / 0.5
                var path = Path()
                path.move(to: from.center)
                path.addLine(to: to.center)
                context.stroke(
                    path,
                    with: .color(Palette.coupling.opacity(0.20 + 0.55 * emphasis)),
                    lineWidth: 0.8 + 2.0 * emphasis
                )
            }
        }

        for node in nodes {
            let isSelected = node.id == selection
            let isHovered = node.id == hovered
            context.fill(
                Path(ellipseIn: CGRect(
                    x: node.center.x - node.radius, y: node.center.y - node.radius,
                    width: node.radius * 2, height: node.radius * 2
                )),
                with: .color(isSelected || isHovered ? .white : Palette.coupling)
            )

            // Pushed away from the middle of its ring and anchored so it grows outward,
            // which is what keeps a name off its neighbour's.
            let gap = node.radius + 7
            context.draw(
                Text(node.name)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected || isHovered ? Palette.primaryText : Palette.secondaryText),
                at: CGPoint(
                    x: node.center.x + node.outward.dx * gap,
                    y: node.center.y + node.outward.dy * gap
                ),
                anchor: Self.anchor(for: node.outward)
            )
        }
    }

    /// Nodes on the left of a ring get their name to the left of them, nodes on the right
    /// to the right, and nodes at the top and bottom get it centred above or below.
    private static func anchor(for outward: CGVector) -> UnitPoint {
        if outward.dx < -0.35 { return .trailing }
        if outward.dx > 0.35 { return .leading }
        return outward.dy < 0 ? .bottom : .top
    }

    /// Long component names would otherwise overrun the cell beside them.
    private static func shortened(_ name: String) -> String {
        guard name.count > 16 else { return name }
        return name.prefix(15) + "…"
    }

    private func node(at point: CGPoint, in nodes: [Node]) -> Node? {
        // A generous target: the circles are small, and the label under one counts as it.
        nodes.min { a, b in distance(a.center, point) < distance(b.center, point) }
            .flatMap { distance($0.center, point) < max($0.radius * 2.5, 16) ? $0 : nil }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func tooltip(for node: Node) -> some View {
        let partners = report.clusters
            .first { $0.id == node.cluster }?
            .pairs
            .filter { $0.a == node.id || $0.b == node.id }
            .sorted { $0.degree > $1.degree } ?? []

        return TreemapTooltip {
            Text(report.path(node.id))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.primaryText)
            ForEach(partners.prefix(4), id: \.self) { pair in
                let other = pair.a == node.id ? pair.b : pair.a
                Text("\(Int((pair.degree * 100).rounded()))% with \(String(report.path(other).split(separator: "/").last ?? "")) · \(pair.sharedCommits) shared commits")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nothing changes together yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Text("A pair has to share several commits before it has demonstrated anything.\nScrub forward.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.faintText)
                .multilineTextAlignment(.center)
        }
    }
}
