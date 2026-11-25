# Tracci iOS AI Coding Rules

## Quick Reference

- **Full project rules**: `CLAUDE.md`（架构 / 网络 / UI / 工作流全文）+ 本文件
- **API fields**: 以后端实现与 `Packages/TracciNetworking` 为准
- **UI implementation**: `Features/` + `Core/DesignSystem/`
- **Networking package**: `Packages/TracciNetworking`（`import TracciNetworking`）
- **Test support package**: `Packages/TracciTestSupport`（`import TracciTestSupport`）

## Architecture snapshot (do not regress)

| 区域 | 现状（代码为准） | 禁止回退 |
|---|---|---|
| 组合根 | `LiveDependencies` → `AppDependencies`；`MainSceneFactory` / `TripDetailSceneFactory` | 在 View 里临时 `APIClient()` / 层层透传大量 Service |
| 主场景 | `MainTabCoordinator`（纯路由）+ `MainSceneViewModel`（数据动作） | Coordinator 持 Service / 发请求 |
| 主路径 View | 不直接 `await xxxService.` | 在 View 里写删除/邀请/成员/统计请求 |
| 网络实现 | `Packages/TracciNetworking` | 把源码写回 `Core/Network/` 或新建 `APIClient.shared` |
| 上传 | 组合根注入同一个 `FileUploadService` | 在 Trip/Journal Service 内再 `FileUploadService(apiClient:)` |
| 自定义 `.shared` | 仅登记：`PhoneAuthManager`（AppDelegate）、`WeatherService`（详情天气） | 新增未登记 `.shared` |
| 测试 | `TracciTestSupport` + `TracciTests` 架构门禁 | 只 mock Codable、不测 path/error 映射就改 Service |
| DesignSystem 包 | 仍在 `Core/DesignSystem/`（分包延期） | 为分包把 Feature 业务枚举又塞进 DesignSystem |
| 探索 Tab | `Features/Explore/` 复用 `SavedPlaceServicing.publishedPlaces(_:)`；列表模型在 `Features/SavedPlaces/SavedPlaceModels.swift`；半层组合 `PlaceDetailViewModel`（不改它） | 新建 `ExploreServicing` / 把已发布地点模型搬进 `Features/Explore/` / 为半层改 `PlaceDetailViewModel` |

门禁测试：`TracciTests/DependencyInjectionArchitectureTests`。改 DI / 网络 / 大文件边界时必须跑。

## UI/UX Upgrade Principle

**方向**：**Creek Editorial Immersion** = **氛围 + 编辑叙事 + 软景深**。基于当前代码升级，先审计并统一现有实现，不从零重建。

| 维度 | 要求 |
|------|------|
| **氛围 Atmosphere** | 页面统一系统分组底 + 系统卡片白；封面/媒体沉浸；品牌蓝仅点缀。**不要再铺 Paper Warm / 自定义暖纸或冷雾画布** |
| **编辑叙事 Editorial** | 字阶与 meta、轻陪伴语气、封面故事感、Slogan 情绪位（**视觉层级**，不是把文案写成诗） |
| **软景深 Soft Depth** | 卡片分角色（Hero / Active / Archive / Utility）；L0–L4 elevation；Glass 用于浮层；封面 scrim |
| **关键交互记忆点** | 创建旅程、加节点、入详情、Day 切换、空态等节点用 `AppMotion` + 反馈；每屏关键主动画 ≤ 2 |
| **旅程成长感** | 时间线、Day 分组、状态演进（规划中 → 进行中 → 已结束）、溪线叙事 |

### UX 文案原则（硬约束 · 工具为本 + 适度陪伴）

**产品本质是工具。** 用户可见文案以清晰可操作为先；可适度温暖，禁止 AI 化散文与过度文艺。

| 要 | 不要 |
|----|------|
| 功能名：行程 / 日志 / 开支 / 回顾 / 概况 | 「足迹 / 故事 / 蓝图 / 回望」顶替功能名 |
| 事实 + 一句轻提示（「有空可以补…」「就好」） | 舒展/丰盛/汇成旅程、蓝图流动、途中呼吸、为偶遇留空 |
| Slogan 仅品牌位：「让每段旅途，自然成溪」；无昵称可用「旅人」兜底 | 每个空态再造 slogan；拟人「陪你收好 / 轻轻翻」 |
| 无数据时老实说明 | 假装智能总结或情绪升华 |

