# The README's video: the omnibar from history, a site asking where you are,
# tabs and pins on ⌘S, and the command palette finding a page by what's on it.
Window 1600x1000
Seed 7
Visit https://wayfarer.travel/lisbon/ https://margin.so/ https://hum.fm/
Pin https://lettera.app/ "Inbox – Lettera"
Pin https://daybook.app/ "Daybook"
Pin https://hum.fm/ "Hum"
Pin https://margin.so/ "Lisbon trip – Margin"
Open https://meridian.news/night-trains/ https://caldera.dev/docs/getting-started/ https://saltwater.kitchen/pasteis-de-nata/ https://lumen.camera/
Pointer @-80,640

Key cmd+t
Sleep 1.2s
Record

# The omnibar, on a new tab, finds what you've been reading.
Sleep 1.6s
Mark omnibar omnibar
Type "lis" 120ms
Sleep 250ms
Mark suggestions results
Sleep 900ms
Key down
Sleep 400ms
Key return
Wait title "Lisbon"
Mark wayfarer
Sleep 1.5s
Move @780,560 900ms
Scroll 560 1.6s
Sleep 700ms

# A site asks where you are, in a bubble over the page.
Click page "#nearby"
Wait AXButton "Never allow"
Mark prompt-title AXStaticText "wants to"
Mark prompt-buttons AXButton "Allow" #3
Mark prompt-never AXButton "Never allow"
Sleep 1.6s
Move AXButton "Never allow" 700ms
Sleep 300ms
Click
Sleep 900ms

# Every tab, and the pins, on ⌘S.
Key cmd+s
Wait overlay
Sleep 200ms
Mark overlay overlay
Mark pins pins
Sleep 1s
Key down
Sleep 300ms
Key down
Sleep 700ms
Move AXButton "Hum" 900ms
Sleep 500ms
Click
Wait title "Hum"
Mark hum
Sleep 2.2s

# The command palette finds pages by what's on them.
Key cmd+p
Wait palette
Sleep 300ms
Mark palette palette
Type "sleeper" 100ms
Sleep 300ms
Mark found results
Sleep 1.4s
Key return
Wait title "night train"
Mark meridian
Sleep 1.2s
Scroll 420 1.4s
Sleep 1.6s
Mark end
