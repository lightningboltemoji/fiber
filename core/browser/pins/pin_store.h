#ifndef FIBER_BROWSER_PINS_PIN_STORE_H_
#define FIBER_BROWSER_PINS_PIN_STORE_H_

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/observer_list.h"
#include "base/observer_list_types.h"
#include "base/supports_user_data.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"

class Profile;

namespace user_prefs {
class PrefRegistrySyncable;
}

namespace fiber {

// A page the user pinned to come back to. Every window of its profile shows
// it, and opens it in a tab of its own when it's clicked (see PinnedTabs).
struct Pin {
  Pin();
  Pin(const Pin&);
  Pin& operator=(const Pin&);
  ~Pin();

  std::string id;
  // Where its tab opens, and goes back to.
  GURL url;
  std::u16string title;
  // Its page's favicon as last seen, for when no window has it open. Empty
  // until then.
  gfx::Image icon;
  // `icon` as kept in the prefs.
  std::vector<uint8_t> icon_png;
};

// A profile's pins, in the order the user arranged them, kept in its prefs.
// Incognito and Guest profiles have none.
class PinStore : public base::SupportsUserData::Data {
 public:
  class Observer : public base::CheckedObserver {
   public:
    virtual void OnPinsChanged() = 0;
  };

  // Nullptr for a profile without pins.
  static PinStore* FromProfile(Profile* profile);
  static void RegisterProfilePrefs(user_prefs::PrefRegistrySyncable* registry);

  explicit PinStore(Profile* profile);
  PinStore(const PinStore&) = delete;
  PinStore& operator=(const PinStore&) = delete;
  ~PinStore() override;

  const std::vector<Pin>& pins() const { return pins_; }
  const Pin* Find(std::string_view id) const;
  std::optional<size_t> IndexOf(std::string_view id) const;

  // Adds `pin` at `index`, or last if that's past the end.
  void Add(Pin pin, size_t index);
  void Remove(std::string_view id);
  // Moves the pin to `index` in the new order.
  void Move(std::string_view id, size_t index);
  // An empty `icon` keeps the one the pin has.
  void Update(std::string_view id,
              const GURL& url,
              const std::u16string& title,
              const gfx::Image& icon);

  void AddObserver(Observer* observer);
  void RemoveObserver(Observer* observer);

 private:
  Pin* FindMutable(std::string_view id);
  void Load();
  // Saves the pins and tells the observers.
  void Changed();

  const raw_ptr<Profile> profile_;
  std::vector<Pin> pins_;
  base::ObserverList<Observer> observers_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_PINS_PIN_STORE_H_
