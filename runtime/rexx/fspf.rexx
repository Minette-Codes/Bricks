/* FSPF - Fake SPF menu. It's just a menu... */

/* Feedback welcome! <3 */
/* MinetteCodes AT outlook DOT com */

/* A note on the clock: */
/* To make the clock update a background transaction is started. */
/* This transaction has to exit as soon as it updates the screen. */
/* Otherwise there is a conflict when the main process updates the screen. */
/* The pending background transaction also must be CANCELLED when LINKing. */
/* Otherwise it will interfere with the new transaction and crash it. */
/* Likewise the clock update must be stopped if anything else is displayed, like help. */
/* (You would think this would be obvious, right? :facepalm:) */
/* Keep all of this in mind if you try to copy the clock. */
/* If is simpler in the CHAT demo because it doesn't LINK to other transactions. */

ADDRESS CICS

/* ! Set this to 'NO' to disable the clock updates. ! */
/* ! Should the clock cause you issues. ! */
DO_CLOCK_TICK='YES'

/* Allow MAPFAIL and PGMIDERR to be handled inline. */ 
EXEC CICS IGNORE CONDITION MAPFAIL PGMIDERR END-EXEC

/* Query the system for various bits of information. */
EXEC CICS ASSIGN
  USERID(SYSUSR)
  TERMID(SYSTERM)
  CONNECTED(SYSCONNECTED)
END-EXEC

EXEC CICS INQUIRE SYSTEM GMMTEXT(GMMTEXT) END-EXEC

EXEC CICS QUERY SECURITY RESOURCE('FSPF') READ(CANREAD) UPDATE(CANUPDATE) END-EXEC

/* Initialize variables. */
FRAME.          = ''      /* Frames from the database. */
FRAME.DISPLAY.  = ''      /* Frames to display on the screen in sorted order. */
FRAME.COUNT     = 0       /* The number of frames loaded. */
/* Indexed by the Frame Name. */

LINK.           = ''      /* Frame links read from the file. */
/* Index by the Frame then the index # as the rows are read. */
/* The file Key makes sure the links are read in order. */
/* Example: The first link for the ADMIN frame. - LINK.'ADMIN'.1 */
/* Also stores the number of links in a frame. */
/* Example: The number of links in the MAIN frame. - LINK.'MAIN' */

LOOKUP.         = ''      /* Lookup IDs back to FRAME and LINK. */
LOOKUP.LINK.    = ''      /* Lookup a Frame Name and Link ID to the LINK.FRAME.INDEX. */
LOOKUP.FRAME.   = ''      /* Lookup a Frame ID to the FRAME.NAME. */

SCR.            = ''      /* Screen interface. */
SCR.USRID       = SYSUSR
SCR.WELCOMEA    = CENTER('Welcome to BRICKS Transaction Server', 50)
SCR.WELCOMEB    = CENTER(GMMTEXT, 50)
PARSE VAR SYSCONNECTED SCR.CONDATE SCR.CONTIME

SET.            = ''      /* Settings. To make it easier to access in procedures. */
SET.CURFRAME    = 'MAIN'  /* The current frame. */
SET.CURLINKS    = 0       /* The number of links in the current Frame. */
SET.DATAFILE    = 'FSPFDATA'
SET.USERFILE    = 'FSPFUSER'
SET.POSITION    = 1       /* Position in the Frame Links list. */
SET.WELCOMEB    = GMMTEXT
SET.BCOLOR      = 'BLUE'  /* The default color of the per-frame welcome message. */
SET.USR         = SYSUSR
SET.LASTINPUT   = ''      /* The last input from the user. Used for PF6 to recall input. */
SET.ISAUTH      = 'NO'    /* The user is authenticated. Not PUBLIC. */
SET.ISADMIN     = 'NO'    /* The user has admin access. */
IF CANUPDATE = 52 THEN
  SET.ISADMIN   = 'YES'
IF CANREAD = 50 THEN
  SET.ISAUTH    = 'YES'

