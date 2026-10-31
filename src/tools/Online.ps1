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
# Gitee mirror as a fallback).  A credit line is shown in the window.
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
$script:ReleasePage = 'https://github.com/burningtnt/Terracotta/releases/latest'
$script:ExePath = ''
$script:DlAsset = $null
$script:DlTag = ''

$script:Strings = @{
    'en' = @{
        title = 'Multiplayer · Terracotta'
        subtitle = 'Play with friends through a room code, no port forwarding'
        status_found = 'Terracotta found'
        status_missing = 'Terracotta is not installed yet'
        status_running = 'Terracotta is running'
        status_downloading = 'Downloading Terracotta, please wait...'
        status_ready = 'Download finished, ready to start'
        status_failed = 'Download failed, use the release page instead'
        status_launched = 'Terracotta started'
        btn_start = 'Start multiplayer'
        btn_show = 'Show window'
        btn_download = 'Download Terracotta'
        btn_release = 'Open release page'
        btn_folder = 'Open folder'
        btn_close = 'Close'
        tips = "1. Click Start multiplayer, then create a room or join one with a room code.`n2. In Minecraft open Multiplayer and double-click the Terracotta lobby.`n3. The host must open the world to LAN first, so friends can see it."
        credit = 'Terracotta by burningtnt, licensed under AGPL-3.0.'
        note = 'Downloaded from the official GitHub release (about 8 MB); the release page and the Gitee mirror work too.'
        dl_failed = 'Could not download Terracotta. Open the release page and download the Windows package by hand.'
        extract_failed = 'The downloaded package could not be unpacked (tar.exe is missing). Open the release page and install it by hand.'
        start_failed = 'Terracotta could not be started.'
    }
    'zh-CN' = @{
        title = '联机 · 陶瓦联机'
        subtitle = '用房间码和好友联机，不需要端口映射'
        status_found = '已找到陶瓦联机'
        status_missing = '尚未安装陶瓦联机'
        status_running = '陶瓦联机正在运行'
        status_downloading = '正在下载陶瓦联机，请稍候……'
        status_ready = '下载完成，可以启动'
        status_failed = '下载失败，请改用发布页手动下载'
        status_launched = '已启动陶瓦联机'
        btn_start = '启动联机'
        btn_show = '显示窗口'
        btn_download = '下载陶瓦联机'
        btn_release = '打开发布页'
        btn_folder = '打开所在文件夹'
        btn_close = '关闭'
        tips = "1. 点「启动联机」，创建房间或输入房间码加入。`n2. 进游戏后打开「多人游戏」，双击「陶瓦联机大厅」。`n3. 房主先在游戏里「对局域网开放」，好友才能看到世界。"
        credit = '陶瓦联机 Terracotta 由 burningtnt 开发，AGPL-3.0 许可。'
        note = '从 GitHub 官方 Release 下载（约 8 MB），发布页和 Gitee 镜像也可用。'
        dl_failed = '下载陶瓦联机失败。请打开官方发布页手动下载 Windows 版本。'
        extract_failed = '下载的压缩包解压失败（缺少 tar.exe）。请打开发布页手动安装。'
        start_failed = '启动陶瓦联机失败。'
    }
    'zh-TW' = @{
        title = '連線 · 陶瓦聯機'
        subtitle = '用房間碼和朋友連線，不需要連接埠轉送'
        status_found = '已找到陶瓦聯機'
        status_missing = '尚未安裝陶瓦聯機'
        status_running = '陶瓦聯機正在執行'
        status_downloading = '正在下載陶瓦聯機，請稍候……'
        status_ready = '下載完成，可以啟動'
        status_failed = '下載失敗，請改用發布頁手動下載'
        status_launched = '已啟動陶瓦聯機'
        btn_start = '啟動連線'
        btn_show = '顯示視窗'
        btn_download = '下載陶瓦聯機'
        btn_release = '開啟發布頁'
        btn_folder = '開啟所在資料夾'
        btn_close = '關閉'
        tips = "1. 點「啟動連線」，建立房間或輸入房間碼加入。`n2. 進入遊戲後開啟「多人遊戲」，雙擊「陶瓦聯機大廳」。`n3. 房主先在遊戲裡「對區域網路開放」，朋友才看得到世界。"
        credit = '陶瓦聯機 Terracotta 由 burningtnt 開發，AGPL-3.0 授權。'
        note = '從 GitHub 官方 Release 下載（約 8 MB），發布頁與 Gitee 鏡像也可用。'
        dl_failed = '下載陶瓦聯機失敗。請開啟官方發布頁手動下載 Windows 版本。'
        extract_failed = '下載的壓縮檔解壓失敗（缺少 tar.exe）。請開啟發布頁手動安裝。'
        start_failed = '啟動陶瓦聯機失敗。'
    }
    'ja' = @{
        title = 'マルチプレイ · Terracotta'
        subtitle = 'ルームコードで友達と接続、ポート開放は不要'
        status_found = 'Terracotta が見つかりました'
        status_missing = 'Terracotta はまだ入っていません'
        status_running = 'Terracotta は実行中です'
        status_downloading = 'Terracotta をダウンロードしています……'
        status_ready = 'ダウンロード完了、起動できます'
        status_failed = 'ダウンロードに失敗しました。配布ページをお使いください'
        status_launched = 'Terracotta を起動しました'
        btn_start = 'マルチプレイを開始'
        btn_show = 'ウィンドウを表示'
        btn_download = 'Terracotta をダウンロード'
        btn_release = '配布ページを開く'
        btn_folder = 'フォルダーを開く'
        btn_close = '閉じる'
        tips = "1. 「マルチプレイを開始」を押し、ルームを作るかルームコードで参加します。`n2. ゲームの「マルチプレイ」で「Terracotta ロビー」をダブルクリックします。`n3. ホストは先に「LAN に公開」すると、友達がワールドを見られます。"
        credit = 'Terracotta by burningtnt、AGPL-3.0 ライセンス。'
        note = 'GitHub 公式 Release からダウンロードします（約 8 MB）。配布ページや Gitee ミラーも使えます。'
        dl_failed = 'Terracotta をダウンロードできませんでした。配布ページから Windows 版を手動で入手してください。'
        extract_failed = 'ダウンロードしたパッケージを展開できませんでした（tar.exe がありません）。手動でインストールしてください。'
        start_failed = 'Terracotta を起動できませんでした。'
    }
    'ko' = @{
        title = '멀티플레이 · Terracotta'
        subtitle = '방 코드로 친구와 연결, 포트 포워딩 불필요'
        status_found = 'Terracotta를 찾았습니다'
        status_missing = 'Terracotta가 아직 설치되지 않았습니다'
        status_running = 'Terracotta가 실행 중입니다'
        status_downloading = 'Terracotta를 내려받는 중입니다……'
        status_ready = '다운로드 완료, 시작할 수 있습니다'
        status_failed = '다운로드 실패, 배포 페이지를 사용하세요'
        status_launched = 'Terracotta를 시작했습니다'
        btn_start = '멀티플레이 시작'
        btn_show = '창 보이기'
        btn_download = 'Terracotta 다운로드'
        btn_release = '배포 페이지 열기'
        btn_folder = '폴더 열기'
        btn_close = '닫기'
        tips = "1. 멀티플레이 시작을 누르고 방을 만들거나 방 코드로 참가합니다.`n2. 게임에서 멀티플레이를 열고 Terracotta 로비를 두 번 클릭합니다.`n3. 호스트가 먼저 LAN에 공개해야 친구가 월드를 볼 수 있습니다."
        credit = 'Terracotta by burningtnt, AGPL-3.0 라이선스.'
        note = 'GitHub 공식 Release에서 내려받습니다(약 8 MB). 배포 페이지와 Gitee 미러도 됩니다.'
        dl_failed = 'Terracotta를 내려받지 못했습니다. 배포 페이지에서 Windows용을 직접 받아 주세요.'
        extract_failed = '받은 패키지를 풀지 못했습니다(tar.exe 없음). 직접 설치해 주세요.'
        start_failed = 'Terracotta를 시작하지 못했습니다.'
    }
    'fr' = @{
        title = 'Multijoueur · Terracotta'
        subtitle = 'Jouez avec vos amis via un code de salon, sans redirection de port'
        status_found = 'Terracotta est installé'
        status_missing = "Terracotta n'est pas encore installé"
        status_running = 'Terracotta est en cours d exécution'
        status_downloading = 'Téléchargement de Terracotta, patientez...'
        status_ready = 'Téléchargement terminé, prêt à démarrer'
        status_failed = 'Échec du téléchargement, utilisez la page de publication'
        status_launched = 'Terracotta démarré'
        btn_start = 'Démarrer le multijoueur'
        btn_show = 'Afficher la fenêtre'
        btn_download = 'Télécharger Terracotta'
        btn_release = 'Ouvrir la page de publication'
        btn_folder = 'Ouvrir le dossier'
        btn_close = 'Fermer'
        tips = "1. Cliquez sur Démarrer le multijoueur, créez un salon ou rejoignez-en un avec un code.`n2. Dans Minecraft, ouvrez Multijoueur et double-cliquez sur le salon Terracotta.`n3. L hôte doit d abord ouvrir le monde au réseau local, sinon vos amis ne le verront pas."
        credit = 'Terracotta par burningtnt, sous licence AGPL-3.0.'
        note = 'Téléchargé depuis la publication GitHub officielle (environ 8 Mo) ; la page de publication et le miroir Gitee fonctionnent aussi.'
        dl_failed = 'Impossible de télécharger Terracotta. Ouvrez la page de publication et prenez la version Windows à la main.'
        extract_failed = "Le paquet téléchargé n a pas pu être décompressé (tar.exe manquant). Installez-le manuellement."
        start_failed = 'Impossible de démarrer Terracotta.'
    }
    'de' = @{
        title = 'Mehrspieler · Terracotta'
        subtitle = 'Mit Freunden über einen Raumcode spielen, ohne Portfreigabe'
        status_found = 'Terracotta gefunden'
        status_missing = 'Terracotta ist noch nicht installiert'
        status_running = 'Terracotta läuft'
        status_downloading = 'Terracotta wird heruntergeladen, bitte warten...'
        status_ready = 'Download fertig, bereit zum Starten'
        status_failed = 'Download fehlgeschlagen, bitte die Release-Seite nutzen'
        status_launched = 'Terracotta gestartet'
        btn_start = 'Mehrspieler starten'
        btn_show = 'Fenster zeigen'
        btn_download = 'Terracotta herunterladen'
        btn_release = 'Release-Seite öffnen'
        btn_folder = 'Ordner öffnen'
        btn_close = 'Schließen'
        tips = "1. Auf Mehrspieler starten klicken, einen Raum erstellen oder mit Code beitreten.`n2. In Minecraft Mehrspieler öffnen und die Terracotta-Lobby doppelklicken.`n3. Der Gastgeber muss die Welt zuerst im LAN öffnen, sonst sehen Freunde sie nicht."
        credit = 'Terracotta von burningtnt, Lizenz AGPL-3.0.'
        note = 'Wird vom offiziellen GitHub-Release geladen (etwa 8 MB); Release-Seite und Gitee-Spiegel gehen auch.'
        dl_failed = 'Terracotta konnte nicht geladen werden. Öffne die Release-Seite und lade die Windows-Version von Hand.'
        extract_failed = 'Das Paket konnte nicht entpackt werden (tar.exe fehlt). Bitte von Hand installieren.'
        start_failed = 'Terracotta konnte nicht gestartet werden.'
    }
    'es' = @{
        title = 'Multijugador · Terracotta'
        subtitle = 'Juega con amigos con un código de sala, sin abrir puertos'
        status_found = 'Terracotta encontrado'
        status_missing = 'Terracotta aún no está instalado'
        status_running = 'Terracotta se está ejecutando'
        status_downloading = 'Descargando Terracotta, espera...'
        status_ready = 'Descarga lista, se puede iniciar'
        status_failed = 'La descarga falló, usa la página de versiones'
        status_launched = 'Terracotta iniciado'
        btn_start = 'Iniciar multijugador'
        btn_show = 'Mostrar ventana'
        btn_download = 'Descargar Terracotta'
        btn_release = 'Abrir página de versiones'
        btn_folder = 'Abrir carpeta'
        btn_close = 'Cerrar'
        tips = "1. Pulsa Iniciar multijugador, crea una sala o únete con un código.`n2. En Minecraft abre Multijugador y haz doble clic en la sala de Terracotta.`n3. El anfitrión debe abrir antes el mundo en la red local, si no, nadie lo verá."
        credit = 'Terracotta por burningtnt, licencia AGPL-3.0.'
        note = 'Se descarga de la versión oficial de GitHub (unos 8 MB); la página de versiones y el espejo de Gitee también sirven.'
        dl_failed = 'No se pudo descargar Terracotta. Abre la página de versiones y descarga la versión de Windows a mano.'
        extract_failed = 'No se pudo descomprimir el paquete (falta tar.exe). Instálalo manualmente.'
        start_failed = 'No se pudo iniciar Terracotta.'
    }
    'pt-BR' = @{
        title = 'Multijogador · Terracotta'
        subtitle = 'Jogue com amigos por código de sala, sem liberar portas'
        status_found = 'Terracotta encontrado'
        status_missing = 'Terracotta ainda não está instalado'
        status_running = 'Terracotta está em execução'
        status_downloading = 'Baixando o Terracotta, aguarde...'
        status_ready = 'Download concluído, pronto para iniciar'
        status_failed = 'Falha no download, use a página de versões'
        status_launched = 'Terracotta iniciado'
        btn_start = 'Iniciar multijogador'
        btn_show = 'Mostrar janela'
        btn_download = 'Baixar Terracotta'
        btn_release = 'Abrir página de versões'
        btn_folder = 'Abrir pasta'
        btn_close = 'Fechar'
        tips = "1. Clique em Iniciar multijogador, crie uma sala ou entre com um código.`n2. No Minecraft abra Multijogador e clique duas vezes na sala do Terracotta.`n3. O anfitrião precisa abrir o mundo na rede local antes, senão ninguém o vê."
        credit = 'Terracotta por burningtnt, licença AGPL-3.0.'
        note = 'Baixado da versão oficial no GitHub (cerca de 8 MB); a página de versões e o espelho do Gitee também funcionam.'
        dl_failed = 'Não foi possível baixar o Terracotta. Abra a página de versões e baixe a versão Windows manualmente.'
        extract_failed = 'Não foi possível extrair o pacote (falta o tar.exe). Instale manualmente.'
        start_failed = 'Não foi possível iniciar o Terracotta.'
    }
    'ru' = @{
        title = 'Сетевая игра · Terracotta'
        subtitle = 'Играйте с друзьями по коду комнаты, без проброса портов'
        status_found = 'Terracotta найден'
        status_missing = 'Terracotta ещё не установлен'
        status_running = 'Terracotta уже запущен'
        status_downloading = 'Загрузка Terracotta, подождите...'
        status_ready = 'Загрузка завершена, можно запускать'
        status_failed = 'Не удалось скачать, используйте страницу релизов'
        status_launched = 'Terracotta запущен'
        btn_start = 'Начать сетевую игру'
        btn_show = 'Показать окно'
        btn_download = 'Скачать Terracotta'
        btn_release = 'Открыть страницу релизов'
        btn_folder = 'Открыть папку'
        btn_close = 'Закрыть'
        tips = "1. Нажмите Начать сетевую игру, создайте комнату или войдите по коду.`n2. В Minecraft откройте Сетевая игра и дважды щёлкните лобби Terracotta.`n3. Хозяин должен сначала открыть мир по локальной сети, иначе друзья его не увидят."
        credit = 'Terracotta от burningtnt, лицензия AGPL-3.0.'
        note = 'Загружается с официального релиза GitHub (около 8 МБ); страница релизов и зеркало Gitee тоже подходят.'
        dl_failed = 'Не удалось скачать Terracotta. Откройте страницу релизов и скачайте версию для Windows вручную.'
        extract_failed = 'Не удалось распаковать пакет (нет tar.exe). Установите вручную.'
        start_failed = 'Не удалось запустить Terracotta.'
    }
    'it' = @{
        title = 'Multigiocatore · Terracotta'
        subtitle = 'Gioca con gli amici tramite codice stanza, senza aprire porte'
        status_found = 'Terracotta trovato'
        status_missing = 'Terracotta non è ancora installato'
        status_running = 'Terracotta è in esecuzione'
        status_downloading = 'Download di Terracotta in corso...'
        status_ready = 'Download completato, pronto per avviare'
        status_failed = 'Download non riuscito, usa la pagina delle release'
        status_launched = 'Terracotta avviato'
        btn_start = 'Avvia multigiocatore'
        btn_show = 'Mostra finestra'
        btn_download = 'Scarica Terracotta'
        btn_release = 'Apri pagina delle release'
        btn_folder = 'Apri cartella'
        btn_close = 'Chiudi'
        tips = "1. Premi Avvia multigiocatore, crea una stanza o entra con un codice.`n2. In Minecraft apri Multigiocatore e fai doppio clic sulla stanza Terracotta.`n3. L host deve prima aprire il mondo in LAN, altrimenti gli amici non lo vedono."
        credit = 'Terracotta di burningtnt, licenza AGPL-3.0.'
        note = 'Scaricato dalla release ufficiale su GitHub (circa 8 MB); vanno bene anche la pagina delle release e il mirror Gitee.'
        dl_failed = 'Impossibile scaricare Terracotta. Apri la pagina delle release e scarica la versione Windows a mano.'
        extract_failed = 'Impossibile estrarre il pacchetto (manca tar.exe). Installalo manualmente.'
        start_failed = 'Impossibile avviare Terracotta.'
    }
    'nl' = @{
        title = 'Multiplayer · Terracotta'
        subtitle = 'Speel met vrienden via een kamercode, zonder port forwarding'
        status_found = 'Terracotta gevonden'
        status_missing = 'Terracotta is nog niet geïnstalleerd'
        status_running = 'Terracotta draait'
        status_downloading = 'Terracotta wordt gedownload, even geduld...'
        status_ready = 'Download klaar, klaar om te starten'
        status_failed = 'Download mislukt, gebruik de releasepagina'
        status_launched = 'Terracotta gestart'
        btn_start = 'Multiplayer starten'
        btn_show = 'Venster tonen'
        btn_download = 'Terracotta downloaden'
        btn_release = 'Releasepagina openen'
        btn_folder = 'Map openen'
        btn_close = 'Sluiten'
        tips = "1. Klik op Multiplayer starten, maak een kamer of join met een code.`n2. Open in Minecraft Multiplayer en dubbelklik op de Terracotta-lobby.`n3. De host moet de wereld eerst in het LAN openen, anders zien vrienden hem niet."
        credit = 'Terracotta door burningtnt, licentie AGPL-3.0.'
        note = 'Gedownload van de officiële GitHub-release (ongeveer 8 MB); de releasepagina en de Gitee-spiegel werken ook.'
        dl_failed = 'Kon Terracotta niet downloaden. Open de releasepagina en haal de Windows-versie handmatig.'
        extract_failed = 'Het pakket kon niet worden uitgepakt (tar.exe ontbreekt). Installeer het handmatig.'
        start_failed = 'Kon Terracotta niet starten.'
    }
    'pl' = @{
        title = 'Wieloosobowa · Terracotta'
        subtitle = 'Graj z przyjaciółmi przez kod pokoju, bez przekierowania portów'
        status_found = 'Znaleziono Terracotta'
        status_missing = 'Terracotta nie jest jeszcze zainstalowana'
        status_running = 'Terracotta jest uruchomiona'
        status_downloading = 'Pobieranie Terracotta, chwilę...'
        status_ready = 'Pobrano, można uruchomić'
        status_failed = 'Pobieranie nie powiodło się, użyj strony wydań'
        status_launched = 'Terracotta uruchomiona'
        btn_start = 'Uruchom grę wieloosobową'
        btn_show = 'Pokaż okno'
        btn_download = 'Pobierz Terracotta'
        btn_release = 'Otwórz stronę wydań'
        btn_folder = 'Otwórz folder'
        btn_close = 'Zamknij'
        tips = "1. Kliknij Uruchom grę wieloosobową, utwórz pokój lub dołącz kodem.`n2. W Minecraft otwórz Wieloosobowa i dwukrotnie kliknij lobby Terracotta.`n3. Gospodarz musi najpierw udostępnić świat w sieci lokalnej, inaczej znajomi go nie zobaczą."
        credit = 'Terracotta autorstwa burningtnt, licencja AGPL-3.0.'
        note = 'Pobierane z oficjalnego wydania GitHub (około 8 MB); strona wydań i mirror Gitee też działają.'
        dl_failed = 'Nie udało się pobrać Terracotta. Otwórz stronę wydań i pobierz wersję dla Windows ręcznie.'
        extract_failed = 'Nie udało się rozpakować paczki (brak tar.exe). Zainstaluj ręcznie.'
        start_failed = 'Nie udało się uruchomić Terracotta.'
    }
    'tr' = @{
        title = 'Çok oyunculu · Terracotta'
        subtitle = 'Oda kodu ile arkadaşlarınızla oynayın, port yönlendirme gerekmez'
        status_found = 'Terracotta bulundu'
        status_missing = 'Terracotta henüz kurulu değil'
        status_running = 'Terracotta çalışıyor'
        status_downloading = 'Terracotta indiriliyor, lütfen bekleyin...'
        status_ready = 'İndirme bitti, başlatılabilir'
        status_failed = 'İndirme başarısız, sürüm sayfasını kullanın'
        status_launched = 'Terracotta başlatıldı'
        btn_start = 'Çok oyunculu başlat'
        btn_show = 'Pencereyi göster'
        btn_download = 'Terracotta indir'
        btn_release = 'Sürüm sayfasını aç'
        btn_folder = 'Klasörü aç'
        btn_close = 'Kapat'
        tips = "1. Çok oyunculu başlat a basın, oda oluşturun veya kodla katılın.`n2. Minecraft ta Çok Oyunculu yu açın ve Terracotta lobisine çift tıklayın.`n3. Sunucu önce dünyayı yerel ağa açmalı, yoksa arkadaşlar göremez."
        credit = 'Terracotta, burningtnt tarafından, AGPL-3.0 lisansı.'
        note = 'Resmi GitHub sürümünden indirilir (yaklaşık 8 MB); sürüm sayfası ve Gitee aynası da çalışır.'
        dl_failed = 'Terracotta indirilemedi. Sürüm sayfasını açıp Windows sürümünü elle indirin.'
        extract_failed = 'Paket açılamadı (tar.exe yok). Elle kurun.'
        start_failed = 'Terracotta başlatılamadı.'
    }
    'vi' = @{
        title = 'Nhiều người · Terracotta'
        subtitle = 'Chơi cùng bạn bè bằng mã phòng, không cần mở cổng'
        status_found = 'Đã tìm thấy Terracotta'
        status_missing = 'Terracotta chưa được cài đặt'
        status_running = 'Terracotta đang chạy'
        status_downloading = 'Đang tải Terracotta, vui lòng chờ...'
        status_ready = 'Tải xong, có thể khởi động'
        status_failed = 'Tải thất bại, hãy dùng trang phát hành'
        status_launched = 'Đã khởi động Terracotta'
        btn_start = 'Bắt đầu nhiều người'
        btn_show = 'Hiện cửa sổ'
        btn_download = 'Tải Terracotta'
        btn_release = 'Mở trang phát hành'
        btn_folder = 'Mở thư mục'
        btn_close = 'Đóng'
        tips = "1. Nhấn Bắt đầu nhiều người, tạo phòng hoặc vào bằng mã phòng.`n2. Trong Minecraft mở Nhiều người rồi nhấp đúp vào sảnh Terracotta.`n3. Chủ phòng phải mở thế giới sang mạng LAN trước, nếu không bạn bè sẽ không thấy."
        credit = 'Terracotta của burningtnt, giấy phép AGPL-3.0.'
        note = 'Tải từ bản phát hành chính thức trên GitHub (khoảng 8 MB); trang phát hành và bản gương Gitee cũng dùng được.'
        dl_failed = 'Không tải được Terracotta. Hãy mở trang phát hành và tải bản Windows thủ công.'
        extract_failed = 'Không giải nén được gói (thiếu tar.exe). Hãy cài thủ công.'
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

function Get-TerracottaProcess {
    $list = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'terracotta*' })
    if ($list.Count -gt 0) { return $list[0] }
    return $null
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

function Show-TerracottaWindow($proc) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.AppActivate($proc.Id)
        return $true
    } catch { return $false }
}

