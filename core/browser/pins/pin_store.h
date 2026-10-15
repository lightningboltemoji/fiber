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

// A page the user pinned to come back to, or kept on a shelf. Every window of
// its profile shows it, and opens it in a tab of its own when it's clicked
// (see PinnedTabs).
struct Pin {
  Pin();
  Pin(const Pin&);
  Pin& operator=(const Pin&);
  ~Pin();

  std::string id;
  // The shelf it's kept on, or empty for one of the pins themselves.
  std::string shelf_id;
  // Where its tab opens, and goes back to.
  GURL url;
  std::u16string title;
  // Its page's favicon as last seen, for when no window has it open. Empty
  // until then.
  gfx::Image icon;
  // `icon` as kept in the prefs.
  std::vector<uint8_t> icon_png;
};

// A named list of pages the user keeps, which the tab overlay lists beside
// the window's own tabs. Its pages are the pins with its ID.
struct Shelf {
  std::string id;
  std::u16string name;
};

// A profile's pins and shelves, in the order the user arranged them, kept in
// its prefs. The pins come first, then each shelf's pages in the shelves'
// order, as their tabs are in the tab strip. Incognito and Guest profiles
// have none.
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

  // The pins and every shelf's pages.
  const std::vector<Pin>& pins() const { return pins_; }
  // The pins, or a shelf's pages, in order.
  std::vector<const Pin*> PinsOn(std::string_view shelf_id) const;
  const Pin* Find(std::string_view id) const;
  // Its place in pins().
  std::optional<size_t> IndexOf(std::string_view id) const;
  // Its place among those on its shelf (or not on one).
  std::optional<size_t> PositionOf(std::string_view id) const;

  // Adds `pin` at `position` on its shelf, or last if that's past the end.
  void Add(Pin pin, size_t position);
  void Remove(std::string_view id);
  // Moves the pin to `position` on its shelf, in the new order.
  void Move(std::string_view id, size_t position);
  // Moves the pin to the end of the shelf, or of the pins for an empty
  // `shelf_id`.
  void MoveToShelf(std::string_view id, std::string_view shelf_id);
  // An empty `icon` keeps the one the pin has.
  void Update(std::string_view id,
              const GURL& url,
              const std::u16string& title,
              const gfx::Image& icon);

  const std::vector<Shelf>& shelves() const { return shelves_; }
  const Shelf* FindShelf(std::string_view id) const;
  // Adds an empty shelf after the others and returns its ID.
  std::string AddShelf(const std::u16string& name);
  void RenameShelf(std::string_view id, const std::u16string& name);
  // Removes the shelf and its pages.
  void RemoveShelf(std::string_view id);

  void AddObserver(Observer* observer);
  void RemoveObserver(Observer* observer);

 private:
  Pin* FindMutable(std::string_view id);
  // Where the pins on the shelf start and end in `pins_`.
  std::pair<size_t, size_t> RangeOf(std::string_view shelf_id) const;
  void Load();
  // Saves the pins and tells the observers.
  void Changed();

  const raw_ptr<Profile> profile_;
  std::vector<Pin> pins_;
  std::vector<Shelf> shelves_;
  base::ObserverList<Observer> observers_;
};

}  // namespace fiber

#endif  // FIBER_BROWSER_PINS_PIN_STORE_H_