/* What is the terminal type, and thus Map set? */
SET.MAPSET      = ''      /* The map set to show the user. */
SET.MAPSETBASE  = 'FSPF1'  /* Default map set for Model 2. */
SET.TERM        = SYSTERM /* Terminal details. */
CALL SETUP_TERMINAL

/* Tick the clock, or start the background transaction to tick the clock. */
IF DO_CLOCK_TICK = 'YES' THEN DO
  EXEC CICS RETRIEVE INTO(BUF) END-EXEC
  IF EIBRESP = 0 & SUBSTR(BUF, 1, 5) = 'TICK-' THEN
    CALL CLOCK_TICK BUF
  ELSE
    CALL CLOCK_START
END

/* Load the frame data from SET.DATAFILE. */
CALL DATA_LOAD
CALL LINK_PARSE
CALL FRAME_POPULATE

/* Start the main loop. */
DO FOREVER
  SKIP          = 'NO'  /* Skip handling user input if YES. */
  SCR.CURTIME   = TIME()
  SCR.CURDATE   = FORMAT_DATE()
  SCR.FRAMENAME = SET.CURFRAME

  EXEC CICS CONVERSE MAP('MAINMENU') MAPSET(SET.MAPSET) FROM(SCR.) INTO(SCR.) ERASE END-EXEC
  /* Make sure the map is found. */
  IF EIBRESP = 36 THEN DO
    /* Avoid infinite loops. Yes, I've done that... */
    IF SET.MAPSET = SET.MAPSETBASE THEN do
      CALL CLOCK_STOP
      ERROR = 'ERROR: Could not find the Map Set:' SET.MAPSETBASE
      EXEC CICS SEND TEXT FROM(ERROR) END-EXEC
      EXEC CICS RETURN END-EXEC
    END

    /* Fallback to Model 2. */
    SET.MODEL = 2
    SET.LINKCOUNT = 17
    SET.SCROLL = 6
    SET.MAPSET = SET.MAPSETBASE
    SCR.TERMID = SET.TERM '- M' || SET.MODEL
    EXEC CICS CONVERSE MAP(SET.MAP) FROM(SCR.) INTO(MAP) ERASE END-EXEC
  END

  SCR.MSG = ''

  /* Handle the AID keys. */
  AID = C2X(EIBAID)
  SELECT
    /* Help. */
    WHEN AID = 'F1' THEN DO
      CALL CLOCK_STOP
      IF SET.MODEL = 4 THEN
        EXEC CICS SEND MAP('MAINMENUHELP') MAPSET(SET.MAPSET) ERASE END-EXEC
      ELSE DO
        EXEC CICS SEND MAP('MAINMENUHELP1') MAPSET(SET.MAPSET) ERASE END-EXEC
        EXEC CICS SEND MAP('MAINMENUHELP2') MAPSET(SET.MAPSET) ERASE END-EXEC
      END
      CALL CLOCK_START
    END
    /* Edit. */
    WHEN AID = 'F2' THEN DO
      IF SET.ISADMIN = 'YES' THEN DO
        CALL CLOCK_STOP
        EXEC CICS LINK PROGRAM('ESPF') END-EXEC
        CALL CLOCK_START
      END
      ELSE DO
        SCR.MSG = 'Not authorized to make changes.'
      END
    END
    /* Back / Exit. */
    WHEN AID = 'F3' THEN DO
      IF SET.CURFRAME = 'MAIN' THEN DO
        CALL CLOCK_STOP
        EXEC CICS RETURN END-EXEC
      END
      ELSE DO
        CALL FRAME_SWITCH 'MAIN'
      END
    END
    /* Reload FSPF. */
    WHEN AID = 'F5' THEN DO
      CALL CLOCK_STOP
      CALL CLOCK_START
      CALL DATA_LOAD
      CALL LINK_PARSE
      CALL FRAME_POPULATE
    END
    /* Recall last input. */
    WHEN AID = 'F6' THEN DO
      SCR.OPTION = SET.LASTINPUT 
      SKIP = 'YES'
    END
    /* Scroll up. */
    WHEN AID = 'F7' THEN DO
      /* Don't bother scrolling if all the Links fit on the screen. */
      IF SET.CURLINKS > SET.LINKCOUNT THEN DO
        SET.POSITION = SET.POSITION - SET.SCROLL
        IF SET.POSITION < 1 THEN
          SET.POSITION = 1
        CALL LINK_PARSE
      END
    END
    /* Scroll down. */
    WHEN AID = 'F8' THEN DO /* PF10 */
      /* Don't bother scrolling if all the Links fit on the screen. */
      IF SET.CURLINKS > SET.LINKCOUNT THEN DO
        SET.POSITION = SET.POSITION + SET.SCROLL
        IF SET.POSITION > (SET.CURLINKS - SET.LINKCOUNT) + 1 THEN
          SET.POSITION = (SET.CURLINKS - SET.LINKCOUNT) + 1
        CALL LINK_PARSE
      END
    END 
    /* Exit. */
    WHEN AID = '7C' THEN DO /* PF12 */
      CALL CLOCK_STOP
      EXEC CICS RETURN END-EXEC
    END
    /* Debug information */
    WHEN AID = 'C1' THEN DO /* PF13 */
      IF SET.ISADMIN = 'YES' THEN DO
        CALL CLOCK_STOP
        CALL DEBUG_CONSOLE SET.MAPSET
        CALL CLOCK_START
        SKIP = 'YES'
      END
      ELSE
        SCR.MSG = 'The Debug Console requires ADMIN '
    END
    OTHERWISE NOP
  END

  /* Skip processing input if an action was taken already. */
  IF SKIP = 'YES' THEN
    ITERATE

  /* Handle user input. */
  IF SCR.OPTION \= '' THEN DO
    SET.LASTINPUT = SCR.OPTION 
    CALL PROCESS_INPUT SCR.OPTION
    SCR.OPTION = ''
  END
