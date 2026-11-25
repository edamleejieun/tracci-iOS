import Photos
import SwiftUI
import UIKit

enum ExportShareHelper {
    @MainActor
    static func renderImage<V: View>(content: V, size: CGSize, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(
            content: content
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = scale
        return renderer.uiImage
    }

    static func loadImages(from urls: [URL]) async -> ExportImageLoadResult {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    (index, await loadImage(from: url))
                }
            }

            var indexedImages: [(Int, UIImage)] = []
            var failedCount = 0
            for await (index, image) in group {
                if let image {
                    indexedImages.append((index, image))
                } else {
                    failedCount += 1
                }
            }
            indexedImages.sort { $0.0 < $1.0 }
            return ExportImageLoadResult(
                images: indexedImages.map(\.1),
                failedCount: failedCount,
                totalCount: urls.count
            )
        }
    }

    static func loadImages(from candidates: [[URL]]) async -> ExportImageLoadResult {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, urls) in candidates.enumerated() {
                group.addTask {
                    (index, await loadFirstImage(from: urls))
                }
            }

            var indexedImages: [(Int, UIImage)] = []
            var failedCount = 0
            for await (index, image) in group {
                if let image {
                    indexedImages.append((index, image))
                } else {
                    failedCount += 1
                }
            }
            indexedImages.sort { $0.0 < $1.0 }
            return ExportImageLoadResult(
                images: indexedImages.map(\.1),
                failedCount: failedCount,
                totalCount: candidates.count
            )
        }
    }

    private static func loadFirstImage(from urls: [URL]) async -> UIImage? {
        for url in urls {
            if let image = await loadImage(from: url) {
                return image
            }
        }
        return nil
    }

    private static func loadImage(from url: URL) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    static func saveToPhotoLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportShareError.photoLibraryDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ExportShareError.saveFailed)
                }
            }
        }
    }

    static func copyToPasteboard(_ text: String) {
        UIPasteboard.general.string = text
    }
}

struct ExportImageLoadResult {
    let images: [UIImage]
    let failedCount: Int
    let totalCount: Int
}

enum ExportShareError: LocalizedError {
    case photoLibraryDenied
    case saveFailed
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .photoLibraryDenied:
            "无法保存到相册，请在系统设置中允许访问照片"
        case .saveFailed:
            "保存到相册失败，请稍后重试"
        case .renderFailed:
            "生成图片失败，请稍后重试"
        }
    }
}

struct ExportSharePresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.update(
            host: uiViewController,
            isPresented: $isPresented,
            items: items
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var activityController: UIActivityViewController?

        @MainActor
        func update(host: UIViewController, isPresented: Binding<Bool>, items: [Any]) {
            guard isPresented.wrappedValue else {
                activityController?.dismiss(animated: true)
                activityController = nil
                return
            }

            schedulePresentation(host: host, isPresented: isPresented, items: items, retryIfNeeded: true)
        }

        @MainActor
        private func schedulePresentation(
            host: UIViewController,
            isPresented: Binding<Bool>,
            items: [Any],
            retryIfNeeded: Bool
        ) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard isPresented.wrappedValue else { return }

                guard !items.isEmpty else {
                    isPresented.wrappedValue = false
                    return
                }

                guard activityController == nil, host.presentedViewController == nil else { return }

                guard host.view.window != nil else {
                    if retryIfNeeded {
                        schedulePresentation(
                            host: host,
                            isPresented: isPresented,
                            items: items,
                            retryIfNeeded: false
                        )
                    } else {
                        isPresented.wrappedValue = false
                    }
                    return
                }

                let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
                controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
                    DispatchQueue.main.async {
                        self?.activityController = nil
                        isPresented.wrappedValue = false
                    }
                }

                if let popover = controller.popoverPresentationController {
                    popover.sourceView = host.view
                    popover.sourceRect = CGRect(
                        x: host.view.bounds.midX,
                        y: host.view.bounds.maxY,
                        width: 0,
                        height: 0
                    )
                    popover.permittedArrowDirections = []
                }

                activityController = controller
                host.present(controller, animated: true)
            }
        }
    }
}

extension View {
    func exportSharePresenter(isPresented: Binding<Bool>, items: [Any]) -> some View {
        background {
            ExportSharePresenter(isPresented: isPresented, items: items)
                .frame(width: 0, height: 0)
        }
    }
}

struct ExportImagePreviewSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }
}
