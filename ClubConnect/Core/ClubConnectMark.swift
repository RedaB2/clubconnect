import SwiftUI

struct ClubConnectMark: View {
    static let side: CGFloat = 512
    static let centerFraction: CGFloat = 45 / side

    // Each color has one vector path, shared by the small brand marks and the animated layers.
    static let parts: [(CGPath, UIColor)] = {
        let copper = CGMutablePath()
        let gold = CGMutablePath()
        let ray = CGMutablePath()
        ray.move(to: CGPoint(x: 0, y: -198))
        ray.addLine(to: CGPoint(x: 23, y: -94))
        ray.addLine(to: CGPoint(x: 0, y: -44))
        ray.addLine(to: CGPoint(x: -23, y: -94))
        ray.closeSubpath()
        for index in 0..<8 {
            let transform = CGAffineTransform(translationX: 256, y: 256).rotated(by: CGFloat(index) * .pi / 4)
            (index.isMultiple(of: 2) ? copper : gold).addPath(ray, transform: transform)
        }
        let disc = CGPath(ellipseIn: CGRect(x: 233.5, y: 233.5, width: 45, height: 45), transform: nil)
        return [(copper, UIColor(red: 170/255, green: 96/255, blue: 63/255, alpha: 1)),
                (gold, UIColor(red: 181/255, green: 155/255, blue: 97/255, alpha: 1)),
                (disc, UIColor(red: 151/255, green: 98/255, blue: 71/255, alpha: 1))]
    }()

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: side / Self.side, y: side / Self.side)
            for (path, color) in Self.parts {
                context.fill(Path(path), with: .color(Color(uiColor: color)))
            }
        }.aspectRatio(1, contentMode: .fit)
    }
}
