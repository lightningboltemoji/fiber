#ifndef FIBER_BROWSER_EXTENSIONS_EXTENSION_UNINSTALL_DIALOG_H_
#define FIBER_BROWSER_EXTENSIONS_EXTENSION_UNINSTALL_DIALOG_H_

#include <memory>

#include "chrome/browser/extensions/extension_uninstall_dialog.h"
#include "ui/gfx/native_ui_types.h"

class Profile;

namespace fiber {

// Chrome's confirmation before removing an extension, over the veiled page in
// place of Chrome's dialog. Asked in `parent`, or else the profile's last
// active window; with neither, the answer is no.
std::unique_ptr<extensions::ExtensionUninstallDialog> CreateUninstallDialog(
    Profile* profile,
    gfx::NativeWindow parent,
    extensions::ExtensionUninstallDialog::Delegate* delegate);

}  // namespace fiber

#endif  // FIBER_BROWSER_EXTENSIONS_EXTENSION_UNINSTALL_DIALOG_H_
