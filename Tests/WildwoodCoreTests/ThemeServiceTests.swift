// ThemeService persists the selected theme under the shared ww_theme key.
// Mirrors the JS themeService tests (default, initialize-from-storage, setTheme).

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct ThemeServiceTests {
    private func makeService(storage: MemoryStorage = MemoryStorage()) -> (ThemeService, MemoryStorage) {
        let service = ThemeService(storage: storage, events: WildwoodEventEmitter())
        return (service, storage)
    }

    @Test func defaultsToWoodlandWarmBeforeInitialize() {
        let (service, _) = makeService()
        #expect(service.theme == WildwoodThemeNames.woodlandWarm)
    }

    @Test func initializeLoadsPersistedTheme() {
        let storage = MemoryStorage()
        storage.setItem(WildwoodStorageKeys.theme, "cool-blue")
        let (service, _) = makeService(storage: storage)

        service.initialize()

        #expect(service.theme == "cool-blue")
    }

    @Test func initializeIgnoresAnEmptyStoredValue() {
        let storage = MemoryStorage()
        storage.setItem(WildwoodStorageKeys.theme, "")
        let (service, _) = makeService(storage: storage)

        service.initialize()

        #expect(service.theme == WildwoodThemeNames.woodlandWarm)
    }

    @Test func setThemePersistsUnderTheThemeKey() {
        let (service, storage) = makeService()

        service.setTheme("fall-colors")

        #expect(service.theme == "fall-colors")
        #expect(storage.getItem(WildwoodStorageKeys.theme) == "fall-colors")
    }

    @Test func initializeDoesNotEmitButSetThemeEmitsThemeChanged() {
        let storage = MemoryStorage()
        storage.setItem(WildwoodStorageKeys.theme, "cool-blue")
        let events = WildwoodEventEmitter()
        let service = ThemeService(storage: storage, events: events)
        var received: [String] = []
        events.on { event in
            if case .themeChanged(let name) = event { received.append(name) }
        }

        service.initialize()
        #expect(service.theme == "cool-blue")
        #expect(received.isEmpty)   // JS parity: the restore is observable via `theme`, not an event

        service.setTheme("fall-colors")
        #expect(received == ["fall-colors"])
    }
}
