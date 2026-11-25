import SwiftUI
import UIKit

/// 旅程成员头像：后端头像可用时优先展示，缺失或加载失败时回退到稳定身份色首字。
struct TripMemberAvatarView: View {
    let member: TripMemberResp
    var size: CGFloat = 28
    var showsOwnerRing = false

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.cardBackground)

            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size - 4, height: size - 4)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(member.memberColor.opacity(0.16))
                    .frame(width: size - 4, height: size - 4)
                    .overlay {
                        Text(member.displayInitial)
                            .font(initialFont)
                            .foregroundStyle(member.memberColor)
                    }
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.92), lineWidth: 1.5)
        }
        .overlay {
            Circle()
                .inset(by: 2.25)
                .stroke(
                    showsOwnerRing && member.isOwner
                        ? AppColors.ownerAmber.opacity(0.72)
                        : member.memberColor.opacity(0.45),
                    lineWidth: 0.75
                )
        }
        .tracciShadow(AppShadow.soft)
        .task(id: member.avatarUrl) {
            loadedImage = nil
            guard let url = member.avatarURL else { return }
            let image = await TripCoverImageLoader.load(url: url, timeout: 8)
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
        .accessibilityHidden(true)
    }

    private var initialFont: Font {
        size >= 44 ? AppTypography.sectionTitle : AppTypography.chipSemibold
    }
}

/// 可复用的旅程成员重叠头像组。
struct TripMemberAvatarStack: View {
    let members: [TripMemberResp]
    var maximumVisible = 3
    var size: CGFloat = 28
    var overlap: CGFloat = 8

    private var visibleMembers: ArraySlice<TripMemberResp> {
        members.prefix(maximumVisible)
    }

    private var overflowCount: Int {
        max(0, members.count - maximumVisible)
    }

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(visibleMembers.enumerated()), id: \.element.id) { index, member in
                TripMemberAvatarView(member: member, size: size)
                    .zIndex(Double(maximumVisible - index))
            }

            if overflowCount > 0 {
                overflowAvatar
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(members.count) 位旅程成员")
    }

    private var overflowAvatar: some View {
        Circle()
            .fill(AppColors.cardBackground)
            .frame(width: size, height: size)
            .overlay {
                Text("+\(overflowCount)")
                    .font(AppTypography.microSemibold)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.92), lineWidth: 1.5)
            }
            .overlay {
                Circle()
                    .inset(by: 2.25)
                    .stroke(AppColors.borderDefault.opacity(0.7), lineWidth: 0.75)
            }
            .tracciShadow(AppShadow.soft)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("旅程成员头像 · 首字回退") {
    ZStack {
        LinearGradient(
            colors: [AppColors.stagePlanning, AppColors.stageCompleted],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        TripMemberAvatarStack(
            members: [
                TripMemberResp(
                    id: "member-owner",
                    tripId: "trip-preview",
                    userId: "user-owner",
                    nickname: "Liz",
                    role: .owner,
                    status: "active",
                    joinedAt: nil
                ),
                TripMemberResp(
                    id: "member-editor",
                    tripId: "trip-preview",
                    userId: "user-editor",
                    nickname: "陈",
                    role: .editor,
                    status: "active",
                    joinedAt: nil
                ),
                TripMemberResp(
                    id: "member-viewer",
                    tripId: "trip-preview",
                    userId: "user-viewer",
                    nickname: "Mika",
                    role: .viewer,
                    status: "active",
                    joinedAt: nil
                ),
                TripMemberResp(
                    id: "member-overflow",
                    tripId: "trip-preview",
                    userId: "user-overflow",
                    nickname: "王",
                    role: .viewer,
                    status: "active",
                    joinedAt: nil
                )
            ]
        )
        .padding(.horizontal, 7)
        .frame(minHeight: 36)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
#endif
