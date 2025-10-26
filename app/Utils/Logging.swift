import os.log

enum Logger {
    static let subsystem = "com.fingercursor.app"

    static let lifecycle = os.Logger(subsystem: subsystem, category: "lifecycle")
    static let permissions = os.Logger(subsystem: subsystem, category: "permissions")
    static let tracking = os.Logger(subsystem: subsystem, category: "tracking")
    static let gestures = os.Logger(subsystem: subsystem, category: "gestures")
    static let dictation = os.Logger(subsystem: subsystem, category: "dictation")
    static let config = os.Logger(subsystem: subsystem, category: "config")
}
