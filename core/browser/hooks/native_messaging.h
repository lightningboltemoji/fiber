#ifndef FIBER_BROWSER_HOOKS_NATIVE_MESSAGING_H_
#define FIBER_BROWSER_HOOKS_NATIVE_MESSAGING_H_

#include <string>

#include "base/files/file_path.h"

namespace fiber {

// The manifest of native messaging host `host_name`, or an empty path, from
// Chrome's folders as well as Fiber's: apps only register hosts with browsers
// they know. Called by LaunchContext::FindManifest() in place of its search.
base::FilePath FindNativeMessagingManifest(const std::string& host_name,
                                           bool allow_user_level_hosts);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_NATIVE_MESSAGING_H_
