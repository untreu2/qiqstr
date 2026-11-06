import Foundation

public struct CoreError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public func coreErrorMessage(_ error: Error) -> String {
    if let qiq = error as? QiqError, case .Failed(let message) = qiq { return message }
    if let core = error as? CoreError { return core.message }
    return error.localizedDescription
}
