#include "fiber/browser/hooks/web_ui_configs.h"

#include <memory>

#include "content/public/browser/webui_config_map.h"
#include "fiber/browser/new_tab/new_tab_page_ui.h"

namespace fiber {

void AddWebUIConfigs(content::WebUIConfigMap& map) {
  map.AddWebUIConfig(std::make_unique<NewTabPageUIConfig>());
}

}  // namespace fiber
