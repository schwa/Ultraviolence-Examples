import CoreGraphics

struct StrokeStyle: Equatable {
    var lineWidth: CGFloat
    var lineCap: CGLineCap
    var lineJoin: CGLineJoin
    var miterLimit: CGFloat

    init(lineWidth: CGFloat = 1.0, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, miterLimit: CGFloat = 2.0) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
    }
}