END
CALL CLOCK_STOP
EXIT

/*\ ----~~~~====####    Process User Input    ####====~~~~---- \*/

/* Process user input. */
PROCESS_INPUT: PROCEDURE EXPOSE FRAME. LINK. LOOKUP. SCR. SET.
  PARSE ARG INPUT ARGS
  FRAME_NAME  = SET.CURFRAME
  ROW_INDX    = LOOKUP.LINK.FRAME_NAME.INPUT
  SHORTCUT    = SUBSTR(INPUT, 1, 1)
  PERIOD      = POS('.', INPUT)
  ACTION      = ''
  COMMAND     = ''

  /* Handle "Frame ID . Link ID" here so that the section for ROW_INDX finishes the work. */
  IF PERIOD >= 2 THEN DO
    FRAME_ID = SUBSTR(INPUT, 1, PERIOD - 1)
    LINK_ID = SUBSTR(INPUT, PERIOD + 1)
    FRAME_NAME = LOOKUP.FRAME.FRAME_ID

    IF FRAME_NAME = '' THEN DO
      SCR.MSG = 'Unknown Frame "' || FRAME_ID || '" for input:' INPUT
      RETURN
    END

    ROW_INDX = LOOKUP.LINK.FRAME_NAME.LINK_ID
    IF ROW_INDX = '' THEN DO
      SCR.MSG = 'Unknown Link "' || LINK_ID || '" under the Frame "' || FRAME_NAME || '" for input:' INPUT
      RETURN
    END
  END

  SELECT
    /* Directly LINK to a Transaction ID. */
    WHEN SHORTCUT = '/' THEN DO
      COMMAND = SUBSTR(INPUT, 2)
      ACTION = 'LINK'
    END
    /* Directly switch to a frame. */
    WHEN SHORTCUT = '@' THEN DO
      COMMAND = SUBSTR(INPUT, 2)
      ACTION = 'FRAME'
    END
    /* Directly a help screen. */
    WHEN SHORTCUT = '?' THEN DO
      COMMAND = SUBSTR(INPUT, 2)
      ACTION = 'HELP'
    END
    /* Found a Link ID. */
    WHEN ROW_INDX \= '' THEN DO
      REC = LINK.FRAME_NAME.ROW_INDX
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

      COMMAND = ROW_TRANS
      IF ROW_SUBM = 'Y' THEN DO
        ACTION = 'FRAME'
      END
      ELSE DO
        IF ROW_COMM \= '' THEN
          ARGS = ROW_COMM
        ACTION = 'LINK'
      END
    END
    /* Found a Frame ID. */
    WHEN LOOKUP.FRAME.INPUT \= '' THEN DO
      COMMAND = LOOKUP.FRAME.INPUT
      ACTION = 'FRAME'
    END
    /* A Frame name? */
    WHEN FRAME.INPUT \= '' THEN DO
      COMMAND = INPUT
      ACTION = 'FRAME'
    END
    /* A Frame name, but not defined in the Frame list? */
    WHEN LINK.INPUT \= '' THEN DO
      COMMAND = INPUT
      ACTION = 'FRAME'
    END
    /* Main frame? */
    WHEN UPPER(INPUT) = 'MAIN' | UPPER(INPUT) = 'M' THEN DO
      COMMAND = 'MAIN'
      ACTION = 'FRAME'
    END
    /* Q defaults to quit. QUIT does the same. */
    WHEN UPPER(INPUT) = 'Q' | UPPER(INPUT) = 'QUIT' THEN DO
      COMMAND = '-Q'
      ACTION = 'LINK'
    END
    /* Must be a command. :crosses fingers: */
    OTHERWISE DO
      COMMAND = INPUT
      ACTION = 'LINK'
    END 
  END

  IF ACTION = '' THEN DO
    SCR.MSG = 'Invalid input:' INPUT ARGS
    RETURN
  END

  /* Perform the desired action. */
  SELECT
    WHEN ACTION = 'LINK' THEN DO
      CALL LINK_EXEC UPPER(COMMAND), ARGS
    END
    WHEN ACTION = 'FRAME' THEN DO
      CALL FRAME_SWITCH COMMAND
    END
    WHEN ACTION = 'HELP' THEN DO
      CALL HELP_SCREEN COMMAND
    END
    OTHERWISE
      SCR.MSG = 'Bad bug. This should never happen.'
  END
  RETURN

