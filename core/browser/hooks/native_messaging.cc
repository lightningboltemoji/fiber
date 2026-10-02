#include "fiber/browser/hooks/native_messaging.h"

#include <vector>

#include "base/apple/foundation_util.h"
#include "base/files/file_util.h"
#include "base/path_service.h"
#include "chrome/common/chrome_paths.h"

namespace fiber {

base::FilePath FindNativeMessagingManifest(const std::string& host_name,
                                           bool allow_user_level_hosts) {
  // As in Chrome, a user's hosts come before the system's.
  std::vector<base::FilePath> dirs;
  base::FilePath dir;
  if (allow_user_level_hosts) {
    if (base::PathService::Get(chrome::DIR_USER_NATIVE_MESSAGING, &dir)) {
      dirs.push_back(dir);
    }
    dirs.push_back(base::apple::GetUserLibraryPath().Append(
        "Application Support/Google/Chrome/NativeMessagingHosts"));
  }
  if (base::PathService::Get(chrome::DIR_NATIVE_MESSAGING, &dir)) {
    dirs.push_back(dir);
  }
  dirs.emplace_back("/Library/Google/Chrome/NativeMessagingHosts");

  for (const base::FilePath& host_dir : dirs) {
    base::FilePath path = host_dir.Append(host_name + ".json");
    if (base::PathExists(path)) {
      return path;
    }
  }
  return base::FilePath();
}

}  // namespace fiber
