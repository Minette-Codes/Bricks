/* ESPF - Edit the Fake SPF menu. It's just a menu... */

/* Feedback welcome! <3 */
/* MinetteCodes AT outlook DOT com */

ADDRESS CICS

/* Allow MAPFAIL to be handled inline. */ 
EXEC CICS IGNORE CONDITION MAPFAIL END-EXEC

/* Initialize variables. */
FRAME.        = ''    /* Frames from the database. */
LINK.FILEKEY. = ''    /* The KEY for this row. Blank if not from the file. */
LINK.FILEREC. = ''    /* The record for this row. Blank if not from the file. */
FRAME.COUNT   = 0     /* The number of records loaded from the file. */

LINK.         = ''    /* Links read from the file. */
                      /* Index by the index # assigned as the rows are read. */
LINK.FILEKEY. = ''    /* The KEY for this row. */
LINK.FILEREC. = ''    /* The record for this row. */
LINK.FILTER.  = ''    /* For filtering based on Frame. */
LINK.COUNT    = 0     /* The number of records loaded from the file. */

SCR.          = ''    /* Screen interface. */

SET.          = ''    /* Settings. To make it easier to access in procedures. */
SET.DATAFILE  = 'FSPFDATA'
SET.FILTER    = ''    /* Filter the Link list to a given Frame. */
SET.MODE      = 'LINK'/* LINK = Editing links. FRAME = Editing Frames. */
SET.PAGES     = 0     /* The number of pages if more than one screen of data. */
SET.PAGE      = 1     /* The current page. */

/* Setup the terminal. */
SET.MAPSET     = ''      /* The map set to show the user. */
SET.MAPSETBASE = 'FSPF1'  /* Default map set for Model 2. */
CALL TERMINAL_SETUP

/* Load the data from SET.DATAFILE. */
CALL DATA_LOAD
CALL LINK_FILL_SCR

/* Start the main loop. */
DO FOREVER
  SKIP    = 'NO' /* Skip processing input and potentially reloading SCR. */
  REPARSE = 'NO' /* Force reloading of SCR. */

  IF SET.MODE = 'LINK' THEN
    MAP_NAME = 'EDITLINK'
  ELSE
    MAP_NAME = 'EDITFRAME'
  EXEC CICS CONVERSE MAP(MAP_NAME) MAPSET(SET.MAPSET) FROM(SCR.) INTO(SCR.) ERASE END-EXEC
  /* Make sure the map is found. */
  IF EIBRESP = 36 THEN DO
    /* Avoid infinite loops. Yes, I've done that... */
    IF SET.MAPSET = SET.MAPSETBASE THEN do
      ERROR = 'ERROR: Could not find the Map Set:' SET.MAPSETBASE
      EXEC CICS SEND TEXT FROM(ERROR) END-EXEC
      EXEC CICS RETURN END-EXEC
    END

    /* Fallback to Model 2. */
    SET.MODEL = 2
    SET.PERPAGE = 16
    SET.MAPSET = SET.MAPSETBASE
    EXEC CICS CONVERSE MAP(SET.MAP) FROM(SCR.) INTO(MAP) ERASE END-EXEC
  END

  SCR.MSG = ''
  SCR.MSGALT = ''

  /* Handle the AID keys. */
  AID = C2X(EIBAID)
  SELECT
    /* Help. */
    WHEN AID = 'F1' THEN DO
      IF SET.MODE = 'LINK' THEN DO
        IF SET.MODEL = 4 THEN
          EXEC CICS SEND MAP('EDITLINKHELP') MAPSET(SET.MAPSET) ERASE END-EXEC
        ELSE DO
          EXEC CICS SEND MAP('EDITLINKHELP1') MAPSET(SET.MAPSET) ERASE END-EXEC
          EXEC CICS SEND MAP('EDITLINKHELP2') MAPSET(SET.MAPSET) ERASE END-EXEC
        END
      END
      ELSE DO
        IF SET.MODEL = 4 THEN
          EXEC CICS SEND MAP('EDITFRAMEHELP') MAPSET(SET.MAPSET) ERASE END-EXEC
        ELSE DO
          EXEC CICS SEND MAP('EDITFRAMEHELP1') MAPSET(SET.MAPSET) ERASE END-EXEC
          EXEC CICS SEND MAP('EDITFRAMEHELP2') MAPSET(SET.MAPSET) ERASE END-EXEC
        END
      END
    END
    /* Edit DFHCOMMAREA. (Only when editing Links.) */
    WHEN AID = 'F2' & SET.MODE = 'LINK' THEN DO
      CALL DFHCOMMAREA_EDIT
    END
    /* Exit. */
    WHEN AID = 'F3' THEN DO
      EXEC CICS RETURN END-EXEC
    END
    /* Switch modes. */
    WHEN AID = 'F4'  THEN DO
      IF SET.MODE = 'LINK' THEN DO
        SET.MODE = 'FRAME'
      END
      ELSE DO
        SET.MODE = 'LINK'
      END
      SET.PAGE = 1
      REPARSE = 'YES'
    END
    /* Reload. */
    WHEN AID = 'F5' | AID = '6D'  THEN DO /* PF5 or CLEAR */
      CALL DATA_LOAD
      REPARSE = 'YES'
    END
    /* Filter the Link list. (Only when editing Links.) */
    WHEN AID = 'F6' & SET.MODE = 'LINK' THEN DO
      CALL LINK_FILTER
      REPARSE = 'YES'
    END
    /* Page up. */
    WHEN AID = 'F7' THEN DO
      SET.PAGE = SET.PAGE - 1
      IF SET.PAGE <= 0 THEN
        SET.PAGE = 1
      REPARSE = 'YES'
    END
    /* Page down. */
    WHEN AID = 'F8' THEN DO
      SET.PAGE = SET.PAGE + 1
      IF SET.PAGE > SET.PAGES THEN
        SET.PAGE = SET.PAGES
      REPARSE = 'YES'
    END 
    /* Import. */
    WHEN AID = 'F9' THEN DO
      CALL DATA_IMPORT
      CALL DATA_LOAD
      REPARSE = 'YES'
    END 
    /* Export. */
    WHEN AID = '7A' THEN DO /* PF10 */
      CALL DATA_EXPORT
    END 
    /* Debug information */
    WHEN AID = 'C1' THEN DO /* PF13 */
      CALL DEBUG_CONSOLE SET.MAPSET
      SKIP = 'YES'
    END
    OTHERWISE NOP
  END

  IF SKIP = 'YES' THEN
    ITERATE

  /* Process the input only on ENTER. */
  IF AID = '7D' THEN
    IF SET.MODE = 'LINK' THEN
      CALL LINK_PROCESS_INPUT
    ELSE
      CALL FRAME_PROCESS_INPUT

  /* Reload SCR with a new page. */
  IF REPARSE = 'YES' THEN
    IF SET.MODE = 'LINK' THEN
      CALL LINK_FILL_SCR
    ELSE
      CALL FRAME_FILL_SCR
END
EXIT

/*\ ----~~~~====####    Load data.    ####====~~~~---- \*/

