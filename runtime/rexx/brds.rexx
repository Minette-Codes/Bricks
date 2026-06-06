/* BRDS - Browse KSDS file records. */
/* Copied from 'cons.rexx'. */

/* Usage: BRDS [-h] [-s SEPARATOR] [FILE_NAME [START_KEY]] */

/* BRDS has a magic trick. */
/* If a message is given after the file and key it will be displayed as an error. */
/* Example: BRDS -s ~ BRDSTEST ReallyBig This is a message. */
/* Will set the Separator, Table and Key as expected... */
/* AND will display 'This is a message.' as an error. Try it. */

/* Another magic trick! */
/* If DFHCOMMAREA is not empty is is treated as command line options. */
/* Example: */
/*   ARGS = '-s ~ BRDSTEST ReallyBig Press F3 to return.' */
/*   EXEC CICS LINK PROGRAM('BRDS'') COMMAREA(ARGS) END-EXEC */
/* When BRDS returns it will set DFHCOMMAREA to: SET.FILE SET.KEY SET.SEP */
/*   The file name, the current key, the field separator. */
/* This has the fun sideeffect of saving your place when you exit BRDS. */

/* Pressing PF24 will demonstrate everything BRDS can do. */
/* This will load test data into the file BRDSTEST. */
/* There are examples for each field separator along with really big text records. */

/* Pressing PF23 will LINK BRDS with COMMAREA set to the following: */
/*   -s ~ BRDSTEST ReallyBig This is a message. */

/* For developers, press PF13 to show all of the tails from the STEMS: */
/*   SET. SCR. FIELDS. */

ADDRESS CICS

/* Allow MAPFAIL to be handled inline. */ 
EXEC CICS IGNORE CONDITION MAPFAIL END-EXEC

EXEC CICS ASSIGN TERMID(TRM) SCREENWD(SCRW) SCREENHT(SCRH) END-EXEC

/* Initialize variables. */
FIELDS. = ''        /* Holds parsed fields from the current record. */
TRUNC. = ''         /* Note when a field is truncated. */
SCR. = ''
SCR.TERMID = TRM
SET. = ''           /* Settings. To make it easier to access in procedures. */
SET.FILE  = ''      /* The KSDS file to read. */
SET.KEY = ''        /* The key for the record read from KSDS. */
SET.MAP = ''        /* The map to show the user. */
SET.REC = ''        /* The record read from KSDS. */
SET.PAGES = 0       /* The number of pages if more than one screen of data. */
SET.PAGE = 1        /* The current page. */
SET.PER_PAGE = 12   /* Rows per page, adjusted for terminal model. */
SET.ROW_WIDTH = 76  /* row width for normal width terminals. */
SET.SEP = ''        /* Field separator. Empty means treat the record as text. */
SET.START_KEY = ''  /* Starting key. */
SET.TID = 'BRDS'    /* The admin can change the TID. This is the default. */
SET.WIDTH = SCRW
SET.HEIGHT = SCRH
TEST_DATA_FILE = 'BRDSTEST'

/* Which version of the map to use. */
MAPBASE = 'BRDS1'                       /* Model 2 - 24x80 */
SUFFIX = ''
IF SCRH >= 43 THEN DO                   /* Model 4 - 43x80 */
  SET.PER_PAGE = 31
  SUFFIX = 'L'
END
ELSE IF SCRH >= 32 THEN DO              /* Model 3 - 32x80 */
  SET.PER_PAGE = 20
  SUFFIX = 'M'
END
ELSE IF SCRH >= 27 & SCRW = 132 THEN DO /* Model 5 - 27x132 */
  SET.ROW_WIDTH = 128
  SET.PER_PAGE = 17
  SUFFIX = 'W'
END
SET.MAP = MAPBASE || SUFFIX

CALL COMMAND_LINE_PARSE

