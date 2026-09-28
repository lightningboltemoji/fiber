// The contract between //fiber/browser, which integrates with Chrome, and
// //fiber/ui, which draws everything the user sees: protocols and immutable
// value types, with no mention of C++ or Chromium.
//
// - Objects in //fiber/browser tell the UI what to show by calling the UI's
//   protocols (FiberWindow…) with value types (FiberPageState…).
// - The UI reports what the user does through actions protocols
//   (FiberWindowActions…) that //fiber/browser implements. When the browser
//   object behind an actions object goes away, its calls do nothing.
// - //fiber/browser creates UI objects with the factories declared here, which
//   //fiber/ui implements (as it does the value types) with
//   @objc @implementation.
// - Everything is main thread only.

#import "FiberContextMenu.h"
#import "FiberDownloadsWait.h"
#import "FiberExtensions.h"
#import "FiberJavaScriptDialog.h"
#import "FiberOmnibox.h"
#import "FiberPageState.h"
#import "FiberPrompt.h"
#import "FiberQuitConfirmation.h"
#import "FiberTabState.h"
#import "FiberWindow.h"
