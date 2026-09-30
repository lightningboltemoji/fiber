#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#import "FiberBridge/FiberPrompt.h"
#include "base/auto_reset.h"
#include "base/callback_list.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/notimplemented.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "content/public/browser/web_contents.h"
#include "fiber/browser/dialogs/prompt.h"
#include "fiber/browser/dialogs/tab_prompt.h"
#include "fiber/browser/hooks/dialog_models.h"
#include "fiber/browser/window/fiber_browser_window.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/models/dialog_model.h"
#include "ui/base/models/image_model.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/events/base_event_utils.h"
#include "ui/events/event.h"
#include "ui/events/event_constants.h"
#include "ui/events/types/event_type.h"
#include "ui/gfx/geometry/point.h"
#include "ui/gfx/image/image.h"
#include "ui/strings/grit/ui_strings.h"

namespace fiber {

namespace {

using ui::mojom::DialogButton;

enum ButtonID {
  kOk,
  kCancel,
  kExtra,
};

// `label`'s text, replacements and all. A link reads as plain text, and a
// label that's only links reads as nothing, since they can't be followed.
std::u16string GetText(const ui::DialogModelLabel& label) {
  const std::vector<ui::DialogModelLabel::TextReplacement>& replacements =
      label.replacements();
  if (replacements.empty()) {
    return label.GetString();
  }
  std::vector<std::u16string> texts;
  bool only_links = true;
  for (const auto& replacement : replacements) {
    texts.push_back(replacement.text());
    only_links = only_links && replacement.callback().has_value();
  }
  if (only_links) {
    const std::u16string rest = l10n_util::GetStringFUTF16(
        label.message_id(), std::vector<std::u16string>(texts.size()), nullptr);
    if (base::TrimWhitespace(rest, base::TRIM_ALL).empty()) {
      return std::u16string();
    }
  }
  return l10n_util::GetStringFUTF16(label.message_id(), texts, nullptr);
}

// Named by its label, or, without one, what a screen reader calls it.
FiberPromptField* MakeField(const std::u16string& label,
                            const std::u16string& accessible_name,
                            const std::u16string& text,
                            bool secure) {
  return [[FiberPromptField alloc]
      initWithPlaceholder:base::SysUTF16ToNSString(
                              label.empty() ? accessible_name : label)
                     text:base::SysUTF16ToNSString(text)
                   secure:secure];
}

bool IsShown(const ui::DialogModel::Button* button) {
  return button && button->is_visible() && button->is_enabled();
}

FiberPromptButton* MakeButton(const ui::DialogModel::Button& button,
                              ButtonID button_id,
                              int default_title_id,
                              FiberPromptButtonRole role) {
  return [[FiberPromptButton alloc]
      initWithButtonID:button_id
                 title:base::SysUTF16ToNSString(
                           button.label().empty()
                               ? l10n_util::GetStringUTF16(default_title_id)
                               : button.label())
                  role:role];
}

// Shows a ui::DialogModel as a prompt. Owns itself and the model until the
// dialog ends: answered, dismissed, or closed by the model's owner.
class DialogModelPrompt final : public ui::DialogModelHost,
                                public ui::DialogModelFieldHost {
 public:
  // Over `web_contents`'s page if it's set, else over Fiber window `window`.
  DialogModelPrompt(std::unique_ptr<ui::DialogModel> model,
                    content::WebContents* web_contents,
                    gfx::NativeWindow window)
      : model_(std::move(model)),
        for_tab_(web_contents != nullptr),
        web_contents_(web_contents ? web_contents->GetWeakPtr()
                                   : base::WeakPtr<content::WebContents>()),
        window_(window) {
    model_->set_host(DialogModelHost::GetPassKey(), this);
    if (!for_tab_) {
      // It ends while the window's features are still there for its
      // callbacks, as a views sheet closes with its window.
      browser_did_close_ = FiberBrowserWindow::FromNativeWindow(window_)
                               ->browser()
                               ->RegisterBrowserDidClose(base::BindRepeating(
                                   &DialogModelPrompt::OnBrowserDidClose,
                                   base::Unretained(this)));
    }
  }

  DialogModelPrompt(const DialogModelPrompt&) = delete;
  DialogModelPrompt& operator=(const DialogModelPrompt&) = delete;

  void Present() {
    FiberPromptContent* content = MakeContent();
    if (!content) {
      NOTIMPLEMENTED() << "Can't show DialogModel "
                       << model_->internal_name(DialogModelHost::GetPassKey());
      // Soon: the model's owner may not expect an answer while it shows it.
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE,
          base::BindOnce(&DialogModelPrompt::OnEnded,
                         weak_factory_.GetWeakPtr(), std::optional<int>()));
      return;
    }
    auto on_ended =
        base::BindOnce(&DialogModelPrompt::OnEnded, base::Unretained(this));
    if (for_tab_) {
      tab_prompt_ =
          TabPrompt::Show(web_contents_.get(), content, std::move(on_ended));
    } else {
      window_prompt_ = Prompt::Show(window_, content, std::move(on_ended));
    }
  }

