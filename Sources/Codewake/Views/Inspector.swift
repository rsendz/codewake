//
//  Inspector.swift
//  codewake
//
//  Created by Luis Resendez on 08/03/2026.
//

import SwiftUI

/// Shared inspector chrome, so every panel that hangs off the map reads as one design.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.faintText)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InspectorRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.primaryText)
        }
    }
}