DATA_LOAD: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  /* Clear any old data. */
  DO TAIL OVER FRAME.
    INTERPRET 'DROP FRAME.' || TAIL
  END
  DO TAIL OVER LINK.
    INTERPRET 'DROP LINK.' || TAIL
  END
  DO TAIL OVER SCR.
    INTERPRET 'DROP SCR.' || TAIL
  END

  CALL CURSOR_OPEN SET.DATAFILE
  FRAMEINDX = 1
  LINKINDX  = 1

  DO FOREVER
    EXEC CICS READNEXT FILE(SET.DATAFILE) INTO(REC) RIDFLD(KEY) END-EXEC
    IF EIBRESP \= 0 THEN
      LEAVE

    IF SUBSTR(KEY, 1, 5) = 'FRAME' THEN DO
      FRAME.FILEKEY.FRAMEINDX = KEY
      FRAME.FILEREC.FRAMEINDX = REC
      FRAMEINDX = FRAMEINDX + 1
    END
    ELSE IF SUBSTR(KEY, 1, 4) = 'LINK' THEN DO
      LINK.FILEKEY.LINKINDX = KEY
      LINK.FILEREC.LINKINDX = REC

      /* For filtering. */
      PARSE VAR KEY 'LINK-' ROW_FRAME '-' ROW_ORDER '-' ROW_ID
      IF LINK.FILTER.ROW_FRAME = '' THEN
        LINK.FILTER.ROW_FRAME = 1
      ELSE
        LINK.FILTER.ROW_FRAME = LINK.FILTER.ROW_FRAME + 1
      FILTERINDX = LINK.FILTER.ROW_FRAME
      LINK.FILTER.ROW_FRAME.FILTERINDX = LINKINDX

      LINKINDX = LINKINDX + 1
    END
  END

  FRAME.COUNT = FRAMEINDX - 1
  LINK.COUNT = LINKINDX - 1
  CALL CURSOR_CLOSE SET.DATAFILE
  RETURN

/*\ ----~~~~====####    Link specific procedures.    ####====~~~~---- \*/

/* Loop over each row from the map and figure out what to do with it. */
LINK_PROCESS_INPUT: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  RELOAD = 'NO'   /* If data changes this is set to YES. */
  MISSING = 0     /* Count of fields that are missing. Prevents reload. */
  DELETED = 0     /* Count of records that were deleted. */
  SAVED   = 0     /* Count of records that were saved. */

  DO ROW = 1 TO SET.PERPAGE
    SKIP = 'NO'
    /* Get the data from the row. */
    ROW_ACTN    = VALUE('SCR.ACTN' || ROW)
    ROW_ID      = UPPER(VALUE('SCR.ID' || ROW))
    ROW_IDC     = VALUE('SCR.IDC' || ROW)
    ROW_ORDER   = VALUE('SCR.ORDER' || ROW)
    ROW_FRAME   = UPPER(VALUE('SCR.FRAME' || ROW))
    ROW_SUBM    = UPPER(VALUE('SCR.SUBM' || ROW))
    ROW_TRANS   = UPPER(VALUE('SCR.TRANS' || ROW))
    ROW_TRANSC  = VALUE('SCR.TRANSC' || ROW)
    ROW_DESCR   = VALUE('SCR.DESCR' || ROW)
    ROW_DESCRC  = VALUE('SCR.DESCRC' || ROW)
    ROW_KEY     = VALUE('SCR.RKEY' || ROW)
    ROW_COMM    = VALUE('SCR.COMM' || ROW)
    ROW_INDX    = VALUE('SCR.SCR_ROW' || ROW)

    CALL VALUE 'SCR.ACTN' || ROW, ''
    IF ROW_SUBM \= 'Y' THEN
      ROW_SUBM = ''

    /* Has the row been purged? */
    IF ROW_KEY \= '' & UPPER(ROW_ACTN) = 'P' THEN DO
      IF ROW_ACTN \= 'P' THEN
        SCR.MSG = SCR.MSG 'To delete a record use uppercase "P".'
      ELSE DO
        CALL RECORD_DELETE SET.DATAFILE, ROW_KEY
        RELOAD = 'YES'
        DELETED = DELETED + 1
      END
      SKIP = 'YES'
    END
    IF SKIP = 'YES' THEN
      ITERATE

    /* Set the colors. */
    CALL COLOR_SET_ROW ROW

    /* Is there data? */
    IF  ROW_ID     = '' &,
        ROW_IDC    = '' &,
        ROW_ORDER  = '' &,
        ROW_FRAME  = '' &,
        ROW_SUBM   = '' &,
        ROW_TRANS  = '' &,
        ROW_TRANSC = '' &,
        ROW_DESCR  = '' &,
        ROW_DESCRC = '' THEN
      ITERATE

    /* Validate some fields. */
    IF ROW_ORDER = '' THEN DO
      CALL VALUE 'SCR.ORDER' || ROW || '_C', 'RED'   
      SKIP = 'YES'
      MISSING = MISSING + 1
    END
    IF ROW_FRAME = '' THEN DO
      CALL VALUE 'SCR.FRAME' || ROW || '_C', 'RED'   
      SKIP = 'YES'
      MISSING = MISSING + 1
    END
    IF SKIP = 'YES' THEN
      ITERATE
    
    /* Prepare to write the record to the DB. */
    KEY = 'LINK-' || ROW_FRAME || '-' || ROW_ORDER || '-' || ROW_ID
    REC = ROW_ID     || '~' ||,
          ROW_IDC    || '~' ||,
          ROW_ORDER  || '~' ||,
          ROW_FRAME  || '~' ||,
          ROW_SUBM   || '~' ||,
          ROW_TRANS  || '~' ||,
          ROW_TRANSC || '~' ||,
          ROW_DESCR  || '~' ||,
          ROW_DESCRC || '~' ||,
          ROW_COMM

    /* An action of D means duplicate the record. */
    IF UPPER(ROW_ACTN) = 'D' THEN DO
      /* Check if the record already exists. */
      IF RECORD_CHECK(SET.DATAFILE, KEY) = 0 THEN DO
        SCR.MSG = SCR.MSG 'Duplicate entry:' ROW_ID ROW_ORDER FRAME
        CALL COLOR_HIGHLIGHT_ROW ROW, 'RED'
      END
      ELSE DO
        CALL RECORD_WRITE SET.DATAFILE, KEY, REC
        RELOAD = 'YES'
        SAVED = SAVED + 1
      END
    END
    ELSE DO
      /* If the record is new or changed write it to the file. */
      CHECK_REC = LINK.FILEREC.ROW_INDX
      IF CHECK_REC \= REC | ROW_KEY \= '' & KEY \= ROW_KEY THEN DO
        IF ROW_KEY \= '' THEN
          CALL RECORD_DELETE SET.DATAFILE, ROW_KEY
        CALL RECORD_WRITE SET.DATAFILE, KEY, REC
        RELOAD = 'YES'
        SAVED = SAVED + 1
      END
    END
  END

  IF MISSING > 0 THEN DO
    RELOAD = 'NO'
    NEW_MSG = MISSING 'field'
    IF MISSING > 1 THEN
    NEW_MSG = NEW_MSG || 's'
    SCR.MSG = NEW_MSG 'with missing data highlighted.' SCR.MSG
  END

  IF DELETED > 0 THEN DO
    SCR.MSG = SCR.MSG DELETED 'record'
    IF DELETED > 1 THEN
      SCR.MSG = SCR.MSG || 's'
    SCR.MSG = SCR.MSG 'have been deleted.'
  END

  IF SAVED > 0 THEN DO
    SCR.MSGALT = SCR.MSGALT SAVED 'record'
    IF SAVED > 1 THEN
      SCR.MSGALT = SCR.MSGALT || 's'
    SCR.MSGALT = SCR.MSGALT 'have been saved.'
  END

  /* If anything changed reload everything. */
  IF RELOAD = 'YES' THEN DO
    CALL DATA_LOAD
    CALL LINK_FILL_SCR
  END
  RETURN

