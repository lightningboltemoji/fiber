#include "fiber/browser/sessions/previous_sessions.h"

#include <algorithm>
#include <map>
#include <optional>
#include <utility>

#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/sessions/session_restore.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/common/webui_url_constants.h"
#include "components/history/core/browser/history_types.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/sessions/core/command_storage_backend.h"
#include "components/sessions/core/session_constants.h"
#include "components/sessions/core/session_service_commands.h"
#include "components/sessions/core/session_types.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/url_constants.h"
#include "fiber/browser/hooks/previous_session.h"

namespace fiber {

namespace {

const char kUserDataKey[] = "fiber.previous_sessions";

using Commands = std::vector<std::unique_ptr<sessions::SessionCommand>>;
using Windows = std::vector<std::unique_ptr<sessions::SessionWindow>>;

// Parsing sessions takes the UI thread, so the first read waits until well
// after startup.
constexpr base::TimeDelta kFirstReadDelay = base::Seconds(10);

bool IsNewTabPage(const GURL& url) {
  return url.SchemeIs(content::kChromeUIScheme) &&
         url.host() == chrome::kChromeUINewTabHost;
}

Commands ReadCommands(const base::FilePath& path) {
  return sessions::CommandStorageBackend::ReadCommandsFromFile(path).commands;
}

// The session's ordinary windows: not popups, apps or DevTools. On the UI
// thread, where session IDs are made.
Windows ParseWindows(const Commands& commands) {
  Windows windows;
  SessionID active_window_id = SessionID::InvalidValue();
  std::string platform_session_id;
  std::set<SessionID> discarded_window_ids;
  sessions::RestoreSessionFromCommands(commands, &windows, &active_window_id,
                                       &platform_session_id,
                                       &discarded_window_ids);
  std::erase_if(windows, [](const auto& window) {
    return window->type != sessions::SessionWindow::TYPE_NORMAL ||
           window->tabs.empty();
  });
  return windows;
}

void DeleteFiles(const std::vector<base::FilePath>& paths) {
  for (const base::FilePath& path : paths) {
    base::DeleteFile(path);
  }
}

}  // namespace

PreviousSessions::Session::Session() = default;
PreviousSessions::Session::Session(const Session&) = default;
PreviousSessions::Session::Session(Session&&) = default;
PreviousSessions::Session& PreviousSessions::Session::operator=(
    const Session&) = default;
PreviousSessions::Session& PreviousSessions::Session::operator=(Session&&) =
    default;
PreviousSessions::Session::~Session() = default;

struct PreviousSessions::ReadFile {
  base::FilePath path;
  base::Time ended;
  // Unless it was read before.
  std::optional<Commands> commands;
};

// static
std::vector<PreviousSessions::ReadFile> PreviousSessions::ReadFiles(
    const base::FilePath& dir,
    const std::set<base::FilePath>& known) {
  std::vector<ReadFile> files;
  base::FileEnumerator enumerator(dir, /*recursive=*/false,
                                  base::FileEnumerator::FILES);
  for (base::FilePath path = enumerator.Next(); !path.empty();
       path = enumerator.Next()) {
    ReadFile& file = files.emplace_back();
    file.path = path;
    file.ended = enumerator.GetInfo().GetLastModifiedTime();
    if (!known.contains(path)) {
      file.commands = ReadCommands(path);
    }
  }
  return files;
}

// static
std::optional<PreviousSessions::Session> PreviousSessions::ParseSession(
    const ReadFile& file) {
  Session session;
  session.path = file.path;
  session.ended = file.ended;
  for (const auto& window : ParseWindows(*file.commands)) {
    std::vector<Tab> tabs;
    for (const auto& tab : window->tabs) {
      if (tab->navigations.empty()) {
        continue;
      }
      const sessions::SerializedNavigationEntry& entry =
          tab->navigations[tab->normalized_navigation_index()];
      tabs.push_back({entry.title(), entry.virtual_url()});
    }
    if (!tabs.empty()) {
      session.windows.push_back(std::move(tabs));
    }
  }
  if (session.Pages().empty()) {
    return std::nullopt;
  }
  return session;
}

std::set<GURL> PreviousSessions::Session::Pages() const {
  std::set<GURL> pages;
  for (const std::vector<Tab>& tabs : windows) {
    for (const Tab& tab : tabs) {
      if (!IsNewTabPage(tab.url)) {
        pages.insert(tab.url);
      }
    }
  }
  return pages;
}

size_t PreviousSessions::Session::TabCount() const {
  size_t count = 0;
  for (const std::vector<Tab>& tabs : windows) {
    count += tabs.size();
  }
  return count;
}

// static
PreviousSessions* PreviousSessions::FromProfile(Profile* profile) {
  if (!profile || profile->IsOffTheRecord() || profile->IsGuestSession()) {
    return nullptr;
  }
  auto* previous =
      static_cast<PreviousSessions*>(profile->GetUserData(kUserDataKey));
  if (!previous) {
    auto owned = std::make_unique<PreviousSessions>(profile);
    previous = owned.get();
    profile->SetUserData(kUserDataKey, std::move(owned));
  }
  return previous;
}

PreviousSessions::PreviousSessions(Profile* profile)
    : profile_(profile),
      dir_(profile->GetPath()
               .Append(sessions::kSessionsDirectory)
               .Append(kPreviousSessionsDirName)),
      task_runner_(base::ThreadPool::CreateSequencedTaskRunner(
          {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
           base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN})) {
  if (history::HistoryService* history = HistoryServiceFactory::GetForProfile(
          profile, ServiceAccessType::EXPLICIT_ACCESS)) {
    history_observation_.Observe(history);
  }
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE,
      base::BindOnce(&PreviousSessions::Update, weak_factory_.GetWeakPtr()),
      kFirstReadDelay);
}