/* Execute a LINK to another Transaction. */
/* There are some special Transactions which do some magic. */
/* There are also a few Transactions that require special treatment. */
LINK_EXEC: PROCEDURE EXPOSE FRAME. LINK. LOOKUP. SCR. SET.
  IF ARG() \= 2 THEN
    RETURN -1
  COMMAND = ARG(1)
  ARGS    = ARG(2)

  /* Quit FSPF. */
  IF COMMAND = '-Q' THEN DO
    CALL CLOCK_STOP
    EXEC CICS RETURN END-EXEC
  END

  /* Jump to a Frame. */
  IF SUBSTR(COMMAND, 1, 1) = "@" THEN DO
    CALL FRAME_SWITCH SUBSTR(COMMAND, 2)
    RETURN
  END

  /* Display a help screen. */
  IF SUBSTR(COMMAND, 1, 1) = "?" THEN DO
    CALL HELP_SCREEN SUBSTR(COMMAND, 2)
    RETURN
  END

  /* Certain programs will not work from FSPF. */
  IF COMMAND = 'CSSN' | COMMAND = 'CSSF' THEN DO
    SCR.MSG = 'CSSN and CSSF will not work here. Sorry.'
    RETURN
  END

  /* These require XCTL to work correctly. */
  IF COMMAND = 'BANK' | COMMAND = 'SABR' | COMMAND = 'BOOK' THEN DO
    CALL CLOCK_STOP
    EXEC CICS XCTL PROGRAM(COMMAND) COMMAREA(ARGS) END-EXEC
  END

  /* Normal LINK to the Transaction. */
  CALL CLOCK_STOP
  EXEC CICS LINK PROGRAM(COMMAND) COMMAREA(ARGS) END-EXEC
  IF EIBRESP \= 0 THEN
    SCR.MSG = 'Invalid Transaction ID "' || COMMAND || '", or not authorized!'
  CALL CLOCK_START
  RETURN