# Offline test hook: print what the window would show, without opening it.
#   PCLTOOLS_ONLINE_TEST=1         detection and language only
#   PCLTOOLS_ONLINE_TEST=download  also download and unpack into <base>\Online
# PCLTOOLS_ONLINE_NO_START=1 keeps the tests from starting the program.
if ($env:PCLTOOLS_ONLINE_TEST) {
    [Console]::Out.WriteLine('DIR=' + $script:OnlineDir)
    [Console]::Out.WriteLine('EXE=' + (Find-Terracotta))
    [Console]::Out.WriteLine('RUN=' + [string][bool](Get-TerracottaProcess))
    [Console]::Out.WriteLine('LANG=' + $script:Lang)
    [Console]::Out.WriteLine('TITLE=' + (T 'title'))
    if ($env:PCLTOOLS_ONLINE_TEST -eq 'download') {
        [Console]::Out.WriteLine('INSTALLED=' + (Install-Terracotta))
        [Console]::Out.WriteLine('INSTALLSTAGE=' + $script:InstallStage)
        [Console]::Out.WriteLine('EXE2=' + (Find-Terracotta))
    }
    exit 0
}

# ==== UI ====
[Windows.Forms.Application]::EnableVisualStyles()
$script:Form = New-Object Windows.Forms.Form
$script:Form.Text = T 'title'
$script:Form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
$script:Form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
$script:Form.MaximizeBox = $false
$script:Form.MinimizeBox = $true
$script:Form.ClientSize = New-Object Drawing.Size(600, 430)
try { $script:Form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9) } catch { }
try { $script:Form.Icon = [Drawing.SystemIcons]::Application } catch { }

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
$panel.Size = New-Object Drawing.Size(560, 56)
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
$script:PathLabel.Size = New-Object Drawing.Size(536, 16)
$panel.Controls.Add($script:PathLabel)