 private:
  ~DialogModelPrompt() = default;

  // ui::DialogModelHost:
  void Close() override {
    if (running_action_) {
      closed_ = true;
      return;
    }
    TakeDown();
    Destroy();
  }

  void OnDialogButtonChanged() override {
    // Again, with the buttons as they are now; what's been typed is lost.
    if (!prompt()) {
      return;
    }
    TakeDown();
    Present();
  }

  // The model as a prompt, or nil if it has what a prompt can't show. Notes
  // which of the model's fields the prompt fills in.
  FiberPromptContent* MakeContent() {
    const auto pass_key = DialogModelHost::GetPassKey();
    text_fields_.clear();
    checkbox_ = nullptr;

    std::vector<std::u16string> paragraphs;
    if (!model_->subtitle(pass_key).empty()) {
      paragraphs.push_back(model_->subtitle(pass_key));
    }
    NSMutableArray<FiberPromptListItem*>* list_items = [NSMutableArray array];
    NSMutableArray<FiberPromptField*>* fields = [NSMutableArray array];
    NSString* checkbox_title = @"";
    for (const auto& field : model_->fields(pass_key)) {
      if (!field->is_visible()) {
        continue;
      }
      switch (field->type()) {
        case ui::DialogModelField::kParagraph: {
          ui::DialogModelParagraph* paragraph = field->AsParagraph();
          std::u16string text = GetText(paragraph->label());
          if (!paragraph->header().empty()) {
            text = text.empty() ? paragraph->header()
                                : paragraph->header() + u"\n" + text;
          }
          if (!text.empty()) {
            paragraphs.push_back(std::move(text));
          }
          break;
        }
        case ui::DialogModelField::kCheckbox: {
          // A prompt's one checkbox starts unchecked.
          ui::DialogModelCheckbox* checkbox = field->AsCheckbox();
          if (checkbox_ || checkbox->is_checked()) {
            return nil;
          }
          checkbox_ = checkbox;
          checkbox_title = base::SysUTF16ToNSString(GetText(checkbox->label()));
          break;
        }
        case ui::DialogModelField::kTextfield: {
          ui::DialogModelTextfield* textfield = field->AsTextfield();
          [fields addObject:MakeField(textfield->label(),
                                      textfield->accessible_name(),
                                      textfield->text(), /*secure=*/false)];
          text_fields_.push_back(field.get());
          break;
        }
        case ui::DialogModelField::kPasswordField: {
          ui::DialogModelPasswordField* password = field->AsPasswordField();
          [fields addObject:MakeField(password->label(),
                                      password->accessible_name(),
                                      password->text(), /*secure=*/true)];
          text_fields_.push_back(field.get());
          break;
        }
        case ui::DialogModelField::kMenuItem: {
          // Items that can't be chosen are a list: the extensions a dialog is
          // about, say.
          ui::DialogModelMenuItem* item = field->AsMenuItem();
          if (item->is_enabled()) {
            return nil;
          }
          [list_items
              addObject:[[FiberPromptListItem alloc]
                            initWithText:base::SysUTF16ToNSString(item->label())
                                  detail:@""]];
          break;
        }
        case ui::DialogModelField::kSeparator:
          break;
        default:
          return nil;
      }
    }
    if (const std::optional<ui::DialogModelLabel>& footnote =
            model_->footnote_label()) {
      std::u16string text = GetText(*footnote);
      if (!text.empty()) {
        paragraphs.push_back(std::move(text));
      }
    }

    ui::DialogModel::Button* ok = model_->ok_button(pass_key);
    ui::DialogModel::Button* cancel = model_->cancel_button(pass_key);
    ui::DialogModel::Button* extra = model_->extra_button(pass_key);
    // As views has it, OK is the default, else Cancel.
    const DialogButton default_button =
        model_->override_default_button(pass_key).value_or(
            ok       ? DialogButton::kOk
            : cancel ? DialogButton::kCancel
                     : DialogButton::kNone);
    // Chrome's input protection is a Confirm button's click and wait. Only
    // one button is tinted, so Cancel takes Return only if OK is plain.
    const FiberPromptButtonRole ok_role =
        model_->enable_input_protection(pass_key) ? FiberPromptButtonRoleConfirm
        : default_button == DialogButton::kOk     ? FiberPromptButtonRoleDefault
                                                  : FiberPromptButtonRoleOther;
    const FiberPromptButtonRole cancel_role =
        default_button == DialogButton::kCancel &&
                (!IsShown(ok) || ok_role == FiberPromptButtonRoleOther)
            ? FiberPromptButtonRoleDefault
            : FiberPromptButtonRoleCancel;
    NSMutableArray<FiberPromptButton*>* buttons = [NSMutableArray array];
    if (IsShown(extra)) {
      [buttons addObject:MakeButton(*extra, kExtra, IDS_APP_OK,
                                    FiberPromptButtonRoleOther)];
    }
    if (IsShown(cancel)) {
      [buttons
          addObject:MakeButton(*cancel, kCancel, IDS_APP_CANCEL, cancel_role)];
    }
    if (IsShown(ok)) {
      [buttons addObject:MakeButton(*ok, kOk, IDS_APP_OK, ok_role)];
    }

    // Only images: Chrome's vector icons are drawn for its own dialogs.
    const ui::ImageModel& icon = model_->icon(pass_key);
    NSImage* ns_icon = icon.IsImage() && !icon.GetImage().IsEmpty()
                           ? icon.GetImage().ToNSImage()
                           : nil;

    return [[FiberPromptContent alloc]
         initWithIcon:ns_icon
              eyebrow:@""
                title:base::SysUTF16ToNSString(model_->title(pass_key))
              message:base::SysUTF16ToNSString(
                          base::JoinString(paragraphs, u"\n\n"))
          listHeading:@""
            listItems:list_items
               fields:fields
        checkboxTitle:checkbox_title
              buttons:buttons];
  }

