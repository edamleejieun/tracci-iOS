# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

- **Product**: 趣溪 Tracci — travel planning, journaling, collaboration, and memory
- **Platform**: iOS 17+, SwiftUI
- **Tech Stack**: SwiftUI, async/await, URLSession, Codable, Observation (`@Observable`), Keychain
- **Backend**: Spring Boot, unified API prefix `/api/v1`
- **UI Language**: Chinese (Simplified)

## Build & Run

```sh
# Open project
open Tracci.xcodeproj

# Simulator build (CLI)
xcodebuild -project Tracci.xcodeproj -scheme Tracci -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run in Xcode: select Tracci scheme + Simulator or connected device
```

- **Scheme**: `Tracci`, **Target**: `Tracci`, **Configurations**: `Debug` / `Release`
- Unit tests live in `TracciTests/` (partial coverage) plus local packages under `Packages/`. Minimum bar for most tasks is a successful compile; run relevant tests when touching covered areas (DI/network changes → run `DependencyInjectionArchitectureTests` + related HTTP stub suites).
- Architecture gate script: `./scripts/run-architecture-gates.sh`
- Simulator hits `http://localhost:8080/api/v1`. Real devices need `TRACCI_API_BASE_URL` set to the Mac's LAN address via Xcode Scheme Environment Variables.
- WeChat login requires a real device. See WeChat Login Rules if touching `Core/Auth/`.

## Source of Truth (priority order)

1. **Backend API** fields/paths/responses: the backend implementation (`tracci-backend`) and its Swagger contract
2. **Current iOS behavior**: code in `App/`, `Features/`, `Core/`, and `Packages/` — code is source of truth for existing functions, entry points, navigation, and feature flags
3. **UI implementation tokens**: current `Core/DesignSystem/` and `Features/` (upgrade from what exists; do not rebuild already-shipped visual patterns)
4. **This file and `AGENTS.md`** as AI collaboration rules

Rules:
- Do not invent API fields, enum values, or product behavior from memory
- Do not create backend endpoints that don't exist
- When docs conflict with code, the code is authoritative
- Pure visual/interaction tasks must not change business flows or invent APIs

## Architecture

MVVM with `Observation` framework (`@Observable`). No heavy frameworks (TCA, Redux, etc.).

```
App/
  TracciApp, AppRootView, MainTabView
  Composition/        # LiveDependencies, AppDependencies, MainSceneFactory
  CreateFlow/         # Create / Join presentation handoff
  Navigation/         # MainTabCoordinator, router, chrome
  Scene/              # MainSceneViewModel (cross-tab data actions)

Packages/
  TracciNetworking/   # APIClient, Endpoint, Error, Response, NetworkConfig, FileUpload*
  TracciTestSupport/  # HTTPStub, ResultQueue, CallRecorder (TracciTests only)

Core/
  Network/            # README only — do NOT add sources here; use Packages/TracciNetworking
  Auth/               # AuthSession, AuthService, TokenRefresh, WeChat, PhoneAuth adapter
  Storage/            # KeychainTokenStore
  Location/           # TracciPlaceSearchSheet (MapKit), LocationService, TripRouteProviding
  DesignSystem/       # Tokens, chrome, forms, sheets (no Feature-specific layout)
  Utils/              # Cover loader, TracciDateContext / TripDateFormatting, AppUpdateChecker

Features/
  Auth, Home, Trip, Itinerary, Journal, Expense, Stats, Export
  Memory, Collaboration, Profile, SavedPlaces, Explore, Demo

TracciTests/          # Unit + architecture gates; Feature capability stubs in TestSupport/
ThirdParty/           # WechatOpenSDK-NoPay / ATAuthSDK xcframeworks
```

### Layer Responsibilities

