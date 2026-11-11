import AppKit
import LanternKit
import Observation
import Security

/// Who is using Local Mind: the profile list, its file, and each profile's password hash in the Keychain.
/// Each profile has its own chats; switching restarts the app on the other profile's chats.
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    private(set) var list: ProfileList
    var current: Profile { list.current }
    /// Bumped when a photo changes, so badges redraw.
    private(set) var photoVersion = 0
    @ObservationIgnored private var photoCache: [UUID: NSImage] = [:]

    /// The app's folder: ~/Library/Application Support/Lantern. Tests and snapshots use their own /tmp place.
    private let folder: URL
    private let listURL: URL
    /// Tests keep hashes in memory instead of the Keychain.
    private var testHashes: [UUID: String] = [:]

    private init() {
        if Store.isOverridden {
            let store = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APP_STORE"] ?? "/tmp/Lantern.store")
            folder = store.deletingLastPathComponent().appending(path: store.lastPathComponent + "-profiles", directoryHint: .isDirectory)
        } else {
            folder = URL.applicationSupportDirectory.appending(path: "Lantern", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        listURL = folder.appending(path: "Profiles.json")
        if let data = try? Data(contentsOf: listURL), let saved = try? JSONDecoder().decode(ProfileList.self, from: data), !saved.profiles.isEmpty {
            list = saved
        } else {
            // First run with profiles: one profile, named after this Mac's account, owns the existing chats.
            list = .first(named: NSFullUserName().split(separator: " ").first.map(String.init) ?? "")
            save()
        }
    }

    /// Where a profile's chats live. Under a test override, the original profile uses the test store itself.
    func storeURL(for profile: Profile) -> URL {
        if Store.isOverridden, profile.isOriginal {
            return URL(fileURLWithPath: ProcessInfo.processInfo.environment["APP_STORE"] ?? "/tmp/Lantern.store")
        }
        let url = ProfileList.storeURL(for: profile, in: folder)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    // MARK: Photos

    /// A profile's photo, kept as a 256-pixel square beside its conversations.
    private func photoURL(for id: UUID) -> URL {
        let dir = folder.appending(path: "Profiles", directoryHint: .isDirectory).appending(path: id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "Photo.png")
    }

    func photo(for id: UUID) -> NSImage? {
        _ = photoVersion
        if let cached = photoCache[id] { return cached }
        let image = NSImage(contentsOf: photoURL(for: id))
        photoCache[id] = image
        return image
    }

    /// Crops the picture to a centered square and saves it small. Returns false for a file that isn't a picture.
    @discardableResult
    func setPhoto(from url: URL, for id: UUID) -> Bool {
        guard let source = NSImage(contentsOf: url), let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let side = min(cg.width, cg.height)
        let crop = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)
        guard let square = cg.cropping(to: crop),
              let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        guard let small = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: small).representation(using: .png, properties: [:]),
              (try? png.write(to: photoURL(for: id))) != nil
        else { return false }
        photoCache[id] = nil
        photoVersion += 1
        return true
    }

    func removePhoto(for id: UUID) {
        try? FileManager.default.removeItem(at: photoURL(for: id))
        photoCache[id] = nil
        photoVersion += 1
    }

    // MARK: Changes

    @discardableResult
    func add(name: String, password: String) -> Profile? {
        guard let name = list.validName(name) else { return nil }
        let profile = Profile(name: name, hasPassword: !password.isEmpty)
        if !password.isEmpty { storeHash(PasswordHash.make(password), for: profile.id) }
        list.profiles.append(profile)
        save()
        return profile
    }

    func rename(_ id: UUID, to raw: String) -> Bool {
        guard let name = list.validName(raw, excluding: id), let index = list.profiles.firstIndex(where: { $0.id == id }) else { return false }
        list.profiles[index].name = name
        save()
        return true
    }

    /// An empty password removes it.
    func setPassword(_ password: String, for id: UUID) {
        guard let index = list.profiles.firstIndex(where: { $0.id == id }) else { return }
        if password.isEmpty {
            deleteHash(for: id)
        } else {
            storeHash(PasswordHash.make(password), for: id)
        }
        list.profiles[index].hasPassword = !password.isEmpty
        save()
    }

    func checkPassword(_ password: String, for id: UUID) -> Bool {
        guard let profile = list.profiles.first(where: { $0.id == id }) else { return false }
        guard profile.hasPassword else { return true }
        guard let stored = readHash(for: id) else { return false }
        return PasswordHash.verify(password, against: stored)
    }

    /// Moves a profile's chats to the Trash, where they can still be put back, and forgets the profile.
    func remove(_ id: UUID) {
        guard let profile = list.profiles.first(where: { $0.id == id }), !profile.isOriginal else { return }
        let profileFolder = storeURL(for: profile).deletingLastPathComponent()
        try? FileManager.default.trashItem(at: profileFolder, resultingItemURL: nil)
        deleteHash(for: id)
        list.profiles.removeAll { $0.id == id }
        if list.currentID == id { list.currentID = list.profiles[0].id }
        save()
    }

    /// Makes another profile current, then restarts on its chats. Tests only change the list.
    func switchTo(_ id: UUID) {
        guard list.profiles.contains(where: { $0.id == id }), id != list.currentID else { return }
        list.currentID = id
        save()
        guard !Store.isOverridden else { return }
        Self.relaunch()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: listURL, options: .atomic)
    }

    /// Quits, then opens the app again a moment later, after this copy has let go of its shortcut and files.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: Keychain

    private static let service = "Local Mind Profiles"

    private func storeHash(_ hash: String, for id: UUID) {
        if Store.isOverridden { testHashes[id] = hash; return }
        deleteHash(for: id)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: Self.service,
                                   kSecAttrAccount as String: id.uuidString,
                                   kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                   kSecValueData as String: Data(hash.utf8)]
        SecItemAdd(item as CFDictionary, nil)
    }

    private func readHash(for id: UUID) -> String? {
        if Store.isOverridden { return testHashes[id] }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: id.uuidString,
                                    kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteHash(for id: UUID) {
        if Store.isOverridden { testHashes[id] = nil; return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: id.uuidString]
        SecItemDelete(query as CFDictionary)
    }
}
