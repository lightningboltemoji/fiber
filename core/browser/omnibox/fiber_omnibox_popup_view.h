#ifndef FIBER_BROWSER_OMNIBOX_FIBER_OMNIBOX_POPUP_VIEW_H_
#define FIBER_BROWSER_OMNIBOX_FIBER_OMNIBOX_POPUP_VIEW_H_

#include <string_view>

#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "chrome/browser/ui/omnibox/omnibox_edit_model.h"
#include "chrome/browser/ui/omnibox/omnibox_popup_view.h"

@protocol FiberOmnibox;

namespace gfx {
class Image;
}

namespace fiber {

// The omnibox's suggestions, which the command palette lists under its field.
// Sends the palette Chrome's autocomplete results as FiberSuggestions, and
// which of them is selected, as they change.
class FiberOmniboxPopupView : public OmniboxPopupView,
                              public OmniboxEditModel::Observer {
 public:
  // `controller` must outlive this.
  FiberOmniboxPopupView(OmniboxController* controller, id<FiberOmnibox> ui);
  FiberOmniboxPopupView(const FiberOmniboxPopupView&) = delete;
  FiberOmniboxPopupView& operator=(const FiberOmniboxPopupView&) = delete;
  ~FiberOmniboxPopupView() override;

  // OmniboxPopupView:
  bool IsOpen() const override;
  void InvalidateLine(size_t line) override;
  void UpdatePopupAppearance() override;
  void ProvideButtonFocusHint(size_t line) override;
  void OnDragCanceled() override;
  void GetPopupAccessibleNodeData(ui::AXNodeData* node_data) const override;
  bool IsSelectionPopupControlled() const override;

  // OmniboxEditModel::Observer:
  void OnSelectionChanged(OmniboxPopupSelection old_selection,
                          OmniboxPopupSelection new_selection) override;
  void OnMatchIconUpdated(size_t index) override;
  void OnContentsChanged() override;
  void OnCharTyped(base::TimeTicks timestamp) override;

 private:
  // Sends the palette the suggestions, then the selection.
  void UpdateSuggestions();
  void UpdateSelection();
  void OnFaviconFetched(const gfx::Image& favicon);
  void UpdateForFetchedFavicons();

  id<FiberOmnibox> __weak ui_;
  bool is_open_ = false;
  // The favicon cache calls back once for every time a favicon was asked for,
  // and each UpdateSuggestions() asks again for those still missing. Favicons
  // that arrive together send the suggestions once.
  bool is_favicon_update_posted_ = false;

  base::ScopedObservation<OmniboxEditModel, OmniboxEditModel::Observer>
      edit_model_observation_{this};
  base::WeakPtrFactory<FiberOmniboxPopupView> weak_ptr_factory_{this};
};

}  // namespace fiber

#endif  // FIBER_BROWSER_OMNIBOX_FIBER_OMNIBOX_POPUP_VIEW_H_
