#ifndef FIBER_BROWSER_EXTENSIONS_EXTENSION_INSTALL_DIALOG_H_
#define FIBER_BROWSER_EXTENSIONS_EXTENSION_INSTALL_DIALOG_H_

#include <memory>

#include "base/memory/scoped_refptr.h"
#include "chrome/browser/extensions/extension_install_prompt.h"

class BrowserWindowInterface;
class ExtensionInstallPromptShowParams;
class SkBitmap;

namespace extensions {
class Extension;
class InstallPromptData;
}  // namespace extensions

namespace fiber {

// Chrome's extension install and permission prompts, over the veiled page in
// place of Chrome's dialog. Asked in the window it's for, or else the
// profile's last active one; with none, the answer is no.
void ShowExtensionInstallDialog(
    std::unique_ptr<ExtensionInstallPromptShowParams> show_params,
    ExtensionInstallPrompt::DoneCallback done_callback,
    std::unique_ptr<extensions::InstallPromptData> prompt);

// Tells the user `extension` was added, in `browser`'s window, in place of
// Chrome's dialog, and offers to pin it to the toolbar.
void ShowExtensionInstalled(BrowserWindowInterface* browser,
                            scoped_refptr<const extensions::Extension> extension,
                            const SkBitmap* icon);

}  // namespace fiber

#endif  // FIBER_BROWSER_EXTENSIONS_EXTENSION_INSTALL_DIALOG_H_
