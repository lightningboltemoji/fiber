#ifndef FIBER_BROWSER_HOOKS_EXTENSION_DIALOGS_H_
#define FIBER_BROWSER_HOOKS_EXTENSION_DIALOGS_H_

#include <memory>

#include "base/memory/scoped_refptr.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/extensions/extension_uninstall_dialog.h"
#include "ui/gfx/native_ui_types.h"

class BrowserWindowInterface;
class Profile;
class SkBitmap;

namespace extensions {
class Extension;
}  // namespace extensions

// Fiber's prompts for adding and removing extensions, over the veiled page, in
// place of Chrome's dialogs, which are cut.
namespace fiber {

// For ExtensionInstallPrompt::GetDefaultShowDialogCallback(): adding an
// extension, and Chrome's other install prompts (re-enabling one that asks for
// more, chrome.permissions.request()…).
ExtensionInstallPrompt::ShowDialogCallback ExtensionInstallDialogCallback();

// For ExtensionInstallUIDesktop::OnInstallSuccess(): tells the user
// `extension` was added, in `browser`'s window.
void OnExtensionInstalled(BrowserWindowInterface* browser,
                          scoped_refptr<const extensions::Extension> extension,
                          const SkBitmap* icon);

// For extensions::ExtensionUninstallDialog::Create().
std::unique_ptr<extensions::ExtensionUninstallDialog>
CreateExtensionUninstallDialog(
    Profile* profile,
    gfx::NativeWindow parent,
    extensions::ExtensionUninstallDialog::Delegate* delegate);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_EXTENSION_DIALOGS_H_