- **View**: Pure presentation. Binds to ViewModel state. **No network calls, no business Service calls in `body`.**
- **ViewModel / Actions**: `@Observable final class`, `@MainActor`. Owns UI state (loading/error/empty/content), async workflows, cancel/retry. Calls Service or capability protocols.
- **Coordinator**: `@Observable final class`, `@MainActor`. Tab / NavigationPath / Sheet presentation only — **no Service, no network**.
- **Scene Factory**: Assembles ViewModels, Actions, and child scenes at the boundary (`MainSceneFactory`, `TripDetailSceneFactory`). Leaf Views must not forward long concrete Service parameter lists.
- **Service**: Plain struct wrapping injected `APIClient` (`import TracciNetworking`). One service per feature domain.
- **Model**: `Codable` structs/enums for API request/response. Maps 1:1 with backend fields unless documented otherwise.
- **DI**: Manual constructor injection only.
  - Live graph: `LiveDependencies.make()` → `AppDependencies`
  - Main shell: `MainSceneDependencies` + `MainSceneFactory` → coordinator + root ViewModels
  - Trip Detail: `TripDetailSceneFactory` so root View does not store/forward concrete Services
  - **Do not** put business Services in SwiftUI `Environment`
  - **Do not** reintroduce `APIClient.shared` or unregistered custom `.shared` (see architecture gates)
- **AuthSession**: `@Observable`, via `@Environment`. Token lifecycle, restore, 401 handling.
- **Registered custom `.shared` (freeze list)**: only `PhoneAuthManager` (AppDelegate SDK lifecycle) and `WeatherService` (TripDetailViewModel WeatherKit). New ones require explicit review + gate update. Prefer injection (`PhoneAuthProviding`, `TripRouteProviding`, `AppUpdateChecker` instance from composition root).

### Architecture gates (tests)

`TracciTests/DependencyInjectionArchitectureTests` enforces:

- Root views do not expand concrete Service parameter lists
- Main path `*View.swift` has **zero** direct business Service calls
- Custom `.shared` matches registered baseline
- Stage E file boundaries / Trip Detail Scene Factory
- Stage F TestSupport + Stage G package files exist

When changing DI or adding Services, run these tests and update baselines only with intent.

## Network & Auth Rules

- Networking types live in **`Packages/TracciNetworking`** — `import TracciNetworking` in App/Features/Tests consumers
- All backend requests go through **injected** `APIClient` — **no `APIClient.shared`**
- Construct the live client and Services in **`LiveDependencies` / Composition**, not ad hoc inside Views
- Services use `init(apiClient:)` (and explicit `fileUploadService:` where needed — never construct `FileUploadService` inside Trip/Journal Service)
- Use `APIEndpoint` for path/method/query/body/requiresAuth
- **Path is relative to base URL**: e.g. `"trips"`, `"files/upload-credentials"` — **not** `"/api/v1/trips"`. Base already includes `/api/v1` (`NetworkConfig`)
- `APIClient.request` decodes `APIResponse<T>`, checks `code == 0`, returns **unwrapped `T`** (or throws `APIError.business`)
- Pagination: `PageResponse<T>` (accepts `list` / `items` / `records` shapes)
- Never invent fields; API source of truth is the backend implementation
- Auth: `Authorization: Bearer <accessToken>` via `AuthSession` / `AccessTokenProviding` on client
- Token refresh only via `TokenRefreshCoordinator`
- Tokens only in Keychain (`KeychainTokenStore`), never `UserDefaults`
- Do not rewrite Auth or `Packages/TracciNetworking` unless explicitly asked
- Exceptions for raw `URLSession`: COS upload in `FileUploadService` (package), WeChat SDK, streaming helpers already on `APIClient`
- Unit tests: use `import TracciTestSupport` (`HTTPStub`, `ResultQueue`, `CallRecorder`); Feature stubs stay in `TracciTests/TestSupport/`

## WeChat Login Rules

- iOS uses `WeChatOpenSDK` for WeChat authorization
- iOS only obtains the WeChat authorization `code`
- iOS calls backend `/auth/wechat-app/login` with `code` + `channel=IOS`
- iOS does NOT handle `openid`, `unionid`, or WeChat `access_token`
- iOS does NOT contain WeChat `AppSecret`
- Mini-program `wx.login` logic must NOT be copied to iOS
- Account unification between mini-program and iOS is handled by the backend via `unionid`
- WeChat login full flow requires a real device — Simulator cannot fully test it

## UI Design Rules

### Direction

**Creek Editorial Immersion** = **Atmosphere + Editorial Narrative + Soft Depth**. UI/UX work upgrades from current SwiftUI code and Design System; audit and unify existing implementation first, do not rebuild from zero.

