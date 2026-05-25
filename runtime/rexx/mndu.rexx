/* MNDU - Mandelbrot Utility. */
/* Logic adapted from CUSL. */
/* Export, Import and Delete saved settings. */

ADDRESS CICS

/* Adapt to the terminal size. */
EXEC CICS ASSIGN TERMID(TRM)  END-EXEC

SAVE_FILE   = 'mandelbrot'
IMPORT_FILE = 'mndl_import.txt'
EXPORT_FILE = 'mndl_export.txt'

SCR = ''
SCR.TERMID        = TRM
SCR.PAGE          = 1
SCR.NPAGES        = 1
SCR.ROWS_PER_PAGE = 10
SCR.RELOAD        = 'YES'

/* Hold the data loaded from the save file. */
KEYS = ''
RECS = ''

DO FOREVER
  /* Load existing save files. */
  IF SCR.RELOAD = 'YES' THEN DO
    CALL SAVES_LOAD SAVE_FILE
    SCR.RELOAD = 'NO'
  END

  /* Save the saves for the current page into SCR. */
  CALL SAVES_SCR_PAGE

  SCR.NIMPORT = IMPORT_FILE
  SCR.NEXPORT = EXPORT_FILE
  EXEC CICS CONVERSE MAP('MNDU1') FROM(SCR.) INTO(MAP.) ERASE END-EXEC
  SCR.MSG = ''

  /* Did any settings change? */
  TYPED = STRIP(MAP.NIMPORT)
  IF TYPES \= '' & TYPED \= IMPORT_FILE THEN DO
    IMPORT_FILE = TYPED
  END
  TYPED = STRIP(MAP.NEXPORT)
  IF TYPES \= '' & TYPED \= EXPORT_FILE THEN DO
    EXPORT_FILE = TYPED
  END

  /* Handle special keys. */
  AID = C2X(EIBAID)
  SELECT
    /* Exit. */
    WHEN AID = 'F3' THEN DO
      EXEC CICS RETURN END-EXEC
    END
    /* Reload the list of saves. */
    WHEN AID = 'F5' THEN DO
      CALL SAVES_LOAD SAVE_FILE
    END
    /* Previous page. */
    WHEN AID = 'F7' THEN DO
      SCR.PAGE = SCR.PAGE + 1
      IF SCR.PAGE > SCR.NPAGES THEN
        SCR.PAGE = SCR.NPAGES
    END
    /* Next page. */
    WHEN AID = 'F8' THEN DO
      SCR.PAGE = SCR.PAGE + 1
      IF SCR.PAGE < 0 THEN
        SCR.PAGE = 1
    END
    /* Export saves. */
    WHEN AID = 'F9' THEN DO
      CALL SAVES_EXPORT SAVE_FILE EXPORT_FILE
    END
    /* Import saves. */
    WHEN AID = '7A' THEN DO
      CALL SAVES_IMPORT SAVE_FILE IMPORT_FILE
    END
    OTHERWISE NOP
  END

  /* Requested to delete saves? */
  CALL SAVES_DELETE SAVE_FILE
END

EXIT

SAVES_LOAD: PROCEDURE EXPOSE KEYS. RECS. SCR.
  PARSE ARG SAVE_FILE
  KEYS.0 = 0
  EXEC CICS STARTBR FILE(SAVE_FILE) END-EXEC
  DONE = 0
  DO WHILE DONE = 0
    EXEC CICS READNEXT FILE(SAVE_FILE) INTO(REC) RIDFLD(KEY) END-EXEC
    IF EIBRESP \= 0 THEN
      DONE = 1
    ELSE DO
      N = KEYS.0 + 1
      KEYS.0 = N
      KEYS.N = KEY
      RECS.N = REC
    END
  END
  EXEC CICS ENDBR FILE(SAVE_FILE) END-EXEC

  SCR.TOTAL = KEYS.0
  SCR.NPAGES = (SCR.TOTAL + SCR.ROWS_PER_PAGE - 1) % SCR.ROWS_PER_PAGE
  IF SCR.NPAGES = 0 THEN SCR.NPAGES = 1
  SCR.STATUS = 'Saves:' SCR.TOTAL 'Page:' SCR.PAGE 'of' SCR.NPAGES
  RETURN