/* Transfer from LINK. into SCR. based on the current page. */
LINK_FILL_SCR: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  START = (SET.PAGE - 1) * SET.PERPAGE + 1

  /* Filter changes the row count and routes through FILTER. */
  IF SET.FILTER \= '' THEN DO
    FILTER_FRAME = SET.FILTER
    ROW_COUNT = LINK.FILTER.FILTER_FRAME

    IF ROW_COUNT = '' THEN DO
      /* The Frame doesn't exist, yet. */
      FILTER_FRAME = ''
      ROW_COUNT = 0
    END
  END
  ELSE DO
    FILTER_FRAME = ''
    ROW_COUNT = LINK.COUNT
  END

  /* Fill SCR. with data. */
  DO SCR_ROW = 1 TO SET.PERPAGE
    ROW_INDX = START + SCR_ROW - 1


    IF ROW_INDX <= ROW_COUNT THEN DO
      IF SET.FILTER \= '' THEN
        ROW_INDX = LINK.FILTER.FILTER_FRAME.ROW_INDX
      REC = LINK.FILEREC.ROW_INDX
      PARSE VAR REC,
        ROW_ID     '~',
        ROW_IDC    '~',
        ROW_ORDER  '~',
        ROW_FRAME  '~',
        ROW_SUBM   '~',
        ROW_TRANS  '~',
        ROW_TRANSC '~',
        ROW_DESCR  '~',
        ROW_DESCRC '~',
        ROW_COMM
      
      IF ROW_COMM \= '' THEN
        ROW_COMM_FLAG = 'C'
      ELSE
        ROW_COMM_FLAG = '-'

      CALL VALUE 'SCR.ID'      || SCR_ROW, ROW_ID    
      CALL VALUE 'SCR.IDC'     || SCR_ROW, ROW_IDC   
      CALL VALUE 'SCR.ORDER'   || SCR_ROW, ROW_ORDER 
      CALL VALUE 'SCR.FRAME'   || SCR_ROW, ROW_FRAME 
      CALL VALUE 'SCR.SUBM'    || SCR_ROW, ROW_SUBM  
      CALL VALUE 'SCR.TRANS'   || SCR_ROW, ROW_TRANS 
      CALL VALUE 'SCR.TRANSC'  || SCR_ROW, ROW_TRANSC
      CALL VALUE 'SCR.DESCR'   || SCR_ROW, ROW_DESCR 
      CALL VALUE 'SCR.DESCRC'  || SCR_ROW, ROW_DESCRC
      CALL VALUE 'SCR.RKEY'    || SCR_ROW, LINK.FILEKEY.ROW_INDX  
      CALL VALUE 'SCR.COMM'    || SCR_ROW, ROW_COMM
      CALL VALUE 'SCR.COMMF'   || SCR_ROW, ROW_COMM_FLAG
      CALL VALUE 'SCR.SCR_ROW' || SCR_ROW, ROW_INDX

      CALL COLOR_SET_ROW SCR_ROW
    END
    ELSE DO
      CALL VALUE 'SCR.ID'      || SCR_ROW, ''
      CALL VALUE 'SCR.IDC'     || SCR_ROW, ''
      CALL VALUE 'SCR.ORDER'   || SCR_ROW, ''
      CALL VALUE 'SCR.FRAME'   || SCR_ROW, ''
      CALL VALUE 'SCR.SUBM'    || SCR_ROW, ''
      CALL VALUE 'SCR.TRANS'   || SCR_ROW, ''
      CALL VALUE 'SCR.TRANSC'  || SCR_ROW, ''
      CALL VALUE 'SCR.DESCR'   || SCR_ROW, ''
      CALL VALUE 'SCR.DESCRC'  || SCR_ROW, ''
      CALL VALUE 'SCR.RKEY'    || SCR_ROW, ''
      CALL VALUE 'SCR.COMM'    || SCR_ROW, ''  
      CALL VALUE 'SCR.COMMF'   || SCR_ROW, ''  
      CALL VALUE 'SCR.SCR_ROW' || SCR_ROW, ''

      CALL COLOR_HIGHLIGHT_ROW SCR_ROW, 'DEFAULT'
    END
  END

  SET.PAGES = (ROW_COUNT + SET.PERPAGE - 1) % SET.PERPAGE
  /* Make sure there is always a page for data entry. */
  IF (SET.PAGES * SET.PERPAGE) < (ROW_COUNT + 10) THEN
    SET.PAGES = SET.PAGES + 1
  IF SET.PAGE > SET.PAGES THEN
    SET.PAGE = SET.PAGES

  IF SET.FILTER \= '' THEN
    SCR.FLTRNOTE = RIGHT('Filter:' SET.FILTER, 30)
  ELSE
    SCR.FLTRNOTE = ''

  SCR.PAGENOTE = 'Rows:' ROW_COUNT
  IF ROW_COUNT > 1 & SET.PAGES > 1 THEN
    SCR.PAGENOTE = SCR.PAGENOTE 'Page:' SET.PAGE 'of' SET.PAGES
  SCR.PAGENOTE = RIGHT(SCR.PAGENOTE, 30)
  RETURN

/* Edit the DFHCOMMAREA value for a Link. */
DFHCOMMAREA_EDIT: PROCEDURE EXPOSE EIBCPOSN SCR. SET.
  /* Figure out which row they were on. */
  ROW = INT(EIBCPOSN / SET.WIDTH) - 2
  IF ROW < 1 | ROW > SET.PERPAGE THEN
    RETURN

  ROW_ID      = VALUE('SCR.ID'    || ROW)
  ROW_ORDER   = VALUE('SCR.ORDER' || ROW)
  ROW_FRAME   = VALUE('SCR.FRAME' || ROW)
  NOTE = 'ID:' LEFT(ROW_ID, 2) ' Order:' LEFT(ROW_ORDER, 4) ' Frame:' LEFT(ROW_FRAME, 4)

  POPSCR. = ''
  POPSCR.POPINPUT   = VALUE('SCR.COMM'  || ROW)
  POPSCR.POPMSG     = CENTER('Enter the value for DFHCOMMAREA:', 34)
  POPSCR.POPNOTE    = CENTER(NOTE, 34)
  POPSCR.POPNOTE_C  = ''
  POPSCR.POPAID     = 'Save'
  EXEC CICS CONVERSE MAP('EDITPOPUP') MAPSET(SET.MAPSET) FROM(POPSCR.) INTO(POPSCR.) ERASE END-EXEC

  /* Only save on ENTER. */
  IF C2X(EIBAID) \= '7D' THEN
    RETURN
  
  IF ROW_COMM = POPSCR.POPINPUT THEN
    /* Nothing changed. */
    RETURN
  ELSE
    SCR.MSGALT = 'Press ENTER to commit changes.'
  ROW_COMM = POPSCR.POPINPUT

  /* Update the screen. */
  IF ROW_COMM \= '' THEN
    ROW_COMM_FLAG = 'C'
  ELSE
    ROW_COMM_FLAG = '-'
  CALL VALUE 'SCR.COMM'   || ROW, ROW_COMM
  CALL VALUE 'SCR.COMMF'  || ROW, ROW_COMM_FLAG
  RETURN

