#include "fiber/browser/sessions/crash_restore.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <utility>

#import "FiberBridge/FiberPrompt.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/supports_user_data.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/prefs/session_startup_pref.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/sessions/exit_type_service.h"
#include "chrome/browser/sessions/session_restore.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/startup/startup_browser_creator.h"
#include "components/pref_registry/pref_registry_syncable.h"
#include "components/prefs/pref_service.h"
#include "fiber/browser/dialogs/prompt.h"
#include "fiber/browser/hooks/crash_restore.h"
#include "ui/base/base_window.h"

namespace fiber {

namespace {

constexpr char kRestoringAfterCrashPref[] = "fiber.restoring_after_crash";
// How long a restore after a crash is under way: a crash after this is taken
// as one of its own.
constexpr base::TimeDelta kRestoreSettleTime = base::Minutes(1);

const char kUserDataKey[] = "fiber.crash_restore";

enum ButtonID {
  kNotNow,
  kReopen,
};

// What the profile's launch does about its last session's crash.
class CrashRestore : public base::SupportsUserData::Data {
 public:
  static CrashRestore* FromProfile(Profile* profile) {
    auto* restore =
        static_cast<CrashRestore*>(profile->GetUserData(kUserDataKey));
    if (!restore) {
      auto owned = std::make_unique<CrashRestore>(profile);
      restore = owned.get();
      profile->SetUserData(kUserDataKey, std::move(owned));
    }
    return restore;
  }

  explicit CrashRestore(Profile* profile) : prefs_(profile->GetPrefs()) {
    const bool crashed =
        ExitTypeService::GetLastSessionExitType(profile) == ExitType::kCrashed;
    is_loop_ = crashed && prefs_->GetBoolean(kRestoringAfterCrashPref);
    prefs_->ClearPref(kRestoringAfterCrashPref);
    restores_ = crashed && !is_loop_ &&
                StartupBrowserCreator::GetSessionStartupPref(
                    *base::CommandLine::ForCurrentProcess(), profile)
                    .ShouldRestoreLastSession();
    if (restores_) {
      StartRestoring();
    }
    // ExitTypeService has just marked this session as open, in prefs written
    // seconds later: now, so a crash sooner counts as one next launch.
    prefs_->CommitPendingWrite();
  }

  bool restores() const { return restores_; }
  // The last session crashed while restoring after the one before did.
  bool is_loop() const { return is_loop_; }

  void StartRestoring() {
    prefs_->SetBoolean(kRestoringAfterCrashPref, true);
    // Now, since the crash it's for would come before the prefs' own write.
    prefs_->CommitPendingWrite();
    settle_timer_.Start(
        FROM_HERE, kRestoreSettleTime,
        base::BindOnce(&CrashRestore::OnSettled, base::Unretained(this)));
  }

 private:
  void OnSettled() { prefs_->ClearPref(kRestoringAfterCrashPref); }

  const raw_ptr<PrefService> prefs_;
  bool is_loop_ = false;
  bool restores_ = false;
  base::OneShotTimer settle_timer_;
};

FiberPromptContent* PromptContent(bool is_loop) {
  return [[FiberPromptContent alloc]
      initWithIcon:nil
             topic:FiberPromptTopicRestore
           eyebrow:@""
             title:is_loop ? @"Fiber quit while reopening your windows"
                           : @"Fiber quit unexpectedly"
           message:@"Reopen your windows now, or later from History › "
                   @"Previous Sessions."
       listHeading:@""
         listItems:@[]
           buttons:@[
             [[FiberPromptButton alloc]
                 initWithButtonID:kNotNow
                            title:@"Not Now"
                             role:FiberPromptButtonRoleCancel],
             [[FiberPromptButton alloc]
                 initWithButtonID:kReopen
                            title:@"Reopen Windows"
                             role:FiberPromptButtonRoleDefault],
           ]];
}

// Owns itself until it's answered.
class RestorePrompt {
 public:
  RestorePrompt(BrowserWindowInterface* browser, bool is_loop)
      : browser_(browser->GetWeakPtr()) {
    // Until it's answered, Chrome keeps the session that crashed.
    if (ExitTypeService* service =
            ExitTypeService::GetInstanceForProfile(browser->GetProfile())) {
      crashed_lock_ = service->CreateCrashedLock();
    }
    prompt_ = Prompt::Show(
        browser->GetWindow()->GetNativeWindow(), PromptContent(is_loop),
        base::BindOnce(&RestorePrompt::OnEnded, base::Unretained(this)));
  }

 private:
  // Deletes this.
  void OnEnded(std::optional<int> button_id) {
    std::unique_ptr<RestorePrompt> self(this);
    if (button_id != kReopen || !browser_) {
      return;
    }
    // Released once the restore has started, so the crash is only taken as
    // dealt with once it's done (see ExitTypeService).
    std::unique_ptr<ExitTypeService::CrashedLock> lock =
        std::move(crashed_lock_);
    CrashRestore::FromProfile(browser_->GetProfile())->StartRestoring();
    SessionRestore::RestoreSessionAfterCrash(browser_.get());
  }

  base::WeakPtr<BrowserWindowInterface> browser_;
  std::unique_ptr<ExitTypeService::CrashedLock> crashed_lock_;
  std::unique_ptr<Prompt> prompt_;
};

}  // namespace

bool RestoresAfterCrash(Profile* profile) {
  return !profile->IsOffTheRecord() &&
         CrashRestore::FromProfile(profile)->restores();
}

void OfferRestoreAfterCrash(BrowserWindowInterface* browser) {
  Profile* profile = browser->GetProfile();
  if (profile->IsOffTheRecord()) {
    return;
  }
  new RestorePrompt(browser, CrashRestore::FromProfile(profile)->is_loop());
}

void RegisterCrashRestorePrefs(user_prefs::PrefRegistrySyncable* registry) {
  registry->RegisterBooleanPref(kRestoringAfterCrashPref, false);
}

}  // namespace fiber
