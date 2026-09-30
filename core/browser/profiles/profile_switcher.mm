#include "fiber/browser/profiles/profile_switcher.h"

#import <AppKit/AppKit.h>

#include <optional>
#include <string>
#include <utility>
#include <vector>

#import "FiberBridge/FiberProfileSwitcher.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_attributes_entry.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_avatar_icon_util.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_window.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "fiber/browser/hooks/browser_window_factory.h"
#include "fiber/browser/profiles/chrome_import.h"

namespace fiber {
class ProfileSwitcher;
}  // namespace fiber

// Forwards what the user does to its ProfileSwitcher.
@interface FiberProfileSwitcherActionsBridge
    : NSObject <FiberProfileSwitcherActions>
- (instancetype)initWithOwner:(fiber::ProfileSwitcher*)owner;
- (void)detachOwner;
@end

namespace fiber {

// The switcher that's up, which it keeps up to date with the profiles. Owns
// itself until the UI is gone.
class ProfileSwitcher : public ProfileAttributesStorageObserver {
 public:
  static ProfileSwitcher* current() { return current_; }

  static void Open(base::WeakPtr<BrowserWindowInterface> browser,
                   ProfileSwitcherPage page,
                   std::vector<ChromeProfile> chrome_profiles);

  ProfileSwitcher(const ProfileSwitcher&) = delete;
  ProfileSwitcher& operator=(const ProfileSwitcher&) = delete;
  ~ProfileSwitcher() override;

  // Called by the UI's actions.
  void SwitchToProfile(const base::FilePath& path);
  void CreateProfile(const std::u16string& name, size_t avatar_index);
  void Import(size_t source_index);
  void DidClose();

  void Close();

  // ProfileAttributesStorageObserver:
  void OnProfileAdded(const base::FilePath& profile_path) override;
  void OnProfileWasRemoved(const base::FilePath& profile_path,
                           const std::u16string& profile_name) override;
  void OnProfileNameChanged(const base::FilePath& profile_path,
                            const std::u16string& old_profile_name) override;
  void OnProfileAvatarChanged(const base::FilePath& profile_path) override;
  void OnProfileIsOmittedChanged(const base::FilePath& profile_path) override;

 private:
  ProfileSwitcher(BrowserWindowInterface* browser,
                  ProfileSwitcherPage page,
                  std::vector<ChromeProfile> chrome_profiles);

  static ProfileAttributesStorage& Storage();
  NSArray<FiberProfile*>* ProfileStates() const;
  NSArray<FiberImportSource*>* ImportSources() const;
  void UpdateProfiles();
  void OnImportProgress(const std::u16string& step);
  void OnImportDone(std::optional<std::u16string> error);

  static inline ProfileSwitcher* current_ = nullptr;

  // Empty in an Incognito window, whose profile isn't one of these.
  base::FilePath current_profile_path_;
  std::vector<ChromeProfile> chrome_profiles_;
  base::ScopedObservation<ProfileAttributesStorage,
                          ProfileAttributesStorageObserver>
      observation_{this};
  FiberProfileSwitcherActionsBridge* __strong actions_;
  id<FiberProfileSwitcher> __strong ui_;
  base::WeakPtrFactory<ProfileSwitcher> weak_factory_{this};
};

}  // namespace fiber

@implementation FiberProfileSwitcherActionsBridge {
  raw_ptr<fiber::ProfileSwitcher> _owner;
}

- (instancetype)initWithOwner:(fiber::ProfileSwitcher*)owner {
  if ((self = [super init])) {
    _owner = owner;
  }
  return self;
}

- (void)detachOwner {
  _owner = nullptr;
}

- (void)switchToProfileWithID:(NSString*)profileID {
  if (_owner) {
    _owner->SwitchToProfile(
        base::FilePath(base::SysNSStringToUTF8(profileID)));
  }
}

- (void)createProfileWithName:(NSString*)name
                  avatarIndex:(NSInteger)avatarIndex {
  if (_owner) {
    _owner->CreateProfile(base::SysNSStringToUTF16(name), avatarIndex);
  }
}

- (void)importSourceWithID:(NSInteger)sourceID {
  if (_owner) {
    _owner->Import(sourceID);
  }
}

- (void)profileSwitcherDidClose {
  if (_owner) {
    _owner->DidClose();
  }
}

@end

