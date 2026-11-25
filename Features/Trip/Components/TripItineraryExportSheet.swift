import SwiftUI
import UIKit

/// 旅程详情「导出行程单」全屏 Sheet：立即呈现加载态，生成完成后展示预览与保存操作。
struct TripItineraryExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tripId: String
    let tripTitle: String
    let dateRangeText: String
    let exportService: ExportService
    let onToast: (String, Bool) -> Void

    @State private var viewModel: ExportViewModel
    @State private var savePhase: SavePhase = .idle
    @State private var hasStartedGeneration = false

    private enum SavePhase: Equatable {
        case idle
        case saving
        case success
    }

    init(
        tripId: String,
        tripTitle: String,
        dateRangeText: String,
        exportService: ExportService,
        onToast: @escaping (String, Bool) -> Void
    ) {
        self.tripId = tripId
        self.tripTitle = tripTitle
        self.dateRangeText = dateRangeText
        self.exportService = exportService
        self.onToast = onToast
        _viewModel = State(
            initialValue: ExportViewModel(
                tripId: tripId,
                tripTitle: tripTitle,
                dateRangeText: dateRangeText,
                exportMode: .itinerary,
                exportService: exportService
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let image = viewModel.renderedImage {
                    previewContent(image: image)
                        .transition(AppMotion.transition(reduceMotion: reduceMotion))
                } else if viewModel.phase == .failed, let message = viewModel.errorMessage {
                    errorContent(message: message)
                        .transition(AppMotion.transition(reduceMotion: reduceMotion))
                } else {
                    loadingContent
                        .transition(.opacity)
                }
            }
            .animation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion), value: viewModel.phase)
            .animation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion), value: viewModel.renderedImage != nil)
            .animation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion), value: savePhase)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("导出行程单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .font(AppTypography.buttonTitle)
                }
            }
        }
        .task {
            guard !hasStartedGeneration else { return }
            hasStartedGeneration = true
            await viewModel.generateExport()
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 18) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(AppColors.brandPrimary)

            VStack(spacing: AppSpacing.xs) {
                Text(loadingTitle)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("正在整理 \(tripTitle) 的行程安排")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppSpacing.pageX)
    }

    private var loadingTitle: String {
        switch viewModel.phase {
        case .generating:
            "正在绘制行程单"
        case .loading:
            "正在加载行程数据"
        default:
            "正在准备行程单"
        }
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.system(36))
                .foregroundStyle(AppColors.danger)

            VStack(spacing: AppSpacing.tight) {
                Text("行程单生成失败")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(message)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }

            Button {
                AppHaptics.lightImpact()
                Task { await viewModel.generateExport() }
            } label: {
                Text("重试")
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            }
            .buttonStyle(PressableCardStyle(scale: 0.98, opacity: 0.95))

            Spacer()
        }
        .padding(.horizontal, AppSpacing.pageX)
    }

    private func previewContent(image: UIImage) -> some View {
        ScrollView {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(AppSpacing.pageX)
                .fadeSlideIn(index: 0, animation: AppMotion.normal)
        }
        .overlay {
            if savePhase == .success {
                saveSuccessOverlay
                    .transition(AppMotion.transition(reduceMotion: reduceMotion, yOffset: AppMotion.fadeSlideOffset))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                guard savePhase == .idle else { return }
                AppHaptics.lightImpact()
                savePhase = .saving
                Task {
                    let saved = await viewModel.saveToPhotoLibrary()
                    if saved {
                        await finishSaveSuccess()
                    } else {
                        savePhase = .idle
                        if let error = viewModel.errorMessage {
                            onToast(error, false)
                        }
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.tight) {
                    if savePhase == .saving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(savePhase == .saving ? "保存中..." : "保存到相册")
                }
                .font(AppTypography.buttonTitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(savePhase == .saving ? AppColors.textDisabled : AppColors.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            }
            .buttonStyle(PressableCardStyle(scale: 0.98, opacity: 0.95))
            .disabled(savePhase != .idle)
            .padding(.horizontal, TripDetailLayout.pageInset)
            .padding(.vertical, AppSpacing.cozy)
            .background(.ultraThinMaterial)
        }
    }

    private var saveSuccessOverlay: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.cozy) {
                TracciSuccessCheck(size: 52)

                Text("已保存到相册")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("正在返回旅程详情")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.pageTop)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
            .tracciElevation(.l1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("行程单已保存到相册，正在返回旅程详情")
    }

    @MainActor
    private func finishSaveSuccess() async {
        withAnimation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion)) {
            savePhase = .success
        }
        AppHaptics.success()

        let dwellSeconds = reduceMotion ? 0.35 : 0.72
        try? await Task.sleep(for: .seconds(dwellSeconds))

        dismiss()

        let dismissDelay = reduceMotion ? 0.15 : 0.30
        try? await Task.sleep(for: .seconds(dismissDelay))
        onToast("行程单已保存到相册", true)
    }
}