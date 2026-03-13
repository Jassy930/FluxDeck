# 2026-03-13 Native Topology Token Flow

## 结果

- 原生端 `Topology` 页已从“单色请求粗线”升级为三列 token flow 画布：
  - 保持 `Entrypoints -> Gateways -> Providers`
  - 在链路内部按 model 分层表达 token 密度
  - 支持 `Tokens / Requests`
  - 支持 `By Model / Total Only`
  - 支持 `Top 3 / Top 5 / All`
- 原生端 `Topology` 页现已进一步重构为更接近参考图的 Sankey 主舞台：
  - 流带厚度计算抽为纯函数 `TopologyBandScale`
  - 所有小流量链路都遵守最小可读宽度
  - 节点降级为轻量锚点，不再承担完整诊断展示
  - hover 流带与 hover 节点均可弹出诊断 tooltip
  - 非关联链路与节点会降透明度，强化当前阅读焦点
  - 2026-03-13 第二轮减层级：
    - 去掉 `Topology` 外层大卡片
    - 去掉画布边界、列标题与轨道底板
    - 让主舞台直接贴页面底色
    - 节点收敛为名称 + 类型/端点 + 主指标的三行轻锚点
    - 控件条压成单行无标题切换，并以淡竖线完成三组分隔
- `TopologyGraph` 现已稳定聚合：
  - `totalTokens`
  - `requestCount`
  - `cachedTokens`
  - `errorCount`
  - `segments`
- 缺失 token 字段时，客户端会回填 `input_tokens + output_tokens`
- 未出现在 provider 列表中的 `provider_id` 会保留为占位节点，避免链路断裂
- 画布底部摘要已切换为：
  - `Hot Paths`
  - `Model Mix`
- 节点锚点已收敛为：
  - 单行 token / request 主摘要
  - 极简 `cached / err` 次信息
- 拓扑色板已进入 `DesignTokens.topologyModelColor(for:)`
- 画布颜色分配改为：
  - `Other / unknown` 使用保底低饱和色
  - 其余 model 按当前图内 token 排名分配稳定顺序色板，避免多个未知 model 共用同色

## 已确认范围

- 保持三列结构：`Entrypoints -> Gateways -> Providers`
- 不新增显式 `Models` 第四列
- 将 model 作为链路内部的 token 分类维度
- 主链路厚度优先编码 `total_tokens`
- 支持：
  - `Tokens / Requests`
  - `By Model / Total Only`
  - `Top 3 / Top 5 / All`
- 支持 hover 诊断：
  - 流带 tooltip：`from -> to`、model、tokens、requests、cached、errors
  - 节点 tooltip：总 token、总 req、top model、error count
- 底部摘要升级为：
  - `Hot Paths`
  - `Model Mix`

## 实现边界

- 第一版只使用原生端现有稳定数据：
  - `AdminGateway`
  - `AdminProvider`
  - `AdminLog`
- 不扩展后端拓扑专用契约
- 不做拖拽布局、缩放、详情抽屉
- 不修改暂停中的 `apps/desktop/` Web 桌面端

## 验证

- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasBuildsLightweightNodeSummaries -derivedDataPath /tmp/fluxdeck-native-derived-sankey-green1 -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasAppliesMinimumReadableBandWidth -derivedDataPath /tmp/fluxdeck-native-derived-sankey-green2 -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasPrioritizesBandStageOverHeavyCards -derivedDataPath /tmp/fluxdeck-native-derived-sankey-green3 -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasBuildsHoverTooltipPayloads -derivedDataPath /tmp/fluxdeck-native-derived-sankey-green4 -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasFlattensVisualHierarchyWithoutExtraChrome -derivedDataPath /tmp/fluxdeck-native-derived-sankey-flat-green -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasUsesSingleLineControlStripWithoutSectionTitles -derivedDataPath /tmp/fluxdeck-native-derived-sankey-controls-green -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphAggregatesTokenSegmentsPerEdge -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphFallsBackForMissingTokenFields -derivedDataPath /tmp/fluxdeck-native-derived-topology-verify1 -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyGraphBuildsTopModelHighlightsAndOtherBucket -derivedDataPath /tmp/fluxdeck-native-derived-topology-green2-fixed -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasSummaryUsesTokenSemantics -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasScreenModelExposesEmptyState -derivedDataPath /tmp/fluxdeck-native-derived-topology-green3c -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyFlowUsesStableModelPalette -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasSummaryUsesTokenSemantics -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyCanvasScreenModelExposesEmptyState -derivedDataPath /tmp/fluxdeck-native-derived-topology-green4 -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -only-testing:FluxDeckNativeTests/FluxDeckNativeTests/testTopologyFlowAssignsDistinctColorsToRankedModelsWithoutHardcodedNames -derivedDataPath /tmp/fluxdeck-native-derived-topology-green-color -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-topology-all -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-topology-final2 -quiet`：PASS
- `xcodebuild test -project apps/desktop-macos-native/FluxDeckNative.xcodeproj -scheme FluxDeckNative -derivedDataPath /tmp/fluxdeck-native-derived-sankey-final -quiet`：PASS
- `cargo test -q`：PASS（存在仓库已有 `unused variable: lines` warning）
- `./scripts/e2e/smoke.sh`：PASS，输出 `anthropic compat ok`、`smoke ok`

## 备注

- `xcodebuild` 仍会打印本机 XCTest runtime 的 macOS 版本链接 warning，本轮未处理该环境级噪音
- 2026-03-13 追加修复：
  - Topology 点击崩溃的根因是重复 `listenHost:listenPort` 生成了重复 entrypoint 节点 ID
  - 旧实现随后在节点查表中使用 `Dictionary(uniqueKeysWithValues:)`，遇到重复 key 会直接触发运行时崩溃
  - 现已在 `TopologyGraph` 中按 `entrypoint:<host>:<port>` 合并入口节点，并将路由文本查表改为覆盖式字典构建
  - 回归测试：`testTopologyGraphCoalescesDuplicateEntrypoints`
