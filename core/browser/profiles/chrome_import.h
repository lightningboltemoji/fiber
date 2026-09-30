#ifndef FIBER_BROWSER_PROFILES_CHROME_IMPORT_H_
#define FIBER_BROWSER_PROFILES_CHROME_IMPORT_H_

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback.h"

namespace fiber {

// A profile of Google Chrome's on this Mac.
struct ChromeProfile {
  ChromeProfile();
  ChromeProfile(const ChromeProfile&);
  ChromeProfile& operator=(const ChromeProfile&);
  ~ChromeProfile();

  base::FilePath path;
  std::u16string name;
  // Its Google account's email, or empty.
  std::u16string user_name;
  // As Chrome numbers its default avatars.
  size_t avatar_index = 0;
  // Its Google account's picture, a PNG, or empty.
  std::vector<uint8_t> picture;
};

// Chrome's profiles, by name, from its Local State. Blocks on the disk.
std::vector<ChromeProfile> FindChromeProfiles();

// Makes a Fiber profile of `source`'s bookmarks and history, and its passwords
// and cookies if the keychain gives up Chrome's key, then opens a window for
// it. `progress` gets each step; `done`, an error or, once it's open, nothing.
void ImportChromeProfile(
    const ChromeProfile& source,
    base::RepeatingCallback<void(const std::u16string& step)> progress,
    base::OnceCallback<void(std::optional<std::u16string> error)> done);

}  // namespace fiber

#endif  // FIBER_BROWSER_PROFILES_CHROME_IMPORT_H_