/* Main loop. */
DO FOREVER
  SKIP         = 'NO' /* Don't fetch a new record if YES. */
  SCR.FIELDSEP = SET.SEP
  SCR.FNAME    = SET.FILE
  SCR.LASTKEY  = SET.KEY
  SCR.STARTKEY = SET.START_KEY
  SCR.TRANSID   = SET.TID

  EXEC CICS CONVERSE MAP(SET.MAP) FROM(SCR.) INTO(MAP) ERASE END-EXEC
  /* Make sure the map is found. */
  IF EIBRESP = 36 THEN DO
    /* Avoid infinite loops. Yes, I've done that... */
    IF SET.MAP = MAPBASE THEN do
      ERROR = 'ERROR: Could not find the map:' MAPBASE
      EXEC CICS SEND TEXT FROM(ERROR) END-EXEC
      EXEC CICS RETURN END-EXEC
    END

    /* Fallback to Model 2. */
    SET.PER_PAGE = 10
    SET.MAP = MAPBASE
    EXEC CICS CONVERSE MAP(SET.MAP) FROM(SCR.) INTO(MAP) ERASE END-EXEC
  END

  SCR.MSG = ''

  AID = C2X(EIBAID)
  SELECT
  /* Help. */
    WHEN AID = 'F1' THEN DO
      CALL SEND_HELP
      SKIP = 'YES'
    END
    /* Exit. */
    WHEN AID = 'F3' THEN DO
      DFHCOMMAREA = ''
      IF SET.SEP \= '' THEN
        DFHCOMMAREA = '-s' SET.SEP
      DFHCOMMAREA = DFHCOMMAREA SET.FILE SET.KEY
      EXEC CICS RETURN END-EXEC
    END
    /* Reset the cursor. */
    WHEN AID = 'F5' & SET.FILE \= '' THEN DO
      CALL CURSOR_CLOSE SET.FILE
      CALL CURSOR_OPEN SET.FILE SET.START_KEY
    END
    /* Toggle the field separator. */
    WHEN AID = 'F6' THEN DO
      CALL NEXT_SEPARATOR
      MAP.FIELDSEP = SET.SEP
      IF SET.FILE \= '' THEN DO
        CALL RECORD_PARSE
      END
      SKIP = 'YES'
    END
    /* Previous record. */
    WHEN AID = 'F7' THEN DO
      DIR = 'BACK'
    END
    /* Next record. */
    WHEN AID = 'F8' THEN DO
      NOP /* Handled automatically. I keep looking for this when I'm "medicated". */
    END
    /* Scroll up. */
    WHEN AID = 'F9' THEN DO
      SET.PAGE = SET.PAGE - 1
      IF SET.PAGE <= 0 THEN
        SET.PAGE = 1
      IF SET.FILE \= '' THEN
        CALL FIELDS_LOAD
      SKIP = 'YES'
    END
    /* Scroll down. */
    WHEN AID = '7A' THEN DO /* PF10 */
      SET.PAGE = SET.PAGE + 1
      IF SET.PAGE > SET.PAGES THEN
        SET.PAGE = SET.PAGES
      IF SET.FILE \= '' THEN
        CALL FIELDS_LOAD
      SKIP = 'YES'
    END 
    WHEN AID = 'C1' THEN DO /* PF13 */
      CALL DEBUG_INFO
      SKIP = 'YES'
    END
    /* Starts another copy of BRDS with test data. */
    WHEN AID = '4B' THEN DO /* PF23 */
      CALL TEST_DATA_LOAD
      COMMAREA = '-s ~ BRDSTEST ReallyBig Press F3 to return.'
      EXEC CICS LINK PROGRAM(SET.TID) COMMAREA(COMMAREA) END-EXEC
      IF COMMAREA \= '' THEN DO
        IF SET.FILE \= '' THEN
          CALL CURSOR_CLOSE SET.FILE
        PARSE VAR COMMAREA MAP.FNAME SET.START_KEY SET.SEP
        MAP.STARTKEY = SET.START_KEY
        MAP.FIELDSEP = SET.SEP
        SET.FILE = '' /* Make it look like the user entered a new file name. */
      END
      ELSE
        SKIP = 'YES'
    END
    /* Test data. SSSHHH! TOP SECRET!! */
    WHEN AID = '4C' THEN DO /* PF24 */
      IF SET.FILE \= '' THEN
        CALL CURSOR_CLOSE SET.FILE
      CALL TEST_DATA_LOAD
      MAP.FNAME = 'BRDSTEST'
      SET.START_KEY = ''
      MAP.STARTKEY = SET.START_KEY
      SET.SEP = ''
      MAP.FIELDSEP = SET.SEP
      SET.FILE = '' /* Make it look like the user entered a new file name. */
    END
    OTHERWISE NOP
  END

  /* Did the field separator change? */
  IF MAP.FIELDSEP \= SET.SEP THEN DO
    SET.SEP = MAP.FIELDSEP
    IF SET.FILE \= '' THEN DO
      CALL RECORD_PARSE
      SKIP = 'YES'
    END
  END

  /* Did the start key change? */
  IF SET.START_KEY \= MAP.STARTKEY THEN DO
    SET.START_KEY = MAP.STARTKEY
    IF SET.FILE \= '' THEN DO
      CALL CURSOR_RESET SET.FILE SET.START_KEY
      SKIP = 'NO'
    END
  END

  /* Skip fetching a new record, if the file name has not changed. */
  IF SKIP = 'YES' & SET.FILE = UPPER(MAP.FNAME) THEN
    ITERATE

  /* Did the file name changed. */
  IF MAP.FNAME \= '' & SET.FILE \= MAP.FNAME THEN DO
    IF SET.FILE \= '' THEN
      CALL CURSOR_CLOSE SET.FILE
    /* IF SET.FILE \= MAP.FNAME THEN */
      CALL CURSOR_OPEN MAP.FNAME SET.START_KEY
    SET.FILE = UPPER(MAP.FNAME)
    SET.REC = ''
    SET.KEY = ''
  END
  ELSE IF MAP.FNAME = '' THEN DO
    SCR.MSG = 'Type a file name and press ENTER. PF3 exits.'
    SET.FILE = ''
  END
  IF SET.FILE = '' THEN
    ITERATE

  /* Consume the next record via the cursor. */
  CALL CURSOR_LOAD DIR
  DROP DIR
  CALL RECORD_PARSE
