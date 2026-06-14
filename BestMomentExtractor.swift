
import AVFoundation
import AVKit
import MediaIntelligence
import SwiftUI

struct ContentView: View {
    @State private var manager = VideoAnalysisManager()

    @State private var url: URL? = Bundle.main.url(
        forResource: "pikachu",
        withExtension: "mp4"
    )
    @State private var error: Error?

    @State private var extractingKeyframe: Bool = false
    @State private var keyframe: (Image, CMTime)?

    @State private var extractingHighlights: Bool = false
    @State private var highlights: [CMTimeRange] = []
    @State private var engagementLevels:
        [(timeRange: CMTimeRange, level: Float)] = []

    @State private var player = AVPlayer()

    var body: some View {
        HSplitView {
            VStack {
                VideoPlayer(player: self.player)

                if let error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 240)
            .frame(maxHeight: .infinity)
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Analyze Video")
                        .font(.title3)
                        .fontWeight(.bold)

                    if let url {
                        HStack(spacing: 24) {
                            Button(
                                action: {
                                    Task {
                                        self.extractingKeyframe = true
                                        self.keyframe = nil
                                        defer {
                                            self.extractingKeyframe = false
                                        }
                                        do {
                                            let (image, time) =
                                                try await manager
                                                .extractKeyframe(
                                                    url
                                                )
                                            self.keyframe = (
                                                Image(
                                                    decorative: image,
                                                    scale: 1.0
                                                ),
                                                time
                                            )
                                        } catch (let error) {
                                            print(error)
                                            self.error = error
                                        }
                                    }
                                },
                                label: {
                                    HStack {
                                        Text("Single Best Moment")
                                        if extractingKeyframe {
                                            ProgressView().controlSize(.small)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            )
                            .disabled(extractingKeyframe)

                            Button(
                                action: {
                                    Task {
                                        self.highlights = []
                                        self.engagementLevels = []
                                        self.extractingHighlights = true
                                        defer {
                                            self.extractingHighlights = false
                                        }

                                        do {
                                            let (highlights, engagements) =
                                                try await manager
                                                .extractHighlights(
                                                    url
                                                )
                                            self.highlights = highlights
                                            self.engagementLevels = engagements
                                        } catch (let error) {
                                            print(error)
                                            self.error = error
                                        }
                                    }
                                },
                                label: {
                                    HStack {
                                        Text("Highlights & Engagements")
                                        if extractingHighlights {
                                            ProgressView().controlSize(.small)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            )
                            .disabled(extractingKeyframe)

                        }
                    }

                    if let keyframe {
                        VStack(alignment: .leading) {
                            Text("Best Moment at \(keyframe.1.formatted)")
                                .fontWeight(.semibold)
                            keyframe.0
                                .resizable()
                                .scaledToFit()
                                .frame(height: 240)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !self.highlights.isEmpty {

                        VStack(alignment: .leading) {
                            Text("Highlights")
                                .fontWeight(.semibold)
                            Text(
                                "Engagement level: 0 (least engaging) to 9 (most engaging)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            ForEach(highlights.enumerated(), id: \.offset) {
                                _,
                                highlight in
                                let level = self.engagementLevels.first(where: {
                                    $0.timeRange == highlight
                                })
                                self.highlightRow(
                                    range: highlight,
                                    engagementLevel: level?.level
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    }

                    let engagements = self.engagementLevels.filter({
                        !self.highlights.contains($0.timeRange)
                    })
                    if !engagements.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Engagements")
                                .fontWeight(.semibold)
                            Text(
                                "Engagement level: 0 (least engaging) to 9 (most engaging)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            ForEach(engagements.enumerated(), id: \.offset) {
                                _,
                                engagement in
                                self.highlightRow(
                                    range: engagement.timeRange,
                                    engagementLevel: engagement.level
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding()

            }
            .frame(width: 400)
            .frame(maxHeight: .infinity, alignment: .topLeading)

        }
        .frame(height: 480)
        .fixedSize()
        .onAppear {
            if let url {
                self.player.replaceCurrentItem(with: .init(url: url))
            }
        }
    }

    @ViewBuilder
    private func highlightRow(range: CMTimeRange, engagementLevel: Float?)
        -> some View
    {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "\(range.start.formatted) - \(range.end.formatted)"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                if let engagementLevel {
                    Text(
                        "Level: \(Int((engagementLevel)))"
                    )
                }
            }

            Button(
                action: {
                    self.player.seek(to: range.start)
                },
                label: {
                    Text("Seek")
                }
            )
        }
    }
}

extension CMTime {
    var formatted: String {
        let totalSeconds = CMTimeGetSeconds(self)
        let totalMilliseconds = Int(totalSeconds * 1000)

        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60_000
        let seconds = (totalMilliseconds / 1000) % 60
        let milliseconds = totalMilliseconds % 1000

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d.%03d",
                hours,
                minutes,
                seconds,
                milliseconds
            )
        } else {
            return String(
                format: "%02d:%02d.%03d",
                minutes,
                seconds,
                milliseconds
            )
        }
    }
}

enum VideoAnalysisError: Error, LocalizedError {
    case invalidURL

    var errorDescription: String? {
        return switch self {
        case .invalidURL:
            "The provided URL is not a valid file URL."
        }
    }
}

@Observable
class VideoAnalysisManager {

    func extractKeyframe(_ videoURL: URL) async throws -> (CGImage, CMTime) {
        let asset = try self.createAsset(from: videoURL)
        let request = KeyFrameAnalysisRequest()
        let result = try await VideoAnalyzer.shared.analyze(asset, for: request)

        var timestamp: CMTime
        switch result {
        case .success(let keyframe):
            timestamp = keyframe.timestamp
        case .failure(let error):
            print("Fail to extract keyframe: \(error.localizedDescription)")
            throw error
        }

        return try await generateFrame(from: videoURL, at: timestamp)
    }

    func extractHighlights(_ videoURL: URL) async throws -> (
        highlights: [CMTimeRange],
        engagementLevels: [(timeRange: CMTimeRange, level: Float)]
    ) {
        let asset = try self.createAsset(from: videoURL)
        let request = HighlightAnalysisRequest()
        let result = try await VideoAnalyzer.shared.analyze(asset, for: request)

        switch result {
        case .success(let analysis):
            return (analysis.highlights, analysis.levels)
        case .failure(let error):
            print("Fail to extract highlights: \(error.localizedDescription)")
            throw error
        }
    }

    private func createAsset(from videoURL: URL) throws
        -> MediaIntelligenceVideoAsset
    {
        // MediaIntelligenceVideoAsset.Kind.url(_:) requires a file URL pointing to a video on disk
        guard videoURL.isFileURL else {
            throw VideoAnalysisError.invalidURL
        }

        let assetID = UUID().uuidString
        let asset = MediaIntelligenceVideoAsset(
            id: MediaIntelligenceVideoAsset.ID(assetID),
            kind: .url(videoURL)
        )
        return asset
    }

    private func generateFrame(from videoURL: URL, at time: CMTime)
        async throws
        -> (CGImage, CMTime)
    {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)

        // Retain correct video orientation
        generator.appliesPreferredTrackTransform = true

        // Set tolerances to zero for precise frame capturing.
        // Without this, AVFoundation may return an approximate keyframe for speed.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        do {
            let (cgImage, actualTime) = try await generator.image(at: time)
            return (cgImage, actualTime)
        } catch (let error) {
            print("Error generating frame: \(error.localizedDescription)")
            throw error
        }
    }

}
