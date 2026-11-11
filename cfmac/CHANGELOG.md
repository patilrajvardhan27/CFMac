# Changelog

## 2.1.0

### Fan control

- Cool and Max now hold whichever tab is open, from the menu bar, and with the window closed.
  The speed lease used to be renewed only while the Status tab was on screen, so fans quietly
  returned to Auto about 20 seconds after leaving it.
- App rules ("Cool while Xcode runs") and the menu bar fan readings update without opening
  Status.
- App Nap can no longer stretch the renewal past the lease while fans are held, and fans are
  re-applied right after the Mac wakes.
- The helper survives clients that disconnect early. If it stops unexpectedly, it restores the
  original fan state when launchd starts it again.
- Works with firmware that names the mode key `F0md`, waits longer for macOS to release the
  fans, skips fans that report no speed range, and tolerates small rounding of the target speed.
- After updating cfmac, picking Cool or Max asks once to update the helper instead of failing
  with "the fan helper isn't running".

### Free up space

- "Manual" items are gone. iPhone backups, local AI models, Docker's disk image and simulators
  now have a **Look Up** button that opens a Google search for the safe way to free that space.
  Every Clean item also offers it from the right-click menu.
- Apps that ship their own uninstaller get **Look Up How to Uninstall**.

### Build

- `Sources/Artwork` is now part of the repository (the old ignore rule excluded it), so a fresh
  clone builds.
- GitHub Actions builds, tests and packages the DMG on every push to `main` and `raj-asleep`.

### Install

1. Open `cfmac-2.1.0.dmg` and drag **cfmac** to **Applications**.
2. The first time, open it from Applications. If macOS says it can't verify the developer, go
   to **System Settings › Privacy & Security** and click **Open Anyway**.
3. If you used fan control before, pick Cool or Max once and approve the helper update.
