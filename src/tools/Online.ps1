# Online.ps1 - standalone multiplayer helper for the PCL custom homepage.
#
# It is the third block in the right hand column of the page.  The window
# finds, downloads and starts Terracotta (陶瓦联机), the free LAN over the
# internet tool that HMCL uses: the host creates a room and shares the room
# code, friends join it, and Minecraft then shows a "陶瓦联机大厅" entry in
# the multiplayer list as if everyone were on the same LAN.
#
# The program itself is a separate open source project by burningtnt:
#   https://github.com/burningtnt/Terracotta  (AGPL-3.0)
# This script only wraps the official, unmodified binary: it never bundles or
# patches it, and it downloads from the official GitHub release (with the
# Gitee mirror as a fallback).
#
# Terracotta has no native window: it serves its own control page on a random
# local port.  The window embeds that page with WebView2, so the whole room UI
# lives inside this window.  If WebView2 cannot start, the page is opened in
# the default browser instead.
#
# The UI language follows CommandManager.lang, which the installer writes with
# the homepage language.  Everything runs windowless: the page starts
# CustomTools.bat through PCLHomeLaunch.vbs.
param(
    [string]$BaseDir = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Give the process its own AppUserModelID so the taskbar uses the form icon
# instead of the blue PowerShell icon.
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PCLHomeOnlineShell {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
}
'@
    [void][PCLHomeOnlineShell]::SetCurrentProcessExplicitAppUserModelID('PCL.Homepage.Online')
} catch { }

