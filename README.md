# Minette-Codes: Bricks

Some stuff I wrote for Bricks. \
<https://github.com/moshix/bricks_ts>.

## Installation

* First you need to get [Bricks](https://github.com/moshix/bricks_ts) running. Follow the readme.
* Copy the contents of `runtime/` over top of your Bricks directory. No files should be overwritten.
* Add the desired transactions to your file `runtime/transactions.conf`.

## Mandelbrot

Generates a Mandelbrot set.

Use `MNDL` to generate a Mandelbrot fractal in ASCII. You can zoom in/out, scroll the fractal, re-center at the cursor, generate a Julia set with the cursor and save settings. You can also rotate through the saved settings, even while displaying the fractal.

Use the included utility `MNDU` to import, export and delete saves. The included `runtime/tmp/mndl_import.txt` includes some saves. When importing any existing saves are NOT overwritten.

Adapted from: <https://rosettacode.org/wiki/Mandelbrot_set> \
(With help from Google.)

See also:
* <https://www.dynamicmath.xyz/mandelbrot-julia/>
* <https://paulbourke.net/fractals/juliaset/>

### Files

```
runtime/rexx/mndl.rexx
runtime/rexx/mndu.rexx
runtime/map/mndl1.map
runtime/map/mndu1.map
runtime/tmp/mndl_import.txt
```

### Transactions

```
MNDL:rexx:mndl.rexx:USERS
MNDU:rexx:mndu.rexx:USERS
```

### Screenshots

The main menu showing the saved setting **PaulZoom1**.

![Main Menu](Screenshots/MNDL_Menu.png)

The Mandelbrot fractal generated from the saved setting **PaulZoom1**.

![Mandelbrot](Screenshots/MNDL_Zoom.png)

The Julia set generated from the cursor in the previous screenshot.

![Julia Set](Screenshots/MNDL_Julia.png)

The Mandelbrot fractal generated from the details settings.

![Default Mandelbrot](Screenshots/MNDL_Default.png)

Showing the overlay with helpful information, help for the AID keys and a marker in the center. This also shows that the cursor is positioned in the center now.

![Overlay](Screenshots/MNDL_Overlay.png)



### Fun thing to try

* Open the web terminal for Bricks <http://localhost:9000/>.
* Adjust the size to something giant like 80x200.
* Set the font as small as it will go.
* Wait.....

![Big Mandelbrot](Screenshots/MNDL_Big.png)

## Changes

* 2026-05-25 - Initial release.
* 2026-05-26 - Added an overlay with useful information. Also position the cursor in the center.
* 2026-05-26 - A new save for the Antenna, the long part on the left. Keep zooming.
* 2026-05-27 - Fix the page handling code. It was backwards, and didn't update the current page number.

## BRDS - KSDS File Browser

A utility I wrote to help when developing `MNDL` and `MNDU`. It lets you browse the records in a **KSDS** file.

The record can be parsed into fields using a separator character. In this mode if a field exceeds the display width it will be truncated. If a record is truncated a red **T** is displayed to the left and the right ends in `...` as visual indicators. A note will be displayed indicating field(s) have been truncated, which may be off screen.

If no separator is provided the record is displayed as plain text. In this mode if a field exceeds the display width it will be wrapped. A note will be displayed indicating the record has been wrapped.

If the number of rows exceeds the display height then the list can be scrolled using **PF9** and **PF10**. Markers indicate where there is more data up or down and if at the top or bottom of the list. The current page and the total number of pages are displayed.

### Fields:

* File: The **KSDS** file to browse. REQUIRED.
* Start Key: The key to start from. This is passed to **STARTBR** when opening or resetting the cursor. Optional.
* Field Separator: Parse the record into fields using the separator. You can use any character. Optional.

### AID Keys

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
* **PF23** - A demonstration of using **LINK** to call `BRDS`. **DFHCOMMAREA** contains `BRDS -s ~ BRDSTEST ReallyBig Press F3 to return.`. Test data will be created in the file **BRDSTEST** before the call is made.

  *(This key is not noted anywhere else. It is only intended for developers calling `BRDS`)*
* **PF24** - BRDS demo. Creates test data in the file **BRDSTEST** then browses the file.

### Command Line

Using the command line you can provide `BRDS` with the **KSDS** file name, the starting key, the field separator and even display a message to the user.

Command line usage: `BRDS [-h] [-s SEPARATOR] [FILE_NAME [START_KEY] [MESSAGE]]`

To display a message the start key is required. Everything after the the start key is used for the message, displayed as an error.

Examples:

```
BRDS -s | MANDELBROT
BRDS MANDELBROT Defaults
BRDS BRDSTEST ReallyBig This is a message the user will see in RED.
```

You can **CICS** **LINK** to `BRDS` passing command line options via **DFHCOMMAREA**. *If using LINK make sure to include the transaction ID in DFHCOMMAREA! DFHCOMMAREA has to be exactly like a command line.*

### Files

```
runtime/rexx/brds.rexx
runtime/map/brds1.map
runtime/map/brds1l.map
runtime/map/brds1m.map
runtime/map/brds1w.map

```

### Transactions

```
BRDS:rexx:brds.rexx:USERS
```

### Screenshots

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
* 2026-05-26 - Complete overhaul. Better interface. Show all of a record. Split records into fields by a separator. Test data for demonstration. Help text. And bugs fixed.

## Go Script

The script `./go` will start Bricks. It figures out which binary to run. Update the variable `BricksPath` to the path Brick lives.

I keep Bricks as a submodule in my Bricks GIT repository.

## Changes

* 2026-05-25 - Initial release.
