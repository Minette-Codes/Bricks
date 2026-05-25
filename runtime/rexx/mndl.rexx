/* MNDL - Draw a Mandelbrot set. */
/* Adapted from: https://rosettacode.org/wiki/Mandelbrot_set */
/* With help from Google. */
/* See also: */
/*  https://www.dynamicmath.xyz/mandelbrot-julia/ */
/*  https://paulbourke.net/fractals/juliaset/ */

ADDRESS CICS

/* Adapt to the terminal size. */
EXEC CICS ASSIGN SCREENHT(TERM_HEIGHT) SCREENWD(TERM_WIDTH) TERMID(TRM)  END-EXEC

/* More precision. */
NUMERIC DIGITS 15

/* Default settings. */
DFTL_MAXITER = 50
DFLT_CHARS = '>=<;:9876543210/.-,+*)(''&%$#"!'
DFLT_CENTERREAL = -0.6
DFLT_CENTERIMAG = 0.0
DFLT_ZOOM = 1
DFLT_SCALE = 3

/* I keep way to much in SCR. :shrugs: */
SCR = ''
SCR.TERMID      = TRM
SCR.SAVE_FILE   = 'mandelbrot'
SCR.VARS_SET    = 'NO'
SCR.CURSOR_OPEN = 'NO'

/* The settings used to draw the Mandelbrot fractal. */
MNDL = ''
MNDL.HEIGHT = TERM_HEIGHT
MNDL.WIDTH  = TERM_WIDTH - 1

/* Change the aspect ratio. To accommodate characters being taller than wider. */
MNDL.XASPECT = 3.0
MNDL.YASPECT = 2.25

/* Main loop. */
DO FOREVER
  /* Do it this here so the user can restore default settings. */
  IF SCR.VARS_SET \= 'YES' THEN DO
    SCR.NMITER = DFTL_MAXITER
    SCR.NCHARS = DFLT_CHARS
    SCR.NCREAL = DFLT_CENTERREAL
    SCR.NCIMAG = DFLT_CENTERIMAG
    SCR.NZOOM  = DFLT_ZOOM
    SCR.NSCALE = DFLT_SCALE
    SCR.NNAME  = ''
    SCR.NNOTE  = ''
    SCR.VARS_SET = 'YES'
  END

  EXEC CICS CONVERSE MAP('MNDL1') FROM(SCR.) INTO(SCR.) ERASE END-EXEC
  SCR.MSG = ''

  /* Do we draw the Mandelbrot fractal or not. */
  SCR.DO_DRAW = 'YES'

  /* Make sure '|'' does not end up in the draw characters. */
  /* Because I'm lazy and I use '|'' as the field separator. */
  IF POS('|', SCR.NCHARS) \= 0 THEN DO
      SCR.DO_DRAW = 'NO'
      SCR.MSG = 'Do not use "|" in the character list.'
  END

  /* Update the settings in MDL. */
  CALL SETTTINGS_UPDATE

  /* Handle special keys. */
  CALL AID_MAIN_MENU C2X(EIBAID)

  IF SCR.DO_DRAW = 'NO' THEN ITERATE

  /* Draw loop. Lets the user scroll and zoom. */
  DO WHILE SCR.DO_DRAW = 'YES'
    CALL SETTTINGS_UPDATE
    CALL MANDELBROT
  END
END

/* End of program. */
EXIT

/* Generate the Julia set. */
/* Draws using the settings in MNDL. */
JULIA: PROCEDURE EXPOSE MNDL. SCR.
  PARSE ARG CENTERIMAG CENTERREAL
  OUTPUT = ''

  /* Correct the aspect ratio. */
  /* The Julia set has a different X-range. */
  JUL.XRANGE = (MNDL.XASPECT + 1) /* / MNDL.ZOOM */
  JUL.YRANGE = MNDL.YASPECT       /* / MNDL.ZOOM */

  /* Set the bounds and steps. */
  JUL.XMIN  = 0 - (JUL.XRANGE / 2)
  JUL.YMAX  = 0 + (JUL.YRANGE / 2)
  JUL.XSTEP = JUL.XRANGE / (MNDL.WIDTH - 1)
  JUL.YSTEP = JUL.YRANGE / (MNDL.HEIGHT - 1)

  DO ROW = 0 TO MNDL.HEIGHT - 1
    /* Map the row into the imaginary part. */
    IMAG = JUL.YMAX - (ROW * JUL.YSTEP)

    DO COL = 0 TO MNDL.WIDTH - 1
    /* Map the column into the real part. */
      REAL = JUL.XMIN + (COL * JUL.XSTEP)

      /* Iterate over the current point. */
      ZR = REAL
      ZI = IMAG
      DO I = 0 TO MNDL.MAXITER
        /* Has the point escaped into infinity? */
        IF (ZR * ZR + ZI * ZI) > 4 THEN LEAVE
        ZR2 = ZR * ZR
        ZI2 = ZI * ZI
        ZI = 2 * ZR * ZI + CENTERIMAG
        ZR = ZR2 - ZI2 + CENTERREAL
      END

      /* "Shade" the pixel. */
      IF I > MNDL.MAXITER THEN
        OUTPUT = OUTPUT || ' '
      ELSE
        OUTPUT = OUTPUT || SUBSTR(MNDL.CHARS, MOD(I, MNDL.NUMCHARS + 1), 1)
    END
    /* Padd the last column or odd things happen with the output. */
    OUTPUT = OUTPUT || ' '
  END

  /* Send the fractal. */
  EXEC CICS SEND TEXT FROM(OUTPUT) END-EXEC
  RETURN