PreviousSessions::~PreviousSessions() = default;

std::vector<const PreviousSessions::Session*> PreviousSessions::Offered()
    const {
  std::set<GURL> open;
  ProfileBrowserCollection::GetForProfile(profile_)->ForEach(
      [&open](BrowserWindowInterface* browser) {
        TabStripModel* model = browser->GetTabStripModel();
        for (int i = 0; i < model->count(); ++i) {
          open.insert(model->GetWebContentsAt(i)->GetVisibleURL());
        }
        return true;
      });
  std::vector<const Session*> offered;
  for (const Session& session : sessions_) {
    if (!std::ranges::includes(open, session.Pages())) {
      offered.push_back(&session);
    }
  }
  return offered;
}

void PreviousSessions::Update() {
  if (is_reading_) {
    needs_read_ = true;
    return;
  }
  is_reading_ = true;
  std::set<base::FilePath> known;
  for (const Session& session : sessions_) {
    known.insert(session.path);
  }
  task_runner_->PostTaskAndReplyWithResult(
      FROM_HERE, base::BindOnce(&ReadFiles, dir_, std::move(known)),
      base::BindOnce(&PreviousSessions::OnRead, weak_factory_.GetWeakPtr(),
                     generation_));
}

void PreviousSessions::OnRead(int generation, std::vector<ReadFile> files) {
  is_reading_ = false;
  if (generation == generation_) {
    std::map<base::FilePath, Session> known;
    for (Session& session : sessions_) {
      known.emplace(session.path, std::move(session));
    }
    std::vector<Session> all;
    std::vector<base::FilePath> dropped;
    for (const ReadFile& file : files) {
      if (auto it = known.find(file.path); it != known.end()) {
        all.push_back(std::move(it->second));
      } else if (std::optional<Session> session = ParseSession(file)) {
        all.push_back(std::move(*session));
      } else {
        dropped.push_back(file.path);
      }
    }
    std::ranges::sort(all, std::ranges::greater(), &Session::ended);
    sessions_.clear();
    for (Session& session : all) {
      if (sessions_.size() == kMaxSessions ||
          (!sessions_.empty() &&
           std::ranges::includes(sessions_.back().Pages(), session.Pages()))) {
        dropped.push_back(session.path);
        continue;
      }
      sessions_.push_back(std::move(session));
    }
    if (!dropped.empty()) {
      task_runner_->PostTask(FROM_HERE,
                             base::BindOnce(&DeleteFiles, std::move(dropped)));
    }
    observers_.Notify(&Observer::OnPreviousSessionsChanged);
  }
  if (needs_read_) {
    needs_read_ = false;
    Update();
  }
}

void PreviousSessions::Restore(const base::FilePath& path) {
  if (!std::ranges::contains(sessions_, path, &Session::path)) {
    return;
  }
  task_runner_->PostTaskAndReplyWithResult(
      FROM_HERE, base::BindOnce(&ReadCommands, path),
      base::BindOnce(&PreviousSessions::OnReadCommands,
                     weak_factory_.GetWeakPtr()));
}

void PreviousSessions::OnReadCommands(Commands commands) {
  Windows windows = ParseWindows(commands);
  if (windows.empty()) {
    return;
  }
  std::vector<const sessions::SessionWindow*> pointers;
  for (const auto& window : windows) {
    pointers.push_back(window.get());
  }
  SessionRestore::RestoreForeignSessionWindows(
      profile_, pointers.begin(), pointers.end(), base::DoNothing());
}

void PreviousSessions::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void PreviousSessions::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

void PreviousSessions::OnHistoryDeletions(
    history::HistoryService* history_service,
    const history::DeletionInfo& deletion_info) {
  // As Chrome deletes its last session
  // (browsing_data::RemoveNavigationEntries).
  if (deletion_info.is_from_expiration()) {
    return;
  }
  ++generation_;
  sessions_.clear();
  task_runner_->PostTask(
      FROM_HERE,
      base::BindOnce(base::IgnoreResult(&base::DeletePathRecursively), dir_));
  observers_.Notify(&Observer::OnPreviousSessionsChanged);
}

void PreviousSessions::HistoryServiceBeingDeleted(
    history::HistoryService* history_service) {
  history_observation_.Reset();
}

}  // namespace fiber
