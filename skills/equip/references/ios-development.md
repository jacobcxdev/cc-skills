# iOS Development

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When working on iOS/Swift projects. Detection signals:
- `.xcodeproj` or `.xcworkspace` present in the project tree
- Swift source files (`.swift`) with `import SwiftUI`, `import UIKit`, or `import Foundation`
- `Package.swift` (Swift Package Manager manifest)
- Xcode-specific files: `Info.plist`, `.xctestplan`, `.xcconfig`, `.entitlements`
- Discussion of iOS frameworks: CoreData, SwiftData, ARKit, HealthKit, etc.

## Core Guidance

### Tool & Skill Priority Order

| Priority | Tool/Skill | Purpose | When to Reach For It |
|----------|-----------|---------|---------------------|
| 1 | **XcodeBuildMCP** | Build, run, test, simulator ops | Always prefer over shell `xcodebuild` commands |
| 2 | **PFW skills** | Point-Free library guidance | When project uses TCA, Dependencies, etc. |
| 3 | **Axiom router skills** | Domain-specific iOS guidance | Architecture, patterns, debugging by domain |
| 4 | **Standalone Swift skills** | Language-level expertise | Concurrency, SwiftUI layout, Swift Testing |
| 5 | **ECC Swift skills** | Pattern libraries | Reference patterns for specific domains |
| 6 | **Sosumi MCP** | Apple documentation | API lookup, WWDC transcripts, external docs |

---

### XcodeBuildMCP

#### Session Startup Workflow

Always begin an iOS session with this sequence:

1. **`session_show_defaults`** -- check if session defaults (scheme, simulator, project) are already configured
2. **`discover_projs`** -- scan the directory for Xcode projects and workspaces
3. **`list_schemes`** -- enumerate available schemes for the discovered project
4. **`list_sims`** -- list available simulators (filter by device type and OS version)
5. **`session_set_defaults`** -- persist scheme, simulator, and project for the session so subsequent calls omit them
6. **`build_run_sim`** -- build and launch on the selected simulator

Use **`session_use_defaults_profile`** to switch between saved profiles (e.g., "iPhone-16-Pro", "iPad-Air").

#### Tool Catalog by Category

**Build:**

| Tool | Purpose |
|------|---------|
| `build_sim` | Build for simulator without launching |
| `build_run_sim` | Build and launch on simulator |
| `clean` | Clean build artifacts |
| `show_build_settings` | Inspect resolved build settings |

**Simulator Management:**

| Tool | Purpose |
|------|---------|
| `list_sims` | List available simulators |
| `boot_sim` | Boot a simulator |
| `open_sim` | Open Simulator.app with a specific device |
| `install_app_sim` | Install an app bundle on a simulator |
| `launch_app_sim` | Launch an installed app |
| `launch_app_logs_sim` | Launch app and stream logs |
| `stop_app_sim` | Stop a running app |
| `get_sim_app_path` | Get the app's sandbox path on simulator |
| `get_app_bundle_id` | Extract bundle ID from an app |

**Testing:**

| Tool | Purpose |
|------|---------|
| `test_sim` | Run tests on a simulator |
| `get_coverage_report` | Retrieve code coverage summary |
| `get_file_coverage` | Get line-by-line coverage for a specific file |

**UI Automation & Debugging:**

| Tool | Purpose |
|------|---------|
| `screenshot` | Capture simulator screenshot |
| `snapshot_ui` | Capture accessibility hierarchy snapshot |
| `record_sim_video` | Record simulator video |
| `start_sim_log_cap` | Begin capturing simulator logs |
| `stop_sim_log_cap` | Stop log capture and retrieve output |

**Session Management:**

| Tool | Purpose |
|------|---------|
| `session_set_defaults` | Set default scheme/simulator/project |
| `session_show_defaults` | Show current session defaults |
| `session_clear_defaults` | Clear all session defaults |
| `session_use_defaults_profile` | Switch to a named defaults profile |

---

### PFW (Point-Free World) Skills

Use when the project depends on Point-Free libraries. Check `Package.swift` or `Podfile` for these dependencies.

| Skill | Library | When to Use |
|-------|---------|-------------|
| `composable-architecture` | swift-composable-architecture (TCA) | Reducer composition, effects, store scoping, testing reducers |
| `dependencies` | swift-dependencies | Dependency injection, `@Dependency` usage, live/test/preview values |
| `swift-navigation` | swift-navigation | Navigation patterns (tree-based, stack-based), deep linking |
| `perception` | swift-perception | `@Perceptible` macro, backporting Observation to pre-iOS 17 |
| `observable-models` | -- | Combining Observation with TCA stores |
| `snapshot-testing` | swift-snapshot-testing | Snapshot test strategies, image/text/custom format assertions |
| `case-paths` | swift-case-paths | Enum case extraction, `@CasePathable`, pattern matching |

**Detection:** look for `import ComposableArchitecture`, `@Reducer`, `Store<`, `TestStore`, `@Dependency`, `@CasePathable` in Swift source files.

---

### Axiom Router Skills

Axiom provides domain-specific iOS guidance via router skills. Invoke with `/axiom:<skill-name>` or via the axiom-apple-docs skill.

| Skill | Domain | When to Use |
|-------|--------|-------------|
| `ios-build` | Build system, SPM, xcconfig | Build failures, dependency resolution, scheme/target config |
| `ios-ui` | SwiftUI, UIKit | Layout issues, navigation patterns, state management, animations |
| `ios-data` | CoreData, SwiftData, GRDB | Data modeling, migrations, fetch performance, persistence strategy |
| `ios-concurrency` | async/await, actors, Sendable | Swift 6 strict concurrency, actor isolation, task groups, data races |
| `ios-performance` | Instruments, profiling | Memory leaks, CPU spikes, hang detection, launch time optimization |
| `ios-integration` | System features | HealthKit, CloudKit, Push Notifications, App Intents, Widgets |
| `ios-ai` | Foundation Models | On-device ML, Foundation Models framework, CoreML integration |
| `ios-vision` | Camera, ARKit, Vision | Camera pipelines, AR experiences, image/video processing |

