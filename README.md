# PCL 自定义主页安装器（支持 PCL2 / PCL CE）

![PCL 自定义主页](src/icon.png)

为 PCL2 和 PCL CE 一键安装同一套自定义主页。安装器使用图形界面，支持 15 种语言；安装器界面语言会同步决定主页语言。

## 功能

- 图形界面 EXE，启动时不显示控制台窗口；命令行参数仍可用于安装和卸载。
- 可选择 PCL2 或 PCL CE，只修改所选启动器的配置，不影响另一个启动器。
- 15 种语言：简体中文、English、繁體中文、日本語、한국어、Français、Deutsch、Español、Português (Brasil)、Русский、Italiano、Nederlands、Polski、Türkçe、Tiếng Việt。
- 卸载后启动器恢复自带主页，其他界面设置保持不变。
- 兼容包含空格、`&`、括号等字符的路径。
- 不注入 DLL；旧版 `InjectDll.ps1` 已移除，不参与构建。
- 安装后保留主页背景、日志查看器和辅助工具。

## 使用

1. 构建或获取 `dist/PCL主页安装[支持CE].zip`。
2. 解压后运行 `PCL主页安装[支持CE].exe`。
3. 选择启动器和安装器语言，然后点击安装。
4. 启动 PCL2 / PCL CE 查看自定义主页。

安装器只写入所选启动器的配置和 PCL 自定义主页目录。卸载时会先要求关闭对应的启动器。

## 构建

环境：Windows 10/11、PowerShell 5.1、.NET Framework 4.x（系统自带 `csc.exe`）。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

输出位于 `dist/`：

- `PCL主页安装[支持CE].bat`：构建中间产物
- `PCL主页安装[支持CE].exe`：图形界面安装器
- `PCL主页安装[支持CE]-使用说明.txt`
- `PCL主页安装[支持CE].zip`：一键安装包，只包含 EXE 和使用说明

## 目录结构

```text
build.ps1               生成 BAT、把 BAT 嵌入 EXE，并打包一键安装 ZIP
src/installer.ps1       安装/卸载逻辑、15 种界面语言和主页语言
src/page.xaml           自定义主页模板，含 @@PCLHOME_*@@ 本地化标记
src/launcher.cs         WinForms EXE 引导器，负责解压并运行内嵌 BAT
src/header.bat          BAT 解压和控制台处理
src/tools/              主页按钮使用的辅助脚本和共享背景图
publish.ps1             维护脚本：通过 GitHub CLI 发布当前源码快照
```

## 说明

- `Custom.xaml` 是 XAML 片段，不是完整 XML 文档。
- 主页可见文本通过 `@@PCLHOME_*@@` 标记本地化，安装时由 `installer.ps1` 替换；辅助脚本内部和页面注释保持中文。
- `src/tools/InjectDll.ps1` 是旧版 DLL 注入脚本，已从当前版本移除，不参与构建。
- 安装器只修改所选启动器（PCL2 或 PCL CE）的配置。
- 一键安装 ZIP 只包含 EXE 和使用说明，BAT 是构建中间产物。

## 许可证

GPL-3.0，详见 [LICENSE](LICENSE)。