LINK_FILTER: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  POPSCR. = ''
  POPSCR.POPINPUT   = ''
  POPSCR.POPMSG     = CENTER('Filter the list to Frame:', 34)
  POPSCR.POPNOTE    = CENTER('(Leave blank to clear.)', 34)
  POPSCR.POPNOTE_C  = ''
  POPSCR.POPAID     = 'FILTER'
  EXEC CICS CONVERSE MAP('EDITPOPUP') MAPSET(SET.MAPSET) FROM(POPSCR.) INTO(POPSCR.) ERASE END-EXEC

  /* Only set on ENTER. */
  IF C2X(EIBAID) \= '7D' THEN
    RETURN

  SET.FILTER = UPPER(POPSCR.POPINPUT)
  SET.PAGE = 1
  RETURN

/*\ ----~~~~====####    Frame specific procedures.    ####====~~~~---- \*/

/* Loop over each row from the map and figure out what to do with it. */
FRAME_PROCESS_INPUT: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  RELOAD = 'NO'   /* If data changes this is set to YES. */
  MISSING = 0     /* Count of fields that are missing. Prevents reload. */
  DELETED = 0     /* Count of records that were deleted. */
  SAVED   = 0     /* Count of records that were saved. */

  DO ROW = 1 TO SET.PERPAGE
    SKIP = 'NO'
    /* Get the data from the row. */
    FRAME_ACTN    = VALUE('SCR.ACTN' || ROW)
    FRAME_ID      = UPPER(VALUE('SCR.ID' || ROW))
    FRAME_IDC     = VALUE('SCR.IDC' || ROW)
    FRAME_ORDER   = VALUE('SCR.ORDER' || ROW)
    FRAME_NAME    = UPPER(VALUE('SCR.NAME' || ROW))
    FRAME_DESCR   = VALUE('SCR.DESCR' || ROW)
    FRAME_DESCRC  = VALUE('SCR.DESCRC'|| ROW)
    FRAME_WELCOM  = VALUE('SCR.WELCOM' || ROW)
    FRAME_WELCOMC = VALUE('SCR.WELCOMC'|| ROW)
    FRAME_KEY     = VALUE('SCR.RKEY' || ROW)
    FRAME_INDX    = VALUE('SCR.SCR_ROW' || ROW)

    CALL VALUE 'SCR.ACTN' || ROW, ''

    /* Has the row been purged? */
    IF FRAME_KEY \= '' & UPPER(FRAME_ACTN) = 'P' THEN DO
      IF FRAME_ACTN \= 'P' THEN
        SCR.MSG = SCR.MSG 'To delete a record use uppercase "P".'
      ELSE DO
        CALL RECORD_DELETE SET.DATAFILE, FRAME_KEY
        RELOAD = 'YES'
        DELETED = DELETED + 1
      END
      SKIP = 'YES'
    END
    IF SKIP = 'YES' THEN
      ITERATE

    /* Set the colors. */
    CALL COLOR_SET_ROW ROW

    /* Is there data? */
    IF  FRAME_ID      = '' &,
        FRAME_IDC     = '' &,
        FRAME_ORDER   = '' &,
        FRAME_NAME    = '' &,
        FRAME_DESCR   = '' &,
        FRAME_DESCRC  = '' &,
        FRAME_WELCOM  = '' &,
        FRAME_WELCOMC = '' THEN
      ITERATE

    /* Validate some fields. */
    IF FRAME_NAME = '' THEN DO
      CALL VALUE 'SCR.NAME' || ROW || '_C', 'RED'   
      SKIP = 'YES'
      MISSING = MISSING + 1
    END
    IF SKIP = 'YES' THEN
      ITERATE
    
    /* Prepare to write the record to the DB. */
    KEY = 'FRAME-' || FRAME_ORDER || '-' || FRAME_ID
    REC = FRAME_ID      || '~' ||,
          FRAME_IDC     || '~' ||,
          FRAME_ORDER   || '~' ||,
          FRAME_NAME    || '~' ||,
          FRAME_DESCR   || '~' ||,
          FRAME_DESCRC  || '~' ||,
          FRAME_WELCOM  || '~' ||,
          FRAME_WELCOMC

    /* An action of D means duplicate the record. */
    IF UPPER(FRAME_ACTN) = 'D' THEN DO
      /* Check if the record already exists. */
      IF RECORD_CHECK(SET.DATAFILE, KEY) = 0 THEN DO
        SCR.MSG = SCR.MSG 'Duplicate entry:' FRAME_ID FRAME_ORDER
        CALL COLOR_HIGHLIGHT_ROW ROW, 'RED'
      END
      ELSE DO
        CALL RECORD_WRITE SET.DATAFILE, KEY, REC
        RELOAD = 'YES'
        SAVED = SAVED + 1
      END
    END
    ELSE DO
      /* If the record is new or changed write it to the file. */
      CHECK_REC = FRAME.FILEREC.FRAME_INDX
      IF CHECK_REC \= REC | FRAME_KEY \= '' & KEY \= FRAME_KEY THEN DO
        IF FRAME_KEY \= '' THEN
          CALL RECORD_DELETE SET.DATAFILE, FRAME_KEY
        CALL RECORD_WRITE SET.DATAFILE, KEY, REC
        RELOAD = 'YES'
        SAVED = SAVED + 1
      END
    END
  END

  IF MISSING > 0 THEN DO
    RELOAD = 'NO'
    NEW_MSG = MISSING 'field'
    IF MISSING > 1 THEN
    NEW_MSG = NEW_MSG || 's'
    SCR.MSG = NEW_MSG 'with missing data highlighted.' SCR.MSG
  END

  IF DELETED > 0 THEN DO
    SCR.MSG = SCR.MSG DELETED 'record'
    IF DELETED > 1 THEN
      SCR.MSG = SCR.MSG || 's'
    SCR.MSG = SCR.MSG 'have been deleted.'
  END

  IF SAVED > 0 THEN DO
    SCR.MSGALT = SCR.MSGALT SAVED 'record'
    IF SAVED > 1 THEN
      SCR.MSGALT = SCR.MSGALT || 's'
    SCR.MSGALT = SCR.MSGALT 'have been saved.'
  END

  /* If anything changed reload everything. */
  IF RELOAD = 'YES' THEN DO
    CALL DATA_LOAD
    CALL FRAME_FILL_SCR
  END
  RETURN

