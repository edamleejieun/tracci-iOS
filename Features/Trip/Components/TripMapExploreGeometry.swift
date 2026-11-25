import SwiftUI

// MARK: - Coordinate space

enum TripMapExploreCoordinateSpace {
    /// 详情页根 ZStack 坐标系，用于 Hero → 全屏地图几何展开。
    static let root = "TripDetailRoot"
}

// MARK: - Preference keys

struct TripHeroFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct TripMapExploreContainerFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

// MARK: - Expanding clip (Hero 窗 → 全屏)

/// 从封面 Hero 矩形插值到全屏 bounds；只动裁剪，不缩放 MKMapView。
struct TripMapExpandingClip: Shape {
    /// 0 = 收在 source，1 = 铺满 rect。
    var progress: CGFloat
    /// 与 `path(in:)` 同坐标系下的 Hero 源矩形。
    var source: CGRect

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return Path(rect)
        }

        let t = Self.smoothstep(min(1, max(0, progress)))
        let src: CGRect
        if source.width > 8, source.height > 8,
           source.origin.x.isFinite, source.origin.y.isFinite {
            src = source
        } else {
            // 未测到 Hero 时退化为中心小窗，仍保留展开感。
            let w = rect.width * 0.92
            let h = min(280, rect.height * 0.32)
            src = CGRect(
                x: rect.midX - w / 2,
                y: rect.minY + 12,
                width: w,
                height: h
            )
        }

        let x = src.minX + (rect.minX - src.minX) * t
        let y = src.minY + (rect.minY - src.minY) * t
        let w = max(1, src.width + (rect.width - src.width) * t)
        let h = max(1, src.height + (rect.height - src.height) * t)
        let corner = max(0, min(28 * (1 - t), min(w, h) / 2))
        let rounded = CGRect(x: x, y: y, width: w, height: h)
        guard rounded.origin.x.isFinite, rounded.origin.y.isFinite else {
            return Path(rect)
        }
        return Path(roundedRect: rounded, cornerRadius: corner, style: .continuous)
    }

    private static func smoothstep(_ t: CGFloat) -> CGFloat {
        t * t * (3 - 2 * t)
    }
}

// MARK: - First-run hint storage

enum TripMapExploreHintStore {
    private static let dismissHintKey = "tracci.mapExplore.dismissHintSeen.v1"

    static var hasSeenDismissHint: Bool {
        get { UserDefaults.standard.bool(forKey: dismissHintKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissHintKey) }
    }
}
