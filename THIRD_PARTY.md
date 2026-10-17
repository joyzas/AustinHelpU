# 来源与变更说明

参考项目：suversal/apple-store-inventory-monitor（果到雷达）
https://github.com/suversal/apple-store-inventory-monitor
其上游：ENCHIGO/apple-pickup-watcher v0.3.2
原许可证：GPL-3.0-or-later。LICENSE、NOTICE 随交付保留。

本次主要变更：
- 新建 SwiftUI 原生 macOS 应用，不使用原 React / Tauri 运行时。
- 将中国大陆门店和 iPhone 商品目录转换为精简 JSON。
- 用 Foundation WebSocket 与专属 Chrome / Edge 会话实现库存查询。
- 新建独立 mihomo 进程管理与订阅导入界面。
- 新建提醒、节点冷却、轮换、菜单栏与本地配置实现。
- 不包含原项目自动结账、加购和下单代码。
- 应用名称更新为 AustinHelpU，应用图标直接使用用户提供的原图，只作方形裁切和多尺寸缩放，未使用参考仓库的品牌图标。

官方代理组件：https://github.com/MetaCubeX/mihomo
组件下载使用 GitHub Release API 提供的 SHA-256 摘要核验；该组件并未预置在当前安装包中。
