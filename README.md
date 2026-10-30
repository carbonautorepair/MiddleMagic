# MiddleMagic

Separate experimental menu-bar app based on MiddlePaste; it does not replace the installed app.

- Middle-drag recognized selectable text to select and copy into the normal clipboard.
- Double middle-click recognized text to select a word and copy it.
- Single middle-click a recognized editable field to focus it and open CopyClip 2 using Control-V. The click waits for the system double-click interval.
- Links and unrecognized controls receive their native middle-click.

Requires Accessibility permission. Quit the original MiddlePaste before running this app so the two listeners do not compete. Configure CopyClip 2 to use Control-V. The app is experimental: mouse behavior and integration require hands-on testing. Some apps do not expose selectable text through Accessibility. Secure fields are excluded.

Build using Scripts/build-app.sh; app is in dist/MiddleMagic.app.
