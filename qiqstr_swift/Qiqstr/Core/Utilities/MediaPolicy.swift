import Foundation
import Network
import Observation

enum VideoAutoplay: String, CaseIterable, Identifiable {
    case never, wifi, always
    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: L("settingsAutoplayNever")
        case .wifi: L("settingsAutoplayWifi")
        case .always: L("settingsAutoplayAlways")
        }
    }
}

@MainActor
@Observable
final class MediaPolicy {
    static let shared = MediaPolicy()
    static let autoplayKey = "video_autoplay"
    static let dataSaverKey = "data_saver"

    private(set) var isExpensive = false
    private(set) var allowed: Set<String> = []
    var autoplay: VideoAutoplay {
        didSet { UserDefaults.standard.set(autoplay.rawValue, forKey: Self.autoplayKey) }
    }
    var dataSaver: Bool {
        didSet { UserDefaults.standard.set(dataSaver, forKey: Self.dataSaverKey) }
    }
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        autoplay = VideoAutoplay(rawValue: UserDefaults.standard.string(forKey: Self.autoplayKey) ?? "") ?? .never
        dataSaver = UserDefaults.standard.bool(forKey: Self.dataSaverKey)
        monitor.pathUpdateHandler = { path in
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in
                if MediaPolicy.shared.isExpensive != expensive { MediaPolicy.shared.isExpensive = expensive }
            }
        }
        monitor.start(queue: DispatchQueue(label: "me.untreu.qiqstr.network"))
    }

    var autoplaysVideo: Bool {
        guard !defersMedia else { return false }
        switch autoplay {
        case .never: return false
        case .wifi: return !isExpensive
        case .always: return true
        }
    }

    var defersMedia: Bool { dataSaver && isExpensive }

    func loads(_ url: String) -> Bool { !defersMedia || allowed.contains(url) }

    func allow(_ url: String) { allowed.insert(url) }
}
