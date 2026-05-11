//
//  LocalizationManager.swift
//  BluetoothTesting
//

import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Codable {
    case english    = "en"
    case spanish    = "es"
    case dutch      = "nl"
    case french     = "fr"
    case japanese   = "ja"
    case portuguese = "pt"

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Español"
        case .dutch:      return "Nederlands"
        case .french:     return "Français"
        case .japanese:   return "日本語"
        case .portuguese: return "Português"
        }
    }
}

enum LocKey: Hashable {
    case settings, hardware, back
    case deviceName
    case sensitivity, low, medium, high
    case alarmLoudness, alarmNone, alarmCalm, alarmNormal, alarmLoud
    case alarmDuration, alarmDurationCaption
    case silentWhenConnected, silentWhenConnectedCaption
    case pingDevice, forgetDevice
    case disableDisconnectSound, disableDisconnectSoundCaption
    case disableAlarm, disableAlarmCaption
    case ledBrightness, disableLED, disableLEDCaption
    case disableMotionLogging, disableMotionLoggingCaption
    case language
    case restartDevice, restartDeviceTitle, restartDeviceMessage, restart
    case locked, unlocked, locking
    case connect, connecting, connected, disconnect
    case motionLogs, deviceNotInRange
    case forgetTitle, forgetMessage, cancel, forgetConfirm
    case resetTitle, resetMessage, reset
    case holdToLock, holdToUnlock, holdToStop
    case addAWatchDog, searchingForWatchDogs, tapToPair, pairing, paired
    case noDeviceTryDemo
    case skip, done, ok, no, go
    case yourWatchDogs
    case appSettings
    case wipeAppData, wipeAppDataConfirmTitle, wipeAppDataConfirmMessage, wipe
    case disconnectOnBackground, disconnectOnBackgroundCaption
    case setToDefaultSettings, setToDefaultSettingsTitle, setToDefaultSettingsMessage
    case unknownTime
}