/* Transfer from FRAME. into SCR. based on the current page. */
FRAME_FILL_SCR: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  START = (SET.PAGE - 1) * SET.PERPAGE + 1
  DO SCR_ROW = 1 TO SET.PERPAGE
    FRAME_INDX = START + SCR_ROW - 1
    IF FRAME_INDX <= FRAME.COUNT THEN DO
      REC = FRAME.FILEREC.FRAME_INDX
      PARSE VAR REC,
        FRAME_ID     '~',
        FRAME_IDC    '~',
        FRAME_ORDER  '~',
        FRAME_NAME   '~',
        FRAME_DESCR  '~',
        FRAME_DESCRC  '~',
        FRAME_WELCOM  '~',
        FRAME_WELCOMC

      CALL VALUE 'SCR.ID'      || SCR_ROW, FRAME_ID    
      CALL VALUE 'SCR.IDC'     || SCR_ROW, FRAME_IDC   
      CALL VALUE 'SCR.ORDER'   || SCR_ROW, FRAME_ORDER 
      CALL VALUE 'SCR.NAME'    || SCR_ROW, FRAME_NAME  
      CALL VALUE 'SCR.DESCR'   || SCR_ROW, FRAME_DESCR 
      CALL VALUE 'SCR.DESCRC'  || SCR_ROW, FRAME_DESCRC
      CALL VALUE 'SCR.WELCOM'  || SCR_ROW, FRAME_WELCOM 
      CALL VALUE 'SCR.WELCOMC' || SCR_ROW, FRAME_WELCOMC
      CALL VALUE 'SCR.RKEY'    || SCR_ROW, FRAME.FILEKEY.FRAME_INDX  
      CALL VALUE 'SCR.SCR_ROW' || SCR_ROW, FRAME_INDX

      CALL COLOR_SET_ROW SCR_ROW
    END
    ELSE DO
      CALL VALUE 'SCR.ID'      || SCR_ROW, ''
      CALL VALUE 'SCR.IDC'     || SCR_ROW, ''
      CALL VALUE 'SCR.ORDER'   || SCR_ROW, ''
      CALL VALUE 'SCR.NAME'    || SCR_ROW, ''
      CALL VALUE 'SCR.DESCR'   || SCR_ROW, ''
      CALL VALUE 'SCR.DESCRC'  || SCR_ROW, ''
      CALL VALUE 'SCR.WELCOM'  || SCR_ROW, ''
      CALL VALUE 'SCR.WELCOMC' || SCR_ROW, ''
      CALL VALUE 'SCR.RKEY'    || SCR_ROW, ''
      CALL VALUE 'SCR.SCR_ROW' || SCR_ROW, ''

      CALL COLOR_HIGHLIGHT_ROW SCR_ROW, 'GREEN'
    END
  END

  SET.PAGES = (FRAME.COUNT + SET.PERPAGE - 1) % SET.PERPAGE
  /* Make sure there is always a page for data entry. */
  IF (SET.PAGES * SET.PERPAGE) < (FRAME.COUNT + 5) THEN
    SET.PAGES = SET.PAGES + 1
  IF SET.PAGE > SET.PAGES THEN
    SET.PAGE = SET.PAGES

  SCR.PAGENOTE = 'Rows:' FRAME.COUNT
  IF FRAME.COUNT > 1 & SET.PAGES > 1 THEN
    SCR.PAGENOTE = SCR.PAGENOTE 'Page:' SET.PAGE 'of' SET.PAGES
  SCR.PAGENOTE = RIGHT(SCR.PAGENOTE, 30)
  RETURN

/*\ ----~~~~====####    KSDS Record interface    ####====~~~~---- \*/

RECORD_CHECK: PROCEDURE
  IF ARG() \= 2 THEN
    RETURN -1
  FILE = ARG(1)
  KEY  = ARG(2)
  EXEC CICS READ FILE(FILE) INTO(REC) RIDFLD(KEY) END-EXEC
  RETURN EIBRESP

RECORD_DELETE: PROCEDURE
  IF ARG() \= 2 THEN
    RETURN -1
  FILE = ARG(1)
  KEY  = ARG(2)
  EXEC CICS DELETE FILE(FILE) RIDFLD(KEY) END-EXEC
  RETURN EIBRESP

RECORD_READ: PROCEDURE
  IF ARG() \= 2 THEN
    RETURN -1
  FILE = ARG(1)
  KEY  = ARG(2)
  REC  = ''
  EXEC CICS READ FILE(FILE) INTO(REC) RIDFLD(KEY) END-EXEC
  RETURN EIBRESP REC

RECORD_WRITE: PROCEDURE
  IF ARG() \= 3 THEN
    RETURN -1
  FILE = ARG(1)
  KEY  = ARG(2)
  REC  = ARG(3)
  EXEC CICS WRITE FILE(FILE) FROM(REC) RIDFLD(KEY) END-EXEC
  RETURN EIBRESP

/* ----~~~~====####    KSDS Cursor interface    ####====~~~~---- */

CURSOR_OPEN: PROCEDURE
  IF ARG() = 0 THEN
    RETURN -1
  FILE = ARG(1)
  IF ARG() > 1 THEN
    KEY = ARG(2)
  ELSE 
    KEY = ''
  EXEC CICS STARTBR FILE(FILE) RIDFLD(KEY) END-EXEC
  RETURN EIBRESP

CURSOR_CLOSE: PROCEDURE
  IF ARG() = 0 THEN
    RETURN -1
  FILE = ARG(1)
  EXEC CICS ENDBR FILE(FILE) END-EXEC
  RETURN EIBRESP

CURSOR_RESET: PROCEDURE
  IF ARG() = 0 THEN
    RETURN -1
  FILE = ARG(1)
  IF ARG() > 1 THEN
    KEY = ARG(2)
  ELSE 
    KEY = ''
  EXEC CICS RESETBR FILE(FILE) RIDFLD(KEY) END-EXEC
  RETURN EIBRESP

/*\ ----~~~~====####    Working with color    ####====~~~~---- \*/

/* Convert a color letter into the full color name. */
COLOR_CONVERT: PROCEDURE
  IF ARG() = 0 THEN
    RETURN ''
  CODE = ARG(1)
  SELECT 
    WHEN UPPER(CODE) = 'B' THEN RETURN 'BLUE'
    WHEN UPPER(CODE) = 'C' THEN RETURN 'CYAN'
    WHEN UPPER(CODE) = 'R' THEN RETURN 'RED'
    WHEN UPPER(CODE) = 'P' THEN RETURN 'PINK'
    WHEN UPPER(CODE) = 'G' THEN RETURN 'GREEN'
    WHEN UPPER(CODE) = 'T' THEN RETURN 'TURQUOISE'
    WHEN UPPER(CODE) = 'Y' THEN RETURN 'YELLOW'
    WHEN UPPER(CODE) = 'W' THEN RETURN 'WHITE'
    OTHERWISE                   RETURN 'WHITE'
  END
  RETURN ''