if (-not $BaseDir) { $BaseDir = $PSScriptRoot }
$script:BaseDir = [IO.Path]::GetFullPath($BaseDir).TrimEnd('\')
$script:OnlineDir = Join-Path $script:BaseDir 'Online'
$script:WebView2Dir = Join-Path $script:BaseDir 'WebView2'
$script:ExePath = ''
$script:DlAsset = $null
$script:DlTag = ''
$script:InstallStage = ''

# Terracotta's own 32x32 icon, used before the program has been downloaded.
$script:IconPng = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAARMSURBVFhHtZbvT1NXGMfvH2HGBvf2120vpbW0q9CWQqnYdZTuhW6ZwJyMBOYkmCUYt2wG2QsFNjdFfWGmKOCwNDEa3KYTR5a9mDCT/dBgYqIZ6p/ymOfAOT0/bqGS7MU3vafn9nw+z3NOb6sBgIa5Fw9tJbAe+X2SFwd6WJ72dGsFn0+7uh7KZRcr72QqDgeWsykYg/coAvyHNghUmLJgzMpQryrA32gTwNyMhmEpl4GnPd1wPRQUoP/szsNic5Lcx0UAY1aLZ0kqFZAXfKUsRAJsayi4UgG2yO/RINtjm1bD/VwWVvv2Ce/JZ2O1eJZmUwEG/qOxtMDDXFoAPO/7EP7aGSdzy4kweX0mSWDoHCdAxkvJqK2A0kKMvCiVet7fA0+69wiV3m+OwuP38sL9S4mwILCcipJ7FYGLfjdgcLJg2Uv8mYyQeazeTopUJ22VLDA7uA8uduXLC2AKDSEGX85llC7IebS7nQnIc4+/PsLAfGwFZur9sJjPsox7TXjWt19ZlM/fuxJl4Q9yaSimkySbCvBgzOmAH4Z1nWTE0IU20yynG9deE2ER/slHDEwzbhrww8AHlQvMxBuYAAY79PNQL/w3d0bYUzm4+Le1bgE+6tFJxrwO8lpW4Fa2DY67XXDC7VLgNNe68nBn5BBcq7dI9Q/698J8yGKVXdhRbws/6XPBVHwHzDbHyVgROO4wGPCYUYLffnsX6UgxFmESKIDBa1zs+3ezBD5uORn4cjzK4JdiUUFqsjGiCvAV8+G35df8W6JAnQcmkhFW/UnLpVTOg/mUFRhzGXDC41bgfBBMJSich821blHgG7eDVCkDp7b7hPF0yBIELryfE2Ds0K2/dyXZqMjYCpy3XKTFFLSQywgHcCZcek5MBkwmIC8uV4/XpwNecj3sNWGgqspegIeTVnNwGn4eBab795YVmG5qUGQQXlZg1GnAlXCdUOVCbu1bMFnnIQK3Myk2X+xIM8D5SJBBsPVsG0wDLsXerExgxDCENpMT374mwHeEjvG8fKZXw1fOGhjzuWG2JQGF1lInZlviQmcofNhRbS+AOed1Cm2W2y6P6aJ8eChNIdUEn+tvkPmjxgYCmLvcNwGBV6NBYXynvW1DgcNOhwA/5TfJdvD3bChAg4AbLTGh4qntltCFT2tqCFCWQDD+ACF48HVV0k5AO2U64IzpZAI32koHjuZywEsOJB3zlY4G6wQIwo/o1Qp8oKqKcdnFhMulzdSa+L9A6IYsQA4iexIOKnv9pemRYQzKp6zAj/UWucaO8AK3Min2W/DL8CB7En7n9wgCU8kYfOFxMnDXtm0KvCIBmsV8lvxUI5g+/fhgmycCPkHicM3aaZehWxJY6dxDcj1kafMHugT4/Med7IGDKaQScEgne68A5byywE/hWu3eUK/277ljGsILHSnSFQo/WP0azLU2acV0UvvfBTC/dXaQP7K04jGPrm1F4CWE7xqa/lrqzQAAAABJRU5ErkJggg=='

$script:Strings = @{
    'en' = @{
        title = 'Multiplayer · Terracotta'
        subtitle = 'Play with friends through a room code, no port forwarding'
        status_found = 'Terracotta found'
        status_missing = 'Terracotta is not installed yet'
        status_running = 'Terracotta is running'
        status_launching = 'Starting Terracotta, please wait...'
        status_stopping = 'Stopping multiplayer...'
        status_waiting_ui = 'Waiting for the Terracotta page...'
        status_downloading = 'Downloading Terracotta, please wait...'
        status_ready = 'Download finished, ready to start'
        status_failed = 'Download failed, check your connection and try again'
        btn_start = 'Start multiplayer'
        btn_stop = 'Stop multiplayer'
        btn_download = 'Download Terracotta'
        btn_folder = 'Open folder'
        tips = "1. Click Start multiplayer, then create a room or join one with a room code.`n2. In Minecraft open Multiplayer and double-click the Terracotta lobby.`n3. The host must open the world to LAN first, so friends can see it."
        embed_hint = 'The Terracotta page will appear here once it is running.'
        embed_failed = 'The page cannot be embedded here, so it was opened in your browser.'
        dl_failed = 'Could not download Terracotta. Check your connection and try again.'
        extract_failed = 'The downloaded package could not be unpacked (tar.exe is missing). Check your system and try again.'
        start_failed = 'Terracotta could not be started.'
    }
    'zh-CN' = @{
        title = '联机 · 陶瓦联机'
        subtitle = '用房间码和好友联机，不需要端口映射'
        status_found = '已找到陶瓦联机'
        status_missing = '尚未安装陶瓦联机'
        status_running = '陶瓦联机正在运行'
        status_launching = '正在启动陶瓦联机，请稍候……'
        status_stopping = '正在关闭联机……'
        status_waiting_ui = '正在等待陶瓦联机页面……'
        status_downloading = '正在下载陶瓦联机，请稍候……'
        status_ready = '下载完成，可以启动'
        status_failed = '下载失败，请检查网络后重试'
        btn_start = '启动联机'
        btn_stop = '关闭联机'
        btn_download = '下载陶瓦联机'
        btn_folder = '打开所在文件夹'
        tips = "1. 点「启动联机」，创建房间或输入房间码加入。`n2. 进游戏后打开「多人游戏」，双击「陶瓦联机大厅」。`n3. 房主先在游戏里「对局域网开放」，好友才能看到世界。"
        embed_hint = '启动后，陶瓦联机的页面会直接显示在这里。'
        embed_failed = '无法在窗口内显示页面，已改用默认浏览器打开。'
        dl_failed = '下载陶瓦联机失败，请检查网络连接后重试。'
        extract_failed = '下载的压缩包解压失败（缺少 tar.exe），请检查系统后重试。'
        start_failed = '启动陶瓦联机失败。'
    }
    'zh-TW' = @{
        title = '連線 · 陶瓦聯機'
        subtitle = '用房間碼和朋友連線，不需要連接埠轉送'
        status_found = '已找到陶瓦聯機'
        status_missing = '尚未安裝陶瓦聯機'
        status_running = '陶瓦聯機正在執行'
        status_launching = '正在啟動陶瓦聯機，請稍候……'
        status_stopping = '正在關閉連線……'
        status_waiting_ui = '正在等待陶瓦聯機頁面……'
        status_downloading = '正在下載陶瓦聯機，請稍候……'
        status_ready = '下載完成，可以啟動'
        status_failed = '下載失敗，請檢查網路後重試'
        btn_start = '啟動連線'
        btn_stop = '關閉連線'
        btn_download = '下載陶瓦聯機'
        btn_folder = '開啟所在資料夾'
        tips = "1. 點「啟動連線」，建立房間或輸入房間碼加入。`n2. 進入遊戲後開啟「多人遊戲」，雙擊「陶瓦聯機大廳」。`n3. 房主先在遊戲裡「對區域網路開放」，朋友才看得到世界。"
        embed_hint = '啟動後，陶瓦聯機的頁面會直接顯示在這裡。'
        embed_failed = '無法在視窗內顯示頁面，已改用預設瀏覽器開啟。'
        dl_failed = '下載陶瓦聯機失敗，請檢查網路連線後重試。'
        extract_failed = '下載的壓縮檔解壓失敗（缺少 tar.exe），請檢查系統後重試。'
        start_failed = '啟動陶瓦聯機失敗。'
    }
    'ja' = @{
        title = 'マルチプレイ · Terracotta'
        subtitle = 'ルームコードで友達と接続、ポート開放は不要'
        status_found = 'Terracotta が見つかりました'
        status_missing = 'Terracotta はまだ入っていません'
        status_running = 'Terracotta は実行中です'
        status_launching = 'Terracotta を起動しています……'
        status_stopping = 'マルチプレイを終了しています……'
        status_waiting_ui = 'Terracotta のページを待っています……'
        status_downloading = 'Terracotta をダウンロードしています……'
        status_ready = 'ダウンロード完了、起動できます'
        status_failed = 'ダウンロードに失敗しました。接続を確認してもう一度お試しください'
        btn_start = 'マルチプレイを開始'
        btn_stop = 'マルチプレイを終了'
        btn_download = 'Terracotta をダウンロード'
        btn_folder = 'フォルダーを開く'
        tips = "1. 「マルチプレイを開始」を押し、ルームを作るかルームコードで参加します。`n2. ゲームの「マルチプレイ」で「Terracotta ロビー」をダブルクリックします。`n3. ホストは先に「LAN に公開」すると、友達がワールドを見られます。"
        embed_hint = '起動すると、Terracotta のページがここに表示されます。'
        embed_failed = 'ページをウィンドウ内に表示できないため、既定のブラウザーで開きました。'
        dl_failed = 'Terracotta をダウンロードできませんでした。接続を確認して再試行してください。'
        extract_failed = 'ダウンロードしたパッケージを展開できませんでした（tar.exe がありません）。システムを確認して再試行してください。'
        start_failed = 'Terracotta を起動できませんでした。'
    }
    'ko' = @{
        title = '멀티플레이 · Terracotta'
        subtitle = '방 코드로 친구와 연결, 포트 포워딩 불필요'
        status_found = 'Terracotta를 찾았습니다'
        status_missing = 'Terracotta가 아직 설치되지 않았습니다'
        status_running = 'Terracotta가 실행 중입니다'
        status_launching = 'Terracotta를 시작하는 중입니다……'
        status_stopping = '멀티플레이를 종료하는 중입니다……'
        status_waiting_ui = 'Terracotta 페이지를 기다리는 중입니다……'
        status_downloading = 'Terracotta를 내려받는 중입니다……'
        status_ready = '다운로드 완료, 시작할 수 있습니다'
        status_failed = '다운로드 실패, 연결을 확인하고 다시 시도하세요'
        btn_start = '멀티플레이 시작'
        btn_stop = '멀티플레이 종료'
        btn_download = 'Terracotta 다운로드'
        btn_folder = '폴더 열기'
        tips = "1. 멀티플레이 시작을 누르고 방을 만들거나 방 코드로 참가합니다.`n2. 게임에서 멀티플레이를 열고 Terracotta 로비를 두 번 클릭합니다.`n3. 호스트가 먼저 LAN에 공개해야 친구가 월드를 볼 수 있습니다."
        embed_hint = '시작하면 Terracotta 페이지가 여기에 표시됩니다.'
        embed_failed = '페이지를 창에 표시할 수 없어 기본 브라우저로 열었습니다.'
        dl_failed = 'Terracotta를 내려받지 못했습니다. 연결을 확인하고 다시 시도해 주세요.'
        extract_failed = '받은 패키지를 풀지 못했습니다(tar.exe 없음). 시스템을 확인하고 다시 시도해 주세요.'
        start_failed = 'Terracotta를 시작하지 못했습니다.'
    }
    'fr' = @{
        title = 'Multijoueur · Terracotta'
        subtitle = 'Jouez avec vos amis via un code de salon, sans redirection de port'
        status_found = 'Terracotta est installé'
        status_missing = "Terracotta n'est pas encore installé"
        status_running = "Terracotta est en cours d'exécution"
        status_launching = 'Démarrage de Terracotta, patientez...'
        status_stopping = 'Arrêt du multijoueur...'
        status_waiting_ui = 'En attente de la page Terracotta...'
        status_downloading = 'Téléchargement de Terracotta, patientez...'
        status_ready = 'Téléchargement terminé, prêt à démarrer'
        status_failed = 'Échec du téléchargement, vérifiez la connexion et réessayez'
        btn_start = 'Démarrer le multijoueur'
        btn_stop = 'Arrêter le multijoueur'
        btn_download = 'Télécharger Terracotta'
        btn_folder = 'Ouvrir le dossier'
        tips = "1. Cliquez sur Démarrer le multijoueur, créez un salon ou rejoignez-en un avec un code.`n2. Dans Minecraft, ouvrez Multijoueur et double-cliquez sur le salon Terracotta.`n3. L hôte doit d abord ouvrir le monde au réseau local, sinon vos amis ne le verront pas."
        embed_hint = 'La page Terracotta apparaîtra ici une fois lancée.'
        embed_failed = "Impossible d'afficher la page ici ; elle a été ouverte dans votre navigateur."
        dl_failed = 'Impossible de télécharger Terracotta. Vérifiez votre connexion et réessayez.'
        extract_failed = "Le paquet téléchargé n'a pas pu être décompressé (tar.exe manquant). Vérifiez votre système et réessayez."
        start_failed = 'Impossible de démarrer Terracotta.'
    }
    'de' = @{
        title = 'Mehrspieler · Terracotta'
        subtitle = 'Mit Freunden über einen Raumcode spielen, ohne Portfreigabe'
        status_found = 'Terracotta gefunden'
        status_missing = 'Terracotta ist noch nicht installiert'
        status_running = 'Terracotta läuft'
        status_launching = 'Terracotta wird gestartet, bitte warten...'
        status_stopping = 'Mehrspieler wird beendet...'
        status_waiting_ui = 'Terracotta-Seite wird geladen...'
        status_downloading = 'Terracotta wird heruntergeladen, bitte warten...'
        status_ready = 'Download fertig, bereit zum Starten'
        status_failed = 'Download fehlgeschlagen, bitte Verbindung prüfen und erneut versuchen'
        btn_start = 'Mehrspieler starten'
        btn_stop = 'Mehrspieler beenden'
        btn_download = 'Terracotta herunterladen'
        btn_folder = 'Ordner öffnen'
        tips = "1. Auf Mehrspieler starten klicken, einen Raum erstellen oder mit Code beitreten.`n2. In Minecraft Mehrspieler öffnen und die Terracotta-Lobby doppelklicken.`n3. Der Gastgeber muss die Welt zuerst im LAN öffnen, sonst sehen Freunde sie nicht."
        embed_hint = 'Die Terracotta-Seite erscheint hier, sobald sie läuft.'
        embed_failed = 'Die Seite kann hier nicht eingebettet werden und wurde im Browser geöffnet.'
        dl_failed = 'Terracotta konnte nicht geladen werden. Prüfe die Verbindung und versuche es erneut.'
        extract_failed = 'Das Paket konnte nicht entpackt werden (tar.exe fehlt). Prüfe das System und versuche es erneut.'
        start_failed = 'Terracotta konnte nicht gestartet werden.'
    }
    'es' = @{
        title = 'Multijugador · Terracotta'
        subtitle = 'Juega con amigos con un código de sala, sin abrir puertos'
        status_found = 'Terracotta encontrado'
        status_missing = 'Terracotta aún no está instalado'
        status_running = 'Terracotta se está ejecutando'
        status_launching = 'Iniciando Terracotta, espera...'
        status_stopping = 'Cerrando el multijugador...'
        status_waiting_ui = 'Esperando la página de Terracotta...'
        status_downloading = 'Descargando Terracotta, espera...'
        status_ready = 'Descarga lista, se puede iniciar'
        status_failed = 'La descarga falló, comprueba la conexión y vuelve a intentarlo'
        btn_start = 'Iniciar multijugador'
        btn_stop = 'Cerrar multijugador'
        btn_download = 'Descargar Terracotta'
        btn_folder = 'Abrir carpeta'
        tips = "1. Pulsa Iniciar multijugador, crea una sala o únete con un código.`n2. En Minecraft abre Multijugador y haz doble clic en la sala de Terracotta.`n3. El anfitrión debe abrir antes el mundo en la red local, si no, nadie lo verá."
        embed_hint = 'La página de Terracotta aparecerá aquí al iniciarse.'
        embed_failed = 'No se pudo mostrar la página aquí; se abrió en el navegador.'
        dl_failed = 'No se pudo descargar Terracotta. Comprueba la conexión y vuelve a intentarlo.'
        extract_failed = 'No se pudo descomprimir el paquete (falta tar.exe). Comprueba el sistema y vuelve a intentarlo.'
        start_failed = 'No se pudo iniciar Terracotta.'
    }
    'pt-BR' = @{
        title = 'Multijogador · Terracotta'
        subtitle = 'Jogue com amigos por código de sala, sem liberar portas'
        status_found = 'Terracotta encontrado'
        status_missing = 'Terracotta ainda não está instalado'
        status_running = 'Terracotta está em execução'
        status_launching = 'Iniciando o Terracotta, aguarde...'
        status_stopping = 'Encerrando o multijogador...'
        status_waiting_ui = 'Aguardando a página do Terracotta...'
        status_downloading = 'Baixando o Terracotta, aguarde...'
        status_ready = 'Download concluído, pronto para iniciar'
        status_failed = 'Falha no download, verifique a conexão e tente novamente'
        btn_start = 'Iniciar multijogador'
        btn_stop = 'Encerrar multijogador'
        btn_download = 'Baixar Terracotta'
        btn_folder = 'Abrir pasta'
        tips = "1. Clique em Iniciar multijogador, crie uma sala ou entre com um código.`n2. No Minecraft abra Multijogador e clique duas vezes na sala do Terracotta.`n3. O anfitrião precisa abrir o mundo na rede local antes, senão ninguém o vê."
        embed_hint = 'A página do Terracotta aparecerá aqui quando estiver em execução.'
        embed_failed = 'Não foi possível exibir a página aqui; ela foi aberta no navegador.'
        dl_failed = 'Não foi possível baixar o Terracotta. Verifique a conexão e tente novamente.'
        extract_failed = 'Não foi possível extrair o pacote (falta o tar.exe). Verifique o sistema e tente novamente.'
        start_failed = 'Não foi possível iniciar o Terracotta.'
    }
    'ru' = @{
        title = 'Сетевая игра · Terracotta'
        subtitle = 'Играйте с друзьями по коду комнаты, без проброса портов'
        status_found = 'Terracotta найден'
        status_missing = 'Terracotta ещё не установлен'
        status_running = 'Terracotta уже запущен'
        status_launching = 'Запуск Terracotta, подождите...'
        status_stopping = 'Завершение сетевой игры...'
        status_waiting_ui = 'Ожидание страницы Terracotta...'
        status_downloading = 'Загрузка Terracotta, подождите...'
        status_ready = 'Загрузка завершена, можно запускать'
        status_failed = 'Не удалось скачать, проверьте подключение и повторите попытку'
        btn_start = 'Начать сетевую игру'
        btn_stop = 'Завершить сетевую игру'
        btn_download = 'Скачать Terracotta'
        btn_folder = 'Открыть папку'
        tips = "1. Нажмите Начать сетевую игру, создайте комнату или войдите по коду.`n2. В Minecraft откройте Сетевая игра и дважды щёлкните лобби Terracotta.`n3. Хозяин должен сначала открыть мир по локальной сети, иначе друзья его не увидят."
        embed_hint = 'Страница Terracotta появится здесь после запуска.'
        embed_failed = 'Не удалось показать страницу здесь; она открыта в браузере.'
        dl_failed = 'Не удалось скачать Terracotta. Проверьте подключение и повторите попытку.'
        extract_failed = 'Не удалось распаковать пакет (нет tar.exe). Проверьте систему и повторите попытку.'
        start_failed = 'Не удалось запустить Terracotta.'
    }
    'it' = @{
        title = 'Multigiocatore · Terracotta'
        subtitle = 'Gioca con gli amici tramite codice stanza, senza aprire porte'
        status_found = 'Terracotta trovato'
        status_missing = 'Terracotta non è ancora installato'
        status_running = 'Terracotta è in esecuzione'
        status_launching = 'Avvio di Terracotta in corso...'
        status_stopping = 'Chiusura del multigiocatore...'
        status_waiting_ui = 'In attesa della pagina Terracotta...'
        status_downloading = 'Download di Terracotta in corso...'
        status_ready = 'Download completato, pronto per avviare'
        status_failed = 'Download non riuscito, controlla la connessione e riprova'
        btn_start = 'Avvia multigiocatore'
        btn_stop = 'Chiudi multigiocatore'
        btn_download = 'Scarica Terracotta'
        btn_folder = 'Apri cartella'
        tips = "1. Premi Avvia multigiocatore, crea una stanza o entra con un codice.`n2. In Minecraft apri Multigiocatore e fai doppio clic sulla stanza Terracotta.`n3. L host deve prima aprire il mondo in LAN, altrimenti gli amici non lo vedono."
        embed_hint = 'La pagina di Terracotta apparirà qui una volta avviata.'
        embed_failed = 'Impossibile mostrare la pagina qui; è stata aperta nel browser.'
        dl_failed = 'Impossibile scaricare Terracotta. Controlla la connessione e riprova.'
        extract_failed = 'Impossibile estrarre il pacchetto (manca tar.exe). Controlla il sistema e riprova.'
        start_failed = 'Impossibile avviare Terracotta.'
    }
    'nl' = @{
        title = 'Multiplayer · Terracotta'
        subtitle = 'Speel met vrienden via een kamercode, zonder port forwarding'
        status_found = 'Terracotta gevonden'
        status_missing = 'Terracotta is nog niet geïnstalleerd'
        status_running = 'Terracotta draait'
        status_launching = 'Terracotta wordt gestart, even geduld...'
        status_stopping = 'Multiplayer wordt gestopt...'
        status_waiting_ui = 'Wachten op de Terracotta-pagina...'
        status_downloading = 'Terracotta wordt gedownload, even geduld...'
        status_ready = 'Download klaar, klaar om te starten'
        status_failed = 'Download mislukt, controleer de verbinding en probeer opnieuw'
        btn_start = 'Multiplayer starten'
        btn_stop = 'Multiplayer stoppen'
        btn_download = 'Terracotta downloaden'
        btn_folder = 'Map openen'
        tips = "1. Klik op Multiplayer starten, maak een kamer of join met een code.`n2. Open in Minecraft Multiplayer en dubbelklik op de Terracotta-lobby.`n3. De host moet de wereld eerst in het LAN openen, anders zien vrienden hem niet."
        embed_hint = 'De Terracotta-pagina verschijnt hier zodra die draait.'
        embed_failed = 'De pagina kan hier niet worden getoond en is in de browser geopend.'
        dl_failed = 'Kon Terracotta niet downloaden. Controleer de verbinding en probeer opnieuw.'
        extract_failed = 'Het pakket kon niet worden uitgepakt (tar.exe ontbreekt). Controleer het systeem en probeer opnieuw.'
        start_failed = 'Kon Terracotta niet starten.'
    }
    'pl' = @{
        title = 'Wieloosobowa · Terracotta'
        subtitle = 'Graj z przyjaciółmi przez kod pokoju, bez przekierowania portów'
        status_found = 'Znaleziono Terracotta'
        status_missing = 'Terracotta nie jest jeszcze zainstalowana'
        status_running = 'Terracotta jest uruchomiona'
        status_launching = 'Uruchamianie Terracotta, chwilę...'
        status_stopping = 'Zamykanie gry wieloosobowej...'
        status_waiting_ui = 'Oczekiwanie na stronę Terracotta...'
        status_downloading = 'Pobieranie Terracotta, chwilę...'
        status_ready = 'Pobrano, można uruchomić'
        status_failed = 'Pobieranie nie powiodło się, sprawdź połączenie i spróbuj ponownie'
        btn_start = 'Uruchom grę wieloosobową'
        btn_stop = 'Zamknij grę wieloosobową'
        btn_download = 'Pobierz Terracotta'
        btn_folder = 'Otwórz folder'
        tips = "1. Kliknij Uruchom grę wieloosobową, utwórz pokój lub dołącz kodem.`n2. W Minecraft otwórz Wieloosobowa i dwukrotnie kliknij lobby Terracotta.`n3. Gospodarz musi najpierw udostępnić świat w sieci lokalnej, inaczej znajomi go nie zobaczą."
        embed_hint = 'Strona Terracotta pojawi się tutaj po uruchomieniu.'
        embed_failed = 'Nie można tu pokazać strony; otwarto ją w przeglądarce.'
        dl_failed = 'Nie udało się pobrać Terracotta. Sprawdź połączenie i spróbuj ponownie.'
        extract_failed = 'Nie udało się rozpakować paczki (brak tar.exe). Sprawdź system i spróbuj ponownie.'
        start_failed = 'Nie udało się uruchomić Terracotta.'
    }
    'tr' = @{
        title = 'Çok oyunculu · Terracotta'
        subtitle = 'Oda kodu ile arkadaşlarınızla oynayın, port yönlendirme gerekmez'
        status_found = 'Terracotta bulundu'
        status_missing = 'Terracotta henüz kurulu değil'
        status_running = 'Terracotta çalışıyor'
        status_launching = 'Terracotta başlatılıyor, lütfen bekleyin...'
        status_stopping = 'Çok oyunculu kapatılıyor...'
        status_waiting_ui = 'Terracotta sayfası bekleniyor...'
        status_downloading = 'Terracotta indiriliyor, lütfen bekleyin...'
        status_ready = 'İndirme bitti, başlatılabilir'
        status_failed = 'İndirme başarısız, bağlantıyı kontrol edip yeniden deneyin'
        btn_start = 'Çok oyunculu başlat'
        btn_stop = 'Çok oyunculuyu kapat'
        btn_download = 'Terracotta indir'
        btn_folder = 'Klasörü aç'
        tips = "1. Çok oyunculu başlat a basın, oda oluşturun veya kodla katılın.`n2. Minecraft ta Çok Oyunculu yu açın ve Terracotta lobisine çift tıklayın.`n3. Sunucu önce dünyayı yerel ağa açmalı, yoksa arkadaşlar göremez."
        embed_hint = 'Terracotta sayfası çalışmaya başlayınca burada görünecek.'
        embed_failed = 'Sayfa burada gösterilemedi; tarayıcınızda açıldı.'
        dl_failed = 'Terracotta indirilemedi. Bağlantınızı kontrol edip yeniden deneyin.'
        extract_failed = 'Paket açılamadı (tar.exe yok). Sisteminizi kontrol edip yeniden deneyin.'
        start_failed = 'Terracotta başlatılamadı.'
    }
    'vi' = @{
        title = 'Nhiều người · Terracotta'
        subtitle = 'Chơi cùng bạn bè bằng mã phòng, không cần mở cổng'
        status_found = 'Đã tìm thấy Terracotta'
        status_missing = 'Terracotta chưa được cài đặt'
        status_running = 'Terracotta đang chạy'
        status_launching = 'Đang khởi động Terracotta, vui lòng chờ...'
        status_stopping = 'Đang đóng chế độ nhiều người...'
        status_waiting_ui = 'Đang chờ trang Terracotta...'
        status_downloading = 'Đang tải Terracotta, vui lòng chờ...'
        status_ready = 'Tải xong, có thể khởi động'
        status_failed = 'Tải thất bại, hãy kiểm tra kết nối và thử lại'
        btn_start = 'Bắt đầu nhiều người'
        btn_stop = 'Đóng nhiều người'
        btn_download = 'Tải Terracotta'
        btn_folder = 'Mở thư mục'
        tips = "1. Nhấn Bắt đầu nhiều người, tạo phòng hoặc vào bằng mã phòng.`n2. Trong Minecraft mở Nhiều người rồi nhấp đúp vào sảnh Terracotta.`n3. Chủ phòng phải mở thế giới sang mạng LAN trước, nếu không bạn bè sẽ không thấy."
        embed_hint = 'Trang Terracotta sẽ hiển thị ở đây sau khi khởi động.'
        embed_failed = 'Không thể hiển thị trang tại đây; đã mở bằng trình duyệt mặc định.'
        dl_failed = 'Không tải được Terracotta. Hãy kiểm tra kết nối và thử lại.'
        extract_failed = 'Không giải nén được gói (thiếu tar.exe). Hãy kiểm tra hệ thống và thử lại.'
        start_failed = 'Không khởi động được Terracotta.'
    }
}

function Get-UiLanguage {
    $code = ''
    $langFile = Join-Path $script:BaseDir 'CommandManager.lang'
    if (Test-Path -LiteralPath $langFile) {
        try { $code = ([IO.File]::ReadAllText($langFile, [Text.Encoding]::UTF8)).Trim().Trim([char]0xFEFF).Trim() } catch { }
    }
    if (-not $code) { $code = [System.Globalization.CultureInfo]::CurrentUICulture.Name }
    $code = $code.Replace('_', '-')
    if ($script:Strings.ContainsKey($code)) { return $code }
    if ($code -match '^zh-(tw|hk|mo)') { return 'zh-TW' }
    if ($code -match '^zh') { return 'zh-CN' }
    if ($code -match '^pt') { return 'pt-BR' }
    foreach ($c in @('en', 'ja', 'ko', 'fr', 'de', 'es', 'ru', 'it', 'nl', 'pl', 'tr', 'vi')) {
        if ($code -ieq $c -or $code -like ($c + '-*')) { return $c }
    }
    return 'en'
}
$script:Lang = Get-UiLanguage

function T([string]$key) {
    $t = $script:Strings[$script:Lang]
    if ($t -and $t.ContainsKey($key)) { return [string]$t[$key] }
    return [string]$script:Strings['en'][$key]
}

# ==== finding Terracotta ====
# HMCL keeps its extracted copy under %USERPROFILE%\.hmcl\dependencies, the
# standalone package is usually installed per user, and our own download goes
# to <PCL>\Online.  The newest matching executable wins.
function Find-Terracotta {
    $dirs = New-Object System.Collections.Generic.List[string]
    $dirs.Add($script:OnlineDir)
    $bases = @(
        (Join-Path $env:USERPROFILE '.hmcl\dependencies\terracotta'),
        (Join-Path $env:APPDATA '.hmcl\dependencies\terracotta'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Terracotta'),
        (Join-Path $env:LOCALAPPDATA 'Terracotta'))
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root) { $bases += (Join-Path $root 'Terracotta') }
    }
    foreach ($d in $bases) {
        if ($d) { $dirs.Add($d) }
    }
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $f = @(Get-ChildItem -LiteralPath $d -Filter 'terracotta*.exe' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($f.Count -gt 0) { return $f[0].FullName }
    }
    return ''
}

