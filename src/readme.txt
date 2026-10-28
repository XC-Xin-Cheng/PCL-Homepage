PCL 自定义主页 · 一键安装包（PCL2 / PCL CE 可选）

【兼容性】
- 仅支持低于 2.99.0.0 的 PCL2 / PCL CE 版本；2.99.0.0 起不适配。
- 如果启动器版本为 2.99.0.0 或更高，安装器会提示：
  “你这个版本的PCL安装主页已经没有意义了
   未对您的计算机进行更改”
  并且不会写入任何文件、配置或开机自启项；本次安装尝试会直接撤销。
- 已安装旧主页的用户仍可手动卸载；卸载后启动器会恢复自带主页。

【安装】
1. 完全退出 PCL2 或 PCL CE（安装会写入它的设置文件；安装器也会检查并提示）。
   如果忘记退出，安装器会询问是否帮你关闭：选 YES 只关闭当前选择的
   PCL2 或 PCL CE，选 NO 取消本次安装，不会修改任何内容。
2. 双击 PCL主页安装[支持CE].exe。
3. 在窗口右上角选择语言。界面和主页会同时使用该语言，例如选择 English，
   PCL / PCL CE 中显示的也是英文；选择中文也一样。
4. 选择要安装到的启动器：
   PCL2（原版，使用 Setup.ini）或 PCL CE（使用 config.v1.yml）。
5. 选择对应的数据文件夹：
   - PCL2：包含 Setup.ini 的 PCL 文件夹；
   - PCL CE：包含 config.v1.yml 的 PCL 文件夹。
   通常在启动器 exe 旁边；直接选启动器根目录也可以。
   选择文件夹或点“检测”时只检查路径；点击“安装”后才自动识别并选中
   PCL2 / PCL CE（两种都支持），不会提前切换。
6. 点击“安装”。如果该文件夹已经安装过，可以选“覆盖安装”或“卸载”。
7. 装完后打开对应的启动器就能看到新主页；如果启动器已经开着，按 F5 刷新或重开。

【支持的语言】
简体中文、English、繁體中文、日本語、한국어、Français、Deutsch、Español、
Português (Brasil)、Русский、Italiano、Nederlands、Polski、Türkçe、Tiếng Việt。
安装器界面和主页文字会一起切换；主页语言显示在安装按钮右侧。
安装后再换语言时，重新点一次“安装”即可覆盖主页文字。

【卸载】
在安装器中选择对应启动器和数据文件夹，点击“卸载”即可。
卸载时如果对应启动器正在运行，也会询问是否帮你关闭；YES 只关闭当前
选择的启动器，NO 取消卸载。
也可以命令行运行：
  "PCL主页安装[支持CE].exe" uninstall "D:\PCL-CE\PCL"

【命令行】
  "PCL主页安装[支持CE].exe" pcl
  "PCL主页安装[支持CE].exe" ce
  "PCL主页安装[支持CE].exe" pcl "D:\PCL"
  "PCL主页安装[支持CE].exe" ce "D:\PCL-CE"
pcl = PCL2（原版），ce = PCL CE；省略文件夹时会弹出选择框。
带参数运行时会自动打开命令行窗口，方便查看输出；只要图形界面时不要带参数。
命令行默认跟随 Windows 显示语言；也可以先用环境变量指定主页语言：
  set PCLHOME_LANG=ja
  "PCL主页安装[支持CE].exe" ce "D:\PCL-CE"
PCLHOME_LANG 支持 zh、zh-CN、zh-TW、en、ja、ko、fr、de、es、pt、pt-BR、ru、
it、nl、pl、tr、vi 等写法。

【说明】
- 安装器、开机自启、主页按钮、日志刷新和彩蛋都不会弹出命令行窗口。
  安装后会写入无窗口启动器 PCLHomeLaunch.vbs，请不要删除它。
- 只有带参数运行命令行安装/卸载时才会显示命令行窗口，方便查看输出；
  双击图形界面安装器不会显示。
- 如果之前装过旧版，重新安装一次即可把开机自启项更新为无窗口方式。
- 安装前必须选择 PCL2 或 PCL CE；安装器只修改所选启动器的配置
  （Setup.ini 或 config.v1.yml），不会顺带改另一个。
- PCL2 和 PCL CE 安装的是同一个主页页面，只是数据文件夹和配置格式不同。
- 选择文件夹或点“检测”时只检查路径；点击“安装”后才会自动识别并选中
  PCL2 / PCL CE（两种都支持），不会提前切换。
- 关闭询问只显示“要不要帮你关闭”，不附加括号说明。
- PCL CE 会额外写入 HintCustomCommand: true，避免第一次点击主页按钮时弹出命令确认框。
- 安装会同时调整启动器的透明度、背景、Logo 等界面设置以获得主题效果；
  卸载时会把主页开关恢复为默认，其他界面设置保持不变。
- PCL CE 的启动器日志在 PCL\Log\Launch-*.log，PCL2 的日志在 PCL\Log1.txt；
  主页上的“启动器日志”按钮会自动打开当前格式对应的日志。
- 主页右侧下方新增“自定义指令”面板：点开后可新增、编辑、删除和保存指令，
  也可直接把指令发送到正在运行的 Minecraft。第一次执行时请在 15 秒内点击
  一次游戏窗口，管理器会静默等待、识别并记住它；之后需要连续点击两次
  “执行”确认才会发送。发送前会检查是否在游戏内，并自动关闭已打开的 GUI，
  多次确认后再输入指令；确认失败则不执行。识别成功时目标窗口行会短暂显示
  “识别成功”，3 秒后消失，不保存识别缓存。