/* Set the colors for a row in SCR. */
COLOR_SET_ROW: PROCEDURE EXPOSE SCR.
  PARSE ARG ROW

  COLOR = VALUE('SCR.IDC' || ROW)
  IF COLOR \= '' THEN DO
    COLOR = COLOR_CONVERT(COLOR)
    CALL VALUE 'SCR.ID'  || ROW || '_C', COLOR
    CALL VALUE 'SCR.IDC' || ROW || '_C', COLOR
  END
  ELSE DO
    CALL VALUE 'SCR.ID'  || ROW || '_C', ''
    CALL VALUE 'SCR.IDC' || ROW || '_C', ''
  END
  
  COLOR = VALUE('SCR.TRANSC' || ROW)
  IF COLOR \= '' THEN DO
    COLOR = COLOR_CONVERT(COLOR)
    CALL VALUE 'SCR.TRANS'  || ROW || '_C', COLOR
    CALL VALUE 'SCR.TRANSC' || ROW || '_C', COLOR
  END
  ELSE DO
    CALL VALUE 'SCR.TRANS'  || ROW || '_C', ''
    CALL VALUE 'SCR.TRANSC' || ROW || '_C', ''
  END

  COLOR = VALUE('SCR.DESCRC' || ROW)
  IF COLOR \= '' THEN DO
    COLOR = COLOR_CONVERT(COLOR)
    CALL VALUE 'SCR.DESCR'  || ROW || '_C', COLOR
    CALL VALUE 'SCR.DESCRC' || ROW || '_C', COLOR
  END
  ELSE DO
    CALL VALUE 'SCR.DESCR'  || ROW || '_C', ''
    CALL VALUE 'SCR.DESCRC' || ROW || '_C', ''
  END

  COLOR = VALUE('SCR.WELCOMC' || ROW)
  IF COLOR \= '' THEN DO
    COLOR = COLOR_CONVERT(COLOR)
    CALL VALUE 'SCR.WELCOM'  || ROW || '_C', COLOR
    CALL VALUE 'SCR.WELCOMC' || ROW || '_C', COLOR
  END
  ELSE DO
    CALL VALUE 'SCR.WELCOM'  || ROW || '_C', ''
    CALL VALUE 'SCR.WELCOMC' || ROW || '_C', ''
  END

  CALL VALUE 'SCR.ORDER' || ROW || '_C' , 'GREEN'
  CALL VALUE 'SCR.FRAME' || ROW || '_C' , 'CYAN'
  CALL VALUE 'SCR.SUBM'  || ROW || '_C' , 'CYAN'
  CALL VALUE 'SCR.NAME'  || ROW || '_C' , 'CYAN'
  RETURN

/* Highlight an entire row in SCR. */
COLOR_HIGHLIGHT_ROW: PROCEDURE EXPOSE SCR.
  IF ARG() \= 2 THEN
    RETURN -1
  ROW   = ARG(1)
  COLOR = ARG(2)

  IF COLOR = 'DEFAULT' THEN DO
    COLOR = 'GREEN'
    COLOR_FRAME = 'CYAN'
  END
  ELSE
    COLOR_FRAME = COLOR

  CALL VALUE 'SCR.ID'       || ROW || '_C', COLOR
  CALL VALUE 'SCR.IDC'      || ROW || '_C', COLOR
  CALL VALUE 'SCR.ORDER'    || ROW || '_C', COLOR
  CALL VALUE 'SCR.NAME'     || ROW || '_C', COLOR_FRAME
  CALL VALUE 'SCR.DESCR'    || ROW || '_C', COLOR
  CALL VALUE 'SCR.DESCRC'   || ROW || '_C', COLOR
  CALL VALUE 'SCR.WELCOM'   || ROW || '_C', COLOR
  CALL VALUE 'SCR.WELCOMC'  || ROW || '_C', COLOR
  CALL VALUE 'SCR.FRAME'    || ROW || '_C', COLOR_FRAME
  CALL VALUE 'SCR.SUBM'     || ROW || '_C', COLOR_FRAME
  CALL VALUE 'SCR.TRANS'    || ROW || '_C', COLOR
  CALL VALUE 'SCR.TRANSC'   || ROW || '_C', COLOR
  RETURN

/*\ ----~~~~====####    Import / Export    ####====~~~~---- \*/

DATA_EXPORT: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  POPSCR. = ''
  POPSCR.POPINPUT   = 'fspf_export.txt'
  POPSCR.POPMSG     = CENTER('File name to export to:', 32)
  POPSCR.POPNOTE    = CENTER('The file will be DELETED!', 32)
  POPSCR.POPNOTE_C  = 'RED'
  POPSCR.POPAID     = 'Export'
  EXEC CICS CONVERSE MAP('EDITPOPUP') MAPSET(SET.MAPSET) FROM(POPSCR.) INTO(POPSCR.) ERASE END-EXEC

  /* Only export on ENTER. */
  IF C2X(EIBAID) \= '7D' THEN
    RETURN

  /* Delete any existing export file. */
  EXPORTFILE = POPSCR.POPINPUT
  EXEC CICS DELETEQ TD QUEUE(EXPORTFILE) END-EXEC
  COUNT = 0

  /* Export the data. */
  CALL CURSOR_OPEN SET.DATAFILE
  COUNT = 0
  DO FOREVER
    EXEC CICS READNEXT FILE(SET.DATAFILE) INTO(REC) RIDFLD(KEY) END-EXEC
    IF EIBRESP \= 0 THEN
      LEAVE

    IF SUBSTR(KEY, 1, 5) = 'FRAME' THEN
      OUTPUT = 'FRAME-' || REC
    ELSE IF SUBSTR(KEY, 1, 4) = 'LINK' THEN
      OUTPUT = 'LINK-' || REC
    EXEC CICS WRITEQ TD QUEUE(EXPORTFILE) FROM(OUTPUT) END-EXEC
    COUNT = COUNT + 1
  END
  CALL CURSOR_CLOSE SET.DATAFILE
  SCR.MSGALT = COUNT 'records exported to the file' EXPORTFILE
  RETURN

DATA_IMPORT: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  POPSCR. = ''
  POPSCR.POPINPUT   = 'fspf_import.txt'
  POPSCR.POPMSG     = CENTER('File name to import from:', 34)
  POPSCR.POPNOTE    = CENTER('Existing records will be DELETED!!', 34)
  POPSCR.POPNOTE_C  = 'RED'
  POPSCR.POPAID     = 'Export'
  EXEC CICS CONVERSE MAP('EDITPOPUP') MAPSET(SET.MAPSET) FROM(POPSCR.) INTO(POPSCR.) ERASE END-EXEC

  /* Only export on ENTER. */
  IF C2X(EIBAID) \= '7D' THEN
    RETURN

  /* IMport the file. */
  IMPORTFILE = POPSCR.POPINPUT
  COUNT = 0
  DO FOREVER
    EXEC CICS READQ TD QUEUE(IMPORTFILE) INTO(INPUT) END-EXEC
    IF EIBRESP \= 0 THEN
      LEAVE
    
    /* Skip blank lines. */
    IF LENGTH(INPUT) = 0 THEN
      ITERATE

    /* Skip commented lines. */
    IF SUBSTR(INPUT, 1, 1) = '*' THEN
      ITERATE

    IF SUBSTR(INPUT, 1, 5) = 'FRAME' THEN DO
      /* Frame record. */
      PARSE VAR INPUT 'FRAME-',
        FRAME_ID     '~',
        FRAME_IDC    '~',
        FRAME_ORDER  '~',
        FRAME_NAME   '~',
        FRAME_DESCR  '~',
        FRAME_DESCRC  '~',
        FRAME_WELCOM  '~',
        FRAME_WELCOMC

      /* Prepare to write the record to the DB. */
      KEY = 'FRAME-' || FRAME_ORDER || '-' || FRAME_ID
      REC = FRAME_ID      || '~' ||,
            FRAME_IDC     || '~' ||,
            FRAME_ORDER   || '~' ||,
            FRAME_NAME    || '~' ||,
            FRAME_DESCR   || '~' ||,
            FRAME_DESCRC  || '~' ||,
            FRAME_WELCOM  || '~' ||,
            FRAME_WELCOMC
    END
    ELSE IF SUBSTR(INPUT, 1, 4) = 'LINK' THEN DO
      /* Link record. */
      PARSE VAR INPUT 'LINK-',
        ROW_ID     '~',
        ROW_IDC    '~',
        ROW_ORDER  '~',
        ROW_FRAME  '~',
        ROW_SUBM   '~',
        ROW_TRANS  '~',
        ROW_TRANSC '~',
        ROW_DESCR  '~',
        ROW_DESCRC '~',
        ROW_COMM

      /* Prepare to write the record to the DB. */
      KEY = 'LINK-' || ROW_FRAME || '-' || ROW_ORDER || '-' || ROW_ID
      REC = ROW_ID     || '~' ||,
            ROW_IDC    || '~' ||,
            ROW_ORDER  || '~' ||,
            ROW_FRAME  || '~' ||,
            ROW_SUBM   || '~' ||,
            ROW_TRANS  || '~' ||,
            ROW_TRANSC || '~' ||,
            ROW_DESCR  || '~' ||,
            ROW_DESCRC || '~' ||,
            ROW_COMM
    END
    
    /* Delete if exists then save. */
    IF RECORD_CHECK(SET.DATAFILE, KEY) = 0 THEN
      CALL RECORD_DELETE SET.DATAFILE, KEY
    CALL RECORD_WRITE SET.DATAFILE, KEY, REC
    COUNT = COUNT + 1
  END
  
  SCR.MSGALT = COUNT 'records imported from the file' EXPORTFILE
  RETURN

