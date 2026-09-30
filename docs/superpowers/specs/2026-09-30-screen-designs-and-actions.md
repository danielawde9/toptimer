# TopTimer screen designs and actions

The user approved the four generated image sheets and requested implementation
and verification of the buttons. Implement them in native SwiftUI and AppKit,
using system colors so the light designs also adapt to dark appearance.

Use rounded blue time badges, restrained dividers, native forms and tables,
status labels, and the existing daily/weekly report charts. Keep timer controls
available after pausing. Show parsing and operation failures where they occur.
Offer the three working example commands on a fresh installation.

Connect the menu-bar popover to the main window and timer list. Connect the main
window and list to History and Reports. Preserve singleton window ownership,
editor sheets, confirmation dialogs, persistence and notification behavior.
The mockups supply visual direction; their invented controls and spacing are
adapted to functional native components rather than copied as raster assets.

Verify with real rendered controls backed by an in-memory Core Data store:
start, pause/resume, stop/finish, suggestions, navigation, timer actions, editor
save/cancel, recovery, history editing/deletion/recovery and report updating.
Run the existing regression suite, release build and bundle verification. Save
native rendered screenshots for visual review. Do not change the installed app
or personal timer data.