**Selection heuristic:** match the *domain* of the problem, not the symptom. A SwiftUI view that's slow? Start with `ios-ui` for the layout fix, escalate to `ios-performance` only if profiling is needed.

---

### Standalone Swift Skills

| Skill | Scope | Key Topics |
|-------|-------|------------|
| `swift-concurrency` | Swift 6 strict concurrency | `Sendable` conformance, `@MainActor` isolation, `nonisolated`, task groups, async sequences, data race safety |
| `swiftui-expert` | SwiftUI framework | Layout system (`GeometryReader`, custom layouts), navigation (`NavigationStack`, `NavigationSplitView`), state management (`@State`, `@Binding`, `@Observable`, `@Environment`), animations, gestures |
| `swift-testing-expert` | Swift Testing framework | `@Test`, `@Suite`, parameterized tests, traits, `#expect`, `#require`, migrating from XCTest |

---

### ECC Swift Knowledge Skills

Pattern libraries providing reference implementations. Invoke when the specific topic arises.

| Skill | Use Case |
|-------|----------|
| `swift-concurrency-6-2` | Swift 6.2 concurrency patterns, `nonisolated(nonsending)` default, caller-isolation inheritance |
| `swiftui-patterns` | Production SwiftUI patterns (MVVM, coordinator, dependency injection via environment) |
| `foundation-models-on-device` | On-device Foundation Models framework (iOS 26+), guided generation, tool calling |
| `liquid-glass-design` | iOS 26 Liquid Glass material system, `glassEffect`, design guidelines |

---

### Sosumi MCP (Apple Documentation)

Load via `ToolSearch("sosumi")` before first use.

| Tool | Purpose | Example |
|------|---------|---------|
| `searchAppleDocumentation` | Search Apple developer docs by keyword | `searchAppleDocumentation(query: "SwiftData ModelContainer")` |
| `fetchAppleDocumentation` | Fetch a specific documentation page by URL | `fetchAppleDocumentation(url: "https://developer.apple.com/documentation/swiftdata/modelcontainer")` |
| `fetchAppleVideoTranscript` | Get WWDC session transcript | `fetchAppleVideoTranscript(url: "https://developer.apple.com/videos/play/wwdc2024/10136/")` |
| `fetchExternalDocumentation` | Fetch non-Apple docs (e.g., Point-Free) | `fetchExternalDocumentation(url: "https://pointfreeco.github.io/swift-composable-architecture/")` |

**Workflow:** `searchAppleDocumentation` to find the right page, then `fetchAppleDocumentation` to get full content.

## If GSD Is Active

When GSD is managing an iOS project:

- **Build verification:** use XcodeBuildMCP `build_sim` (not shell `xcodebuild`) as the build verification step in GSD phases
- **Test verification:** use XcodeBuildMCP `test_sim` and `get_coverage_report` for GSD verification gates
- **Phase boundaries:** run `/compact` after the research/planning phase and before implementation, since iOS projects tend to generate large tool outputs (build logs, coverage reports)
- **GSD config:** ensure `.planning/config.json` has the Xcode scheme and simulator recorded so verification steps are reproducible

## Common Mistakes

| Mistake | Correction |
|---------|------------|
| Running `xcodebuild` via Bash instead of XcodeBuildMCP | Always use XcodeBuildMCP tools -- they handle derived data, simulator lifecycle, and error parsing |
| Forgetting `session_set_defaults` and repeating scheme/sim on every call | Set defaults once at session start; all subsequent tools inherit them |
| Using `ios-performance` before confirming the UI logic is correct | Fix correctness first (`ios-ui`), then profile (`ios-performance`) |
| Guessing Apple API signatures instead of checking Sosumi | Always `searchAppleDocumentation` before using unfamiliar APIs |
| Using XCTest patterns in new test files | Check if project uses Swift Testing (`@Test`/`@Suite`). Use `swift-testing-expert` for guidance |
| Loading all Axiom skills at once | Load only the domain-relevant skill. They're large context; loading multiple wastes budget |
| Not checking for PFW dependencies before advising architecture | Grep for `ComposableArchitecture`, `@Dependency`, `@CasePathable` first -- PFW projects have very different patterns |
| Building for device when simulator suffices | Prefer simulator for development iteration; device builds are slower and require signing |

## Quick Reference

```
Session start:
  session_show_defaults → discover_projs → list_schemes → list_sims → session_set_defaults

Build & run:     build_run_sim
Test:             test_sim → get_coverage_report
Debug UI:         snapshot_ui (accessibility tree), screenshot (visual)
Debug logs:       launch_app_logs_sim or start_sim_log_cap / stop_sim_log_cap

Skill selection:
  Using TCA?              → composable-architecture (PFW)
  PFW dependency?         → check PFW skills first, then Axiom
  Build broken?           → ios-build (Axiom) + build_sim (XcodeBuildMCP)
  SwiftUI layout wrong?   → ios-ui (Axiom) + swiftui-expert
  Data layer question?    → ios-data (Axiom) + sosumi (for API docs)
  Concurrency warning?    → ios-concurrency (Axiom) + swift-concurrency
  Need Apple API docs?    → sosumi: search → fetch
  Need WWDC session?      → sosumi: fetchAppleVideoTranscript
```