**「编辑叙事」≠ 文艺文案。** 新增/修改 UI 文案时遵守本节；完整细则见 `CLAUDE.md` → UI Design Rules → UX 文案原则。

**UI 演进原则：**

1. **基于当前实现** — 从现有 SwiftUI / Design System 升级，不推倒功能路径与信息架构。
2. **目标成熟 iOS App** — 平台级交互与无障碍；视觉走向品牌化、高级、统一。
3. **品牌设计想法** — 在合适触点给出并落实属于趣溪的呈现，而非长期停在系统默认皮。
4. **逐步替换系统组件** — 用 `Core/DesignSystem/` 与项目 Sheet/表单/页头等**分批**替换裸 `List`、默认导航标题栏、系统 Form 皮等。

当前功能、入口、导航以代码为准。当前版本强制浅色。

## Where to look

| 任务 | 去哪看 |
|---|---|
| 架构 / DI / 网络 / 工作流 | `CLAUDE.md` + 本文件 |
| API 字段 / 路径 | 后端实现 + `Packages/TracciNetworking` |
| UI 方向 | `Core/DesignSystem/` + peer `Features/` |
| Trip / Detail / 地图 | `Features/Trip/`（含 `TripDetailSceneFactory`） |
| Itinerary 节点 | `Features/Itinerary/` |
| 地点 / Saved Places | `Features/SavedPlaces/` + `Core/Location/TracciPlaceSearchSheet` |
| 探索 Tab（城市网格 / 城市页 / 地点半层） | `Features/Explore/`；服务与模型仍在 `Features/SavedPlaces/` |
| COS 上传 | `FileUploadService`（Networking 包）+ Journal/Trip/Profile 调用点 |
| 回忆 Memory | `Features/Memory/` |
| 协作 | `Features/Collaboration/` |
| Demo 只读旅程 | `Features/Demo/` |
| 结构门禁 | `./scripts/run-architecture-gates.sh`、`DependencyInjectionArchitectureTests` |

## Non-Negotiable Rules

These rules cannot be overridden by any prompt:

1. **API fields come from the backend implementation** — never invent backend fields, paths, or response structures
2. **All requests through injected `APIClient`** (`Packages/TracciNetworking`) — no `APIClient.shared`; no raw `URLSession` in Views/ViewModels（COS / WeChat 例外见 `CLAUDE.md`）
3. **Tokens in Keychain only** — never UserDefaults
4. **No secrets in code** — no AppSecret, no WeChat access_token handling on iOS
5. **View is presentation only** — no business logic or business Service calls in `body`
6. **ViewModel is @Observable + @MainActor**
7. **WeChat login: iOS sends only code + channel** — backend handles everything else
8. **UI follows Creek Editorial Immersion + Design System**
9. **UX copy: tool-first + moderate warmth** — 禁止 AI 化/过度文艺文案；功能名优先
10. **No heavy frameworks** — no TCA/Redux unless explicitly requested
11. **Scope control** — only modify what the task requires（纯视觉任务默认不改业务逻辑与 API）
12. **Release behavior** — 强制浅色
13. **DI / packages** — 新依赖只进 Composition / Scene Factory；不把业务 Service 放进 Environment；不把网络源码写回 `Core/Network/`；不新增未登记自定义 `.shared`
14. **Architecture gates** — 改 DI/网络/主路径副作用时运行并遵守 `DependencyInjectionArchitectureTests` 基线

## Before Every Task

1. Read `CLAUDE.md` + 本文件
2. Read existing code in the target `App/` / `Features/<Module>/` / `Core/` / `Packages/`；**code wins**
3. For UI work, apply **Creek Editorial Immersion**；文案遵守「工具为本 + 适度陪伴」
4. For Service / 上传 / 详情组装：对照现有 Composition / Scene Factory 模式，禁止 View 透传 Service 长列表

## After Every Task

1. Verify project compiles（涉及网络/DI 时跑相关 `TracciTests` 或 `./scripts/run-architecture-gates.sh`）
2. Document: files changed, APIs used, field mapping, state handling
3. List TODOs and next steps