# Minette-Codes: Bricks

Some stuff I wrote for Bricks. \
<https://github.com/moshix/bricks_ts>.

`MNDL` and `BRDS` are now included in the [Bricks](https://github.com/moshix/bricks_ts) repository. No need to futz around, just go install [Bricks](https://github.com/moshix/bricks_ts)!

## Contents

* [JSON REXX Library](#json-rexx-library)
* [BOFH - JSON Example](#bofh---json-example)
* [Installation](#installation)
* [MNDL - Mandelbrot Set Viewer](#mndl---mandelbrot-set-viewer)
* [BRDS - KSDS File Browser](#brds---ksds-file-browser)
* [FSPF - Fake ISPF Menu](#fspf---fake-ispf-menu)
* [License](#license)

<!-- With the help of: https://bitdowntoc.derlin.ch/ -->

## JSON REXX Library

A library for parsing and manipulating JSON.
See [JSON.md](JSON.md) for details.
There is too much to fit here.

![JSON Explorer](Screenshots/JSON_Console.png)

## BOFH - JSON Example

A simple example of using the [JSON library](JSON.md) to fetch and display an excuse.
See the site <https://bofh.bombeck.io/> for details.
See [JSON.md](JSON.md#bofh---json-example) for details.

![BOFH Excuse](Screenshots/BOFH.png)

## MNDL - Mandelbrot Set Viewer

Mandelbrot set fractal explorer.
See [MNDL.md](MNDL.md) for details.

![Mandelbrot](Screenshots/MNDL_Zoom.png)

## BRDS - KSDS File Browser

`BRDS` is a utility for browsing records in **KSDS** files.
See [BRDS.md](BRDS.md) for details.

![MNDL Save](Screenshots/BRDS_Model3.png)

## FSPF - Fake ISPF Menu

A simple menu system with delutions of grandure.
See [FSPF.md](FSPF.md) for details.

![Main Screen](Screenshots/FSPF.png)

## Installation

**NOTE:** `BRDS`, `FSPF` and `MNDL` are now included in the [Bricks](https://github.com/moshix/bricks_ts) repository. The only reason to use this repository is to grab changes Moshix hasn't included or to send me pull requests. Save yourself the hassle, just go run [Bricks](https://github.com/moshix/bricks_ts).

Basic steps:

* First you need to get [Bricks](https://github.com/moshix/bricks_ts) running. Follow the file `README.md`.
* Copy the contents of `runtime/` from this repository over top of your Bricks directory. No files should be overwritten unless you are replacing an old copy.
* Add the desired transactions to your file `runtime/transactions.conf`. Noted in the **Transactions** sections below.

### Installing everything?

Copy the `runtime/` files:

```bash
cp -r runtime/* PATH_TO_BRICKS
```

Add these transactions to the file `runtime/transactions.conf`:\
(These can also be found in the file `transactions.txt`.)

```text
BRDS:rexx:brds.rexx:USERS
ESPF:rexx:espf.rexx:ADMIN
FSPF:rexx:fspf.rexx:USERS
MNDL:rexx:mndl.rexx:USERS
MNDU:rexx:mndu.rexx:USERS
JSON:rexx:json.rexx:USERS
BOFH:rexx:bofh.rexx:USERS
```

### Alternate setup

An alternate setup to make your life easier would be checkout this repository and [Bricks](https://github.com/moshix/bricks_ts) into a shared directory. Then copy the required files from both repositories into the shared parent directory.

The result would look like this:

* `MyBricks/`
  * `BRICKS_TS/` - The [Bricks](https://github.com/moshix/bricks_ts) repository.
  * `Minette/` - This repository.
  * `runtime/` - The combined runtime files from both repositories.
  * `data/` - The `data/` directory from the [Bricks](https://github.com/moshix/bricks_ts) repository.
  * All of the other files from the [Bricks](https://github.com/moshix/bricks_ts) repository top level.

This setup would provide a directory to experiment with [Bricks](https://github.com/moshix/bricks_ts) and not interfere with either of the repositories. It can get messy quick when you `git pull` if any files are new or different.

Setup the shared directory:

```bash
mkdir Bricks
cd Bricks
git clone https://github.com/moshix/BRICKS_TS.git
git clone https://github.com/Minette-Codes/Bricks.git Minette
(cd BRICKS_TS/; cp *.* ../; cp -rv data/ runtime/ ../)
(cd Minette; cp -rv runtime/ ../)
cat Minette/transactions.txt >> runtime/transactions.conf
```

Run [Bricks](https://github.com/moshix/bricks_ts):

```bash
./start_bricks.bash
```

Update from Github, **WITHOUT** replace any files:\
(This is the sensible choice. New files will be copied. You can decide what to do with changed files.)

```bash
(cd BRICKS_TS/; git pull; cp -nrv *.* data/ runtime/ ../)
(cd Minette; git pull; cp -nrv runtime/ ../)
```

Update from Github, **REPLACE ALL FILES**:\
**(DON'T do this if you intend to make changes to the files. You WILL loose your changes!)**

```bash
(cd BRICKS_TS/; git pull; /bin/cp -rv *.* data/ runtime/ ../)
(cd Minette; git pull; /bin/cp -rv runtime/ ../)
```

### Changes

* 2026-07-03 - Removed the `go` script. Use `start_bricks.bash` from the BRICKS_TS directory.
* 2026-07-11 - Moved detailed documentation for `MNDL`, `BRDS`, and `FSPF` into separate files.

## License

I claim no copyright on anything here. I have copied copious amounts of code from [Bricks](https://github.com/moshix/bricks_ts) examples and documentation. If I actually wrote it, consider it public domain and do whatever you please with it. But that does make YOU legally responsible for copyright violations of other peoples code.

Do not use this production, I claim no legal liability for misusing this for mission critical workloads, keep away from governments and children, blah blah blah, the usual don't blame me...

And don't blame Moshix for my insanity.