SAVES_SCR_PAGE: PROCEDURE EXPOSE KEYS. RECS. SCR.
  START = (SCR.PAGE - 1) * SCR.ROWS_PER_PAGE + 1
  DO J = 1 TO SCR.ROWS_PER_PAGE
    IDX = START + J - 1
    LINE = ''
    IF IDX <= SCR.TOTAL THEN DO
      KEY = KEYS.IDX
      REC = RECS.IDX
      PARSE VAR REC MITER '|' CHARS '|' CREAL '|' CIMAG '|' ZOOM '|' SCALE '|' NOTE
      LINE = LEFT(KEY,16) LEFT(NOTE,55)
    END
    CALL VALUE 'SCR.ROW' || J, LINE
  END
  RETURN

SAVES_DELETE: PROCEDURE EXPOSE KEYS. MAP. SCR.
  PARSE ARG SAVE_FILE KEY
  DELETED = 0
  
  /* Check if any records were selected for deletion. */
  DO J = 1 TO SCR.ROWS_PER_PAGE
    CHECK = 'DEL' || J
    IF MAP.CHECK = 'D' | MAP.CHECK = 'd' THEN DO
      KEY = KEYS.J
      EXEC CICS DELETE FILE(SAVE_FILE) RIDFLD(KEY) END-EXEC
      IF EIBRESP = 13 THEN
        SCR.MSG = SCR.MSG 'Error deleting:' KEY
      ELSE DO
        DELETED = DELETED + 1
      END
    END
  END

  /* IF any records were deleted then reload from the save file. */
  IF DELETED \= 0 THEN DO
    SCR.MSG = SCR.MSG 'Deleted' DELETED 'saves.'
    SCR.RELOAD = 'YES'
  END
  RETURN

SAVES_IMPORT: PROCEDURE EXPOSE SCR.
  PARSE ARG SAVE_FILE IMPORT_FILE
  COUNT = 0
  DO FOREVER
    EXEC CICS READQ TD QUEUE(IMPORT_FILE) INTO(INPUT) END-EXEC
    IF EIBRESP \= 0 THEN LEAVE
    PARSE VAR INPUT KEY '|' MITER '|' CHARS '|' CREAL '|' CIMAG '|' ZOOM '|' SCALE '|' NOTE
    REC = STRIP(MITER) || '|' || STRIP(CHARS) || '|' || STRIP(CREAL) || '|' || STRIP(CIMAG) || '|' || STRIP(ZOOM) || '|' || STRIP(SCALE) || '|' || STRIP(NOTE)
    EXEC CICS WRITE FILE(SAVE_FILE) FROM(REC) RIDFLD(KEY) END-EXEC
    IF EIBRESP = 0 THEN COUNT = COUNT + 1
  END

  SCR.MSG = 'Imported Mandelbrot saves:' COUNT
  IF COUNT \= 0 THEN
    SCR.RELOAD = 'YES'
  RETURN

SAVES_EXPORT: PROCEDURE EXPOSE SCR.
  PARSE ARG SAVE_FILE EXPORT_FILE

  /* Delete the export file incase it exists. */
  EXEC CICS DELETEQ TD QUEUE(EXPORT_FILE) END-EXEC

  /* Start reading the saves. */
  EXEC CICS STARTBR FILE(SAVE_FILE) END-EXEC

  /* Loop over all saved settings and write to temporary storage. */
  COUNT = 0
  DO FOREVER
    EXEC CICS READNEXT FILE(SAVE_FILE) INTO(REC) RIDFLD(KEY) END-EXEC
    IF EIBRESP \= 0 THEN LEAVE
    OUTPUT = KEY || '|' || REC
    EXEC CICS WRITEQ TD QUEUE(EXPORT_FILE) FROM(OUTPUT) END-EXEC
    COUNT = COUNT + 1
  END
  EXEC CICS ENDBR FILE(SAVE_FILE) END-EXEC

  SCR.MSG = 'Exported Mandelbrot saves:' COUNT
  RETURN
