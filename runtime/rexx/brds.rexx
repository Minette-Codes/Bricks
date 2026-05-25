/* BRDS - Brows KSDS file records. */

/* Copied from 'cons.rexx'. */

ADDRESS CICS

EXEC CICS ASSIGN TERMID(TRM) END-EXEC

DO FOREVER
  IF FNM  = 'FNM'  THEN FNM  = ''       /* unset -> NOVALUE returns 'FNM' */
  IF LKEY = 'LKEY' THEN LKEY = ''
  IF LREC = 'LREC' THEN LREC = ''
  IF SKEY = 'SKEY' THEN SKEY = ''

  SCR. = ''
  SCR.TERMID   = TRM
  SCR.FNAME    = FNM
  SCR.LASTKEY  = LKEY
  SCR.LASTREC  = LREC
  SCR.STARTKEY = SKEY

  EXEC CICS CONVERSE MAP('BRDS1') FROM(SCR.) INTO(MAP) ERASE END-EXEC
  SCR.MSG = ''

  AID = C2X(EIBAID)
  SELECT
    WHEN AID = 'F3' THEN DO
      EXEC CICS RETURN END-EXEC
    END
    WHEN AID = 'F5' & FNM \= '' THEN DO
      CALL CURSORRESET TYPED SKEY
    END
    WHEN AID = 'F7' THEN DO
      DIR = 'BACK'
    END
    OTHERWISE NOP
  END

  /* Get the start key. */
  /* If the start key changes while the cursor is open close the cursor. */
  TYPED = STRIP(MAP.STARTKEY)
  IF SKEY \= TYPED & FNM \= '' THEN DO
    CALL CURSORCLOSE FNM
    FNM = ''
  END
  SKEY = TYPED

  /* Get the file name, and handle if the file name changed. */
  TYPED = STRIP(MAP.FNAME)
  IF TYPED \= '' & TYPED \= 'TYPED' THEN DO
    IF FNM = '' THEN DO
      CALL CURSOROPEN TYPED SKEY
    END
    ELSE IF FNM \= TYPED THEN DO
      CALL CURSORCLOSE FNM
      CALL CURSOROPEN TYPED SKEY
    END
    FNM = TYPED
  END
  ELSE DO
    SCR.MSG = 'Type a file name and press ENTER. PF3 exits.'
    FNM = ''
  END
  IF FNM = '' THEN ITERATE

  /* Default ENTER: consume the next item via the cursor.    */
  IF DIR = 'BACK' THEN DO
    EXEC CICS READPREV FILE(FNM) INTO(REC) RIDFLD(LKEY) END-EXEC
    DROP DIR
  END
  ELSE
    EXEC CICS READNEXT FILE(FNM) INTO(REC) RIDFLD(LKEY) END-EXEC

  SELECT
    WHEN EIBRESP = 0 THEN DO
      LREC = LEFT(REC, 60)
    END
    WHEN EIBRESP = 20 THEN DO        /* ENDFILE -- Past the last key. */
      LKEY = '(end)'
      LREC = ''
      SCR.MSG = 'Last record read.'
    END
    WHEN EIBRESP = 17 THEN DO        /* IOERR -- Underlying store error. */
      LKEY = '(ioerr)'
      LREC = ''
      SCR.MSG = 'IO ERROR.'
    END
    OTHERWISE NOP
  END
END

EXIT

CURSOROPEN: PROCEDURE
  PARSE ARG FILE KEY
  EXEC CICS STARTBR FILE(FILE) RIDFLD(KEY) END-EXEC
  RETURN

CURSORCLOSE: PROCEDURE
  PARSE ARG FILE
  EXEC CICS ENDBR FILE(FILE) END-EXEC
  RETURN

CURSORRESET: PROCEDURE
  PARSE ARG FILE KEY
  EXEC CICS RESETBR FILE(FILE) RIDFLD(KEY) END-EXEC
  RETURN
