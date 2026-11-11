import Foundation
import Testing
@testable import LanternKit

@Test("S-063 the right password passes and a wrong one fails")
func checksPasswords() {
    let stored = PasswordHash.make("open sesame")
    #expect(PasswordHash.verify("open sesame", against: stored))
    #expect(!PasswordHash.verify("open sesamE", against: stored))
    #expect(!stored.contains("open sesame"))
}

@Test("S-063 the same password hashes differently each time")
func saltsPasswords() {
    #expect(PasswordHash.make("same") != PasswordHash.make("same"))
}

@Test("S-063 the first profile keeps the existing chats where they are")
func originalKeepsStore() {
    let folder = URL(fileURLWithPath: "/tmp/app")
    let list = ProfileList.first(named: "Toufique")
    #expect(ProfileList.storeURL(for: list.current, in: folder).path == "/tmp/app/Lantern.store")
    let other = Profile(name: "Sam")
    #expect(ProfileList.storeURL(for: other, in: folder).path == "/tmp/app/Profiles/\(other.id.uuidString)/Lantern.store")
}

@Test("S-063 profile names are trimmed, never empty, and never repeated")
func validatesNames() {
    var list = ProfileList.first(named: "Toufique")
    #expect(list.validName("  Sam ") == "Sam")
    #expect(list.validName("   ") == nil)
    #expect(list.validName("toufique") == nil)
    #expect(list.validName("Toufique", excluding: list.currentID) == "Toufique")
    list.profiles.append(Profile(name: "Sam"))
    #expect(list.current.name == "Toufique")
}
