#ifndef FIBER_BROWSER_SESSIONS_PREVIOUS_SESSIONS_H_
#define FIBER_BROWSER_SESSIONS_PREVIOUS_SESSIONS_H_

#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/observer_list.h"
#include "base/observer_list_types.h"
#include "base/scoped_observation.h"
#include "base/supports_user_data.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/history_service_observer.h"
#include "url/gurl.h"

class Profile;

namespace sessions {
class SessionCommand;
}

namespace fiber {

// The windows open as each of a profile's recent sessions ended: Fiber quit or
// crashed, or the profile's last window closed. Chrome deletes a session once
// the next one ends, so CommandStorageBackend keeps a link to each
// (hooks/previous_session.h), which this lists, prunes and restores. Clearing
// history clears them, as it does Chrome's last session.
class PreviousSessions : public base::SupportsUserData::Data,
                         public history::HistoryServiceObserver {
 public:
  struct Tab {
    std::u16string title;
    GURL url;
  };

  struct Session {
    Session();
    Session(const Session&);
    Session(Session&&);
    Session& operator=(const Session&);
    Session& operator=(Session&&);
    ~Session();

    // The pages it would bring back: its tabs' but New Tab pages'.
    std::set<GURL> Pages() const;
    size_t TabCount() const;

    base::FilePath path;
    // When it was last written, as it ended.
    base::Time ended;
    // Each window's tabs, in order.
    std::vector<std::vector<Tab>> windows;
  };

  class Observer : public base::CheckedObserver {
   public:
    virtual void OnPreviousSessionsChanged() = 0;
  };

  static constexpr size_t kMaxSessions = 20;

  // Nullptr for Incognito and Guest profiles, which keep no sessions.
  static PreviousSessions* FromProfile(Profile* profile);

  explicit PreviousSessions(Profile* profile);
  PreviousSessions(const PreviousSessions&) = delete;
  PreviousSessions& operator=(const PreviousSessions&) = delete;
  ~PreviousSessions() override;

  // Newest first, as last read: empty until Update() first finishes.
  const std::vector<Session>& sessions() const { return sessions_; }
  // Those that would bring something back: not all their pages are open in
  // the profile's windows now.
  std::vector<const Session*> Offered() const;

  // Reads the sessions kept since, then prunes them to kMaxSessions, dropping
  // any a later one has all the pages of. Observers hear when it's done. The
  // first is soon after startup.
  void Update();

  // Opens the windows of the session at `path` again, as they were.
  void Restore(const base::FilePath& path);

  void AddObserver(Observer* observer);
  void RemoveObserver(Observer* observer);

  // history::HistoryServiceObserver:
  void OnHistoryDeletions(history::HistoryService* history_service,
                          const history::DeletionInfo& deletion_info) override;
  void HistoryServiceBeingDeleted(
      history::HistoryService* history_service) override;

 private:
  struct ReadFile;

  // On `task_runner_`: the files in `dir`, with the commands of those not in
  // `known`.
  static std::vector<ReadFile> ReadFiles(const base::FilePath& dir,
                                         const std::set<base::FilePath>& known);
  // Nullopt if it has nothing to bring back.
  static std::optional<Session> ParseSession(const ReadFile& file);

  void OnRead(int generation, std::vector<ReadFile> files);
  void OnReadCommands(
      std::vector<std::unique_ptr<sessions::SessionCommand>> commands);

  const raw_ptr<Profile> profile_;
  const base::FilePath dir_;
  const scoped_refptr<base::SequencedTaskRunner> task_runner_;
  std::vector<Session> sessions_;
  // Bumped as history is cleared, so a read from before is ignored.
  int generation_ = 0;
  bool is_reading_ = false;
  bool needs_read_ = false;
  base::ObserverList<Observer> observers_;
  base::ScopedObservation<history::HistoryService,
                          history::HistoryServiceObserver>
      history_observation_{this};
  base::WeakPtrFactory<PreviousSessions> weak_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_SESSIONS_PREVIOUS_SESSIONS_H_
