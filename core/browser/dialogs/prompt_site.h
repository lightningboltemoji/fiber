#ifndef FIBER_BROWSER_DIALOGS_PROMPT_SITE_H_
#define FIBER_BROWSER_DIALOGS_PROMPT_SITE_H_

#include <string>

class GURL;
class Profile;

namespace fiber {

// A site as Fiber's prompts name it: its host, and any port, without http or
// https, or an extension, an isolated web app or a file as Chrome names it.
std::u16string SiteForPrompt(Profile* profile, const GURL& url);

}  // namespace fiber

#endif  // FIBER_BROWSER_DIALOGS_PROMPT_SITE_H_