### Upgrade Goal

Every UI/UX change should advance:

1. **氛围 Atmosphere** — page canvas is system grouped + system card white; immersive cover/media only. Do **not** reintroduce Paper Warm or custom mist hexes as page fills
2. **编辑叙事 Editorial** — type hierarchy, meta labels, restrained companion tone, cover storytelling, slogan on emotional surfaces（**视觉与信息层级**，不是把文案写成诗）
3. **软景深 Soft Depth** — card roles (Hero / Active / Archive / Utility), elevation L0–L4, glass on floating chrome, media scrims
4. **关键交互记忆点** — purposeful `AppMotion` + haptics at create / add node / enter detail / day switch / empty states (≤2 primary animations per screen)
5. **旅程成长感** — timelines, day streams, status progression (规划中 → 进行中 → 已结束)

### UX 文案原则（硬约束 · 工具为本 + 适度陪伴）

**产品本质是旅行工具**（规划 / 记录 / 协作 / 回看）。用户可见中文文案必须：

1. **工具优先**：先说清状态与动作（有没有内容、可以补什么、去哪里看）
2. **适度温暖**：允许轻度口语与轻陪伴（如「有空可以…」「就好」「不必勉强」），避免冷冰冰的机器腔
3. **克制**：绝不写成 AI 散文、文艺散文或拟人陪伴机器人

| 要 | 不要 |
|----|------|
| 功能名：行程 / 日志 / 开支（花费）/ 回顾 / 概况 | 用「足迹 / 故事 / 蓝图 / 回望 / 启程」替换功能名 |
| 事实 + 一句轻提示 | 「舒展 / 丰盛 / 从容 / 汇成一段旅程 / 空白也成为故事」等升华句 |
| 品牌 Slogan 仅品牌位：「让每段旅途，自然成溪」 | 每个空态/洞察再造第二套 slogan |
| 无昵称时可用「旅人」作温暖兜底称呼；有昵称用昵称 | 到处堆叠文艺称呼或拟人（如「陪你收好」） |
| 洞察、空态、回忆：事实优先 | 过度拟人：「陪你收好 / 轻轻翻 / 我会帮你放 / 安静地出现」 |
| 轻提示：「可以补一条日志」 | 隐喻堆叠：「蓝图流动 / 途中呼吸 / 为偶遇留空 / 留下痕迹 / 故事空着一页」 |
| 无数据时老实说明 | 无数据仍装作「智能总结」或情绪升华 |
| 中文品牌名「趣溪」 | 旧名「旅迹」出现在用户可见文案 |

**禁止**（与产品设计一致）：完成度、连续记录、还差多少、解锁门槛、徽章任务式文案。

**「编辑叙事」≠ 文艺文案。** Creek Editorial Immersion 的 Editorial 指字阶、meta、封面与信息叙事的**视觉**，不授权把 UI 文案写成诗或 AI 陪伴散文。新增/修改任何 `Text` / empty / companion / insight / toast / a11y 文案时遵守本节。

### What we are breaking (intentionally)

Do **not** enforce these MVP-era rules on new UI work:

- Global pure white only
- Uniform low information density on every screen
- Same visual weight for all cards
- “Minimal = avoid materials / atmosphere / narrative”

Do **keep**:

- Clear, efficient **forms and settings**, with room for branded artistic treatment
- Unchanged **feature paths and APIs**
- Brand hard rules: ink wordmark, blue only as accent, a11y, iOS-quality interaction
- Token-driven styling via Design System

### Source of Truth (UI)

1. `Core/DesignSystem/` and peer screens in `Features/`
2. Brand rules in this file (no blue Chinese titles; logo/wordmark sizes)
3. iOS HIG / native SwiftUI patterns

### iOS-Quality Interaction and Branded Presentation