namespace fiber {

namespace {

void OnNewProfileInitialized(size_t avatar_index, Profile* profile) {
  if (!profile) {
    return;
  }
  // Clears Chrome's note that the profile has the avatar it was given, not
  // one the user chose.
  profiles::SetDefaultProfileAvatarIndex(profile, avatar_index);
  profiles::OpenBrowserWindowForProfile(base::DoNothing(),
                                        /*always_create=*/false,
                                        /*is_new_profile=*/false,
                                        /*open_command_line_urls=*/false,
                                        profile);
}

}  // namespace

// static
void ProfileSwitcher::Open(base::WeakPtr<BrowserWindowInterface> browser,
                           ProfileSwitcherPage page,
                           std::vector<ChromeProfile> chrome_profiles) {
  if (!browser) {
    return;
  }
  CloseProfileSwitcher();
  current_ = new ProfileSwitcher(browser.get(), page, std::move(chrome_profiles));
}

ProfileSwitcher::ProfileSwitcher(BrowserWindowInterface* browser,
                                 ProfileSwitcherPage page,
                                 std::vector<ChromeProfile> chrome_profiles)
    : chrome_profiles_(std::move(chrome_profiles)),
      actions_([[FiberProfileSwitcherActionsBridge alloc] initWithOwner:this]) {
  Profile* profile = browser->GetProfile();
  if (!profile->IsOffTheRecord()) {
    current_profile_path_ = profile->GetPath();
  }
  observation_.Observe(&Storage());

  NSURL* chrome = [NSWorkspace.sharedWorkspace
      URLForApplicationWithBundleIdentifier:@"com.google.Chrome"];
  FiberProfileSwitcherContent* content = [[FiberProfileSwitcherContent alloc]
             initWithProfiles:ProfileStates()
        newProfileAvatarIndex:Storage().ChooseAvatarIconIndexForNewProfile()
                importBrowser:@"Chrome"
                   importIcon:chrome ? [NSWorkspace.sharedWorkspace
                                           iconForFile:chrome.path]
                                     : nil
                importSources:ImportSources()
                         page:page == ProfileSwitcherPage::kNewProfile
                                  ? FiberProfileSwitcherPageNewProfile
                                  : FiberProfileSwitcherPageProfiles];
  ui_ = [FiberProfileSwitcherFactory
      switcherWithContent:content
                   window:browser->GetWindow()
                              ->GetNativeWindow()
                              .GetNativeNSWindow()
                  actions:actions_];
}

ProfileSwitcher::~ProfileSwitcher() {
  [actions_ detachOwner];
}

void ProfileSwitcher::SwitchToProfile(const base::FilePath& path) {
  ProfileAttributesEntry* entry = Storage().GetProfileAttributesWithPath(path);
  // A locked profile opens Chrome's Profile Picker to sign in, which Fiber
  // can't.
  if (!entry || entry->IsSigninRequired() || path == current_profile_path_) {
    return;
  }
  profiles::SwitchToProfile(path, /*always_create=*/false);
}

void ProfileSwitcher::CreateProfile(const std::u16string& name,
                                    size_t avatar_index) {
  if (name.empty()) {
    return;
  }
  if (!profiles::IsDefaultAvatarIconIndex(avatar_index)) {
    avatar_index = profiles::GetPlaceholderAvatarIndex();
  }
  ProfileManager::CreateMultiProfileAsync(
      name, avatar_index, /*is_hidden=*/false,
      base::BindOnce(&OnNewProfileInitialized, avatar_index));
}

void ProfileSwitcher::Import(size_t source_index) {
  if (source_index >= chrome_profiles_.size()) {
    return;
  }
  ImportChromeProfile(
      chrome_profiles_[source_index],
      base::BindRepeating(&ProfileSwitcher::OnImportProgress,
                          weak_factory_.GetWeakPtr()),
      base::BindOnce(&ProfileSwitcher::OnImportDone,
                     weak_factory_.GetWeakPtr()));
}

// The UI may still be on the stack.
void ProfileSwitcher::DidClose() {
  if (current_ == this) {
    current_ = nullptr;
  }
  [actions_ detachOwner];
  weak_factory_.InvalidateWeakPtrs();
  observation_.Reset();
  base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
}

void ProfileSwitcher::Close() {
  id<FiberProfileSwitcher> ui = ui_;
  [ui close];
}

void ProfileSwitcher::OnProfileAdded(const base::FilePath& profile_path) {
  UpdateProfiles();
}

void ProfileSwitcher::OnProfileWasRemoved(const base::FilePath& profile_path,
                                          const std::u16string& profile_name) {
  UpdateProfiles();
}

void ProfileSwitcher::OnProfileNameChanged(
    const base::FilePath& profile_path,
    const std::u16string& old_profile_name) {
  UpdateProfiles();
}

void ProfileSwitcher::OnProfileAvatarChanged(
    const base::FilePath& profile_path) {
  UpdateProfiles();
}

void ProfileSwitcher::OnProfileIsOmittedChanged(
    const base::FilePath& profile_path) {
  UpdateProfiles();
}

// static
ProfileAttributesStorage& ProfileSwitcher::Storage() {
  return g_browser_process->profile_manager()->GetProfileAttributesStorage();
}

// In the order of Chrome's Profiles menu, less those Chrome leaves out of it
// (being set up, or about to be deleted).
NSArray<FiberProfile*>* ProfileSwitcher::ProfileStates() const {
  NSMutableArray<FiberProfile*>* states = [NSMutableArray array];
  for (ProfileAttributesEntry* entry :
       Storage().GetAllProfilesAttributesSortedByNameWithCheck()) {
    if (entry->IsOmitted()) {
      continue;
    }
    [states
        addObject:[[FiberProfile alloc]
                      initWithProfileID:base::SysUTF8ToNSString(
                                            entry->GetPath().value())
                                   name:base::SysUTF16ToNSString(
                                            entry->GetName())
                            avatarIndex:entry->GetAvatarIconIndex()
                                current:entry->GetPath() ==
                                        current_profile_path_]];
  }
  return states;
}

NSArray<FiberImportSource*>* ProfileSwitcher::ImportSources() const {
  NSMutableArray<FiberImportSource*>* sources = [NSMutableArray array];
  for (size_t i = 0; i < chrome_profiles_.size(); ++i) {
    const ChromeProfile& profile = chrome_profiles_[i];
    NSImage* picture =
        profile.picture.empty()
            ? nil
            : [[NSImage alloc]
                  initWithData:[NSData dataWithBytes:profile.picture.data()
                                              length:profile.picture.size()]];
    [sources addObject:[[FiberImportSource alloc]
                           initWithSourceID:i
                                       name:base::SysUTF16ToNSString(
                                                profile.name)
                                     detail:base::SysUTF16ToNSString(
                                                profile.user_name)
                                avatarIndex:profile.avatar_index
                                    picture:picture]];
  }
  return sources;
}

void ProfileSwitcher::UpdateProfiles() {
  [ui_ setProfiles:ProfileStates()];
}

void ProfileSwitcher::OnImportProgress(const std::u16string& step) {
  [ui_ setImportProgress:base::SysUTF16ToNSString(step)];
}

void ProfileSwitcher::OnImportDone(std::optional<std::u16string> error) {
  if (error) {
    [ui_ setImportFailure:base::SysUTF16ToNSString(*error)];
  } else {
    Close();
  }
}

void ShowProfileSwitcher(BrowserWindowInterface* browser,
                         ProfileSwitcherPage page) {
  // Chrome's profiles are read from disk first, to offer them for import.
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_BLOCKING},
      base::BindOnce(&FindChromeProfiles),
      base::BindOnce(&ProfileSwitcher::Open, browser->GetWeakPtr(), page));
}

void ShowProfileSwitcher(ProfileSwitcherPage page, bool may_open_window) {
  BrowserWindowInterface* browser =
      GetLastActiveBrowserWindowInterfaceWithAnyProfile();
  if (browser && IsFiberBrowser(browser) &&
      browser->GetType() == BrowserWindowInterface::TYPE_NORMAL) {
    ShowProfileSwitcher(browser, page);
    return;
  }
  if (!may_open_window) {
    return;
  }
  ProfileManager* manager = g_browser_process->profile_manager();
  const base::FilePath path = manager->GetLastUsedProfileDir();
  ProfileAttributesEntry* entry =
      manager->GetProfileAttributesStorage().GetProfileAttributesWithPath(
          path);
  if (!entry || entry->IsSigninRequired()) {
    return;
  }
  profiles::SwitchToProfile(
      path, /*always_create=*/false,
      base::BindOnce(
          [](ProfileSwitcherPage page, BrowserWindowInterface* browser) {
            if (browser) {
              ShowProfileSwitcher(browser, page);
            }
          },
          page));
}

void CloseProfileSwitcher() {
  if (ProfileSwitcher* switcher = ProfileSwitcher::current()) {
    switcher->Close();
  }
}

}  // namespace fiber
