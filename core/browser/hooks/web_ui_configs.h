#ifndef FIBER_BROWSER_HOOKS_WEB_UI_CONFIGS_H_
#define FIBER_BROWSER_HOOKS_WEB_UI_CONFIGS_H_

namespace content {
class WebUIConfigMap;
}

namespace fiber {

// Adds Fiber's WebUIs, in place of the Chrome ones Fiber replaces. Called from
// RegisterChromeWebUIConfigs() (see patches/chromium/
// chrome-browser-ui-webui-chrome_web_ui_configs.cc.patch).
void AddWebUIConfigs(content::WebUIConfigMap& map);

}  // namespace fiber

#endif  // FIBER_BROWSER_HOOKS_WEB_UI_CONFIGS_H_
