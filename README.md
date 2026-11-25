# Tracci iOS

SwiftUI iOS App for **趣溪 Tracci**（旅行规划 / 记录 / 协作 / 回看工具）。当前包含 auth、home、trip create/detail、itinerary、journal、expense、stats、export、profile、微信登录、Keychain、COS 上传、POI/定位与 Design System。

## Build

```sh
open Tracci.xcodeproj
xcodebuild -project Tracci.xcodeproj -scheme Tracci -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
```

### 阿里云号码认证（一键登录）

仓库不包含 `ALIYUN_PNVS_AUTH_INFO` 凭证。如需启用一键登录，在 Xcode Scheme → Run → Environment Variables 中设置 `ALIYUN_PNVS_AUTH_INFO`（值从阿里云号码认证控制台获取）；未设置时 App 正常构建运行，仅跳过一键登录 SDK 初始化。

## Docs

### Architecture pointers

- Composition: `App/Composition/`（`LiveDependencies` / `MainSceneFactory`）
- Networking package: `Packages/TracciNetworking`（`import TracciNetworking`；勿在 `Core/Network/` 加源码）
- Test support package: `Packages/TracciTestSupport`
- Architecture gates: `TracciTests/DependencyInjectionArchitectureTests`

UI/UX 方向为 **Creek Editorial Immersion**（氛围 + 编辑叙事 + 软景深）：功能路径不变，视觉与交互全面升级。实现以 `Features/` + `Core/DesignSystem/` 为准。

**用户可见文案**：工具为本 + 适度陪伴；禁止 AI 化散文与过度文艺。功能名优先（行程 / 日志 / 开支 / 回顾）。

## 第三方 SDK

`ThirdParty/ATAuthSDK/` 为阿里云号码认证 SDK（闭源二进制），版权归阿里云所有，按阿里云 SDK 许可协议使用；本仓库 MIT 许可证不覆盖该目录。

## 许可证

[MIT](LICENSE)（`ThirdParty/` 除外，见上）