/* Display a help screen. */
HELP_SCREEN: PROCEDURE EXPOSE FRAME. LINK. LOOKUP. SCR. SET.
  PARSE ARG HELP_NAME

  IF HELP_NAME = '' THEN DO
    CALL FRAME_SWITCH 'HELP'
    RETURN
  END

  MAP_NAME = 'BRICKSHELP' || HELP_NAME
  CALL CLOCK_STOP
  EXEC CICS SEND MAP(MAP_NAME) MAPSET(SET.MAPSET) ERASE END-EXEC
  IF EIBRESP \= 0 THEN
    SCR.MSG = 'Invalid Help ID:' COMMAND
  CALL CLOCK_START
RETURN

/* Switch to a different frame. */
FRAME_SWITCH: PROCEDURE EXPOSE FRAME. LINK. LOOKUP. SCR. SET.
  PARSE ARG NEW_FRAME
  NEW_FRAME = UPPER(NEW_FRAME)
  
  IF NEW_FRAME = '' THEN DO
    SCR.MSG = 'Frame ID required.'
    RETURN
  END

  /* The new frame is an ID, so get the name for the ID. */
  IF FRAME.NEW_FRAME = '' & LOOKUP.FRAME.NEW_FRAME \= '' THEN
    NEW_FRAME = LOOKUP.FRAME.NEW_FRAME

  IF NEW_FRAME = '' THEN DO
    SCR.MSG = 'Unknown Frame ID:' NEW_FRAME
    RETURN
  END

  IF NEW_FRAME = 'MAIN' THEN DO
    SCR.WELCOMEB    = CENTER(SET.WELCOMEB, 50)
    SCR.WELCOMEB_C  = SET.BCOLOR
    SCR.FRAMENAME_C = SET.BCOLOR
  END
  ELSE DO
    REC = FRAME.NEW_FRAME
    PARSE VAR REC,
      FRAME_ID      '~',
      FRAME_IDC     '~',
      FRAME_ORDER   '~',
      FRAME_NAME    '~',
      FRAME_DESCR   '~',
      FRAME_DESCRC  '~',
      FRAME_WELCOM  '~',
      FRAME_WELCOMC
    IF FRAME_WELCOM \= '' THEN
      SCR.WELCOMEB = CENTER(FRAME_WELCOM, 50)
    IF FRAME_WELCOMC \= '' THEN DO
      COLOR = COLOR_CONVERT(FRAME_WELCOMC)
      SCR.WELCOMEB_C = COLOR
      SCR.FRAMENAME_C = COLOR
    END
    ELSE DO
      SCR.WELCOMEB_C = SET.BCOLOR
      SCR.FRAMENAME_C = SET.BCOLOR
    END
  END

  SET.CURFRAME = NEW_FRAME
  SET.POSITION = 1
  CALL LINK_PARSE
  RETURN

/*\ ----~~~~====####    Loading and Parsing    ####====~~~~---- \*/

/* Load the frame data from SET.DATAFILE. */
DATA_LOAD: PROCEDURE EXPOSE FRAME. LINK. LOOKUP. SCR. SET.
  CALL CURSOR_OPEN SET.DATAFILE
  FRAME.COUNT = 0

  /* Clear any old data. */
  DO TAIL OVER LINK.
    LINK.TAIL = ''
  END
  
  DO FOREVER
    EXEC CICS READNEXT FILE(SET.DATAFILE) INTO(REC) RIDFLD(KEY) END-EXEC
    IF EIBRESP \= 0 THEN
      LEAVE

    IF SUBSTR(KEY, 1, 5) = 'FRAME' THEN DO
      /* Current record is a frame. */
      PARSE VAR REC,
        ROW_ID     '~',
        ROW_IDC    '~',
        ROW_ORDER  '~',
        ROW_NAME   '~',
        ROW_DESCR  '~',
        ROW_DESCRC

      FRAME.ROW_NAME = REC
      LOOKUP.FRAME.ROW_ID = ROW_NAME
      IF ROW_ORDER \= '' THEN DO
        FRAME.COUNT = FRAME.COUNT + 1
        ROW_ID = FRAME.COUNT
        FRAME.DISPLAY.ROW_ID = ROW_NAME
      END
    END
    ELSE IF SUBSTR(KEY, 1, 4) = 'LINK' THEN DO
      /* Current record is a link. */
      PARSE VAR KEY 'LINK-' ROW_FRAME '-' ROW_ORDER '-' ROW_ID

      IF LINK.ROW_FRAME = '' THEN
        LINK.ROW_FRAME = 1
      ELSE
        LINK.ROW_FRAME = LINK.ROW_FRAME + 1
      ROW_INDX = LINK.ROW_FRAME

      LINK.ROW_FRAME.ROW_INDX = REC
      LOOKUP.LINK.ROW_FRAME.ROW_ID = ROW_INDX
    END
  END

  CALL CURSOR_CLOSE SET.DATAFILE
  RETURN