- 也可以用“选择窗口”按钮重新识别目标窗口：每次点击都会先清除旧目标，
  再识别你随后点击的窗口并更新，不会固定为第一次的结果。发送时会输入“/”，
  粘贴指令并回车。
- 自定义指令保存在 PCL\CustomCommands.json，卸载主页时不会删除这个文件，
  方便以后重新安装后继续使用。管理器不会绕过服务器权限。
- 左上角“打开游戏目录”按钮名称保持不变；悬停提示和点击打开的文件夹
  已改为当前实例文件夹（没有选中实例时回退到游戏目录）。
- 首次运行若被 Windows SmartScreen 拦截：点“更多信息”→“仍要运行”。

============================================================
PCL Custom Homepage - One-click Installer (PCL2 / PCL CE)

[Compatibility]
- Supports PCL2 / PCL CE versions below 2.99.0.0 only; 2.99.0.0 and later are not supported.
- If the launcher is 2.99.0.0 or newer, the installer shows:
  "Installing a custom homepage for this PCL version is no longer meaningful.
   No changes have been made to your computer."
  It writes no files, config or startup entries; the install attempt is cancelled.
- If an older custom homepage is already installed, you can still uninstall it
  manually; uninstalling restores the launcher's built-in homepage.

[Install]
1. Fully exit PCL2 or PCL CE first. The installer writes to its settings file.
   If it is still running, the installer asks whether to close it: YES closes
   only the currently selected PCL2 or PCL CE; NO cancels the install without
   changing anything.
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
   root folder. Selecting a folder or clicking Detect only checks the path;
   clicking Install auto-detects and selects PCL2 / PCL CE (both supported).
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
If the matching launcher is running, the installer asks whether to close it:
YES closes only the selected launcher; NO cancels the uninstall.
You can also use the command line:
  "PCL主页安装[支持CE].exe" uninstall "D:\PCL-CE\PCL"

[Command line]
  "PCL主页安装[支持CE].exe" pcl
  "PCL主页安装[支持CE].exe" ce
  "PCL主页安装[支持CE].exe" pcl "D:\PCL"
  "PCL主页安装[支持CE].exe" ce "D:\PCL-CE"
pcl = PCL2 (Original), ce = PCL CE. If the folder is omitted, a picker opens.
When arguments are supplied, a console window opens so you can see the output;
run without arguments when you want the GUI.
The command line follows the Windows display language by default. You can
override the homepage language with:
  set PCLHOME_LANG=ja
  "PCL主页安装[支持CE].exe" ce "D:\PCL-CE"
PCLHOME_LANG accepts zh, zh-CN, zh-TW, en, ja, ko, fr, de, es, pt, pt-BR, ru,
it, nl, pl, tr, vi and similar codes.

[Notes]
- The installer, logon startup, homepage buttons, log refresh and easter egg
  do not open a console window. The installer writes a windowless launcher
  named PCLHomeLaunch.vbs; do not delete it.
- Only command-line installs/uninstalls open a console window so you can see
  the output. Double-clicking the GUI installer does not.
- If you installed an older version, run the installer again to update the
  logon entry to the windowless launcher.
- PCL2 and PCL CE install the same homepage page; only the data folder and
  config format differ.
- The installer only modifies the selected launcher's config file
  (Setup.ini or config.v1.yml); the other launcher is untouched.
- Selecting a folder or clicking Detect only checks the path; clicking Install
  auto-detects and selects PCL2 / PCL CE (both supported). It does not switch
  the launcher type early.
- The close prompt shows only the question, with no parenthetical
  clarification.
- PCL CE also gets HintCustomCommand: true, so the first homepage click does
  not show a command confirmation dialog.
- The installer also adjusts transparency, background, logo and other UI
  settings for the theme. Uninstalling restores the homepage switch and
  leaves the other UI settings unchanged.
- PCL CE logs are in PCL\Log\Launch-*.log; PCL2 logs are in PCL\Log1.txt.
  The "Launcher log" button on the homepage opens the matching log.
- A "Custom commands" panel is at the bottom right of the homepage. Open it
  to add, edit, delete and save commands, or send one to the running Minecraft
  client. On the first run, click the Minecraft window within 15 seconds; the
  manager waits silently and remembers it for this session. To send, click Run
  twice within 10 seconds. Before sending, the manager checks that you are in a
  world, closes an open GUI, and confirms the state several times; if it cannot
  confirm, nothing is sent. "Recognized" appears briefly after the target
  window line for 3 seconds and is not cached. Reopening the manager requires
  recognizing the window again.
- Use "Select window" to recognize a new target: each click clears the old
  target, then recognizes and updates the window you click next; it does not
  stay fixed to the first result. The sender types "/", pastes the command and
  presses Enter.
- The "Open game folder" button keeps its name; its tooltip and the folder it
  opens now point to the current instance folder (falling back to the game
  folder when no instance is selected).
- Commands are stored in PCL\CustomCommands.json. Uninstalling the homepage
  keeps this file so you can reuse your commands after reinstalling. The
  manager does not bypass server permissions.
- If Windows SmartScreen blocks the first run, click "More info" -> "Run anyway".
