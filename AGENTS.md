# 项目维护说明

- 本项目是 PCL2 / PCL CE 自定义主页安装器，保持 15 种语言、图形界面 EXE，并让安装器语言决定主页语言。
- 修改源码或文档后，先构建并运行必要测试，再执行发布脚本：
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\publish.ps1 -Message "本次改动摘要"
  ```
- `publish.ps1` 使用已登录的 GitHub CLI（XC-Xin-Cheng），通过 GitHub Git Data API 更新 `main` 分支；不需要本地安装 Git。
- 发布内容不包含 `build/`、`dist/` 和 `src/tools/InjectDll.ps1`。
- 每次完成源码提交后，同步更新 GitHub Releases：版本号递增（如 v1.1 → v1.2），在最新 `main` 提交上创建 Release 并设为 Latest，至少上传当前 EXE 和使用说明，同时上传一键安装 ZIP。
- Release 资产名使用 ASCII，例如 `PCL.Homepage.Installer.CE.Supported.exe`、`PCL.Homepage.Installer.CE.Supported.UserGuide.txt`、`PCL.Homepage.Installer.CE.Supported.zip`，避免 `gh` 把方括号当作通配符。不要覆盖旧版本资产。
- 不要修改 `D:\PCL` 或 `D:\PCL-CE`；测试请使用沙箱目录。
- PCL2 和 PCL CE 安装同一套主页；安装器只修改所选启动器的配置。
- 保持卸载后恢复启动器自带主页，并保留其他界面设置。
