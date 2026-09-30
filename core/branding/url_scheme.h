#ifndef FIBER_BRANDING_URL_SCHEME_H_
#define FIBER_BRANDING_URL_SCHEME_H_

namespace fiber {

// The scheme Chrome's own pages show in. url_formatter shows
// chrome://settings as fiber://settings and reads fiber:// back as chrome://,
// which is all Chrome and extensions ever see.
inline constexpr char kFiberUIScheme[] = "fiber";
inline constexpr char16_t kFiberUIScheme16[] = u"fiber";

}  // namespace fiber

#endif  // FIBER_BRANDING_URL_SCHEME_H_