@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()

    private let storageKey = "watchdog_app_language"

    var current: AppLanguage {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: storageKey) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: raw) {
            self.current = lang
        } else {
            self.current = .english
        }
    }

    func t(_ key: LocKey) -> String {
        Self.table[current]?[key] ?? Self.table[.english]?[key] ?? ""
    }

    private static let table: [AppLanguage: [LocKey: String]] = [
        .english: [
            .settings: "Settings",
            .hardware: "Hardware",
            .back: "Back",
            .deviceName: "Device Name",
            .sensitivity: "Sensitivity",
            .low: "Low", .medium: "Medium", .high: "High",
            .alarmLoudness: "Alarm Loudness",
            .alarmNone: "None", .alarmCalm: "Calm",
            .alarmNormal: "Normal", .alarmLoud: "Loud",
            .alarmDuration: "Alarm Duration",
            .alarmDurationCaption: "How long the alarm continues sounding once the device comes to rest after a motion event.",
            .silentWhenConnected: "Silent When Connected",
            .silentWhenConnectedCaption: "Disable alarm when phone is connected",
            .pingDevice: "Ping This Device",
            .forgetDevice: "Forget This Device",
            .disableDisconnectSound: "Disable Disconnect Sound",
            .disableDisconnectSoundCaption: "Silences the chime that plays when the device disconnects.",
            .disableAlarm: "Disable Speaker",
            .disableAlarmCaption: "Completely disable the speaker.",
            .ledBrightness: "LED Brightness",
            .disableLED: "Disable LED",
            .disableLEDCaption: "Turns off all indicator lights except for charging status.",
            .disableMotionLogging: "Disable Motion Logging",
            .disableMotionLoggingCaption: "Completely disable motion logging functionality.",
            .language: "Language",
            .restartDevice: "Restart Device",
            .restartDeviceTitle: "Restart Device?",
            .restartDeviceMessage: "Are you sure you want to restart the WatchDog? The BLE connection will drop.",
            .restart: "Restart",
            .locked: "Locked", .unlocked: "Unlocked", .locking: "Locking",
            .connect: "Connect", .connecting: "Connecting…", .connected: "Connected",
            .disconnect: "Disconnect",
            .motionLogs: "Motion Logs",
            .deviceNotInRange: "Device not in range",
            .forgetTitle: "Forget WatchDog?",
            .forgetMessage: "Are you sure you want to forget %@? You'll need to pair again to reconnect.",
            .cancel: "Cancel", .forgetConfirm: "Forget Device",
            .resetTitle: "Reset Device?",
            .resetMessage: "This will immediately reboot the WatchDog. The BLE connection will drop.",
            .reset: "Reset",
            .holdToLock: "Hold to Lock",
            .holdToUnlock: "Hold to Unlock",
            .holdToStop: "Hold to Stop",
            .addAWatchDog: "Add a WatchDog",
            .searchingForWatchDogs: "Searching for WatchDogs...",
            .tapToPair: "Tap to pair",
            .pairing: "Pairing...",
            .paired: "Paired!",
            .skip: "Skip", .done: "Done", .ok: "OK", .no: "No", .go: "Go",
            .noDeviceTryDemo: "No device? Try demo",
            .yourWatchDogs: "Your WatchDogs",
            .appSettings: "App Settings",
            .wipeAppData: "Wipe App Data",
            .wipeAppDataConfirmTitle: "Wipe All App Data?",
            .wipeAppDataConfirmMessage: "This permanently deletes all bonded devices, custom names, motion logs, and preferences on this phone. This cannot be undone.",
            .wipe: "Wipe",
            .disconnectOnBackground: "Disconnect in Background",
            .disconnectOnBackgroundCaption: "Disconnect from the WatchDog after the app has been minimized for more than 5 seconds.",
            .setToDefaultSettings: "Set to Default Settings",
            .setToDefaultSettingsTitle: "Restore Default Settings?",
            .setToDefaultSettingsMessage: "This resets every WatchDog's sensitivity, alarm, duration, LED brightness, and other preferences back to their defaults. Bonded devices, custom names, and motion logs are kept.",
            .unknownTime: "Unknown time"
        ],
        .spanish: [
            .settings: "Ajustes",
            .hardware: "Hardware",
            .back: "Atrás",
            .deviceName: "Nombre del Dispositivo",
            .sensitivity: "Sensibilidad",
            .low: "Bajo", .medium: "Medio", .high: "Alto",
            .alarmLoudness: "Volumen de Alarma",
            .alarmNone: "Ninguno", .alarmCalm: "Suave",
            .alarmNormal: "Normal", .alarmLoud: "Fuerte",
            .alarmDuration: "Duración de Alarma",
            .alarmDurationCaption: "Cuánto tiempo continúa sonando la alarma una vez que el dispositivo se detiene tras un evento de movimiento.",
            .silentWhenConnected: "Silencio al Conectar",
            .silentWhenConnectedCaption: "Desactiva la alarma cuando el teléfono está conectado",
            .pingDevice: "Hacer Sonar el Dispositivo",
            .forgetDevice: "Olvidar Dispositivo",
            .disableDisconnectSound: "Desactivar Sonido de Desconexión",
            .disableDisconnectSoundCaption: "Silencia el tono que suena cuando el dispositivo se desconecta.",
            .disableAlarm: "Desactivar Altavoz",
            .disableAlarmCaption: "Desactiva el altavoz por completo.",
            .ledBrightness: "Brillo del LED",
            .disableLED: "Desactivar LED",
            .disableLEDCaption: "Apaga todas las luces indicadoras excepto la del estado de carga.",
            .disableMotionLogging: "Desactivar Registro de Movimiento",
            .disableMotionLoggingCaption: "Desactiva por completo la función de registro de movimiento.",
            .language: "Idioma",
            .restartDevice: "Reiniciar Dispositivo",
            .restartDeviceTitle: "¿Reiniciar Dispositivo?",
            .restartDeviceMessage: "¿Estás seguro de que quieres reiniciar el WatchDog? La conexión BLE se interrumpirá.",
            .restart: "Reiniciar",
            .locked: "Bloqueado", .unlocked: "Desbloqueado", .locking: "Bloqueando",
            .connect: "Conectar", .connecting: "Conectando…", .connected: "Conectado",
            .disconnect: "Desconectar",
            .motionLogs: "Registros de Movimiento",
            .deviceNotInRange: "Dispositivo fuera de alcance",
            .forgetTitle: "¿Olvidar WatchDog?",
            .forgetMessage: "¿Estás seguro de que quieres olvidar %@? Tendrás que emparejar de nuevo para reconectar.",
            .cancel: "Cancelar", .forgetConfirm: "Olvidar Dispositivo",
            .resetTitle: "¿Reiniciar Dispositivo?",
            .resetMessage: "Esto reiniciará el WatchDog inmediatamente. La conexión BLE se interrumpirá.",
            .reset: "Reiniciar",
            .holdToLock: "Mantén para Bloquear",
            .holdToUnlock: "Mantén para Desbloquear",
            .holdToStop: "Mantén para Detener",
            .addAWatchDog: "Añadir un WatchDog",
            .searchingForWatchDogs: "Buscando WatchDogs...",
            .tapToPair: "Toca para emparejar",
            .pairing: "Emparejando...",
            .paired: "¡Emparejado!",
            .skip: "Omitir", .done: "Listo", .ok: "OK", .no: "No", .go: "Ir",
            .noDeviceTryDemo: "¿Sin dispositivo? Probar demo",
            .yourWatchDogs: "Tus WatchDogs",
            .appSettings: "Ajustes de la App",
            .wipeAppData: "Borrar Datos de la App",
            .wipeAppDataConfirmTitle: "¿Borrar Todos los Datos?",
            .wipeAppDataConfirmMessage: "Esto elimina permanentemente todos los dispositivos emparejados, nombres personalizados, notas, registros de movimiento y preferencias en este teléfono. No se puede deshacer.",
            .wipe: "Borrar",
            .disconnectOnBackground: "Desconectar en Segundo Plano",
            .disconnectOnBackgroundCaption: "Desconectarse del WatchDog cuando la aplicación haya estado minimizada durante más de 5 segundos.",
            .setToDefaultSettings: "Restablecer Ajustes",
            .setToDefaultSettingsTitle: "¿Restablecer Ajustes por Defecto?",
            .setToDefaultSettingsMessage: "Esto restablece la sensibilidad, alarma, duración, brillo del LED y otras preferencias de cada WatchDog a sus valores predeterminados. Se conservan los dispositivos emparejados, nombres personalizados y registros de movimiento.",
            .unknownTime: "Hora desconocida"
        ],
        .dutch: [
            .settings: "Instellingen",
            .hardware: "Hardware",
            .back: "Terug",
            .deviceName: "Apparaatnaam",
            .sensitivity: "Gevoeligheid",
            .low: "Laag", .medium: "Gemiddeld", .high: "Hoog",
            .alarmLoudness: "Alarmvolume",
            .alarmNone: "Geen", .alarmCalm: "Rustig",
            .alarmNormal: "Normaal", .alarmLoud: "Luid",
            .alarmDuration: "Alarmduur",
            .alarmDurationCaption: "Hoe lang het alarm blijft klinken zodra het apparaat tot rust komt na een bewegingsgebeurtenis.",
            .silentWhenConnected: "Stil bij Verbinding",
            .silentWhenConnectedCaption: "Schakel het alarm uit wanneer de telefoon is verbonden",
            .pingDevice: "Apparaat Pingen",
            .forgetDevice: "Apparaat Vergeten",
            .disableDisconnectSound: "Verbreekgeluid Uitschakelen",
            .disableDisconnectSoundCaption: "Dempt de toon die klinkt wanneer het apparaat de verbinding verbreekt.",
            .disableAlarm: "Luidspreker Uitschakelen",
            .disableAlarmCaption: "Schakel de luidspreker volledig uit.",
            .ledBrightness: "LED-helderheid",
            .disableLED: "LED Uitschakelen",
            .disableLEDCaption: "Schakelt alle indicatorlampjes uit behalve voor de oplaadstatus.",
            .disableMotionLogging: "Bewegingsregistratie Uitschakelen",
            .disableMotionLoggingCaption: "Schakel de bewegingsregistratie volledig uit.",
            .language: "Taal",
            .restartDevice: "Apparaat Herstarten",
            .restartDeviceTitle: "Apparaat Herstarten?",
            .restartDeviceMessage: "Weet je zeker dat je de WatchDog wilt herstarten? De BLE-verbinding wordt verbroken.",
            .restart: "Herstarten",
            .locked: "Vergrendeld", .unlocked: "Ontgrendeld", .locking: "Vergrendelen",
            .connect: "Verbinden", .connecting: "Verbinden…", .connected: "Verbonden",
            .disconnect: "Verbreken",
            .motionLogs: "Bewegingslogboek",
            .deviceNotInRange: "Apparaat buiten bereik",
            .forgetTitle: "WatchDog Vergeten?",
            .forgetMessage: "Weet je zeker dat je %@ wilt vergeten? Je moet opnieuw koppelen om verbinding te maken.",
            .cancel: "Annuleren", .forgetConfirm: "Apparaat Vergeten",
            .resetTitle: "Apparaat Resetten?",
            .resetMessage: "Hierdoor wordt de WatchDog onmiddellijk opnieuw opgestart. De BLE-verbinding wordt verbroken.",
            .reset: "Resetten",
            .holdToLock: "Houd vast om te Vergrendelen",
            .holdToUnlock: "Houd vast om te Ontgrendelen",
            .holdToStop: "Houd vast om te Stoppen",
            .addAWatchDog: "WatchDog Toevoegen",
            .searchingForWatchDogs: "WatchDogs zoeken...",
            .tapToPair: "Tik om te koppelen",
            .pairing: "Koppelen...",
            .paired: "Gekoppeld!",
            .skip: "Overslaan", .done: "Klaar", .ok: "OK", .no: "Nee", .go: "Ga",
            .noDeviceTryDemo: "Geen apparaat? Probeer demo",
            .yourWatchDogs: "Jouw WatchDogs",
            .appSettings: "App-instellingen",
            .wipeAppData: "App-gegevens Wissen",
            .wipeAppDataConfirmTitle: "Alle App-gegevens Wissen?",
            .wipeAppDataConfirmMessage: "Dit verwijdert permanent alle gekoppelde apparaten, aangepaste namen, notities, bewegingslogboeken en voorkeuren op deze telefoon. Dit kan niet ongedaan worden gemaakt.",
            .wipe: "Wissen",
            .disconnectOnBackground: "Verbreken op Achtergrond",
            .disconnectOnBackgroundCaption: "Verbreek de verbinding met de WatchDog nadat de app meer dan 5 seconden is geminimaliseerd.",
            .setToDefaultSettings: "Standaardinstellingen Herstellen",
            .setToDefaultSettingsTitle: "Standaardinstellingen Herstellen?",
            .setToDefaultSettingsMessage: "Dit zet de gevoeligheid, alarm, duur, LED-helderheid en andere voorkeuren van elke WatchDog terug naar de standaardwaarden. Gekoppelde apparaten, aangepaste namen en bewegingslogboeken blijven behouden.",
            .unknownTime: "Tijd onbekend"
        ],
        .french: [
            .settings: "Réglages",
            .hardware: "Matériel",
            .back: "Retour",
            .deviceName: "Nom de l'Appareil",
            .sensitivity: "Sensibilité",
            .low: "Faible", .medium: "Moyenne", .high: "Élevée",
            .alarmLoudness: "Volume de l'Alarme",
            .alarmNone: "Aucun", .alarmCalm: "Doux",
            .alarmNormal: "Normal", .alarmLoud: "Fort",
            .alarmDuration: "Durée de l'Alarme",
            .alarmDurationCaption: "Durée pendant laquelle l'alarme continue de sonner une fois que l'appareil s'immobilise après un événement de mouvement.",
            .silentWhenConnected: "Silencieux Lorsque Connecté",
            .silentWhenConnectedCaption: "Désactiver l'alarme lorsque le téléphone est connecté",
            .pingDevice: "Faire Sonner l'Appareil",
            .forgetDevice: "Oublier l'Appareil",
            .disableDisconnectSound: "Désactiver le Son de Déconnexion",
            .disableDisconnectSoundCaption: "Coupe le son qui retentit lorsque l'appareil se déconnecte.",
            .disableAlarm: "Désactiver le Haut-parleur",
            .disableAlarmCaption: "Désactive complètement le haut-parleur.",
            .ledBrightness: "Luminosité de la LED",
            .disableLED: "Désactiver la LED",
            .disableLEDCaption: "Éteint tous les voyants sauf celui de l'état de charge.",
            .disableMotionLogging: "Désactiver le Journal de Mouvement",
            .disableMotionLoggingCaption: "Désactive complètement la fonction de journalisation des mouvements.",
            .language: "Langue",
            .restartDevice: "Redémarrer l'Appareil",
            .restartDeviceTitle: "Redémarrer l'Appareil ?",
            .restartDeviceMessage: "Êtes-vous sûr de vouloir redémarrer le WatchDog ? La connexion BLE sera interrompue.",
            .restart: "Redémarrer",
            .locked: "Verrouillé", .unlocked: "Déverrouillé", .locking: "Verrouillage",
            .connect: "Connecter", .connecting: "Connexion…", .connected: "Connecté",
            .disconnect: "Déconnecter",
            .motionLogs: "Journaux de Mouvement",
            .deviceNotInRange: "Appareil hors de portée",
            .forgetTitle: "Oublier le WatchDog ?",
            .forgetMessage: "Êtes-vous sûr de vouloir oublier %@ ? Vous devrez l'appairer à nouveau pour vous reconnecter.",
            .cancel: "Annuler", .forgetConfirm: "Oublier l'Appareil",
            .resetTitle: "Réinitialiser l'Appareil ?",
            .resetMessage: "Cela redémarrera immédiatement le WatchDog. La connexion BLE sera interrompue.",
            .reset: "Réinitialiser",
            .holdToLock: "Maintenir pour Verrouiller",
            .holdToUnlock: "Maintenir pour Déverrouiller",
            .holdToStop: "Maintenir pour Arrêter",
            .addAWatchDog: "Ajouter un WatchDog",
            .searchingForWatchDogs: "Recherche de WatchDogs...",
            .tapToPair: "Appuyer pour appairer",
            .pairing: "Appairage...",
            .paired: "Appairé !",
            .skip: "Passer", .done: "OK", .ok: "OK", .no: "Non", .go: "Aller",
            .noDeviceTryDemo: "Pas d'appareil ? Essayer la démo",
            .yourWatchDogs: "Vos WatchDogs",
            .appSettings: "Réglages de l'App",
            .wipeAppData: "Effacer les Données",
            .wipeAppDataConfirmTitle: "Effacer Toutes les Données ?",
            .wipeAppDataConfirmMessage: "Cela supprime définitivement tous les appareils appairés, noms personnalisés, notes, journaux de mouvement et préférences sur ce téléphone. Cette action est irréversible.",
            .wipe: "Effacer",
            .disconnectOnBackground: "Déconnecter en Arrière-plan",
            .disconnectOnBackgroundCaption: "Se déconnecter du WatchDog lorsque l'application est minimisée depuis plus de 5 secondes.",
            .setToDefaultSettings: "Rétablir les Réglages",
            .setToDefaultSettingsTitle: "Rétablir les Réglages par Défaut ?",
            .setToDefaultSettingsMessage: "Cela rétablit la sensibilité, l'alarme, la durée, la luminosité de la LED et les autres préférences de chaque WatchDog à leurs valeurs par défaut. Les appareils appairés, noms personnalisés et journaux de mouvement sont conservés.",
            .unknownTime: "Heure inconnue"
        ],
        .japanese: [
            .settings: "設定",
            .hardware: "ハードウェア",
            .back: "戻る",
            .deviceName: "デバイス名",
            .sensitivity: "感度",
            .low: "低", .medium: "中", .high: "高",
            .alarmLoudness: "アラーム音量",
            .alarmNone: "なし", .alarmCalm: "静か",
            .alarmNormal: "標準", .alarmLoud: "大",
            .alarmDuration: "アラーム持続時間",
            .alarmDurationCaption: "動作イベント後にデバイスが静止してから、アラームが鳴り続ける時間です。",
            .silentWhenConnected: "接続中はサイレント",
            .silentWhenConnectedCaption: "電話が接続されているときにアラームを無効にする",
            .pingDevice: "このデバイスを鳴らす",
            .forgetDevice: "このデバイスを削除",
            .disableDisconnectSound: "切断音を無効化",
            .disableDisconnectSoundCaption: "デバイスが切断されたときに鳴る通知音をミュートします。",
            .disableAlarm: "スピーカーを無効化",
            .disableAlarmCaption: "スピーカーを完全に無効にします。",
            .ledBrightness: "LEDの明るさ",
            .disableLED: "LEDを無効化",
            .disableLEDCaption: "充電状態を除き、すべてのインジケーターランプを消灯します。",
            .disableMotionLogging: "モーションログを無効化",
            .disableMotionLoggingCaption: "モーションログ機能を完全に無効にします。",
            .language: "言語",
            .restartDevice: "デバイスを再起動",
            .restartDeviceTitle: "デバイスを再起動しますか?",
            .restartDeviceMessage: "WatchDogを再起動してもよろしいですか？BLE接続は切断されます。",
            .restart: "再起動",
            .locked: "ロック中", .unlocked: "ロック解除", .locking: "ロック中…",
            .connect: "接続", .connecting: "接続中…", .connected: "接続済み",
            .disconnect: "切断",
            .motionLogs: "モーションログ",
            .deviceNotInRange: "デバイスが範囲外です",
            .forgetTitle: "WatchDogを削除しますか?",
            .forgetMessage: "%@を本当に削除しますか? 再接続するには再度ペアリングが必要です。",
            .cancel: "キャンセル", .forgetConfirm: "デバイスを削除",
            .resetTitle: "デバイスをリセットしますか?",
            .resetMessage: "WatchDogが直ちに再起動します。BLE接続は切断されます。",
            .reset: "リセット",
            .holdToLock: "長押しでロック",
            .holdToUnlock: "長押しでロック解除",
            .holdToStop: "長押しで停止",
            .addAWatchDog: "WatchDogを追加",
            .searchingForWatchDogs: "WatchDogを検索中...",
            .tapToPair: "タップしてペアリング",
            .pairing: "ペアリング中...",
            .paired: "ペアリング完了!",
            .skip: "スキップ", .done: "完了", .ok: "OK", .no: "いいえ", .go: "実行",
            .noDeviceTryDemo: "デバイスがない?デモを試す",
            .yourWatchDogs: "あなたのWatchDog",
            .appSettings: "アプリ設定",
            .wipeAppData: "アプリデータを消去",
            .wipeAppDataConfirmTitle: "すべてのアプリデータを消去しますか?",
            .wipeAppDataConfirmMessage: "ペアリング済みのデバイス、カスタム名、メモ、モーションログ、設定がすべて完全に削除されます。元に戻すことはできません。",
            .wipe: "消去",
            .disconnectOnBackground: "バックグラウンドで切断",
            .disconnectOnBackgroundCaption: "アプリが5秒以上バックグラウンドにある場合、WatchDogから切断します。",
            .setToDefaultSettings: "初期設定にリセット",
            .setToDefaultSettingsTitle: "初期設定に戻しますか?",
            .setToDefaultSettingsMessage: "各WatchDogの感度、アラーム、持続時間、LEDの明るさなどの設定が初期値に戻ります。ペアリング済みのデバイス、カスタム名、モーションログは保持されます。",
            .unknownTime: "時刻不明"
        ],
        .portuguese: [
            .settings: "Ajustes",
            .hardware: "Hardware",
            .back: "Voltar",
            .deviceName: "Nome do Dispositivo",
            .sensitivity: "Sensibilidade",
            .low: "Baixa", .medium: "Média", .high: "Alta",
            .alarmLoudness: "Volume do Alarme",
            .alarmNone: "Nenhum", .alarmCalm: "Suave",
            .alarmNormal: "Normal", .alarmLoud: "Forte",
            .alarmDuration: "Duração do Alarme",
            .alarmDurationCaption: "Quanto tempo o alarme continua a tocar depois que o dispositivo para após um evento de movimento.",
            .silentWhenConnected: "Silencioso Quando Conectado",
            .silentWhenConnectedCaption: "Desativar o alarme quando o telefone estiver conectado",
            .pingDevice: "Tocar Este Dispositivo",
            .forgetDevice: "Esquecer Dispositivo",
            .disableDisconnectSound: "Desativar Som de Desconexão",
            .disableDisconnectSoundCaption: "Silencia o tom que toca quando o dispositivo se desconecta.",
            .disableAlarm: "Desativar Altifalante",
            .disableAlarmCaption: "Desativa completamente o altifalante.",
            .ledBrightness: "Brilho do LED",
            .disableLED: "Desativar LED",
            .disableLEDCaption: "Desliga todas as luzes indicadoras, exceto o status de carregamento.",
            .disableMotionLogging: "Desativar Registo de Movimento",
            .disableMotionLoggingCaption: "Desativa completamente a função de registo de movimento.",
            .language: "Idioma",
            .restartDevice: "Reiniciar Dispositivo",
            .restartDeviceTitle: "Reiniciar Dispositivo?",
            .restartDeviceMessage: "Tem a certeza de que quer reiniciar o WatchDog? A conexão BLE será interrompida.",
            .restart: "Reiniciar",
            .locked: "Bloqueado", .unlocked: "Desbloqueado", .locking: "Bloqueando",
            .connect: "Conectar", .connecting: "Conectando…", .connected: "Conectado",
            .disconnect: "Desconectar",
            .motionLogs: "Registos de Movimento",
            .deviceNotInRange: "Dispositivo fora de alcance",
            .forgetTitle: "Esquecer WatchDog?",
            .forgetMessage: "Tem a certeza de que quer esquecer %@? Terá de emparelhar novamente para reconectar.",
            .cancel: "Cancelar", .forgetConfirm: "Esquecer Dispositivo",
            .resetTitle: "Reiniciar Dispositivo?",
            .resetMessage: "Isto irá reiniciar imediatamente o WatchDog. A conexão BLE será interrompida.",
            .reset: "Reiniciar",
            .holdToLock: "Manter para Bloquear",
            .holdToUnlock: "Manter para Desbloquear",
            .holdToStop: "Manter para Parar",
            .addAWatchDog: "Adicionar um WatchDog",
            .searchingForWatchDogs: "À procura de WatchDogs...",
            .tapToPair: "Tocar para emparelhar",
            .pairing: "A emparelhar...",
            .paired: "Emparelhado!",
            .skip: "Saltar", .done: "Concluído", .ok: "OK", .no: "Não", .go: "Ir",
            .noDeviceTryDemo: "Sem dispositivo? Experimentar demo",
            .yourWatchDogs: "Os Seus WatchDogs",
            .appSettings: "Ajustes da App",
            .wipeAppData: "Apagar Dados da App",
            .wipeAppDataConfirmTitle: "Apagar Todos os Dados?",
            .wipeAppDataConfirmMessage: "Isto apaga permanentemente todos os dispositivos emparelhados, nomes personalizados, notas, registos de movimento e preferências neste telefone. Esta ação não pode ser desfeita.",
            .wipe: "Apagar",
            .disconnectOnBackground: "Desconectar em Segundo Plano",
            .disconnectOnBackgroundCaption: "Desligar do WatchDog quando a app estiver minimizada há mais de 5 segundos.",
            .setToDefaultSettings: "Repor Predefinições",
            .setToDefaultSettingsTitle: "Repor Predefinições?",
            .setToDefaultSettingsMessage: "Isto repõe a sensibilidade, alarme, duração, brilho do LED e outras preferências de cada WatchDog para os valores predefinidos. Dispositivos emparelhados, nomes personalizados e registos de movimento são mantidos.",
            .unknownTime: "Hora desconhecida"
        ]
    ]
}
