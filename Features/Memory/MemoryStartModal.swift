import SwiftUI

struct MemoryStartModal: View {
    let trip: Trip
    let dateRangeText: String
    let storyViewModel: MemoryStoryViewModel?
    /// Demo can provide a story-specific cover without mutating the synthetic Trip.
    var coverURL: URL? = nil
    /// True when the user has opened this trip's story before (still shows launcher as transition).
    var isRevisit: Bool = false
    let onStart: () -> Void
    let onClose: () -> Void
    var launchNamespace: Namespace.ID? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSparse: Bool {
        if let stats = storyViewModel?.summary?.stats {
            return MemoryDisplayCopy.isSparse(stats: stats)
        }
        return MemoryDisplayCopy.isSparse(trip: trip)
    }

    private var canStart: Bool {
        storyViewModel?.isLoading != true
    }

    private var startButtonTitle: String {
        MemoryDisplayCopy.launcherStartTitle(isRevisit: isRevisit)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    TripCoverView(
                        url: coverURL ?? trip.coverStoryCardURL ?? trip.coverPreviewURL,
                        height: 214,
                        cornerRadius: 0
                    )
                        .frame(maxWidth: .infinity)
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.08), location: 0.0),
                            .init(color: .clear, location: 0.30),
                            .init(color: .black.opacity(0.70), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "sparkles")
                                .font(AppTypography.chipSemibold)
                            Text("TRIP STORY")
                                .font(AppTypography.microSemibold)
                                .tracking(1.2)
                        }
                        .foregroundStyle(.white.opacity(0.64))

                        Text(trip.title)
                            .font(AppTypography.pageTitle)
                            .foregroundStyle(.white)
                            .tracking(-0.3)
                            .lineLimit(2)
                            .tracciShadow(AppShadow.textStrong)

                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "calendar")
                                .font(AppTypography.captionSemibold)
                            Text(dateRangeText)
                                .lineLimit(1)
                        }
                        .font(AppTypography.label)
                        .foregroundStyle(.white.opacity(0.78))

                        if let destinationName = trip.destinationName, !destinationName.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(AppTypography.chipSemibold)
                                Text(destinationName)
                                    .lineLimit(1)
                            }
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(.white.opacity(0.68))
                        }
                    }
                    .padding(.horizontal, AppSpacing.pageX)
                    .padding(.bottom, AppSpacing.md + 4)
                }
                .frame(height: 214)

                VStack(spacing: 18) {
                    VStack(spacing: AppSpacing.tight) {
                        Text(MemoryDisplayCopy.launcherHeadline(isSparse: isSparse, isRevisit: isRevisit))
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(MemoryDisplayCopy.launcherSubtitle(isSparse: isSparse, isRevisit: isRevisit))
                            .font(AppTypography.labelRegular)
                            .foregroundStyle(AppColors.textMuted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)

                        if storyViewModel?.isLoading == true {
                            AppProgressIndicator(diameter: 16)
                                .padding(.top, AppSpacing.xs)
                        } else if let error = storyViewModel?.errorMessage {
                            Text("暂时没能打开：\(error)")
                                .font(AppTypography.captionMedium)
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .padding(.horizontal, AppSpacing.xxs)
                                .padding(.vertical, AppSpacing.sm)
                                .frame(maxWidth: .infinity)
                                .background(AppColors.subtleBackground.opacity(0.85))
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                                .padding(.top, AppSpacing.xxs)
                        }
                    }
                    .padding(.horizontal, 2)

                    Button {
                        guard canStart else { return }
                        AppHaptics.mediumImpact()
                        onStart()
                    } label: {
                        Label(startButtonTitle, systemImage: isRevisit ? "arrow.counterclockwise" : "play.fill")
                            .font(AppTypography.listTitle)
                            .foregroundStyle(.white)
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                LinearGradient(
                                    colors: [AppColors.brandPrimary, AppColors.brandPrimaryLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                            .tracciShadow(AppShadow.brand)
                    }
                    .pressableCardStyle(scale: 0.975, opacity: 0.92)
                    .disabled(!canStart)
                    .opacity(canStart ? 1 : 0.58)

                    Button {
                        AppHaptics.lightImpact()
                        onClose()
                    } label: {
                        Text("稍后再看")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textPlaceholder)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 18)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.96), AppColors.cardAltBackground.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.36)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 18)
                    .offset(y: -18)
                }
            }
            .background {
                #if compiler(>=26)
                if #available(iOS 26, *) {
                    RoundedRectangle(cornerRadius: AppRadius.launcher, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(in: RoundedRectangle(cornerRadius: AppRadius.launcher, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: AppRadius.launcher, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                #else
                RoundedRectangle(cornerRadius: AppRadius.launcher, style: .continuous)
                    .fill(.ultraThinMaterial)
                #endif
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.launcher, style: .continuous))
            .modifier(MemoryLaunchZoomDestinationModifier(
                id: trip.id,
                namespace: launchNamespace,
                reduceMotion: reduceMotion
            ))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.launcher, style: .continuous)
                    .stroke(.white.opacity(0.48), lineWidth: 0.6)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 26)
            .tracciShadow(AppShadow.floating)
        }
    }
}
