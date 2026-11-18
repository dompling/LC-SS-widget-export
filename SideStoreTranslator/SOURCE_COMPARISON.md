# SideStore 源码对照记录

## 对照基准

LC+SS 的 `.github/build_github.sh` 下载 `LiveContainer/SideStore` 的 nightly IPA，
因此本次检查的是实际集成分支，而不是只检查 SideStore 官方 develop：

- 仓库：<https://github.com/LiveContainer/SideStore>
- 分支：`LiveContainerSupport`
- 提交：`044bd72ad4eb270c3900bd04dc6f508d0ac474db`
- 本地只读参考：`/tmp/LCSS-SideStore-source`

旧 inventory 的 1,726 个 key 来自未合并的官方本地化 PR #1495，不能代表
当前集成分支的完整界面。本次保留历史清单，新增词条记录在 `supplementalKeys`，
每条指向当前源码文件。品牌、协议名、文件名、示例地址和数字不强行汉化。
本次未改动 SideStore 源码、安装流程或插件注入机制。

## 插件原理和遗漏原因

1. 主程序插件在启动内置 SideStore 前，将自己的 dylib 路径加入 LC 的一次性
   `preloadLibraries.txt`。下次启动时，LC 在加载自身共享框架前先加载插件。
2. 插件安装 NSBundle 本地化方法、CoreFoundation 本地化函数和 UIKit 文案设置
   方法的 hook。只有 `NSUserDefaults.isSideStore` 为真时才启用翻译。
3. JSON 是“完整英文原文 → 中文”的精确映射，构建时嵌入 dylib。
   Storyboard 文案另有 `awakeFromNib` 和页面显示时遍历视图的补偿。
4. 原版仅使用 CoreFoundation 拦截，遗漏了 `UserCustomizationsView.swift` 的
   `toggleRow` / `textFieldRow`：它们将 String 传入 `Text(title)` / `Text(subtitle)`，
   并不发起本地化查询。本次修复改为重绑定内置 SideStore 镜像导入的 Text 泛型
   初始化器及 LocalizedStringKey 的字面量/String 初始化器，直接使用同一份词典。
   Swift 包装函数保持原生调用约定和 consuming 所有权；未命中时调用未改动的原实现。
5. `Text("…\(value)…")` 等动态文案也不能简单按最终英文文本精确匹配。
   源码中的 `String(format: NSLocalizedString(...))` 则在格式化之前查询 key，
   可按原有本地化路径翻译。不能把 Swift 插值模板猜成 `%@` key 写入 JSON。
6. LC 主容器 `Documents/SideStoreTranslator/zh-Hans.json` 若存在，会整体替换
   内嵌词典；旧外置 JSON 会覆盖新版补充内容。更新 dylib 时也要同步外置词典，
   或移除外置覆盖，并重启内置 SideStore。`status.json` 的 `source` 可确认来源。

插件通过 `dlopen` 预载，静态 `__interpose` 表无法在此加载方式下接管后续 SwiftUI
调用。这也是必须修复的加载问题。本次复用仓库已有 litehook，在 dyld 镜像回调中
仅处理 `SideStoreApp.framework`，既处理已加载镜像也处理后续加载，绝不重绑定插件
自身或其他框架。用真实 SwiftUI 的 `dlopen(插件) -> dlopen(模拟 guest)` 和反向
顺序验证，不再只测试 `DYLD_INSERT_LIBRARIES`。保留上下文与精确 key 匹配限制，
不对子串、用户输入或未知文本做通用机器翻译。

## 翻译语义与格式安全

- 区分重新签名（Resign）、撤销证书（Revoke）、停用应用（Deactivate）、删除本地
  描述文件与从开发者平台删除描述文件，不把不同操作统一译成“删除”。
- Sheet 在此是弹出面板，Entitlements 是签名的权限声明，不能理解成普通表单或授权账号。
- 修复了删除团队描述文件确认文案中 `%d` 和 `%@` 顺序互换的问题；这可能导致格式化
  时将数量作为对象读取。校验现在同时检查占位符类型、数量与非位置参数的顺序。
  显式位置参数（如 `%1$d`、`%2$@`）可按位置标记安全调换。
- 格式校验器仍保守处理含 `%` 的文本。例如 `~40% faster` 会被 printf 正则识别成
  `% f`；该说明暂不强行添加，避免为单一文案放宽格式安全校验。

## 可重复对比

本次新增 331 条，词典总数 2,045 条；修正 5 条已有译文。最终扫描结果：

| 检查项 | 结果 |
| --- | --- |
| 明确的静态源码 key 已有译文 | 1,185 / 1,237 |
| 命名 UI 参数候选已有译文 | 155 / 173 |
| 动态插值模板位置 | 193 |
| 运行时 Text 变量位置 | 251 |
| 历史及补充清单已有译文 | 2,045 / 2,087 |

未翻译项包含品牌、数字、示例、许可证及上述自然百分号说明，不能全部认定为遗漏。
12 项提取和格式安全回归测试通过；新增 supplemental key 已逐条核对实际 Swift
字符串；独立 arm64 iOS dylib 编译通过（最低 iOS 15.0）。没有进行真机注入测试。

```sh
python3 SideStoreTranslator/scripts/compare_source.py \
  --source-root /tmp/LCSS-SideStore-source \
  --output SideStoreTranslator/.generated/source-audit.json
python3 -m unittest discover -s SideStoreTranslator/scripts -p 'test_*.py' -v
bash SideStoreTranslator/tests/run-swiftui-tests.sh
bash SideStoreTranslator/build.sh dist/SideStoreTranslator.dylib
```

报告分开列出明确的静态源码 key、待人工判断的命名 UI 参数、插值模板、运行时
`Text(variable)` 位置，并保留文件和行号。扫描范围包括 iOS、tvOS 和 Widget，
不是当前 iPhone 画面的覆盖率。词法扫描不覆盖间接常量、raw Swift 字符串、
Objective-C、依赖及服务端文案；运行时变量也不一定都是英文或需要翻译。

本地构建和 JSON 校验不能替代真机检查，尤其是早期加载、SwiftUI 桥接和不同 iOS
版本的表现。现有插件没有提供全界面汉化的保证。

## 设置二级页面修复验证

- 不加载新桥接时，`Text(String)` 的同一条设置文案复现为英文，负对照如预期失败。
- 真实 macOS SwiftUI 下通过 `dlopen` 加载插件和 guest，两种加载顺序及两种优化等级
  均通过；停用翻译和非 SideStoreApp 框架保持英文。每次运行含 5,000 次文本创建。
- 优化后的同一 Swift 包装及 guest 测试在 arm64 iOS 18.6 模拟器通过，启用时翻译、
  关闭时保持原文。另测试旧式非 chained fixups 导入指针布局通过。
- 新插件使用仓库现有 litehook，编译进独立 dylib 并隐藏其符号；没有新增外部依赖。
- 未运行真实手机上的 LC+SS。安装新版时需替换 dylib、重新签名并完全重启 LC，
  再打开内置 SideStore；只更新 JSON 不会安装新的文本入口修复。
