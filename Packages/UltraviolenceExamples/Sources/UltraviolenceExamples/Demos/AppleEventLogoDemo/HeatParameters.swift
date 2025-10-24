import Metal
import simd

struct HeatParameters {
    // periphery:ignore - used in Metal shader
    var mousePosition: SIMD2<Float>      // 8 bytes (offset: 0)
    // periphery:ignore - used in Metal shader
    var mouseDirection: SIMD2<Float>     // 8 bytes (offset: 8)
    // periphery:ignore - used in Metal shader
    var heatIntensity: Float             // 4 bytes (offset: 16)
    // periphery:ignore - used in Metal shader
    var radius: Float                    // 4 bytes (offset: 20)
    // periphery:ignore - used in Metal shader
    var fadeDamping: Float               // 4 bytes (offset: 24)
    // periphery:ignore - used in Metal shader
    var sizeDamping: Float               // 4 bytes (offset: 28)
    // periphery:ignore - used in Metal shader
    var textureSize: SIMD2<UInt32>       // 8 bytes (offset: 32)
    // periphery:ignore - used in Metal shader
    var isInteracting: Float             // 4 bytes (offset: 40)
    // periphery:ignore - used in Metal shader
    var _padding_final: UInt32 = 0       // 4 bytes (offset: 44) - total: 48 bytes

    init(
        mousePosition: SIMD2<Float> = SIMD2<Float>(0.5, 0.5),
        mouseDirection: SIMD2<Float> = SIMD2<Float>(0, 0),
        heatIntensity: Float = 0,
        radius: Float = 50,
        fadeDamping: Float = 0.98,
        sizeDamping: Float = 0.8,
        textureSize: SIMD2<UInt32> = SIMD2<UInt32>(256, 256),
        isInteracting: Bool = false
    ) {
        self.mousePosition = mousePosition
        self.mouseDirection = mouseDirection
        self.heatIntensity = heatIntensity
        self.radius = radius
        self.fadeDamping = fadeDamping
        self.sizeDamping = sizeDamping
        self.textureSize = textureSize
        self.isInteracting = isInteracting ? 1.0 : 0.0
        self._padding_final = 0
    }
}