/* Generate the Mandelbrot fractal. */
/* Draws using the settings in MNDL. */
MANDELBROT: PROCEDURE EXPOSE MNDL. SCR.
  OUTPUT = ''
  EXEC CICS ASKTIME ABSTIME(START_TIME) END-EXEC
  DO ROW = 0 TO MNDL.HEIGHT - 1
    /* Map the row into the imaginary part. */
    IMAG = MNDL.YMAX - (ROW * MNDL.YSTEP)

    DO COL = 0 TO MNDL.WIDTH - 1
    /* Map the column into the real part. */
      REAL = MNDL.XMIN + (COL * MNDL.XSTEP)

      /* Iterate over the current point. */
      ZR = 0
      ZI = 0
      DO I = 0 TO MNDL.MAXITER
        /* Has the point escaped into infinity? */
        IF (ZR * ZR + ZI * ZI) > 4 THEN LEAVE
        ZR2 = ZR * ZR
        ZI2 = ZI * ZI
        ZI = 2 * ZR * ZI + IMAG
        ZR = ZR2 - ZI2 + REAL
      END

      /* "Shade" the pixel. */
      IF I > MNDL.MAXITER THEN
        OUTPUT = OUTPUT || ' '
      ELSE
        OUTPUT = OUTPUT || SUBSTR(MNDL.CHARS, MOD(I, MNDL.NUMCHARS + 1), 1)
    END
    /* Padd the last column or odd things happen with the output. */
    OUTPUT = OUTPUT || ' '
  END

  EXEC CICS ASKTIME ABSTIME(END_TIME) END-EXEC
  SCR.MSG = 'Draw time:' (END_TIME - START_TIME) 'Milliseconds'

  /* Send the fractal. */
  EXEC CICS SEND TEXT FROM(OUTPUT) END-EXEC

  /* If this CALL isn't right here it doesn't get the key. */
  CALL AID_DRAW C2X(EIBAID)
  RETURN