/*\ ----~~~~====####    Terminal Related    ####====~~~~---- \*/

TERMINAL_SETUP: PROCEDURE EXPOSE SET. SCR.
  EXEC CICS ASSIGN
    SCREENWD(SYSSCRW)
    SCREENHT(SYSSCRH)
  END-EXEC

  SET.WIDTH = SYSSCRW

  /* Model 2 - 24x80 */
  SET.MODEL     = 2     /* Terminal model # */
  SET.PERPAGE   = 16    /* Rows per page, adjusted for terminal model. */
  SET.SUFFIX    = ''    /* The suffix to affix the map set for larger screens. */

  IF SYSSCRH >= 43 THEN DO
    /* Model 4 - 43x80 */
    SET.MODEL     = 4
    SET.PERPAGE   = 35
    SET.SUFFIX    = 'L'
  END
  ELSE IF SYSSCRH >= 32 THEN DO
    /* Model 3 - 32x80 */
    SET.MODEL     = 3
    SET.PERPAGE   = 24
    SET.SUFFIX    = 'M'
  END
  ELSE IF SYSSCRH >= 27 & SYSSCRW = 132 THEN DO
    /* Model 5 - 27x132 */
    SET.MODEL     = 5
    SET.PERPAGE   = 16
    SET.SUFFIX    = 'W'
  END
  SET.MAPSET = SET.MAPSETBASE || SET.SUFFIX
  RETURN

/*\ ----~~~~====####    Debug Console!    ####====~~~~---- \*/

/* TODO: These are where you should make updates to use in your project. */
/* NOTE: This is rather crude, on purpose. Adapt it to your needs. */

/* Debug loop. */
/* TODO: Change the EXPOSE here to your global variables. */
DEBUG_CONSOLE: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  MAP_SET = ARG(1)

  /* Screen interface. */
  DEBUG_SCR. = ''
  DEBUG_SCR.CUR_PAGE = 1
  DEBUG_SCR.PAGE_CNT = 1
  DEBUG_SCR.FIND_TEXT = ''
  DEBUG_SCR.FIND_CNT = 0

  /* Hold the debug data and settings. */
  DEBUG_DATA. = ''
  DEBUG_DATA.0 = 0
  DEBUG_DATA.FOUND. = ''

  /* Terminal size. */
  EXEC CICS ASSIGN SCREENWD(SYSSCRW) SCREENHT(SYSSCRH) END-EXEC
  DEBUG_DATA.PER_PAGE = SYSSCRH - 4
  DEBUG_DATA.SCR_WIDTH = SYSSCRW - 1

  /* Load all of the debug data into an array. */
  CALL DEBUG_DATA_LOAD
  CALL DEBUG_FILL_SCR

  HELP_MSG = 'RELOAD / SET VARIABLE VALUE / DROP VARIABLE / FIND TEXT (Case insensitive.)'
  DO FOREVER
    DO_RELOAD = 'NO'
    EXEC CICS CONVERSE MAP('DEBUGCONSOLE') MAPSET(MAP_SET) FROM(DEBUG_SCR.) INTO(DEBUG_SCR.) ERASE END-EXEC
    DEBUG_SCR.MSG = ''
    USER_INPUT = STRIP(DEBUG_SCR.OPTION)
    DEBUG_SCR.OPTION = ''

    /* Handle the AID keys. */
    AID = C2X(EIBAID)
    SELECT
      /* Help */
      WHEN AID = 'F1' THEN DO
        DEBUG_SCR.MSG = HELP_MSG
      END
      /* Find text. */
      WHEN AID = 'F2' THEN DO
        IF USER_INPUT \= '' THEN
          DEBUG_SCR.FIND_TEXT = UPPER(USER_INPUT)
        IF DEBUG_SCR.FIND_TEXT \= '' THEN
          CALL DEBUG_FIND USER_INPUT, 'YES'
      END
      /* Back / Exit. */
      WHEN AID = 'F3' THEN DO
        RETURN
      END
      /* Reload */
      WHEN AID = 'F5' THEN DO
        DO_RELOAD = 'YES'
      END
      /* Back to the top. */
      WHEN AID = 'F6' THEN DO
        DEBUG_SCR.CUR_PAGE = 1
      END
      /* Page up. */
      WHEN AID = 'F7' THEN DO 
        DEBUG_SCR.CUR_PAGE = DEBUG_SCR.CUR_PAGE - 1
        IF DEBUG_SCR.CUR_PAGE <= 0 THEN
          DEBUG_SCR.CUR_PAGE = 1
        REPARSE = 'YES'
      END
      /* Page down. */
      WHEN AID = 'F8' THEN DO
        DEBUG_SCR.CUR_PAGE = DEBUG_SCR.CUR_PAGE + 1
        IF DEBUG_SCR.CUR_PAGE > DEBUG_SCR.PAGE_CNT THEN
          DEBUG_SCR.CUR_PAGE = DEBUG_SCR.PAGE_CNT
        REPARSE = 'YES'
      END 
      /* Down to the bottom.. */
      WHEN AID = 'F9' THEN DO
        DEBUG_SCR.CUR_PAGE = DEBUG_SCR.PAGE_CNT
      END
      OTHERWISE NOP
    END

    /* Do something with the user input. */
    IF USER_INPUT \= '' THEN DO
      PARSE VAR USER_INPUT COMMAND ARGS
      SELECT
        /* Jump to the bottom of data. */
        WHEN UPPER(COMMAND) = 'BOT' THEN DO
          DEBUG_SCR.CUR_PAGE = DEBUG_SCR.PAGE_CNT
        END
        /* Drop a variable. */
        WHEN UPPER(COMMAND) = 'DROP' THEN DO
          INTERPRET 'DROP ' || ARGS
        END
        /* Help text. */
        WHEN UPPER(COMMAND) = 'HELP' THEN DO
          DEBUG_SCR.MSG = HELP_MSG
        END
        /* Search for text. */
        WHEN UPPER(COMMAND) = 'FIND' THEN DO
          IF ARGS \= '' THEN
            DEBUG_SCR.FIND_TEXT = UPPER(ARGS)
          CALL DEBUG_FIND ARGS, 'YES'
        END
        /* Set a variable. */
        WHEN UPPER(COMMAND) = 'SET' THEN DO
          PARSE VAR ARGS VARIABLE VALUE
          CALL VALUE VARIABLE, VALUE
          DEBUG_SCR.MSG = VARIABLE '=' VALUE
        END
        /* Quit */
        WHEN UPPER(COMMAND) = 'QUIT' THEN DO
          RETURN
        END
        /* Search for text. */
        WHEN UPPER(COMMAND) = 'RELOAD' THEN DO
          DO_RELOAD = 'YES'
        END
        /* Jump to the top of data. */
        WHEN UPPER(COMMAND) = 'TOP' THEN DO
          DEBUG_SCR.CUR_PAGE = 1
        END
        OTHERWISE NOP
      END
    END

    /* Reload all the debug data. */
    IF DO_RELOAD = 'YES' THEN DO
      DEBUG_SCR.MSG = 'Reloading...'
      CALL DEBUG_DATA_LOAD
      IF DEBUG_SCR.FIND_TEXT \= '' THEN
        CALL DEBUG_FIND '', 'NO'
    END

    /* Reload DEBUG_SCR. */
    CALL DEBUG_FILL_SCR
  END
  RETURN

