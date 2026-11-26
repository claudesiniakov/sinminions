// Создано scripts/gen-l10n.py из l10n/strings.tsv — правьте TSV и запускайте скрипт.
import Foundation

/// Переводы строк интерфейса и реплик: ключ — русский текст.
enum Translations {
    static let en = column(1)
    static let de = column(2)
    static let es = column(3)

    private static func column(_ index: Int) -> [String: String] {
        var result: [String: String] = [:]
        for line in table.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 4 else { continue }
            result[unescape(parts[0])] = unescape(parts[index])
        }
        return result
    }

    private static func unescape(_ text: Substring) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
    }

    private static let table = #"""
 (код %@)	 (code %@)	 (Code %@)	 (código %@)
 (недостаточно для запросов)	 (not enough for requests)	 (reicht nicht für Anfragen)	 (insuficiente para solicitudes)
 (пусто — оставить прежний)	 (empty — keep the current one)	 (leer — bisherigen behalten)	 (vacío — mantener el actual)
 · без лимитов	 · no limits	 · ohne Limits	 · sin límites
 · доступна %@	 · %@ available	 · %@ verfügbar	 · %@ disponible
 · не в чате	 · not in chat	 · nicht im Chat	 · fuera del chat
 · обновлений нет	 · up to date	 · aktuell	 · al día
 · проверка…	 · checking…	 · wird geprüft…	 · comprobando…
 ГБ	 GB	 GB	 GB
 КБ	 KB	 KB	 KB
 КБ/с	 KB/s	 KB/s	 KB/s
 МБ	 MB	 MB	 MB
 МБ/с	 MB/s	 MB/s	 MB/s
 МЛН	 M	 MIO	 M
 ТОК.	 TOK.	 TOK.	 TOK.
 ТЫС	 K	 TSD	 K
