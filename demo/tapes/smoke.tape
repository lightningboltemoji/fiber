# Checks the director end to end on one page.
Window 1400x900
Open https://lettera.app/
Pointer @-40,400

Sleep 800ms
Key cmd+l
Wait omnibar
Mark omnibar omnibar
Type "hello world" 70ms
Sleep 500ms
Key escape
Sleep 400ms
Move @700,450 800ms
Scroll 400 1s
Sleep 600ms
