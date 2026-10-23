PCL 自定义主页 · 一键安装包（PCL2 / PCL CE 可选）

【安装】
1. 完全退出 PCL2 或 PCL CE（安装会写入它的设置文件；安装器也会等待你退出）。
2. 双击 PCL主页安装[支持CE].bat。
3. 先选择要安装到的启动器：
   1 = PCL2（原版，使用 Setup.ini）
   2 = PCL CE（使用 config.v1.yml）
4. 再选择对应的数据文件夹：
   - PCL2：包含 Setup.ini 的 PCL 文件夹；
   - PCL CE：包含 config.v1.yml 的 PCL 文件夹。
   通常在启动器 exe 旁边；直接选启动器根目录也可以，会自动识别为所选版本的 PCL 文件夹。
5. 装完后打开对应的启动器就能看到新主页；如果启动器已经开着，按 F5 刷新或重开。

【卸载】
再次运行 PCL主页安装[支持CE].bat，选择对应启动器并选中已安装的文件夹，
提示已安装时输入 u 回车；或命令行运行：
  "PCL主页安装[支持CE].bat" uninstall "D:\PCL-CE\PCL"

【命令行指定启动器】
  "PCL主页安装[支持CE].bat" pcl
  "PCL主页安装[支持CE].bat" ce
  "PCL主页安装[支持CE].bat" pcl "D:\PCL"
  "PCL主页安装[支持CE].bat" ce "D:\PCL-CE"
pcl = PCL2（原版），ce = PCL CE；省略文件夹时会弹出选择框。

【说明】
- 安装前必须选择 PCL2 或 PCL CE；安装器只修改所选启动器的配置
  （Setup.ini 或 config.v1.yml），不会顺带改另一个。
- 选错启动器类型时，安装器会提示该文件夹不匹配，并让你重新选择。
- PCL CE 会额外写入 HintCustomCommand: true，避免第一次点击主页按钮时弹出命令确认框。
- 安装会同时调整启动器的透明度、背景、Logo 等界面设置以获得主题效果；
  卸载时会把主页开关恢复为默认，其他界面设置保持不变。
- PCL CE 的启动器日志在 PCL\Log\Launch-*.log，PCL2 的日志在 PCL\Log1.txt；
  主页上的“启动器日志”按钮会自动打开当前格式对应的日志。
- 首次运行若被 Windows SmartScreen 拦截：点“更多信息”→“仍要运行”。