LINK_PARSE: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  FRAMENAME = SET.CURFRAME
  IF LINK.FRAMENAME \= '' THEN
    LINKS = LINK.FRAMENAME
  ELSE
    LINKS = 0

  START = SET.POSITION
  IF LINKS > 0 THEN DO
    IF START > (LINKS - SET.SCROLL) THEN
      START = LINKS - SET.SCROLL
  END

  DO SCR_ROW = 1 TO SET.LINKCOUNT
    ROW_ID = START + SCR_ROW - 1
    IF ROW_ID <= LINKS THEN DO
      REC = LINK.FRAMENAME.ROW_ID
      PARSE VAR REC,
        ROW_ID     '~',
        ROW_IDC    '~',
        ROW_ORDER  '~',
        ROW_FRAME   '~',
        ROW_SUBM   '~',
        ROW_TRANS  '~',
        ROW_TRANSC '~',
        ROW_DESCR  '~',
        ROW_DESCRC '~',
        ROW_COMM
      
      IF UPPER(ROW_IDC) = 'H' THEN DO
        CALL VALUE 'SCR.LINKID' || SCR_ROW, ''
        CALL VALUE 'SCR.LINKID' || SCR_ROW || '_C', ''
      END
      ELSE DO
        CALL VALUE 'SCR.LINKID' || SCR_ROW, ROW_ID    
        CALL VALUE 'SCR.LINKID' || SCR_ROW || '_C', COLOR_CONVERT(ROW_IDC)
      END

      IF UPPER(ROW_TRANSC) = 'H' THEN DO
        CALL VALUE 'SCR.TRANSID' || SCR_ROW, ''
        CALL VALUE 'SCR.TRANSID' || SCR_ROW || '_C', ''
      END
      ELSE DO
        IF SUBSTR(ROW_TRANS, 1, 1) = '?' THEN
          ROW_TRANS = LEFT(ROW_TRANS, 5)
        ELSE
          ROW_TRANS = RIGHT(ROW_TRANS, 5)
        CALL VALUE 'SCR.TRANSID' || SCR_ROW, ROW_TRANS    
        CALL VALUE 'SCR.TRANSID' || SCR_ROW || '_C', COLOR_CONVERT(ROW_TRANSC)
      END

      IF UPPER(ROW_DESCRC) = 'H' THEN DO
        CALL VALUE 'SCR.DESCR' || SCR_ROW, ''
        CALL VALUE 'SCR.DESCR' || SCR_ROW || '_C', ''
      END
      ELSE DO
        CALL VALUE 'SCR.DESCR' || SCR_ROW, ROW_DESCR    
        CALL VALUE 'SCR.DESCR' || SCR_ROW || '_C', COLOR_CONVERT(ROW_DESCRC)
      END
    END
    ELSE DO
      CALL VALUE 'SCR.LINKID' || SCR_ROW, ''
      CALL VALUE 'SCR.TRANSID'|| SCR_ROW, ''
      CALL VALUE 'SCR.DESCR'  || SCR_ROW, ''

      CALL VALUE 'SCR.LINKID' || SCR_ROW || '_C', ''
      CALL VALUE 'SCR.TRANSID'|| SCR_ROW || '_C', ''
      CALL VALUE 'SCR.DESCR'  || SCR_ROW || '_C', ''
    END
  END

  SET.CURLINKS = LINKS
  IF LINKS = 0 THEN
    SET.POSITION = 1
  ELSE IF SET.POSITION > LINKS THEN
    SET.POSITION = LINKS

  IF SET.POSITION > 1 THEN
    SCR.MORETOP = CENTER('*** Press PF7 for more links ***', 40)
  ELSE
    SCR.MORETOP = ''

  IF SET.POSITION - 1 < (LINKS - SET.LINKCOUNT) & LINKS > SET.LINKCOUNT THEN
    SCR.MOREBOT = CENTER('*** Press PF8 for more links ***', 40)
  ELSE
    SCR.MOREBOT = ''
  RETURN

