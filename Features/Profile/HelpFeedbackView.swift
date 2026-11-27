import SwiftUI

struct HelpFeedbackView: View {
    @State private var viewModel: HelpFeedbackViewModel

    init(viewModel: HelpFeedbackViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.cardSmall) {
                if viewModel.submitSuccess {
                    feedbackSuccessView
                } else {
                    feedbackIntro
                    optionsState
                    feedbackForm
                }
            }
            .animation(AppMotion.milestoneSpring, value: viewModel.submitSuccess)
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.cardSmall)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracciDismissKeyboardOnBlankTap()
        .navigationTitle("意见反馈")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
        .task {
            await viewModel.loadOptions()
        }
    }

    // MARK: - Intro

    private var feedbackIntro: some View {
        HStack(alignment: .top, spacing: AppSpacing.cozy) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 36, height: 36)
                .background(AppColors.brandPrimaryBackground, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("你的声音对我们很重要")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                Text("无论是遇到的问题、功能建议，还是使用感受，我们都很期待听到。")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .lineSpacing(2)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .tracciElevation(.l0)
    }

    // MARK: - Feedback Form

    @ViewBuilder
    private var optionsState: some View {
        if viewModel.isLoadingOptions && viewModel.feedbackTypes.isEmpty {
            InlineLoadingStateView(message: "正在准备反馈选项", verticalPadding: 18)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .tracciElevation(.l0)
        } else if let warning = viewModel.optionsWarning {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.circle")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.warning)
                Text(warning)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                Spacer(minLength: 8)
                Button("重试") {
                    Task { await viewModel.loadOptions() }
                }
                .font(AppTypography.label)
                .foregroundStyle(AppColors.interactiveText)
            }
            .padding(AppSpacing.cozy)
            .background(AppColors.warning.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
    }

    private var feedbackForm: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            // 反馈类型
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                Text("反馈类型")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(viewModel.feedbackTypes) { option in
                            feedbackTypeChip(option)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xxs)
                }
            }
            .padding(AppSpacing.cardSmall)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .tracciElevation(.l0)

            // 详细描述
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text("详细描述")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Text("\(viewModel.contentCharacterCount)/1000")
                        .font(AppTypography.caption)
                        .foregroundStyle(
                            viewModel.contentCharacterCount > 1000
                                ? AppColors.danger
                                : AppColors.textPlaceholder
                        )
                }

                ZStack(alignment: .topLeading) {
                    if viewModel.content.isEmpty {
                        Text("可以说说你遇到的情况，或者希望我们改进的地方…")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPlaceholder)
                            .padding(.horizontal, AppSpacing.xxs)
                            .padding(.vertical, AppSpacing.tight)
                    }

                    TextEditor(text: $viewModel.content)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(minHeight: 120, maxHeight: 200)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                }
            }
            .padding(AppSpacing.cardSmall)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .tracciElevation(.l0)

            // 联系方式
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                Text("邮箱（可选）")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "envelope")
                            .font(AppTypography.label)
                        Text("邮箱")
                            .font(AppTypography.label)
                    }
                    .foregroundStyle(AppColors.textMuted)
                    .padding(.horizontal, AppSpacing.cozy)
                    .frame(height: 40)
                    .background(AppColors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                    TextField("方便我们回复你", text: $viewModel.contact)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, AppSpacing.cozy)
                        .frame(height: 40)
                        .background(AppColors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }
            }
            .padding(AppSpacing.cardSmall)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .tracciElevation(.l0)

            // Error message
            if let error = viewModel.errorMessage {
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppTypography.labelRegular)
                        .foregroundStyle(AppColors.danger)
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                    Spacer()
                }
                .padding(AppSpacing.cozy)
                .background(AppColors.dangerBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            }

            // Submit button
            PrimaryButton(
                title: "提交反馈",
                systemImage: "paperplane.fill",
                isLoading: viewModel.isSubmitting
            ) {
                Task { await viewModel.submit() }
            }
            .disabled(!viewModel.isSubmitEnabled)
        }
    }

    private func feedbackTypeChip(_ option: FeedbackOption) -> some View {
        let isSelected = viewModel.selectedType == option.value

        return Button {
            viewModel.selectedType = option.value
        } label: {
            HStack(spacing: 7) {
                Image(systemName: feedbackTypeIcon(option.value))
                    .font(AppTypography.bodyMedium)
                Text(option.label)
                    .font(isSelected ? AppTypography.cardBody : AppTypography.label)
            }
            .foregroundStyle(isSelected ? .white : AppColors.textMuted)
            .padding(.horizontal, AppSpacing.md)
            .frame(height: 38)
            .background(isSelected ? AppColors.brandPrimary : AppColors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .tracciElevation(isSelected ? .l1 : .l0)
        }
        .buttonStyle(.plain)
    }

    private func feedbackTypeIcon(_ value: String) -> String {
        switch value.uppercased() {
        case "BUG":
            return "exclamationmark.triangle"
        case "FEATURE":
            return "sparkles"
        case "UX":
            return "hand.tap"
        case "ACCOUNT":
            return "person.circle"
        default:
            return "ellipsis.message"
        }
    }

    private var feedbackSuccessView: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer().frame(height: 40)


            TracciSuccessCheck(size: 72)

            VStack(spacing: AppSpacing.tight) {
                Text("已收到你的反馈")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("每一条建议我们都会认真阅读，感谢你帮助趣溪变得更好。")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer().frame(height: 20)

            Button {
                withAnimation(AppMotion.quick) {
                    viewModel.resetForm()
                }
            } label: {
                Text("继续反馈")
                    .font(AppTypography.cardBody)
                    .foregroundStyle(AppColors.interactiveText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .transition(.scale.combined(with: .opacity))
    }
}
