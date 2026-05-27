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

## KSDS Browser

A simply utility I wrote to help when developing `MNDL` and `MNDU`.

`BRDS` prompts for a **KSDS** file then displays each record using a cursor. Nothing fancy, just a way to look at what is in the database. The record is truncated, because I'm lazy.

You can give `BRDS` the file and key from the command line. For example: `BRDS mandelbrot Defaults`

### Files

```
runtime/rexx/brds.rexx
runtime/map/brds1.map
```

### Transactions

```
BRDS:rexx:brds.rexx:USERS
```

### Screenshots

Browsing the saved settings for `MNDL`.

![Main Menu](Screenshots/BRDS.png)

## Changes

* 2026-05-25 - Initial release.
* 2026-05-26 - Read the file and starting key from the command line. Handle going past the last record more gracefully. The cursor is re-opened and the last record re-read so you can keep scrolling through the data.

## Go Script

The script `./go` will start Bricks. It figures out which binary to run. Update the variable `BricksPath` to the path Brick lives.

I keep Bricks as a submodule in my Bricks GIT repository.

## Changes

* 2026-05-25 - Initial release.
