# The README's video: Leo, mid-trip in Lisbon, answers a friend who wants
# coffee near where he's staying. A search from a new tab finds a café map,
# which asks where he is; ⌘S opens the mail pin to reply; ⌘P finds the
# guesthouse's address on its page; and ⌘S goes back to the reply.
Window 1600x1000
Seed 7
Search "Kestrel" kestrel.so https://kestrel.so/search?q=%s
Pin https://lettera.app/ "Inbox – Lettera"
Pin https://daybook.app/ "Daybook"
Pin https://hum.fm/ "Hum"
Open https://casa-alecrim.pt/ https://margin.so/ https://meridian.news/night-trains/ https://saltwater.kitchen/pasteis-de-nata/ https://caldera.dev/docs/getting-started/ https://lumen.camera/
Pointer @-80,640

Key cmd+t
Sleep 1.2s
Record

# A search from a new tab.
Sleep 1.4s
Mark omnibar omnibar
Type "best coffee in alfama" 80ms
Sleep 250ms
Mark suggestions results
Sleep 700ms
Key return
Wait title "Kestrel"
Mark kestrel
Sleep 1.1s
Mark result page "#top-result"
Move page "#top-result" 900ms
Sleep 250ms
Click
Wait title "Wayfarer"
Mark wayfarer
Locate 38.7121,-9.1302
Sleep 0.9s

# The map asks where he is, in a bubble over the page, and finds the café
# round the corner.
Move page "#nearby" 700ms
Sleep 150ms
Click
Wait AXButton "Never allow"
Mark prompt
Sleep 1.4s
Mark prompt-title AXStaticText "wants to"
Mark prompt-buttons AXButton "Allow" #3
Click AXButton "Allow" #3
Mark allowed
Wait page ".located"
Sleep 1.6s

# ⌘S: every tab, and the pins. The mail pin, where Inês is waiting.
Key cmd+s
Wait overlay
Sleep 200ms
Mark overlay overlay
Mark pins pins
Sleep 1.1s
Move AXButton "Lettera" 800ms
Sleep 250ms
Click
Wait title "Lettera"
Mark mail
Sleep 300ms
Mark subject page ".subject h2"
Sleep 1.2s
Move page "#reply-body" 450ms
Sleep 100ms
Click
Sleep 300ms
Mark draft page "#reply-draft"
Type "We're staying at " 75ms
Sleep 1.2s

# ⌘P finds the address on the guesthouse's page.
Key cmd+p
Wait palette
Mark palette palette
Sleep 500ms
Type "address" 95ms
Sleep 300ms
Mark found results
Sleep 1.4s
Key return
Wait title "Casa do Alecrim"
Mark casa
Sleep 800ms
Mark address page "#address"
Click page "#address" 3x
Sleep 450ms
Key cmd+c
Sleep 700ms

# ⌘S again, and the mail pin, back to the reply.
Key cmd+s
Wait overlay
Sleep 200ms
Mark overlay-again overlay
Mark pins-again pins
Sleep 700ms
Move AXButton "Lettera" 700ms
Sleep 250ms
Click
Wait title "Lettera"
Mark back
Sleep 500ms
Key cmd+v
Sleep 350ms
Type ". Leitaria do Largo is round the corner. 8:30?" 65ms
Sleep 900ms
Mark send page "#send-reply"
Click page "#send-reply"
Sleep 3s
Mark end