END

EXIT

/* FIELDS. is here so it gets passed through to procedure calls. */
COMMAND_LINE_PARSE: PROCEDURE EXPOSE DFHCOMMAREA FIELDS. SCR. SET.
  /* Check for command line arguments. */
  /* If there are none check for arguments in DFHCOMMAREA. */
  EXEC CICS RECEIVE INTO(BUF) END-EXEC
  PARSE VAR BUF SET.TID CKEY
  IF DFHCOMMAREA \= '' & CKEY = '' THEN DO
    CKEY = STRIP(DFHCOMMAREA)
  END


  /* Do they need help? */
  IF        CKEY        = '-?'   |,
     SUBSTR(CKEY, 1, 2) = '--'   |,
      LOWER(CKEY)       = '-h'   |,
      UPPER(CKEY)       = 'HELP' THEN DO
    CALL SEND_HELP
    EXIT
  END

  /* Was the field separator provided? */
  PARSE VAR CKEY '-s' CHECK REST
  IF CHECK \= '' THEN DO
    SET.SEP = CHECK
    CKEY = REST
  END

  /* If a file is given open it and read a record. */
  IF CKEY \= '' THEN DO
    PARSE VAR CKEY SET.FILE SET.START_KEY
    SET.FILE = UPPER(SET.FILE)

    /* Check for a message to display. */
    PARSE VAR SET.START_KEY NEW_KEY MESSAGE
    IF NEW_KEY \= '' THEN DO
      SET.START_KEY = NEW_KEY
      SCR.MSG = MESSAGE
    END

    CALL CURSOR_OPEN SET.FILE SET.START_KEY
    CALL CURSOR_LOAD
    CALL RECORD_PARSE
  END
  RETURN