/* Populate the frame list in the lower right. */
FRAME_POPULATE: PROCEDURE EXPOSE FRAME. LINK. SCR. SET.
  DO SCR_ROW = 1 TO SET.FRAMECOUNT
    IF SCR_ROW <= FRAME.COUNT THEN DO
      FRAME_NAME = FRAME.DISPLAY.SCR_ROW
      REC = FRAME.FRAME_NAME
      PARSE VAR REC,
        FRAME_ID     '~',
        FRAME_IDC    '~',
        FRAME_ORDER  '~',
        FRAME_NAME   '~',
        FRAME_DESCR  '~',
        FRAME_DESCRC  '~',
        FRAME_WELCOM  '~',
        FRAME_WELCOMC
      
      IF UPPER(FRAME_IDC) = 'H' THEN DO
        CALL VALUE 'SCR.FRAMEID' || SCR_ROW, ''
        CALL VALUE 'SCR.FRAMEID' || SCR_ROW || '_C', ''
      END
      ELSE DO
        CALL VALUE 'SCR.FRAMEID' || SCR_ROW, RIGHT(FRAME_ID, 2)
        CALL VALUE 'SCR.FRAMEID' || SCR_ROW || '_C', COLOR_CONVERT(FRAME_IDC)
      END

      IF UPPER(FRAME_DESCRC) = 'H' THEN DO
        CALL VALUE 'SCR.FRAME' || SCR_ROW, ''
        CALL VALUE 'SCR.FRAME' || SCR_ROW || '_C', ''
      END
      ELSE DO
        CALL VALUE 'SCR.FRAME' || SCR_ROW, FRAME_DESCR    
        CALL VALUE 'SCR.FRAME' || SCR_ROW || '_C', COLOR_CONVERT(FRAME_DESCRC)
      END
    END
    ELSE DO
      CALL VALUE 'SCR.FRAMEID' || SCR_ROW, ''
      CALL VALUE 'SCR.FRAME'|| SCR_ROW, ''

      CALL VALUE 'SCR.FRAMEID' || SCR_ROW || '_C', ''
      CALL VALUE 'SCR.FRAME'|| SCR_ROW || '_C', ''
    END
  END
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
  RETURN REC

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
  RETURN

/*\ ----~~~~====####    Setup the Terminal    ####====~~~~---- \*/

SETUP_TERMINAL: PROCEDURE EXPOSE SET. SCR.
  EXEC CICS ASSIGN
    SCREENWD(SYSSCRW)
    SCREENHT(SYSSCRH)
  END-EXEC

  /* Model 2 - 24x80 */
  SET.FRAMECOUNT  = 8       /* Number of frames to list in the lower right. */
  SET.LINKCOUNT   = 17      /* The number of Links to display per screen. */
  SET.MODEL       = 2       /* Terminal model # */
  SET.SCROLL      = 6       /* How many rows to scroll with PF7 and PF8. */
  SET.SUFFIX      = ''      /* The suffix to affix the map set for larger screens. */

  IF SYSSCRH >= 43 THEN DO
    /* Model 4 - 43x80 */
    SET.FRAMECOUNT  = 36
    SET.LINKCOUNT   = 36
    SET.MODEL       = 4
    SET.SCROLL      = 12
    SET.SUFFIX      = 'L'
  END
  ELSE IF SYSSCRH >= 32 THEN DO
    /* Model 3 - 32x80 */
    SET.FRAMECOUNT  = 16
    SET.LINKCOUNT   = 24
    SET.MODEL       = 3
    SET.SCROLL      = 8
    SET.SUFFIX      = 'M'
  END
  ELSE IF SYSSCRH >= 27 & SYSSCRW = 132 THEN DO
    /* Model 5 - 27x132 */
    SET.FRAMECOUNT  = 8
    SET.LINKCOUNT   = 17
    SET.MODEL       = 5
    SET.SCROLL      = 6
    SET.SUFFIX      = 'W'
  END
  SET.MAPSET = SET.MAPSETBASE || SET.SUFFIX
  SCR.TERMID = SET.TERM '- M' || SET.MODEL
  RETURN

