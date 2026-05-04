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
    case disableAlarm, disableAlarmCaption
    case ledBrightness, disableLED, disableLEDCaption
    case disableMotionLogging, disableMotionLoggingCaption
    case language, installLatestFirmware
    case locked, unlocked, locking
    case connect, connecting, connected, disconnect
    case motionLogs, deviceNotInRange
    case forgetTitle, forgetMessage, cancel, forgetConfirm
    case resetTitle, resetMessage, reset
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
            .disableAlarm: "Disable Alarm",
            .disableAlarmCaption: "Completely disable the alarm regardless of triggers.",
            .ledBrightness: "LED Brightness",
            .disableLED: "Disable LED",
            .disableLEDCaption: "Turns off all indicator lights except for charging status.",
            .disableMotionLogging: "Disable Motion Logging",
            .disableMotionLoggingCaption: "Completely disable motion logging functionality.",
            .language: "Language",
            .installLatestFirmware: "Install Latest Firmware",
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
            .reset: "Reset"
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
            .disableAlarm: "Desactivar Alarma",
            .disableAlarmCaption: "Desactiva la alarma por completo sin importar los disparadores.",
            .ledBrightness: "Brillo del LED",
            .disableLED: "Desactivar LED",
            .disableLEDCaption: "Apaga todas las luces indicadoras excepto la del estado de carga.",
            .disableMotionLogging: "Desactivar Registro de Movimiento",
            .disableMotionLoggingCaption: "Desactiva por completo la función de registro de movimiento.",
            .language: "Idioma",
            .installLatestFirmware: "Instalar Último Firmware",
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
            .reset: "Reiniciar"
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
            .disableAlarm: "Alarm Uitschakelen",
            .disableAlarmCaption: "Schakel het alarm volledig uit ongeacht de triggers.",
            .ledBrightness: "LED-helderheid",
            .disableLED: "LED Uitschakelen",
            .disableLEDCaption: "Schakelt alle indicatorlampjes uit behalve voor de oplaadstatus.",
            .disableMotionLogging: "Bewegingsregistratie Uitschakelen",
            .disableMotionLoggingCaption: "Schakel de bewegingsregistratie volledig uit.",
            .language: "Taal",
            .installLatestFirmware: "Nieuwste Firmware Installeren",
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
            .reset: "Resetten"
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
            .disableAlarm: "Désactiver l'Alarme",
            .disableAlarmCaption: "Désactive complètement l'alarme quels que soient les déclencheurs.",
            .ledBrightness: "Luminosité de la LED",
            .disableLED: "Désactiver la LED",
            .disableLEDCaption: "Éteint tous les voyants sauf celui de l'état de charge.",
            .disableMotionLogging: "Désactiver le Journal de Mouvement",
            .disableMotionLoggingCaption: "Désactive complètement la fonction de journalisation des mouvements.",
            .language: "Langue",
            .installLatestFirmware: "Installer le Dernier Firmware",
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
            .reset: "Réinitialiser"
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
            .disableAlarm: "アラームを無効化",
            .disableAlarmCaption: "トリガーに関係なく、アラームを完全に無効にします。",
            .ledBrightness: "LEDの明るさ",
            .disableLED: "LEDを無効化",
            .disableLEDCaption: "充電状態を除き、すべてのインジケーターランプを消灯します。",
            .disableMotionLogging: "モーションログを無効化",
            .disableMotionLoggingCaption: "モーションログ機能を完全に無効にします。",
            .language: "言語",
            .installLatestFirmware: "最新のファームウェアをインストール",
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
            .reset: "リセット"
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
            .disableAlarm: "Desativar Alarme",
            .disableAlarmCaption: "Desativa completamente o alarme, independentemente dos gatilhos.",
            .ledBrightness: "Brilho do LED",
            .disableLED: "Desativar LED",
            .disableLEDCaption: "Desliga todas as luzes indicadoras, exceto o status de carregamento.",
            .disableMotionLogging: "Desativar Registo de Movimento",
            .disableMotionLoggingCaption: "Desativa completamente a função de registo de movimento.",
            .language: "Idioma",
            .installLatestFirmware: "Instalar Firmware Mais Recente",
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
            .reset: "Reiniciar"
        ]
    ]
}