function New-ActionButton([string]$text, [int]$x, [int]$w) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object Drawing.Point($x, 142)
    $b.Size = New-Object Drawing.Size($w, 34)
    $b.UseVisualStyleBackColor = $true
    return $b
}

$script:Primary = New-ActionButton (T 'btn_download') 20 160
$script:Primary.Tag = 'download'
$script:Form.Controls.Add($script:Primary)

$release = New-ActionButton (T 'btn_release') 190 130
$script:Form.Controls.Add($release)

$folder = New-ActionButton (T 'btn_folder') 330 130
$script:Form.Controls.Add($folder)

$closeButton = New-ActionButton (T 'btn_close') 470 110
$closeButton.DialogResult = [Windows.Forms.DialogResult]::Cancel
$script:Form.Controls.Add($closeButton)
$script:Form.CancelButton = $closeButton

$tips = New-Object Windows.Forms.Label
$tips.Text = T 'tips'
$tips.AutoSize = $false
$tips.Location = New-Object Drawing.Point(21, 190)
$tips.Size = New-Object Drawing.Size(560, 160)
$script:Form.Controls.Add($tips)

$credit = New-Object Windows.Forms.Label
$credit.Text = T 'credit'
$credit.ForeColor = [Drawing.Color]::FromArgb(120, 120, 120)
$credit.AutoSize = $true
$credit.Location = New-Object Drawing.Point(21, 366)
$script:Form.Controls.Add($credit)

