param(
    [string]$BaseDir = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $BaseDir) { $BaseDir = $PSScriptRoot }
$script:BaseDir = [IO.Path]::GetFullPath($BaseDir).TrimEnd('\')
$script:DataPath = Join-Path $script:BaseDir 'CustomCommands.json'
$script:Commands = New-Object System.Collections.ArrayList
$script:CurrentIndex = -1
$script:TargetWindow = $null
$script:PendingRun = $null
$script:TargetShowSuccess = $false
$script:TargetLabelTimer = $null

$script:Strings = @{
    'en' = @{
        title = 'Custom commands'
        subtitle = 'Manage client commands that run in Minecraft'
        list = 'Commands'
        name = 'Name'
        command = 'Command'
        hint = 'Do not type the leading slash. Click Run twice to confirm. Each Select window click re-recognizes and updates the target; no cache is saved.'
        add = 'Add'
        delete = 'Delete'
        save = 'Save'
        run = 'Run'
        close = 'Close'
        empty = 'No commands yet. Click Add to start.'
        name_required = 'Enter a name.'
        command_required = 'Enter a command.'
        confirm_delete = 'Delete "{0}"?'
        no_game = 'No running Minecraft found. Start the game first.'
        focus_failed = 'Could not focus the Minecraft window. Switch to it and try again.'
        sent = 'Sent to Minecraft (PID {0}).'
        saved = 'Saved.'
        send_failed = 'Send failed: {0}'
        data_error = 'Could not read the command file: {0}'
        click_game = 'Click the Minecraft game window so the manager can remember it. The command will be sent to that window.'
        target_none = 'Target window: not selected'
        target_bound = 'Target window: {0}'
        select_window = 'Select window'
        recognized = 'Recognized'
        not_in_game = 'Not in a world. Enter a world first; command not sent.'
        confirm_run = 'In game. Click Run again within 10 seconds to confirm.'
        gui_closing = 'A game GUI is open. Closing it and checking before sending.'
        gui_failed = 'Could not close the game GUI. Command not sent.'
        ready = 'Ready.'
    }
    'zh-CN' = @{
        title = '自定义指令'
        subtitle = '管理会在 Minecraft 中执行的客户端指令'
        list = '指令列表'
        name = '名称'
        command = '指令'
        hint = '不需要输入开头的 /。连续点击两次“执行”确认；每次点击“选择窗口”都会重新识别并更新目标，不保存缓存。'
        add = '新增'
        delete = '删除'
        save = '保存'
        run = '执行'
        close = '关闭'
        empty = '还没有指令，点击“新增”开始。'
        name_required = '请填写名称。'
        command_required = '请填写指令。'
        confirm_delete = '确定删除“{0}”吗？'
        no_game = '没有找到正在运行的 Minecraft，请先进入游戏。'
        focus_failed = '无法切换到 Minecraft 窗口，请手动切换后再试。'
        sent = '已发送到 Minecraft（PID {0}）。'
        saved = '已保存。'
        send_failed = '发送失败：{0}'
        data_error = '指令文件无法读取：{0}'
        click_game = '请点击 Minecraft 游戏窗口，让管理器识别并记住它；指令会发送到这个窗口。'
        target_none = '目标窗口：未选择'
        target_bound = '目标窗口：{0}'
        select_window = '选择窗口'
        recognized = '识别成功'
        not_in_game = '当前不在游戏内。请先进入世界；未执行指令。'
        confirm_run = '已进入游戏。请在 10 秒内再次点击“执行”确认。'
        gui_closing = '检测到游戏 GUI，正在关闭并多次确认...'
        gui_failed = '无法关闭游戏 GUI，未执行指令。'
        ready = '就绪。'
    }
    'zh-TW' = @{
        title = '自訂指令'
        subtitle = '管理會在 Minecraft 中執行的用戶端指令'
        list = '指令列表'
        name = '名稱'
        command = '指令'
        hint = '不需要輸入開頭的 /。連續點擊兩次「執行」確認；每次點擊「選擇視窗」都會重新辨識並更新目標，不儲存快取。'
        add = '新增'
        delete = '刪除'
        save = '儲存'
        run = '執行'
        close = '關閉'
        empty = '尚無指令，點擊「新增」開始。'
        name_required = '請填寫名稱。'
        command_required = '請填寫指令。'
        confirm_delete = '確定刪除「{0}」嗎？'
        no_game = '找不到正在執行的 Minecraft，請先進入遊戲。'
        focus_failed = '無法切換到 Minecraft 視窗，請手動切換後再試。'
        sent = '已傳送到 Minecraft（PID {0}）。'
        saved = '已儲存。'
        send_failed = '傳送失敗：{0}'
        data_error = '無法讀取指令檔案：{0}'
        click_game = '請點擊 Minecraft 遊戲視窗，讓管理器辨識並記住它；指令會傳送到這個視窗。'
        target_none = '目標視窗：未選擇'
        target_bound = '目標視窗：{0}'
        select_window = '選擇視窗'
        recognized = '辨識成功'
        not_in_game = '目前不在遊戲內。請先進入世界；未執行指令。'
        confirm_run = '已進入遊戲。請在 10 秒內再次點擊「執行」確認。'
        gui_closing = '偵測到遊戲 GUI，正在關閉並多次確認...'
        gui_failed = '無法關閉遊戲 GUI，未執行指令。'
        ready = '就緒。'
    }
    'ja' = @{
        title = 'カスタムコマンド'
        subtitle = 'Minecraft で実行するクライアントコマンドを管理します'
        list = 'コマンド一覧'
        name = '名前'
        command = 'コマンド'
        hint = '/ は入力不要です。「実行」を2回クリックして確認します。「ウィンドウ選択」を押すたびに再認識して更新し、キャッシュは保存しません。'
        add = '追加'
        delete = '削除'
        save = '保存'
        run = '実行'
        close = '閉じる'
        empty = 'コマンドがありません。「追加」をクリックしてください。'
        name_required = '名前を入力してください。'
        command_required = 'コマンドを入力してください。'
        confirm_delete = '「{0}」を削除しますか？'
        no_game = '実行中の Minecraft が見つかりません。先にゲームを起動してください。'
        focus_failed = 'Minecraft ウィンドウを前面にできません。手動で切り替えてから再試行してください。'
        sent = 'Minecraft に送信しました（PID {0}）。'
        saved = '保存しました。'
        send_failed = '送信に失敗しました：{0}'
        data_error = 'コマンドファイルを読み込めません：{0}'
        click_game = 'Minecraft のゲームウィンドウをクリックして、マネージャーに記憶させてください。コマンドはそのウィンドウに送信されます。'
        target_none = '対象ウィンドウ：未選択'
        target_bound = '対象ウィンドウ：{0}'
        select_window = 'ウィンドウを選択'
        recognized = '認識しました'
        not_in_game = 'ゲーム内ではありません。先にワールドへ入ってください。コマンドは送信されません。'
        confirm_run = 'ゲーム内です。10 秒以内にもう一度「実行」をクリックして確認してください。'
        gui_closing = 'ゲーム内 GUI を検出しました。閉じて確認してから送信します。'
        gui_failed = 'ゲーム GUI を閉じられませんでした。コマンドは送信されません。'
        ready = '準備完了。'
    }
    'ko' = @{
        title = '사용자 지정 명령'
        subtitle = 'Minecraft에서 실행할 클라이언트 명령을 관리합니다'
        list = '명령 목록'
        name = '이름'
        command = '명령'
        hint = '앞의 /는 입력하지 마세요. 실행을 두 번 클릭해 확인합니다. 창 선택을 누를 때마다 다시 인식해 갱신하며 캐시는 저장하지 않습니다.'
        add = '추가'
        delete = '삭제'
        save = '저장'
        run = '실행'
        close = '닫기'
        empty = '명령이 없습니다. 추가를 클릭하세요.'
        name_required = '이름을 입력하세요.'
        command_required = '명령을 입력하세요.'
        confirm_delete = '"{0}"을(를) 삭제할까요?'
        no_game = '실행 중인 Minecraft를 찾을 수 없습니다. 먼저 게임을 시작하세요.'
        focus_failed = 'Minecraft 창으로 전환할 수 없습니다. 직접 전환한 뒤 다시 시도하세요.'
        sent = 'Minecraft로 보냈습니다(PID {0}).'
        saved = '저장했습니다.'
        send_failed = '보내기 실패: {0}'
        data_error = '명령 파일을 읽을 수 없습니다: {0}'
        click_game = 'Minecraft 게임 창을 클릭해 관리자가 기억하도록 하세요. 명령은 해당 창으로 전송됩니다.'
        target_none = '대상 창: 선택되지 않음'
        target_bound = '대상 창: {0}'
        select_window = '창 선택'
        recognized = '인식됨'
        not_in_game = '게임 안이 아닙니다. 먼저 월드에 들어가세요. 명령은 전송되지 않았습니다.'
        confirm_run = '게임 안입니다. 10초 안에 실행을 다시 클릭해 확인하세요.'
        gui_closing = '게임 GUI가 열려 있습니다. 닫고 확인한 뒤 전송합니다.'
        gui_failed = '게임 GUI를 닫지 못했습니다. 명령이 전송되지 않았습니다.'
        ready = '준비됨.'
    }
    'fr' = @{
        title = 'Commandes personnalisées'
        subtitle = 'Gérer les commandes client exécutées dans Minecraft'
        list = 'Commandes'
        name = 'Nom'
        command = 'Commande'
        hint = 'Ne saisissez pas le / initial. Cliquez deux fois sur Exécuter pour confirmer. Chaque clic sur Sélectionner la fenêtre reconnaît et met à jour la cible ; aucun cache n est enregistré.'
        add = 'Ajouter'
        delete = 'Supprimer'
        save = 'Enregistrer'
        run = 'Exécuter'
        close = 'Fermer'
        empty = 'Aucune commande. Cliquez sur Ajouter.'
        name_required = 'Saisissez un nom.'
        command_required = 'Saisissez une commande.'
        confirm_delete = 'Supprimer « {0} » ?'
        no_game = 'Aucun Minecraft en cours. Lancez le jeu d abord.'
        focus_failed = 'Impossible de passer à la fenêtre Minecraft. Basculez manuellement puis réessayez.'
        sent = 'Envoyé à Minecraft (PID {0}).'
        saved = 'Enregistré.'
        send_failed = 'Échec de l envoi : {0}'
        data_error = 'Impossible de lire le fichier : {0}'
        click_game = 'Cliquez sur la fenêtre de jeu Minecraft pour que le gestionnaire la mémorise. La commande sera envoyée à cette fenêtre.'
        target_none = 'Fenêtre cible : non sélectionnée'
        target_bound = 'Fenêtre cible : {0}'
        select_window = 'Choisir la fenêtre'
        recognized = 'Reconnu'
        not_in_game = 'Vous devez être dans une partie. Entrez d abord dans un monde ; commande non envoyée.'
        confirm_run = 'Dans la partie. Cliquez à nouveau sur Exécuter dans les 10 secondes pour confirmer.'
        gui_closing = 'Une interface de jeu est ouverte. Fermeture et vérification avant envoi.'
        gui_failed = 'Impossible de fermer l interface de jeu. Commande non envoyée.'
        ready = 'Prêt.'
    }
    'de' = @{
        title = 'Eigene Befehle'
        subtitle = 'Client-Befehle für Minecraft verwalten'
        list = 'Befehle'
        name = 'Name'
        command = 'Befehl'
        hint = 'Das führende / nicht eingeben. Zum Bestätigen zweimal auf Ausführen klicken. Jeder Klick auf Fenster wählen erkennt das Ziel neu und aktualisiert es; kein Cache.'
        add = 'Hinzufügen'
        delete = 'Löschen'
        save = 'Speichern'
        run = 'Ausführen'
        close = 'Schließen'
        empty = 'Noch keine Befehle. Klicke auf Hinzufügen.'
        name_required = 'Namen eingeben.'
        command_required = 'Befehl eingeben.'
        confirm_delete = '"{0}" löschen?'
        no_game = 'Kein laufendes Minecraft gefunden. Starte zuerst das Spiel.'
        focus_failed = 'Minecraft-Fenster konnte nicht aktiviert werden. Wechsle manuell und versuche es erneut.'
        sent = 'An Minecraft gesendet (PID {0}).'
        saved = 'Gespeichert.'
        send_failed = 'Senden fehlgeschlagen: {0}'
        data_error = 'Befehlsdatei konnte nicht gelesen werden: {0}'
        click_game = 'Klicke auf das Minecraft-Spielfenster, damit der Manager es sich merkt. Der Befehl wird an dieses Fenster gesendet.'
        target_none = 'Zielfenster: nicht ausgewählt'
        target_bound = 'Zielfenster: {0}'
        select_window = 'Fenster wählen'
        recognized = 'Erkannt'
        not_in_game = 'Du bist nicht in einer Welt. Betritt zuerst eine Welt; Befehl nicht gesendet.'
        confirm_run = 'Im Spiel. Klicke innerhalb von 10 Sekunden erneut auf Ausführen, um zu bestätigen.'
        gui_closing = 'Eine Spiel-GUI ist offen. Sie wird geschlossen und vor dem Senden geprüft.'
        gui_failed = 'Die Spiel-GUI konnte nicht geschlossen werden. Befehl nicht gesendet.'
        ready = 'Bereit.'
    }
    'es' = @{
        title = 'Comandos personalizados'
        subtitle = 'Gestiona comandos de cliente que se ejecutan en Minecraft'
        list = 'Comandos'
        name = 'Nombre'
        command = 'Comando'
        hint = 'No escribas la / inicial. Haz clic dos veces en Ejecutar para confirmar. Cada clic en Seleccionar ventana vuelve a reconocer y actualiza el objetivo; no se guarda caché.'
        add = 'Añadir'
        delete = 'Eliminar'
        save = 'Guardar'
        run = 'Ejecutar'
        close = 'Cerrar'
        empty = 'No hay comandos. Haz clic en Añadir.'
        name_required = 'Escribe un nombre.'
        command_required = 'Escribe un comando.'
        confirm_delete = '¿Eliminar "{0}"?'
        no_game = 'No se encontró Minecraft en ejecución. Inicia el juego primero.'
        focus_failed = 'No se pudo activar la ventana de Minecraft. Cámbiala manualmente y vuelve a intentarlo.'
        sent = 'Enviado a Minecraft (PID {0}).'
        saved = 'Guardado.'
        send_failed = 'Error al enviar: {0}'
        data_error = 'No se pudo leer el archivo: {0}'
        click_game = 'Haz clic en la ventana de Minecraft para que el administrador la recuerde. El comando se enviará a esa ventana.'
        target_none = 'Ventana de destino: no seleccionada'
        target_bound = 'Ventana de destino: {0}'
        select_window = 'Elegir ventana'
        recognized = 'Reconocido'
        not_in_game = 'No estás dentro de una partida. Entra primero en un mundo; comando no enviado.'
        confirm_run = 'En partida. Haz clic de nuevo en Ejecutar en 10 segundos para confirmar.'
        gui_closing = 'Hay una interfaz del juego abierta. Se cerrará y verificará antes de enviar.'
        gui_failed = 'No se pudo cerrar la interfaz del juego. Comando no enviado.'
        ready = 'Listo.'
    }
    'pt-BR' = @{
        title = 'Comandos personalizados'
        subtitle = 'Gerencie comandos de cliente executados no Minecraft'
        list = 'Comandos'
        name = 'Nome'
        command = 'Comando'
        hint = 'Não digite a / inicial. Clique em Executar duas vezes para confirmar. Cada clique em Selecionar janela reconhece e atualiza o alvo; nenhum cache é salvo.'
        add = 'Adicionar'
        delete = 'Excluir'
        save = 'Salvar'
        run = 'Executar'
        close = 'Fechar'
        empty = 'Nenhum comando. Clique em Adicionar.'
        name_required = 'Informe um nome.'
        command_required = 'Informe um comando.'
        confirm_delete = 'Excluir "{0}"?'
        no_game = 'Nenhum Minecraft em execução. Inicie o jogo primeiro.'
        focus_failed = 'Não foi possível ativar a janela do Minecraft. Alterne manualmente e tente novamente.'
        sent = 'Enviado ao Minecraft (PID {0}).'
        saved = 'Salvo.'
        send_failed = 'Falha ao enviar: {0}'
        data_error = 'Não foi possível ler o arquivo: {0}'
        click_game = 'Clique na janela do Minecraft para que o gerenciador se lembre dela. O comando será enviado para essa janela.'
        target_none = 'Janela de destino: não selecionada'
        target_bound = 'Janela de destino: {0}'
        select_window = 'Escolher janela'
        recognized = 'Reconhecido'
        not_in_game = 'Você não está em um mundo. Entre em um mundo primeiro; comando não enviado.'
        confirm_run = 'No jogo. Clique em Executar novamente em até 10 segundos para confirmar.'
        gui_closing = 'Há uma GUI do jogo aberta. Ela será fechada e verificada antes do envio.'
        gui_failed = 'Não foi possível fechar a GUI do jogo. Comando não enviado.'
        ready = 'Pronto.'
    }
    'ru' = @{
        title = 'Свои команды'
        subtitle = 'Управление клиентскими командами для Minecraft'
        list = 'Команды'
        name = 'Название'
        command = 'Команда'
        hint = 'Не вводите начальный /. Нажмите «Выполнить» дважды для подтверждения. Каждое нажатие «Выбрать окно» заново распознаёт и обновляет цель; кэш не сохраняется.'
        add = 'Добавить'
        delete = 'Удалить'
        save = 'Сохранить'
        run = 'Выполнить'
        close = 'Закрыть'
        empty = 'Команд пока нет. Нажмите «Добавить».'
        name_required = 'Введите название.'
        command_required = 'Введите команду.'
        confirm_delete = 'Удалить «{0}»?'
        no_game = 'Запущенный Minecraft не найден. Сначала запустите игру.'
        focus_failed = 'Не удалось переключиться на окно Minecraft. Переключитесь вручную и повторите.'
        sent = 'Отправлено в Minecraft (PID {0}).'
        saved = 'Сохранено.'
        send_failed = 'Ошибка отправки: {0}'
        data_error = 'Не удалось прочитать файл: {0}'
        click_game = 'Нажмите на окно Minecraft, чтобы менеджер запомнил его. Команда будет отправлена в это окно.'
        target_none = 'Целевое окно: не выбрано'
        target_bound = 'Целевое окно: {0}'
        select_window = 'Выбрать окно'
        recognized = 'Распознано'
        not_in_game = 'Вы не в мире. Сначала войдите в мир; команда не отправлена.'
        confirm_run = 'В игре. Нажмите «Выполнить» ещё раз в течение 10 секунд для подтверждения.'
        gui_closing = 'Открыт игровой интерфейс. Закрываем и проверяем перед отправкой.'
        gui_failed = 'Не удалось закрыть игровой интерфейс. Команда не отправлена.'
        ready = 'Готово.'
    }
    'it' = @{
        title = 'Comandi personalizzati'
        subtitle = 'Gestisci comandi client eseguiti in Minecraft'
        list = 'Comandi'
        name = 'Nome'
        command = 'Comando'
        hint = 'Non digitare la / iniziale. Fai clic due volte su Esegui per confermare. Ogni clic su Seleziona finestra riconosce e aggiorna il target; nessuna cache viene salvata.'
        add = 'Aggiungi'
        delete = 'Elimina'
        save = 'Salva'
        run = 'Esegui'
        close = 'Chiudi'
        empty = 'Nessun comando. Fai clic su Aggiungi.'
        name_required = 'Inserisci un nome.'
        command_required = 'Inserisci un comando.'
        confirm_delete = 'Eliminare "{0}"?'
        no_game = 'Nessun Minecraft in esecuzione. Avvia prima il gioco.'
        focus_failed = 'Impossibile attivare la finestra di Minecraft. Passa manualmente e riprova.'
        sent = 'Inviato a Minecraft (PID {0}).'
        saved = 'Salvato.'
        send_failed = 'Invio non riuscito: {0}'
        data_error = 'Impossibile leggere il file: {0}'
        click_game = 'Fai clic sulla finestra di Minecraft per farla ricordare al gestore. Il comando verrà inviato a quella finestra.'
        target_none = 'Finestra di destinazione: non selezionata'
        target_bound = 'Finestra di destinazione: {0}'
        select_window = 'Scegli finestra'
        recognized = 'Riconosciuto'
        not_in_game = 'Non sei in un mondo. Entra prima in un mondo; comando non inviato.'
        confirm_run = 'In partita. Fai di nuovo clic su Esegui entro 10 secondi per confermare.'
        gui_closing = 'È aperta una GUI del gioco. La chiudiamo e verifichiamo prima dell invio.'
        gui_failed = 'Impossibile chiudere la GUI del gioco. Comando non inviato.'
        ready = 'Pronto.'
    }
    'nl' = @{
        title = 'Aangepaste opdrachten'
        subtitle = 'Beheer clientopdrachten die in Minecraft worden uitgevoerd'
        list = 'Opdrachten'
        name = 'Naam'
        command = 'Opdracht'
        hint = 'Typ niet de leidende /. Klik twee keer op Uitvoeren om te bevestigen. Elke klik op Venster kiezen herkent en werkt het doel bij; er wordt geen cache opgeslagen.'
        add = 'Toevoegen'
        delete = 'Verwijderen'
        save = 'Opslaan'
        run = 'Uitvoeren'
        close = 'Sluiten'
        empty = 'Nog geen opdrachten. Klik op Toevoegen.'
        name_required = 'Voer een naam in.'
        command_required = 'Voer een opdracht in.'
        confirm_delete = '"{0}" verwijderen?'
        no_game = 'Geen actieve Minecraft gevonden. Start eerst het spel.'
        focus_failed = 'Kan het Minecraft-venster niet activeren. Schakel handmatig en probeer opnieuw.'
        sent = 'Verzonden naar Minecraft (PID {0}).'
        saved = 'Opgeslagen.'
        send_failed = 'Verzenden mislukt: {0}'
        data_error = 'Kan het bestand niet lezen: {0}'
        click_game = 'Klik op het Minecraft-spelvenster zodat de manager het onthoudt. De opdracht wordt naar dat venster verzonden.'
        target_none = 'Doelvenster: niet geselecteerd'
        target_bound = 'Doelvenster: {0}'
        select_window = 'Venster kiezen'
        recognized = 'Herkend'
        not_in_game = 'Je bent niet in een wereld. Ga eerst een wereld in; opdracht niet verzonden.'
        confirm_run = 'In de game. Klik binnen 10 seconden opnieuw op Uitvoeren om te bevestigen.'
        gui_closing = 'Er is een game-GUI open. Deze wordt gesloten en gecontroleerd voordat we verzenden.'
        gui_failed = 'De game-GUI kon niet worden gesloten. Opdracht niet verzonden.'
        ready = 'Gereed.'
    }
    'pl' = @{
        title = 'Własne polecenia'
        subtitle = 'Zarządzaj poleceniami klienta wykonywanymi w Minecraft'
        list = 'Polecenia'
        name = 'Nazwa'
        command = 'Polecenie'
        hint = 'Nie wpisuj początkowego /. Kliknij dwukrotnie Uruchom, aby potwierdzić. Każde kliknięcie Wybierz okno ponownie rozpoznaje i aktualizuje cel; pamięć podręczna nie jest zapisywana.'
        add = 'Dodaj'
        delete = 'Usuń'
        save = 'Zapisz'
        run = 'Wykonaj'
        close = 'Zamknij'
        empty = 'Brak poleceń. Kliknij Dodaj.'
        name_required = 'Podaj nazwę.'
        command_required = 'Podaj polecenie.'
        confirm_delete = 'Usunąć „{0}”?'
        no_game = 'Nie znaleziono uruchomionego Minecrafta. Najpierw uruchom grę.'
        focus_failed = 'Nie można aktywować okna Minecrafta. Przełącz ręcznie i spróbuj ponownie.'
        sent = 'Wysłano do Minecraft (PID {0}).'
        saved = 'Zapisano.'
        send_failed = 'Wysyłanie nie powiodło się: {0}'
        data_error = 'Nie można odczytać pliku: {0}'
        click_game = 'Kliknij okno gry Minecraft, aby menedżer je zapamiętał. Polecenie zostanie wysłane do tego okna.'
        target_none = 'Okno docelowe: nie wybrano'
        target_bound = 'Okno docelowe: {0}'
        select_window = 'Wybierz okno'
        recognized = 'Rozpoznano'
        not_in_game = 'Nie jesteś w świecie. Najpierw wejdź do świata; polecenie nie zostało wysłane.'
        confirm_run = 'W grze. Kliknij ponownie Uruchom w ciągu 10 sekund, aby potwierdzić.'
        gui_closing = 'Otwarte jest GUI gry. Zamykamy je i sprawdzamy przed wysłaniem.'
        gui_failed = 'Nie udało się zamknąć GUI gry. Polecenie nie zostało wysłane.'
        ready = 'Gotowe.'
    }
    'tr' = @{
        title = 'Özel komutlar'
        subtitle = 'Minecraft içinde çalışacak istemci komutlarını yönetin'
        list = 'Komutlar'
        name = 'Ad'
        command = 'Komut'
        hint = 'Baştaki / karakterini yazmayın. Onaylamak için Çalıştır düğmesine iki kez tıklayın. Pencere seç her tıklamada hedefi yeniden tanır ve güncelle; önbellek kaydedilmez.'
        add = 'Ekle'
        delete = 'Sil'
        save = 'Kaydet'
        run = 'Çalıştır'
        close = 'Kapat'
        empty = 'Henüz komut yok. Ekle düğmesine tıklayın.'
        name_required = 'Bir ad girin.'
        command_required = 'Bir komut girin.'
        confirm_delete = '"{0}" silinsin mi?'
        no_game = 'Çalışan Minecraft bulunamadı. Önce oyunu başlatın.'
        focus_failed = 'Minecraft penceresine geçilemedi. Elle geçip tekrar deneyin.'
        sent = 'Minecrafta gönderildi (PID {0}).'
        saved = 'Kaydedildi.'
        send_failed = 'Gönderme başarısız: {0}'
        data_error = 'Komut dosyası okunamadı: {0}'
        click_game = 'Yöneticinin hatırlaması için Minecraft oyun penceresine tıklayın. Komut o pencereye gönderilecektir.'
        target_none = 'Hedef pencere: seçilmedi'
        target_bound = 'Hedef pencere: {0}'
        select_window = 'Pencere seç'
        recognized = 'Tanındı'
        not_in_game = 'Bir dünyada değilsiniz. Önce bir dünyaya girin; komut gönderilmedi.'
        confirm_run = 'Oyunda. Onaylamak için 10 saniye içinde Çalıştır düğmesine tekrar tıklayın.'
        gui_closing = 'Bir oyun GUIsi açık. Göndermeden önce kapatılıp kontrol edilecek.'
        gui_failed = 'Oyun GUIsi kapatılamadı. Komut gönderilmedi.'
        ready = 'Hazır.'
    }
    'vi' = @{
        title = 'Lệnh tùy chỉnh'
        subtitle = 'Quản lý lệnh máy khách chạy trong Minecraft'
        list = 'Danh sách lệnh'
        name = 'Tên'
        command = 'Lệnh'
        hint = 'Không nhập dấu / ở đầu. Nhấp Chạy hai lần để xác nhận. Mỗi lần nhấp Chọn cửa sổ sẽ nhận diện lại và cập nhật mục tiêu; không lưu bộ nhớ đệm.'
        add = 'Thêm'
        delete = 'Xóa'
        save = 'Lưu'
        run = 'Chạy'
        close = 'Đóng'
        empty = 'Chưa có lệnh. Nhấn Thêm để bắt đầu.'
        name_required = 'Nhập tên.'
        command_required = 'Nhập lệnh.'
        confirm_delete = 'Xóa "{0}"?'
        no_game = 'Không tìm thấy Minecraft đang chạy. Hãy khởi động game trước.'
        focus_failed = 'Không thể chuyển sang cửa sổ Minecraft. Hãy chuyển thủ công rồi thử lại.'
        sent = 'Đã gửi tới Minecraft (PID {0}).'
        saved = 'Đã lưu.'
        send_failed = 'Gửi thất bại: {0}'
        data_error = 'Không đọc được tệp lệnh: {0}'
        click_game = 'Nhấp vào cửa sổ game Minecraft để trình quản lý ghi nhớ nó. Lệnh sẽ được gửi tới cửa sổ đó.'
        target_none = 'Cửa sổ đích: chưa chọn'
        target_bound = 'Cửa sổ đích: {0}'
        select_window = 'Chọn cửa sổ'
        recognized = 'Đã nhận diện'
        not_in_game = 'Bạn không ở trong thế giới. Hãy vào thế giới trước; lệnh chưa được gửi.'
        confirm_run = 'Trong game. Nhấp lại Chạy trong 10 giây để xác nhận.'
        gui_closing = 'GUI game đang mở. Đang đóng và kiểm tra trước khi gửi.'
        gui_failed = 'Không thể đóng GUI game. Lệnh chưa được gửi.'
        ready = 'Sẵn sàng.'
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
function Format-Text([string]$key, [string]$value) {
    return (T $key).Replace('{0}', $value)
}

function Normalize-Command([string]$value) {
    $s = [string]$value
    $s = $s -replace '[\r\n]+', ' '
    $s = $s.Trim()
    while ($s.StartsWith('/')) { $s = $s.Substring(1).TrimStart() }
    return $s.Trim()
}

function Load-CommandData {
    $script:Commands.Clear()
    if (-not (Test-Path -LiteralPath $script:DataPath)) { return }
    try {
        $raw = [IO.File]::ReadAllText($script:DataPath, [Text.Encoding]::UTF8)
        if (-not $raw.Trim()) { return }
        $obj = $raw | ConvertFrom-Json
        $items = @()
        if ($obj -is [array]) {
            $items = @($obj)
        } elseif ($obj.commands) {
            $items = @($obj.commands)
        }
        foreach ($item in $items) {
            if ($null -eq $item) { continue }
            $name = ([string]$item.name).Trim()
            $cmd = Normalize-Command ([string]$item.command)
            if (-not $name -and -not $cmd) { continue }
            if (-not $name) { $name = $cmd }
            [void]$script:Commands.Add([pscustomobject]@{ Name = $name; Command = $cmd })
        }
    } catch {
        [void][Windows.Forms.MessageBox]::Show((Format-Text 'data_error' $_.Exception.Message), (T 'title'), [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
    }
}

function Save-CommandData {
    $items = @($script:Commands | ForEach-Object {
        [pscustomobject]@{ name = [string]$_.Name; command = [string]$_.Command }
    })
    $payload = [pscustomobject]@{ version = 1; commands = $items }
    $json = $payload | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($script:DataPath, $json + "`r`n", [Text.UTF8Encoding]::new($false))
}

function Get-MinecraftProcess {
    $found = @()
    foreach ($p in @(Get-Process -Name java, javaw -ErrorAction SilentlyContinue)) {
        $isMc = $false
        try {
            $ci = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [string]$p.Id)
            $cl = ''
            if ($ci) { $cl = [string]$ci.CommandLine }
            if ($cl -match 'net\.minecraft\.client\.main\.Main' -or $cl -match '-{2}gameDir') { $isMc = $true }
        } catch { }
        if (-not $isMc -and $p.MainWindowTitle -match 'Minecraft') { $isMc = $true }
        if (-not $isMc) { continue }
        try { $p.Refresh() } catch { }
        if ($p.MainWindowHandle.ToInt64() -eq 0) { continue }
        $start = $null
        try { $start = $p.StartTime } catch { }
        $found += [pscustomobject]@{ Id = [int]$p.Id; Handle = $p.MainWindowHandle; Title = [string]$p.MainWindowTitle; Start = $start }
    }
    if ($found.Count -eq 0) { return $null }
    return ($found | Sort-Object -Property @{ Expression = 'Start'; Descending = $true } | Select-Object -First 1)
}

function Get-MinecraftProcessIds {
    $ids = @()
    foreach ($p in @(Get-Process -Name java, javaw -ErrorAction SilentlyContinue)) {
        $isMc = $false
        try {
            $ci = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [string]$p.Id)
            $cl = ''
            if ($ci) { $cl = [string]$ci.CommandLine }
            if ($cl -match 'net\.minecraft\.client\.main\.Main' -or $cl -match '-{2}gameDir') { $isMc = $true }
        } catch { }
        if (-not $isMc -and $p.MainWindowTitle -match 'Minecraft') { $isMc = $true }
        if ($isMc) { $ids += [int]$p.Id }
    }
    return $ids
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PCLCommandNative {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public POINT ptScreenPos; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CURSORINFO pci);
}
'@

function Wait-ForMinecraftForeground([int[]]$processIds) {
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $h = [PCLCommandNative]::GetForegroundWindow()
        if ($h.ToInt64() -ne 0) {
            $procId = [uint32]0
            [void][PCLCommandNative]::GetWindowThreadProcessId($h, [ref]$procId)
            if ($processIds -contains [int]$procId) {
                return [pscustomobject]@{ Id = [int]$procId; Handle = $h }
            }
        }
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Test-MinecraftProcess([int]$processId) {
    $p = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    $isMc = $false
    try {
        $ci = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [string]$processId)
        $cl = ''
        if ($ci) { $cl = [string]$ci.CommandLine }
        if ($cl -match 'net\.minecraft\.client\.main\.Main' -or $cl -match '-{2}gameDir') { $isMc = $true }
    } catch { }
    if (-not $isMc) {
        try { $p.Refresh() } catch { }
        if ($p.MainWindowTitle -match 'Minecraft') { $isMc = $true }
    }
    return $isMc
}

function Update-TargetLabel {
    if ($null -eq $targetLabel) { return }
    if ($null -eq $script:TargetWindow) {
        $targetLabel.Text = T 'target_none'
        return
    }
    $name = [string]$script:TargetWindow.Title
    if (-not $name) { $name = 'PID ' + [string]$script:TargetWindow.Id }
    $text = Format-Text 'target_bound' $name
    if ($script:TargetShowSuccess) { $text += ' ' + (T 'recognized') }
    $targetLabel.Text = $text
}

function Show-TargetRecognized {
    if ($null -eq $targetLabel) { return }
    $script:TargetShowSuccess = $true
    Update-TargetLabel
    if ($null -ne $script:TargetLabelTimer) {
        $script:TargetLabelTimer.Stop()
        $script:TargetLabelTimer.Start()
    }
}

function Reset-TargetWindow {
    $script:TargetWindow = $null
    $script:TargetShowSuccess = $false
    if ($null -ne $script:TargetLabelTimer) { $script:TargetLabelTimer.Stop() }
    Update-TargetLabel
}

function Get-TargetWindow {
    if ($null -eq $script:TargetWindow) { return $null }
    $target = $script:TargetWindow
    if (-not (Test-MinecraftProcess $target.Id)) {
        Reset-TargetWindow
        return $null
    }
    $alive = $false
    try { $alive = [PCLCommandNative]::IsWindow($target.Handle) } catch { }
    if (-not $alive) {
        try {
            $p = Get-Process -Id $target.Id -ErrorAction SilentlyContinue
            if ($p) {
                try { $p.Refresh() } catch { }
                if ($p.MainWindowHandle.ToInt64() -ne 0) {
                    $target.Handle = $p.MainWindowHandle
                    $target.Title = [string]$p.MainWindowTitle
                    $alive = $true
                }
            }
        } catch { }
    }
    if (-not $alive) {
        Reset-TargetWindow
        return $null
    }
    try {
        $p = Get-Process -Id $target.Id -ErrorAction SilentlyContinue
        if ($p) {
            try { $p.Refresh() } catch { }
            $target.Title = [string]$p.MainWindowTitle
        }
    } catch { }
    Show-TargetRecognized
    return $target
}

function Test-CursorVisible {
    $ci = New-Object PCLCommandNative+CURSORINFO
    $ci.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($ci)
    if (-not [PCLCommandNative]::GetCursorInfo([ref]$ci)) { return $false }
    return (($ci.flags -band 1) -ne 0)
}

function Test-InGameWindow($target) {
    if ($null -eq $target) { return $false }
    $p = Get-Process -Id $target.Id -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    try { $p.Refresh() } catch { }
    $title = [string]$p.MainWindowTitle
    if (-not $title) { return $false }
    if ($title -notmatch '\s-\s') { return $false }
    $target.Title = $title
    return $true
}

function Bind-GameWindow([switch]$ResetFirst) {
    if ($ResetFirst) {
        Reset-TargetWindow
    }
    $ids = @(Get-MinecraftProcessIds)
    if ($ids.Count -eq 0) {
        $script:status.Text = (T 'no_game')
        return $null
    }
    $script:status.Text = (T 'click_game')
    [Windows.Forms.Application]::DoEvents()
    $found = Wait-ForMinecraftForeground $ids
    if ($null -eq $found) {
        $script:status.Text = (T 'focus_failed')
        return $null
    }
    $title = ''
    try {
        $p = Get-Process -Id $found.Id -ErrorAction SilentlyContinue
        if ($p) { try { $p.Refresh() } catch { }; $title = [string]$p.MainWindowTitle }
    } catch { }
    $script:TargetWindow = [pscustomobject]@{
        Id = [int]$found.Id
        Handle = $found.Handle
        Title = $title
    }
    Show-TargetRecognized
    $show = $title
    if (-not $show) { $show = 'PID ' + [string]$found.Id }
    $script:status.Text = (Format-Text 'target_bound' $show)
    return $script:TargetWindow
}

function Test-TargetForeground($target) {
    if ($null -eq $target) { return $false }
    $fg = [PCLCommandNative]::GetForegroundWindow()
    return ($fg.ToInt64() -eq $target.Handle.ToInt64())
}

function Activate-TargetWindow($target) {
    if ($null -eq $target) { return $false }
    $handle = $target.Handle
    try {
        if (-not [PCLCommandNative]::IsWindow($handle)) { return $false }
    } catch {
        return $false
    }
    try { [void][PCLCommandNative]::ShowWindowAsync($handle, 9) } catch { }
    if (Test-TargetForeground $target) { return $true }
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.AppActivate([int]$target.Id)
    } catch { }
    try { [void][PCLCommandNative]::SetForegroundWindow($handle) } catch { }
    Start-Sleep -Milliseconds 350
    if (Test-TargetForeground $target) { return $true }
    try {
        $fg = [PCLCommandNative]::GetForegroundWindow()
        $fgPid = [uint32]0
        $targetPid = [uint32]0
        $fgThread = [PCLCommandNative]::GetWindowThreadProcessId($fg, [ref]$fgPid)
        $targetThread = [PCLCommandNative]::GetWindowThreadProcessId($handle, [ref]$targetPid)
        if ($fgThread -ne 0 -and $targetThread -ne 0) {
            [void][PCLCommandNative]::AttachThreadInput($fgThread, $targetThread, $true)
            [void][PCLCommandNative]::SetForegroundWindow($handle)
            [void][PCLCommandNative]::AttachThreadInput($fgThread, $targetThread, $false)
        }
    } catch { }
    Start-Sleep -Milliseconds 350
    return (Test-TargetForeground $target)
}

function Close-GameGui($target) {
    for ($i = 0; $i -lt 4; $i++) {
        if (-not (Test-TargetForeground $target)) { return $false }
        if (-not (Test-InGameWindow $target)) { return $false }
        if (-not (Test-CursorVisible)) { return $true }
        [Windows.Forms.SendKeys]::SendWait('{ESC}')
        Start-Sleep -Milliseconds 320
    }
    if (-not (Test-TargetForeground $target)) { return $false }
    if (-not (Test-InGameWindow $target)) { return $false }
    return (-not (Test-CursorVisible))
}

function Confirm-GameReady($target) {
    for ($i = 0; $i -lt 3; $i++) {
        if (-not (Test-TargetForeground $target)) { return $false }
        if (-not (Test-InGameWindow $target)) { return $false }
        if (Test-CursorVisible) { return $false }
        Start-Sleep -Milliseconds 140
    }
    return $true
}

function Send-GameCommand([string]$command) {
    $target = Get-TargetWindow
    $newTarget = $false
    if ($null -eq $target) {
        $target = Bind-GameWindow
        if ($null -eq $target) {
            $script:PendingRun = $null
            return
        }
        $newTarget = $true
        $script:PendingRun = $null
    }
    if (-not (Test-InGameWindow $target)) {
        $script:PendingRun = $null
        $script:status.Text = (T 'not_in_game')
        return
    }

    $now = Get-Date
    $confirmed = $false
    if (-not $newTarget -and $null -ne $script:PendingRun) {
        if ($script:PendingRun.Command -eq $command -and ($now - $script:PendingRun.Time).TotalSeconds -le 10) {
            $confirmed = $true
        }
    }
    if (-not $confirmed) {
        $script:PendingRun = [pscustomobject]@{ Command = $command; Time = $now }
        $script:status.Text = (T 'confirm_run')
        return
    }
    $script:PendingRun = $null

    if (-not (Activate-TargetWindow $target)) {
        $script:status.Text = (T 'focus_failed')
        return
    }
    if (-not (Test-InGameWindow $target)) {
        $script:status.Text = (T 'not_in_game')
        return
    }
    if (Test-CursorVisible) {
        $script:status.Text = (T 'gui_closing')
        [Windows.Forms.Application]::DoEvents()
    }
    if (-not (Close-GameGui $target)) {
        $script:status.Text = (T 'gui_failed')
        return
    }
    if (-not (Confirm-GameReady $target)) {
        $script:status.Text = (T 'gui_failed')
        return
    }

    $oldClipboard = $null
    try { $oldClipboard = [Windows.Forms.Clipboard]::GetDataObject() } catch { }
    try {
        [Windows.Forms.Clipboard]::SetText($command)
        [Windows.Forms.SendKeys]::SendWait('/')
        Start-Sleep -Milliseconds 160
        [Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 160
        [Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Start-Sleep -Milliseconds 260
        $script:status.Text = (Format-Text 'sent' ([string]$target.Id))
    } catch {
        $msg = $_.Exception.Message
        $script:status.Text = (Format-Text 'send_failed' $msg)
    } finally {
        try {
            if ($null -ne $oldClipboard) { [Windows.Forms.Clipboard]::SetDataObject($oldClipboard, $true) }
            else { [Windows.Forms.Clipboard]::Clear() }
        } catch { }
    }
}

Load-CommandData

[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = T 'title'
$form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object Drawing.Size(780, 540)
$form.BackColor = [Drawing.Color]::FromArgb(30, 30, 36)
$form.ForeColor = [Drawing.Color]::FromArgb(242, 242, 246)
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
$form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi

function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [float]$size, [Drawing.Color]$color) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object Drawing.Point($x, $y)
    $l.Size = New-Object Drawing.Size($w, $h)
    $l.Font = New-Object Drawing.Font('Microsoft YaHei UI', $size)
    $l.ForeColor = $color
    $l.BackColor = [Drawing.Color]::Transparent
    return $l
}
function Style-Button($b, [Drawing.Color]$back) {
    $b.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $back
    $b.ForeColor = [Drawing.Color]::White
    $b.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
    $b.Cursor = [Windows.Forms.Cursors]::Hand
}

$title = New-Label (T 'title') 18 14 744 30 17 ([Drawing.Color]::FromArgb(255, 255, 255))
$title.Font = New-Object Drawing.Font('Microsoft YaHei UI', 17, [Drawing.FontStyle]::Bold)
$form.Controls.Add($title)
$subtitle = New-Label (T 'subtitle') 18 48 744 22 9 ([Drawing.Color]::FromArgb(170, 175, 185))
$form.Controls.Add($subtitle)
$listLabel = New-Label (T 'list') 18 82 300 20 9 ([Drawing.Color]::FromArgb(210, 215, 225))
$form.Controls.Add($listLabel)

$list = New-Object Windows.Forms.ListBox
$list.Location = New-Object Drawing.Point(18, 105)
$list.Size = New-Object Drawing.Size(300, 350)
$list.BackColor = [Drawing.Color]::FromArgb(42, 42, 50)
$list.ForeColor = [Drawing.Color]::FromArgb(245, 245, 250)
$list.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
$list.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9.5)
$list.IntegralHeight = $false
$form.Controls.Add($list)

$nameLabel = New-Label (T 'name') 340 82 420 20 9 ([Drawing.Color]::FromArgb(210, 215, 225))
$form.Controls.Add($nameLabel)
$nameBox = New-Object Windows.Forms.TextBox
$nameBox.Location = New-Object Drawing.Point(340, 105)
$nameBox.Size = New-Object Drawing.Size(420, 28)
$nameBox.BackColor = [Drawing.Color]::FromArgb(42, 42, 50)
$nameBox.ForeColor = [Drawing.Color]::FromArgb(245, 245, 250)
$nameBox.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
$nameBox.MaxLength = 80
$form.Controls.Add($nameBox)

$commandLabel = New-Label (T 'command') 340 145 420 20 9 ([Drawing.Color]::FromArgb(210, 215, 225))
$form.Controls.Add($commandLabel)
$commandBox = New-Object Windows.Forms.TextBox
$commandBox.Location = New-Object Drawing.Point(340, 168)
$commandBox.Size = New-Object Drawing.Size(420, 180)
$commandBox.Multiline = $true
$commandBox.AcceptsReturn = $true
$commandBox.ScrollBars = [Windows.Forms.ScrollBars]::Vertical
$commandBox.BackColor = [Drawing.Color]::FromArgb(42, 42, 50)
$commandBox.ForeColor = [Drawing.Color]::FromArgb(245, 245, 250)
$commandBox.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
$commandBox.MaxLength = 512
$form.Controls.Add($commandBox)
$hintLabel = New-Label (T 'hint') 340 356 420 54 8.5 ([Drawing.Color]::FromArgb(165, 172, 184))
$form.Controls.Add($hintLabel)

$targetLabel = New-Label (T 'target_none') 340 414 300 22 8.5 ([Drawing.Color]::FromArgb(185, 195, 210))
$targetLabel.AutoEllipsis = $true
$form.Controls.Add($targetLabel)

$script:TargetLabelTimer = New-Object Windows.Forms.Timer
$script:TargetLabelTimer.Interval = 3000
$script:TargetLabelTimer.Add_Tick({
    $script:TargetLabelTimer.Stop()
    $script:TargetShowSuccess = $false
    Update-TargetLabel
})

$selectWindowButton = New-Object Windows.Forms.Button
$selectWindowButton.Text = T 'select_window'
$selectWindowButton.Location = New-Object Drawing.Point(650, 409)
$selectWindowButton.Size = New-Object Drawing.Size(110, 28)
Style-Button $selectWindowButton ([Drawing.Color]::FromArgb(55, 55, 66))
$form.Controls.Add($selectWindowButton)

$addButton = New-Object Windows.Forms.Button
$addButton.Text = T 'add'
$addButton.Location = New-Object Drawing.Point(18, 465)
$addButton.Size = New-Object Drawing.Size(90, 32)
Style-Button $addButton ([Drawing.Color]::FromArgb(55, 55, 66))
$form.Controls.Add($addButton)

$deleteButton = New-Object Windows.Forms.Button
$deleteButton.Text = T 'delete'
$deleteButton.Location = New-Object Drawing.Point(116, 465)
$deleteButton.Size = New-Object Drawing.Size(90, 32)
Style-Button $deleteButton ([Drawing.Color]::FromArgb(55, 55, 66))
$form.Controls.Add($deleteButton)

$saveButton = New-Object Windows.Forms.Button
$saveButton.Text = T 'save'
$saveButton.Location = New-Object Drawing.Point(340, 465)
$saveButton.Size = New-Object Drawing.Size(100, 32)
Style-Button $saveButton ([Drawing.Color]::FromArgb(55, 55, 66))
$form.Controls.Add($saveButton)

$runButton = New-Object Windows.Forms.Button
$runButton.Text = T 'run'
$runButton.Location = New-Object Drawing.Point(450, 465)
$runButton.Size = New-Object Drawing.Size(110, 32)
Style-Button $runButton ([Drawing.Color]::FromArgb(55, 105, 205))
$form.Controls.Add($runButton)

$closeButton = New-Object Windows.Forms.Button
$closeButton.Text = T 'close'
$closeButton.Location = New-Object Drawing.Point(650, 465)
$closeButton.Size = New-Object Drawing.Size(110, 32)
Style-Button $closeButton ([Drawing.Color]::FromArgb(55, 55, 66))
$form.Controls.Add($closeButton)

$status = New-Label (T 'ready') 18 510 742 20 8.5 ([Drawing.Color]::FromArgb(170, 175, 185))
$form.Controls.Add($status)

function Refresh-List([int]$select = -1) {
    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        foreach ($c in $script:Commands) { [void]$list.Items.Add([string]$c.Name) }
    } finally {
        $list.EndUpdate()
    }
    if ($script:Commands.Count -eq 0) {
        $script:CurrentIndex = -1
        $status.Text = T 'empty'
    } elseif ($select -ge 0 -and $select -lt $list.Items.Count) {
        $list.SelectedIndex = $select
    } else {
        $list.ClearSelected()
        $status.Text = T 'ready'
    }
}
function Load-Editor([int]$index) {
    if ($index -lt 0 -or $index -ge $script:Commands.Count) { return }
    $script:CurrentIndex = $index
    $nameBox.Text = [string]$script:Commands[$index].Name
    $commandBox.Text = [string]$script:Commands[$index].Command
    $status.Text = T 'ready'
}
function Clear-Editor {
    $script:CurrentIndex = -1
    $list.ClearSelected()
    $nameBox.Clear()
    $commandBox.Clear()
    $nameBox.Focus()
    $status.Text = T 'empty'
}
function Get-EditorCommand {
    $name = $nameBox.Text.Trim()
    $cmd = Normalize-Command $commandBox.Text
    if (-not $name) {
        [void][Windows.Forms.MessageBox]::Show((T 'name_required'), (T 'title'), [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)
        return $null
    }
    if (-not $cmd) {
        [void][Windows.Forms.MessageBox]::Show((T 'command_required'), (T 'title'), [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)
        return $null
    }
    $nameBox.Text = $name
    $commandBox.Text = $cmd
    return [pscustomobject]@{ Name = $name; Command = $cmd }
}
function Save-Editor {
    $entry = Get-EditorCommand
    if ($null -eq $entry) { return $false }
    if ($script:CurrentIndex -ge 0 -and $script:CurrentIndex -lt $script:Commands.Count) {
        $script:Commands[$script:CurrentIndex] = $entry
    } else {
        [void]$script:Commands.Add($entry)
        $script:CurrentIndex = $script:Commands.Count - 1
    }
    try {
        Save-CommandData
    } catch {
        [void][Windows.Forms.MessageBox]::Show((Format-Text 'send_failed' $_.Exception.Message), (T 'title'), [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
    Refresh-List $script:CurrentIndex
    $status.Text = T 'saved'
    return $true
}

$list.Add_SelectedIndexChanged({
    if ($list.SelectedIndex -ge 0) { Load-Editor $list.SelectedIndex }
})
$addButton.Add_Click({ Clear-Editor })
$deleteButton.Add_Click({
    if ($script:CurrentIndex -lt 0 -or $script:CurrentIndex -ge $script:Commands.Count) { return }
    $name = [string]$script:Commands[$script:CurrentIndex].Name
    $answer = [Windows.Forms.MessageBox]::Show((Format-Text 'confirm_delete' $name), (T 'title'), [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    $script:Commands.RemoveAt($script:CurrentIndex)
    try { Save-CommandData } catch { }
    $script:CurrentIndex = -1
    Refresh-List
    Clear-Editor
})
$saveButton.Add_Click({ [void](Save-Editor) })
$selectWindowButton.Add_Click({
    $script:PendingRun = $null
    [void](Bind-GameWindow -ResetFirst)
})
$runButton.Add_Click({
    if (-not (Save-Editor)) { return }
    Send-GameCommand ([string]$script:Commands[$script:CurrentIndex].Command)
})
$closeButton.Add_Click({ $form.Close() })
$form.AcceptButton = $saveButton
$form.CancelButton = $closeButton

Update-TargetLabel
Refresh-List
[void]$form.ShowDialog()
$form.Dispose()
