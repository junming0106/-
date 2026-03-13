import SwiftUI

/// Engineering notebook grid
struct GridBackgroundView: View {
    var gridSpacing: CGFloat = 24
    var accentEvery: Int = 4

    @Environment(\.colorScheme) private var colorScheme

    private var lineColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.03)
            : Color.black.opacity(0.04)
    }

    private var accentLineColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.07)
    }

    private var dotColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.09)
    }

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / gridSpacing) + 1
            let rows = Int(size.height / gridSpacing) + 1

            for col in 0...cols {
                let x = CGFloat(col) * gridSpacing
                let isAccent = col % accentEvery == 0
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(isAccent ? accentLineColor : lineColor),
                    lineWidth: isAccent ? 0.8 : 0.4
                )
            }

            for row in 0...rows {
                let y = CGFloat(row) * gridSpacing
                let isAccent = row % accentEvery == 0
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    path,
                    with: .color(isAccent ? accentLineColor : lineColor),
                    lineWidth: isAccent ? 0.8 : 0.4
                )
            }

            for col in stride(from: 0, through: cols, by: accentEvery) {
                for row in stride(from: 0, through: rows, by: accentEvery) {
                    let x = CGFloat(col) * gridSpacing
                    let y = CGFloat(row) * gridSpacing
                    let dotRect = CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(dotColor)
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Lively ambient gradient — warm+cool color play for glass refraction
struct AmbientGradientView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Base warm-cool gradient
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.10, green: 0.06, blue: 0.18),
                        Color(red: 0.04, green: 0.10, blue: 0.16),
                    ]
                    : [
                        Color(red: 0.95, green: 0.93, blue: 0.98),
                        Color(red: 0.92, green: 0.96, blue: 0.99),
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Accent color blobs — lively feel
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.purple.opacity(colorScheme == .dark ? 0.08 : 0.06),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .offset(x: -200, y: -150)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.blue.opacity(colorScheme == .dark ? 0.06 : 0.04),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 350
                    )
                )
                .frame(width: 700, height: 700)
                .offset(x: 250, y: 200)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.teal.opacity(colorScheme == .dark ? 0.05 : 0.03),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: 100, y: -200)

            // Vignette
            RadialGradient(
                colors: [
                    Color.clear,
                    (colorScheme == .dark ? Color.black : Color(.windowBackgroundColor)).opacity(0.3)
                ],
                center: .center,
                startRadius: 250,
                endRadius: 900
            )
        }
        .ignoresSafeArea()
    }
}
