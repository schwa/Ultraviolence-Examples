import AsyncAlgorithms
import AVFoundation
import CoreVideo
import Metal
import Ultraviolence
import UltraviolenceSupport

/// Pipeline that renders video frames to a Metal texture
@Observable
public class VideoTexturePipeline: @unchecked Sendable {
    private let device: MTLDevice
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var updateTask: Task<Void, Never>?

    public private(set) var currentTexture: MTLTexture?
    private var textureCache: CVMetalTextureCache?

    public init(device: MTLDevice) {
        self.device = device

        // Create texture cache for efficient video frame conversion
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    @MainActor
    public func loadVideo(url: URL, loopStart: TimeInterval = 2.95, loopEnd: TimeInterval = 11.95) throws {
        // Create player item and player
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Configure video output for Metal textures
        let outputSettings: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        guard let videoOutput else {
            fatalError("Failed to create video output")
        }
        playerItem?.add(videoOutput)

        // Set up looping
        player?.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        // Store loop points
        self.loopStart = CMTime(seconds: loopStart, preferredTimescale: 600)
        self.loopEnd = CMTime(seconds: loopEnd, preferredTimescale: 600)
    }

    private var loopStart = CMTime.zero
    private var loopEnd = CMTime.zero

    @objc private func playerItemDidReachEnd() {
        Task { @MainActor in
            await player?.seek(to: loopStart)
        }
    }

    public func play() {
        player?.play()

        // Set up async task for frame updates (60 fps)
        updateTask = Task {
            for await _ in AsyncTimerSequence(interval: .milliseconds(16), clock: .continuous) {
                await updateFrame()
            }
        }
    }

    public func pause() {
        player?.pause()
        updateTask?.cancel()
        updateTask = nil
    }

    @MainActor
    private func updateFrame() async {
        guard let videoOutput, let player else {
            return
        }

        let currentTime = player.currentTime()

        // Check for loop point
        if currentTime >= loopEnd {
            await player.seek(to: loopStart)
            return
        }

        // Get the current video frame
        guard videoOutput.hasNewPixelBuffer(forItemTime: currentTime), let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
            return
        }

        // Convert pixel buffer to Metal texture
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        guard let textureCache else {
            fatalError("Texture cache not initialized")
        }
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else {
            return
        }

        texture.label = "Video Frame Texture"
        currentTexture = texture
    }

    deinit {
        updateTask?.cancel()
        player?.pause()
    }
}
