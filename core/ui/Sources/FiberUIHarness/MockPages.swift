import Foundation

/// What the harness's made-up sites say: each page's title and text, as
/// Chrome would read them (a line per block), for the command palette to
/// search.
enum MockPages {
  struct Page {
    let title: String
    let text: String
  }

  static func page(for url: String) -> Page? {
    guard let host = URL(string: url)?.host() else {
      return nil
    }
    return pages[host]
  }

  private static let pages: [String: Page] = [
    "fiber.example": Page(
      title: "Fiber — a Chromium-based browser for macOS",
      text: """
        Fiber
        A Chromium-based browser for macOS, with its own native interface.
        Every window is a Chrome browser underneath, so extensions, session restore and links from other apps work as they do in Chrome.
        Download for macOS 26
        Release notes
        Fiber 0.1 brings the tab picker, the command palette, and hardware video decoding through VideoToolbox.
        """),
    "news.example": Page(
      title: "Front Page — News",
      text: """
        Top stories
        City council approves the new waterfront transit line after a two-year review
        The line will connect the ferry terminal with the university campus, with construction starting next spring.
        Markets close higher as chipmakers rally on strong earnings
        Opinion: why the four-day work week keeps coming back
        Weather: a cold front brings heavy rain to the coast through Thursday
        Sports: the home team clinches a playoff spot with a late goal
        """),
    "mail.example": Page(
      title: "Inbox (3) — Mail",
      text: """
        Inbox
        Priya Raman — Quarterly planning notes: attached are the notes from Tuesday's planning session, including the hiring plan.
        Build Bot — Nightly build failed on macOS arm64: linker error in chrome/browser
        Landlord — Lease renewal: please sign and return the renewal before the end of the month.
        Airline — Your boarding pass for flight 212 to Lisbon
        """),
    "docs.example": Page(
      title: "Tab picker — Design spec",
      text: """
        Tab picker
        The tab picker lives on the window's right edge. Moving the pointer to the edge reveals a glass panel listing the window's tabs.
        Scrolling
        The list scrolls with two fingers and rubber-bands past either end. A flick coasts and stops at the last tab.
        Selecting
        Clicking a tab selects it and closes the panel. The highlight glides to the hovered tab with a spring animation.
        Open questions
        Should pinned tabs get their own section? How does the picker behave with hundreds of tabs?
        """),
    "video.example": Page(
      title: "Designing with Liquid Glass — Video",
      text: """
        Designing with Liquid Glass
        48,210 views
        In this session we look at how glass materials refract the content behind them, and how to layer controls so they stay legible.
        Chapters: introduction, refraction and blur, rims and edges, animating glass shapes, accessibility and reduced transparency.
        Comments
        Great talk. The part about concentric corner radii finally made it click for me.
        """),
    "maps.example": Page(
      title: "San Francisco — Maps",
      text: """
        San Francisco, California
        Directions
        Nearby: coffee, restaurants, parking, gas stations
        Ferry Building Marketplace — open until 7 PM
        Golden Gate Park — 4.8 stars — 1,017 acres of gardens, museums and meadows
        """),
    "shop.example": Page(
      title: "Your Cart — Shop",
      text: """
        Shopping cart
        Mechanical keyboard, brown switches — $129.00 — in stock
        USB-C cable, braided, 2 m — $19.00
        Laptop stand, aluminum — $49.00 — ships in 3 days
        Subtotal (3 items): $197.00
        Proceed to checkout
        """),
    "wiki.example": Page(
      title: "Liquid glass — Wiki",
      text: """
        Liquid glass
        From the free encyclopedia
        Liquid glass is a visual material in user interfaces that bends and refracts light from the content beneath it, as a physical lens would.
        History
        Translucent materials appeared in desktop interfaces in the early 2000s. Later systems added real-time blur, vibrancy, and eventually refraction.
        Design principles
        Glass is reserved for controls and navigation that float above content. Content itself is never made of glass.
        See also: skeuomorphism, flat design, neumorphism
        """),
    "code.example": Page(
      title: "Pull requests · fiber/fiber — Code",
      text: """
        Pull requests
        Add command palette with tab search #412 — opened 2 hours ago by tanner — review required
        Offload media decoding to VideoToolbox #398 — merged
        Fix rubber banding in the tab sidebar when the list is short #405 — changes requested
        Borrow checker errors in the rust helper crate #377 — closed
        Rebase onto Chromium 155 stable #410 — draft
        """),
    "music.example": Page(
      title: "Focus — Playlist — Music",
      text: """
        Focus
        Playlist · 42 songs · 2 hr 51 min
        Instrumental music for deep work: ambient, piano, and minimal electronic.
        1. Weightless  2. Near Light  3. Awake  4. Experience  5. Nuvole Bianche
        """),
    "weather.example": Page(
      title: "Today's Forecast — Weather",
      text: """
        Today
        Partly cloudy, high of 68°F, low of 54°F. Wind from the west at 12 mph.
        Tonight: fog rolls in after midnight.
        10-day forecast: rain returns Thursday with a cold front, clearing by the weekend.
        Air quality: good. UV index: moderate.
        """),
    "calendar.example": Page(
      title: "Week of September 28 — Calendar",
      text: """
        Monday: 9:30 standup, 11:00 design review of the command palette, 2:00 one on one with Priya
        Tuesday: quarterly planning, all afternoon
        Wednesday: dentist at 8:00, focus time
        Thursday: Chromium rebase sync, team lunch
        Friday: demo day
        """),
    "photos.example": Page(
      title: "Summer — Album — Photos",
      text: """
        Summer
        214 photos · shared with family
        Lake house, July. Sunset over the dock. Kayaking at dawn. Fourth of July fireworks.
        Road trip: Big Sur, Monterey, the Bixby Bridge in the fog.
        """),
    "recipes.example": Page(
      title: "Weeknight Shoyu Ramen — Recipes",
      text: """
        Weeknight shoyu ramen
        Prep 20 minutes, cook 40 minutes, serves 4
        Ingredients
        Chicken stock, soy sauce, mirin, kombu, dried shiitake, fresh ramen noodles, soft-boiled eggs, scallions, nori, chashu pork.
        Method
        Simmer the stock with kombu and shiitake for 20 minutes. Season the tare with soy sauce and mirin.
        Marinate the soft-boiled eggs in soy sauce overnight for jammy ajitama.
        Cook the noodles for 90 seconds, then assemble in warm bowls.
        """),
    "forum.example": Page(
      title: "Maintaining a Chromium fork — Forum",
      text: """
        Maintaining a Chromium fork
        How do you keep a Chromium fork rebased on every stable release without drowning in merge conflicts?
        Reply: keep patches small, one patch per file, and put the logic in your own directory. Hooks, not rewrites.
        Reply: we rebase onto each stable branch and run a size report to make sure the code we cut stays out of the binary.
        Reply: the hardest part for us was the views code; anything that assumes a BrowserView breaks.
        """),
    "bank.example": Page(
      title: "Accounts — Bank",
      text: """
        Accounts overview
        Checking ····4821 — available balance $3,204.18
        Savings ····0937 — $12,850.00 — 4.10% APY
        Recent activity: rent payment, grocery store, payroll deposit, coffee
        Transfer money · Pay bills · Deposit a check
        """),
    "travel.example": Page(
      title: "Flights to Lisbon — Travel",
      text: """
        San Francisco to Lisbon
        Depart October 14, return October 24, 1 adult, economy
        Best: 1 stop in Newark, 14 hr 5 min — $812
        Cheapest: 2 stops, 22 hr 40 min — $640
        Nonstop flights are available on Thursdays and Sundays.
        Hotels in Alfama and Baixa from $140 a night.
        """),
    "design.example": Page(
      title: "Toolbar — Design Files",
      text: """
        Toolbar
        Last edited by Mia 3 hours ago
        Frames: toolbar default, toolbar hover, address field focused, extensions menu open
        Comment from Mia: can the back and forward buttons share one capsule, like Safari's?
        Comment from Jordan: the rim on the glass looks too thick at small sizes.
        """),
    "chat.example": Page(
      title: "#general — Chat",
      text: """
        general
        Priya: the nightly build is green again 🎉
        Jordan: anyone have a good ramen place near the office?
        Mia: posted new toolbar mocks in the design file, feedback welcome
        Tanner: command palette lands this week, try ⌘P
        """),
    "papers.example": Page(
      title: "Okapi at TREC-3 — Papers",
      text: """
        Okapi at TREC-3
        Abstract
        We describe the BM25 weighting function, which combines term frequency saturation with document length normalization, and evaluate it on the TREC-3 ad hoc task.
        Probabilistic retrieval models rank documents by the estimated probability that they are relevant to the query.
        Results show large gains over earlier Okapi weighting schemes.
        """),
    "store.example": Page(
      title: "Fiber — App Store",
      text: """
        Fiber
        A fast, native browser built on Chromium.
        Ratings and reviews: 4.7 out of 5
        What's new: the command palette searches your open tabs, their pages, and commands.
        Requires macOS 26 or later.
        """),
  ]
}