/* Load your data into DEBUG_DATA. how you want it. */
/* TODO: Change the EXPOSE here to your global variables. */
DEBUG_DATA_LOAD: PROCEDURE EXPOSE DEBUG_DATA. FRAME. LINK. SCR. SET.
  DEBUG_DATA.0 = 0

  /* TODO: Put your debug data here. */
  CALL DEBUG_DATA_PUSH 'SET. - Settings.'
  DO TAIL OVER SET.
    OUTPUT = 'SET.' || TAIL '=' SET.TAIL
    CALL DEBUG_DATA_PUSH OUTPUT
  END
  CALL DEBUG_DATA_PUSH ''

  CALL DEBUG_DATA_PUSH 'FRAME. - Frames.'
  DO TAIL OVER FRAME.
    OUTPUT = 'FRAME.' || TAIL '=' FRAMESET.TAIL
    CALL DEBUG_DATA_PUSH OUTPUT
  END
  CALL DEBUG_DATA_PUSH ''

  CALL DEBUG_DATA_PUSH 'LINK. - Frame Links.'
  DO TAIL OVER LINK.
    OUTPUT = 'LINK.' || TAIL '=' LINK.TAIL
    CALL DEBUG_DATA_PUSH OUTPUT
  END
  CALL DEBUG_DATA_PUSH ''

  CALL DEBUG_DATA_PUSH 'SCR. - Screen data.'
  DO TAIL OVER SCR.
    OUTPUT = 'SCR.' || TAIL '=' SCR.TAIL
    CALL DEBUG_DATA_PUSH OUTPUT
  END
  RETURN

/* Search in DEBUG_DATA. for the given text. */
DEBUG_FIND: PROCEDURE EXPOSE DEBUG_SCR. DEBUG_DATA.
  FIRST_SEARCH       = ARG(1) /* This will be blank on repeat searches. */
  DO_MOVE            = ARG(2) /* If YES move the current page. */
  DEBUG_SCR.FIND_CNT = 0
  PAGE_MARKER_MOVED  = 'NO'

  /* Don't move the current page. */
  /* Do this during reload so the screen doesn't jump. */
  IF DO_MOVE = 'NO' THEN
    PAGE_MARKER_MOVED = 'YES'

  /* Do the search. */
  DO FIND_ROW = 1 TO DEBUG_DATA.0
    DEBUG_DATA.FOUND.FIND_ROW = ''
    
    IF POS(DEBUG_SCR.FIND_TEXT, UPPER(DEBUG_DATA.FIND_ROW)) \= 0 THEN DO
      /* Note each record that has the search text */
      DEBUG_DATA.FOUND.FIND_ROW = 'YES'
      DEBUG_SCR.FIND_CNT = DEBUG_SCR.FIND_CNT + 1

      /* Move the current page to where it was found? */
      IF PAGE_MARKER_MOVED = 'NO' THEN DO
        /* Pge number where this row is. */
        NEW_PAGE = INT(FIND_ROW / DEBUG_DATA.PER_PAGE) + 1

        IF FIRST_SEARCH \= '' THEN DO
          /* First time searching jump to the first page found. */
          DEBUG_SCR.CUR_PAGE = NEW_PAGE
          PAGE_MARKER_MOVED = 'YES'
        END
        ELSE IF NEW_PAGE > DEBUG_SCR.CUR_PAGE THEN DO
          /* Not the first time searching, jump to the next page. */
          DEBUG_SCR.CUR_PAGE = NEW_PAGE
          PAGE_MARKER_MOVED = 'YES'
        END
      END
    END
  END
  RETURN

/* Transfer from DEBUG_DATA. into SCR. based on the current page. */
DEBUG_FILL_SCR: PROCEDURE EXPOSE DEBUG_SCR. DEBUG_DATA.
  START = (DEBUG_SCR.CUR_PAGE - 1) * DEBUG_DATA.PER_PAGE + 1

  DO SCR_ROW = 1 TO DEBUG_DATA.PER_PAGE
    DATA_INDEX = START + SCR_ROW - 1
    IF DATA_INDEX <= DEBUG_DATA.0 THEN DO
      ROW_DATA = DEBUG_DATA.DATA_INDEX

      /* TODO: Cut long rows. You might want to handle this differently. */
      IF LENGTH(ROW_DATA) > DEBUG_DATA.SCR_WIDTH THEN
        ROW_DATA = SUBSTR(ROW_DATA, 1, DEBUG_DATA.SCR_WIDTH - 4) || ' ...'

      IF DEBUG_DATA.FOUND.DATA_INDEX \= '' THEN
        COLOR = 'CYAN'
      ELSE
        COLOR = ''
      CALL VALUE 'DEBUG_SCR.OUTPUT' || SCR_ROW, ROW_DATA
      CALL VALUE 'DEBUG_SCR.OUTPUT' || SCR_ROW || '_C', COLOR
    END
    ELSE DO
      CALL VALUE 'DEBUG_SCR.OUTPUT' || SCR_ROW, ''
      CALL VALUE 'DEBUG_SCR.OUTPUT' || SCR_ROW || '_C', ''
    END
  END

  DEBUG_SCR.PAGE_CNT = (DEBUG_DATA.0 + DEBUG_DATA.PER_PAGE - 1) % DEBUG_DATA.PER_PAGE

  /* There could be less data this time, so adjust the current page if necessary. */
  IF DEBUG_SCR.CUR_PAGE > DEBUG_SCR.PAGE_CNT THEN
    DEBUG_SCR.CUR_PAGE = DEBUG_SCR.PAGE_CNT
  RETURN

/* Push text into DEBUG_DATA. like a stack. */
/* This exist purely to make DEBUG_DATA_LOAD easier to customize. */
DEBUG_DATA_PUSH: PROCEDURE EXPOSE DEBUG_DATA.
  DEBUG_DATA.0 = DEBUG_DATA.0 + 1
  INDX = DEBUG_DATA.0
  DEBUG_DATA.INDX = ARG(1)
  RETURN
