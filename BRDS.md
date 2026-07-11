# BRDS - KSDS File Browser

A utility I wrote to help when developing `MNDL` and `MNDU`. It lets you browse the records in a **KSDS** file.

The record can be parsed into fields using a separator character. In this mode if a field exceeds the display width it will be truncated. If a record is truncated a red **T** is displayed to the left and the right ends in `...` as visual indicators. A note will be displayed indicating field(s) have been truncated, which may be off screen.

If no separator is provided the record is displayed as plain text. In this mode if a field exceeds the display width it will be wrapped. A note will be displayed indicating the record has been wrapped.

If the number of rows exceeds the display height then the list can be scrolled using **PF9** and **PF10**. Markers indicate where there is more data up or down and if at the top or bottom of the list. The current page and the total number of pages are displayed.

When `BRDS` exits it sets **DFHCOMMAREA** to the current file, key and field separator, just like it is specified on the command line. This is intended to allow other programs to **LINK** to `BRDS` to pick a record to be returned. This has the added bonus that **DFHCOMMAREA** persists in your session, so it acts like a place holder. When you start `BRDS` again it will pick up where you left off.

If you are calling BRDS and and expecting record details to be returned in **DFHCOMMAREA** be aware of the formatting. It is just like command line arguments. Which means the first field might be `-s`. If present `-s` will be followed by the separator. For example `-s | MANDELBROT Antenna` means the separator is `|`, the file is `MANDELBROT` and the record key was `Antenna`. The same example without the separator `MANDELBROT Antenna`.

## Fields

* File: The **KSDS** file to browse. REQUIRED.
* Start Key: The key to start from. This is passed to **STARTBR** when opening or resetting the cursor. Optional.
* Field Separator: Parse the record into fields using the separator. You can use any character. Optional.

## AID Keys

* **PF1** - Display help text. The same text when giving the `-h` command line option.
* **PF3** - Exit.
* **PF5** - Reset the cursor with **RESETBR**.
* **PF6** - Rotate the separator through the list `|`, `,`, `;`, `:`, `~`, and blank to display the record as plain text.
* **PF7** - Read the previous record with **READPREV**.
* **PF8** - Read the next record with **READNEXT**. Also **Enter**.
* **PF9** - Scroll the field list up.
* **PF10** - Scroll the field list down.
* **PF13** - Display debug information. Long values will be truncated to fit in the display width. \
  Shows the contents of the STEMS:
  * `SET.` containing settings.
  * `SCR.` containing the screen data for the **MAP**.
  * `FIELDS.` containing the parsed fields or the text of the record split into rows.

  *(This key is not noted anywhere else. It is only intended for development and bug hunting.)*
* **PF23** - A demonstration of using **LINK** to call `BRDS`. **DFHCOMMAREA** contains `-s ~ BRDSTEST ReallyBig Press F3 to return.`. Test data will be created in the file **BRDSTEST** before the call is made.

  *(This key is not noted anywhere else. It is only intended for developers calling `BRDS`)*
* **PF24** - BRDS demo. Creates test data in the file **BRDSTEST** then browses the file.

## Command Line

Using the command line you can provide `BRDS` with the **KSDS** file name, the starting key, the field separator and even display a message to the user.

Command line usage: `BRDS [-h] [-s SEPARATOR] [FILE_NAME [START_KEY] [MESSAGE]]`

To display a message the start key is required. Everything after the the start key is used for the message, displayed as an error.

Examples:

```text
BRDS -s | MANDELBROT
BRDS MANDELBROT Defaults
BRDS BRDSTEST ReallyBig This is a message the user will see in RED.
```

You can **CICS** **LINK** to `BRDS` passing command line options via **DFHCOMMAREA**. for example `COMMAREA = '-s | MANDELBROT Paul'` When BRDS returns it will set **DFHCOMMAREA** to the current file, key and field separator.

## Files

```text
runtime/rexx/brds.rexx
runtime/map/brds1.map
runtime/map/brds1l.map
runtime/map/brds1m.map
runtime/map/brds1w.map

```

## Transactions

```text
BRDS:rexx:brds.rexx:USERS
```

## Screenshots

Viewing a simple plain text record on a Model 2 terminal.

![Plain Text](Screenshots/BRDS_Model2.png)

Viewing one of the `MNDL` saves on a Model 3 terminal.

![MNDL Save](Screenshots/BRDS_Model3.png)

Viewing a record with a long field truncated on a Model 4 terminal. Note the red `T` noting the field has been truncated and the `...` at the end also showing it was truncated.

![Truncated Field](Screenshots/BRDS_Model4.png)

Viewing a rather large record on the enormous Model 5 terminal.

![Big Record](Screenshots/BRDS_Model5.png)

## Changes

* 2026-05-25 - Initial release.
* 2026-05-27 - Read the file and starting key from the command line. Handle going past the last record more gracefully. The cursor is re-opened and the last record re-read so you can keep scrolling through the data.
* 2026-05-29 - Complete overhaul. Better interface. Show all of a record. Split records into fields by a separator. Test data for demonstration. Help text. And bugs fixed.
* 2026-05-30 - Removed the requirement for the transaction ID to be in COMMAREA.
* 2026-05-30 - Properly handle DFHCOMMAREA. I didn't understand it...
* 2026-05-30 - Made the AID keys for scrolling through the displayed data more prominent.
* 2026-06-01 - Adjusted the maps to add more rows of data.
* 2026-06-06 - Fixed an issue parsing records with empty fields. These would cause parsing to stop.
* 2026-06-06 - Fixed handling of command line arguments and DFHCOMMAREA. Added a record to test data to exercise this fix.
* 2026-06-06 - Correctly include the separator in DFHCOMMAREA when quitting.
* 2026-06-06 - Off by one error where the last field could be dropped.
* 2026-06-15 - Hopefully handling command line arguments correctly.

## The future?

Thoughts on future improvements. Feedback welcome.

* Store record formats for tables to allow fields to be labelled. This should support delimited and fixed width records. With a condition to check if the format applies to a record. Automatically apply a separator at the table and format level. Admin only!

* Delete the current record, with confirmation. Admin only!

* Edit the plain text of a record. Prevent editing if the record contains non-printable characters. Admin only!