function Get-TerracottaProcesses {
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'terracotta*' })
}

function Get-TerracottaProcess {
    $list = Get-TerracottaProcesses
    if ($list.Count -gt 0) { return $list[0] }
    return $null
}

# Terracotta serves its web UI and API on a random loopback port.  It records
# the port as two big endian bytes in %TEMP%\terracotta\terracotta.lock; the
# file stays open for writing, so it must be opened with FileShare.ReadWrite.
# /meta proves that the candidate port really belongs to Terracotta.
function Test-TerracottaMeta([int]$port) {
    if ($port -le 0) { return $false }
    try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri ('http://127.0.0.1:' + $port + '/meta')
        return ([int]$r.StatusCode -eq 200 -and ([string]$r.Content).Contains('"version"'))
    } catch {
        return $false
    }
}

function Get-TerracottaPort {
    $lock = Join-Path $env:TEMP 'terracotta\terracotta.lock'
    if (Test-Path -LiteralPath $lock) {
        for ($try = 0; $try -lt 2; $try++) {
            $read = 0
            $buf = New-Object byte[] 2
            try {
                $fs = [IO.File]::Open($lock, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                try { $read = $fs.Read($buf, 0, 2) } finally { $fs.Dispose() }
            } catch { $read = 0 }
            if ($read -eq 2) {
                $candidate = ([int]$buf[0] * 256) + [int]$buf[1]
                if ($candidate -gt 1024 -and $candidate -lt 65536 -and (Test-TerracottaMeta $candidate)) {
                    return $candidate
                }
            }
        }
    }
    $proc = Get-TerracottaProcess
    if ($proc) {
        try {
            foreach ($conn in @(Get-NetTCPConnection -OwningProcess $proc.Id -State Listen -ErrorAction SilentlyContinue)) {
                $p = [int]$conn.LocalPort
                if ($p -eq 13448) { continue }
                if (Test-TerracottaMeta $p) { return $p }
            }
        } catch { }
    }
    return 0
}

# Asks the local API for a peaceful shutdown, then removes any process that
# is still alive after a short grace period.
function Stop-TerracottaCore {
    $port = Get-TerracottaPort
    $asked = $false
    if ($port -gt 0) {
        try {
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri ('http://127.0.0.1:' + $port + '/panic?peaceful=true') | Out-Null
            $asked = $true
        } catch { }
    }
    if ($asked) {
        for ($i = 0; $i -lt 24; $i++) {
            if (-not (Get-TerracottaProcess)) { break }
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 250
        }
    }
    foreach ($p in (Get-TerracottaProcesses)) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
    }
    return (-not [bool](Get-TerracottaProcess))
}

