#ifndef FIBER_BROWSER_HOOKS_PREVIOUS_SESSION_H_
#define FIBER_BROWSER_HOOKS_PREVIOUS_SESSION_H_

#include <unistd.h>

#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/posix/eintr_wrapper.h"
#include "components/sessions/core/command_storage_manager.h"

// Header-only: components/sessions, a library of its own in the component
// build, can't link against //fiber.
namespace fiber {

// In a profile's Sessions folder: the sessions Fiber keeps after Chrome deletes
// them (sessions/previous_sessions.h).
inline constexpr base::FilePath::CharType kPreviousSessionsDirName[] =
    FILE_PATH_LITERAL("Previous");

// `path` is the file of a session that has ended, which Chrome deletes once
// another ends. A hard link beside it keeps it until Fiber prunes it.
// Called by CommandStorageBackend, on its sequence.
inline void KeepPreviousSession(
    sessions::CommandStorageManager::SessionType type,
    bool encrypted,
    const base::FilePath& path) {
  if (type != sessions::CommandStorageManager::SessionType::kSessionRestore ||
      encrypted) {
    return;
  }
  const base::FilePath dir = path.DirName().Append(kPreviousSessionsDirName);
  if (base::CreateDirectory(dir)) {
    // Fails harmlessly if it's kept already.
    HANDLE_EINTR(link(path.value().c_str(),
                      dir.Append(path.BaseName()).value().c_str()));
  }
}

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_PREVIOUS_SESSION_H_
