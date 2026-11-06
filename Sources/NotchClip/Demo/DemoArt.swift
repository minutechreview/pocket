import AppKit
import SwiftUI

/// Sample "screenshots" for demo mode, drawn in code so the repo ships no images and nothing personal shows on camera.
@MainActor
enum DemoArt {
    static func png<V: View>(_ view: V, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// A café receipt with real text, so "search inside screenshots" finds it (try typing "latte").
    static var receipt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BLUE BEAN CAFÉ").font(.system(size: 30, weight: .heavy, design: .monospaced))
            Text("Avenue Mall · Kuwait City").font(.system(size: 16, design: .monospaced)).foregroundStyle(.gray)
            Divider()
            ForEach([("Iced Latte", "1.750"), ("Croissant", "1.250"), ("Sparkling Water", "0.500")], id: \.0) { row in
                HStack { Text(row.0); Spacer(); Text(row.1 + " KD") }.font(.system(size: 20, design: .monospaced))
            }
            Divider()
            HStack { Text("TOTAL").bold(); Spacer(); Text("3.500 KD").bold() }.font(.system(size: 24, design: .monospaced))
            Text("Order #4471 · Thank you!").font(.system(size: 16, design: .monospaced)).foregroundStyle(.gray)
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(Color(white: 0.97))
    }

    /// A presentation slide with a big number.
    static var slide: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.09), Color(red: 0.14, green: 0.09, blue: 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 14) {
                Text("Q4 REVIEW").font(.system(size: 18, weight: .semibold)).tracking(4).foregroundStyle(.white.opacity(0.55))
                Text("Revenue +38%").font(.system(size: 64, weight: .heavy)).foregroundStyle(.white)
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(Array([0.35, 0.5, 0.62, 0.9].enumerated()), id: \.offset) { index, value in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(index == 3 ? Color(red: 1, green: 0.38, blue: 0) : .white.opacity(0.25))
                            .frame(width: 70, height: 220 * value)
                    }
                }
                .frame(height: 220, alignment: .bottom)
            }
            .padding(50)
        }
    }

    /// A small app dashboard.
    static var dashboard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(["Home", "Projects", "Tasks", "Team", "Settings"], id: \.self) { Text($0).font(.system(size: 17, weight: .medium)) }
                Spacer()
            }
            .padding(28).frame(width: 190).background(Color(white: 0.94))
            VStack(alignment: .leading, spacing: 18) {
                Text("Launch week").font(.system(size: 30, weight: .bold))
                HStack(spacing: 14) {
                    stat("Signups", "1,284"); stat("Stars", "312"); stat("Bugs", "3")
                }
                ForEach(["Record demo video", "Write README", "Ship v0.1"], id: \.self) { task in
                    HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(task) }.font(.system(size: 18))
                }
                Spacer()
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.black)
        .background(.white)
    }

    private static func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 14)).foregroundStyle(.gray)
            Text(value).font(.system(size: 28, weight: .bold))
        }
        .padding(16).frame(width: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.95)))
    }

    /// A photo-like sunset over hills.
    static var sunset: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.98, green: 0.55, blue: 0.25), Color(red: 0.95, green: 0.3, blue: 0.4),
                                    Color(red: 0.35, green: 0.2, blue: 0.5)], startPoint: .bottom, endPoint: .top)
            Circle().fill(Color(red: 1, green: 0.85, blue: 0.5)).frame(width: 180).offset(y: -170)
            Hills(phase: 0.2).fill(Color(red: 0.25, green: 0.12, blue: 0.3)).frame(height: 260)
            Hills(phase: 1.4).fill(Color(red: 0.12, green: 0.06, blue: 0.16)).frame(height: 170)
        }
    }

    private struct Hills: Shape {
        let phase: Double
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.maxY))
            for x in stride(from: 0.0, through: rect.width, by: 8) {
                let y = rect.height * (0.35 + 0.25 * sin(x / rect.width * 5 + phase))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: rect.width, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