function Get-TerracottaAsset {
    $arch = 'x86_64'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    $headers = @{ 'User-Agent' = 'PCL-Homepage-Online' }
    try {
        $rel = Invoke-RestMethod -UseBasicParsing -TimeoutSec 30 -Headers $headers -Uri 'https://api.github.com/repos/burningtnt/Terracotta/releases/latest'
        $script:DlTag = [string]$rel.tag_name
        $asset = @($rel.assets | Where-Object { $_.name -like ('*windows-' + $arch + '-pkg.tar.gz') })
        if ($asset.Count -gt 0) {
            $script:DlAsset = $asset[0]
            return $asset[0]
        }
    } catch { }
    return $null
}

# ==== downloading Terracotta ====
function Set-Status([string]$text) {
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = $text
        [Windows.Forms.Application]::DoEvents()
    }
}

function Get-DownloadFile([string]$url, [string]$dest) {
    try {
        $headers = @{ 'User-Agent' = 'PCL-Homepage-Online' }
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 240 -Headers $headers -Uri $url -OutFile $dest
        return ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 1048576))
    } catch {
        return $false
    }
}

function Remove-DownloadFile([string]$path) {
    try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch { }
}

function Expand-TerracottaPackage([string]$pkg) {
    # The package holds one executable plus VCRUNTIME140.DLL.  Windows 10 and
    # later ship bsdtar, so no extra tool is needed.
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tar)) { return $false }
    try {
        & $tar -xzf $pkg -C $script:OnlineDir
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

# Downloads and unpacks the newest official Windows package into
# <PCL>\Online and returns the executable path ('' on failure).  The Gitee
# mirror is tried when GitHub does not answer.  UI independent, so it can also
# run from the offline tests.
function Install-Terracotta {
    $script:InstallStage = 'download'
    $asset = Get-TerracottaAsset
    if (-not $asset) {
        Set-Status (T 'status_failed')
        return ''
    }
    Set-Status (T 'status_downloading')
    [void][IO.Directory]::CreateDirectory($script:OnlineDir)
    $pkg = Join-Path $script:OnlineDir 'terracotta.pkg.tar.gz'
    $urls = @([string]$asset.browser_download_url)
    if ($script:DlTag) {
        $urls += ('https://gitee.com/burningtnt/Terracotta/releases/download/' + $script:DlTag + '/' + [string]$asset.name)
    }
    $got = $false
    foreach ($u in $urls) {
        if (Get-DownloadFile $u $pkg) { $got = $true; break }
    }
    if (-not $got) {
        Remove-DownloadFile $pkg
        Set-Status (T 'status_failed')
        return ''
    }
    $script:InstallStage = 'extract'
    if (-not (Expand-TerracottaPackage $pkg)) {
        Remove-DownloadFile $pkg
        Set-Status (T 'status_failed')
        return ''
    }
    Remove-DownloadFile $pkg
    $exe = Find-Terracotta
    if ($exe) { Set-Status (T 'status_ready') }
    return $exe
}

function Start-Terracotta([string]$path) {
    if (-not $path) { return $false }
    if ($env:PCLTOOLS_ONLINE_NO_START) { return $true }
    try {
        $dir = Split-Path -Parent $path
        Start-Process -FilePath $path -WorkingDirectory $dir | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Test-WebView2Files {
    foreach ($f in @('Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll', 'WebView2Loader.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $script:WebView2Dir $f))) { return $false }
    }
    return $true
}

# Offline test hook: print what the window would show, without opening it.
#   PCLTOOLS_ONLINE_TEST=1         detection, language and embedded page info
#   PCLTOOLS_ONLINE_TEST=download  also download and unpack into <base>\Online
#   PCLTOOLS_ONLINE_TEST=stop      gracefully stop the running Terracotta
# PCLTOOLS_ONLINE_NO_START=1 keeps the tests from starting the program.
if ($env:PCLTOOLS_ONLINE_TEST) {
    [Console]::Out.WriteLine('DIR=' + $script:OnlineDir)
    [Console]::Out.WriteLine('EXE=' + (Find-Terracotta))
    [Console]::Out.WriteLine('RUN=' + [string][bool](Get-TerracottaProcess))
    [Console]::Out.WriteLine('LANG=' + $script:Lang)
    [Console]::Out.WriteLine('TITLE=' + (T 'title'))
    [Console]::Out.WriteLine('WEBVIEW=' + [string](Test-WebView2Files))
    $testPort = Get-TerracottaPort
    [Console]::Out.WriteLine('PORT=' + $testPort)
    if ($testPort -gt 0) {
        [Console]::Out.WriteLine('URL=http://127.0.0.1:' + $testPort + '/')
    } else {
        [Console]::Out.WriteLine('URL=')
    }
    if ($env:PCLTOOLS_ONLINE_TEST -eq 'download') {
        [Console]::Out.WriteLine('INSTALLED=' + (Install-Terracotta))
        [Console]::Out.WriteLine('INSTALLSTAGE=' + $script:InstallStage)
        [Console]::Out.WriteLine('EXE2=' + (Find-Terracotta))
    }
    if ($env:PCLTOOLS_ONLINE_TEST -eq 'stop') {
        [Console]::Out.WriteLine('STOPPED=' + [string](Stop-TerracottaCore))
    }
    exit 0
}

# ==== window icon ====
# The taskbar and title bar use Terracotta's own icon.  The program is not
# always installed yet, so a copy of the same 32x32 icon is embedded above.
function Set-WindowIcon {
    $exe = Find-Terracotta
    if ($exe) {
        try {
            $script:Form.Icon = [Drawing.Icon]::ExtractAssociatedIcon($exe)
            return
        } catch { }
    }
    try {
        $bytes = [Convert]::FromBase64String($script:IconPng)
        $ms = New-Object IO.MemoryStream
        $ms.Write($bytes, 0, $bytes.Length)
        $ms.Position = 0
        $script:IconBitmap = [Drawing.Image]::FromStream($ms)
        $ms.Dispose()
        $script:Form.Icon = [Drawing.Icon]::FromHandle($script:IconBitmap.GetHicon())
    } catch {
        try { $script:Form.Icon = [Drawing.SystemIcons]::Application } catch { }
    }
}

# ==== UI ====
[Windows.Forms.Application]::EnableVisualStyles()
$script:Form = New-Object Windows.Forms.Form
$script:Form.Text = T 'title'
$script:Form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
$script:Form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::Sizable
$script:Form.MaximizeBox = $true
$script:Form.MinimizeBox = $true
$script:Form.ClientSize = New-Object Drawing.Size(980, 760)
$script:Form.MinimumSize = New-Object Drawing.Size(820, 640)
try { $script:Form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9) } catch { }
$script:Form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
Set-WindowIcon

$header = New-Object Windows.Forms.Label
$header.Text = T 'title'
$header.Font = New-Object Drawing.Font('Microsoft YaHei UI', 15, [Drawing.FontStyle]::Bold)
$header.AutoSize = $true
$header.Location = New-Object Drawing.Point(20, 14)
$script:Form.Controls.Add($header)

$subtitle = New-Object Windows.Forms.Label
$subtitle.Text = T 'subtitle'
$subtitle.ForeColor = [Drawing.Color]::FromArgb(90, 90, 90)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object Drawing.Point(21, 46)
$script:Form.Controls.Add($subtitle)

$panel = New-Object Windows.Forms.Panel
$panel.Location = New-Object Drawing.Point(20, 74)
$panel.Size = New-Object Drawing.Size(900, 56)
$panel.Anchor = ([Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right)
$panel.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
$panel.BackColor = [Drawing.Color]::FromArgb(248, 248, 248)
$script:Form.Controls.Add($panel)

$script:StatusLabel = New-Object Windows.Forms.Label
$script:StatusLabel.Text = ''
$script:StatusLabel.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10, [Drawing.FontStyle]::Bold)
$script:StatusLabel.AutoSize = $true
$script:StatusLabel.Location = New-Object Drawing.Point(10, 8)
$panel.Controls.Add($script:StatusLabel)

$script:PathLabel = New-Object Windows.Forms.Label
$script:PathLabel.Text = ''
$script:PathLabel.ForeColor = [Drawing.Color]::FromArgb(110, 110, 110)
$script:PathLabel.AutoSize = $false
$script:PathLabel.AutoEllipsis = $true
$script:PathLabel.Location = New-Object Drawing.Point(11, 31)
$script:PathLabel.Size = New-Object Drawing.Size(876, 16)
$script:PathLabel.Anchor = ([Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right)
$panel.Controls.Add($script:PathLabel)

function New-ActionButton([string]$text, [int]$x, [int]$w) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object Drawing.Point($x, 142)
    $b.Size = New-Object Drawing.Size($w, 34)
    $b.UseVisualStyleBackColor = $true
    $b.FlatStyle = [Windows.Forms.FlatStyle]::System
    return $b
}

$script:Primary = New-ActionButton (T 'btn_start') 20 190
$script:Form.Controls.Add($script:Primary)

$script:Stop = New-ActionButton (T 'btn_stop') 222 160
$script:Stop.Enabled = $false
$script:Form.Controls.Add($script:Stop)

$folder = New-ActionButton (T 'btn_folder') 394 190
$script:Form.Controls.Add($folder)

# The web host holds either the hint placeholder or the embedded Terracotta
# page.  Keeping a fixed border around WebView2 makes it look like a panel.
$script:WebHost = New-Object Windows.Forms.Panel
$script:WebHost.Location = New-Object Drawing.Point(20, 188)
$script:WebHost.Size = New-Object Drawing.Size(900, 512)
$script:WebHost.Anchor = ([Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Bottom -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right)
$script:WebHost.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
$script:WebHost.BackColor = [Drawing.Color]::FromArgb(250, 250, 250)
$script:Form.Controls.Add($script:WebHost)

$script:Placeholder = New-Object Windows.Forms.Panel
$script:Placeholder.Dock = [Windows.Forms.DockStyle]::Fill
$script:Placeholder.BackColor = [Drawing.Color]::FromArgb(250, 250, 250)
$script:WebHost.Controls.Add($script:Placeholder)

$script:Tips = New-Object Windows.Forms.Label
$script:Tips.Text = T 'tips'
$script:Tips.AutoSize = $false
$script:Tips.Location = New-Object Drawing.Point(24, 60)
$script:Tips.Size = New-Object Drawing.Size(852, 92)
$script:Placeholder.Controls.Add($script:Tips)

$script:EmbedHint = New-Object Windows.Forms.Label
$script:EmbedHint.Text = T 'embed_hint'
$script:EmbedHint.AutoSize = $false
$script:EmbedHint.ForeColor = [Drawing.Color]::FromArgb(120, 120, 120)
$script:EmbedHint.Location = New-Object Drawing.Point(24, 158)
$script:EmbedHint.Size = New-Object Drawing.Size(852, 24)
$script:Placeholder.Controls.Add($script:EmbedHint)

$script:Placeholder.Add_Resize({
    $w = [Math]::Max(200, $script:Placeholder.Width - 48)
    $script:Tips.Left = 24
    $script:Tips.Width = $w
    $script:Tips.Top = [Math]::Max(32, [int](($script:Placeholder.Height - 150) / 2))
    $script:EmbedHint.Left = 24
    $script:EmbedHint.Width = $w
    $script:EmbedHint.Top = $script:Tips.Top + 102
})

$script:PageUrl = ''
$script:EmbedState = 'none'
$script:Busy = $false
$script:Wv = $null
$script:EnvTask = $null
$script:InitTask = $null

function Set-EmbedFailed([string]$reason) {
    if ($script:EmbedState -eq 'failed') { return }
    $script:EmbedState = 'failed'
    try { if ($script:InitTimer) { $script:InitTimer.Stop() } } catch { }
    try {
        if ($script:Wv) { $script:Wv.Visible = $false }
        $script:Placeholder.Visible = $true
        $script:Placeholder.BringToFront()
        $script:EmbedHint.Text = T 'embed_failed'
        $script:EmbedHint.ForeColor = [Drawing.Color]::FromArgb(165, 80, 55)
    } catch { }
}

function Initialize-WebView {
    if ($script:EmbedState -ne 'none') { return }
    if (-not (Test-WebView2Files)) {
        Set-EmbedFailed 'files'
        return
    }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PCLHomeOnlineWebViewNative {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetDllDirectory(string path);
}
'@
        [void][PCLHomeOnlineWebViewNative]::SetDllDirectory($script:WebView2Dir)
        [void][Reflection.Assembly]::LoadFrom((Join-Path $script:WebView2Dir 'Microsoft.Web.WebView2.Core.dll'))
        [void][Reflection.Assembly]::LoadFrom((Join-Path $script:WebView2Dir 'Microsoft.Web.WebView2.WinForms.dll'))
        $wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $wv.Dock = [Windows.Forms.DockStyle]::Fill
        $wv.Visible = $false
        try { $wv.DefaultBackgroundColor = [Drawing.Color]::FromArgb(22, 33, 62) } catch { }
        $script:WebHost.Controls.Add($wv)
        $wv.BringToFront()
        $script:Wv = $wv
        $udf = Join-Path $script:OnlineDir 'WebView2Data'
        [void][IO.Directory]::CreateDirectory($udf)
        $script:EnvTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $udf, $null)
        $script:EmbedState = 'loading'
    } catch {
        Set-EmbedFailed 'load'
    }
}

function Reset-Embed {
    $script:PageUrl = ''
    if ($script:Wv) {
        try { $script:Wv.Visible = $false } catch { }
        try {
            if ($script:Wv.CoreWebView2) { $script:Wv.CoreWebView2.Navigate('about:blank') }
        } catch { }
    }
    try {
        $script:Placeholder.Visible = $true
        $script:Placeholder.BringToFront()
    } catch { }
}

function Update-Embed {
    if ($script:EmbedState -eq 'failed') {
        $proc = Get-TerracottaProcess
        if ($proc) {
            $port = Get-TerracottaPort
            if ($port -gt 0) {
                $url = 'http://127.0.0.1:' + $port + '/'
                if ($script:PageUrl -ne $url) {
                    $script:PageUrl = $url
                    
                }
            }
        }
        return
    }
    if ($script:EmbedState -ne 'ready') { return }
    $proc = Get-TerracottaProcess
    if (-not $proc) {
        if ($script:PageUrl) { Reset-Embed }
        return
    }
    $port = Get-TerracottaPort
    if ($port -le 0) { return }
    $url = 'http://127.0.0.1:' + $port + '/'
    if ($script:PageUrl -eq $url -and $script:Wv -and $script:Wv.Visible) { return }
    try {
        $script:Wv.Source = [Uri]$url
        $script:Wv.Visible = $true
        $script:Placeholder.Visible = $false
        $script:PageUrl = $url
        if ($script:StatusLabel) { $script:StatusLabel.Text = T 'status_running' }
    } catch { }
}

function Update-Ui {
    if ($script:Busy) { return }
    $proc = Get-TerracottaProcess
    if ($proc) {
        $script:Primary.Enabled = $false
        $script:Primary.Text = T 'btn_start'
        $script:Stop.Enabled = $true
        $path = ''
        try { $path = [string]$proc.Path } catch { }
        $script:PathLabel.Text = $path
        if ($script:PageUrl) {
            $script:StatusLabel.Text = T 'status_running'
        } else {
            $script:StatusLabel.Text = T 'status_waiting_ui'
        }
        return
    }
    $script:Primary.Enabled = $true
    $script:Stop.Enabled = $false
    $script:ExePath = Find-Terracotta
    if ($script:ExePath) {
        $script:StatusLabel.Text = T 'status_found'
        $script:PathLabel.Text = $script:ExePath
        $script:Primary.Text = T 'btn_start'
    } else {
        $script:StatusLabel.Text = T 'status_missing'
        $script:PathLabel.Text = $script:OnlineDir
        $script:Primary.Text = T 'btn_download'
    }
}

function Start-Online {
    if ($script:Busy) { return }
    $script:Busy = $true
    try {
        $exe = $script:ExePath
        if (-not $exe) { $exe = Find-Terracotta }
        if (-not $exe) {
            $exe = Install-Terracotta
            if (-not $exe) {
                $msg = T 'dl_failed'
                if ($script:InstallStage -eq 'extract') { $msg = T 'extract_failed' }
                [void][Windows.Forms.MessageBox]::Show($msg, (T 'title'), [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            Set-WindowIcon
        }
        Set-Status (T 'status_launching')
        if (-not (Start-Terracotta $exe)) {
            [void][Windows.Forms.MessageBox]::Show((T 'start_failed'), (T 'title'), [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
        }
    } finally {
        $script:Busy = $false
        Update-Ui
    }
}

function Stop-Online {
    if ($script:Busy) { return }
    $script:Busy = $true
    try {
        Set-Status (T 'status_stopping')
        [void](Stop-TerracottaCore)
        Reset-Embed
    } finally {
        $script:Busy = $false
        Update-Ui
    }
}

$script:Primary.Add_Click({ Start-Online })
$script:Stop.Add_Click({ Stop-Online })

$folder.Add_Click({
    try {
        $exe = Find-Terracotta
        if ($exe) {
            Start-Process 'explorer.exe' -ArgumentList ('/select,"' + $exe + '"') | Out-Null
        } else {
            [void][IO.Directory]::CreateDirectory($script:OnlineDir)
            Start-Process 'explorer.exe' -ArgumentList ('"' + $script:OnlineDir + '"') | Out-Null
        }
    } catch { }
})

# Polls the WebView2 initialization tasks.  PowerShell 5.1 cannot bind the
# ContinueWith overload with a script block, so a WinForms timer polls them.
$script:InitTimer = New-Object Windows.Forms.Timer
$script:InitTimer.Interval = 250
$script:InitTimer.Add_Tick({
    if ($script:EmbedState -ne 'loading') {
        $script:InitTimer.Stop()
        return
    }
    try {
        if ($script:EnvTask -and $script:EnvTask.IsFaulted) {
            Set-EmbedFailed 'env'
            return
        }
        if ($script:EnvTask -and $script:EnvTask.IsCompleted -and -not $script:InitTask) {
            $script:InitTask = $script:Wv.EnsureCoreWebView2Async($script:EnvTask.Result)
            return
        }
        if ($script:InitTask -and $script:InitTask.IsFaulted) {
            Set-EmbedFailed 'core'
            return
        }
        if ($script:InitTask -and $script:InitTask.IsCompleted -and $script:Wv.CoreWebView2) {
            $script:EmbedState = 'ready'
            $script:InitTimer.Stop()
            Update-Embed
            Update-Ui
        }
    } catch {
        Set-EmbedFailed 'poll'
    }
})

$script:UiTimer = New-Object Windows.Forms.Timer
$script:UiTimer.Interval = 1200
$script:UiTimer.Add_Tick({
    Update-Embed
    Update-Ui
})

$script:Form.Add_Shown({
    if (-not (Test-WebView2Files)) {
        Set-EmbedFailed 'files'
    } else {
        Initialize-WebView
        $script:InitTimer.Start()
    }
    $script:UiTimer.Start()
    Update-Embed
    Update-Ui
})

$script:Form.Add_FormClosed({
    try { $script:UiTimer.Stop() } catch { }
    try { $script:InitTimer.Stop() } catch { }
    try { if ($script:Wv) { $script:Wv.Dispose() } } catch { }
})

Update-Ui
[void]$script:Form.ShowDialog()