<!-- SPDX-FileCopyrightText: 2026 Sayantan Santra <sayantan.santra689@gmail.com> -->
<!-- SPDX-License-Identifier: GPL-3.0 -->

## KOReader Patches

This is a collection of the KOReader patches that I've written. A short description for each patch is provided below.

1. Calibre Collections
   This automatically creates KOReader collections using a custom collection from calibre. By default, a custom column called
   `#collections` is used. But the script can easily be edited to use any other column name.

   It does not touch already existing collections. So please don't create any collections with the same name an entry in `#collections` manually.
   Collections are created/updated at startup.

   [Read this to learn about custom columns.](https://wiki.mobileread.com/wiki/Kobo_Shelves_and_Collections#Driver_.2F_calibre_Configuration)

1. Clean Header
   This adds a clean looking header on top of KOReader reader view.

   It shows the author name on left, book title on right, and time in the middle. The time is automatically refreshed.
   Customization is possible, but I don't intend to provide much support.

   It's heavily inspired by https://github.com/joshuacant/KOReader.patches, please use his patches instead if you want more customization.
   This is simply a highly optimized version for my specific setup, along with auto refresh for the clock.

## Installation

Just copy the corresponding patch into your `<koreader>patches/` directory.