$note = New-Object Windows.Forms.Label
$note.Text = T 'note'
$note.ForeColor = [Drawing.Color]::FromArgb(150, 150, 150)
$note.AutoSize = $false
$note.Location = New-Object Drawing.Point(21, 386)
$note.Size = New-Object Drawing.Size(560, 32)
$script:Form.Controls.Add($note)

function Update-Ui {
    $proc = Get-TerracottaProcess
    if ($proc) {
        $script:StatusLabel.Text = T 'status_running'
        $path = ''
        try { $path = [string]$proc.Path } catch { }
        $script:PathLabel.Text = $path
        $script:Primary.Text = T 'btn_show'
        $script:Primary.Tag = 'show'
        return
    }
    $script:ExePath = Find-Terracotta
    if ($script:ExePath) {
        $script:StatusLabel.Text = T 'status_found'
        $script:PathLabel.Text = $script:ExePath
        $script:Primary.Text = T 'btn_start'
        $script:Primary.Tag = 'start'
    } else {
        $script:StatusLabel.Text = T 'status_missing'
        $script:PathLabel.Text = $script:OnlineDir
        $script:Primary.Text = T 'btn_download'
        $script:Primary.Tag = 'download'
    }
}

function Download-ThenStart {
    $script:PathLabel.Text = ''
    $exe = Install-Terracotta
    if (-not $exe) {
        $msg = T 'dl_failed'
        if ($script:InstallStage -eq 'extract') { $msg = T 'extract_failed' }
        [void][Windows.Forms.MessageBox]::Show($msg, (T 'title'), [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
        Update-Ui
        return
    }
    if (Start-Terracotta $exe) {
        Set-Status (T 'status_launched')
        Start-Sleep -Milliseconds 600
    } else {
        [void][Windows.Forms.MessageBox]::Show((T 'start_failed'), (T 'title'), [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
    }
    Update-Ui
}
$script:Primary.Add_Click({
    switch ([string]$script:Primary.Tag) {
        'show' {
            $proc = Get-TerracottaProcess
            if ($proc) { [void](Show-TerracottaWindow $proc) }
            Update-Ui
        }
        'start' {
            if (-not $script:ExePath) { $script:ExePath = Find-Terracotta }
            if ($script:ExePath -and (Start-Terracotta $script:ExePath)) {
                $script:StatusLabel.Text = T 'status_launched'
                Start-Sleep -Milliseconds 600
            } else {
                [void][Windows.Forms.MessageBox]::Show((T 'start_failed'), (T 'title'), [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
            }
            Update-Ui
        }
        default {
            Download-ThenStart
        }
    }
})

$release.Add_Click({
    try { Start-Process $script:ReleasePage | Out-Null } catch { }
})

$folder.Add_Click({
    try {
        if ($script:ExePath -and (Test-Path -LiteralPath $script:ExePath)) {
            Start-Process 'explorer.exe' -ArgumentList ('/select,"' + $script:ExePath + '"') | Out-Null
        } else {
            [void][IO.Directory]::CreateDirectory($script:OnlineDir)
            Start-Process 'explorer.exe' -ArgumentList ('"' + $script:OnlineDir + '"') | Out-Null
        }
    } catch { }
})

Update-Ui
[void]$script:Form.ShowDialog()
