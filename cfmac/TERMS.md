# cfmac Terms of Use and License

Version 1 · Effective October 27, 2026

Copyright © 2026 cfmac contributors. All rights reserved.

Please read these terms before you use cfmac. By installing, opening or using cfmac, you
agree to them. If you do not agree, do not use cfmac.

## 1. Free software, used at your own risk

cfmac is free. There is no price, subscription, trial or license key. It is offered as a
convenience, with no promise that it suits any particular purpose, and **you use it entirely
at your own risk**.

## 2. License

Subject to these terms, the copyright holders grant you a free, worldwide, non-exclusive,
revocable license to:

- install and use cfmac on any Mac you own or control, for personal or commercial purposes;
- make and share exact, unmodified copies, as long as each copy includes these terms and
  the third-party notices (NOTICES.md) and is given away free of charge.

You may not:

- sell, rent or charge for cfmac, on its own or as part of a bundle;
- remove or change copyright notices, these terms or the third-party notices;
- distribute modified versions under the cfmac name, or in a way that suggests they are
  official.

All rights not expressly granted here are reserved.

## 3. What cfmac does to your Mac

cfmac is a maintenance tool. Depending on what you choose, it may:

- move files to the Trash or delete them permanently, including caches, logs, app data and
  the contents of the Trash;
- uninstall apps and remove the data they leave behind;
- run maintenance commands, some with administrator rights after you approve the macOS
  password prompt;
- stop processes, change startup items, keep the display awake or blank the screen;
- install a background helper that runs as the system administrator (root) and, when you ask,
  changes fan speed.

cfmac shows what it plans to remove before removing it, and it refuses to touch system
locations it knows to be critical. It cannot know what every file means to you. **Review every
selection, and keep a current backup (for example, with Time Machine) before cleaning or
uninstalling anything.** Deleted data may be impossible to recover.

## 4. Fan control

Fan control writes settings to your Mac's System Management Controller. cfmac keeps fan speeds
within the limits your Mac reports. It hands control back to macOS when you choose Auto, when
you quit cfmac, and on its own if cfmac stops responding. Running fans at high speed increases
noise, power use and wear. Fan control is optional, is not provided or endorsed by Apple, and
may stop working or behave differently on some Macs or versions of macOS. Turn it on only if you
accept these risks. You can remove the helper at any time in Settings.

## 5. No warranty

CFMAC IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE,
NON-INFRINGEMENT AND ACCURACY, AND ANY WARRANTY THAT IT WILL WORK WITHOUT INTERRUPTION OR
ERROR. Sizes, temperatures, battery health, health scores and other readings are estimates.

## 6. Limitation of liability

TO THE FULLEST EXTENT PERMITTED BY LAW, THE COPYRIGHT HOLDERS AND CONTRIBUTORS WILL NOT BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY ARISING FROM OR CONNECTED WITH CFMAC OR ITS
USE. THIS INCLUDES LOSS OF DATA, LOSS OF PROFITS, DAMAGE TO HARDWARE, AND DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, CONSEQUENTIAL OR EXEMPLARY DAMAGES, EVEN IF THEY WERE ADVISED THAT SUCH
DAMAGES WERE POSSIBLE. Where the law does not allow a limitation, liability is limited to the
smallest amount the law permits.

## 7. Privacy

cfmac runs entirely on your Mac. It reads file names, sizes and dates, never the contents of
your documents, and it never looks inside Photos, Mail, Messages, Contacts, Calendars, Safari
or Keychains. It never asks for the camera, microphone, location, contacts or photos. It has no
accounts, collects no analytics and sends no data anywhere. It uses the network only when you
ask it to check for or install updates, through the Homebrew or App Store command-line tools on
your Mac; those services have their own terms. Details are in the Privacy Statement
(PRIVACY.md).

## 8. Third-party material

cfmac includes artwork by other creators, used under their licenses and listed in NOTICES.md
(Open Source Licenses in the app). Those licenses govern that material.

Apple, Mac and macOS are trademarks of Apple Inc. cfmac is not affiliated with, sponsored by or
endorsed by Apple, or by any company whose products cfmac can clean, update or remove.

## 9. Changes and ending these terms

New versions of cfmac may come with updated terms. When that happens, the version and date
above change and cfmac asks you to accept the new terms before continuing. Your license ends
automatically if you break these terms; you must then stop using cfmac and delete it.
