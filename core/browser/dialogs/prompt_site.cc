#include "fiber/browser/dialogs/prompt_site.h"

#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/url_identity.h"
#include "components/url_formatter/elide_url.h"
#include "url/gurl.h"

namespace fiber {

std::u16string SiteForPrompt(Profile* profile, const GURL& url) {
  constexpr UrlIdentity::TypeSet kAllowedTypes = {
      UrlIdentity::Type::kDefault, UrlIdentity::Type::kChromeExtension,
      UrlIdentity::Type::kIsolatedWebApp, UrlIdentity::Type::kFile};
  constexpr UrlIdentity::FormatOptions kOptions = {
      .default_options = {
          UrlIdentity::DefaultFormatOptions::kOmitCryptographicScheme}};
  UrlIdentity identity =
      UrlIdentity::CreateFromUrl(profile, url, kAllowedTypes, kOptions);
  if (identity.type != UrlIdentity::Type::kDefault) {
    return identity.name;
  }
  return url_formatter::FormatUrlForSecurityDisplay(
      url, url_formatter::SchemeDisplay::OMIT_HTTP_AND_HTTPS);
}

}  // namespace fiber
