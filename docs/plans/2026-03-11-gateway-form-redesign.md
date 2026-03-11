# Gateway Form Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the macOS native Gateway create/edit sheet into the same workbench-style configuration surface used by the Provider form.

**Architecture:** Keep the existing `GatewayFormSheet` entry points and submission flow, but replace the internal `Form` layout with a `ProviderFormSheet`-style card layout. Extract Gateway-specific derived UI helpers inside `ContentView.swift` first, then add focused native tests for compatibility labels and summary text to prevent regressions.

**Tech Stack:** SwiftUI, XCTest, xcodebuild

---

### Task 1: 重构 GatewayFormSheet 布局骨架

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Test: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写一个失败测试，描述新的 Gateway 摘要与辅助文案派生规则**

在 `FluxDeckNativeTests.swift` 增加针对 Gateway 表单派生文案的测试，覆盖：

- `host:port` 摘要
- `Auto Start` 开关对应文案
- 协议组合摘要

**Step 2: 运行原生测试，确认新增测试先失败**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: FAIL，提示缺少新的辅助函数或期望文案不匹配。

**Step 3: 在 GatewayFormSheet 中加入与 ProviderFormSheet 同构的布局**

实现内容：

- 顶部标题栏
- `Gateway Snapshot`
- 双栏 `Identity` / `Runtime`
- `Network & Protocols`
- `Routing JSON`
- 底部固定操作栏

**Step 4: 运行原生测试，确认布局重构没有破坏已有测试**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: PASS 或仅剩后续任务相关失败。

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "feat(native): redesign gateway form layout"
```

### Task 2: 将易错字段改为受控输入并补兼容逻辑

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Test: `apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift`

**Step 1: 写失败测试，覆盖未知 provider 和未知协议值的兼容显示**

测试点：

- 旧的 `defaultProviderId` 不在 providers 列表中时，仍能生成可显示标签
- 未知协议值不会在编辑态被 silently 丢失

**Step 2: 运行测试，确认兼容逻辑尚未实现**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: FAIL，提示新的兼容 helper 缺失或断言失败。

**Step 3: 实现 provider picker / protocol picker 与 unknown value fallback**

实现内容：

- `Default Provider` picker
- `Inbound Protocol` picker
- `Upstream Protocol` picker
- fallback label / fallback option

**Step 4: 运行测试，确认兼容逻辑通过**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: PASS

**Step 5: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift
git commit -m "feat(native): add controlled gateway form inputs"
```

### Task 3: 完善错误反馈、辅助卡片和说明文案

**Files:**
- Modify: `apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift`
- Modify: `docs/USAGE.md`
- Modify: `docs/ops/local-runbook.md`

**Step 1: 写失败测试或断言，覆盖 JSON 错误提示与提交前校验文案**

至少覆盖：

- 非法 JSON object 被拒绝
- 缺失默认 provider 时返回明确错误
- `Listen Port` 非法时保留已有校验

**Step 2: 运行测试，确认反馈逻辑先失败**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: FAIL

**Step 3: 实现局部错误反馈与 Routing Targets 辅助卡片**

实现内容：

- `Routing JSON` 卡片内错误提示
- `Routing Targets` provider 参考卡片
- 更清晰的底部摘要与说明文案

**Step 4: 更新文档**

同步更新：

- `docs/USAGE.md`
- `docs/ops/local-runbook.md`

说明 Gateway 原生配置页已与 Provider 统一为工作台式编辑界面，并支持基于现有 provider/协议值的受控编辑。

**Step 5: 运行验证**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: PASS

**Step 6: Commit**

```bash
git add apps/desktop-macos-native/FluxDeckNative/App/ContentView.swift apps/desktop-macos-native/FluxDeckNativeTests/FluxDeckNativeTests.swift docs/USAGE.md docs/ops/local-runbook.md
git commit -m "docs: sync gateway form redesign workflow"
```

### Task 4: 最终回归与工作区整理

**Files:**
- Modify: `docs/progress/` 下对应阶段记录（如需）

**Step 1: 运行最终验证**

Run: `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -quiet`

Expected: PASS

**Step 2: 检查 git 状态**

Run: `git status --short`

Expected: 仅包含本次 Gateway 表单重构相关文件。

**Step 3: 记录阶段性结果**

如本轮实现新增了用户可见行为变更或验证方式，补充更新 `docs/progress/` 或相关完成记录。

**Step 4: Commit**

```bash
git add .
git commit -m "feat(native): unify gateway workbench form"
```
