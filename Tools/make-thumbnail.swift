// Draws the Devpost thumbnail (3:2). Run from the repo root: swift Tools/make-thumbnail.swift
import AppKit
import SwiftUI

let coral = Color(red: 1.0, green: 0.36, blue: 0.30)

struct Logo: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
            Circle()
                .trim(from: 0.135, to: 0.865)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round))
                .frame(width: size * 0.48, height: size * 0.48)
                .rotationEffect(.degrees(0))
                .offset(x: -size * 0.02)
            Circle().fill(coral).frame(width: size * 0.14, height: size * 0.14).offset(x: size * 0.13)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: size * 0.08, y: size * 0.04)
    }
}

struct NotchShape: Shape {
    var top: CGFloat = 10
    var bottom: CGFloat = 26
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct Pill: View {
    var text: String
    var prominent = false
    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(prominent ? Color.white : Color.white.opacity(0.14), in: .capsule)
    }
}

struct Field: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Color.white.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}

/// The island as it looks in the app, a little larger.
struct Island: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Logo(size: 26).shadow(radius: 0)
                Spacer()
                Image(systemName: "mic.fill").font(.system(size: 17)).foregroundStyle(.white.opacity(0.55))
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(.white.opacity(0.55))
            }
            .frame(height: 30)
            Text("Meet Ravi")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                Field(text: "Fri 16 Oct")
                Field(text: "17:30")
                Text("–").foregroundStyle(.white.opacity(0.5)).font(.system(size: 19))
                Field(text: "18:30")
            }
            HStack(spacing: 8) {
                Image(systemName: "mappin").foregroundStyle(.white.opacity(0.5))
                Text("Starbucks in Bandra").foregroundStyle(.white)
                Spacer()
            }
            .font(.system(size: 19, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 10))
            HStack(spacing: 12) {
                Circle().fill(Color(red: 0.35, green: 0.65, blue: 0.95)).frame(width: 10, height: 10)
                Text("Home").foregroundStyle(.white.opacity(0.6))
                Image(systemName: "bell").foregroundStyle(.white.opacity(0.6))
                Text("15m").foregroundStyle(.white.opacity(0.6))
                Spacer()
                Pill(text: "Discard")
                Pill(text: "Add", prominent: true)
            }
            .font(.system(size: 17, weight: .medium))
        }
        .padding(.horizontal, 34)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(width: 520)
        .background(NotchShape().fill(.black))
    }
}

/// A slice of a Mac screen: wallpaper, menu bar, notch, and the island growing out of it.
struct Screen: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.48), Color(red: 0.56, green: 0.36, blue: 0.75),
                                    Color(red: 0.16, green: 0.2, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // A copied message behind the island, the thing that was caught.
            VStack(alignment: .leading, spacing: 8) {
                Text("Ravi").font(.system(size: 17, weight: .semibold)).foregroundStyle(.black.opacity(0.55))
                Text("so tomorrow around 5.30? probably the Starbucks in Bandra ☕️")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(.black.opacity(0.85))
                    .padding(14)
                    .background(Color(white: 0.93), in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).fill(Color.blue.opacity(0.18)))
            }
            .padding(22)
            .frame(width: 420, alignment: .leading)
            .background(.white.opacity(0.78), in: .rect(cornerRadius: 20))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .offset(x: 120, y: 420)
            Rectangle().fill(.black.opacity(0.35)).frame(height: 40)
            Island()
        }
        .frame(width: 780, height: 760)
        .clipShape(.rect(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.12), lineWidth: 2))
        .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
    }
}

struct Chip: View {
    var symbol: String
    var text: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 11)
            .background(Color.white.opacity(0.1), in: .capsule)
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
    }
}

struct Thumbnail: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.05)
            RadialGradient(colors: [coral.opacity(0.28), .clear], center: UnitPoint(x: 0.78, y: 0.12), startRadius: 0, endRadius: 760)
            RadialGradient(colors: [Color.purple.opacity(0.22), .clear], center: UnitPoint(x: 0.1, y: 0.95), startRadius: 0, endRadius: 700)
            HStack(spacing: 70) {
                VStack(alignment: .leading, spacing: 34) {
                    Logo(size: 150)
                    Text("Catchy")
                        .font(.system(size: 112, weight: .heavy))
                        .tracking(-2)
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            Chip(symbol: "doc.on.clipboard", text: "Copied text")
                            Chip(symbol: "viewfinder", text: "Screenshot")
                        }
                        HStack(spacing: 14) {
                            Chip(symbol: "mic.fill", text: "Voice")
                            Chip(symbol: "iphone", text: "iPhone photo")
                        }
                    }
                    Label("On-device · macOS", systemImage: "lock.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(width: 520, alignment: .leading)
                Screen()
            }
        }
        .frame(width: 1500, height: 1000)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Thumbnail().environment(\.colorScheme, .dark))
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        fatalError("render failed")
    }
    let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "devpost/thumbnail.png")
    try! png.write(to: url)
    print("Wrote \(url.path) (\(png.count / 1024) KB)")
}
