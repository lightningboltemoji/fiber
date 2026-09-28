#include "fiber/browser/hooks/extension_dialogs.h"

#include <utility>

#include "base/functional/bind.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/common/extension.h"
#include "fiber/browser/extensions/extension_install_dialog.h"
#include "fiber/browser/extensions/extension_uninstall_dialog.h"

namespace fiber {

ExtensionInstallPrompt::ShowDialogCallback ExtensionInstallDialogCallback() {
  return base::BindRepeating(&ShowExtensionInstallDialog);
}

void OnExtensionInstalled(BrowserWindowInterface* browser,
                          scoped_refptr<const extensions::Extension> extension,
                          const SkBitmap* icon) {
  ShowExtensionInstalled(browser, std::move(extension), icon);
}

std::unique_ptr<extensions::ExtensionUninstallDialog>
CreateExtensionUninstallDialog(
    Profile* profile,
    gfx::NativeWindow parent,
    extensions::ExtensionUninstallDialog::Delegate* delegate) {
  return CreateUninstallDialog(profile, parent, delegate);
}

}  // namespace fiber
