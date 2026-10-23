PCL 自定义主页 · 一键安装包（PCL2 / PCL CE 可选）

【安装】
1. 完全退出 PCL2 或 PCL CE（安装会写入它的设置文件；安装器也会检查并提示）。
2. 双击 PCL主页安装[支持CE].exe。
3. 在窗口右上角选择语言。界面和主页会同时使用该语言，例如选择 English，
   PCL / PCL CE 中显示的也是英文；选择中文也一样。
4. 选择要安装到的启动器：
   PCL2（原版，使用 Setup.ini）或 PCL CE（使用 config.v1.yml）。
5. 选择对应的数据文件夹：
   - PCL2：包含 Setup.ini 的 PCL 文件夹；
   - PCL CE：包含 config.v1.yml 的 PCL 文件夹。
   通常在启动器 exe 旁边；直接选启动器根目录也可以，安装器会自动识别。
6. 点击“安装”。如果该文件夹已经安装过，可以选“覆盖安装”或“卸载”。
7. 装完后打开对应的启动器就能看到新主页；如果启动器已经开着，按 F5 刷新或重开。

【支持的语言】
简体中文、English、繁體中文、日本語、한국어、Français、Deutsch、Español、
Português (Brasil)、Русский、Italiano、Nederlands、Polski、Türkçe、Tiếng Việt。
安装器界面和主页文字会一起切换；主页语言显示在安装按钮右侧。
安装后再换语言时，重新点一次“安装”即可覆盖主页文字。

【卸载】
在安装器中选择对应启动器和数据文件夹，点击“卸载”即可。
也可以命令行运行：
  "PCL主页安装[支持CE].exe" uninstall "D:\PCL-CE\PCL"

【命令行】
  "PCL主页安装[支持CE].exe" pcl
  "PCL主页安装[支持CE].exe" ce
  "PCL主页安装[支持CE].exe" pcl "D:\PCL"
  "PCL主页安装[支持CE].exe" ce "D:\PCL-CE"
pcl = PCL2（原版），ce = PCL CE；省略文件夹时会弹出选择框。
带参数运行时会自动打开命令行窗口，方便查看输出。
命令行默认跟随 Windows 显示语言；也可以先用环境变量指定主页语言：
  set PCLHOME_LANG=ja
  "PCL主页安装[支持CE].exe" ce "D:\PCL-CE"
PCLHOME_LANG 支持 zh、zh-CN、zh-TW、en、ja、ko、fr、de、es、pt、pt-BR、ru、
it、nl、pl、tr、vi 等写法。

【说明】
- 安装前必须选择 PCL2 或 PCL CE；安装器只修改所选启动器的配置
  （Setup.ini 或 config.v1.yml），不会顺带改另一个。
- PCL2 和 PCL CE 安装的是同一个主页页面，只是数据文件夹和配置格式不同。
- 选错启动器类型时，安装器会提示该文件夹不匹配，并让你重新选择。
- PCL CE 会额外写入 HintCustomCommand: true，避免第一次点击主页按钮时弹出命令确认框。
- 安装会同时调整启动器的透明度、背景、Logo 等界面设置以获得主题效果；
  卸载时会把主页开关恢复为默认，其他界面设置保持不变。
- PCL CE 的启动器日志在 PCL\Log\Launch-*.log，PCL2 的日志在 PCL\Log1.txt；
  主页上的“启动器日志”按钮会自动打开当前格式对应的日志。
- 首次运行若被 Windows SmartScreen 拦截：点“更多信息”→“仍要运行”。

============================================================
PCL Custom Homepage - One-click Installer (PCL2 / PCL CE)

[Install]
1. Fully exit PCL2 or PCL CE first. The installer writes to its settings file.
2. Double-click PCL主页安装[支持CE].exe.
3. Choose a language at the top-right. The installer UI and the homepage use
   the same language: choosing English shows English text in PCL / PCL CE;
   choosing Chinese does the same in Chinese.
4. Select the launcher you want to install to:
   PCL2 (Original, uses Setup.ini) or PCL CE (uses config.v1.yml).
5. Select the matching data folder:
   - PCL2: the PCL folder containing Setup.ini.
   - PCL CE: the PCL folder containing config.v1.yml.
   It is usually next to the launcher exe. You can also select the launcher
   root folder; the installer detects the correct data folder automatically.
6. Click "Install". If a custom homepage is already installed, choose
   "Reinstall" or "Uninstall".
7. Open the launcher to see the new homepage. If it is already running,
   press F5 or reopen it.

[Supported languages]
Simplified Chinese, English, Traditional Chinese, Japanese, Korean, French,
German, Spanish, Portuguese (Brazil), Russian, Italian, Dutch, Polish, Turkish,
Vietnamese. The installer UI and homepage switch together. The homepage
language is shown next to the Install button. To change it later, reinstall
the homepage with the new language selected.

[Uninstall]
Select the launcher and data folder in the installer, then click "Uninstall".
You can also use the command line:
  "PCL主页安装[支持CE].exe" uninstall "D:\PCL-CE\PCL"

[Command line]
  "PCL主页安装[支持CE].exe" pcl
  "PCL主页安装[支持CE].exe" ce
  "PCL主页安装[支持CE].exe" pcl "D:\PCL"
  "PCL主页安装[支持CE].exe" ce "D:\PCL-CE"
pcl = PCL2 (Original), ce = PCL CE. If the folder is omitted, a picker opens.
When arguments are supplied, a console window opens so you can see the output.
The command line follows the Windows display language by default. You can
override the homepage language with:
  set PCLHOME_LANG=ja
  "PCL主页安装[支持CE].exe" ce "D:\PCL-CE"
PCLHOME_LANG accepts zh, zh-CN, zh-TW, en, ja, ko, fr, de, es, pt, pt-BR, ru,
it, nl, pl, tr, vi and similar codes.

[Notes]
- PCL2 and PCL CE install the same homepage page; only the data folder and
  config format differ.
- The installer only modifies the selected launcher's config file
  (Setup.ini or config.v1.yml); the other launcher is untouched.
- If the selected folder belongs to the other launcher, the installer warns
  you and lets you choose again.
- PCL CE also gets HintCustomCommand: true, so the first homepage click does
  not show a command confirmation dialog.
- The installer also adjusts transparency, background, logo and other UI
  settings for the theme. Uninstalling restores the homepage switch and
  leaves the other UI settings unchanged.
- PCL CE logs are in PCL\Log\Launch-*.log; PCL2 logs are in PCL\Log1.txt.
  The "Launcher log" button on the homepage opens the matching log.
- If Windows SmartScreen blocks the first run, click "More info" -> "Run anyway".