/* Parse a record according to SET.SEP. */
RECORD_PARSE: PROCEDURE EXPOSE FIELDS. SCR. SET. TRUNC.
  SET.PAGE = 1
  SCR.PAGES_EXTRA = ''
  IF SET.SEP = '' THEN DO
    /* Present the record as one long string of text. */
    /* The record is wrapped as needed. */
    FIELDS.0 = 0
    POS = 1
    DO WHILE POS < LENGTH(SET.REC)
      FIELD_NUM = FIELDS.0 + 1
      FIELDS.0 = FIELD_NUM
      FIELDS.FIELD_NUM = SUBSTR(SET.REC, POS, SET.ROW_WIDTH)
      TRUNC.FIELD_NUM = ''
      POS = POS + SET.ROW_WIDTH
    END
    IF LENGTH(SET.REC) > SET.ROW_WIDTH THEN
      SCR.PAGES_EXTRA = 'Record wrapped. '
  END
  ELSE DO
    /* Parse the record into separate fields. */
    FIELDS.0 = 0
    RIGHT = SET.REC
    DO WHILE LENGTH(RIGHT) > 0
      /* Do a strange little dance to parse the record. */
      /* This translate to: PARSE VAR LEFT 'X' RIGHT */
      /* With X as the separator character. */
      INTERPRET 'PARSE VAR RIGHT LEFT ''' || SET.SEP || ''' RIGHT' 
      FIELDS.0 = FIELDS.0 + 1
      FIELD_NUM = FIELDS.0
      TRUNC.FIELD_NUM = ''
      IF LENGTH(LEFT) > SET.ROW_WIDTH THEN DO
        FIELDS.FIELD_NUM = LEFT(LEFT, SET.ROW_WIDTH - 6) '...'
        SCR.PAGES_EXTRA = 'Field(s) truncated. '
        TRUNC.FIELD_NUM = 'T'
      END
      ELSE
        FIELDS.FIELD_NUM = LEFT
    END
  END
  SET.PAGES = (FIELDS.0 + SET.PER_PAGE - 1) % SET.PER_PAGE
  CALL FIELDS_LOAD
  RETURN

/* Load FIELDS. into SCR. */
FIELDS_LOAD: PROCEDURE EXPOSE FIELDS. SCR. SET. TRUNC.
  SCR.MORE_UP = ''
  SCR.MORE_TOP = ''
  SCR.MORE_DOWN = ''
  SCR.MORE_BOT = ''
  START = (SET.PAGE - 1) * SET.PER_PAGE + 1
  DO J = 1 TO SET.PER_PAGE
    IDX = START + J - 1
    LINE = ''
    LINE_TRUNC = ''
    IF IDX <= FIELDS.0 THEN DO
      LINE = FIELDS.IDX
      LINE_TRUNC = TRUNC.IDX
    END
    CALL VALUE 'SCR.ROW' || J, LINE
    CALL VALUE 'SCR.TRUNC' || J, LINE_TRUNC
  END
  IF IDX < FIELDS.0 THEN
    SCR.MORE_DOWN = 'More..'
  IF START > 1 THEN
    SCR.MORE_UP = 'More...'
  IF SET.PAGES > 1 & SET.PAGE = SET.PAGES THEN
    SCR.MORE_BOT = '*** Bottom Of Data ***'
  IF SET.PAGES > 1 & SET.PAGE = 1 THEN
    SCR.MORE_TOP = ' *** Top Of Data ***'

  SCR.PAGES = SCR.PAGES_EXTRA
  IF FIELDS.0 > 1 & SET.PAGES > 1 THEN DO
    IF SET.SEP = '' THEN
      SCR.PAGES = SCR.PAGES || 'Rows:'
    ELSE
      SCR.PAGES = SCR.PAGES || 'Fields:'
    SCR.PAGES = SCR.PAGES FIELDS.0 'Page:' SET.PAGE 'of' SET.PAGES
    /* Add a note on scrolling through the pages. */
    PADD = COPIES(' ', SET.WIDTH - LENGTH(SCR.PAGES) - 37)
    SCR.PAGES = SCR.PAGES || PADD 'PF9=Page up PF10=Page Down'
  END
RETURN

CURSOR_LOAD: PROCEDURE EXPOSE SCR. SET.
  PARSE ARG DIR
  IF DIR = 'BACK' THEN
    EXEC CICS READPREV FILE(SET.FILE) INTO(SET.REC) RIDFLD(SET.KEY) END-EXEC
  ELSE
    EXEC CICS READNEXT FILE(SET.FILE) INTO(SET.REC) RIDFLD(SET.KEY) END-EXEC

  SELECT
    WHEN EIBRESP = 0 THEN DO
    END
    WHEN EIBRESP = 20 THEN DO        /* ENDFILE -- Past the last key. */
      SCR.MSG = 'Last record read. / File not found.'
      /* Reset the cursor and re-read the last record. */
      /* This lets the user go (back/for)wards from the last record. */
      CALL CURSOR_RESET SET.FILE SET.KEY
      IF DIR = 'BACK' THEN
        EXEC CICS READNEXT FILE(SET.FILE) INTO(SET.REC) RIDFLD(SET.KEY) END-EXEC
      ELSE
        EXEC CICS READPREV FILE(SET.FILE) INTO(SET.REC) RIDFLD(SET.KEY) END-EXEC
    END
    WHEN EIBRESP = 17 THEN DO        /* IOERR -- Underlying store error. */
      SET.KEY = ''
      SET.REC = ''
      SCR.MSG = 'IO ERROR.'
    END
    OTHERWISE NOP
  END
  RETURN

CURSOR_OPEN: PROCEDURE
  PARSE ARG FILE KEY
  EXEC CICS STARTBR FILE(FILE) RIDFLD(KEY) END-EXEC
  RETURN

CURSOR_CLOSE: PROCEDURE
  PARSE ARG FILE
  EXEC CICS ENDBR FILE(FILE) END-EXEC
  RETURN

CURSOR_RESET: PROCEDURE
  PARSE ARG FILE KEY
  EXEC CICS RESETBR FILE(FILE) RIDFLD(KEY) END-EXEC
  RETURN

/* Set SET.SEP to the next value. */
NEXT_SEPARATOR: PROCEDURE EXPOSE SET.
  IF SET.SEP = '' THEN
    SET.SEP = '|'
  ELSE IF SET.SEP = '|' THEN
    SET.SEP = ','
  ELSE IF SET.SEP = ',' THEN
    SET.SEP = ';'
  ELSE IF SET.SEP = ';' THEN
    SET.SEP = ':'
  ELSE IF SET.SEP = ':' THEN
    SET.SEP = '~'
  ELSE IF SET.SEP = '~' THEN
    SET.SEP = ''
  ELSE
    SET.SEP = ''
  RETURN

/* Send some help text. */
SEND_HELP: PROCEDURE EXPOSE SET.
  BLANK_LINE = LEFT('', SET.WIDTH)
  HELP_TEXT = LEFT('BRDS - Browse KSDS file records.', SET.WIDTH) ||,
  BLANK_LINE ||,
  LEFT('Usage:' SET.TID '[-h] [-s SEPARATOR] [FILE_NAME [START_KEY]]', SET.WIDTH) ||,
  BLANK_LINE || ,
  LEFT('Displays the records for a given KSDS file. Starting at the optional key.', SET.WIDTH) ||,
  LEFT('The record is parsed into fields by SEPARATOR.', SET.WIDTH) ||,
  LEFT('If SEPARATOR is blank the record is wrapped into multiple rows.', SET.WIDTH) ||,
  BLANK_LINE ||,
  LEFT('Wide fields will be truncated and a red "T" will mark the field.', SET.WIDTH) ||,
  BLANK_LINE ||,
  LEFT('PF5 closes the cursor then opens a new one. New records will be seen.', SET.WIDTH) ||,
  BLANK_LINE ||,
  LEFT('PF4 rotates the separator through: "" "|" "," ";" ":" "!"', SET.WIDTH) ||,
  BLANK_LINE ||,
  LEFT('PF7 and PF8 read the Previous and Next record.', SET.WIDTH) ||,
  BLANK_LINE ||,
  LEFT('PF9 and PF10 scroll Up and Down through the record fields/rows.', SET.WIDTH) ||,
  BLANK_LINE ||,
  LEFT('Press PF24 for a demonstration with test data.', SET.WIDTH) ||,
  BLANK_LINE ||,
  LEFT('Example: BRDS -s | mandelbrot Defaults', SET.WIDTH) ||,
  LEFT('(Requires the Mandelbrot saves be loaded using MNDU.)', SET.WIDTH) ||,
  BLANK_LINE || X2C(13)
  EXEC CICS SEND TEXT FROM(HELP_TEXT) ERASE END-EXEC
  RETURN

  /* Load some useful test data. */
  TEST_DATA_LOAD: PROCEDURE EXPOSE TEST_DATA_FILE
  REC = '1234567890'
  Key = '1234567890'
  CALL TEST_DATA_RECORD KEY REC
  REC = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  REC = 'This is a really big record.|' || COPIES(REC,100) || '|The End.'
  KEY = 'ReallyBig'
  CALL TEST_DATA_RECORD KEY REC
  REC = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  REC = 'This is an incredibly big record.:' || COPIES(REC,200) ||':The End.'
  KEY = 'ZBig'
  CALL TEST_DATA_RECORD KEY REC
  REC = '1|2|3|4|5|6|7|8|9|0'
  KEY = 'Pipe0'
  CALL TEST_DATA_RECORD KEY REC
  REC = 'A|B|C|D|E|F|G|H|I|J|K|L|M|N|O|P|Q|R|S|T|U|V|W|X|Y|Z'
  KEY = 'PipeA'
  CALL TEST_DATA_RECORD KEY REC
  REC = REC || '|' || REC
  KEY = 'PipeB'
  CALL TEST_DATA_RECORD KEY REC
  REC = '1,2,3,4,5,6,7,8,9,0'
  KEY = 'Comma0'
  CALL TEST_DATA_RECORD KEY REC
  REC = 'A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z'
  KEY = 'CommaA'
  CALL TEST_DATA_RECORD KEY REC
  REC = REC || ',' || REC
  KEY = 'CommaB'
  CALL TEST_DATA_RECORD KEY REC
  REC = '1;2;3;4;5;6;7;8;9;0'
  KEY = 'Semicolon0'
  CALL TEST_DATA_RECORD KEY REC
  REC = 'A;B;C;D;E;F;G;H;I;J;K;L;M;N;O;P;Q;R;S;T;U;V;W;X;Y;Z'
  KEY = 'SemicolonA'
  CALL TEST_DATA_RECORD KEY REC
  REC = REC || ';' || REC
  KEY = 'SemicolonB'
  CALL TEST_DATA_RECORD KEY REC
  REC = '1~2~3~4~5~6~7~8~9~0'
  KEY = 'Tilde0'
  CALL TEST_DATA_RECORD KEY REC
  REC = 'A~B~C~D~E~F~G~H~I~J~K~L~M~N~O~P~Q~R~S~T~U~V~W~X~Y~Z'
  KEY = 'TildeA'
  CALL TEST_DATA_RECORD KEY REC
  REC = REC || '~' || REC
  KEY = 'TildeB'
  CALL TEST_DATA_RECORD KEY REC
  REC = 'This record has a blank field.||Right there, the line above.'
  KEY = 'BlankRow'
  CALL TEST_DATA_RECORD KEY REC
  REC = 'This record is just a little bit of plain text.'
  KEY = 'PlainText'
  CALL TEST_DATA_RECORD KEY REC
  REC = 'This record=Has a really long row that will end up getting truncated on some monitors. But BRDS manages to handle this without issue.=0=1=2=3=4=5=6=7=8=9=0=A=B=C=D=E=F=G=You get the idea.'
  KEY = 'LongRow'
  CALL TEST_DATA_RECORD KEY REC
  RETURN

/* Recreate a test record. */
TEST_DATA_RECORD: PROCEDURE EXPOSE TEST_DATA_FILE
  PARSE ARG KEY REC
  EXEC CICS DELETE  FILE(TEST_DATA_FILE)            RIDFLD(KEY) END-EXEC
  EXEC CICS WRITE   FILE(TEST_DATA_FILE)  FROM(REC) RIDFLD(KEY) END-EXEC
  RETURN


DEBUG_INFO: PROCEDURE EXPOSE FIELDS. SCR. SET.
  OUTPUT = LEFT('SET. - Settings. (Press ENTER to continue)', SET.WIDTH)
  LINES = 1
  DO TAIL OVER SET.
    TAIL_WIDTH = LENGTH(TAIL)
    ROW = TAIL '=' SET.TAIL
    OUTPUT = OUTPUT || LEFT(ROW, SET.WIDTH)
    LINES = LINES + 1
    IF LINES >= SET.HEIGHT THEN DO
      EXEC CICS SEND TEXT FROM(OUTPUT) ERASE END-EXEC
      IF C2X(EIBAID) = 'F3' THEN RETURN
      OUTPUT = ''
      LINES=0
    END
  END
  EXEC CICS SEND TEXT FROM(OUTPUT) ERASE END-EXEC
  IF C2X(EIBAID) = 'F3' THEN RETURN

  LINES = 1
  OUTPUT = LEFT('SCR. - Screen data. (Press ENTER to continue)', SET.WIDTH)
  DO TAIL OVER SCR.
    TAIL_WIDTH = LENGTH(TAIL)
    ROW = TAIL '=' SCR.TAIL
    OUTPUT = OUTPUT || LEFT(ROW, SET.WIDTH)
    LINES = LINES + 1
    IF LINES >= SET.HEIGHT THEN DO
      EXEC CICS SEND TEXT FROM(OUTPUT) ERASE END-EXEC
      IF C2X(EIBAID) = 'F3' THEN RETURN
      OUTPUT = ''
      LINES=0
    END
  END
  EXEC CICS SEND TEXT FROM(OUTPUT) ERASE END-EXEC
  IF C2X(EIBAID) = 'F3' THEN RETURN

  LINES = 1
  OUTPUT = LEFT('FIELDS. - Parsed fields. (Press ENTER to continue)', SET.WIDTH)
  DO TAIL OVER FIELDS.
    TAIL_WIDTH = LENGTH(TAIL)
    ROW = TAIL '=' FIELDS.TAIL
    OUTPUT = OUTPUT || LEFT(ROW, SET.WIDTH)
    LINES = LINES + 1
    IF LINES >= SET.HEIGHT THEN DO
      EXEC CICS SEND TEXT FROM(OUTPUT) ERASE END-EXEC
      IF C2X(EIBAID) = 'F3' THEN RETURN
      OUTPUT = ''
      LINES=0
    END
  END
  EXEC CICS SEND TEXT FROM(OUTPUT) ERASE END-EXEC
  RETURN
