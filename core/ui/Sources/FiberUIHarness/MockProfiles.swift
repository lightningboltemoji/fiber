import AppKit
import FiberBridge

/// Plays the part of //fiber/browser's profiles: a few made up, and Chrome
/// profiles to import from.
@MainActor
final class MockProfiles: NSObject, FiberProfileSwitcherActions {
  private struct Profile {
    let id: String
    let name: String
    let avatarIndex: Int
  }

  private weak var app: HarnessAppDelegate?
  private var profiles = [
    Profile(id: "Default", name: "Personal", avatarIndex: 27),
    Profile(id: "Profile 1", name: "Work", avatarIndex: 32),
    Profile(id: "Profile 2", name: "Side Project", avatarIndex: 40),
  ]
  private var currentProfileID = "Default"
  private var switcher: (any FiberProfileSwitcher)?
  private var importSteps: [DispatchWorkItem] = []

  init(app: HarnessAppDelegate) {
    self.app = app
  }

  func showSwitcher(in window: NSWindow, page: FiberProfileSwitcherPage) {
    guard switcher == nil else {
      switcher?.close()
      return
    }
    let chrome = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.google.Chrome")
    let content = FiberProfileSwitcherContent(
      profiles: profileStates(), newProfileAvatarIndex: 29,
      importBrowser: "Chrome",
      importIcon: chrome.map { NSWorkspace.shared.icon(forFile: $0.path) },
      importSources: [
        FiberImportSource(
          sourceID: 0, name: "Personal", detail: "you@example.com",
          avatarIndex: 29, picture: nil),
        FiberImportSource(
          sourceID: 1, name: "Work", detail: "you@work.example",
          avatarIndex: 33, picture: nil),
      ], page: page)
    switcher = FiberProfileSwitcherFactory.switcher(
      with: content, window: window, actions: self)
  }

  private func profileStates() -> [FiberProfile] {
    profiles.map {
      FiberProfile(
        profileID: $0.id, name: $0.name, avatarIndex: $0.avatarIndex,
        current: $0.id == currentProfileID)
    }
  }

  func switchToProfile(withID profileID: String) {
    currentProfileID = profileID
    app?.openWindow(urls: [MockBrowser.newTabURL])
  }

  func createProfile(withName name: String, avatarIndex: Int) {
    let profile = Profile(
      id: "Profile \(profiles.count)", name: name, avatarIndex: avatarIndex)
    profiles.append(profile)
    switchToProfile(withID: profile.id)
  }

  func importSource(withID sourceID: Int) {
    let steps = [
      "Waiting for access to Chrome’s passwords…",
      "Copying bookmarks and history…", "Copying passwords…",
    ]
    for (index, step) in steps.enumerated() {
      schedule(after: Double(index) * 1.2) { [weak self] in
        self?.switcher?.setImportProgress(step)
      }
    }
    schedule(after: Double(steps.count) * 1.2) { [weak self] in
      guard let self else {
        return
      }
      self.createProfile(
        withName: sourceID == 0 ? "Personal" : "Work",
        avatarIndex: sourceID == 0 ? 29 : 33)
      self.switcher?.close()
    }
  }

  func profileSwitcherDidClose() {
    switcher = nil
    importSteps.forEach { $0.cancel() }
    importSteps.removeAll()
  }

  private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void)
  {
    let item = DispatchWorkItem {
      MainActor.assumeIsolated { work() }
    }
    importSteps.append(item)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }
}