/* Handle the AID keys on the draw screen. */
AID_DRAW: PROCEDURE EXPOSE MNDL. SCR. EIBCPOSN 
  PARSE ARG AID
  SELECT
    /* Center on the cursor. */
    WHEN AID = 'F1' THEN DO
      /* Translate the cursor position. */
      COL = (EIBCPOSN // (MNDL.WIDTH + 1)) - 2
      ROW = INT(EIBCPOSN / (MNDL.WIDTH + 1))
      SCR.NCIMAG = MNDL.YMAX - (ROW * MNDL.YSTEP)
      SCR.NCREAL = MNDL.XMIN + (COL * MNDL.XSTEP)
    END
    /* Show the Julia set for the current point. */
    WHEN AID = 'F5' THEN DO
      COL = (EIBCPOSN // (MNDL.WIDTH + 1)) - 2
      ROW = INT(EIBCPOSN / (MNDL.WIDTH + 1))
      REAL = MNDL.YMAX - (ROW * MNDL.YSTEP)
      IMAG = MNDL.XMIN + (COL * MNDL.XSTEP)
      CALL JULIA REAL IMAG
    END
    /* Zoom out. */
    WHEN AID = 'F7' THEN DO
      SCR.NZOOM = SCR.NZOOM / SCR.NSCALE
      IF SCR.NZOOM < 1 THEN SCR.NZOOM = 1
    END
    /* Zoom in. */
    WHEN AID = 'F8' THEN DO
      SCR.NZOOM = SCR.NZOOM * SCR.NSCALE
    END
    /* Scroll left. */
    WHEN AID = 'F9' THEN DO
      SCR.NCREAL = SCR.NCREAL - (MNDL.XRANGE / 4)
    END
    /* Scroll right. */
    WHEN AID = '7A' THEN DO /* PF10 */
      SCR.NCREAL = SCR.NCREAL + (MNDL.XRANGE / 4)
    END
    /* Scroll up. */
    WHEN AID = '7B' THEN DO /* PF11 */
      SCR.NCIMAG = SCR.NCIMAG + (MNDL.YRANGE / 4)
    END
    /* Scroll down. */
    WHEN AID = '7C' THEN DO /* PF12 */
      SCR.NCIMAG = SCR.NCIMAG - (MNDL.YRANGE / 4)
    END
    /* Shuffle through saves. */
    WHEN AID = 'C4' THEN DO /* PF16 */
      IF SCR.CURSOR_OPEN \= 'YES' THEN DO
        CALL CURSOR_OPEN
      END
      CALL CUSROR_READ
    END
    OTHERWISE DO
      SCR.DO_DRAW = 'NO'
    END
  END
  RETURN

/* Handle the AID keys on the main menu. */
  AID_MAIN_MENU: PROCEDURE EXPOSE MNDL. SCR. EIBAID
  PARSE ARG AID
  SELECT
    /* Load the defaults. */
    WHEN AID = 'F1' THEN DO
      SCR.DO_DRAW = 'NO'
      DROP SCR.VARS_SET
    END
    /* Delete a save. */
    WHEN AID = 'F2' THEN DO
      SCR.DO_DRAW = 'NO'
      CALL SETTTINGS_DELETE
    END
    /* Exit. */
    WHEN AID = 'F3' THEN DO
      IF SCR.CURSOR_OPEN \= 'YES' THEN
        CALL CURSOR_CLOSE
      EXEC CICS RETURN END-EXEC
    END
    /* Shuffle through saves. */
    WHEN AID = 'F4' | AID = 'C4' THEN DO /* PF4 & PF16 */
      IF AID = 'F4' THEN SCR.DO_DRAW = 'NO'
      IF SCR.CURSOR_OPEN \= 'YES' THEN DO
        CALL CURSOR_OPEN
      END
      CALL CUSROR_READ
    END
    /* Load settings. */
    WHEN AID = 'F5' THEN DO
      CALL SETTTINGS_LOAD
    END
    /* Save settings. */
    WHEN AID = 'F6' THEN DO
      SCR.DO_DRAW = 'NO'
      CALL SETTTINGS_SAVE KEY
    END
    /* Zoom out. */
    WHEN AID = 'F7' THEN DO
      SCR.NZOOM = SCR.NZOOM / SCR.NSCALE
      IF SCR.NZOOM < 1 THEN SCR.NZOOM = 1
    END
    /* Zoom in. */
    WHEN AID = 'F8' THEN DO
      SCR.NZOOM = SCR.NZOOM * SCR.NSCALE
    END
    /* Scroll left. */
    WHEN AID = 'F9' THEN DO
      SCR.NCREAL = SCR.NCREAL - (MNDL.XRANGE / 4)
    END
    /* Scroll right. */
    WHEN AID = '7A' THEN DO /* PF10 */
      SCR.NCREAL = SCR.NCREAL + (MNDL.XRANGE / 4)
    END
    /* Scroll up. */
    WHEN AID = '7B' THEN DO /* PF11 */
      SCR.NCIMAG = SCR.NCIMAG + (MNDL.YRANGE / 4)
    END
    /* Scroll down. */
    WHEN AID = '7C' THEN DO /* PF12 */
      SCR.NCIMAG = SCR.NCIMAG - (MNDL.YRANGE / 4)
    END
    WHEN AID = '6D' THEN DO /* Clear */
      SCR.DO_DRAW = 'NO'
    END
    OTHERWISE NOP
  END
  RETURN

/* Translate the settings from SCR into MNDL. */
SETTTINGS_UPDATE: PROCEDURE EXPOSE MNDL. SCR.
  MNDL.MAXITER    = SCR.NMITER
  MNDL.CHARS      = SCR.NCHARS
  MNDL.CENTERREAL = SCR.NCREAL
  MNDL.CENTERIMAG = SCR.NCIMAG
  MNDL.ZOOM       = SCR.NZOOM

  /* Correct the aspect ratio. */
  MNDL.XRANGE = MNDL.XASPECT / MNDL.ZOOM
  MNDL.YRANGE = MNDL.YASPECT / MNDL.ZOOM

  /* Set the bounds and steps. */
  MNDL.XMIN  = MNDL.CENTERREAL - (MNDL.XRANGE / 2)
  MNDL.YMAX  = MNDL.CENTERIMAG + (MNDL.YRANGE / 2)
  MNDL.XSTEP = MNDL.XRANGE / (MNDL.WIDTH - 1)
  MNDL.YSTEP = MNDL.YRANGE / (MNDL.HEIGHT - 1)
  
  MNDL.NUMCHARS = LENGTH(MNDL.CHARS)
  RETURN

/* Save the settings to the save file. */
SETTTINGS_SAVE: PROCEDURE EXPOSE SCR.
  KEY  = STRIP(SCR.NNAME)
  IF KEY = '' THEN
    SCR.MSG = 'Name required when saving.'
  ELSE DO
    REC = STRIP(SCR.NMITER) || '|' || STRIP(SCR.NCHARS) || '|' || STRIP(SCR.NCREAL) || '|' || STRIP(SCR.NCIMAG) || '|' || STRIP(SCR.NZOOM) || '|' || STRIP(SCR.NSCALE) || '|' || STRIP(SCR.NNOTE)
    EXEC CICS DELETE FILE(SCR.SAVE_FILE) RIDFLD(KEY) END-EXEC
    EXEC CICS WRITE FILE(SCR.SAVE_FILE) FROM(REC) RIDFLD(KEY) END-EXEC
    IF EIBRESP \= 0 THEN
      SCR.MSG = 'Error while saving.'
    ELSE DO
      CALL CURSOR_CLOSE
      SCR.MSG = 'Settings saved.'
    END
  END
  RETURN

/* Load the settings from the save file. */
SETTTINGS_LOAD: PROCEDURE EXPOSE SCR.
  PARSE ARG KEY
  SCR.DO_DRAW = 'NO'
  KEY  = STRIP(SCR.NNAME)
  IF KEY = '' THEN
    SCR.MSG = 'Name required when loading.'
  ELSE DO
    EXEC CICS READ FILE(SCR.SAVE_FILE) INTO(REC) RIDFLD(KEY) END-EXEC
    IF EIBRESP = 0 THEN DO
      CALL SETTTINGS_RECORD REC
      CALL CURSOR_CLOSE
    END
    ELSE IF EIBRESP = 13 THEN
      SCR.MSG = 'Save not found.'
    ELSE
      SCR.MSG = 'Error loading the save.'
  END
  RETURN

/* Load saved settings from a record. */
SETTTINGS_RECORD: PROCEDURE EXPOSE SCR.
  PARSE ARG MITER '|' CHARS '|' CREAL '|' CIMAG '|' ZOOM '|' SCALE '|' NOTE
  SCR.NMITER = MITER
  SCR.NCHARS = CHARS
  SCR.NCREAL = CREAL
  SCR.NCIMAG = CIMAG
  SCR.NZOOM  = ZOOM
  SCR.NSCALE = SCALE
  SCR.NNOTE  = NOTE
  RETURN

/* Delete a set of saved settings. */
SETTTINGS_DELETE: PROCEDURE EXPOSE SCR.
  KEY  = STRIP(SCR.NNAME)
  IF KEY = '' THEN
    SCR.MSG = 'Name required when deleting.'
  ELSE DO
    EXEC CICS DELETE FILE(SCR.SAVE_FILE) RIDFLD(KEY) END-EXEC
    IF EIBRESP = 13 THEN
      SCR.MSG = 'Save not found.'
    ELSE DO
      CALL CURSOR_CLOSE
      SCR.MSG = 'Record deleted.'
    END
  END
  RETURN

/* Working with the cursor for shuffling saves. */
CURSOR_OPEN: PROCEDURE EXPOSE SCR.
  EXEC CICS STARTBR FILE(SCR.SAVE_FILE) END-EXEC
  IF EIBRESP = 0 THEN
    SCR.CURSOR_OPEN = 'YES'
  ELSE
    SCR.MSG = 'Error opening the cursor for shuffle.'
  RETURN

CURSOR_CLOSE: PROCEDURE EXPOSE SCR.
  PARSE ARG KEY
  EXEC CICS ENDBR FILE(SCR.SAVE_FILE) END-EXEC
  SCR.CURSOR_OPEN = 'NO'
  RETURN

CUSROR_READ: PROCEDURE EXPOSE SCR.
  PARSE ARG KEY
  EXEC CICS READNEXT FILE(SCR.SAVE_FILE) INTO(REC) RIDFLD(SCR.NNAME) END-EXEC
  IF EIBRESP = 20 THEN DO
    CALL CURSOR_RESET
    EXEC CICS READNEXT FILE(SCR.SAVE_FILE) INTO(REC) RIDFLD(SCR.NNAME) END-EXEC
  END
  IF EIBRESP = 0 THEN
    CALL SETTTINGS_RECORD REC
  ELSE
    SCR.MSG = 'No saves to shuffle.'
  RETURN

CURSOR_RESET: PROCEDURE EXPOSE SCR.
  PARSE ARG KEY
  EXEC CICS RESETBR FILE(SCR.SAVE_FILE) RIDFLD(KEY) END-EXEC
  RETURN