- “Native” means iOS-quality behavior, system integration, and accessibility — not an obligation to keep unstyled system visuals
- **Baseline for UI work**: evolve from **current shipped code**; aim for a **mature branded iOS app** under Creek Editorial Immersion
- **Progressive replacement**: when polishing a surface, prefer Design System / Tracci chrome over raw system skin if a shared pattern exists; extract new shared components when a brand pattern repeats
- Navigation: `NavigationStack` / tab container are structural baselines; branded headers, tab chrome, and transitions are encouraged when hierarchy, back/edge-swipe, safe areas, and accessibility remain correct
- Forms: branded input cards, labels, groups, picker shells, focus, validation, submit — encourage replacing stock `Form` chrome over time; keep keyboard/IME/AutoFill/focus/scroll
- Sheets and alerts: prefer `TracciSheetKind` / `tracciSheetPresentation` and branded top bars; preserve safe areas and dismiss semantics
- Lists: prefer `ScrollView` + `LazyVStack` or established list components; do not use unstyled system `List`
- States: loading, empty, error, and content — complete and consistent
- Motion: `AppMotion`; meaningful, interruptible; respect `accessibilityReduceMotion`
- Accessibility: Dynamic Type, contrast ≥ 4.5:1 for body text, 44pt targets, VoiceOver labels
- Appearance: current release is light-only and is locked at `Info.plist`, `TracciApp`, and UIKit window levels; do not add dark-mode scope unless explicitly re-approved
- On UI tasks, agents may **propose** brand presentation ideas (atmosphere, type, elevation, ritual moments) within brand rules — not invent new product features

### Tracci Style (post-upgrade identity)

- **Backgrounds**: system grouped page (`backgroundGrouped`) + system card white. Auth / empty / export / memory use the same canvas. Immersive media only on trip header and memory covers. Do not use Paper Warm.
- **Brand blue**: `#3B82F6` — logo, glow, creek lines, selection, small accents only
- **Ink / warm text**: brand ink / `#2F2A25` hierarchy — never blue wordmark or blue display titles
- **Cards**: large continuous radii with **role-based elevation**, not one flat card style
- **Density**: breathable on hero/memory; compact on forms — **not** one global density
- Quiet but **premium**: materials and atmosphere without noise

### Implementation preference

- Prefer extending `AppColors`, `AppShadow`, `AppMotion`, and shared surfaces (`AppAtmosphereBackground`, glass, elevation cards) over one-off page styling

### Do Not

- Sacrifice iOS interaction quality or system capabilities for decoration; custom branded visuals themselves are allowed
- Add one-off colors/radii/shadows when a Design System token should exist (add the token instead)
- Polish only pixels without atmosphere, narrative, depth, memorable interaction, or journey growth
- **Use “keep it minimal” as a reason to refuse the upgrade direction**
- **Write AI-ified or overly literary Chinese copy** (see UX 文案原则 above) — tool-first, moderate warmth only
- Change business logic or APIs during a pure visual task

## Development Workflow

### Before starting a task

1. Read this `CLAUDE.md` and `AGENTS.md`
2. Read existing code in the target `Features/<Module>/`, `App/Composition/` if wiring deps, and relevant `Core/DesignSystem/` / `Packages/` components
3. For UI screens: peer screens + Design System
4. Extend existing structure — do not refactor broadly unless the task requires Design System foundation or package boundary work
5. For new Service/DI: wire only at Composition / Scene Factory; do not pass Services through leaf Views; do not add unregistered `.shared`

### After completing a task

1. List modified files
2. List APIs used (endpoint, method, fields)
3. Document field mapping (backend response -> iOS model)
4. Describe state management approach
5. Describe how to verify (compile, simulator, manual test)
6. List TODOs and open questions
7. Suggest next steps

### Preview Rules

- Add `#Preview` for each new user-facing page using mock data
- Previews must NOT call real backend APIs, Keychain, WeChat SDK, or production login flows
- Cover normal, loading, empty, and error states for data-driven pages
- Keep preview data aligned with the backend API contract
- Keep preview helpers private or clearly isolated from production code

## Do NOT

- Refactor unrelated modules during a focused task
- Delete existing business code or docs
- Break Auth / Token / Home / Trip existing flows
- Write network requests inside SwiftUI Views
- Bypass Keychain for token storage
- Introduce unnecessary third-party libraries
- Fabricate backend response fields
- Hardcode secrets (AppSecret, tokens, credentials) in source code
- Mix mock data into production logic
- Write Preview code that breaks real flows
- Use `UserDefaults` for tokens or sensitive data