/*\ ----~~~~====####    Clock Tick    ####====~~~~---- \*/

/* Add hyphens for an ISO date format. */
/* https://en.wikipedia.org/wiki/ISO_8601 */
FORMAT_DATE: PROCEDURE
    CURDATE = DATE('S')
    PARSE VAR CURDATE 1 YYYY 5 MM 7 DD
    CURDATE = YYYY || '-' || MM || '-' || DD
  RETURN CURDATE

/* Update the time. */
CLOCK_TICK: PROCEDURE EXPOSE SET.
  /* Buffer to pass on. Contains TICK- and the Map set. */
  PARSE ARG BUF
  PARSE VAR BUF 'TICK-' MAPSET

  /* Tick the clock. */
  TICKSCR. = ''
  TICKSCR.CURTIME = TIME()
  TICKSCR.CURDATE = FORMAT_DATE()
  EXEC CICS SEND MAP('MAINMENUTICK')  MAPSET(MAPSET) FROM(TICKSCR.) DATAONLY END-EXEC
  IF EIBRESP \= 0 THEN DO
    EXEC CICS RETURN END-EXEC
    EXIT
  END

  /* Kick off the next Tick Transaction. */
  /* Jiggle the update time a bit for spice. */
  NEXT_TICK = RIGHT(RANDOM(1, 3), 6, '0')
  EXEC CICS START TRANSID('FSPF') INTERVAL(NEXT_TICK) FROM(BUF) END-EXEC
  EXEC CICS RETURN END-EXEC
  EXIT
  RETURN

/* Start a background Transaction to update the clock. */
CLOCK_START: PROCEDURE EXPOSE SET.
  /* Pass along the map set so the tick knows which one to use. */
  BUF = 'TICK-' || SET.MAPSET

  /* Start the Tick Transaction. */
  EXEC CICS START TRANSID('FSPF') INTERVAL(2) FROM(BUF) END-EXEC
  RETURN

/* Stop the background Transaction that updates the clock. */
CLOCK_STOP: PROCEDURE EXPOSE SET. 
  EXEC CICS CANCEL TRANSID('FSPF') END-EXEC
  RETURN

/*\ ----~~~~====####    Debug Console!    ####====~~~~---- \*/

/* TODO: These are where you should make updates to use in your project. */
/* The first two procedures require modification. */
/* NOTE: This is rather simple and crude, on purpose. Adapt it to your needs. */

/* Debug loop. */
/* TODO: Change the EXPOSE here to your global variables. */
DEBUG_CONSOLE: PROCEDURE EXPOSE FRAME. LINK. LOOKUP. SCR. SET.
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
        CALL DEBUG_FIND '', 'NO' /* The NO means do not move the current page. */
    END

    /* Reload DEBUG_SCR. */
    CALL DEBUG_FILL_SCR
  END
  RETURN

/* Load your data into DEBUG_DATA. how you want it. */
/* TODO: Change the EXPOSE here to your global variables. */
DEBUG_DATA_LOAD: PROCEDURE EXPOSE DEBUG_DATA. FRAME. LINK. LOOKUP. SCR. SET.
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

  CALL DEBUG_DATA_PUSH 'LOOKUP. - ID to row lookup.'
  DO TAIL OVER LOOKUP.
    OUTPUT = 'LOOKUP.' || TAIL '=' LOOKUP.TAIL
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
