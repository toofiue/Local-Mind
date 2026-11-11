import CommonCrypto
import Foundation

/// One person using Local Mind on this Mac: a name, their own chats, and an optional password.
/// Models are shared, since they belong to Ollama.
public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var hasPassword: Bool
    /// The first profile keeps the chats that existed before profiles, where they always were.
    public var isOriginal: Bool

    public init(id: UUID = UUID(), name: String, hasPassword: Bool = false, isOriginal: Bool = false) {
        self.id = id
        self.name = name
        self.hasPassword = hasPassword
        self.isOriginal = isOriginal
    }

    /// The first letter, for the round badge in the sidebar.
    public var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

/// Every profile, and which one is in use. Saved as a small JSON file next to the chats.
public struct ProfileList: Codable, Equatable, Sendable {
    public var profiles: [Profile]
    public var currentID: UUID

    public init(profiles: [Profile], currentID: UUID) {
        self.profiles = profiles
        self.currentID = currentID
    }

    /// Before any profile exists: one profile, owning the chats already on this Mac.
    public static func first(named name: String) -> ProfileList {
        let profile = Profile(name: name.isEmpty ? "Me" : name, isOriginal: true)
        return ProfileList(profiles: [profile], currentID: profile.id)
    }

    public var current: Profile {
        profiles.first { $0.id == currentID } ?? profiles[0]
    }

    /// Where a profile's chats live, inside the app's own folder.
    /// The original profile keeps the old place, so nothing has to move.
    public static func storeURL(for profile: Profile, in folder: URL) -> URL {
        if profile.isOriginal { return folder.appending(path: "Lantern.store") }
        return folder.appending(path: "Profiles", directoryHint: .isDirectory)
            .appending(path: profile.id.uuidString, directoryHint: .isDirectory)
            .appending(path: "Lantern.store")
    }

    /// A trimmed, non-empty name that no other profile uses, or nil.
    public func validName(_ raw: String, excluding id: UUID? = nil) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !profiles.contains(where: { $0.id != id && $0.name.compare(name, options: .caseInsensitive) == .orderedSame })
        else { return nil }
        return name
    }
}

/// Passwords are never kept. Only a salted, slow hash is, so the password can be checked but not read back.
public enum PasswordHash {
    public static let rounds: UInt32 = 200_000

    /// "salt:hash", both in base64.
    public static func make(_ password: String, salt: Data = randomSalt()) -> String {
        "\(salt.base64EncodedString()):\(derive(password, salt: salt).base64EncodedString())"
    }

    public static func verify(_ password: String, against stored: String) -> Bool {
        let parts = stored.split(separator: ":").map(String.init)
        guard parts.count == 2, let salt = Data(base64Encoded: parts[0]), let expected = Data(base64Encoded: parts[1]) else {
            return false
        }
        let actual = derive(password, salt: salt)
        // Compare every byte, so timing doesn't hint at how much matched.
        return actual.count == expected.count && zip(actual, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    public static func randomSalt() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    }

    private static func derive(_ password: String, salt: Data) -> Data {
        var key = Data(count: 32)
        let passwordBytes = Array(password.utf8)
        _ = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     passwordBytes.map { Int8(bitPattern: $0) }, passwordBytes.count,
                                     saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                     keyBytes.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        return key
    }
}