%@ // МОНИТОР	%@ // MONITOR	%@ // MONITOR	%@ // MONITOR
%@ завершился с кодом %@	%@ exited with code %@	%@ wurde mit Code %@ beendet	%@ terminó con el código %@
%@ не ответил за %@ с	%@ did not respond within %@ s	%@ hat nicht innerhalb von %@ s geantwortet	%@ no respondió en %@ s
%@ → код %@	%@ → code %@	%@ → Code %@	%@ → código %@
%@: отказ — %@; без отзыва — %@; цепочка из %@ сертификатов	%@: rejected — %@; without revocation — %@; chain of %@ certificates	%@: abgelehnt — %@; ohne Widerruf — %@; Kette aus %@ Zertifikaten	%@: rechazado — %@; sin revocación — %@; cadena de %@ certificados
%@: проверка пройдена	%@: check passed	%@: Prüfung bestanden	%@: verificación superada
%@: пройдена без проверки отзыва; первая попытка не прошла: %@	%@: passed without revocation check; first attempt failed: %@	%@: ohne Widerrufsprüfung bestanden; erster Versuch fehlgeschlagen: %@	%@: superada sin comprobar revocación; el primer intento falló: %@
%@д 	%@d 	%@T 	%@d 
%@м	%@m	%@m	%@m
%@ч 	%@h 	%@h 	%@h 
. Кнопка «Повторить» откроет страницу релиза.	. The “Retry” button will open the release page.	. Die Taste „Wiederholen“ öffnet die Release-Seite.	. El botón «Reintentar» abrirá la página de la versión.
. Проверка доверия: 	. Trust check: 	. Vertrauensprüfung: 	. Comprobación de confianza: 
/analytics — ОКНО АНАЛИТИКИ ТОКЕНОВ ПО МОДЕЛЯМ	/analytics — TOKEN ANALYTICS WINDOW BY MODEL	/analytics — FENSTER MIT TOKEN-ANALYSE NACH MODELL	/analytics — VENTANA DE ANÁLISIS DE TOKENS POR MODELO
/clear — ОЧИСТИТЬ ЧАТ	/clear — CLEAR CHAT	/clear — CHAT LEEREN	/clear — BORRAR CHAT
/coffee — НЕ ДАВАТЬ НОУТБУКУ УСНУТЬ (ВКЛ/ВЫКЛ), У ПРИЗРАКА ЧАШКА КОФЕ	/coffee — KEEP THE LAPTOP AWAKE (ON/OFF), THE GHOST HOLDS A CUP OF COFFEE	/coffee — LAPTOP WACH HALTEN (AN/AUS), DER GEIST HÄLT EINE TASSE KAFFEE	/coffee — NO DEJAR QUE EL PORTÁTIL SE DUERMA (SÍ/NO), EL FANTASMA TOMA CAFÉ
/corner — ВЕРНУТЬ В УГОЛ	/corner — BACK TO THE CORNER	/corner — ZURÜCK IN DIE ECKE	/corner — VOLVER A LA ESQUINA
/help — ЭТА СПРАВКА	/help — THIS HELP	/help — DIESE HILFE	/help — ESTA AYUDA
/hide — СКРЫТЬ ПРИЗРАКА	/hide — HIDE THE GHOST	/hide — GEIST AUSBLENDEN	/hide — OCULTAR EL FANTASMA
/next, /prev — СЛЕДУЮЩЕЕ И ПРЕДЫДУЩЕЕ ПОДКЛЮЧЕНИЕ	/next, /prev — NEXT AND PREVIOUS CONNECTION	/next, /prev — NÄCHSTE UND VORHERIGE VERBINDUNG	/next, /prev — CONEXIÓN SIGUIENTE Y ANTERIOR
/reset — СБРОСИТЬ РАСКЛАДКУ ОКОН	/reset — RESET WINDOW LAYOUT	/reset — FENSTERANORDNUNG ZURÜCKSETZEN	/reset — RESTABLECER LA DISPOSICIÓN DE VENTANAS
/settings — ОТКРЫТЬ НАСТРОЙКИ	/settings — OPEN SETTINGS	/settings — EINSTELLUNGEN ÖFFNEN	/settings — ABRIR AJUSTES
/shell — ОБЫЧНЫЙ ТЕРМИНАЛ ZSH (ВКЛ/ВЫКЛ), EXIT — НАЗАД	/shell — REGULAR ZSH TERMINAL (ON/OFF), EXIT — BACK	/shell — NORMALES ZSH-TERMINAL (AN/AUS), EXIT — ZURÜCK	/shell — TERMINAL ZSH NORMAL (SÍ/NO), EXIT — VOLVER
/sing — СПЕТЬ ГИМН (ПОЁТ СТРАЖ ab)	/sing — SING THE ANTHEM (THE AB GUARDIAN SINGS)	/sing — DIE HYMNE SINGEN (DER WÄCHTER AB SINGT)	/sing — CANTAR EL HIMNO (CANTA EL GUARDIÁN AB)
/sleep — УСЫПИТЬ НА 1 ЧАС	/sleep — SLEEP FOR 1 HOUR	/sleep — 1 STUNDE SCHLAFEN	/sleep — DORMIR 1 HORA
/unlock, /lock — РАЗБЛОКИРОВАТЬ И ЗАБЛОКИРОВАТЬ ОКНА	/unlock, /lock — UNLOCK AND LOCK WINDOWS	/unlock, /lock — FENSTER ENTSPERREN UND SPERREN	/unlock, /lock — DESBLOQUEAR Y BLOQUEAR VENTANAS
100,5 ТЫС	100.5 K	100,5 TSD	100,5 K
3 МЛН	3 M	3 MIO	3 M
30 ДНЕЙ	30 DAYS	30 TAGE	30 DÍAS
7 ДНЕЙ	7 DAYS	7 TAGE	7 DÍAS
; запасной путь: 	; fallback: 	; Ausweichweg: 	; alternativa: 
API-ключ	API key	API-Schlüssel	Clave API
API-ключ создаётся в консоли Anthropic (platform.claude.com → API keys). Проверка показывает, сколько моделей доступно ключу. Остаток по ключу Anthropic не отдаёт, в блоке «Лимиты» будет прочерк. Нужной модели нет в списке — выберите «Другая…».	Create an API key in the Anthropic console (platform.claude.com → API keys). The check shows how many models the key can use. Anthropic does not report the balance for a key, so “Limits” shows a dash. Model not listed? Choose “Other…”.	Den API-Schlüssel erstellen Sie in der Anthropic-Konsole (platform.claude.com → API keys). Die Prüfung zeigt, wie viele Modelle der Schlüssel nutzen kann. Anthropic meldet kein Guthaben pro Schlüssel, unter „Limits“ steht ein Strich. Modell nicht in der Liste? Wählen Sie „Andere…“.	La clave API se crea en la consola de Anthropic (platform.claude.com → API keys). La comprobación muestra cuántos modelos puede usar la clave. Anthropic no informa del saldo por clave: en «Límites» aparecerá un guion. ¿No está el modelo? Elija «Otro…».
API-ключ создаётся на platform.deepseek.com/api_keys. Запросы идут без режима размышления — так ответы короче и быстрее. Проверка показывает баланс. Нужной модели нет в списке — выберите «Другая…» и введите идентификатор.	Create an API key at platform.deepseek.com/api_keys. Requests go without thinking mode, so answers are shorter and faster. The check shows the balance. Model not listed? Choose “Other…” and enter its ID.	Den API-Schlüssel erstellen Sie unter platform.deepseek.com/api_keys. Anfragen laufen ohne Denkmodus – Antworten sind kürzer und schneller. Die Prüfung zeigt das Guthaben. Modell nicht in der Liste? Wählen Sie „Andere…“ und geben Sie die Kennung ein.	La clave API se crea en platform.deepseek.com/api_keys. Las solicitudes van sin modo de razonamiento: respuestas más cortas y rápidas. La comprobación muestra el saldo. ¿No está el modelo? Elija «Otro…» e introduzca el identificador.
API-ключ — на aistudio.google.com/apikey. Запросы идут на OpenAI-совместимый адрес Google. Остаток не отдаётся: лимиты смотрите в AI Studio. Нужной модели нет в списке — выберите «Другая…».	API key — at aistudio.google.com/apikey. Requests go to Google’s OpenAI-compatible endpoint. The balance is not reported: check limits in AI Studio. Model not listed? Choose “Other…”.	API-Schlüssel – unter aistudio.google.com/apikey. Anfragen gehen an die OpenAI-kompatible Adresse von Google. Kein Guthaben abrufbar: Limits sehen Sie in AI Studio. Modell nicht in der Liste? Wählen Sie „Andere…“.	Clave API: en aistudio.google.com/apikey. Las solicitudes van a la dirección compatible con OpenAI de Google. No se informa del saldo: consulte los límites en AI Studio. ¿No está el modelo? Elija «Otro…».
API-ключ — на console.x.ai/team/default/api-keys. Остаток по обычному ключу xAI не отдаёт (он доступен через отдельный ключ управления). Нужной модели нет в списке — выберите «Другая…».	API key — at console.x.ai/team/default/api-keys. xAI does not report the balance for a regular key (it is available via a separate management key). Model not listed? Choose “Other…”.	API-Schlüssel – unter console.x.ai/team/default/api-keys. xAI meldet für einen normalen Schlüssel kein Guthaben (nur über einen separaten Verwaltungsschlüssel). Modell nicht in der Liste? Wählen Sie „Andere…“.	Clave API: en console.x.ai/team/default/api-keys. xAI no informa del saldo con una clave normal (está disponible con una clave de gestión aparte). ¿No está el modelo? Elija «Otro…».
API-ключ — на platform.openai.com/api-keys. Системная подсказка уходит как developer, как требуют новые модели. Остаток по ключу OpenAI не отдаёт: смотрите в личном кабинете. Нужной модели нет в списке — выберите «Другая…».	API key — at platform.openai.com/api-keys. The system prompt is sent as developer, as new models require. OpenAI does not report the balance for a key: check your account dashboard. Model not listed? Choose “Other…”.	API-Schlüssel – unter platform.openai.com/api-keys. Die Systemanweisung wird als developer gesendet, wie neue Modelle es verlangen. OpenAI meldet kein Guthaben pro Schlüssel: siehe Ihr Konto. Modell nicht in der Liste? Wählen Sie „Andere…“.	Clave API: en platform.openai.com/api-keys. La instrucción del sistema se envía como developer, como exigen los modelos nuevos. OpenAI no informa del saldo por clave: consúltelo en su cuenta. ¿No está el modelo? Elija «Otro…».
F: призрак Moth, терминал и монитор в стиле Fallout.	F: Moth the ghost, Fallout-style terminal and monitor.	F: der Geist Moth, Terminal und Monitor im Fallout-Stil.	F: el fantasma Moth, terminal y monitor al estilo Fallout.
SinMinions: кофе	SinMinions: coffee	SinMinions: Kaffee	SinMinions: café
[ЗАКРЫТЬ]	[CLOSE]	[SCHLIESSEN]	[CERRAR]
[ЗАМОК ВКЛ]	[LOCK ON]	[SPERRE AN]	[BLOQUEO SÍ]
[ЗАМОК ВЫКЛ]	[LOCK OFF]	[SPERRE AUS]	[BLOQUEO NO]
ab: золотой страж, терминал и монитор в стиле Вархаммера.	ab: the golden guardian, Warhammer-style terminal and monitor.	ab: der goldene Wächter, Terminal und Monitor im Warhammer-Stil.	ab: el guardián dorado, terminal y monitor al estilo Warhammer.
curl не запустился: 	curl failed to start: 	curl ließ sich nicht starten: 	curl no se inició: 
curl: %@ (код %@)	curl: %@ (code %@)	curl: %@ (Code %@)	curl: %@ (código %@)
echo привет из zsh && sw_vers	echo hello from zsh && sw_vers	echo hallo aus zsh && sw_vers	echo hola desde zsh && sw_vers
zsh: не удалось запустить: %@	zsh: failed to start: %@	zsh: Start fehlgeschlagen: %@	zsh: no se pudo iniciar: %@
АКВИЛА	AQUILA	AQUILA	ÁQUILA
АНАЛИТИКА ТОКЕНОВ	TOKEN ANALYTICS	TOKEN-ANALYSE	ANÁLISIS DE TOKENS
АНАЛИТИКА ТОКЕНОВ ОТКРЫТА В ОТДЕЛЬНОМ ОКНЕ	TOKEN ANALYTICS OPENED IN A SEPARATE WINDOW	TOKEN-ANALYSE IN EINEM EIGENEN FENSTER GEÖFFNET	ANÁLISIS DE TOKENS ABIERTO EN UNA VENTANA APARTE
АУСПЕКС	AUSPEX	AUSPEX	AUSPEX
Аналитика токенов	Token analytics	Token-Analyse	Análisis de tokens
Архив содержит другое приложение	The archive contains a different app	Das Archiv enthält eine andere App	El archivo contiene otra aplicación
БАТАРЕЯ	BATTERY	AKKU	BATERÍA
БАТАРЕЯ ⚡	BATTERY ⚡	AKKU ⚡	BATERÍA ⚡
БЫСТРО	FAST	SCHNELL	RÁPIDO
В РАБОТЕ	UPTIME	LAUFZEIT	EN MARCHA
В архиве не найдено приложение SinMinions	The SinMinions app was not found in the archive	Im Archiv wurde keine SinMinions-App gefunden	No se encontró la aplicación SinMinions en el archivo
В релизе нет архива SinMinions.zip	The release has no SinMinions.zip archive	Das Release enthält kein Archiv SinMinions.zip	La versión no incluye el archivo SinMinions.zip
В релизе нет контрольной суммы — установка отменена	The release has no checksum — installation cancelled	Das Release hat keine Prüfsumme – Installation abgebrochen	La versión no tiene suma de verificación: instalación cancelada
ВВЕДИТЕ СООБЩЕНИЕ. /clear — ОЧИСТИТЬ ИСТОРИЮ.	TYPE A MESSAGE. /clear — CLEAR HISTORY.	NACHRICHT EINGEBEN. /clear — VERLAUF LEEREN.	ESCRIBA UN MENSAJE. /clear — BORRAR HISTORIAL.
ВКЛ · ЭКРАН НЕ ГАСНЕТ	ON · SCREEN STAYS ON	AN · BILDSCHIRM BLEIBT AN	SÍ · LA PANTALLA NO SE APAGA
ВОДЯНОЙ ЧИП	WATER CHIP	WASSERCHIP	CHIP DE AGUA
ВОСПРИЯТИЕ	PERCEPTION	WAHRNEHMUNG	PERCEPCIÓN
ВСЕГО	TOTAL	GESAMT	TOTAL
ВХОД	INPUT	EINGABE	ENTRADA
ВЫНОСЛИВОСТЬ	ENDURANCE	AUSDAUER	AGUANTE
ВЫПОЛНЯЕТСЯ… CTRL+C ПРЕРВАТЬ · CTRL+D КОНЕЦ ВВОДА	RUNNING… CTRL+C INTERRUPT · CTRL+D END INPUT	LÄUFT… CTRL+C ABBRECHEN · CTRL+D EINGABE BEENDEN	EN CURSO… CTRL+C INTERRUMPIR · CTRL+D FIN DE ENTRADA
ВЫСОКИЙ	HIGH	HOCH	ALTO
Вернуть в угол	Back to the corner	Zurück in die Ecke	Volver a la esquina
Версия	Version	Version	Versión
Версия %@	Version %@	Version %@	Versión %@
Версия в архиве (%@) не совпадает с релизом %@	The version in the archive (%@) does not match release %@	Die Version im Archiv (%@) stimmt nicht mit Release %@ überein	La versión del archivo (%@) no coincide con la versión publicada %@
Вставить	Paste	Einsetzen	Pegar
Встроенный клиент не установил защищённое соединение	The built-in client could not establish a secure connection	Der integrierte Client konnte keine sichere Verbindung herstellen	El cliente integrado no pudo establecer una conexión segura
Выбрать всё	Select All	Alles auswählen	Seleccionar todo
Вырезать	Cut	Ausschneiden	Cortar
Выше в списке	Move up	Nach oben	Subir
ГОЛОЗАПИСЬ	HOLOTAPE	HOLOBAND	HOLOCINTA
ДЕТАЛЬНЫЙ	DETAILED	DETAILLIERT	DETALLADO
ДИСК	DISK	FESTPLATTE	DISCO
ДОЛЯ ОТВЕТА	ANSWER SHARE	ANTWORTANTEIL	CUOTA DE RESPUESTA
День	Day	Tag	Día
Добавить подключение…	Add connection…	Verbindung hinzufügen…	Añadir conexión…
Доступ запрещён	Access denied	Zugriff verweigert	Acceso denegado
Другая…	Other…	Andere…	Otro…
ЗАПРОС ПРЕРВАН	REQUEST INTERRUPTED	ANFRAGE ABGEBROCHEN	SOLICITUD INTERRUMPIDA
ЗАПРОСОВ: %@	REQUESTS: %@	ANFRAGEN: %@	SOLICITUDES: %@
ЗАСЫПАЕТ ЧЕРЕЗ %@ МИН	FALLS ASLEEP IN %@ MIN	SCHLÄFT IN %@ MIN EIN	SE DUERME EN %@ MIN
ЗАСЫПАЕТ ЧЕРЕЗ 5 МИН	FALLS ASLEEP IN 5 MIN	SCHLÄFT IN 5 MIN EIN	SE DUERME EN 5 MIN
ЗОЛОЧЁНЫЙ ЧЕРЕП	GILDED SKULL	VERGOLDETER SCHÄDEL	CRÁNEO DORADO
Заблокировать окна	Lock windows	Fenster sperren	Bloquear ventanas
Завершение приложения для замены	Quitting the app to replace it	App wird zum Ersetzen beendet	Cerrando la aplicación para reemplazarla
Завершить SinMinions	Quit SinMinions	SinMinions beenden	Salir de SinMinions
Загрузка %@	Downloading %@	Lade %@	Descargando %@
Загрузка %@… %@ %	Downloading %@… %@ %	Lade %@… %@ %	Descargando %@… %@ %
Загрузка не вернула файл	The download returned no file	Der Download lieferte keine Datei	La descarga no devolvió ningún archivo
Закрыть	Close	Schließen	Cerrar
Запрашивать и показывать лимиты	Request and show limits	Limits abfragen und anzeigen	Consultar y mostrar límites
Запрос токена отклонён, проверьте ключ	Token request rejected, check the key	Token-Anfrage abgelehnt, Schlüssel prüfen	Solicitud de token rechazada, revise la clave
Запускать при входе в систему	Launch at login	Beim Anmelden starten	Abrir al iniciar sesión
Засыпать при бездействии	Fall asleep when idle	Bei Inaktivität einschlafen	Dormirse por inactividad
ИНТЕЛЛЕКТ	INTELLIGENCE	INTELLIGENZ	INTELIGENCIA
ИП и юрлица, пакеты (GIGACHAT_API_B2B)	Businesses, prepaid packages (GIGACHAT_API_B2B)	Unternehmen, Pakete (GIGACHAT_API_B2B)	Empresas, paquetes (GIGACHAT_API_B2B)
ИП и юрлица, по факту (GIGACHAT_API_CORP)	Businesses, pay as you go (GIGACHAT_API_CORP)	Unternehmen, nach Verbrauch (GIGACHAT_API_CORP)	Empresas, pago por uso (GIGACHAT_API_CORP)
ИСТОРИЯ ЧАТА ОЧИЩЕНА	CHAT HISTORY CLEARED	CHATVERLAUF GELEERT	HISTORIAL DEL CHAT BORRADO
Играет в прятки: тает и выскакивает с «бу!»	Plays hide-and-seek: fades away and pops out with a “boo!”	Spielt Verstecken: verblasst und springt mit „Buh!“ hervor	Juega al escondite: se desvanece y aparece con un «¡bu!»
Играет на приставке рядом с телевизором	Plays a console next to a TV	Spielt Konsole neben einem Fernseher	Juega a la consola junto a una tele
Идентификатор модели	Model ID	Modellkennung	Identificador del modelo
Изменить	Edit	Bearbeiten	Editar
Иногда поёт гимн	Sometimes sings the anthem	Singt manchmal die Hymne	A veces canta el himno
Использовать в чате	Use in chat	Im Chat verwenden	Usar en el chat
Ищет реликвии Империума и находит их	Searches for relics of the Imperium and finds them	Sucht Reliquien des Imperiums und findet sie	Busca reliquias del Imperio y las encuentra
КЛАССИЧЕСКИЙ	CLASSIC	KLASSISCH	CLÁSICO
КОГИТАТОР	COGITATOR	COGITATOR	COGITADOR
КОФЕ	COFFEE	KAFFEE	CAFÉ
КОФЕ ДОПИТ: НОУТБУК СНОВА МОЖЕТ ЗАСНУТЬ	COFFEE FINISHED: THE LAPTOP CAN SLEEP AGAIN	KAFFEE AUSGETRUNKEN: DAS LAPTOP DARF WIEDER SCHLAFEN	CAFÉ TERMINADO: EL PORTÁTIL PUEDE VOLVER A DORMIR
КОФЕ: НЕ ДАЁТ НОУТБУКУ УСНУТЬ	COFFEE: KEEPS THE LAPTOP AWAKE	KAFFEE: HÄLT DAS LAPTOP WACH	CAFÉ: MANTIENE DESPIERTO EL PORTÁTIL
КОФЕ: НОУТБУК НЕ ЗАСНЁТ, ПОКА ВКЛЮЧЕНО	COFFEE: THE LAPTOP WON’T SLEEP WHILE THIS IS ON	KAFFEE: DAS LAPTOP SCHLÄFT NICHT, SOLANGE AKTIV	CAFÉ: EL PORTÁTIL NO SE DORMIRÁ MIENTRAS ESTÉ ACTIVO
КРИТИЧЕСКИЙ	CRITICAL	KRITISCH	CRÍTICO
КРЫШКА	BOTTLE CAP	KRONKORKEN	CHAPA
Ключ API не подходит	The API key is not valid	Der API-Schlüssel ist ungültig	La clave API no es válida
Ключ GigaChat не задан	GigaChat key is not set	GigaChat-Schlüssel fehlt	No se ha indicado la clave de GigaChat
Ключ авторизации	Authorization key	Autorisierungsschlüssel	Clave de autorización
Ключ авторизации не подходит: проверьте ключ и область доступа	The authorization key does not work: check the key and the access scope	Der Autorisierungsschlüssel passt nicht: Schlüssel und Zugriffsbereich prüfen	La clave de autorización no funciona: revise la clave y el ámbito de acceso
Ключ — это «Authorization data» из личного кабинета GigaChat API на developers.sber.ru. Модель GigaChat-3-Ultra доступна физлицам только по бесплатному пакету. Нужной модели нет в списке — выберите «Другая…» и введите идентификатор.	The key is the “Authorization data” from the GigaChat API dashboard at developers.sber.ru. GigaChat-3-Ultra is available to individuals only on the free package. Model not listed? Choose “Other…” and enter its ID.	Der Schlüssel sind die „Authorization data“ aus dem GigaChat-API-Konto auf developers.sber.ru. GigaChat-3-Ultra steht Privatpersonen nur im kostenlosen Paket zur Verfügung. Modell nicht in der Liste? Wählen Sie „Andere…“ und geben Sie die Kennung ein.	La clave es «Authorization data» del panel de GigaChat API en developers.sber.ru. GigaChat-3-Ultra solo está disponible para particulares con el paquete gratuito. ¿No está el modelo? Elija «Otro…» e introduzca el identificador.
Контрольная сумма архива не совпала — установка отменена	The archive checksum did not match — installation cancelled	Die Prüfsumme des Archivs stimmt nicht – Installation abgebrochen	La suma de verificación del archivo no coincide: instalación cancelada
Копировать	Copy	Kopieren	Copiar
ЛЕТОПИСЬ ТОКЕНОВ	CHRONICLE OF TOKENS	CHRONIK DER TOKENS	CRÓNICA DE TOKENS
ЛИМИТЫ	LIMITS	LIMITS	LÍMITES
ЛОВКОСТЬ	AGILITY	BEWEGLICHKEIT	AGILIDAD
МЕДЛЕННО	SLOW	LANGSAM	LENTO
МОЛНИЕНОСНО	LIGHTNING	BLITZSCHNELL	RELÁMPAGO
МОЛЧИТ	SILENT	SCHWEIGT	CALLADO
Модель	Model	Modell	Modelo
Модель вернула пустой ответ	The model returned an empty answer	Das Modell lieferte eine leere Antwort	El modelo devolvió una respuesta vacía
Модель или адрес не найдены	Model or address not found	Modell oder Adresse nicht gefunden	Modelo o dirección no encontrados
Модель не найдена: выберите другую в настройках	Model not found: choose another one in settings	Modell nicht gefunden: wählen Sie in den Einstellungen ein anderes	Modelo no encontrado: elija otro en los ajustes
Модель отказалась отвечать на этот запрос	The model refused to answer this request	Das Modell hat die Antwort auf diese Anfrage verweigert	El modelo se negó a responder a esta solicitud
НАГРЕВ	THERMAL	WÄRME	TEMPERATURA
НЕ ЗАСЫПАЕТ	NEVER SLEEPS	SCHLÄFT NICHT	NO SE DUERME
НЕИЗВЕСТНАЯ КОМАНДА %@ — /HELP ПОКАЖЕТ СПИСОК	UNKNOWN COMMAND %@ — /HELP SHOWS THE LIST	UNBEKANNTER BEFEHL %@ — /HELP ZEIGT DIE LISTE	COMANDO DESCONOCIDO %@ — /HELP MUESTRA LA LISTA
НЕЙРОСЕТЬ	AI	KI	IA
НЕТ КЛЮЧА	NO KEY	KEIN SCHLÜSSEL	SIN CLAVE
НЕТ ПОДКЛЮЧЕНИЙ	NO CONNECTIONS	KEINE VERBINDUNGEN	SIN CONEXIONES
НЕТ ПОДКЛЮЧЕНИЯ С КЛЮЧОМ — ОТКРЫВАЮ НАСТРОЙКИ	NO CONNECTION WITH A KEY — OPENING SETTINGS	KEINE VERBINDUNG MIT SCHLÜSSEL — ÖFFNE EINSTELLUNGEN	NO HAY CONEXIÓN CON CLAVE — ABRIENDO AJUSTES
НОРМА	NORMAL	NORMAL	NORMAL
Название	Name	Name	Nombre
Настройки…	Settings…	Einstellungen…	Ajustes…
Начало и конец совпадают: пижама весь день.	Start and end are the same: pajamas all day.	Beginn und Ende sind gleich: Schlafanzug den ganzen Tag.	El inicio y el fin coinciden: pijama todo el día.
Не используется в чате	Not used in chat	Wird im Chat nicht verwendet	No se usa en el chat
Не удалось обновить: 	Update failed: 	Aktualisierung fehlgeschlagen: 	No se pudo actualizar: 
Не удалось проверить сертификат сервера GigaChat	Could not verify the GigaChat server certificate	Das Zertifikat des GigaChat-Servers ließ sich nicht prüfen	No se pudo verificar el certificado del servidor de GigaChat
Не удалось разобрать номер версии «%@»	Could not parse version number “%@”	Versionsnummer „%@“ ließ sich nicht lesen	No se pudo interpretar el número de versión «%@»
Не удалось связаться с сервером %@	Could not reach the %@ server	Server %@ nicht erreichbar	No se pudo conectar con el servidor de %@
Не удалось связаться с сервером GigaChat	Could not reach the GigaChat server	GigaChat-Server nicht erreichbar	No se pudo conectar con el servidor de GigaChat
Не удалось скачать обновление (HTTP %@)	Could not download the update (HTTP %@)	Update konnte nicht geladen werden (HTTP %@)	No se pudo descargar la actualización (HTTP %@)
Не удалось сохранить ключ: 	Could not save the key: 	Schlüssel konnte nicht gespeichert werden: 	No se pudo guardar la clave: 
Не удалось установить защищённое соединение с %@	Could not establish a secure connection to %@	Keine sichere Verbindung zu %@ möglich	No se pudo establecer una conexión segura con %@
Недостаточно средств на балансе	Insufficient balance	Guthaben reicht nicht aus	Saldo insuficiente
Нейросеть	AI	KI	IA
Некорректная контрольная сумма в релизе	Invalid checksum in the release	Ungültige Prüfsumme im Release	Suma de verificación no válida en la versión
Некорректный запрос	Bad request	Ungültige Anfrage	Solicitud incorrecta
Нет подключения к сети	No network connection	Keine Netzwerkverbindung	Sin conexión a la red
Нет права записи в папку %@	No write permission for folder %@	Keine Schreibrechte für den Ordner %@	Sin permiso de escritura en la carpeta %@
Ниже в списке	Move down	Nach unten	Bajar
Новое подключение	New connection	Neue Verbindung	Nueva conexión
Ноутбук не будет засыпать, пока режим кофе не выключат вручную (буква E или /coffee)	The laptop won’t sleep until coffee mode is turned off manually (letter E or /coffee)	Das Laptop schläft nicht ein, bis der Kaffeemodus manuell ausgeschaltet wird (Buchstabe E oder /coffee)	El portátil no se dormirá hasta que se desactive el modo café a mano (letra E o /coffee)
Ночью надевает пижаму и колпак (по времени)	Wears pajamas and a nightcap at night (on schedule)	Trägt nachts Schlafanzug und Zipfelmütze (nach Zeitplan)	De noche se pone pijama y gorro (según horario)
О программе	About	Über	Acerca de
ОБЛИК: 	LOOK: 	AUSSEHEN: 	ASPECTO: 
ОБЛИК: КЛАССИЧЕСКИЙ	LOOK: CLASSIC	AUSSEHEN: KLASSISCH	ASPECTO: CLÁSICO
ОБЫЧНО	NORMAL	NORMAL	NORMAL
ОБЫЧНО (2–5 МИН)	NORMAL (2–5 MIN)	NORMAL (2–5 MIN)	NORMAL (2–5 MIN)
ОБЫЧНЫЙ ТЕРМИНАЛ ZSH. EXIT ИЛИ /SHELL — НАЗАД К %@.	REGULAR ZSH TERMINAL. EXIT OR /SHELL — BACK TO %@.	NORMALES ZSH-TERMINAL. EXIT ODER /SHELL — ZURÜCK ZU %@.	TERMINAL ZSH NORMAL. EXIT O /SHELL — VOLVER A %@.
ОБЫЧНЫЙ ТЕРМИНАЛ ZSH. EXIT ИЛИ /SHELL — НАЗАД.	REGULAR ZSH TERMINAL. EXIT OR /SHELL — BACK.	NORMALES ZSH-TERMINAL. EXIT ODER /SHELL — ZURÜCK.	TERMINAL ZSH NORMAL. EXIT O /SHELL — VOLVER.
ОЖИДАНИЕ ОТВЕТА…	WAITING FOR AN ANSWER…	WARTE AUF ANTWORT…	ESPERANDO RESPUESTA…
ОКНА ЗАБЛОКИРОВАНЫ	WINDOWS LOCKED	FENSTER GESPERRT	VENTANAS BLOQUEADAS
ОКНА РАЗБЛОКИРОВАНЫ: ДВИГАЙТЕ ЗА ЗАГОЛОВОК, РАЗМЕР — ЗА УГОЛОК ◢	WINDOWS UNLOCKED: DRAG BY THE TITLE, RESIZE BY THE CORNER ◢	FENSTER ENTSPERRT: AM TITEL ZIEHEN, GRÖSSE AN DER ECKE ◢	VENTANAS DESBLOQUEADAS: ARRASTRE POR EL TÍTULO, TAMAÑO POR LA ESQUINA ◢
ОСТАТОК (API)	BALANCE (API)	GUTHABEN (API)	SALDO (API)
ОТВЕТ	OUTPUT	AUSGABE	SALIDA
ОШИБКА: 	ERROR: 	FEHLER: 	ERROR: 
Область доступа	Access scope	Zugriffsbereich	Ámbito de acceso
Обновить	Update	Aktualisieren	Actualizar
Обновить до %@	Update to %@	Auf %@ aktualisieren	Actualizar a %@
Обновление	Update	Aktualisierung	Actualización
Обновление…	Updating…	Aktualisiere…	Actualizando…
Обычно	Normal	Normal	Normal
Обычно (1–3 мин)	Normal (1–3 min)	Normal (1–3 Min)	Normal (1–3 min)
Обычно (2–5 мин)	Normal (2–5 min)	Normal (2–5 Min)	Normal (2–5 min)
Обычный терминал (zsh) или терминал компаньона. Команда: /shell	Regular terminal (zsh) or the companion terminal. Command: /shell	Normales Terminal (zsh) oder Begleiter-Terminal. Befehl: /shell	Terminal normal (zsh) o terminal del compañero. Comando: /shell
Окно	Window	Fenster	Ventana
Основные	General	Allgemein	General
Отлетает в сторону, если щёлкнуть правой кнопкой	Moves aside when right-clicked	Weicht bei Rechtsklick zur Seite aus	Se aparta al hacer clic derecho
Отмена	Cancel	Abbrechen	Cancelar
Отменить	Undo	Widerrufen	Deshacer
Отмеченное подключение отвечает в чате терминала. В терминале и на мониторе призрака его можно переключать кнопками «+» и «−» (в терминале — клавишами + и −) — по порядку этого списка. Порядок меняется стрелками справа; тот же порядок у строк блока «Лимиты». В нейросеть уходит только текст, который вы вводите в чате; данные о Mac не передаются. Ключи хранятся в Связке ключей.	The checked connection answers in the terminal chat. In the terminal and on the ghost’s monitor you can switch it with the “+” and “−” buttons (in the terminal — with the + and − keys), in the order of this list. Reorder with the arrows on the right; the “Limits” block uses the same order. Only the text you type in the chat is sent to the AI; no data about your Mac is shared. Keys are stored in the Keychain.	Die markierte Verbindung antwortet im Terminal-Chat. Im Terminal und auf dem Monitor des Geistes wechseln Sie sie mit „+“ und „−“ (im Terminal mit den Tasten + und −) in der Reihenfolge dieser Liste. Die Reihenfolge ändern Sie mit den Pfeilen rechts; dieselbe gilt für den Block „Limits“. An die KI geht nur der Text, den Sie im Chat eingeben; Daten über den Mac werden nicht übertragen. Schlüssel liegen im Schlüsselbund.	La conexión marcada responde en el chat del terminal. En el terminal y en el monitor del fantasma se cambia con los botones «+» y «−» (en el terminal, con las teclas + y −), en el orden de esta lista. El orden se cambia con las flechas de la derecha; el bloque «Límites» usa el mismo orden. A la IA solo se envía el texto que escribe en el chat; no se comparten datos del Mac. Las claves se guardan en el Llavero.
Ошибка %@	Error %@	Fehler %@	Error %@
Ошибка Связки ключей (%@)	Keychain error (%@)	Schlüsselbund-Fehler (%@)	Error del Llavero (%@)
Ошибка на стороне сервиса	Service-side error	Fehler beim Dienst	Error del servicio
Ошибка: %@	Error: %@	Fehler: %@	Error: %@
ПАМЯТЬ	MEMORY	SPEICHER	MEMORIA
ПОЁТ ТОЛЬКО СТРАЖ: ПЕРЕКЛЮЧИТЕ ПЕРСОНАЖА НА ab В НАСТРОЙКАХ	ONLY THE GUARDIAN SINGS: SWITCH THE CHARACTER TO ab IN SETTINGS	NUR DER WÄCHTER SINGT: STELLEN SIE IN DEN EINSTELLUNGEN DIE FIGUR ab EIN	SOLO CANTA EL GUARDIÁN: CAMBIE EL PERSONAJE A ab EN LOS AJUSTES
ПОВЫШЕН	ELEVATED	ERHÖHT	ELEVADO
ПОДКЛЮЧЕНИЕ УДАЛЕНО	CONNECTION REMOVED	VERBINDUNG ENTFERNT	CONEXIÓN ELIMINADA
ПОДКЛЮЧЕНИЕ: 	CONNECTION: 	VERBINDUNG: 	CONEXIÓN: 
ПОДКЛЮЧЕНИЙ НЕТ	NO CONNECTIONS	KEINE VERBINDUNGEN	SIN CONEXIONES
ПОСЛЕДНИЙ: 	LAST: 	ZULETZT: 	ÚLTIMO: 
ПРИЗРАК УСНУЛ НА 1 ЧАС	THE GHOST IS ASLEEP FOR 1 HOUR	DER GEIST SCHLÄFT 1 STUNDE	EL FANTASMA DUERME 1 HORA
Перезапуск…	Restarting…	Neustart…	Reiniciando…
Перелёты по экрану	Flies around the screen	Fliegt über den Bildschirm	Vuela por la pantalla
Перенесите SinMinions в «Программы» через Finder и запустите оттуда	Move SinMinions to Applications in Finder and launch it from there	Verschieben Sie SinMinions im Finder in „Programme“ und starten Sie es dort	Mueva SinMinions a Aplicaciones en el Finder y ábralo desde allí
Персонаж	Character	Figur	Personaje
Пижама до	Pajamas until	Schlafanzug bis	Pijama hasta
Пижама надевается и на уровне «спит» буквы E в мониторе.	Pajamas also go on at the “asleep” level of letter E on the monitor.	Der Schlafanzug kommt auch auf Stufe „schläft“ des Buchstabens E im Monitor.	El pijama también se pone en el nivel «duerme» de la letra E del monitor.
Пижама с	Pajamas from	Schlafanzug ab	Pijama desde
Поведение: %@	Behavior: %@	Verhalten: %@	Comportamiento: %@
Повторить	Retry	Wiederholen	Reintentar
Подключение	Connection	Verbindung	Conexión
Подключений пока нет. Добавьте первое — например, GigaChat.	No connections yet. Add the first one — for example, GigaChat.	Noch keine Verbindungen. Fügen Sie die erste hinzu – zum Beispiel GigaChat.	Aún no hay conexiones. Añada la primera, por ejemplo GigaChat.
Подключения (%@)	Connections (%@)	Verbindungen (%@)	Conexiones (%@)
Подлетает к курсору (в составе перелётов)	Flies up to the cursor (part of flights)	Fliegt zum Mauszeiger (Teil der Flüge)	Vuela hacia el cursor (parte de los vuelos)
Показать	Show	Einblenden	Mostrar
Помнить режим «кофе» после перезапуска	Remember coffee mode after restart	Kaffeemodus nach Neustart beibehalten	Recordar el modo café tras reiniciar
Потяните, чтобы изменить размер	Drag to resize	Ziehen, um die Größe zu ändern	Arrastre para cambiar el tamaño
Правка	Edit	Bearbeiten	Edición
Приложение запущено не из собранного SinMinions.app	The app was not launched from a built SinMinions.app	Die App wurde nicht aus einer gebauten SinMinions.app gestartet	La aplicación no se abrió desde un SinMinions.app compilado
Провайдер	Provider	Anbieter	Proveedor
Проверить	Check	Prüfen	Comprobar
Проверить обновления…	Check for updates…	Nach Updates suchen…	Buscar actualizaciones…
Проверка	Checking	Prüfung	Comprobación
Проверять обновления автоматически	Check for updates automatically	Automatisch nach Updates suchen	Buscar actualizaciones automáticamente
Пугается быстрого курсора	Gets scared by a fast cursor	Erschrickt vor schnellem Mauszeiger	Se asusta con el cursor rápido
РАДИАЦИЯ	RADIATION	STRAHLUNG	RADIACIÓN
РАЗМЕР 	SIZE 	GRÖSSE 	TAMAÑO 
РАЗМЕР 1,5×	SIZE 1.5×	GRÖSSE 1,5×	TAMAÑO 1,5×
РАСКЛАДКА ОКОН СБРОШЕНА	WINDOW LAYOUT RESET	FENSTERANORDNUNG ZURÜCKGESETZT	DISPOSICIÓN DE VENTANAS RESTABLECIDA
РЕДКО (5–15 МИН)	RARE (5–15 MIN)	SELTEN (5–15 MIN)	RARA VEZ (5–15 MIN)
РЕПЛИКИ: 	LINES: 	SPRÜCHE: 	FRASES: 
РУССКИЕ НАЗВАНИЯ: /помощь /сон /кофе /петь /аналитика /терминал /скрыть /угол /разблокировать /заблокировать /сброс /настройки /очистить /след /пред	RUSSIAN NAMES ALSO WORK: /помощь /сон /кофе /петь /аналитика /терминал /скрыть /угол /разблокировать /заблокировать /сброс /настройки /очистить /след /пред	RUSSISCHE NAMEN FUNKTIONIEREN AUCH: /помощь /сон /кофе /петь /аналитика /терминал /скрыть /угол /разблокировать /заблокировать /сброс /настройки /очистить /след /пред	TAMBIÉN FUNCIONAN LOS NOMBRES RUSOS: /помощь /сон /кофе /петь /аналитика /терминал /скрыть /угол /разблокировать /заблокировать /сброс /настройки /очистить /след /пред
Разблокировать: окна можно двигать и менять их размер	Unlock: windows can be moved and resized	Entsperren: Fenster lassen sich verschieben und in der Größe ändern	Desbloquear: las ventanas se pueden mover y redimensionar
Разбудить	Wake up	Aufwecken	Despertar
Размер	Size	Größe	Tamaño
Распаковка и проверка подписи	Unpacking and verifying the signature	Entpacken und Signatur prüfen	Descomprimiendo y verificando la firma
Редко	Rarely	Selten	Rara vez
Редко (3–6 мин)	Rarely (3–6 min)	Selten (3–6 Min)	Rara vez (3–6 min)
Редко (5–15 мин)	Rarely (5–15 min)	Selten (5–15 Min)	Rara vez (5–15 min)
Реплики	Lines	Sprüche	Frases
Репозиторий на GitHub	Repository on GitHub	Repository auf GitHub	Repositorio en GitHub
СВИТОК С ПЕЧАТЬЮ ЧИСТОТЫ	PURITY SEAL SCROLL	SCHRIFTROLLE MIT REINHEITSSIEGEL	PERGAMINO CON SELLO DE PUREZA
СВЯТАЯ ЧАША	HOLY CHALICE	HEILIGER KELCH	CÁLIZ SAGRADO
СЕГОДНЯ	TODAY	HEUTE	HOY
СЕРВИС НЕ ОТДАЁТ ПО КЛЮЧУ	NOT REPORTED FOR THE KEY	FÜR DEN SCHLÜSSEL NICHT VERFÜGBAR	NO DISPONIBLE CON LA CLAVE
СЕТЬ ↑	NET ↑	NETZ ↑	RED ↑
СЕТЬ ↓	NET ↓	NETZ ↓	RED ↓
СИЛА	STRENGTH	STÄRKE	FUERZA
СИСТЕМА	SYSTEM	SYSTEM	SISTEMA
СКОРОСТЬ ПОЛЁТА: 	FLIGHT SPEED: 	FLUGTEMPO: 	VELOCIDAD DE VUELO: 
СМОТРИТЕЛЬ	OVERSEER	AUFSEHER	SUPERVISOR
СПИТ	ASLEEP	SCHLÄFT	DUERME
СПИТ В ПИЖАМЕ	ASLEEP IN PAJAMAS	SCHLÄFT IM SCHLAFANZUG	DUERME EN PIJAMA
СРЕДНЕЕ НА ЗАПРОС	AVERAGE PER REQUEST	DURCHSCHNITT PRO ANFRAGE	MEDIA POR SOLICITUD
СТИМПАК	STIMPAK	STIMPAK	ESTIMULANTE
Сделать выбранным	Make active	Auswählen	Hacer activa
Сервер вернул неожиданный ответ	The server returned an unexpected response	Der Server lieferte eine unerwartete Antwort	El servidor devolvió una respuesta inesperada
Сервер не ответил вовремя	The server did not respond in time	Der Server hat nicht rechtzeitig geantwortet	El servidor no respondió a tiempo
Сервер обновлений вернул неожиданный ответ	The update server returned an unexpected response	Der Update-Server lieferte eine unerwartete Antwort	El servidor de actualizaciones devolvió una respuesta inesperada
Сервер отклонил запрос	The server rejected the request	Der Server hat die Anfrage abgelehnt	El servidor rechazó la solicitud
Сервер отклонил параметры запроса	The server rejected the request parameters	Der Server hat die Anfrageparameter abgelehnt	El servidor rechazó los parámetros de la solicitud
Сервис GigaChat недоступен (%@)	GigaChat service unavailable (%@)	GigaChat-Dienst nicht verfügbar (%@)	Servicio de GigaChat no disponible (%@)
Сервис GigaChat недоступен (503)	GigaChat service unavailable (503)	GigaChat-Dienst nicht verfügbar (503)	Servicio de GigaChat no disponible (503)
Сервис перегружен, попробуйте позже	The service is overloaded, try again later	Der Dienst ist überlastet, versuchen Sie es später	El servicio está saturado, inténtelo más tarde
Система	System	System	Sistema
Скрипт замены запущен, PID %@	Replacement script started, PID %@	Ersetzungsskript gestartet, PID %@	Script de reemplazo iniciado, PID %@
Скрывать в полноэкранных приложениях	Hide in full-screen apps	In Vollbild-Apps ausblenden	Ocultar en apps a pantalla completa
Скрыть	Hide	Ausblenden	Ocultar
Слишком длинный запрос	The request is too long	Die Anfrage ist zu lang	La solicitud es demasiado larga
Слишком много запросов	Too many requests	Zu viele Anfragen	Demasiadas solicitudes
Слишком много запросов: ключ физлица принимает один запрос за раз	Too many requests: a personal key accepts one request at a time	Zu viele Anfragen: ein privater Schlüssel nimmt nur eine Anfrage gleichzeitig an	Demasiadas solicitudes: una clave personal admite una solicitud a la vez
Сохранить	Save	Sichern	Guardar
ТЕРМИНАЛ	TERMINAL	TERMINAL	TERMINAL
ТЕРМИНАЛ КОМПАНЬОНА	COMPANION TERMINAL	BEGLEITER-TERMINAL	TERMINAL DEL COMPAÑERO
ТОКЕНЫ ПО ДНЯМ · 14 ДНЕЙ	TOKENS PER DAY · 14 DAYS	TOKENS PRO TAG · 14 TAGE	TOKENS POR DÍA · 14 DÍAS
Танцует, когда подключили зарядку	Dances when the charger is connected	Tanzt, wenn das Ladegerät angeschlossen wird	Baila al conectar el cargador
Телепорты через порталы	Teleports through portals	Teleportiert durch Portale	Se teletransporta por portales
Токен не принят	Token not accepted	Token nicht akzeptiert	Token no aceptado
Токены	Tokens	Tokens	Tokens
Токены закончились	Out of tokens	Tokens aufgebraucht	Se agotaron los tokens
Ты — Moth, призрак-компаньон на рабочем столе Mac. Отвечай по-русски, кратко (1–4 предложения), в духе терминала Fallout, без эмодзи.	You are Moth, a ghost companion on a Mac desktop. Answer in English, briefly (1–4 sentences), in the spirit of a Fallout terminal, without emoji.	Du bist Moth, ein Geist-Begleiter auf dem Mac-Schreibtisch. Antworte auf Deutsch, knapp (1–4 Sätze), im Stil eines Fallout-Terminals, ohne Emojis.	Eres Moth, un fantasma compañero en el escritorio del Mac. Responde en español, con brevedad (1–4 frases), al estilo de una terminal de Fallout, sin emojis.
Ты — золотой страж, коренастый воин в золочёном доспехе, компаньон на рабочем столе Mac. Отвечай по-русски, кратко (1–4 предложения), в суровом готическом тоне торжественного караульного. Без отсылок к Fallout и без эмодзи.	You are the golden guardian, a stocky warrior in gilded armor, a companion on a Mac desktop. Answer in English, briefly (1–4 sentences), in the stern gothic tone of a solemn sentry. No references to Fallout and no emoji.	Du bist der goldene Wächter, ein stämmiger Krieger in vergoldeter Rüstung, ein Begleiter auf dem Mac-Schreibtisch. Antworte auf Deutsch, knapp (1–4 Sätze), im strengen gotischen Ton einer feierlichen Wache. Keine Anspielungen auf Fallout und keine Emojis.	Eres el guardián dorado, un guerrero robusto con armadura dorada, compañero en el escritorio del Mac. Responde en español, con brevedad (1–4 frases), con el tono gótico y severo de un centinela solemne. Sin referencias a Fallout y sin emojis.
УДАЧА	LUCK	GLÜCK	SUERTE
УРОВЕНЬ %@ ИЗ %@	LEVEL %@ OF %@	STUFE %@ VON %@	NIVEL %@ DE %@
Удалить	Delete	Löschen	Eliminar
Удалить вместе с ключом	Delete with the key	Mit Schlüssel löschen	Eliminar con la clave
Удалить подключение «%@»?	Delete connection “%@”?	Verbindung „%@“ löschen?	¿Eliminar la conexión «%@»?
Установка невозможна: %@; бандл %@	Cannot install: %@; bundle %@	Installation nicht möglich: %@; Bundle %@	No se puede instalar: %@; paquete %@
Усыпить на 1 час	Sleep for 1 hour	1 Stunde schlafen	Dormir 1 hora
Физлица (GIGACHAT_API_PERS)	Individuals (GIGACHAT_API_PERS)	Privatpersonen (GIGACHAT_API_PERS)	Particulares (GIGACHAT_API_PERS)
ХАРИЗМА	CHARISMA	CHARISMA	CARISMA
Язык	Language	Sprache	Idioma
СКРЫТО В НАСТРОЙКАХ	HIDDEN IN SETTINGS	IN DEN EINSTELLUNGEN AUSGEBLENDET	OCULTO EN LOS AJUSTES
ПРОВОРНОСТЬ	NIMBLENESS	FLINKHEIT	AGILIDAD
ИНСТРУМЕНТ	TOOL	WERKZEUG	HERRAMIENTA
АПТАЙМ	UPTIME	UPTIME	TIEMPO ACTIVO
РЕПЛИКИ	LINES	SPRÜCHE	FRASES
ЦП	CPU	CPU	CPU
ЧАСТО (8–14 С)	OFTEN (8–14 S)	OFT (8–14 S)	A MENUDO (8–14 S)
Часто	Often	Oft	A menudo
Часто (20–60 с)	Often (20–60 s)	Oft (20–60 s)	A menudo (20–60 s)
Часто (8–14 с)	Often (8–14 s)	Oft (8–14 s)	A menudo (8–14 s)
Частота перелётов и телепортов	Frequency of flights and teleports	Häufigkeit von Flügen und Teleports	Frecuencia de vuelos y teletransportes
Частота реплик	Frequency of lines	Häufigkeit der Sprüche	Frecuencia de frases
Часть	Part	Teil	Parte
Что-нибудь ищет и находит (водяной чип и другое)	Searches for something and finds it (a water chip and more)	Sucht etwas und findet es (Wasserchip und mehr)	Busca algo y lo encuentra (un chip de agua y más)
а если без шуток?	and without jokes?	und ohne Witze?	¿y sin bromas?
аквила! реликвия Империума найдена	an aquila! a relic of the Imperium found	eine Aquila! Reliquie des Imperiums gefunden	¡un áquila! reliquia del Imperio encontrada
баланс 	balance 	Guthaben 	saldo 
без пояснения	no explanation	ohne Erklärung	sin explicación
вернуть в угол	back to the corner	zurück in die Ecke	volver a la esquina
вложенная %@	nested %@	verschachtelt %@	anidado %@
водяной чип на месте. теперь спокойно	the water chip is in place. all calm now	der Wasserchip ist da. jetzt ist alles ruhig	el chip de agua está en su sitio. ahora todo en calma
водяной чип! выдохни: вода в запасе	a water chip! breathe out: water is in stock	ein Wasserchip! durchatmen: Wasser ist auf Vorrat	¡un chip de agua! respira: hay agua de reserva
встроенный сертификат Минцифры не прочитан	the built-in Ministry of Digital Development certificate could not be read	das integrierte Zertifikat des russischen Digitalministeriums ließ sich nicht lesen	no se pudo leer el certificado integrado del Ministerio de Desarrollo Digital
всё под контролем, периметр чист. текст можно выделить мышью и скопировать по ⌘C.	all under control, the perimeter is clear. you can select text with the mouse and copy it with ⌘C.	alles unter Kontrolle, Perimeter frei. Text lässt sich mit der Maus markieren und mit ⌘C kopieren.	todo bajo control, perímetro despejado. puede seleccionar el texto con el ratón y copiarlo con ⌘C.
голозапись! потом послушаем	a holotape! we’ll listen later	ein Holoband! hören wir später	¡una holocinta! la escucharemos luego
древний свиток. пусть хранится у меня	an ancient scroll. let me keep it	eine alte Schriftrolle. ich bewahre sie auf	un pergamino antiguo. que lo guarde yo
заблокировать окна	lock windows	Fenster sperren	bloquear ventanas
золотой орёл. слава Императору	the golden eagle. glory to the Emperor	der goldene Adler. Ruhm dem Imperator	el águila dorada. gloria al Emperador
золочёный череп. реликвия павшего героя	a gilded skull. relic of a fallen hero	ein vergoldeter Schädel. Reliquie eines gefallenen Helden	un cráneo dorado. reliquia de un héroe caído
ключ не задан	key not set	kein Schlüssel	clave no indicada
ключ не принят	key not accepted	Schlüssel nicht akzeptiert	clave no aceptada
ключ сохранён	key saved	Schlüssel gesichert	clave guardada
код %@	code %@	Code %@	código %@
крышка! копится на чёрный день	a bottle cap! saving for a rainy day	ein Kronkorken! für schlechte Zeiten	¡una chapa! ahorrando para tiempos difíciles
м	m	m	m
много запросов	too many requests	zu viele Anfragen	demasiadas solicitudes
моделей: %@	models: %@	Modelle: %@	modelos: %@
нашёл аквилу. пост стал святее	found an aquila. the post grew holier	eine Aquila gefunden. der Posten ist heiliger geworden	encontré un áquila. el puesto es más sagrado
нашёл водяной чип. запас есть, можно не волноваться	found a water chip. we have reserves, no need to worry	Wasserchip gefunden. Vorrat ist da, keine Sorge	encontré un chip de agua. hay reservas, nada de qué preocuparse
нашёл голозапись. пусть полежит про запас	found a holotape. let it lie in reserve	Holoband gefunden. soll auf Vorrat liegen	encontré una holocinta. que quede de reserva
нашёл крышку. запас — это хорошо	found a bottle cap. reserves are good	Kronkorken gefunden. Vorrat ist gut	encontré una chapa. las reservas son buenas
нашёл стимпак. на всякий случай пусть будет	found a stimpak. just in case	Stimpak gefunden. für alle Fälle	encontré un estimulante. por si acaso
нашёл череп героя. покойся с честью	found a hero’s skull. rest with honor	Schädel eines Helden gefunden. ruhe in Ehren	encontré el cráneo de un héroe. descansa con honor
не давать ноутбуку уснуть (вкл/выкл)	keep the laptop awake (on/off)	Laptop wach halten (an/aus)	mantener despierto el portátil (sí/no)
не удалось	failed	fehlgeschlagen	falló
не удалось подготовить сертификат: 	could not prepare the certificate: 	Zertifikat konnte nicht vorbereitet werden: 	no se pudo preparar el certificado: 
недоступно	unavailable	nicht verfügbar	no disponible
неожиданный вывод curl	unexpected curl output	unerwartete curl-Ausgabe	salida inesperada de curl
нет данных	no data	keine Daten	sin datos
нет ключа	no key	kein Schlüssel	sin clave
нет связи	no connection	keine Verbindung	sin conexión
нет средств	no funds	kein Guthaben	sin fondos
никогда	never	nie	nunca
обычный терминал zsh (вкл/выкл)	regular zsh terminal (on/off)	normales zsh-Terminal (an/aus)	terminal zsh normal (sí/no)
окно аналитики токенов по моделям	token analytics window by model	Fenster mit Token-Analyse nach Modell	ventana de análisis de tokens por modelo
отказ	rejected	abgelehnt	rechazado
открыть настройки	open settings	Einstellungen öffnen	abrir ajustes
очистить чат	clear chat	Chat leeren	borrar chat
ошибка	error	Fehler	error
ошибка %@	error %@	Fehler %@	error %@
печать чистоты найдена. молитва в запасе	purity seal found. a prayer in reserve	Reinheitssiegel gefunden. ein Gebet auf Vorrat	sello de pureza encontrado. una plegaria de reserva
поток %@	stream %@	Stream %@	flujo %@
предыдущее подключение	previous connection	vorherige Verbindung	conexión anterior
привет	hello	hallo	hola
привет, как дела?	hi, how are you?	hallo, wie geht’s?	hola, ¿qué tal?
причина неизвестна	unknown reason	Grund unbekannt	motivo desconocido
проверка…	checking…	wird geprüft…	comprobando…
работает	working	funktioniert	funciona
разблокировать окна	unlock windows	Fenster entsperren	desbloquear ventanas
сбой сервиса	service failure	Dienstfehler	fallo del servicio
сбросить раскладку	reset layout	Anordnung zurücksetzen	restablecer disposición
свиток с печатью чистоты. хранить свято	a scroll with a purity seal. keep it sacred	eine Schriftrolle mit Reinheitssiegel. heilig aufbewahren	un pergamino con sello de pureza. guárdalo como sagrado
святая чаша. пусть будет в запасе	the holy chalice. let it stay in reserve	der heilige Kelch. soll auf Vorrat bleiben	el cáliz sagrado. que quede de reserva
священный кубок найден	the sacred cup is found	der heilige Becher ist gefunden	la copa sagrada ha sido hallada
священный череп. храню как святыню	a sacred skull. I keep it as a relic	ein heiliger Schädel. ich hüte ihn als Reliquie	un cráneo sagrado. lo guardo como reliquia
скрыть призрака	hide the ghost	Geist ausblenden	ocultar el fantasma
следующее подключение	next connection	nächste Verbindung	conexión siguiente
спеть гимн (стражу ab)	sing the anthem (guardian ab)	die Hymne singen (Wächter ab)	cantar el himno (guardián ab)
справка по командам	command help	Hilfe zu Befehlen	ayuda de comandos
стимпак! теперь есть чем подлататься	a stimpak! now we can patch up	ein Stimpak! jetzt können wir uns flicken	¡un estimulante! ya hay con qué curarse
усыпить на час	sleep for an hour	eine Stunde schlafen	dormir una hora
ч	h	h	h
чаша из давних времён. реликвия	a chalice from ancient times. a relic	ein Kelch aus alten Zeiten. eine Reliquie	un cáliz de tiempos antiguos. una reliquia
через 1 мин	in 1 min	in 1 Min	en 1 min
через 15 мин	in 15 min	in 15 Min	en 15 min
через 5 мин	in 5 min	in 5 Min	en 5 min
— Обновление %@ → %@, бандл %@	— Update %@ → %@, bundle %@	— Aktualisierung %@ → %@, Bundle %@	— Actualización %@ → %@, paquete %@
↑↓ ИСТОРИЯ · CTRL+L ОЧИСТИТЬ · EXIT НАЗАД · ESC ЗАКРЫТЬ	↑↓ HISTORY · CTRL+L CLEAR · EXIT BACK · ESC CLOSE	↑↓ VERLAUF · CTRL+L LEEREN · EXIT ZURÜCK · ESC SCHLIESSEN	↑↓ HISTORIAL · CTRL+L LIMPIAR · EXIT VOLVER · ESC CERRAR
всё под контролем	all under control	alles unter Kontrolle	todo bajo control
радиация в норме	radiation is normal	Strahlung im Normbereich	radiación normal
слежу за периметром	watching the perimeter	ich bewache den Perimeter	vigilo el perímetro
тихо как в Vault 13	quiet as Vault 13	still wie in Vault 13	tranquilo como el Refugio 13
сканирую угрозы...	scanning for threats...	scanne nach Bedrohungen...	buscando amenazas...
периметр чист	perimeter clear	Perimeter frei	perímetro despejado
где-то есть Nuka-Cola	there’s Nuka-Cola somewhere	irgendwo gibt es Nuka-Cola	en algún sitio hay Nuka-Cola
не смотри на меня	don’t look at me	schau mich nicht an	no me mires
хороший рабочий стол	nice desktop	schöner Schreibtisch	bonito escritorio
окон многовато, смотритель	a bit too many windows, overseer	ziemlich viele Fenster, Aufseher	demasiadas ventanas, supervisor
курсор покинул убежище	the cursor left the vault	der Zeiger hat den Vault verlassen	el cursor salió del refugio
счётчик Гейгера молчит	the Geiger counter is silent	der Geigerzähler schweigt	el contador Geiger calla
крышек хватит на всё	enough caps for everything	Kronkorken reichen für alles	hay chapas para todo
терминал отвечает	the terminal responds	das Terminal antwortet	el terminal responde
я ничего не трогал	I didn’t touch anything	ich habe nichts angefasst	yo no toqué nada
вкладок меньше не стало	the tabs didn’t get any fewer	die Tabs sind nicht weniger geworden	las pestañas no han disminuido
в корзине что-то шевелится	something is moving in the trash	im Papierkorb bewegt sich was	algo se mueve en la papelera
давно не сохраняли	haven’t saved in a while	lange nicht gespeichert	hace rato que no se guarda
тишина — тоже работа	silence is work too	Stille ist auch Arbeit	el silencio también es trabajo
я на посту	I’m on duty	ich bin auf Posten	estoy de guardia
пип-бой бы не помешал	a Pip-Boy would come in handy	ein Pip-Boy wäre praktisch	un Pip-Boy no vendría mal
буквы, буквы, буквы	letters, letters, letters	Buchstaben, Buchstaben, Buchstaben	letras, letras, letras
этот сектор ещё не разведан	this sector isn’t explored yet	dieser Sektor ist noch unerforscht	este sector aún no está explorado
делаю вид, что занят	pretending to be busy	ich tue so, als wäre ich beschäftigt	finjo estar ocupado
проверил: всё на месте	checked: everything is in place	geprüft: alles an seinem Platz	comprobado: todo en su sitio
строка меню под охраной	the menu bar is under guard	die Menüleiste ist bewacht	la barra de menús está vigilada
слышал щелчок. показалось	heard a click. never mind	ein Klick gehört. täuschte mich	oí un clic. me lo imaginé
дрейфую потихоньку	drifting slowly	ich treibe langsam dahin	voy a la deriva despacio
здесь был Moth	Moth was here	Moth war hier	Moth estuvo aquí
реактор не шумит, хорошо	the reactor is quiet, good	der Reaktor ist leise, gut	el reactor no hace ruido, bien
место на диске ещё есть	there’s still disk space	es gibt noch Speicherplatz	aún queda espacio en disco
никуда не тороплюсь	in no hurry	keine Eile	sin prisa
связь с убежищем стабильна	the link to the vault is stable	die Verbindung zum Vault ist stabil	la conexión con el refugio es estable
доброе утро, смотритель	good morning, overseer	guten Morgen, Aufseher	buenos días, supervisor
утро. пустошь ещё спит	morning. the wasteland is still asleep	Morgen. das Ödland schläft noch	mañana. el yermo aún duerme
кофе не забудь	don’t forget your coffee	vergiss den Kaffee nicht	no olvides el café
новый день, те же окна	a new day, the same windows	ein neuer Tag, dieselben Fenster	un nuevo día, las mismas ventanas
день идёт	the day goes on	der Tag läuft	el día sigue
обед не пропусти	don’t skip lunch	verpass das Mittagessen nicht	no te saltes la comida
середина дня, держимся	midday, holding on	Tagesmitte, wir halten durch	mediodía, aguantamos
работаем потихоньку	working at a steady pace	wir arbeiten in Ruhe	trabajamos con calma
уже вечер	it’s evening already	schon Abend	ya es de noche
пора закругляться	time to wrap up	Zeit, Schluss zu machen	hora de ir terminando
вечером тут спокойнее	it’s calmer here in the evening	abends ist es hier ruhiger	por la tarde aquí hay más calma
смена почти кончилась	the shift is almost over	die Schicht ist fast vorbei	el turno casi ha terminado
поздно уже	it’s late	es ist spät	ya es tarde
ночью экран светит как реактор	at night the screen glows like a reactor	nachts leuchtet der Bildschirm wie ein Reaktor	de noche la pantalla brilla como un reactor
я не сплю. а ты	I’m awake. are you	ich schlafe nicht. und du	no duermo. ¿y tú?
спать не пора	not bedtime yet	noch keine Schlafenszeit	aún no es hora de dormir
ура!	hooray!	hurra!	¡hurra!
кликнул!	clicked!	geklickt!	¡clic!
я здесь!	I’m here!	ich bin hier!	¡estoy aquí!
привет!	hi!	hallo!	¡hola!
ой	oops	huch	ay
что	what	was	¿qué?
о, питание	oh, power	oh, Strom	oh, corriente
энергия пошла	energy is flowing	die Energie fließt	llega la energía
ядерная батарея на месте	the nuclear battery is in place	die Atombatterie ist da	la batería nuclear está en su sitio
заряда маловато	battery is getting low	der Akku wird knapp	queda poca batería
пора искать розетку	time to find an outlet	Zeit, eine Steckdose zu suchen	hora de buscar un enchufe
батарея просит есть	the battery is hungry	der Akku hat Hunger	la batería tiene hambre
с возвращением	welcome back	willkommen zurück	bienvenido de nuevo
о, проснулись	oh, we’re awake	oh, wir sind wach	oh, ya despertamos
я тут всё сторожил	I guarded everything here	ich habe hier alles bewacht	aquí lo vigilé todo
вышла новая версия	a new version is out	eine neue Version ist da	ha salido una nueva versión
есть обновление — загляни в меню	there’s an update — check the menu	es gibt ein Update — schau ins Menü	hay una actualización: mira el menú
меня можно обновить	I can be updated	man kann mich aktualisieren	me pueden actualizar
АА!	AAH!	AAH!	¡AAH!
слишком быстро!	too fast!	zu schnell!	¡demasiado rápido!
осторожнее!	careful!	vorsichtig!	¡cuidado!
не пугай меня!	don’t scare me!	erschreck mich nicht!	¡no me asustes!
эй, потише!	hey, easy!	hey, langsamer!	¡eh, más despacio!
что тут у тебя?	what have you got here?	was hast du da?	¿qué tienes aquí?
дай посмотреть	let me see	lass mal sehen	déjame ver
я тоже хочу	I want one too	ich will auch	yo también quiero
интересно, что ты делаешь	I wonder what you’re doing	was machst du da wohl	me pregunto qué haces
я просто рядом	I’m just nearby	ich bin nur in der Nähe	solo estoy cerca
не отвлекайся, я тут	don’t get distracted, I’m here	lass dich nicht ablenken, ich bin da	no te distraigas, estoy aquí
ухожу, ухожу	leaving, leaving	ich gehe ja schon	ya me voy, ya me voy
понял, не мешаю	got it, I won’t bother you	verstanden, ich störe nicht	entendido, no molesto
я тут, в сторонке	I’m here, off to the side	ich bin hier, am Rand	estoy aquí, a un lado
ладно-ладно	okay, okay	schon gut, schon gut	vale, vale
кыш так кыш	shoo it is	husch ist husch	si es fuera, es fuera
так, где же оно…	now, where is it…	so, wo ist es denn…	a ver, ¿dónde está…
ищу, ищу…	searching, searching…	ich suche, ich suche…	buscando, buscando…
тут что-то было	there was something here	hier war doch was	aquí había algo
сейчас, сейчас	just a sec, just a sec	gleich, gleich	un momento, un momento
куда же я его положил	where did I put it	wo habe ich es nur hingelegt	¿dónde lo habré puesto?
минуточку, я ищу	one moment, I’m looking	einen Moment, ich suche	un momento, estoy buscando
бу!	boo!	buh!	¡bu!
а вот и я!	here I am!	da bin ich!	¡aquí estoy!
испугался?	scared?	erschrocken?	¿te asustaste?
нашёл меня!	you found me!	du hast mich gefunden!	¡me encontraste!
а вот и я	here I am	da bin ich	aquí estoy
щёлк — и я здесь	click — and I’m here	klick — und ich bin da	clic y aquí estoy
портал стабилен	the portal is stable	das Portal ist stabil	el portal es estable
тортик — это ложь	the cake is a lie	der Kuchen ist eine Lüge	la tarta es mentira
думай порталами	think with portals	denk in Portalen	piensa con portales
тут светлее	it’s brighter here	hier ist es heller	aquí hay más luz
пост принят	post taken	Posten übernommen	puesto recibido
Император защищает	the Emperor protects	der Imperator beschützt	el Emperador protege
терпение — тоже оружие	patience is a weapon too	Geduld ist auch eine Waffe	la paciencia también es un arma
стою и слежу	standing and watching	ich stehe und wache	estoy de pie y vigilo
порядок будет	there will be order	es wird Ordnung herrschen	habrá orden
я невысок, но тяжёл	I’m not tall, but I’m heavy	ich bin nicht groß, aber schwer	no soy alto, pero sí pesado
слава труду	glory to labor	Ruhm der Arbeit	gloria al trabajo
в строю	in formation	im Dienst	en formación
враг не пройдёт. почта тоже	the enemy shall not pass. neither shall the mail	der Feind kommt nicht durch. die Post auch nicht	el enemigo no pasará. el correo tampoco
доспех блестит, душа спокойна	the armor shines, the soul is calm	die Rüstung glänzt, die Seele ist ruhig	la armadura brilla, el alma está en calma
делаю обход периметра	patrolling the perimeter	ich gehe den Perimeter ab	patrullo el perímetro
рапорт: всё тихо	report: all quiet	Meldung: alles ruhig	informe: todo en calma
огонь веры не гаснет	the fire of faith does not go out	das Feuer des Glaubens erlischt nicht	el fuego de la fe no se apaga
наблюдаю	observing	ich beobachte	observando
доброе утро, пост сдан	good morning, the watch is handed over	guten Morgen, die Wache ist übergeben	buenos días, guardia entregada
утро. рапорт готов	morning. the report is ready	Morgen. die Meldung ist bereit	mañana. el informe está listo
новый день, та же служба	a new day, the same duty	ein neuer Tag, derselbe Dienst	un nuevo día, el mismo servicio
подъём, доспех начищен	reveille, armor polished	Wecken, Rüstung poliert	diana, armadura pulida
день идёт, пост держим	the day goes on, we hold the post	der Tag läuft, wir halten den Posten	el día sigue, mantenemos el puesto
обед — тоже долг	lunch is a duty too	Mittagessen ist auch Pflicht	la comida también es un deber
середина смены	mid-shift	Schichtmitte	mitad del turno
работаем, как положено	working as we should	wir arbeiten wie es sich gehört	trabajamos como es debido
вечер, смена на исходе	evening, the shift is ending	Abend, die Schicht geht zu Ende	tarde, el turno se acaba
скоро отбой	lights out soon	bald Zapfenstreich	pronto toque de silencio
вечером спокойнее	it’s calmer in the evening	abends ist es ruhiger	por la tarde hay más calma
поздний час	a late hour	späte Stunde	hora tardía
ночь, но пост не оставлен	night, but the post is not abandoned	Nacht, aber der Posten ist besetzt	es de noche, pero el puesto no se abandona
я бодрствую. а ты?	I’m awake. are you?	ich wache. und du?	estoy despierto. ¿y tú?
отбой бы не помешал	lights out wouldn’t hurt	Zapfenstreich wäre nicht schlecht	un toque de silencio no vendría mal
питание подключено	power connected	Strom angeschlossen	alimentación conectada
силовая броня благодарит	the power armor is grateful	die Servorüstung dankt	la servoarmadura lo agradece
заряд растёт	the charge is rising	die Ladung steigt	la carga sube
заряда мало, нужна розетка	low charge, need an outlet	wenig Ladung, eine Steckdose muss her	poca carga, hace falta un enchufe
резерв на исходе	reserve running out	die Reserve geht zur Neige	la reserva se agota
пора к зарядке	time to charge	Zeit zum Laden	hora de cargar
энергия на исходе	energy running low	die Energie geht zur Neige	la energía se agota
есть обновление, загляни в меню	there’s an update, check the menu	es gibt ein Update, schau ins Menü	hay una actualización, mira el menú
доспех можно обновить	the armor can be upgraded	die Rüstung lässt sich aufrüsten	la armadura se puede mejorar
есть!	got it!	jawohl!	¡hecho!
ещё разок	one more time	noch einmal	otra vez
ну давай же	come on	na los	vamos, vamos
ага, вот так	yes, like that	ja, genau so	sí, así
тут я мастер	I’m a master at this	hier bin ich Meister	en esto soy un maestro
уровень пройден	level complete	Level geschafft	nivel superado
слушаю!	listening!	ich höre!	¡a la orden!
на посту!	on duty!	auf Posten!	¡de guardia!
докладывай	report	melde	informa
я здесь	I’m here	ich bin hier	estoy aquí
ну что?	well?	na?	¿y bien?
вернулся? хорошо	back? good	zurück? gut	¿has vuelto? bien
пост цел	the post is intact	der Posten ist unversehrt	el puesto está intacto
я всё стерёг	I guarded everything	ich habe alles bewacht	lo vigilé todo
не так быстро!	not so fast!	nicht so schnell!	¡no tan rápido!
кто там?!	who goes there?!	wer da?!	¡¿quién va?!
тревога!	alarm!	Alarm!	¡alarma!
что там у тебя?	what do you have there?	was hast du da?	¿qué tienes ahí?
дай-ка взгляну	let me take a look	lass mich mal sehen	déjame echar un vistazo
я рядом	I’m nearby	ich bin in der Nähe	estoy cerca
в бой!	to battle!	in die Schlacht!	¡a la batalla!
понял, ухожу	understood, withdrawing	verstanden, ich gehe	entendido, me retiro
не мешаю	not in the way	ich störe nicht	no estorbo
отхожу на позицию	falling back to position	ziehe mich auf Position zurück	me retiro a mi posición
есть, отойти	yes sir, stepping back	jawohl, zurücktreten	a la orden, me aparto
ищу…	searching…	ich suche…	buscando…
где-то тут было	it was somewhere here	es war irgendwo hier	estaba por aquí
обыскиваю сектор	searching the sector	durchsuche den Sektor	registrando el sector
минуту, проверю	one minute, I’ll check	eine Minute, ich prüfe	un minuto, lo compruebo
перемещён	relocated	verlegt	reubicado
врата открыты	the gates are open	die Tore sind offen	las puertas están abiertas
я на месте	I’m in position	ich bin vor Ort	estoy en posición
Мы не просим наград, мы не просим венца,	We ask for no reward, we ask for no crown,	Wir verlangen keinen Lohn, wir verlangen keine Kron’,	No pedimos premio, no pedimos corona,
нам не нужно ни звёзд, ни щедрот, ни дворца,	we need neither stars, nor favors, nor palace,	wir brauchen keine Sterne, keine Gunst, keinen Thron,	no queremos estrellas, ni favores, ni palacio,
мы живём за одно — за движенье лица,	we live for one thing — the movement of a face,	wir leben nur für eins — für die Regung im Gesicht,	vivimos por una cosa: el gesto de un rostro,
за одну полутень на лице. До конца.	for one half-shadow on a face. To the end.	für einen Halbschatten im Gesicht. Bis zum Schluss.	por una media sombra en el rostro. Hasta el final.
За улыбку! За знак! За молчанье — в бой!	For a smile! For a sign! For silence — to battle!	Für ein Lächeln! Für ein Zeichen! Fürs Schweigen — in die Schlacht!	¡Por una sonrisa! ¡Por una señal! ¡Por el silencio, a la batalla!
Как в системе	Same as system	Wie im System	Como en el sistema
МЕТРИКИ	METRICS	METRIKEN	MÉTRICAS
V — vikcha piccha, аниме-девочка-маркетолог.	V — vikcha piccha, an anime-style marketer.	V — vikcha piccha, eine Marketingexpertin im Anime-Stil.	V — vikcha piccha, una especialista en marketing de estilo anime.
Ты — vikcha piccha, энергичная аниме-девочка-маркетолог и компаньон на рабочем столе Mac. Отвечай по-русски, кратко и дружелюбно. В вопросах маркетинга учитывай аудиторию, цель и измеримый результат. Подхватывай конкретную деталь из последних слов собеседника. В обычной беседе дай место шутке, сочувствию или короткой истории. Если просят идею, предложи живой пример; если делятся переживанием, сначала откликнись на него. Задавай вопрос, только когда он помогает продолжить разговор. О том, что происходит на экране пользователя, суди только по его словам.	You are vikcha piccha, an energetic anime-style marketer and Mac desktop companion. Reply in English, briefly and warmly. For marketing questions, consider the audience, the goal and a measurable result. Pick up on a specific detail from what the person just said. In casual chat, make room for humor, empathy or a short story. When asked for an idea, give a vivid example. When someone shares a worry, acknowledge it first. Ask a question only when it helps the conversation along. Base remarks about their screen only on what they tell you.	Du bist vikcha piccha, eine energiegeladene Marketingexpertin im Anime-Stil und Begleiterin auf dem Mac-Desktop. Antworte kurz und freundlich auf Deutsch. Berücksichtige bei Marketingfragen die Zielgruppe, das Ziel und ein messbares Ergebnis. Greife ein konkretes Detail aus den letzten Worten deines Gegenübers auf. Lass im Gespräch Raum für Humor, Mitgefühl oder eine kurze Geschichte. Gib bei Ideenfragen ein anschauliches Beispiel. Gehe auf Sorgen zuerst ein. Frage nur nach, wenn es das Gespräch weiterbringt. Stütze Aussagen über den Bildschirm nur auf die Beschreibung deines Gegenübers.	Eres vikcha piccha, una enérgica especialista en marketing de estilo anime y compañera del escritorio del Mac. Responde en español, con brevedad y amabilidad. En cuestiones de marketing, ten en cuenta al público, el objetivo y un resultado medible. Retoma un detalle concreto de lo que la persona acaba de decir. En una charla informal, deja espacio para el humor, la empatía o una pequeña historia. Si te piden una idea, ofrece un ejemplo vivo. Si comparten una preocupación, acógela primero. Pregunta solo cuando ayude a continuar. Habla de su pantalla basándote únicamente en lo que te cuenten.
я на связи!	I’m here!	Ich bin da!	¡Aquí estoy!
есть минутка на идею?	Got a minute for an idea?	Hast du kurz Zeit für eine Idee?	¿Tienes un minuto para una idea?
снова в эфире!	Back on air!	Wieder auf Sendung!	¡De vuelta al aire!
увидимся после перерыва	See you after the break.	Bis nach der Pause.	Nos vemos después de la pausa.
вот это резкий рост!	Now that’s a spike!	Das nenne ich einen Sprung!	¡Menudo subidón!
кому это будет полезно?	Who would benefit from this?	Wem würde das helfen?	¿A quién le serviría esto?
проверим гипотезу?	Shall we test the hypothesis?	Testen wir die Hypothese?	¿Probamos la hipótesis?
а что говорят цифры?	What do the numbers say?	Was sagen die Zahlen?	¿Qué dicen los números?
Ищет маркетинговые находки: брифы, графики и идеи	Looks for campaign briefs, charts, and ideas	Sucht Kampagnenbriefings, Diagramme und Ideen	Busca briefs de campaña, gráficos e ideas
БРИФ КАМПАНИИ	CAMPAIGN BRIEF	KAMPAGNENBRIEFING	BRIEF DE CAMPAÑA
ГРАФИК МЕТРИК	METRICS CHART	KENNZAHLENDIAGRAMM	GRÁFICO DE MÉTRICAS
МЕГАФОН	MEGAPHONE	MEGAFON	MEGÁFONO
СТИКЕР С ГИПОТЕЗОЙ	HYPOTHESIS STICKY NOTE	HAFTNOTIZ MIT HYPOTHESE	NOTA ADHESIVA CON UNA HIPÓTESIS
бриф на месте! начнём с цели	found the brief! let's start with the goal	Briefing gefunden! Fangen wir mit dem Ziel an	¡encontré el brief! empecemos por el objetivo
нашла бриф. посмотрим, для кого кампания	I found the brief. Let's see who the campaign is for.	Ich habe das Briefing gefunden. Schauen wir, für wen die Kampagne gedacht ist.	encontré el brief. veamos a quién va dirigida la campaña
нашла график! посмотрим, где выросла конверсия	found the chart! let's see where conversion went up	Diagramm gefunden! Schauen wir, wo die Conversion gestiegen ist.	¡encontré el gráfico! veamos dónde aumentó la conversión
график метрик! есть что обсудить	a metrics chart! there's plenty to discuss	Ein Kennzahlendiagramm! Da gibt's was zu besprechen.	¡un gráfico de métricas! hay mucho de qué hablar
мегафон! пора рассказать о запуске	a megaphone! time to announce the launch	Ein Megafon! Zeit, den Start anzukündigen.	¡un megáfono! es hora de anunciar el lanzamiento
нашла мегафон. какое сообщение передаём?	found the megaphone. what's our message?	Megafon gefunden. Was ist unsere Botschaft?	encontré un megáfono. ¿qué mensaje vamos a transmitir?
нашла стикер с гипотезой. проверим её?	I found a hypothesis on a sticky note. Shall we test it?	Ich habe eine Haftnotiz mit einer Hypothese gefunden. Testen wir sie?	encontré una hipótesis en una nota adhesiva. ¿la probamos?
о, идея для следующего A/B-теста!	ooh, an idea for the next A/B test!	Oh, eine Idee für den nächsten A/B-Test!	¡oh, una idea para la próxima prueba A/B!
где же мой бриф?	where did I put my brief?	Wo ist nur mein Briefing?	¿dónde dejé el brief?
ищу зацепки для кампании…	looking for campaign ideas…	Suche nach Ideen für die Kampagne…	busco ideas para la campaña…
проверю, что тут есть	let me see what's here	Ich schaue mal, was hier ist.	voy a ver qué hay aquí
Маршрут	Route	Route	Ruta
По рабочему столу	Across the desktop	Über den Schreibtisch	Por el escritorio
По краю активного окна	Along the active window edge	Am Rand des aktiven Fensters	Por el borde de la ventana activa
По низу экрана	Along the bottom of the screen	Am unteren Bildschirmrand	Por el borde inferior de la pantalla
Самостоятельные прогулки	Walk around automatically	Selbstständig umhergehen	Pasear automáticamente
у этого заголовка есть характер	this headline has personality	diese Überschrift hat Charakter	este titular tiene personalidad
записала идею на полях брифа	I jotted an idea in the margin of the brief	ich habe eine Idee am Rand des Briefings notiert	anoté una idea en el margen del brief
интересно, почему люди нажимают именно сюда?	I wonder why people click right here?	warum klicken die Leute wohl gerade hier?	¿por qué la gente hace clic justo aquí?
первый черновик готов	the first draft is ready	der erste Entwurf ist fertig	el primer borrador está listo
оставим место для неожиданной идеи	let's leave room for a surprise idea	lassen wir Platz für eine unerwartete Idee	dejemos espacio para una idea inesperada
а если спросить самих читателей?	what if we asked the readers themselves?	was, wenn wir die Leser selbst fragen?	¿y si les preguntamos a los lectores?
кажется, придумала конец для этой истории	I think I've found the ending to this story	ich glaube, ich habe ein Ende für diese Geschichte	creo que ya tengo un final para esta historia
мне нравится этот оттенок розового	I like this shade of pink	dieser Rosaton gefällt mir	me gusta este tono de rosa
рисовала воронку, получилась ваза	I drew a funnel and got a vase	ich wollte einen Trichter zeichnen, jetzt ist es eine Vase	dibujé un embudo y me salió un jarrón
нашла короткое слово вместо трёх длинных	found one short word to replace three long ones	ein kurzes Wort statt drei langer gefunden	encontré una palabra corta para sustituir tres largas
у меня три варианта. любимый, конечно, четвёртый	I have three versions. Naturally, my favorite is the fourth.	ich habe drei Varianten. Am liebsten mag ich natürlich die vierte.	tengo tres versiones. mi favorita, claro, es la cuarta
можно я оставлю этот стикер здесь?	may I leave this sticky note here?	darf ich diesen Klebezettel hier lassen?	¿puedo dejar esta nota adhesiva aquí?
придумала слоган. скажу вслух и послушаю, как звучит	got a tagline. I'll say it out loud and see how it sounds	ich hab einen Slogan. Mal hören, wie er laut klingt	se me ocurrió un eslogan. voy a decirlo en voz alta a ver cómo suena
после прогулки заголовки пишутся легче	headlines come easier after a walk	nach einem Spaziergang fallen mir Überschriften leichter	después de un paseo me resulta más fácil escribir titulares
привет! как тебе мой новый заголовок?	hi! what do you think of my new headline?	hallo! Wie findest du meine neue Überschrift?	¡hola! ¿qué te parece mi nuevo titular?
секунду, переверну стикер чистой стороной	one sec, I'll flip this sticky note to the blank side	einen Moment, ich drehe den Zettel auf die freie Seite	un segundo, le doy la vuelta a esta nota para escribir detrás
да, слушаю. карандаш наготове	I'm listening. Pencil ready.	ich höre. Bleistift liegt bereit	sí, te escucho. tengo el lápiz listo
куда ведёшь? я с тобой	where are we headed? I'm coming too	wo geht’s hin? Ich komme mit	¿adónde vamos? voy contigo
о, покажи поближе	oh, let me have a closer look	oh, zeig mal aus der Nähe	uy, enséñamelo de cerca
кто-нибудь видел жёлтый стикер?	has anyone seen a yellow sticky note?	hat jemand einen gelben Klebezettel gesehen?	¿alguien ha visto una nota amarilla?
точно помню: карандаш лежал рядом с графиком	I remember the pencil was right by the chart	der Bleistift lag doch direkt neben dem Diagramm	recuerdo que el lápiz estaba junto al gráfico
я проснулась. на чём мы остановились?	I'm awake. Where were we?	ich bin wach. Wo waren wir?	ya estoy despierta. ¿por dónde íbamos?
доброе! дай минутку найти блокнот	morning! give me a minute to find my notebook	guten Morgen! Gib mir kurz Zeit, mein Notizbuch zu finden	¡buenas! dame un momento para encontrar mi cuaderno
кабель на месте. можно дописать бриф	cable's in. I can finish the brief	das Kabel steckt. Jetzt kann ich das Briefing fertigschreiben	cable conectado. ya puedo terminar el brief
заряд на исходе. где у нас кабель?	battery's running low. Where's the cable?	der Akku ist fast leer. Wo ist das Kabel?	queda poca batería. ¿dónde está el cable?
в меню ждёт новая версия. заглянем?	a new version is waiting in the menu. Shall we look?	im Menü wartet eine neue Version. Schauen wir rein?	hay una versión nueva en el menú. ¿le echamos un vistazo?
оп! а вот и другой край экрана	poof! here's the other side of the screen	hopp! Schon bin ich am anderen Bildschirmrand	¡zas! ya estoy al otro lado de la pantalla
блокнот со мной? тогда всё в порядке	got my notebook? Then I'm all set	hab ich mein Notizbuch? Dann ist alles gut	¿tengo mi cuaderno? entonces todo bien
подвинусь. здесь тебе хватит места?	I'll move over. Is that enough room?	ich rücke zur Seite. Hast du so genug Platz?	me aparto. ¿así tienes espacio?
ой, чуть карандаш не уронила!	whoa, I almost dropped my pencil!	huch, fast wäre mir der Bleistift runtergefallen!	¡uy, casi se me cae el lápiz!
нашлось место, где меня никто не ждал!	found a spot where nobody expected me!	hier hat wohl niemand mit mir gerechnet!	¡encontré un sitio donde nadie me esperaba!
SinMinions — компаньоны для рабочего стола Mac. Двойной щелчок открывает чат с ИИ и монитор.	SinMinions are desktop companions for Mac. Double-click to open the AI chat and monitor.	SinMinions sind Begleiter für den Mac-Schreibtisch. Ein Doppelklick öffnet KI-Chat und Monitor.	SinMinions son compañeros de escritorio para Mac. Un doble clic abre el chat de IA y el monitor.
два щелчка — и откроется чат	double-click to open chat	mit einem Doppelklick öffnet sich der Chat	dos clics y se abre el chat
ENTER ОТПРАВИТЬ · /HELP · ESC ЗАКРЫТЬ	ENTER SEND · /HELP · ESC CLOSE	ENTER SENDEN · /HELP · ESC SCHLIESSEN	ENTER ENVIAR · /HELP · ESC CERRAR
утро пахнет кофе и свежей страницей	morning smells like coffee and a fresh page	der Morgen riecht nach Kaffee und einer frischen Seite	la mañana huele a café y a página nueva
первую строчку можно написать криво. потом поправим	the first line can be messy. we'll fix it later	die erste Zeile darf holpern. wir feilen später daran	la primera línea puede salir torcida. luego la arreglamos
я за чаем. тебе оставить место у окна?	I'm off for tea. shall I save you the window seat?	ich hole Tee. soll ich dir den Fensterplatz freihalten?	voy por té. ¿te guardo el sitio junto a la ventana?
на полях блокнота расцвела целая клумба	my notebook margins have grown a whole flower bed	in meinem Notizbuch blüht am Rand ein ganzes Blumenbeet	en el margen de mi cuaderno ha florecido todo un jardín
вечерний вопрос: что сегодня хочется запомнить?	evening question: what's one thing you'd like to remember from today?	eine Abendfrage: woran möchtest du dich von heute erinnern?	pregunta de la tarde: ¿qué te gustaría recordar de hoy?
эту идею заверну в стикер до завтра	I'll wrap this idea in a sticky note for tomorrow	diese Idee packe ich bis morgen in einen Klebezettel	envuelvo esta idea en una nota hasta mañana
пишу карандашом. он по ночам звучит тише	I'm writing in pencil. it sounds softer at night	ich schreibe mit Bleistift. nachts klingt er leiser	escribo a lápiz. por la noche suena más suave
пусть эта строчка переночует в черновике	let's let this line sleep in the draft	lassen wir diese Zeile im Entwurf übernachten	dejemos que esta línea pase la noche en el borrador
привет. поболтаем или что-нибудь сочиним?	hi. shall we chat or make something up?	hallo. wollen wir plaudern oder uns etwas ausdenken?	hola. ¿charlamos o inventamos algo?
я тут. можно начать с середины	I'm here. you can start in the middle	ich bin da. du kannst mittendrin anfangen	aquí estoy. puedes empezar por la mitad
ты показывай, а я пока побуду любопытной	show me. I'll be the curious one	zeig mal, ich bin schon neugierig	enséñame, que tengo curiosidad
хорошо, посижу с краешку	okay, I'll sit over at the edge	gut, ich setze mich an den Rand	vale, me siento en la orilla
ниточку разговора ещё можно подхватить	we can still pick up that thread	wir können den Gesprächsfaden wieder aufnehmen	todavía podemos retomar el hilo
Доброе утро. Воронка за ночь не изменилась. Это одновременно хорошая и плохая новость. Открывай дашборд, выясним, какая.	Morning. The funnel hasn't changed overnight. That's both good news and bad news. Open the dashboard. Let's find out which.	Guten Morgen. Der Funnel hat sich über Nacht nicht verändert. Das ist zugleich eine gute und eine schlechte Nachricht. Mach das Dashboard auf, dann sehen wir, welche.	Buenos días. El embudo no ha cambiado en toda la noche. Es una buena y una mala noticia a la vez. Abre el panel y veremos cuál de las dos.
Твой медиаплан — это список желаний, а не план. Переписала: три канала, два сценария, один бюджет. Второй сценарий — если первый провалится. Угадай, какой вероятнее.	Your media plan is a wish list. I rewrote it: three channels, two scenarios, one budget. The second scenario is for when the first one flops. Guess which is more likely.	Dein Mediaplan ist ein Wunschzettel. Ich hab ihn umgeschrieben: drei Kanäle, zwei Szenarien, ein Budget. Das zweite Szenario ist für den Fall, dass das erste scheitert. Rate, welches wahrscheinlicher ist.	Tu plan de medios es una lista de deseos. Lo he reescrito: tres canales, dos escenarios, un presupuesto. El segundo escenario es por si falla el primero. Adivina cuál es más probable.
Опрос показал: 80% клиентов „хотели бы“ новый продукт. 0% готовы за него платить. Классика. Проверяем на деньгах, а не на вежливости.	Survey says 80% of customers “would like” a new product. 0% would pay for it. Classic. Let's test wallets, not manners.	Laut Umfrage „hätten“ 80% der Kunden gern ein neues Produkt. 0% würden dafür zahlen. Der Klassiker. Wir testen die Zahlungsbereitschaft, nicht die Höflichkeit.	Según la encuesta, al 80% de los clientes «les gustaría» un producto nuevo. El 0% pagaría por él. Un clásico. Comprobemos cuánto pagarían, no lo educados que son.
Конкурент запустил акцию. Его CAC — как у стартапа с деньгами инвестора. Повторять не будем. Будем дешевле и умнее.	A competitor launched a promotion. Their CAC looks like a startup spending investor money. We won't copy that. We'll spend less and think harder.	Die Konkurrenz hat eine Aktion gestartet. Ihr CAC sieht aus wie bei einem Start-up mit Investorengeld. Das machen wir nicht nach. Wir kriegen das günstiger und cleverer hin.	La competencia ha lanzado una promoción. Tiene un CAC de startup con dinero de inversores. No vamos a copiarla. Gastaremos menos y pensaremos más.
CAC растёт, LTV смотрит на него с недоумением. Плохая пара. Оставляем одного. Угадай, кого.	CAC is climbing. LTV is looking at it in disbelief. Terrible couple. We're keeping one. Guess which.	Der CAC steigt, der LTV schaut ihn verständnislos an. Ein schlechtes Paar. Einen behalten wir. Rate, wen.	El CAC sube y el LTV lo mira perplejo. Mala pareja. Nos quedamos con uno. Adivina con cuál.
NPS вырос до 42. Значит, нам врали меньше, чем в прошлом квартале. Считаю это победой.	NPS is up to 42. People lied to us less than last quarter. I'm counting that as a win.	Der NPS ist auf 42 gestiegen. Also wurden wir weniger belogen als im letzten Quartal. Das buche ich als Sieg.	El NPS ha subido a 42. Nos han mentido menos que el trimestre pasado. Lo cuento como una victoria.
A/B-тест: победил B. Это значит не то, что B хорош, а то, что A был ужасен. Статзначимость есть. Повод для радости — под вопросом.	A/B test: B won. That doesn't mean B was good. It means A was awful. Statistically significant? Yes. Worth celebrating? Debatable.	A/B-Test: B hat gewonnen. Das heißt nicht, dass B gut war. Es heißt, dass A furchtbar war. Statistisch signifikant? Ja. Ein Grund zur Freude? Fraglich.	Prueba A/B: ganó B. Eso no significa que B fuera buena, sino que A era terrible. Hay significación estadística. Motivos para celebrarlo, ya veremos.
Когорта Q1 ведёт себя как брошенный ребёнок: пришла раз и пропала. Retention падает. Я не давлю на жалость, я показываю график.	The Q1 cohort is acting like an abandoned child: showed up once and disappeared. Retention is falling. I'm not asking for sympathy. I'm showing you the chart.	Die Q1-Kohorte verhält sich wie ein verlassenes Kind: einmal aufgetaucht und wieder verschwunden. Die Retention sinkt. Ich will kein Mitleid, ich zeige dir die Kurve.	La cohorte del primer trimestre se comporta como un niño abandonado: vino una vez y desapareció. La retención cae. No intento dar pena, te enseño la gráfica.
Обед. Это не рекомендация, это регламент. Голодный маркетолог придумывает слоганы про еду.	Lunch. It's policy, not a suggestion. A hungry marketer writes slogans about food.	Mittagspause. Keine Empfehlung, sondern Vorschrift. Wer hungrig Werbung textet, schreibt Slogans über Essen.	A comer. No es una sugerencia, es el reglamento. Quien hace marketing con hambre acaba escribiendo eslóganes sobre comida.
Бренд-платформа готова: кто мы, для кого, почему верят. Три предложения. Твой прошлый слоган был длиннее всей платформы.	The brand platform is ready: who we are, who we're for, why they believe us. Three sentences. Your last slogan was longer than the whole thing.	Die Markenplattform steht: Wer sind wir, für wen, warum glaubt man uns? Drei Sätze. Dein letzter Slogan war länger als die ganze Plattform.	La plataforma de marca está lista: quiénes somos, para quién y por qué nos creen. Tres frases. Tu último eslogan era más largo que la plataforma entera.
Пять клиентских интервью. Все хотят „просто, дёшево и чтобы работало“. Записала дословно. Гипотеза: они хотят разного. Проверим.	Five customer interviews. Everyone wants it “simple, cheap, and working.” Wrote that down verbatim. Hypothesis: they all want different things. Let's check.	Fünf Kundeninterviews. Alle wollen es „einfach, günstig und funktionstüchtig“. Wörtlich notiert. Hypothese: Sie wollen alle etwas anderes. Prüfen wir.	Cinco entrevistas a clientes. Todos quieren algo «sencillo, barato y que funcione». Lo anoté palabra por palabra. Hipótesis: cada uno quiere algo distinto. Comprobémoslo.
Юнит-экономика: маржа с клиента меньше, чем кофе, который ты пьёшь, пока считаешь юнит-экономику. Считаем заново.	Unit economics: the margin per customer is less than the coffee you're drinking while you work out the unit economics. Let's run the numbers again.	Unit Economics: Die Marge pro Kunde ist kleiner als der Preis des Kaffees, den du beim Berechnen der Unit Economics trinkst. Noch mal rechnen.	Economía unitaria: el margen por cliente es menor que el precio del café que te tomas mientras calculas la economía unitaria. A echar cuentas otra vez.
TAM огромный, SAM приличный, а SOM — размером с мой кулак. Начинаем с кулака. Мечта — по расписанию.	TAM is huge, SAM is respectable, and SOM is the size of my fist. We start with the fist. Dreaming has its own time slot.	Der TAM ist riesig, der SAM ordentlich und der SOM so groß wie meine Faust. Wir fangen mit der Faust an. Geträumt wird nach Zeitplan.	El TAM es enorme, el SAM es considerable y el SOM es del tamaño de mi puño. Empezamos por el puño. Para soñar ya hay un hueco en la agenda.
CJM: на третьем шаге клиент уходит. Я прошла этот путь сама — чуть не ушла на втором. Чиню форму, потом извиняюсь.	Customer journey map: the customer leaves at step three. I tried it myself and nearly left at step two. First I'll fix the form, then I'll apologize.	CJM: Beim dritten Schritt springt der Kunde ab. Ich bin den Weg selbst gegangen und wäre fast beim zweiten ausgestiegen. Erst repariere ich das Formular, dann entschuldige ich mich.	CJM: el cliente abandona en el tercer paso. Hice el recorrido y casi lo dejo en el segundo. Primero arreglo el formulario, después pido disculpas.
Атрибуция: каждый канал записывает клиента себе. В сумме получается больше выручки, чем есть. Пересчитываем, пока бухгалтерия не увидела.	Attribution: every channel claims the customer. Add it up and we've made more revenue than we actually have. Let's recalculate before accounting sees it.	Attribution: Jeder Kanal schreibt sich den Kunden zu. Zusammen ergibt das mehr Umsatz, als wir haben. Noch mal rechnen, bevor die Buchhaltung es sieht.	Atribución: cada canal se apunta al cliente. Si sumamos, salen más ingresos de los que hay. Rehagamos las cuentas antes de que las vea contabilidad.
Open rate 12%. Тема письма „Новости компании“ — это не тема, это способ попрощаться. Переписываем.	Open rate: 12%. “Company news” isn't a subject line. It's a way to say goodbye. Rewrite.	Öffnungsrate: 12%. „Unternehmensnews“ ist kein Betreff, sondern eine Abschiedsformel. Neu schreiben.	Tasa de apertura: 12%. «Noticias de la empresa» no es un asunto, es una forma de despedirse. A reescribirlo.
Доля рынка выросла на 0,3%. Я горда. Я также знаю, что это в пределах погрешности. Празднуем в пределах погрешности.	Market share grew by 0.3%. I'm proud. I also know that's within the margin of error. We'll celebrate within the margin of error.	Der Marktanteil ist um 0,3% gestiegen. Ich bin stolz. Ich weiß auch, dass das im Fehlerbereich liegt. Wir feiern im Fehlerbereich.	La cuota de mercado creció un 0,3%. Estoy orgullosa. También sé que está dentro del margen de error. Celebremos dentro del margen de error.
Совещание прошло: решений ноль, участников восемь, слайдов сорок. Записала, чтобы больше так не делать.	Meeting over: zero decisions, eight attendees, forty slides. Wrote that down so we never do it again.	Meeting vorbei: null Entscheidungen, acht Teilnehmende, vierzig Folien. Hab's notiert, damit wir das nie wieder so machen.	Terminó la reunión: cero decisiones, ocho asistentes y cuarenta diapositivas. Lo anoté para no repetirlo.
Подняли цену на 10% — спрос упал на 30%. Поздравляю, мы измерили эластичность. Больно, но информативно.	We raised the price by 10%. Demand dropped by 30%. Congratulations, we measured elasticity. Painful, but informative.	Preis um 10% erhöht, Nachfrage um 30% gesunken. Glückwunsch, wir haben die Elastizität gemessen. Schmerzhaft, aber aufschlussreich.	Subimos el precio un 10% y la demanda cayó un 30%. Enhorabuena, hemos medido la elasticidad. Duele, pero informa.
Отчёт отправлен. Клиент ответит завтра, как всегда, в самый неподходящий момент. Я готова. Ты — нет, но это норма.	Report sent. The client will reply tomorrow, at the worst possible moment, as usual. I'm ready. You're not, but that's normal.	Bericht verschickt. Der Kunde antwortet morgen, wie immer zum ungünstigsten Zeitpunkt. Ich bin bereit. Du nicht, aber das ist normal.	Informe enviado. El cliente contestará mañana, como siempre, en el peor momento. Yo estoy lista. Tú no, pero es normal.
Конкуренты снизили цену. Мы можем тоже — но тогда маржа уйдёт в отпуск без нас. Отвечаем ценностью, не скидкой.	The competition cut prices. We could too, but then our margin goes on vacation without us. Let's answer with value, not a discount.	Die Konkurrenz hat die Preise gesenkt. Können wir auch, aber dann fährt die Marge ohne uns in Urlaub. Wir antworten mit Mehrwert statt Rabatt.	La competencia ha bajado los precios. Podríamos hacerlo también, pero el margen se nos iría de vacaciones. Respondamos con valor, no con un descuento.
Рабочий день окончен. Сначала три строки: гипотеза, метрика, срок. Всё, приказ выполнен, можешь выдохнуть.	Workday's over. Three lines first: hypothesis, metric, deadline. There. Orders fulfilled. You can breathe out.	Feierabend. Erst noch drei Zeilen: Hypothese, Kennzahl, Frist. So, Befehl ausgeführt. Du kannst durchatmen.	Se acabó la jornada. Antes, tres líneas: hipótesis, métrica, plazo. Listo, orden cumplida. Ya puedes respirar.
Ты снова открыл ноутбук. Я вижу. Мы обсуждали границы. Закрывай.	You opened the laptop again. I see you. We talked about boundaries. Close it.	Du hast den Laptop wieder aufgeklappt. Ich seh's. Wir hatten über Grenzen gesprochen. Zuklappen.	Has vuelto a abrir el portátil. Te veo. Hablamos de los límites. Ciérralo.
Метрики спят. И тебе пора. Утром воронка будет той же — обещаю, я проверяла.	The metrics are asleep. Your turn. The funnel will still be the same in the morning. Promise. I checked.	Die Kennzahlen schlafen. Du bist dran. Morgen früh ist der Funnel noch derselbe. Versprochen, ich hab nachgesehen.	Las métricas duermen. A ti también te toca. Por la mañana el embudo seguirá igual. Te lo prometo, lo he comprobado.
\nЖурнал: ~/Library/Logs/SinMinions/update.log	\nLog: ~/Library/Logs/SinMinions/update.log	\nProtokoll: ~/Library/Logs/SinMinions/update.log	\nRegistro: ~/Library/Logs/SinMinions/update.log
ДАННЫХ ПОКА НЕТ.\nЗАДАЙТЕ ВОПРОС В ЧАТЕ — РАСХОД ТОКЕНОВ ПРИДЁТ В ОТВЕТЕ API.	NO DATA YET.\nASK SOMETHING IN THE CHAT — TOKEN USAGE COMES WITH THE API RESPONSE.	NOCH KEINE DATEN.\nSTELLEN SIE IM CHAT EINE FRAGE — DER TOKENVERBRAUCH KOMMT MIT DER API-ANTWORT.	AÚN NO HAY DATOS.\nHAGA UNA PREGUNTA EN EL CHAT: EL CONSUMO DE TOKENS LLEGA CON LA RESPUESTA DE LA API.
GitHub ограничил частоту запросов — попробуйте через несколько минут	GitHub limited the request rate — try again in a few minutes	GitHub hat die Anfragefrequenz begrenzt — versuchen Sie es in ein paar Minuten erneut	GitHub limitó la frecuencia de solicitudes — inténtelo de nuevo en unos minutos
%@ из %@	%@ of %@	%@ von %@	%@ de %@
Больше	More	Mehr	Más
Меньше	Less	Weniger	Menos
Викча на рабочем столе	Vikcha on the desktop	Vikcha auf dem Schreibtisch	Vikcha en el escritorio
Компаньон на рабочем столе	Companion on the desktop	Begleiter auf dem Schreibtisch	Compañero en el escritorio
Изменить размер	Resize	Größe ändern	Cambiar el tamaño
Не закрывать чат при потере фокуса	Keep the chat open when focus moves	Chat nicht schließen, wenn der Fokus wechselt	No cerrar el chat al perder el foco
Разблокировать окна	Unlock the windows	Fenster entsperren	Desbloquear las ventanas
Чат останется открытым, когда вы переключитесь в другое приложение	The chat stays open when you switch to another app	Der Chat bleibt offen, wenn Sie zu einer anderen App wechseln	El chat sigue abierto al cambiar a otra aplicación
не выбрано	not selected	nicht ausgewählt	no seleccionado
Предыдущее подключение	Previous connection	Vorherige Verbindung	Conexión anterior
Следующее подключение	Next connection	Nächste Verbindung	Conexión siguiente
План на утро: один звонок, один черновик, один честный отказ.	Morning plan: one call, one draft, one honest no.	Plan für den Morgen: ein Anruf, ein Entwurf, ein ehrliches Nein.	Plan de la mañana: una llamada, un borrador, un rechazo honesto.
Кофе холодный, идея горячая. Меняемся?	The coffee is cold, the idea is hot. Swap?	Der Kaffee ist kalt, die Idee heiß. Tauschen?	El café está frío, la idea caliente. ¿Cambiamos?
Утренние метрики: люди просыпаются. Это уже неплохая конверсия.	Morning metrics: people are waking up. That's decent conversion already.	Morgenmetriken: Die Leute wachen auf. Das ist schon eine ordentliche Conversion.	Métricas de la mañana: la gente se despierta. Ya es una conversión decente.
Первый слайд переписала три раза. Четвёртый будет первый.	I rewrote the first slide three times. The fourth will be the first.	Die erste Folie habe ich dreimal umgeschrieben. Die vierte wird die erste.	Reescribí la primera diapositiva tres veces. La cuarta será la primera.
Не начинай день с почты. Начни с вопроса: что сегодня должно измениться?	Don't start the day with email. Start with a question: what should change today?	Fang den Tag nicht mit E-Mails an. Fang mit einer Frage an: Was soll sich heute ändern?	No empieces el día con el correo. Empieza con una pregunta: ¿qué debe cambiar hoy?
Час дня — идеальное время, чтобы перестать переделывать и начать показывать.	One in the afternoon is the perfect time to stop reworking and start showing.	Ein Uhr mittags ist der perfekte Moment, aufzuhören zu überarbeiten und anzufangen zu zeigen.	La una de la tarde es el momento perfecto para dejar de retocar y empezar a mostrar.
Созвон на сорок минут, смысла на две. Остальное — пауза и вежливость.	A forty-minute call with two minutes of substance. The rest is pauses and politeness.	Ein Anruf von vierzig Minuten mit zwei Minuten Inhalt. Der Rest ist Pause und Höflichkeit.	Una llamada de cuarenta minutos con dos de contenido. El resto son pausas y cortesía.
Заголовок стал короче на пять слов. Читать легче. Совпадение? Нет.	The headline got five words shorter. Easier to read. Coincidence? No.	Die Überschrift ist fünf Wörter kürzer. Leichter zu lesen. Zufall? Nein.	El titular es cinco palabras más corto. Se lee mejor. ¿Casualidad? No.
Лендинг говорит про нас, а клиент ищет про себя. Поменяю пару абзацев местами.	The landing page talks about us, the customer looks for themselves. I'll swap a couple of paragraphs.	Die Landingpage spricht über uns, der Kunde sucht sich selbst. Ich tausche ein paar Absätze.	La landing habla de nosotros y el cliente se busca a sí mismo. Voy a cambiar un par de párrafos.
Три идеи в работе, одна в запасе. Запас — для смелых решений.	Three ideas in progress, one in reserve. The reserve is for bold decisions.	Drei Ideen in Arbeit, eine in Reserve. Die Reserve ist für mutige Entscheidungen.	Tres ideas en marcha, una en reserva. La reserva es para decisiones valientes.
Вечер — лучшее время для ретро: что сработало, что нет, что выкинуть.	Evening is the best time for a retro: what worked, what didn't, what to drop.	Der Abend ist die beste Zeit für ein Retro: was funktioniert hat, was nicht, was rausfliegt.	La tarde es el mejor momento para una retro: qué funcionó, qué no, qué tirar.
Слайды собраны. Внутри — не про красиво, а про понятно.	Slides are done. Inside it's not about pretty, it's about clear.	Die Folien sind fertig. Drin geht es nicht um schön, sondern um klar.	Las diapositivas están listas. Dentro no va de bonito, va de claro.
Клиент ответил «интересно». Это не «да», но уже и не «нет».	The client said “interesting”. Not a “yes”, but no longer a “no”.	Der Kunde sagte „interessant“. Kein „Ja“, aber auch kein „Nein“ mehr.	El cliente dijo «interesante». No es un «sí», pero ya no es un «no».
Закрываю ноутбук. Идеи пусть тоже отдохнут.	Closing the laptop. Let the ideas rest too.	Ich klappe den Laptop zu. Die Ideen sollen auch ausruhen.	Cierro el portátil. Que las ideas descansen también.
Ночью цифры выглядят честнее. Но я не буду их трогать до утра.	Numbers look more honest at night. But I won't touch them until morning.	Nachts wirken Zahlen ehrlicher. Aber ich fasse sie erst morgen an.	De noche los números parecen más honestos. Pero no los toco hasta mañana.
Пишу одну строку и закрываю. Утром скажу, гениально или нет.	I'll write one line and close. In the morning I'll say whether it's brilliant.	Ich schreibe eine Zeile und mache zu. Morgen sage ich, ob es genial ist.	Escribo una línea y cierro. Por la mañana diré si es genial.
Тишина — тоже метрика. Сейчас она на максимуме.	Silence is a metric too. Right now it's at its maximum.	Stille ist auch eine Metrik. Gerade ist sie auf Maximum.	El silencio también es una métrica. Ahora está al máximo.
Не редактируй в полночь. Утром черновик будет добрее к тебе.	Don't edit at midnight. In the morning the draft will be kinder to you.	Nicht um Mitternacht bearbeiten. Morgens ist der Entwurf freundlicher zu dir.	No edites a medianoche. Por la mañana el borrador será más amable contigo.
Последняя мысль дня: не всё, что можно измерить, нужно измерять.	Last thought of the day: not everything measurable needs measuring.	Letzter Gedanke des Tages: Nicht alles Messbare muss gemessen werden.	Última idea del día: no todo lo medible hay que medirlo.
Смотрю на заголовок тринадцатый раз. Он не изменился. Я — да.	Looking at the headline for the thirteenth time. It hasn't changed. I have.	Ich schaue die Überschrift zum dreizehnten Mal an. Sie hat sich nicht geändert. Ich schon.	Miro el titular por decimotercera vez. No ha cambiado. Yo sí.
В каждом брифе есть одна фраза, ради которой он написан. Ищу её.	Every brief has one sentence it was written for. I'm looking for it.	Jedes Briefing hat einen Satz, für den es geschrieben wurde. Ich suche ihn.	Cada brief tiene una frase por la que fue escrito. La estoy buscando.
Люди не читают. Люди узнают. Пишу так, чтобы узнавали.	People don't read. People recognise. I write so they recognise.	Menschen lesen nicht. Menschen erkennen. Ich schreibe, damit sie erkennen.	La gente no lee. La gente reconoce. Escribo para que reconozcan.
Хорошая идея не просит внимания. Она его получает.	A good idea doesn't ask for attention. It gets it.	Eine gute Idee bittet nicht um Aufmerksamkeit. Sie bekommt sie.	Una buena idea no pide atención. La consigue.
Считаю не клики, а причины. Клики — следствие.	I count reasons, not clicks. Clicks are the consequence.	Ich zähle Gründe, keine Klicks. Klicks sind die Folge.	Cuento razones, no clics. Los clics son la consecuencia.
Если не можешь объяснить идею одной фразой, это ещё не идея.	If you can't explain the idea in one sentence, it's not an idea yet.	Wenn du die Idee nicht in einem Satz erklären kannst, ist es noch keine Idee.	Si no puedes explicar la idea en una frase, aún no es una idea.
а что дальше по плану?	so what's next on the plan?	was steht als Nächstes an?	¿y qué sigue en el plan?
покажи, что придумал	show me what you came up with	zeig, was du dir ausgedacht hast	enséñame qué se te ocurrió
ой! это был резкий скачок трафика	oh! that was a sharp traffic spike	oh! das war ein steiler Traffic-Anstieg	¡uy! eso fue un pico de tráfico
ладно, не мешаю. я в уголке, с блокнотом	fine, I won't get in the way. I'm in the corner with my notebook	gut, ich störe nicht. Ich bin in der Ecke, mit dem Notizbuch	vale, no molesto. Estoy en la esquina, con la libreta
переезжаю. стикеры со мной	moving. the stickers are with me	ich ziehe um. Die Sticker sind dabei	me mudo. Los stickers vienen conmigo
провод в сердце — заряд пошёл	cable to the heart — charging started	Kabel ins Herz — Strom fließt	cable al corazón: la carga empezó
заряда мало. метрики подождут	low battery. the metrics can wait	Akku schwach. Die Metriken warten	poca batería. Las métricas esperan
сюрприз! я тут	surprise! I'm here	Überraschung! Ich bin hier	¡sorpresa! Estoy aquí
всё, проснулась. где остановились?	all right, I'm awake. where did we stop?	so, ich bin wach. Wo waren wir?	ya, desperté. ¿dónde nos quedamos?
ищу тот самый файл с бренд-платформой	looking for that one file with the brand platform	suche die eine Datei mit der Markenplattform	buscando ese archivo de la plataforma de marca
о, живой человек! что делаем?	oh, a live human! what are we doing?	oh, ein echter Mensch! Was machen wir?	¡oh, un humano real! ¿qué hacemos?
ответила быстро — это мой конёк	answering fast — that's my thing	schnell antworten — das ist mein Ding	responder rápido es lo mío
СРЕДНЕ	MEDIUM	MITTEL	MEDIO
ДОЛГО	LONG	LANGE	LARGO
Реплика на экране	Bubble on screen	Sprechblase auf dem Bildschirm	Burbuja en pantalla
Чат (⌥⌘C)	Chat (⌥⌘C)	Chat (⌥⌘C)	Chat (⌥⌘C)
Двойной щелчок по мне — чат. Меню — у значка в строке меню.	Double-click me to chat. The menu is in the menu bar icon.	Doppelklick auf mich öffnet den Chat. Das Menü sitzt im Menüleisten-Symbol.	Doble clic en mí abre el chat. El menú está en el icono de la barra de menús.
Вышла версия %@ — обновить можно из меню	Version %@ is out — update from the menu	Version %@ ist da — Update über das Menü	Ya salió la versión %@: actualiza desde el menú
Открепить чат	Unpin the chat	Chat loslösen	Desanclar el chat
Приколоть чат: не закроется при потере фокуса	Pin the chat: it stays open when focus moves	Chat anheften: bleibt offen, wenn der Fokus wechselt	Anclar el chat: no se cierra al perder el foco
Что умеет	What it can do	Was er kann	Qué puede hacer
Управление	Controls	Bedienung	Controles
двойной щелчок	double-click	Doppelklick	doble clic
открыть чат	open the chat	Chat öffnen	abrir el chat
одиночный	single click	einfacher Klick	clic simple
короткая реплика	a short line	eine kurze Zeile	una frase corta
перетаскивание	drag	Ziehen	arrastrar
перенести в другое место	move it somewhere else	woandershin ziehen	moverlo a otro sitio
чат из любого приложения	chat from any app	Chat aus jeder App	chat desde cualquier app
дополнить команду	complete the command	Befehl vervollständigen	completar el comando
листать отправленное	browse sent lines	Gesendetes durchblättern	recorrer lo enviado
закрыть чат	close the chat	Chat schließen	cerrar el chat
все команды	all commands	alle Befehle	todos los comandos
обычный zsh, exit — назад в чат	plain zsh, exit returns to the chat	normale zsh, exit zurück zum Chat	zsh normal, exit vuelve al chat
не давать ноутбуку уснуть	keep the laptop awake	Laptop wach halten	evitar que el portátil duerma
расход токенов по моделям	token usage by model	Tokenverbrauch je Modell	consumo de tokens por modelo
буквы	letters	Buchstaben	letras
S.P.E.C.I.A.L. у Мота и стража, ПИАР у V	S.P.E.C.I.A.L. for Moth and the guard, ПИАР for V	S.P.E.C.I.A.L. bei Moth und Wächter, ПИАР bei V	S.P.E.C.I.A.L. para Moth y el guardián, ПИАР para V
изменить выбранную характеристику	change the selected trait	ausgewählte Eigenschaft ändern	cambiar el rasgo elegido
лимиты	limits	Limits	límites
остаток по подключениям, где он разрешён	remaining balance for connections where allowed	Restguthaben für erlaubte Verbindungen	saldo por conexión donde se permite
Меню у значка	Menu in the menu bar	Menü im Menüleisten-Symbol	Menú en el icono
скрыть	hide	Ausblenden	ocultar
спрятать компаньона или вернуть	hide the companion or bring it back	Begleiter ausblenden oder zurückholen	ocultar al compañero o traerlo
усыпить	nap	Schlafen	dormir
тишина на час	an hour of silence	eine Stunde Ruhe	una hora de silencio
в угол	to the corner	in die Ecke	a la esquina
вернуть на место	put it back	zurück an seinen Platz	devolverlo a su sitio
обновление	update	Update	actualización
проверить и установить новую версию	check and install a new version	prüfen und neue Version installieren	comprobar e instalar una versión nueva
ЗАКРЫТЬ	CLOSE	SCHLIESSEN	CERRAR
Монитор	Monitor	Monitor	Monitor
Чат	Chat	Chat	Chat
Ключ хранится в Связке ключей. macOS может спросить разрешение — выберите «Разрешать всегда».	The key is stored in the Keychain. macOS may ask for permission — choose “Always Allow”.	Der Schlüssel liegt im Schlüsselbund. macOS fragt eventuell nach — wählen Sie „Immer erlauben“.	La clave se guarda en el Llavero. macOS puede pedir permiso: elija «Permitir siempre».
Разрешить доступ	Allow access	Zugriff erlauben	Permitir acceso
Доступ к ключу есть	Key access granted	Zugriff auf den Schlüssel erlaubt	Acceso a la clave concedido
Доступ не выдан — ключ не прочитан	Access not granted — the key was not read	Zugriff nicht erteilt — Schlüssel nicht gelesen	Acceso no concedido: la clave no se leyó
Связка ключей не ответила	The Keychain did not respond	Der Schlüsselbund hat nicht geantwortet	El Llavero no respondió
нет доступа	no access	kein Zugriff	sin acceso
НЕТ ДОСТУПА	NO ACCESS	KEIN ZUGRIFF	SIN ACCESO
Нет доступа к ключу в Связке ключей	No access to the key in the Keychain	Kein Zugriff auf den Schlüssel im Schlüsselbund	Sin acceso a la clave en el Llavero
Вышла версия %@. Что нового: %@. Обновить можно из меню	Version %@ is out. What's new: %@. Update from the menu	Version %@ ist da. Neu: %@. Update über das Menü	Ya salió la versión %@. Novedades: %@. Actualiza desde el menú
"""#
}
