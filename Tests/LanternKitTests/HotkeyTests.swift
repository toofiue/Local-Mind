import Carbon.HIToolbox
import Foundation
import Testing
@testable import LanternKit

@Test("S-032 shortcuts read the way menus write them")
func displaysHotkeys() {
    #expect(Hotkey.standard.display == "⌃⌥Space")
    #expect(Hotkey(keyCode: kVK_ANSI_K, modifiers: cmdKey | shiftKey).display == "⇧⌘K")
    #expect(Hotkey(keyCode: kVK_F5, modifiers: optionKey).display == "⌥F5")
}

@Test("S-032 a shortcut needs a real modifier", arguments: [(0, false), (shiftKey, false), (cmdKey, true), (controlKey, true), (optionKey | shiftKey, true)])
func requiresModifier(modifiers: Int, allowed: Bool) {
    #expect(Hotkey(keyCode: kVK_ANSI_K, modifiers: modifiers).hasRequiredModifier == allowed)
}

@Test("S-032 a shortcut survives being saved and read back")
func savesHotkeys() throws {
    let hotkey = Hotkey(keyCode: kVK_ANSI_K, modifiers: controlKey | shiftKey)
    let data = try JSONEncoder().encode(hotkey)
    #expect(try JSONDecoder().decode(Hotkey.self, from: data) == hotkey)
}

@Test("S-032 menus get a character only for keys that have one")
func menuCharacters() {
    #expect(Hotkey.standard.character == " ")
    #expect(Hotkey(keyCode: kVK_ANSI_K, modifiers: cmdKey).character == "k")
    #expect(Hotkey(keyCode: kVK_F5, modifiers: cmdKey).character == nil)
}