  const Prompt* prompt() const {
    return tab_prompt_ ? &tab_prompt_->prompt() : window_prompt_.get();
  }

  // Takes the prompt down, without an answer.
  void TakeDown() {
    tab_prompt_.reset();
    window_prompt_.reset();
  }

  void OnEnded(std::optional<int> button_id) {
    const auto pass_key = DialogModelHost::GetPassKey();
    std::vector<std::u16string> values;
    bool checked = false;
    if (button_id && prompt()) {
      values = prompt()->GetFieldValues();
      checked = prompt()->IsCheckboxChecked();
    }
    TakeDown();

    bool keep_open = false;
    {
      base::AutoReset<bool> running_action(&running_action_, true);
      // What the user entered, for the model's callbacks to read.
      if (button_id) {
        for (size_t i = 0; i < text_fields_.size() && i < values.size(); ++i) {
          ui::DialogModelField* field = text_fields_[i];
          if (field->type() == ui::DialogModelField::kTextfield) {
            field->AsTextfield()->OnTextChanged(
                DialogModelFieldHost::GetPassKey(), values[i]);
          } else {
            field->AsPasswordField()->OnTextChanged(
                DialogModelFieldHost::GetPassKey(), values[i]);
          }
        }
        if (checkbox_) {
          checkbox_->OnChecked(DialogModelFieldHost::GetPassKey(), checked);
        }
      }
      if (button_id == kOk) {
        keep_open = !model_->OnDialogAcceptAction(pass_key);
      } else if (button_id == kCancel) {
        keep_open = !model_->OnDialogCancelAction(pass_key);
      } else if (button_id == kExtra) {
        // Unlike in views, the dialog ends: its owner can't close it through
        // the widget views would have returned.
        model_->extra_button(pass_key)->OnPressed(
            pass_key,
            ui::MouseEvent(ui::EventType::kMouseReleased, gfx::Point(),
                           gfx::Point(), ui::EventTimeForNow(),
                           ui::EF_LEFT_MOUSE_BUTTON, ui::EF_LEFT_MOUSE_BUTTON));
      } else {
        model_->OnDialogCloseAction(pass_key);
      }
    }
    if (keep_open && !closed_ && (!for_tab_ || web_contents_)) {
      Present();
      return;
    }
    Destroy();
  }

  void OnBrowserDidClose(BrowserWindowInterface* browser) {
    if (!window_prompt_) {
      return;
    }
    TakeDown();
    OnEnded(std::nullopt);
  }

  // Tells the model the dialog's gone, and deletes this.
  void Destroy() {
    running_action_ = true;
    model_->OnDialogDestroying(DialogModelHost::GetPassKey());
    delete this;
  }

  std::unique_ptr<ui::DialogModel> model_;
  const bool for_tab_;
  const base::WeakPtr<content::WebContents> web_contents_;
  const gfx::NativeWindow window_;
  base::CallbackListSubscription browser_did_close_;
  std::unique_ptr<TabPrompt> tab_prompt_;
  std::unique_ptr<Prompt> window_prompt_;
  // The model's text and password fields, in the prompt's order, and its
  // checkbox.
  std::vector<raw_ptr<ui::DialogModelField>> text_fields_;
  raw_ptr<ui::DialogModelCheckbox> checkbox_ = nullptr;
  // While one of the model's callbacks runs, Close() waits for it to return.
  bool running_action_ = false;
  bool closed_ = false;
  base::WeakPtrFactory<DialogModelPrompt> weak_factory_{this};
};

}  // namespace

void ShowTabModalDialog(std::unique_ptr<ui::DialogModel> dialog_model,
                        content::WebContents* web_contents) {
  (new DialogModelPrompt(std::move(dialog_model), web_contents,
                         gfx::NativeWindow()))
      ->Present();
}

void ShowWindowModalDialog(std::unique_ptr<ui::DialogModel> dialog_model,
                           gfx::NativeWindow window) {
  (new DialogModelPrompt(std::move(dialog_model), nullptr, window))->Present();
}

}  // namespace fiber
