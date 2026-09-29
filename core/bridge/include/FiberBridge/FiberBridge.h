// The contract between //fiber/browser and //fiber/ui, with no C++ or Chromium
// (see "Across the bridge" in .agents/IMPLEMENTATION.md). An actions object's
// calls do nothing once the browser object behind it is gone.

#import "FiberContextMenu.h"
#import "FiberDownloadsWait.h"
#import "FiberExtensions.h"
#import "FiberJavaScriptDialog.h"
#import "FiberOmnibox.h"
#import "FiberPageState.h"
#import "FiberPrompt.h"
#import "FiberQuitConfirmation.h"
#import "FiberTabIndex.h"
#import "FiberTabState.h"
#import "FiberWindow.h"
