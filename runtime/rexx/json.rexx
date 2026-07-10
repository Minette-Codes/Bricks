ADDRESS CICS

/* See the file 'JSON.md' for documentation. */

/* Simple test JSON from the documentation. */
REC = '["This", {"is": "JSON!"}, [1234, null, true, "String."]]'

/* Check for JSON passed on the command line or in COMMAREA. */
EXEC CICS RECEIVE INTO(BUF) END-EXEC
PARSE VAR BUF TID CKEY
IF CKEY \= '' THEN
  REC = CKEY
ELSE IF EIBCALEN > 0 THEN
  REC = DFHCOMMAREA

CALL JSON_PARSE REC

/* Fetch and parse the Bricks metrics. */
/* This requires metrics be enabled in the configuration file "bricks.cnf". */
/* CALL JSON_GET "http://localhost:9000/metrics" */

/* Open the JSON Explorer console. */
CALL JSON_CONSOLE

EXIT

/* Top of JSON Library. */

/* JSON Parser Interface ================================================ */

/* Parse JSON, placing it into the STEM JSON.                             */
/* Returns the position in the string parsing ended.                      */
/*                                                                        */
/* Arguments:                                                             */
/*  REC     - The JSON string to parse.                                   */
/*                                                                        */
/* Returns:                                                               */
/*  The position in the JSON string where parsing stopped.                */
/*  -10 if there is nothing to parse or expected end of JSON.             */
/*  Any other negative value from parsing.                                */
JSON_PARSE: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('Nothing to parse.', -10)
  REC = ARG(1)

  /* Reset the JSON STEM. */
  JSON. = ''
  CALL JSON_CLEAR

  /* Save the JSON text and length. */
  /* Simplifies the parsing a bit. */
  JSON._JSON = REC
  JSON._LEN = LENGTH(REC)
  IF JSON._LEN = 0 THEN
    RETURN _JSON_SET_ERROR('Nothing to parse.', -10)

  /* Do the parsing. */
  INDX = _JSON_PARSE_ELEMENT('JSON', 1)

  /* Parsing error. */
  IF INDX < 0 THEN
    RETURN INDX

  /* Successful! */
  JSON._END = INDX
  RETURN INDX

/* Reset the JSON STEM. */
JSON_CLEAR: PROCEDURE EXPOSE JSON.
  /* Clear any old data. */
  DO TAIL OVER JSON.
    INTERPRET 'DROP JSON.' || TAIL
  END

  /* Set the pointer to the root and set the type to null. */
  JSON._PTR = 'JSON'
  CALL _JSON_SET_TYPE JSON._PTR, 'U'
  RETURN 1

/* Return the error text. */
JSON_ERROR_TEXT: PROCEDURE EXPOSE JSON.
  IF JSON._ERROR = '' THEN
    RETURN ''
  RETURN JSON._ERROR

/* Return the error code. */
JSON_ERROR_CODE: PROCEDURE EXPOSE JSON.
  IF JSON._ERRORCODE = '' THEN
    RETURN 0
  RETURN JSON._ERRORCODE

/* GET JSON from a URL then parse it.                                     */
/*                                                                        */
/* Arguments:                                                             */
/*  URL     - The URL to GET.                                             */
/*            To use a URIMAP name format it as: MAP:MAP_NAME/PATH        */
/*            Optional if a URL was previously passed.                    */
/*                                                                        */
/* Returns:                                                               */
/*  -30 Error parsing the given URL.                                      */
/*  -31 Error opening a connection to the host in the URL.                */
/*  -32 Error sending the HTTP request to the given URL.                  */
JSON_GET: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    IF JSON._URL = '' THEN
      RETURN _JSON_SET_ERROR('Nothing to get.', -20)
    ELSE
      URL = JSON._URL
  ELSE
    URL = ARG(1)

  /* TODO: Handle authentication. */

  IF ABBREV(UPPER(URL), 'MAP:') THEN DO
    /* Handle MAP://URIMAP/PATH?QUERY format as a convenience. */
    NEW_URL = SUBSTR(URL, 5)
    IF ABBREV(NEW_URL, '//') THEN
      NEW_URL = SUBSTR(NEW_URL, 3)

    /* Check for a path. */
    URL_PATH = '/'
    PATH_POS = POS('/', NEW_URL)
    IF PATH_POS > 0 THEN DO
      URL_PATH = SUBSTR(NEW_URL, PATH_POS)
      NEW_URL = SUBSTR(NEW_URL, 1, PATH_POS - 1)
    END
    MAP_NAME = NEW_URL

    /* And check for a query string. */
    URL_QUERY = ''
    QUERY_POS = POS('?', NEW_URL)
    IF QUERY_POS > 0 THEN DO
      URL_QUERY = SUBSTR(NEW_URL, QUERY_POS)
      NEW_URL = SUBSTR(NEW_URL, 1, QUERY_POS - 1)
    END

    /* Finally open the connection. */
    EXEC CICS WEB OPEN
      URIMAP(MAP_NAME)
      SESSTOKEN(SES_TOKEN)
    END-EXEC
    IF EIBRESP \= 0 THEN
      RETURN _JSON_SET_ERROR('Error opening a connection to the URIMAP:' MAP_NAME 'RC:' EIBRESP, -31)
  END
  ELSE DO
    /* Otherwise process as a normal URL. */
    EXEC CICS WEB PARSE URL
      URL(URL)
      SCHEMENAME(URL_SCHEME)
      HOST(URL_HOST)
      PORT(URL_PORT)
      PATH(URL_PATH)
      QUERYSTRING(URL_QUERY)
    END-EXEC
    IF EIBRESP \= 0 | URL_HOST = '' THEN
      RETURN _JSON_SET_ERROR('Error parsing the URL:' EIBRESP, -30)

    EXEC CICS WEB OPEN
      HOST(URL_HOST)
      PORT(URL_PORT)
      SCHEME(URL_SCHEME)
      SESSTOKEN(SES_TOKEN)
    END-EXEC
    IF EIBRESP \= 0 THEN
      RETURN _JSON_SET_ERROR('Error opening a connection to the host:' EIBRESP, -31)
  END

  EXEC CICS WEB CONVERSE
    SESSTOKEN(SES_TOKEN)
    METHOD('GET')
    PATH(URL_PATH)
    QUERYSTRING(URL_QUERY)
    MEDIATYPE('text/json')
    INTO(REC)
    STATUSCODE(STATUS_CODE)
  END-EXEC
  JSON._STATUS = STATUS_CODE
  JSON._URL = URL
  IF EIBRESP \= 0 & STATUS_CODE \= '200' THEN
    RETURN _JSON_SET_ERROR('Error sending the HTTP request:' EIBRESP 'Status:' STATUS_CODE, -32)

  EXEC CICS WEB CLOSE SESSTOKEN(SES_TOKEN) END-EXEC

  RC = JSON_PARSE(REC)
  JSON._STATUS = STATUS_CODE
  JSON._URL = URL
  RETURN RC

/* Return the position in the original JSON string where parsing stopped. */
JSON_PARSE_END: PROCEDURE EXPOSE JSON.
  RETURN JSON._END

/* JSON Public Interface ================================================ */

/* Returns the number of elements in the current array or object.         */
/* Or at a given path.                                                    */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the count for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  The number of elements.                                               */
/*  -21 if the current element is not an array or object.                 */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_COUNT: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_COUNT')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  TYPE = VALUE(POINTER || '.TYPE')
  IF TYPE \= 'A' & TYPE \= 'O' THEN
    RETURN _JSON_SET_ERROR('JSON_COUNT() requires an array or object.', -21)

  RETURN VALUE(POINTER || '.0')

/* Returns the depth of the current element or a given path.              */
/* 1 for root level.                                                      */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the count for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  The depth.                                                            */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_DEPTH: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_DEPTH')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN COUNTSTR('.', POINTER) + 1

/* Return a list of members in the current object.                        */
/* If no separator is specified the default is space.                     */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to list members for. Optional.        */
/*  SEP     - A separator to use in the returned list. Optional.          */
/*                                                                        */
/* Returns:                                                               */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_LIST: PROCEDURE EXPOSE JSON.
  SEP = ' '
  POINTER = JSON._PTR

  IF ARG() = 2 THEN DO
    POINTER = ARG(1)
    SEP = ARG(2)
  END
  ELSE IF ARG() = 1 THEN DO
    TEMP = ARG(1)
    IF LENGTH(TEMP) = 1 THEN
      SEP = TEMP
    ELSE IF LENGTH(TEMP) > 1 THEN
      POINTER = TEMP
  END

  IF POINTER \= JSON._PTR THEN DO
    POINTER = _JSON_PATH_RESOLVE(POINTER, 'JSON_LIST')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  TYPE = VALUE(POINTER || '.TYPE')
  IF TYPE \= 'O' THEN
    RETURN _JSON_SET_ERROR('JSON_LIST() requires an object.', -21)

  /* Loop over the object and build the list. */
  LIST = ''
  COUNT = VALUE(POINTER || '.0')
  DO INDX = 1 TO COUNT
    IF INDX > 1 THEN
      LIST = LIST || SEP
    LIST = LIST || VALUE(POINTER || '.' || INDX || '.MEMBER')
  END
  RETURN LIST

/* Moves the pointer to the given member name in the current object.      */
/*                                                                        */
/* Arguments:                                                             */
/*  MEMBER  - The member name to move the pointer to.                     */
/*                                                                        */
/* Returns:                                                               */
/*  The index of the new element.                                         */
/*  -20 - The member name is blank.                                       */
/*  -21 - The current element is an object.                               */
/*  -26 - The member is not found.                                        */
JSON_MEMBER: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 | ARG(1) = '' THEN
    RETURN _JSON_SET_ERROR('JSON_MEMBER() requires an member name.', -20)
  MEMBER = ARG(1)

  POINTER = _JSON_FIND_MEMBER(JSON._PTR, MEMBER)
  IF POINTER <= 0 THEN
    RETURN _JSON_SET_ERROR('JSON_MEMBER(MEMBER)' JSON._ERROR, POINTER)
  POINTER = JSON._PTR || '.' || POINTER

  TYPE = VALUE(JSON._PTR || '.TYPE')
  IF TYPE \= 'O' THEN
    RETURN _JSON_SET_ERROR('JSON_MEMBER() requires an object.', -21)
  JSON._PTR = POINTER
  RETURN SUBSTR(JSON._PTR, LASTPOS('.', JSON._PTR) + 1)

/* Returns the name of the current member or a given path.                */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the name for. Optional.        */
/*                                                                        */
/* Returns:                                                               */
/*  The value of the current element or path.                             */
/*  -21 if the current element is an array or object.                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member is not found.                                       */
JSON_NAME: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NAME')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  PARENT = SUBSTR(POINTER, 1, LASTPOS('.', POINTER) - 1)
  PARENT_TYPE = VALUE(PARENT || '.TYPE')
  IF PARENT_TYPE \= 'O' THEN
    RETURN _JSON_SET_ERROR('JSON_NAME() requires an object.', -21)
  RETURN VALUE(POINTER || '.MEMBER')

/* Move the pointer to the next element in an array or object.            */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to set the pointer to. Optional.      */
/*                                                                        */
/* Returns:                                                               */
/*  The index of the next element.                                        */
/*  If a path is given returns the new path.                              */
/*  0 if the pointer or path are already at the last element.             */
/*  -21 if the current element is not an array or object.                 */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEXT: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  MODE = 'PTR'

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NEXT')
    IF POINTER <= 0 THEN
      RETURN POINTER
    MODE = 'PATH'
  END

  IF POINTER = 'JSON' THEN
    RETURN _JSON_SET_ERROR('JSON_NEXT() does not work at the root.', -21)

  PARENT = SUBSTR(POINTER, 1, LASTPOS('.', POINTER) - 1)
  INDX = SUBSTR(POINTER, LASTPOS('.', POINTER) + 1)
  PARENT_TYPE = VALUE(PARENT || '.TYPE')

  IF PARENT_TYPE \= 'A' & PARENT_TYPE \= 'O' THEN
    RETURN _JSON_SET_ERROR('JSON_NEXT() requires an array or object.', -21)

  /* Is this element the last one? */
  IF INDX >= VALUE(PARENT || '.0') THEN
    RETURN 0
  INDX = INDX + 1

  /* Move the pointer. */
  JSON._PTR = PARENT || '.' || INDX

  IF MODE = 'PTR' THEN
    /* Return the new index. */
    RETURN INDX
  ELSE IF MODE = 'PATH' THEN
    /* Return the new path. */
    RETURN SUBSTR(PARENT || '.' || INDX, 5)
  ELSE
    RETURN _JSON_SET_ERROR('FATAL ERROR IN JSON_NEXT', -1)

/* Moves the pointer to the given path, if provided.                      */
/* Returns the path to the current element.                               */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to set the pointer to. Optional.      */
/*                                                                        */
/* Returns:                                                               */
/*  The current or new path.                                              */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_PATH: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_PATH')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  IF POINTER \= JSON._PTR THEN
    JSON._PTR = POINTER
  PATH = SUBSTR(JSON._PTR, 5)
  IF PATH = '' THEN
    PATH = '.'
  RETURN PATH

/* Moves the pointer to the parent of the current element.                */
/*                                                                        */
/* Returns:                                                               */
/*  The new depth. 1 is for the root level.                               */
/*  -22 if already at the root level.                                     */
JSON_PARENT: PROCEDURE EXPOSE JSON.
  IF JSON._PTR = 'JSON' THEN
    RETURN _JSON_SET_ERROR('JSON_PARENT() Already at the root', -22)
  JSON._PTR = SUBSTR(JSON._PTR, 1, LASTPOS('.', JSON._PTR) - 1)
  RETURN JSON_DEPTH()

/* Pretty Print the JSON. */
/* Turns the JSON into an array. */
/* From there it is up to you to make use of it. */
/*                                                                        */
/* Arguments:                                                             */
/*  INDENT  - The number of characters to indent each element.            */
/*            Defaults to 1. Optional.                                    */
JSON_PRETTY: PROCEDURE EXPOSE JSON.
  INDENT = 1
  IF ARG() > 0 & ARG(1) \= '' THEN
    INDENT = ARG(1)

  /* Clear any previous pretty print data. */
  IF JSON._PP.0 \= '' THEN DO
    DO INDX = 1 TO JSON._PP.0
      INTERPRET 'DROP JSON._PP.' || INDX
    END
  END

  JSON._PP.0 = 0
  RETURN _JSON_PP_ELEMENT('JSON', 0, INDENT)

/* Move the pointer to the previous element in an array.                  */
/*                                                                        */
/* Returns:                                                               */
/*  The index of the previous element.                                    */
/*  0 if the pointer is already at the first element.                     */
/*  -21 if the current element is not an array or object.                 */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_PREV: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  MODE = 'PTR'

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_PREV')
    IF POINTER <= 0 THEN
      RETURN POINTER
    MODE = 'PATH'
  END

  IF POINTER = 'JSON' THEN
    RETURN _JSON_SET_ERROR('JSON_PREV() does not work at the root.', -21)

  PARENT = SUBSTR(POINTER, 1, LASTPOS('.', POINTER) - 1)
  INDX = SUBSTR(POINTER, LASTPOS('.', POINTER) + 1)
  PARENT_TYPE = VALUE(PARENT || '.TYPE')

  IF PARENT_TYPE \= 'A' & PARENT_TYPE \= 'O' THEN
    RETURN _JSON_SET_ERROR('JSON_PREV() requires an array or object.', -21)

  /* Is this element the last one? */
  IF INDX = 1 THEN
    RETURN 0
  INDX = INDX - 1

  /* Move the pointer. */
  JSON._PTR = PARENT || '.' || INDX

  IF MODE = 'PTR' THEN
    /* Return the new index. */
    RETURN INDX
  ELSE IF MODE = 'PATH' THEN
    /* Return the new path. */
    RETURN SUBSTR(PARENT || '.' || INDX, 5)
  ELSE
    RETURN _JSON_SET_ERROR('FATAL ERROR IN JSON_PREV', -1)

/* Move the pointer to the root. */
/*                                                                        */
/* Returns:                                                               */
/*  1 for success.                                                        */
JSON_ROOT: PROCEDURE EXPOSE JSON.
  JSON._PTR = 'JSON'
  RETURN 1

/* Transforms JSON back into a string.                                    */
/*                                                                        */
/* Returns:                                                               */
/*  A string representation of the parsed JSON.                           */
JSON_STRING: PROCEDURE EXPOSE JSON.
  RETURN _JSON_STRING_ELEMENT('JSON')

/* Returns the type of the current element or a given path.               */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the type for. Optional.        */
/*                                                                        */
/* Returns:                                                               */
/*  The element type. See the table Types: above.                         */
/*  Returns '' if there is an error.                                      */
JSON_TYPE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_TYPE')
    IF POINTER <= 0 THEN
      RETURN ''
  END

  RETURN VALUE(POINTER || '.TYPE')

/* Returns the value of the current element or a given path.              */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the value for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  The value of the current element or path.                             */
/*  Returns '' if there is an error.                                      */
JSON_VALUE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_VALUE')
    IF POINTER <= 0 THEN
      RETURN ''
  END

  TYPE = VALUE(POINTER || '.TYPE')
  IF TYPE = 'A' | TYPE = 'O' THEN DO
    CALL _JSON_SET_ERROR 'JSON_VALUE() does not work with arrays or objects.', -21
    RETURN ''
  END

  IF TYPE = 'S' THEN
    RETURN JSON_UNESCAPE(VALUE(POINTER || '.VALUE'))

  RETURN VALUE(POINTER || '.VALUE')

/* JSON Type Checks ===================================================== */

/* Returns true if the current element or a given path is an Array.       */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the value for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  True if the element is an Array.                                      */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_IS_ARRAY: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_IS_ARRAY')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN VALUE(POINTER || '.TYPE') = 'A'

/* Returns true if the current element or a given path is an Object.      */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the value for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  True if the element is an Object.                                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_IS_OBJECT: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_IS_OBJECT')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN VALUE(POINTER || '.TYPE') = 'O'

/* Returns true if the current element or a given path is a Number.       */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the value for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  True if the element is a Number.                                      */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_IS_NUMBER: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_IS_NUMBER')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN VALUE(POINTER || '.TYPE') = 'N'

/* Returns true if the current element or a given path is a String.       */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the value for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  True if the element is a String.                                      */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_IS_STRING: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_IS_STRING')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN VALUE(POINTER || '.TYPE') = 'S'

/* Returns true if the current element or a given path is True.           */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the value for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  True if the element is True.                                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_IS_TRUE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_IS_TRUE')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN VALUE(POINTER || '.TYPE') = 'T'

/* Returns true if the current element or a given path is False.          */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the value for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  True if the element is False.                                         */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_IS_FALSE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_IS_FALSE')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN VALUE(POINTER || '.TYPE') = 'F'

/* Returns true if the current element or a given path is Null.           */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the value for. Optional.       */
/*                                                                        */
/* Returns:                                                               */
/*  True if the element is Null.                                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_IS_NULL: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_IS_NULL')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN VALUE(POINTER || '.TYPE') = 'U'

/* JSON Permutation Interface =========================================== */

/* Adds a new element to an array.                                        */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an array.                           */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_ADD: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_ADD')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  TYPE = VALUE(POINTER || '.TYPE')
  IF TYPE \= 'A' THEN
    RETURN _JSON_SET_ERROR('JSON_ADD() requires an array.', -21)

  RETURN _JSON_ADD(POINTER)

/* Deletes the current element and children.                              */
/* Renumbers elements for arrays and objects.                             */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to delete. Optional.                               */
/*                                                                        */
/* Returns:                                                               */
/*  1 for success                                                         */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_DELETE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_COUNT')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  /* Root level is handled differently. */
  IF POINTER = 'JSON' THEN DO
    /* Just delete it all. */
    CALL JSON_CLEAR
    RETURN 1
  END

  /* Things we need. */
  PARENT = SUBSTR(POINTER, 1, LASTPOS('.', POINTER) - 1)
  PARENT_TYPE = VALUE(PARENT || '.TYPE')
  DEL_INDX = SUBSTR(POINTER, LASTPOS('.', POINTER) + 1)

  /* Drop the current element and children. */
  DO TAIL OVER JSON.
    FULL_TAIL = 'JSON.' || TAIL
    IF ABBREV(FULL_TAIL, POINTER) THEN
      INTERPRET 'DROP' FULL_TAIL
  END

  /* Update the pointer. */
  IF POINTER = JSON._PTR THEN
    JSON._PTR = PARENT

  /* Extra work if the parent is an array or object. */
  IF PARENT_TYPE = 'A' | PARENT_TYPE = 'O' THEN DO
    /* Renumber the elements. */
    CALL _JSON_RENUMBER PARENT, DEL_INDX

    /* Adjust the count. */
    COUNT = VALUE(PARENT || '.0')
    CALL VALUE PARENT || '.0', COUNT - 1
  END
  RETURN 1

/* Adds a new element to an object.                                       */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*  NAME    - The name for the new member.                                */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEW: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_NEW() Member name required', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NEW')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NAME = ARG(2)
  END
  ELSE
    NAME = ARG(1)

  IF NAME = '' THEN
    RETURN _JSON_SET_ERROR('JSON_NEW() Member name must not be blank.', -20)

  TYPE = VALUE(POINTER || '.TYPE')
  IF TYPE \= 'O' THEN
    RETURN _JSON_SET_ERROR('JSON_NEW() requires an object.', -21)

  RETURN _JSON_NEW(POINTER, NAME)

/* Set the type of the current element.                                   */
/* Prepares the new element according to the type.                        */
/* See the table Types: above.                                            */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to add the new element. Optional.                */
/*  NEW_TYPE  - The new type for the current element.                     */
/*                                                                        */
/* Returns:                                                               */
/*  The old type value.                                                   */
/*  -20 if the required type is not provided.                             */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_SET_TYPE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NEW_TYPE = UPPER(ARG(1))

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_SET_TYPE(TYPE) requires a type.', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_SET_TYPE')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NEW_TYPE = UPPER(ARG(2))
  END

  /* If the long type name is given turn it into the type code. */
  IF NEW_TYPE = 'NULL' THEN
    NEW_TYPE = 'U'
  ELSE IF LENGTH(NEW_TYPE) > 1 THEN
    NEW_TYPE = SUBSTR(NEW_TYPE, 1, 1)

  IF POS(NEW_TYPE, 'AFNOSTU') < 1 | LENGTH(NEW_TYPE) \= 1 THEN
    RETURN _JSON_SET_ERROR('JSON_SET_TYPE() requires a VALID type. (AFNOSTU)' , -21)

  /* Set the type, returning the old type. */
  RETURN _JSON_SET_TYPE(POINTER, NEW_TYPE)

/* Set the value of the current element. */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to add the new element. Optional.                */
/*  NEW_VALUE - The new value for the current element.                    */
/*                                                                        */
/* Returns:                                                               */
/*  1 on success.                                                         */
/*  -20 if the required value is not provided.                            */
/*  -21 if the current element is an array or object.                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_SET_VALUE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NEW_VALUE = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_SET_VALUE(VALUE) requires a value', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_SET_VALUE')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NEW_VALUE = ARG(2)
  END

  /* Is the new value quoted? */
  IF ABBREV(NEW_VALUE, '"') | ABBREV(NEW_VALUE, "'") THEN DO
    END_QUOTE = _JSON_STRING_END(NEW_VALUE)
    IF END_QUOTE < 0 THEN DO
      RETURN _JSON_SET_ERROR('JSON_SET_VALUE(VALUE)' JSON._ERROR, END_QUOTE)
      RETURN END_QUOTE
    END
      NEW_VALUE = SUBSTR(NEW_VALUE, 2, END_QUOTE - 2)
  END

  TYPE = VALUE(POINTER || '.TYPE')
  IF TYPE = 'A' | TYPE = 'O' THEN
    RETURN _JSON_SET_ERROR('JSON_SET_VALUE() does not work with arrays or objects.', -21)

  CALL VALUE POINTER || '.VALUE', JSON_ESCAPE(NEW_VALUE)
  RETURN 1

/* JSON Permutation Shortcuts =========================================== */

/* Adds a new array element to an array.                                  */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an array.                           */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_ADD_ARRAY: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_ADD_ARRAY')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  /* Setup the new element. */
  INDX = _JSON_ADD(POINTER)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'A')
  RETURN INDX

/* Adds a new object element to an array.                                 */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an array.                           */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_ADD_OBJECT: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_ADD_OBJECT')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  /* Setup the new element. */
  INDX = _JSON_ADD(POINTER)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'O')
  RETURN INDX

/* Adds a new string to an array.                                         */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new string. Optional.                   */
/*  VALUE   - The string value for the new element.                     */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an array.                           */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_ADD_STRING: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  VALUE = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_ADD_STRING() requires a string', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_ADD_STRING')
    IF POINTER <= 0 THEN
      RETURN POINTER
    VALUE = ARG(2)
  END

  /* Setup the new element. */
  INDX = _JSON_ADD(POINTER)
  CALL VALUE POINTER || '.' || INDX || '.TYPE', 'S'
  CALL VALUE POINTER || '.' || INDX || '.VALUE', JSON_ESCAPE(VALUE)
  RETURN INDX

/* Adds a new number to an array.                                         */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new number. Optional.                   */
/*  VALUE   - The number value for the new element.                     */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an array.                           */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_ADD_NUMBER: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  VALUE = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_ADD_NUMBER() requires a number', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_ADD_NUMBER')
    IF POINTER <= 0 THEN
      RETURN POINTER
    VALUE = ARG(2)
  END

  /* Setup the new element. */
  INDX = _JSON_ADD(POINTER)
  CALL VALUE POINTER || '.' || INDX || '.TYPE', 'N'
  CALL VALUE POINTER || '.' || INDX || '.VALUE', VALUE
  RETURN INDX

/* Adds a new true element to an array.                                   */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an array.                           */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_ADD_TRUE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_ADD_TRUE')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  /* Setup the new element. */
  INDX = _JSON_ADD(POINTER)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'T')
  RETURN INDX

/* Adds a new false element to an array.                                  */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an array.                           */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_ADD_FALSE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_ADD_FALSE')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  /* Setup the new element. */
  INDX = _JSON_ADD(POINTER)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'F')
  RETURN INDX

/* Adds a new null element to an array.                                   */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an array.                           */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_ADD_NULL: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_ADD_NULL')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  /* Setup the new element. */
  INDX = _JSON_ADD(POINTER)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'U')
  RETURN INDX

/* Adds a new array element to an object.                                 */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*  NAME    - The name for the new member.                                */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEW_ARRAY: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NAME = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_NEW_ARRAY() Member name required', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NEW_ARRAY')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NAME = ARG(2)
  END

  /* Setup the new element. */
  INDX = _JSON_NEW(POINTER, NAME)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'A')

/* Adds a new object element to an object.                                */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*  NAME    - The name for the new member.                                */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEW_OBJECT: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NAME = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_NEW_OBJECT() Member name required', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NEW_OBJECT')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NAME = ARG(2)
  END

  /* Setup the new element. */
  INDX = _JSON_NEW(POINTER, NAME)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'O')

/* Adds a new string element to an object.                                */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*  NAME    - The name for the new member.                                */
/*  VALUE   - The  string value for the new element.                    */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEW_STRING: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NAME = ARG(1)
  VALUE = ARG(2)

  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('JSON_NEW_STRING() Member name and value required', -20)
  IF ARG() > 2 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NEW_STRING')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NAME = ARG(2)
    VALUE = ARG(3)
  END

  /* Setup the new element. */
  INDX = _JSON_NEW(POINTER, NAME)
  CALL VALUE POINTER || '.' || INDX || '.TYPE', 'S'
  CALL VALUE POINTER || '.' || INDX || '.VALUE', JSON_ESCAPE(VALUE)
  RETURN INDX

/* Adds a new number element to an object.                                */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*  NAME    - The name for the new member.                                */
/*  VALUE   - The number value for the new element.                     */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEW_NUMBER: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NAME = ARG(1)
  VALUE = ARG(2)

  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('JSON_NEW_NUMBER() Member name and value required', -20)
  IF ARG() > 2 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NEW_NUMBER')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NAME = ARG(2)
    VALUE = ARG(3)
  END

  /* Setup the new element. */
  INDX = _JSON_NEW(POINTER, NAME)
  CALL VALUE POINTER || '.' || INDX || '.TYPE', 'N'
  CALL VALUE POINTER || '.' || INDX || '.VALUE', VALUE
  RETURN INDX

/* Adds a new true element to an object.                                  */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*  NAME    - The name for the new member.                                */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEW_TRUE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NAME = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_NEW_TRUE() Member name required', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NEW_TRUE')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NAME = ARG(2)
  END

  /* Setup the new element. */
  INDX = _JSON_NEW(POINTER, NAME)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'T')

/* Adds a new false element to an object.                                 */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*  NAME    - The name for the new member.                                */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEW_FALSE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NAME = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_NEW_FALSE() Member name required', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NEW_FALSE')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NAME = ARG(2)
  END

  /* Setup the new element. */
  INDX = _JSON_NEW(POINTER, NAME)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'F')

/* Adds a new null element to an object.                                  */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element. Optional.                  */
/*  NAME    - The name for the new member.                                */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEW_NULL: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NAME = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_NEW_NULL() Member name required', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_NEW_NULL')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NAME = ARG(2)
  END

  /* Setup the new element. */
  INDX = _JSON_NEW(POINTER, NAME)
  RETURN _JSON_SET_TYPE(POINTER || '.' || INDX, 'N')

/* Set the current element type to array.                                 */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to element to be modified. Optional.             */
/*                                                                        */
/* Returns:                                                               */
/*  The old type value.                                                   */
/*  -20 if the required value is not provided.                            */
/*  -21 if the current element is an array or object.                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_SET_ARRAY: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_SET_ARRAY')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN _JSON_SET_TYPE(POINTER, 'A')

/* Set the current element type to object.                                */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to element to be modified. Optional.             */
/*                                                                        */
/* Returns:                                                               */
/*  The old type value.                                                   */
/*  -20 if the required value is not provided.                            */
/*  -21 if the current element is an array or object.                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_SET_OBJECT: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_SET_OBJECT')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN _JSON_SET_TYPE(POINTER, 'O')

/* Set the current element type to string and set the value.              */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to element to be modified. Optional.             */
/*  NEW_VALUE - The new string value for the current element.             */
/*                                                                        */
/* Returns:                                                               */
/*  The old type value.                                                   */
/*  -20 if the required value is not provided.                            */
/*  -21 if the current element is an array or object.                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_SET_STRING: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NEW_VALUE = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_SET_STRING() requires a string', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_SET_STRING')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NEW_VALUE = ARG(2)
  END

  /* Is the new value quoted? */
  IF ABBREV(NEW_VALUE, '"') | ABBREV(NEW_VALUE, "'") THEN DO
    END_QUOTE = _JSON_STRING_END(NEW_VALUE)
    IF END_QUOTE < 0 THEN DO
      RETURN _JSON_SET_ERROR('JSON_SET_STRING(STRING)' JSON._ERROR, END_QUOTE)
      RETURN END_QUOTE
    END
      NEW_VALUE = SUBSTR(NEW_VALUE, 2, END_QUOTE - 2)
  END

  OLD_TYPE = VALUE(POINTER || '.TYPE')
  CALL VALUE POINTER || '.TYPE', 'S'
  CALL VALUE POINTER || '.VALUE', JSON_ESCAPE(NEW_VALUE)
  RETURN OLD_TYPE

/* Set the current element type to number and set the value.              */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to element to be modified. Optional.             */
/*  NEW_VALUE - The new number value for the current element.             */
/*                                                                        */
/* Returns:                                                               */
/*  The old type value.                                                   */
/*  -20 if the required value is not provided.                            */
/*  -21 if the current element is an array or object.                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_SET_NUMBER: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR
  NEW_VALUE = ARG(1)

  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('JSON_SET_NUMBER() requires a value', -20)
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_SET_NUMBER')
    IF POINTER <= 0 THEN
      RETURN POINTER
    NEW_VALUE = ARG(2)
  END

  OLD_TYPE = VALUE(POINTER || '.TYPE')
  CALL VALUE POINTER || '.TYPE', 'N'
  CALL VALUE POINTER || '.VALUE', JSON_ESCAPE(NEW_VALUE)
  RETURN OLD_TYPE

/* Set the current element type to true.                                  */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to element to be modified. Optional.             */
/*                                                                        */
/* Returns:                                                               */
/*  The old type value.                                                   */
/*  -20 if the required value is not provided.                            */
/*  -21 if the current element is an array or object.                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_SET_TRUE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_SET_TRUE')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN _JSON_SET_TYPE(POINTER, 'T')

/* Set the current element type to false.                                 */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to element to be modified. Optional.             */
/*                                                                        */
/* Returns:                                                               */
/*  The old type value.                                                   */
/*  -20 if the required value is not provided.                            */
/*  -21 if the current element is an array or object.                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_SET_FALSE: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_SET_FALSE')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN _JSON_SET_TYPE(POINTER, 'F')

/* Set the current element type to null.                                  */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to element to be modified. Optional.             */
/*                                                                        */
/* Returns:                                                               */
/*  The old type value.                                                   */
/*  -20 if the required value is not provided.                            */
/*  -21 if the current element is an array or object.                     */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_SET_NULL: PROCEDURE EXPOSE JSON.
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_SET_NULL')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN _JSON_SET_TYPE(POINTER, 'U')

/* JSON Utilities ======================================================= */

/* Escape special characters in a string. */
JSON_ESCAPE: PROCEDURE
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR("JSON_ESCAPE() requires a string.", -20)
  STR = ARG(1)
  NEW_STR = ''

  DO INDX = 1 TO LENGTH(STR)
    CHR = SUBSTR(STR, INDX, 1)
    CHR_VALUE = C2D(CHR)
    IF CHR = '"' THEN
      CHR = '\"'
    ELSE IF CHR_VALUE = 7 THEN
      CHR = '\b'
    ELSE IF CHR_VALUE = 11 THEN
      CHR = '\f'
    ELSE IF CHR_VALUE = 10 THEN
      CHR = '\n'
    ELSE IF CHR_VALUE = 13 THEN
      CHR = '\r'
    ELSE IF CHR_VALUE = 9 THEN
      CHR = '\t'
    ELSE IF CHR_VALUE < 32 THEN
      CHR = '\u' || C2X(CHR)

    NEW_STR = NEW_STR || CHR
  END

  RETURN NEW_STR

/* Turn escaped characters in string to normal characters. */
JSON_UNESCAPE: PROCEDURE
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR("JSON_UNESCAPE() requires a string.", -20)

  /* Loop over the string looking for escapes. */
  STR = ARG(1)
  STR_LEN = LENGTH(STR)
  NEW_STR = ''
  INDX = 1
  DO FOREVER
    CHR = SUBSTR(STR, INDX, 1)
    IF CHR = '\' THEN DO
      INDX = INDX + 1
      CHR = SUBSTR(STR, INDX, 1)

    /* Decode the escaped character. */
      IF LOWER(CHR) = 'b' THEN
        CHR = X2C('07')
      ELSE IF LOWER(CHR) = 'f' THEN
        CHR = X2C('0C')
      ELSE IF LOWER(CHR) = 'n' THEN
        CHR = X2C('0A')
      ELSE IF LOWER(CHR) = 'r' THEN
        CHR = X2C('0D')
      ELSE IF LOWER(CHR) = 't' THEN
        CHR = X2C('09')
      ELSE IF LOWER(CHR) = 'u' THEN DO
        /* Get the hex digits to convert. */
        HEX = SUBSTR(STR, INDX + 1, 4)
        INDX = INDX + 4

        /* Drop the two leading digits since this isn't Unicode land. */
        HEX = SUBSTR(HEX, 3, 2)

        /* Finally convert the hex to a character. */
        CHR = X2C(HEX)
      END
    END
    NEW_STR = NEW_STR || CHR

    /* End of the JSON text? */
    INDX = INDX + 1
    IF INDX > STR_LEN THEN
      LEAVE
  END
  RETURN NEW_STR

/* Convert a single character type code to a string type name. */
JSON_TYPE_STRING: PROCEDURE
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR("JSON_TYPE_STRING(TYPE) requires a type.", -20)

  TYPE = UPPER(ARG(1))
  IF TYPE = 'A' THEN
    RETURN 'Array'
  IF TYPE = 'F' THEN
    RETURN 'false'
  IF TYPE = 'N' THEN
    RETURN 'Number'
  IF TYPE = 'O' THEN
    RETURN 'Object'
  IF TYPE = 'S' THEN
    RETURN 'String'
  IF TYPE = 'T' THEN
    RETURN 'true'
  IF TYPE = 'U' THEN
    RETURN 'null'
  RETURN '?'

/* JSON Internal Parsing ================================================ */

/* Parse a JSON Element                                                   */
/* Arguments:                                                             */
/*  STEM    - The STEM to store into.                                     */
/*  INDX    - Where to start in JSON._JSON.                               */
/*                                                                        */
/* Returns:                                                               */
/*  The new position in JSON._JSON.                                       */
/*  -11  if an unknown element type is encountered.                       */
_JSON_PARSE_ELEMENT: PROCEDURE EXPOSE JSON.
  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_PARSE_ELEMENT', -1)
  STEM = ARG(1)
  INDX = ARG(2)

  /* Skip over white space. */
  INDX =_JSON_SKIP_WHITESPACE(INDX, ',')
  CHR = SUBSTR(JSON._JSON, INDX, 1)

  IF INDX > JSON._LEN THEN
    RETURN INDX

  /* Comment. */
  IF CHR = '/' THEN DO
    RETURN _JSON_SKIP_COMMENT(INDX)
  END

  /* Array. */
  IF CHR = '[' THEN DO
    CALL VALUE STEM || '.TYPE', 'A'
    CALL VALUE STEM || '.0', 0
    RETURN _JSON_PARSE_ARRAY(STEM, INDX)
  END

  /* Object. */
  IF CHR = '{' THEN DO
    CALL VALUE STEM || '.TYPE', 'O'
    CALL VALUE STEM || '.0', 0
    RETURN _JSON_PARSE_OBJECT(STEM, INDX)
  END

  /* String. */
  IF CHR = '"' THEN DO
    INDX = INDX + 1
    END_OF_STR = _JSON_PARSE_STRING(INDX)
    IF END_OF_STR < 0 THEN
      RETURN END_OF_STR
    STR = SUBSTR(JSON._JSON, INDX, END_OF_STR - INDX)
    CALL VALUE STEM || '.TYPE', 'S'
    CALL VALUE STEM || '.VALUE', STR
    RETURN END_OF_STR + 1
  END

  /* Number. */
  IF POS(CHR, '-.0123456789') > 0 THEN DO
    END_OF_NUM = _JSON_PARSE_NUMBER(INDX)
    IF END_OF_NUM < 0 THEN
      RETURN END_OF_NUM
    NUM = SUBSTR(JSON._JSON, INDX, END_OF_NUM - INDX)
    CALL VALUE STEM || '.TYPE', 'N'
    CALL VALUE STEM || '.VALUE', NUM
    RETURN END_OF_NUM
  END

  /* true, false or null. */
  IF LOWER(SUBSTR(JSON._JSON, INDX, 4)) = 'true' THEN DO
    CALL VALUE STEM || '.TYPE', 'T'
    CALL VALUE STEM || '.VALUE', 'true'
    RETURN INDX + 4
  END
  IF LOWER(SUBSTR(JSON._JSON, INDX, 5)) = 'false' THEN DO
    CALL VALUE STEM || '.TYPE', 'F'
    CALL VALUE STEM || '.VALUE', 'false'
    RETURN INDX + 5
  END
  IF LOWER(SUBSTR(JSON._JSON, INDX, 4)) = 'null' THEN DO
    CALL VALUE STEM || '.TYPE', 'U'
    CALL VALUE STEM || '.VALUE', 'null'
    RETURN INDX + 4
  END

  /* No idea what this is. :shrug: */
  RETURN _JSON_SET_ERROR('Unknown element type at:' INDX, -11)

/* Skip over whitespace characters.                                       */
/*                                                                        */
/* Arguments:                                                             */
/*  INDX    - Where to start in JSON._JSON.                               */
/*  EXTRA   - An optional extra character to consider whitespace.         */
/*                                                                        */
/* Returns:                                                               */
/*  The new position in JSON._JSON.                                       */
_JSON_SKIP_WHITESPACE: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_SKIP_WHITESPACE', -1)
  INDX = ARG(1)
  EXTRA = ''
  IF ARG() > 1 THEN
    EXTRA = ARG(2)

  CHR = SUBSTR(JSON._JSON, INDX, 1)
  DO WHILE (_JSON_PARSE_IS_WHITESPACE(CHR) | CHR = EXTRA | CHR = '/') & INDX < JSON._LEN
    IF CHR = '/' THEN DO
      INDX = _JSON_SKIP_COMMENT(INDX)
      IF INDX < 0 THEN
        RETURN INDX
    END
    INDX = INDX + 1
    CHR = SUBSTR(JSON._JSON, INDX, 1)
  END
  RETURN INDX

/* Return 1 if the given character is whitespace. */
_JSON_PARSE_IS_WHITESPACE: PROCEDURE
  HEX = C2X(ARG(1))
  IF HEX = '09' | HEX = '0A' | HEX = '0D' | HEX = '020' THEN
    RETURN 1
  RETURN 0

/* Skip over a comment.                                                   */
/*                                                                        */
/* Arguments:                                                             */
/*  INDX    - Where to start in JSON._JSON.                               */
/*                                                                        */
/* Returns:                                                               */
/*  The new position in JSON._JSON.                                       */
_JSON_SKIP_COMMENT: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_SKIP_COMMENT', -1)
  INDX = ARG(1)

  IF SUBSTR(JSON._JSON, INDX, 2) = '//' THEN DO
    INDX = INDX + 2
    DO WHILE INDX < JSON._LEN
      CHR = SUBSTR(JSON._JSON, INDX, 1)
      IF CHR = X2C('0D') | CHR = X2C('0A') THEN
        RETURN INDX + 1
      INDX = INDX + 1
    END
    RETURN _JSON_SET_ERROR('Unexpected end of comment starting at:' START, -16)
  END

  IF SUBSTR(JSON._JSON, INDX, 2) = '/*' THEN DO
    INDX = INDX + 2
    DO WHILE INDX < JSON._LEN
      IF SUBSTR(JSON._JSON, INDX, 2) = '*/' THEN
        RETURN INDX + 1
      INDX = INDX + 1
    END
    RETURN _JSON_SET_ERROR('Unexpected end of comment starting at:' START, -16)
  END

  RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_SKIP_COMMENT', -1)

/* Parse a JSON Array.                                                    */
/*                                                                        */
/* Arguments:                                                             */
/*  STEM   - The STEM to store into.                                      */
/*  INDX   - Where to start in JSON._JSON.                                */
/*                                                                        */
/* Returns:                                                               */
/*  The new position in JSON._JSON.                                       */
_JSON_PARSE_ARRAY: PROCEDURE EXPOSE JSON.
  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_PARSE_ARRAY', -1)
  STEM = ARG(1)
  INDX = ARG(2)

  /* Get the array elements. */
  COUNT = 1
  INDX = INDX + 1
  DO FOREVER
    /* Skip over white space. */
    INDX =_JSON_SKIP_WHITESPACE(INDX, ',')
    IF INDX < 0 THEN
      RETURN INDX

    /* End of the array already? */
    IF SUBSTR(JSON._JSON, INDX, 1) = ']' THEN
      LEAVE

    /* Parse the element. */
    NEW_STEM = STEM || '.' || COUNT
    INDX = _JSON_PARSE_ELEMENT(NEW_STEM, INDX)
    IF INDX < 0 THEN
      RETURN INDX

    /* Save the element count. */
    CALL VALUE STEM || '.0', COUNT

    /* End of the JSON text? */
    IF INDX > JSON._LEN THEN
      LEAVE
    COUNT = COUNT + 1
  END

  IF SUBSTR(JSON._JSON, INDX, 1) \= ']' THEN
    RETURN _JSON_SET_ERROR('Expected closing array brace "]" at:' INDX, -12)

  RETURN INDX + 1

/* Parse a JSON Object.                                                   */
/*                                                                        */
/* Arguments:                                                             */
/*  STEM   - The STEM to store into.                                      */
/*  INDX   - Where to start in JSON._JSON.                                */
/*                                                                        */
/* Returns:                                                               */
/*  The new position in JSON._JSON.                                       */
/*  -13 - Expected a quoted member name.                                  */
/*  -14 - Expected a colon, ':', after the member name.                   */
_JSON_PARSE_OBJECT: PROCEDURE EXPOSE JSON.
  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_PARSE_OBJECT', -1)
  STEM = ARG(1)
  INDX = ARG(2)

  /* Get the members of the object. */
  COUNT = 1
  INDX = INDX + 1
  DO FOREVER
    /* Skip over white space. */
    INDX =_JSON_SKIP_WHITESPACE(INDX, ',')
    IF INDX < 0 THEN
      RETURN INDX
    CHR = SUBSTR(JSON._JSON, INDX, 1)

    /* End of the object already? */
    IF CHR = '}' THEN
      LEAVE

    /* Get the member name. This should be a string. */
    IF CHR \= '"' THEN
      RETURN _JSON_SET_ERROR('Expected quoted member name at:' INDX, -13)
    INDX = INDX + 1
    END_OF_STR = _JSON_PARSE_STRING(INDX)
    IF END_OF_STR < 0 THEN
      RETURN END_OF_STR
    MEMBER = SUBSTR(JSON._JSON, INDX, END_OF_STR - INDX)
    CALL VALUE STEM || '.' || COUNT || '.MEMBER', MEMBER
    INDX = END_OF_STR + 1

    /* Skip over white space. */
    INDX =_JSON_SKIP_WHITESPACE(INDX)
    IF INDX < 0 THEN
      RETURN INDX

    /* Expecting a colon here. */
    IF SUBSTR(JSON._JSON, INDX, 1) \= ':' THEN
      RETURN _JSON_SET_ERROR('Expected ":" after member "' || MEMBER || '" at:' INDX, -14)

    /* Parse the element. */
    INDX = INDX + 1
    NEW_STEM = STEM || '.' || COUNT
    INDX = _JSON_PARSE_ELEMENT(NEW_STEM, INDX)
    IF INDX < 0 THEN
      RETURN INDX

    /* Save the element count. */
    CALL VALUE STEM || '.0', COUNT

    /* End of the JSON text? */
    IF INDX > JSON._LEN THEN
      LEAVE
    COUNT = COUNT + 1
  END

  IF SUBSTR(JSON._JSON, INDX, 1) \= '}' THEN
    RETURN _JSON_SET_ERROR('Expected closing object brace "}" at:' INDX, -15)

  RETURN INDX + 1

/* Parse a JSON String.                                                   */
/*                                                                        */
/* Arguments:                                                             */
/*  INDX   - Where to start in JSON._JSON.                                */
/*           INDX should start AFTER the opening quote.                   */
/*                                                                        */
/* Returns:                                                               */
/*  The end of the string BEFORE the ending quote.                        */
/*  -1    - Reached end of input.                                         */
_JSON_PARSE_STRING: PROCEDURE EXPOSE JSON.
  START = ARG(1)

  INDX = START
  DO FOREVER
    CHR = SUBSTR(JSON._JSON, INDX, 1)

    IF CHR = '\' THEN
      INDX = INDX + 1

    IF CHR = '"' THEN
      RETURN INDX

    INDX = INDX + 1
    IF INDX > JSON._LEN THEN
      LEAVE
  END
  RETURN _JSON_SET_ERROR('Unexpected end of string starting at:' START, -16)

/* Parse a JSON Number.                                                   */
/*                                                                        */
/* This is VERY lazy and completely disregards standards.                 */
/* It just reads until ',', '}', ']' or whitespace.                       */
/*                                                                        */
/* Arguments:                                                             */
/*  INDX   - Where to start in JSON._JSON.                                */
/*           INDX should start at the first character of the number.      */
/*                                                                        */
/* Returns:                                                               */
/*  The new position in JSON._JSON.                                       */
_JSON_PARSE_NUMBER: PROCEDURE EXPOSE JSON.
  INDX = ARG(1)

  CHR = SUBSTR(JSON._JSON, INDX, 1)
  DO FOREVER
    IF POS(CHR, ",}]") > 0 | _JSON_PARSE_IS_WHITESPACE(CHR) THEN
      RETURN INDX

    INDX = INDX + 1
    IF INDX > JSON._LEN THEN
      RETURN INDX
    CHR = SUBSTR(JSON._JSON, INDX, 1)
  END

/* Convert parsed JSON to Text =========================================== */

/* Call the appropriate JSON_STRING_ function for the element type. */
_JSON_STRING_ELEMENT: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_ELEMENT', -1)
  POINTER = ARG(1)
  TYPE = VALUE(POINTER || '.TYPE')

  IF TYPE = 'A' THEN
    RETURN _JSON_STRING_ARRAY(POINTER)
  IF TYPE = 'F' THEN
    RETURN 'false'
  IF TYPE = 'N' THEN
    RETURN VALUE(POINTER || '.VALUE')
  IF TYPE = 'O' THEN
    RETURN _JSON_STRING_OBJECT(POINTER)
  IF TYPE = 'S' THEN
    RETURN _JSON_STRING_STRING(POINTER)
  IF TYPE = 'T' THEN
    RETURN 'true'
  IF TYPE = 'U' THEN
    RETURN 'null'
  RETURN ''

_JSON_STRING_ARRAY: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_ARRAY', -1)
  POINTER = ARG(1)
  NEW_STR = ''

  DO INDX = 1 TO VALUE(POINTER || '.0')
    IF NEW_STR \= '' THEN
      NEW_STR = NEW_STR || ','
    NEW_STR = NEW_STR || _JSON_STRING_ELEMENT(POINTER || '.' || INDX)
  END

  RETURN '[' || NEW_STR || ']'

_JSON_STRING_STRING: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_STRING', -1)
  POINTER = ARG(1)
  NEW_STR = '"' || VALUE(POINTER || '.VALUE') || '"'
  RETURN NEW_STR

_JSON_STRING_OBJECT: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_OBJECT', -1)
  POINTER = ARG(1)
  NEW_STR = ''

  DO INDX = 1 TO VALUE(POINTER || '.0')
    IF NEW_STR \= '' THEN
      NEW_STR = NEW_STR || ','
    NEW_STR = NEW_STR ||,
              '"' ||VALUE(POINTER || '.' || INDX || '.MEMBER') || '"' ||,
              ':' ||,
              _JSON_STRING_ELEMENT(POINTER || '.' || INDX)
  END

  RETURN '{' || NEW_STR || '}'

/* Pretty Print JSON ==================================================== */

_JSON_PP_ELEMENT: PROCEDURE EXPOSE JSON.
  IF ARG() < 3 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_ELEMENT', -1)
  POINTER = ARG(1)
  INDENT  = ARG(2)
  SHIFT   = ARG(3)
  TAIL    = ARG(4)
  TYPE    = VALUE(POINTER || '.TYPE')

  SELECT
    WHEN TYPE = 'A' THEN DO
      CALL _JSON_PP_PUSH '[', INDENT, SHIFT
      CALL _JSON_PP_ARRAY POINTER, INDENT, SHIFT, TAIL
    END
    WHEN TYPE = 'F' THEN
      CALL _JSON_PP_PUSH 'false' || TAIL, INDENT, SHIFT
    WHEN TYPE = 'N' THEN
      CALL _JSON_PP_PUSH VALUE(POINTER || '.VALUE') || TAIL, INDENT, SHIFT
    WHEN TYPE = 'O' THEN DO
      CALL _JSON_PP_PUSH '{', INDENT, SHIFT
      CALL _JSON_PP_OBJECT POINTER, INDENT, SHIFT, TAIL
    END
    WHEN TYPE = 'S' THEN
      CALL _JSON_PP_STRING POINTER, INDENT, SHIFT, TAIL
    WHEN TYPE = 'T' THEN
      CALL _JSON_PP_PUSH 'true' || TAIL, INDENT, SHIFT
    WHEN TYPE = 'U' THEN
      CALL _JSON_PP_PUSH 'null' || TAIL, INDENT, SHIFT
    OTHERWISE
      RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_ELEMENT', -1)
  END
  RETURN 1

_JSON_PP_ARRAY: PROCEDURE EXPOSE JSON.
  IF ARG() < 3 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_ARRAY', -1)
  POINTER = ARG(1)
  INDENT  = ARG(2)
  SHIFT   = ARG(3)
  TAIL    = ARG(4)
  ELEMENT_TAIL = ','

  COUNT = VALUE(POINTER || '.0')
  DO INDX = 1 TO COUNT
    IF INDX = COUNT THEN
      ELEMENT_TAIL = ''
    CALL _JSON_PP_ELEMENT POINTER || '.' || INDX, INDENT + 1, SHIFT, ELEMENT_TAIL
  END
  CALL _JSON_PP_PUSH ']' || TAIL, INDENT, SHIFT
  RETURN 1

_JSON_PP_STRING: PROCEDURE EXPOSE JSON.
  IF ARG() < 3 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_STRING', -1)
  POINTER = ARG(1)
  INDENT  = ARG(2)
  SHIFT   = ARG(3)
  TAIL    = ARG(4)
  CALL _JSON_PP_PUSH '"' || VALUE(POINTER || '.VALUE') || '"' || TAIL, INDENT, SHIFT
  RETURN 1

_JSON_PP_OBJECT: PROCEDURE EXPOSE JSON.
  IF ARG() < 3 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_OBJECT', -1)
  POINTER = ARG(1)
  INDENT  = ARG(2)
  SHIFT   = ARG(3)
  TAIL    = ARG(4)
  ELEMENT_TAIL = ','

  COUNT = VALUE(POINTER || '.0')
  DO INDX = 1 TO COUNT
    IF INDX = COUNT THEN
      ELEMENT_TAIL = ''
    TYPE = VALUE(POINTER || '.' || INDX || '.TYPE')
    MEMBER = '"' || VALUE(POINTER || '.' || INDX || '.MEMBER') || '":'

    IF POS(TYPE, "NTFU") > 0 THEN
      /* Numbers, booleans and null on the same line as the member name. */
      CALL _JSON_PP_PUSH MEMBER ||,
        VALUE(POINTER || '.' || INDX || '.VALUE') || ELEMENT_TAIL, INDENT + 1, SHIFT
    ELSE IF TYPE = 'S' THEN
      /* Strings on the same line as the member name. */
      CALL _JSON_PP_PUSH MEMBER ||,
        ' "' || VALUE(POINTER || '.' || INDX || '.VALUE') || '"' || ELEMENT_TAIL, INDENT + 1, SHIFT
    ELSE DO
      /* Arrays and Objects put the opening brace on the same line as the member name. */
      IF TYPE = 'A' THEN DO
        CALL _JSON_PP_PUSH MEMBER || ' [', INDENT + 1, SHIFT
        CALL _JSON_PP_ARRAY POINTER || '.' || INDX, INDENT + 1, SHIFT,  ELEMENT_TAIL
      END
      ELSE IF TYPE = 'O' THEN DO
        CALL _JSON_PP_PUSH MEMBER || ' {', INDENT + 1, SHIFT
        CALL _JSON_PP_OBJECT POINTER || '.' || INDX, INDENT + 1, SHIFT,  ELEMENT_TAIL
      END
    END
  END
  CALL _JSON_PP_PUSH '}' || TAIL, INDENT, SHIFT
  RETURN 1

/* Add a new string to the JSON._PP. array. */
_JSON_PP_PUSH: PROCEDURE EXPOSE JSON.
  IF ARG() < 3 THEN
    RETURN -1
  STRING = ARG(1)
  INDENT = ARG(2)
  SHIFT = ARG(3)
  INDX = JSON._PP.0 + 1
  JSON._PP.0 = INDX
  JSON._PP.INDX = COPIES(' ', INDENT * SHIFT) || STRING
  RETURN INDX

/* JSON Private Utilities =============================================== */

/* Adds a new element to an array.                                        */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element.                            */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an array.                           */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
_JSON_ADD: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_ADD!', -1)
  POINTER = ARG(1)

  INDX = VALUE(POINTER || '.0') + 1
  CALL VALUE POINTER || '.0', INDX
  CALL VALUE POINTER || '.' || INDX || '.TYPE', 'U'
  CALL VALUE POINTER || '.' || INDX || '.VALUE', 'null'
  RETURN INDX

/* Search the object at the given pointer for a member name.              */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The pointer to search from.                                 */
/*  SEARCH  - The member name to search for.                              */
/*                                                                        */
/* Returns:                                                               */
/*  The element index if the member is found.                             */
/*  -1 SEARCH is blank or the pointer is not found.                       */
/*  -21 if the current element is not an object.                          */
/*  -26 if the member was not found.                                      */
_JSON_FIND_MEMBER: PROCEDURE EXPOSE JSON.
  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_FIND_MEMBER!', -1)
  POINTER = ARG(1)
  SEARCH = ARG(2)
  IF SEARCH = '' THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_FIND_MEMBER!', -1)

  /* Is the member name quoted? */
  IF ABBREV(SEARCH, '"') | ABBREV(SEARCH, "'") THEN DO
    END_QUOTE = _JSON_STRING_END(SEARCH)
    IF END_QUOTE < 0 THEN DO
      RETURN END_QUOTE
    END
      SEARCH = SUBSTR(SEARCH, 2, END_QUOTE - 2)
  END

  TYPE = VALUE(POINTER || '.TYPE')
  IF TYPE = '' THEN
    RETURN _JSON_SET_ERROR('Type not set.', -21)
  ELSE IF TYPE \= 'O' THEN
    RETURN _JSON_SET_ERROR('Element not an object.', -21)

  /* Loop over the stem and try to locate the member. */
  COUNT = VALUE(POINTER || '.0')
  DO INDX = 1 TO COUNT
    IF VALUE(POINTER || '.' || INDX || '.MEMBER') = SEARCH THEN DO
      RETURN INDX
    END
  END

  /* Not found. */
  RETURN _JSON_SET_ERROR('Member name not found.', -26)

/* Adds a new element to an object.                                       */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The path to add the new element.                            */
/*  NAME    - The name for the new member.                                */
/*                                                                        */
/* Returns:                                                               */
/*  The index number of the new element.                                  */
/*  -21 if the current element is not an object.                          */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
_JSON_NEW: PROCEDURE EXPOSE JSON.
  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_NEW!', -1)
  POINTER = ARG(1)
  NAME = ARG(2)

  INDX = VALUE(POINTER || '.0') + 1
  CALL VALUE POINTER || '.0', INDX
  CALL VALUE POINTER || '.' || INDX || '.MEMBER', NAME
  CALL VALUE POINTER || '.' || INDX || '.TYPE', 'U'
  CALL VALUE POINTER || '.' || INDX || '.VALUE', 'null'
  RETURN INDX

/* Resolve a path into an absolute pointer.                               */
/* Will resolve element indexes and member names.                         */
/* Note: This is a bit complicated because it tries to handle most cases. */
/*                                                                        */
/* Arguments:                                                             */
/*  PATH    - The path to resolve. (May also just be a member.)           */
/*  FUNC    - The calling function name for errors. Optional.             */
/*                                                                        */
/* Returns:                                                               */
/*  The absolute path for the input.                                      */
/*  -1  - PATH is blank or missing.                                       */
/*  -21 - A member is used on an element that is NOT an object.           */
/*  -24 - The path is invalid.                                            */
/*  -26 - The member was not found.                                       */
_JSON_PATH_RESOLVE: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_PATH_RESOLVE', -1)
  PATH = ARG(1)
  FUNC = ARG(2)
  NEW_PATH = ''
  ERROR = ''

  /* Try to determine the intention. */
  IF PATH = '' THEN DO
    IF FUNC \= '' THEN
      ERROR = FUNC || '() '
    RETURN _JSON_SET_ERROR(ERROR || 'Invalid path.', -24)
  END
  ELSE IF PATH = '.' THEN
    /* Easy case, just the root. */
    RETURN 'JSON'
  ELSE IF ABBREV(PATH, '+') THEN
    /* Relative path starting from the existing pointer. */
    NEW_PATH = JSON._PTR
  ELSE IF ABBREV(PATH, '.') THEN
    /* Absolute path starting from the root. */
    NEW_PATH = 'JSON'
  ELSE IF DATATYPE(PATH) = 'NUM' THEN DO
    /* Element ID. Treat it as a relative path. */
    PATH = '.' || PATH
    NEW_PATH = JSON._PTR
  END
  ELSE DO
    /* Member name? */
      NEW_PATH = _JSON_FIND_MEMBER(JSON._PTR, PATH)
      IF NEW_PATH <= 0 THEN DO
        IF FUNC \= '' THEN
          ERROR = FUNC || '(MEMBER) '
        RETURN _JSON_SET_ERROR(ERROR || JSON._ERROR, NEW_PATH)
      END
      RETURN JSON._PTR || '.' || NEW_PATH
  END

  /* Split the path on periods then process each section. */
  PATH = SUBSTR(PATH, 2)
  DO WHILE LENGTH(PATH) > 0
    /* Get the path fragment to search for. */
    IF ABBREV(PATH, '"') | ABBREV(PATH, "'") THEN DO
      /* Quoted member name. Get the fragment from inside the quotes. */
      END_QUOTE = _JSON_STRING_END(PATH)
      IF END_QUOTE < 0 THEN DO
        /* Ending quote not found. */
        IF FUNC \= '' THEN
          ERROR = FUNC || '(PATH) '
        RETURN _JSON_SET_ERROR(ERROR || JSON._ERROR, END_QUOTE)
      END
      FRAGMENT = SUBSTR(PATH, 2, END_QUOTE - 2)
      PATH = SUBSTR(PATH, END_QUOTE + 2)

      /* Search for the member name. */
      INDX = _JSON_FIND_MEMBER(NEW_PATH, FRAGMENT)
      IF INDX < 1 THEN DO
        /* Member not found. */
        IF FUNC \= '' THEN
          ERROR = FUNC || '(PATH) '
        RETURN _JSON_SET_ERROR(ERROR || JSON._ERROR, NEW_PATH)
      END
      ELSE
        NEW_PATH = NEW_PATH || '.' || INDX
    END
    ELSE DO
      /* The fragment is up to the next period, or the rest ot the path. */
      PERIOD = POS('.', PATH)
      IF PERIOD > 0 THEN DO
        FRAGMENT = SUBSTR(PATH, 1, PERIOD -1)
        PATH = SUBSTR(PATH, PERIOD + 1)
      END
      ELSE DO
        FRAGMENT = PATH
        PATH = ''
      END

      /* Try to resolve the fragment. */
      IF DATATYPE(FRAGMENT) = 'NUM' THEN DO
        /* Element index. */
        NEW_PATH = NEW_PATH || '.' || FRAGMENT
        TYPE = VALUE(NEW_PATH || '.TYPE')
        IF TYPE = '' THEN DO
          IF FUNC \= '' THEN
            ERROR = FUNC || '(PATH) '
          RETURN _JSON_SET_ERROR(ERROR || 'Element index not found.', -25)
        END
      END
      ELSE DO
        /* Member name. */
        INDX = _JSON_FIND_MEMBER(NEW_PATH, FRAGMENT)
        IF INDX < 1 THEN DO
          IF FUNC \= '' THEN
            ERROR = FUNC || '(PATH) '
          RETURN _JSON_SET_ERROR(ERROR || JSON._ERROR, INDX)
        END
        ELSE
          NEW_PATH = NEW_PATH || '.' || INDX
      END
    END
  END

  RETURN NEW_PATH

/* Set an error message. */
/* Return with an optional error code. */
_JSON_SET_ERROR: PROCEDURE EXPOSE JSON.
  JSON._ERROR = ARG(1)
  JSON._ERRORCODE = -1
  IF ARG() > 1 THEN
    JSON._ERRORCODE = ARG(2)
  RETURN JSON._ERRORCODE

/* Set the type of the current element.                                   */
/* Prepares the new element according to the type.                        */
/* See the table Types: above.                                            */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER   - The path to add the new element.                          */
/*  NEW_TYPE  - The new type for the current element.                     */
/*                                                                        */
/* Returns:                                                               */
/*  The old type value.                                                   */
/*  -20 if the required type is not provided.                             */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
_JSON_SET_TYPE: PROCEDURE EXPOSE JSON.
  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_NEW!', -1)
  POINTER = ARG(1)
  NEW_TYPE = UPPER(ARG(2))

  /* Make sure the proper structure exists for this type. */
  IF NEW_TYPE = 'A' & VALUE(POINTER || '.0') = '' THEN
    CALL VALUE POINTER || '.0', 0
  ELSE IF NEW_TYPE = 'F' THEN
    CALL VALUE POINTER || '.VALUE', 'false'
  ELSE IF NEW_TYPE = 'N' & VALUE(POINTER || '.VALUE') = '' THEN
    CALL VALUE POINTER || '.VALUE', 0
  ELSE IF NEW_TYPE = 'O' & VALUE(POINTER || '.0') = '' THEN
    CALL VALUE POINTER || '.0', 0
  ELSE IF NEW_TYPE = 'U' THEN
    CALL VALUE POINTER || '.VALUE', 'null'
  ELSE IF NEW_TYPE = 'S' & VALUE(POINTER || '.VALUE') = '' THEN
    CALL VALUE POINTER || '.VALUE', ''
  ELSE IF NEW_TYPE = 'T' THEN
    CALL VALUE POINTER || '.VALUE', 'true'

  /* Set the new type and return the old. */
  RETURN VALUE(POINTER || '.TYPE', NEW_TYPE)

/* Return the end of the quoted string at the start of the variable.      */
/*                                                                        */
/* Arguments:                                                             */
/*  STR     - The string to process.                                      */
/*                                                                        */
/* Returns:                                                               */
/* Then index of the ending quote.                                        */
/* -16 if the ending quote is not found.                                  */
_JSON_STRING_END: PROCEDURE EXPOSE JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_END', -1)
  STR = ARG(1)
  QUOTE = SUBSTR(STR, 1, 1)
  LEN = LENGTH(STR)

  INDX = 2
  DO FOREVER
    CHR = SUBSTR(STR, INDX, 1)
    NCHR = SUBSTR(STR, INDX + 1, 1)
    IF CHR = QUOTE THEN DO
      IF NCHR = QUOTE THEN
        INDX = INDX + 1
      ELSE
        RETURN INDX
    END

    INDX = INDX + 1
    IF INDX > LEN THEN
      RETURN _JSON_SET_ERROR('Unexpected end of string :' STR, -16)
  END
  RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_END', -1)

/* Extracts the quoted string at the start of the variable.               */
/* Any doubled quotes are turned into single quotes.                      */
/* Example "That''s a string!" => "That's a string!"                      */
/*                                                                        */
/* Arguments:                                                             */
/*  STR     - The string to process.                                      */
/*  INDX    - The position of the end quote from _JSON_STRING_END(STR).   */
/*                                                                        */
/* Returns:                                                               */
/* Then index of the ending quote.                                        */
/* -16 if the ending quote is not found.                                  */
  _JSON_STRING_EXTRACT: PROCEDURE EXPOSE JSON.
  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_STRING_END', -1)
  STR = ARG(1)
  INDX = ARG(2)

  NEW_STR = SUBSTR(STR, 2, INDX - 2)
  IF SUBSTR(STR, 1, 1) = '"' THEN
    RETURN CHANGESTR('""', NEW_STR, '"')
  ELSE
    RETURN CHANGESTR("''", NEW_STR, "'")

/* Renumber elements in an array or object after deletion.                */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - The location the element that was deleted from.             */
/*  DEL_INDX- The index of the element that was deleted.                  */
/*                                                                        */
/* Returns:                                                               */
/*  1 for success.                                                        */
_JSON_RENUMBER: PROCEDURE EXPOSE JSON.
  IF ARG() < 2 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_RENUMBER', -1)
  POINTER = ARG(1)
  DEL_INDX = ARG(2)
  COUNT = VALUE(POINTER || '.0')

  DO INDX = DEL_INDX TO COUNT
    /* The STEM to renumber. */
    RENUM_STEM = POINTER || '.' || INDX
    RENUM_LEN = LENGTH(RENUM_STEM)

    /* The new name for the STEM using its new index. */
    NEW_STEM = POINTER || '.' || INDX - 1

    /* Loop over all tails and rename the ones that match. */
    /* Doing so involves looking at every single TAIL. */
    /* This is horribly inefficient, but I don't know how to improve it. */
    DO TAIL OVER JSON.
      FULL_TAIL = 'JSON.' || TAIL
      IF ABBREV(FULL_TAIL, RENUM_STEM) THEN DO
        /* Rename the STEM. */
        NEW_NAME = NEW_STEM || SUBSTR(FULL_TAIL, RENUM_LEN + 1)
        CALL VALUE NEW_NAME, VALUE(FULL_TAIL)
        INTERPRET 'DROP' FULL_TAIL
      END
    END
  END
  RETURN 1

/* JSON Testing ========================================================= */

/* Runs tests from the file 'json_tests.txt'.                             */
/*                                                                        */
/* Returns:                                                               */
/*  The total number of tests run.                                        */
/*  -90 if the test file could not be read.                               */
/*  -91 if the test variables name or json are missing.                   */
JSON_TESTS: PROCEDURE EXPOSE JSON. JSON_TESTS.
  JSON_TESTS. = ''
  TEST_TOTAL = 0
  TEST_PASS = 0
  TEST_FILE = 'json_tests.txt'
  RESULT_FILE = 'json_results.txt'
  JSON_TESTS.TOTAL = 0
  JSON_TESTS.PASS = 0
  JSON_TESTS.FAIL = 0

  EXEC CICS DELETEQ TD QUEUE(RESULT_FILE) END-EXEC

  DO FOREVER
    /* Get the next test case. */
    EXEC CICS READQ TD QUEUE(TEST_FILE) INTO(REC) END-EXEC
    IF EIBRESP = 12 | EIBRESP = 23 THEN
      LEAVE
    ELSE IF EIBRESP = 44 THEN
      RETURN _JSON_SET_ERROR('JSON_TESTS() Test file "' || TEST_FILE || '" does not exist. RC:' EIBRESP, -90)
    ELSE IF EIBRESP \= 0 THEN
      RETURN _JSON_SET_ERROR('JSON_TESTS() Unable to read tests. RC:' EIBRESP, -90)

    /* Skip comments. and blank lines. */
    REC = STRIP(REC)
    IF LENGTH(REC) = 0 | SUBSTR(REC, 1, 2) = '//' THEN
      ITERATE

    /* Parse the test case. */
    TEST_TOTAL = TEST_TOTAL + 1
    RC = JSON_PARSE(REC)
    IF RC < 0 THEN
      RETURN _JSON_SET_ERROR('JSON_TESTS() Unable parse the test. Error:' JSON._ERROR 'Test:' REC, -90)

    /* Get the variables we care about. */
    TEST_NAME       = JSON_VALUE('.name')
    IF JSON_ERROR_CODE() < 0 THEN
      RETURN _JSON_SET_ERROR('JSON_TESTS() Missing member "name". Test:' REC, -91)
    TEST_JSON       = JSON_VALUE('.json')
    IF JSON_ERROR_CODE() < 0 THEN
      RETURN _JSON_SET_ERROR('JSON_TESTS() Missing member "json." Test:' TEST_NAME, -91)
    TEST_RC         = JSON_VALUE('.rc')
    TEST_RC_TYPE    = JSON_TYPE('.rc')
    TEST_ERROR      = JSON_VALUE('.error')
    TEST_ERROR_TYPE = JSON_TYPE('.error')
    TEST_STRING     = JSON_VALUE('.string')
    TEST_PATH       = JSON_VALUE('.path')
    TEST_FUNC       = JSON_VALUE('.func')
    TEST_ARG1       = JSON_VALUE('.arg1')
    TEST_ARG1_TYPE  = JSON_TYPE('.arg1')
    TEST_ARG2       = JSON_VALUE('.arg2')
    TEST_ARG2_TYPE  = JSON_TYPE('.arg2')
    TEST_RESULT     = JSON_VALUE('.result')

    /* Parse the test JSON. */
    TEST_JSON = CHANGESTR("'", TEST_JSON, '"')
    TEST_STRING = CHANGESTR("'", TEST_STRING, '"')
    CALL JSON_PARSE TEST_JSON

    /* Is there a path to move to? */
    IF TEST_PATH \= '' THEN DO
      CALL JSON_PATH TEST_PATH
      IF JSON_ERROR_CODE() \= 0 THEN
        RETURN _JSON_SET_ERROR('JSON_TESTS() Invalid path:' TEST_PATH, -92)
    END

    /* Is there a function to call? */
    FUNC_RESULT = ''
    IF TEST_FUNC \= '' THEN DO
      TEST_FUNC = 'CALL' TEST_FUNC
      IF TEST_ARG1_TYPE \= '' THEN DO
        TEST_FUNC = TEST_FUNC '"' || JSON_ESCAPE(TEST_ARG1) || '"'
        IF TEST_ARG2_TYPE \= '' THEN
          TEST_FUNC = TEST_FUNC || ', "' || JSON_ESCAPE(TEST_ARG2) || '"'
      END
      INTERPRET TEST_FUNC
      FUNC_RESULT = RESULT
    END

    /* And figure out what to check based on the variables. */
    ERROR_CODE = JSON_ERROR_CODE()
    ERROR_TEXT = JSON_ERROR_TEXT()
    TEST_STATUS = 'PASS'
    TEST_MESSAGE = ''

    IF TEST_RC \= '' THEN DO
      SELECT
        WHEN TEST_RC_TYPE = 'T' & ERROR_CODE <= 0 THEN DO
          TEST_STATUS = 'FAIL'
          TEST_MESSAGE = TEST_MESSAGE 'Expected a positive RC.'
        END
        WHEN TEST_RC_TYPE = 'F' & ERROR_CODE >= 0 THEN DO
          TEST_STATUS = 'FAIL'
          TEST_MESSAGE = TEST_MESSAGE 'Expected a negative RC.'
        END
        WHEN TEST_RC_TYPE = 'U' & ERROR_CODE \= 0 THEN DO
          TEST_STATUS = 'FAIL'
          TEST_MESSAGE = TEST_MESSAGE 'Expected RC \= -1.'
        END
        WHEN TEST_RC_TYPE = 'S' | TEST_RC_TYPE = 'N' THEN DO
          IF TEST_RC \= ERROR_CODE THEN DO
            TEST_STATUS = 'FAIL'
            TEST_MESSAGE = TEST_MESSAGE 'Expected RC:' TEST_RC
          END
        END
        OTHERWISE
          NOP
      END
    END

    IF TEST_ERROR_TYPE = 'F' & ERROR_TEXT \= '' THEN DO
      TEST_STATUS = 'FAIL'
      TEST_MESSAGE = TEST_MESSAGE 'Expected no error.'
    END
    IF TEST_ERROR_TYPE = 'T' & ERROR_TEXT = '' THEN DO
      TEST_STATUS = 'FAIL'
      TEST_MESSAGE = TEST_MESSAGE 'Expected an error, got empty string.'
    END
    IF TEST_ERROR_TYPE = 'S' & TEST_ERROR \= ERROR_TEXT THEN DO
      TEST_STATUS = 'FAIL'
      TEST_MESSAGE = TEST_MESSAGE 'Expected error: "' || TEST_ERROR || '".'
    END

    IF TEST_STRING \= '' THEN DO
      TO_STRING = JSON_STRING()
      IF TEST_STRING \= TO_STRING THEN DO
        TEST_STATUS = 'FAIL'
        TEST_MESSAGE = TEST_MESSAGE 'Expected string: "' || TEST_STRING || '".'
      END
      JSON_TESTS.TEST_TOTAL.STRING = TO_STRING
    END
    ELSE
      JSON_TESTS.TEST_TOTAL.STRING = ''

    IF TEST_RESULT \= '' & TEST_RESULT \= FUNC_RESULT THEN DO
      TEST_STATUS = 'FAIL'
      TEST_MESSAGE = TEST_MESSAGE 'Expected function result: "' || TEST_RESULT || '".'
    END

    /* Save the test results. */
    TEST_MESSAGE = STRIP(TEST_MESSAGE)
    IF TEST_STATUS = 'PASS' THEN
      TEST_PASS = TEST_PASS + 1
    JSON_TESTS.TEST_TOTAL.NAME = TEST_NAME
    JSON_TESTS.TEST_TOTAL.STATUS = TEST_STATUS
    JSON_TESTS.TEST_TOTAL.JSON = TEST_JSON
    JSON_TESTS.TEST_TOTAL.MESSAGE = TEST_MESSAGE
    JSON_TESTS.TEST_TOTAL.ERROR = ERROR_TEXT
    JSON_TESTS.TEST_TOTAL.CODE = ERROR_CODE
    IF TEST_FUNC \= '' THEN DO
      JSON_TESTS.TEST_TOTAL.FUNC = TEST_FUNC
      JSON_TESTS.TEST_TOTAL.FRESULT = FUNC_RESULT
    END

    /* Save to RESULT_FILE. */
    CALL JSON_CLEAR
    CALL JSON_SET_TYPE 'O'
    CALL JSON_NEW_STRING 'name', TEST_NAME
    CALL JSON_NEW_NUMBER 'number', TEST_TOTAL
    IF TEST_STATUS = 'PASS' THEN
      CALL JSON_NEW_TRUE 'status'
    ELSE
      CALL JSON_NEW_FALSE 'status'
    CALL JSON_NEW_STRING 'json', CHANGESTR('"', TEST_JSON, "'")
    IF TEST_MESSAGE = '' THEN
      CALL JSON_NEW_NULL 'message'
    ELSE
      CALL JSON_NEW_STRING 'message', CHANGESTR('"', TEST_MESSAGE, "'")
    IF ERROR_TEXT = '' THEN
      CALL JSON_NEW_NULL 'error'
    ELSE
      CALL JSON_NEW_STRING 'error', CHANGESTR('"', ERROR_TEXT, "'")
    CALL JSON_NEW_NUMBER 'rc', ERROR_CODE
    IF TEST_FUNC \= '' THEN DO
      CALL JSON_NEW_STRING 'function', TEST_FUNC
      CALL JSON_NEW_STRING 'result', FUNC_RESULT
    END
    OUTPUT = JSON_STRING()
    EXEC CICS WRITEQ TD QUEUE(RESULT_FILE) FROM(OUTPUT) END-EXEC
  END

  /* Save and return the totals. */
  JSON_TESTS.TOTAL = TEST_TOTAL
  JSON_TESTS.PASS = TEST_PASS
  JSON_TESTS.FAIL = TEST_TOTAL - TEST_PASS
  RETURN TEST_TOTAL

/* Bottom of JSON Library. */

/* JSON Console ========================================================= */

/* Console loop. */
JSON_CONSOLE: PROCEDURE EXPOSE JSON. JSON_TESTS.
  /* Holds the console data and settings. */
  /* CONS_DATA is what the user sees in screens. */
  CONS_DATA. = ''
  CONS_DATA.SOURCE = 'JSON'

  /* Holds the console help text. */
  CONS_HELP. = ''

  /* Screen interface. */
  CONS_SCR. = ''
  CONS_SCR.CUR_POS = 1
  CONS_SCR.SCROLL = 'THIRD'
  CONS_SCR.PAGE_CNT = 1
  CONS_SCR.FIND_TEXT = ''
  CONS_SCR.FIND_CNT = ''
  CONS_SCR.PREV_INPUT = ''
  CONS_SCR.MSG = ''

  /* Terminal size. */
  EXEC CICS ASSIGN SCREENWD(SYSSCRW) SCREENHT(SYSSCRH) END-EXEC
  CONS_DATA.PER_PAGE = SYSSCRH - 5
  CONS_DATA.SCROLL_AMT = INT(CONS_DATA.PER_PAGE / 3)
  CONS_DATA.SCR_WIDTH = SYSSCRW - 1

  /* Map set. */
  MAPSETBASE = 'JSON1'
  MAPSETSUFFIX = ''
  IF SYSSCRH >= 43 THEN DO
    MAPSETSUFFIX    = 'L'
  END
  ELSE IF SYSSCRH >= 32 THEN DO
    MAPSETSUFFIX    = 'M'
  END
  ELSE IF SYSSCRH >= 27 & SYSSCRW = 132 THEN DO
    MAPSETSUFFIX    = 'W'
  END
  CONS_DATA.MAPSET = MAPSETBASE || MAPSETSUFFIX

  /* Load JSON into CONS_DATA then fill the first screen full. */
  CALL _CONS_DATA_LOAD
  CALL _CONS_FILL_SCR

  /* Capture any JSON parse error. */
  CONS_SCR.MSG = JSON._ERROR

  /* Start the main loop. */
  CALL _JSON_CONSOLE_LOOP 'JSONCONSOLE'
  RETURN

/* Main loop for the JSON console, help, or any other set of data. */
/* When changing data source some parameters should be preserved. */
/* See _CONS_HELP for details. */
_JSON_CONSOLE_LOOP: PROCEDURE EXPOSE CONS_DATA. CONS_SCR. CONS_HELP. JSON. JSON_TESTS.
  IF ARG() > 0 THEN
    CONSOLE_MAP = ARG(1)
  ELSE
    CONSOLE_MAP = 'JSONCONSOLE'

  DO FOREVER
    /* For the header. */
    CONS_SCR.JCOUNT = VALUE(JSON._PTR || '.0')
    CONS_SCR.JDEPTH = JSON_DEPTH()
    CONS_SCR.JERRORC = JSON._ERRORCODE
    CONS_SCR.JPATH = JSON_PATH()
    CONS_SCR.JTYPE = JSON_TYPE_STRING(VALUE(JSON._PTR || '.TYPE'))
    CONS_SCR.JTYPE = JSON_TYPE() '-' JSON_TYPE_STRING(JSON_TYPE())

    DO_RELOAD = 'NO'
    PREV_FIND = CONS_SCR.FIND_TEXT
    PREV_SCROLL = CONS_SCR.SCROLL
    EXEC CICS CONVERSE MAP(CONSOLE_MAP) MAPSET(CONS_DATA.MAPSET) FROM(CONS_SCR.) INTO(CONS_SCR.) ERASE END-EXEC
    CONS_SCR.MSG = ''

    /* Get any input from the user. */
    USER_INPUT = STRIP(CONS_SCR.OPTION)
    CONS_SCR.OPTION = ''

    /* Did the find text or scroll change? */
    IF CONS_SCR.FIND_TEXT \= PREV_FIND THEN DO
      IF CONS_SCR.FIND_TEXT \= '' THEN
        CALL _CONS_FIND CONS_SCR.FIND_TEXT, 'YES'
      ELSE DO
        DO TAIL OVER CONS_DATA.
          IF ABBREV(TAIL, 'FOUND') THEN
            INTERPRET 'DROP CONS_DATA.' || TAIL
        END
      END
    END
    IF CONS_SCR.SCROLL \= PREV_SCROLL THEN
        IF _CONS_SCROLL_UPDATE(CONS_SCR.SCROLL) = 0 THEN
          CONS_SCR.SCROLL = PREV_SCROLL

    /* Handle the AID keys. */
    /* Most of these just set USER_INPUT to the command. */
    AID = C2X(EIBAID)
    SELECT
      /* Help. */
      WHEN AID = 'F1' THEN DO
        USER_INPUT = 'HELP' USER_INPUT
        AID = '7D'
      END
      /* Find text. */
      WHEN AID = 'F2' THEN DO
        USER_INPUT = 'FIND' USER_INPUT
        AID = '7D'
      END
      /* Back/Exit. */
      WHEN AID = 'F3' THEN DO
        RETURN
      END
      /* Recall previous input. */
      WHEN AID = 'F4' THEN DO
        CONS_SCR.OPTION = CONS_SCR.PREV_INPUT
      END
      /* Reload. */
      WHEN AID = 'F5' THEN DO
        IF CONS_DATA.SOURCE = 'JSON' THEN
          DO_RELOAD = 'YES'
        IF CONS_DATA.SOURCE = 'TEST' THEN DO
          IF CONS_DATA.SHOW_DETAIL = 'YES' THEN
            CONS_DATA.SHOW_DETAIL = 'NO'
          ELSE
            CONS_DATA.SHOW_DETAIL = 'YES'
          DO_RELOAD = 'YES'
        END
      END
      /* Up to the top. */
      WHEN AID = 'F6' THEN DO
        USER_INPUT = 'TOP'
        AID = '7D'
      END
      /* Scroll up. */
      WHEN AID = 'F7' THEN DO
        USER_INPUT = 'UP'
        AID = '7D'
      END
      /* Scroll down. */
      WHEN AID = 'F8' THEN DO
        USER_INPUT = 'DOWN'
        AID = '7D'
      END
      /* Down to the bottom. */
      WHEN AID = 'F9' THEN DO
        USER_INPUT = 'BOT'
        AID = '7D'
      END
      /* Home, scroll the screen to the current path. */
      WHEN AID = '7A' THEN DO
        USER_INPUT = 'HOME' USER_INPUT
        AID = '7D'
      END
      /* Change scroll. */
      WHEN AID = '7B' THEN DO /* PF12 */
        USER_INPUT = 'SCROLL'
        AID = '7D'
      END
      /* Exit. */
      WHEN AID = '7C' THEN DO /* PF12 */
        EXIT
      END
      OTHERWISE NOP
    END

    /* Translate a few shortcuts for a friendlier interface. */
    IF ABBREV(USER_INPUT, '/') THEN
      /* Search for text. */
      USER_INPUT = 'FIND' SUBSTR(USER_INPUT, 2)
    ELSE IF ABBREV(USER_INPUT, '?') THEN
      /* Help. */
      USER_INPUT = 'HELP' SUBSTR(USER_INPUT, 2)
    ELSE IF ABBREV(USER_INPUT, '.') | ABBREV(USER_INPUT, '+') THEN
      /* Change the path. */
      USER_INPUT = 'PATH' USER_INPUT
    ELSE IF POS(SUBSTR(USER_INPUT, 1, 1), '{["0123456789') > 0 THEN
      /* Enter JSON. */
      USER_INPUT = 'PARSE' USER_INPUT
    ELSE IF USER_INPUT = '-' THEN
      /* Up one level. */
      USER_INPUT = 'PARENT'

    /* Do something with the user input. */
    IF AID = '7D' & USER_INPUT \= '' THEN DO
      DROP JSON._ERROR
      DROP JSON._ERRORCODE
      CONS_SCR.PREV_INPUT = USER_INPUT
      PARSE VAR USER_INPUT COMMAND ARGS
      COMMAND = UPPER(COMMAND)
      SELECT
        /* Jump to the bottom of data. */
        WHEN COMMAND = 'BOT' | COMMAND = 'B' THEN DO
          CONS_SCR.CUR_POS = (CONS_DATA.0 - CONS_DATA.PER_PAGE) + 1
        END
        /* Demonstration with the Bricks metrics. */
        WHEN COMMAND = 'DEMO' | COMMAND = 'M' THEN DO
          CALL _CONS_DEMO
        END
        /* Scroll down. */
        WHEN COMMAND = 'DOWN' | COMMAND = 'D' THEN DO
          /* Don't bother scrolling if all the Links fit on the screen. */
          IF CONS_DATA.0 > CONS_DATA.PER_PAGE THEN DO
            CONS_SCR.CUR_POS = CONS_SCR.CUR_POS + CONS_DATA.SCROLL_AMT
            IF CONS_SCR.CUR_POS > (CONS_DATA.0 - CONS_DATA.PER_PAGE) + 1 THEN
              CONS_SCR.CUR_POS = (CONS_DATA.0 - CONS_DATA.PER_PAGE) + 1
          END
        END
        /* Exit. */
        WHEN COMMAND = 'EXIT' | COMMAND = 'E' | COMMAND = 'BYE' THEN DO
          EXIT
        END
        /* Help text. */
        WHEN COMMAND = 'HELP' | COMMAND = 'H' THEN DO
          IF CONS_DATA.SOURCE = 'HELP' THEN
            CALL _CONS_HELP_TOPIC ARGS
          ELSE DO
            CALL _CONS_HELP ARGS
          END
          DO_RELOAD = 'YES'
        END
        /* Search for text. */
        WHEN COMMAND = 'FIND' | COMMAND = 'RFIND' | COMMAND = 'F' THEN DO
          IF ARGS \= '' THEN
            CONS_SCR.FIND_TEXT = ARGS
          IF CONS_SCR.FIND_TEXT \= '' THEN
            CALL _CONS_FIND ARGS, 'YES'
        END
        /* Locate a line. */
        WHEN COMMAND = 'LOCATE' | COMMAND = 'L' THEN DO
          IF ARGS \= '' THEN
            CONS_SCR.CUR_POS = ARGS
        END
        /* Quit. */
        WHEN COMMAND = 'QUIT' | COMMAND = 'Q' THEN DO
          RETURN
        END
        /* Reload the data. */
        WHEN COMMAND = 'RELOAD' | COMMAND = 'R' THEN DO
          DO_RELOAD = 'YES'
        END
        /* Clear the search text. */
        WHEN COMMAND = 'RESET' THEN DO
          CONS_SCR.FIND_TEXT = ''
          DO TAIL OVER CONS_DATA.
            IF ABBREV(TAIL, 'FOUND') THEN
              INTERPRET 'DROP CONS_DATA.' || TAIL
          END
        END
        /* Chang the scroll. */
        WHEN COMMAND = 'SCROLL' | COMMAND = 'S' THEN DO
          CALL _CONS_SCROLL_UPDATE ARGS
        END
        /* Re-run the tests. */
        WHEN COMMAND = 'TEST' & CONS_DATA.SOURCE = 'TEST' THEN DO
          RC = JSON_TESTS()
          IF RC < 0 THEN
            CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
          CONS_SCR.TTOTAL = JSON_TESTS.TOTAL
          CONS_SCR.TFAIL = JSON_TESTS.FAIL
          CONS_SCR.TPASS = JSON_TESTS.PASS
          DO_RELOAD = 'YES'
        END

        /* Jump to the top of data. */
        WHEN COMMAND = 'TOP' | COMMAND = 'T' THEN DO
          CONS_SCR.CUR_POS = 1
        END
        /* Scroll up. */
        WHEN COMMAND = 'UP' | COMMAND = 'U' THEN DO
          /* Don't bother scrolling if all the Links fit on the screen. */
          IF CONS_DATA.0 > CONS_DATA.PER_PAGE THEN DO
            CONS_SCR.CUR_POS = CONS_SCR.CUR_POS - CONS_DATA.SCROLL_AMT
            IF CONS_SCR.CUR_POS < 1 THEN
              CONS_SCR.CUR_POS = 1
          END
        END
        /* Try JSON, if the data source is JSON. */
        OTHERWISE DO
          IF CONS_DATA.SOURCE = 'JSON' THEN
            DO_RELOAD = _CONS_JSON_COMMAND(USER_INPUT)
          ELSE DO
            CONS_SCR.OPTION = USER_INPUT
            CONS_SCR.MSG = 'Unknown command:' USER_INPUT
          END
        END
      END
    END

    /* Reload the JSON data? */
    IF DO_RELOAD = 'YES' THEN DO
      CALL _CONS_DATA_LOAD
      IF CONS_SCR.FIND_TEXT \= '' THEN
        CALL _CONS_FIND '', 'NO'
    END

    /* Reload CONS_SCR. */
    CALL _CONS_FILL_SCR
  END
  RETURN

/* Update the page scroll amount. */
_CONS_SCROLL_UPDATE: PROCEDURE EXPOSE CONS_DATA. CONS_SCR.
  NEW_SCROLL = UPPER(ARG(1))

  IF NEW_SCROLL = '' THEN DO
    /* Rotate to the next option. */
    IF CONS_SCR.SCROLL = 'THIRD' THEN
      NEW_SCROLL = 'HALF'
    ELSE IF CONS_SCR.SCROLL = 'HALF' THEN
      NEW_SCROLL = 'PAGE'
    ELSE IF CONS_SCR.SCROLL = 'PAGE' THEN
      NEW_SCROLL = 'LINE'
    ELSE IF CONS_SCR.SCROLL = 'LINE' THEN
      NEW_SCROLL = 'THIRD'
  END

  /* Verify what has been entered and update the scroll amount. */
  IF UPPER(NEW_SCROLL) = 'THIRD' THEN DO
    CONS_DATA.SCROLL_AMT = INT(CONS_DATA.PER_PAGE / 3)
    CONS_SCR.SCROLL = 'THIRD'
  END
  ELSE IF UPPER(NEW_SCROLL) = 'HALF' THEN DO
    CONS_DATA.SCROLL_AMT = INT(CONS_DATA.PER_PAGE / 2)
    CONS_SCR.SCROLL = 'HALF'
  END
  ELSE IF UPPER(NEW_SCROLL) = 'PAGE' THEN DO
    CONS_DATA.SCROLL_AMT = CONS_DATA.PER_PAGE
    CONS_SCR.SCROLL = 'PAGE'
  END
  ELSE IF UPPER(NEW_SCROLL) = 'LINE' THEN DO
    CONS_DATA.SCROLL_AMT = 1
    CONS_SCR.SCROLL = 'LINE'
  END
  ELSE DO
    CONS_SCR.MSG = 'Invalid scroll amount. Try one of: THIRD, HALF, PAGE, or LINE'
    RETURN 0
  END
  RETURN 1

/* Load data into CONS_DATA from the desired source. */
_CONS_DATA_LOAD: PROCEDURE EXPOSE CONS_DATA. CONS_HELP. JSON. JSON_TESTS.
  /* Clean any old markers. */
  DO TAIL OVER CONS_DATA.
    IF ABBREV(TAIL, 'WRAPPED') | ABBREV(TAIL, 'FOUND') THEN
      INTERPRET 'DROP CONS_DATA.' || TAIL
  END
  CONS_DATA.0 = 0

  IF CONS_DATA.SOURCE = 'JSON' THEN DO
    /* Parsed JSON. */
    CALL _CONS_DATA_LOAD_JSON

    /* Meta data. */
    DO TAIL OVER JSON.
      IF ABBREV(TAIL, '_') THEN
      CALL _CONS_DATA_LOAD_PUSH 'JSON.' || TAIL '=' JSON.TAIL
    END
  END
  ELSE IF CONS_DATA.SOURCE = 'PRETTY' THEN
    /* Pretty Printed JSON. */
    DO INDX = 1 TO JSON._PP.0
      CALL _CONS_DATA_LOAD_PUSH JSON._PP.INDX
    END
  ELSE IF CONS_DATA.SOURCE = 'HELP' THEN
    /* Help text. */
    DO INDX = 1 TO CONS_HELP.0
      CALL _CONS_DATA_LOAD_PUSH CONS_HELP.INDX
    END
  ELSE IF CONS_DATA.SOURCE = 'TEST' THEN
    CALL _CONS_DATA_LOAD_TEST
  RETURN

/* Walks the parsed JSON and loads data in a sensible order. */
_CONS_DATA_LOAD_JSON: PROCEDURE EXPOSE CONS_DATA. JSON.
  IF ARG() > 0 THEN
    POINTER = ARG(1)
  ELSE
    POINTER = 'JSON'

  TYPE = VALUE(POINTER || '.TYPE')
  CALL _CONS_DATA_LOAD_PUSH POINTER || '.TYPE' '=' TYPE

  IF TYPE = 'A' | TYPE = 'O' THEN DO
    COUNT = VALUE(POINTER || '.0')
    CALL _CONS_DATA_LOAD_PUSH POINTER || '.0 =' COUNT
    DO INDX = 1 TO COUNT
      IF TYPE = 'O' THEN DO
        NAME = VALUE(POINTER || '.' || INDX || '.MEMBER')
        CALL _CONS_DATA_LOAD_PUSH POINTER || '.' || INDX || '.MEMBER' '=' NAME
      END
      CALL _CONS_DATA_LOAD_JSON POINTER || '.' || INDX
    END
  END

  IF POS(TYPE, 'FNSTU?  ') > 0 THEN
    CALL _CONS_DATA_LOAD_PUSH POINTER || '.VALUE' '=' VALUE(POINTER || '.VALUE')
  RETURN

/* Loads the test results in a more readable format. */
_CONS_DATA_LOAD_TEST: PROCEDURE EXPOSE CONS_DATA. JSON_TESTS.
  DO INDX = 1 TO JSON_TESTS.TOTAL
    /* Format the test header to fit the screen. */
    RC = JSON_TESTS.INDX.CODE
    IF RC >= 0 THEN
      RC = ' ' || RC
    HEADER =,
      LEFT(JSON_TESTS.INDX.NAME, CONS_DATA.SCR_WIDTH - 13),
      LEFT(RC, 4),
      LEFT(JSON_TESTS.INDX.STATUS, 4)
    CALL _CONS_DATA_LOAD_PUSH HEADER

    /* Display details? */
    IF CONS_DATA.SHOW_DETAIL = 'YES' | JSON_TESTS.INDX.STATUS = 'FAIL' THEN DO
      CALL _CONS_DATA_LOAD_PUSH 'JSON:   ' || JSON_TESTS.INDX.JSON
      IF JSON_TESTS.INDX.STRING \= '' THEN
        CALL _CONS_DATA_LOAD_PUSH 'String: ' || JSON_TESTS.INDX.STRING
      IF JSON_TESTS.INDX.ERROR \= '' THEN
        CALL _CONS_DATA_LOAD_PUSH 'Error:' JSON_TESTS.INDX.ERROR
      IF JSON_TESTS.INDX.FUNC \= '' THEN
        CALL _CONS_DATA_LOAD_PUSH 'Function:' JSON_TESTS.INDX.FUNC
      IF JSON_TESTS.INDX.FRESULT \= '' THEN
        CALL _CONS_DATA_LOAD_PUSH 'Result:' JSON_TESTS.INDX.FRESULT
      IF JSON_TESTS.INDX.MESSAGE \= '' THEN
        CALL _CONS_DATA_LOAD_PUSH JSON_TESTS.INDX.MESSAGE
      CALL _CONS_DATA_LOAD_PUSH ''
    END
  END
  RETURN

/* Push text into CONS_DATA like a stack. */
/* Wraps long lines. */
/* This exist purely to make _CONS_DATA_LOAD simpler */
_CONS_DATA_LOAD_PUSH: PROCEDURE EXPOSE CONS_DATA.
  DATA = ARG(1)

  IF LENGTH(DATA) = 0 THEN DO
    CONS_DATA.0 = CONS_DATA.0 + 1
    INDX = CONS_DATA.0
    CONS_DATA.INDX = ''
  END

  DO WHILE LENGTH(DATA) > 0
    CONS_DATA.0 = CONS_DATA.0 + 1
    INDX = CONS_DATA.0
    IF LENGTH(DATA) > CONS_DATA.SCR_WIDTH THEN DO
      /* The row is too long and must be wrapped. */
      IF CONS_DATA.SOURCE = 'HELP' THEN DO
        /* Handle wrapping help text a bit more human. */
        LAST_SPACE = LASTPOS(' ', SUBSTR(DATA, 1, CONS_DATA.SCR_WIDTH - 1))
        IF LAST_SPACE >= CONS_DATA.SCR_WIDTH - 10 THEN DO
          /* Wrap on a space character. */
          CONS_DATA.INDX = SUBSTR(DATA, 1, LAST_SPACE - 1)
          DATA = SUBSTR(DATA, LAST_SPACE + 1)
        END
        ELSE DO
          /* Too long, just hard wrap. */
          CONS_DATA.INDX = SUBSTR(DATA, 1, CONS_DATA.SCR_WIDTH - 4) '...'
          DATA = SUBSTR(DATA, CONS_DATA.SCR_WIDTH - 3)
        END
      END
      ELSE DO
        /* Hard wrap. Also mark this and the next line as wrapped for highlighting. */
        CONS_DATA.INDX = SUBSTR(DATA, 1, CONS_DATA.SCR_WIDTH - 4) '...'
        DATA = SUBSTR(DATA, CONS_DATA.SCR_WIDTH - 3)
        CONS_DATA.WRAPPED.INDX = 'YES'
        CALL VALUE 'CONS_DATA.WRAPPED.' || (INDX + 1), 'YES'
      END
    END
    ELSE DO
      CONS_DATA.INDX = DATA
      DATA = ''
    END
  END
  RETURN

/* Search in CONS_DATA for the given text. */
_CONS_FIND: PROCEDURE EXPOSE CONS_SCR. CONS_DATA.
  FIRST_SEARCH       = ARG(1) /* This will be blank on repeat searches. */
  DO_MOVE            = ARG(2) /* If YES move the current position. */
  CONS_SCR.FIND_CNT = 0
  MARKER_MOVED  = 'NO'

  /* Is there anything to search for? */
  IF CONS_SCR.FIND_TEXT = '' THEN
    IF FIRST_SEARCH = '' THEN
      RETURN
    ELSE
      CONS_SCR.FIND_TEXT = FIRST_SEARCH

  /* Clean any old markers. */
  DO TAIL OVER CONS_DATA.
    IF ABBREV(TAIL, 'FOUND') THEN
      INTERPRET 'DROP CONS_DATA.' || TAIL
  END

  /* Don't move the current position. */
  /* Do this during reload so the screen doesn't jump. */
  IF DO_MOVE = 'NO' THEN
    MARKER_MOVED = 'YES'

  /* Do the search. */
  DO INDX = 1 TO CONS_DATA.0
    IF POS(UPPER(CONS_SCR.FIND_TEXT), UPPER(CONS_DATA.INDX)) \= 0 THEN DO
      /* Note each record that has the search text */
      CONS_DATA.FOUND.INDX = 'YES'
      CONS_SCR.FIND_CNT = CONS_SCR.FIND_CNT + 1

      /* Move the current position to where it was found? */
      IF MARKER_MOVED = 'NO' THEN DO
        IF FIRST_SEARCH \= '' THEN DO
          /* First time searching jump to the first position found. */
          CONS_SCR.CUR_POS = INDX
          MARKER_MOVED = 'YES'
        END
        ELSE IF INDX > CONS_SCR.CUR_POS THEN DO
          /* Not the first time searching, jump to the next result. */
          CONS_SCR.CUR_POS = INDX
          MARKER_MOVED = 'YES'
        END
      END
    END
  END
  RETURN

/* Fill CONS_SCR from CONS_DATA based on the current position. */
_CONS_FILL_SCR: PROCEDURE EXPOSE CONS_SCR. CONS_DATA. JSON.
  /* Make sure the current position makes sense with the data we have. */
  IF CONS_SCR.CUR_POS > CONS_DATA.0 THEN
    CONS_SCR.CUR_POS = CONS_DATA.0 - CONS_DATA.PER_PAGE + 1
  START = CONS_SCR.CUR_POS

  /* For HELP text find the topic to display at the top of the screen. */
  IF CONS_DATA.SOURCE = 'HELP' THEN DO
    CONS_SCR.CUR_TOPIC = ''
    IF START > 1 THEN
      /* Search backwards for the topic. */
      DO INDX = START - 1 TO 1 BY -1
        IF ABBREV(CONS_DATA.INDX, '# ') THEN DO
          CONS_SCR.CUR_TOPIC = CONS_DATA.INDX
          LEAVE INDX
        END
      END
  END

  /* Fill the screen up. */
  DO SCR_ROW = 1 TO CONS_DATA.PER_PAGE
    INDX = START + SCR_ROW - 1
    IF INDX <= CONS_DATA.0 THEN DO
      ROW_DATA = CONS_DATA.INDX
      COLOR = ''

      IF CONS_DATA.FOUND.INDX = 'YES' THEN
        COLOR = 'CYAN'      /* Search text. */
      ELSE IF CONS_DATA.WRAPPED.INDX = 'YES' THEN
        COLOR = 'YELLOW'    /* Wrapped. */
      ELSE IF ABBREV(ROW_DATA, 'JSON._') THEN
        COLOR = 'GREEN'     /* Meta data. */
      ELSE IF JSON._PTR \= 'JSON' & ABBREV(ROW_DATA, JSON._PTR) THEN
        COLOR = 'PINK'      /* Current path. But not at the root. */
      ELSE IF CONS_DATA.SOURCE = 'HELP' THEN DO
        /* Highlighting for help text. */
        MARKER = SUBSTR(ROW_DATA, 1, 1)
        IF MARKER = '#' THEN
          COLOR = 'WHITE'   /* Topic header. */
        ELSE IF MARKER = '!' THEN
          COLOR = 'RED'     /* Important! */
        ELSE IF MARKER = '|' | MARKER = '+' THEN
          COLOR = 'GREEN'   /* Table. */
        ELSE IF MARKER = '*' THEN
          COLOR = 'GREEN'    /* List. */
        ELSE IF MARKER = '@' THEN
          COLOR = 'PINK'    /* Code. */
      END
      ELSE IF CONS_DATA.SOURCE = 'TEST' THEN DO
        /* Highlighting for test results. */
        STATUS = SUBSTR(ROW_DATA, LENGTH(ROW_DATA) - 4)
        IF STATUS = 'PASS' THEN
          COLOR = 'GREEN'
        ELSE IF STATUS = 'FAIL' THEN
          COLOR = 'RED'
        ELSE IF ABBREV(ROW_DATA, 'Expected') THEN
          COLOR = 'YELLOW'
        ELSE IF ABBREV(ROW_DATA, 'Error:') THEN
          COLOR = 'PINK'
        ELSE IF ABBREV(ROW_DATA, 'JSON:') THEN
          COLOR = 'BLUE'
        ELSE IF ABBREV(ROW_DATA, 'String:') THEN
          COLOR = 'BLUE'
      END

      CALL VALUE 'CONS_SCR.OUTPUT' || SCR_ROW, ROW_DATA
      CALL VALUE 'CONS_SCR.OUTPUT' || SCR_ROW || '_C', COLOR
    END
    ELSE DO
      /* Past the end of available data. Blank row. */
      CALL VALUE 'CONS_SCR.OUTPUT' || SCR_ROW, ''
      CALL VALUE 'CONS_SCR.OUTPUT' || SCR_ROW || '_C', ''
    END
  END

  /* And finally some friendly extras. */
  CONS_SCR.PAGE_CNT = TRUNC(CONS_DATA.0 / CONS_DATA.PER_PAGE, 1)
  CONS_SCR.CUR_PAGE = TRUNC(INDX / CONS_DATA.PER_PAGE, 1)
  RETURN

/* Execute a JSON command. */
/* Returns YES or NO to indicate if data should be reloaded. */
_CONS_JSON_COMMAND: PROCEDURE EXPOSE CONS_SCR. CONS_DATA. CONS_HELP. JSON.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _CONS_JSON_COMMAND', -1)
  USER_INPUT = ARG(1)
  PARSE VAR USER_INPUT COMMAND ARGS
  COMMAND = UPPER(COMMAND)
  IF SUBSTR(COMMAND, 1, 5) = 'JSON_' THEN
    COMMAND = SUBSTR(COMMAND, 6)
  DO_RELOAD = 'NO'

  /* Split the args into ARGA and ARGB. */
  ARGA = ''
  ARGB = ''
  IF ARGS \= '' THEN DO
    IF ABBREV(ARGS, '"') | ABBREV(ARGS, "'") THEN DO
      /* The first arg is quoted. */
      END_QUOTE = _JSON_STRING_END(ARGS)
      IF END_QUOTE < 0 THEN DO
        CONS_SCR.MSG = JSON_ERROR_TEXT()
        RETURN 'NO'
      END
      ARGA = _JSON_STRING_EXTRACT(ARGS, END_QUOTE)
      ARGB = STRIP(SUBSTR(ARGS, END_QUOTE + 1))
    END
    ELSE DO
      /* Not quoted. */
      PARSE VAR ARGS ARGA ARGB
    END

    /* Is the second arg quoted? */
    IF ARGB \= '' & (ABBREV(ARGB, '"') | ABBREV(ARGB, "'")) THEN DO
      END_QUOTE = _JSON_STRING_END(ARGB)
      IF END_QUOTE < 0 THEN DO
        CONS_SCR.MSG = JSON_ERROR_TEXT()
        RETURN 'NO'
      END
      ARGB = _JSON_STRING_EXTRACT(ARGB, END_QUOTE)
    END
  END

  /* Handle the user input. */
  SELECT
    /* Add an element to an array */
    WHEN COMMAND = 'ADD' THEN DO
      IF ARGA = '' THEN
        NEW_INDX = JSON_ADD()
      ELSE
        NEW_INDX = JSON_ADD(ARGA)
      IF NEW_INDX < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Added a new element with index:' NEW_INDX
      DO_RELOAD = 'YES'
    END
    /* Clear the contents of JSON. */
    WHEN COMMAND = 'CLEAR' THEN DO
      CALL JSON_CLEAR
      DO_RELOAD = 'YES'
    END
    /* Element count at the pointer. */
    WHEN COMMAND = 'COUNT' THEN DO
      IF ARGA = '' THEN
        COUNT = JSON_COUNT()
      ELSE
        COUNT = JSON_COUNT(ARGA)
      IF COUNT < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Count:' COUNT
    END
    /* Delete the current element. */
    WHEN COMMAND = 'DELETE' | COMMAND = 'DEL' | COMMAND = 'RM' THEN DO
      IF ARGA = '' THEN
        RC = JSON_DELETE()
      ELSE
        RC = JSON_DELETE(ARGA)
      IF RC < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE IF RC = 1 THEN
        CONS_SCR.MSG = 'SUCCESS!'
      ELSE
        CONS_SCR.MSG = 'UNKNOWN STATE! RC:' RC 'Error:' JSON_ERROR_TEXT()
      DO_RELOAD = 'YES'
    END
    /* Depth of the current element. */
    WHEN COMMAND = 'DEPTH' THEN DO
      IF ARGA = '' THEN
        DEPTH = JSON_DEPTH()
      ELSE
        DEPTH = JSON_DEPTH(ARGA)
      IF DEPTH < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Depth:' DEPTH
    END
    /* Error text. */
    WHEN COMMAND = 'ERROR' THEN DO
      ERROR = JSON_ERROR_TEXT()
      IF ERROR = '' THEN
        CONS_SCR.MSG = 'No error.'
      ELSE
        CONS_SCR.MSG = ERROR
    END
    /* Error code. */
    WHEN COMMAND = 'ERROR_CODE' THEN DO
      CONS_SCR.MSG = 'Error Code:' JSON_ERROR_CODE()
    END
    /* Process string escape characters. */
    WHEN COMMAND = 'ESCAPE' THEN DO
      STR = JSON_ESCAPE(ARGA)
      CONS_SCR.MSG = 'Result:' STR
    END
    /* GET JSON from a URL. */
    WHEN COMMAND = 'GET' THEN DO
      IF ARGA = '' THEN
        RC = JSON_GET()
      ELSE
        RC = JSON_GET(ARGA)
      IF RC < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE IF RC > 0 THEN
        CONS_SCR.MSG = 'SUCCESS!' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Possible error. Nothing fetched/parsed?' JSON_ERROR_TEXT()
      CONS_SCR.CUR_PAGE = 1
      DO_RELOAD = 'YES'
    END
    /* Home the screen in on the current pointer. */
    WHEN COMMAND = 'HOME' | COMMAND = 'GO' | COMMAND = 'G' THEN DO
      POINTER = JSON._PTR
      IF COMMAND = 'GO' & ARGA \= '' THEN DO
        POINTER = _JSON_PATH_RESOLVE(ARGA)
        IF POINTER < 0 THEN DO
          CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
          RETURN 'NO'
        END
        JSON._PTR = POINTER
        ARGA = ''
      END

      IF ARGA \= '' THEN DO
        POINTER = _JSON_PATH_RESOLVE(ARGA)
        IF POINTER <= 0 THEN DO
          CONS_SCR.MSG = JSON_ERROR_TEXT()
          RETURN 'NO'
        END
      END

      IF POINTER = 'JSON' THEN
        /* Easy case. */
        CONS_SCR.CUR_POS = 1
      ELSE DO
        /* Hunt for the pointer in the data. */
        SEARCH = POINTER || '.'
        DO INDX = 1 to CONS_DATA.0
          IF ABBREV(CONS_DATA.INDX, SEARCH) THEN DO
            CONS_SCR.CUR_POS = INDX
            LEAVE INDX
          END
        END
      END
      DO_RELOAD = 'YES'
    END
    /* Is this a specific type? */
    WHEN ABBREV(COMMAND, 'IS') THEN DO
      IF COMMAND = 'IS' THEN DO
        /* The two word format: IS STRING */
        NAME = UPPER(ARGA)
        ARGA = ARGB
      END
      ELSE
        /* One word format: IS_STRING */
        NAME = SUBSTR(COMMAND, 4)

      IF  NAME \= 'ARRAY' &,
          NAME \= 'OBJECT' &,
          NAME \= 'NUMBER' &,
          NAME \= 'STRING' &,
          NAME \= 'TRUE' &,
          NAME \= 'FALSE' &,
          NAME \= 'NULL' THEN DO
        CONS_SCR.MSG = 'Unknown command:' USER_INPUT
        RETURN 'NO'
      END

      INTERPRET 'CALL JSON_IS_' || NAME ARGA
      IF NAME \= 'TRUE' & NAME \= 'FALSE' & NAME \= 'NULL' THEN
        NAME = 'an' SUBSTR(NAME, 1, 1) || LOWER(SUBSTR(NAME, 2))
      IF RC < 0 THEN
        CONS_SCR.MSG = 'ERROR!' JSON_ERROR_TEXT()
      ELSE IF RC = 1 THEN
        CONS_SCR.MSG = 'Yes, it is' NAME '.'
      ELSE
        CONS_SCR.MSG = 'No, it is not' NAME '.'
    END
    /* List of members. */
    WHEN COMMAND = 'LIST' THEN DO
      IF ARGA = '' THEN
        LIST = JSON_LIST()
      ELSE IF ARGB = '' THEN
        LIST = JSON_LIST(ARGA)
      ELSE
        LIST = JSON_LIST(ARGA, ARGB)
      IF LIST < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Members:' LIST
      DO_RELOAD = 'YES'
    END
    /* Move the pointer to the given member. */
    WHEN COMMAND = 'MEMBER' THEN DO
      IF ARGA = '' THEN
        NEW_INDX = JSON_MEMBER()
      ELSE
        NEW_INDX = JSON_MEMBER(ARGA)
      IF NEW_INDX < 0 THEN
        CONS_SCR.MSG = 'ERROR!' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'New element index:' NEW_INDX
    END
    /* Get the Bricks metrics. */
    WHEN COMMAND = 'METRICS' THEN DO
      RC = JSON_GET('http://localhost:9000/metrics')
      IF RC < 0 THEN
        CONS_SCR.MSG = 'ERROR!' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Success!'
      DO_RELOAD = 'YES'
    END

    /* Name of the member at the pointer. */
    WHEN COMMAND = 'NAME' THEN DO
      IF ARGA = '' THEN
        NAME = JSON_NAME()
      ELSE
        NAME = JSON_NAME(ARGA)
      IF NAME < 0 THEN
        CONS_SCR.MSG = 'ERROR!' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Name:' NAME
    END
    /* Add an element to an object. */
    WHEN COMMAND = 'NEW' THEN DO
      IF ARGA = '' THEN
        NEW_INDX = JSON_NEW()
      ELSE IF ARGB = '' THEN
        NEW_INDX = JSON_NEW(ARGA)
      ELSE
        NEW_INDX = JSON_NEW(ARGA, ARGB)
      IF NEW_INDX < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Added a new element with index:' NEW_INDX
      DO_RELOAD = 'YES'
    END
    /* Next array or object element. */
    WHEN COMMAND = 'NEXT' | COMAND = 'N' THEN DO
      IF ARGA = '' THEN
        NEW_INDX = JSON_NEXT()
      ELSE
        NEW_INDX = JSON_NEXT(ARGA)
      IF NEW_INDX = 0 THEN
        CONS_SCR.MSG = 'Already on the last element.'
      ELSE IF JSON._ERRORCODE \= '' & JSON._ERRORCODE < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE DO
        IF ARGA = '' THEN
          CONS_SCR.MSG = 'New element index:' NEW_INDX
        ELSE
          CONS_SCR.MSG = 'New path:' NEW_INDX
      END
      DO_RELOAD = 'YES'
    END
    /* Move the pointer to the parent */
    WHEN COMMAND = 'PARENT' THEN DO
      DEPTH = JSON_PARENT()
      IF DEPTH = -22 THEN
        CONS_SCR.MSG = 'Already at the root.'
      ELSE IF DEPTH < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE IF DEPTH = 1 THEN
        CONS_SCR.MSG = 'Moved to the root.'
      ELSE
        CONS_SCR.MSG = 'New depth:' DEPTH
      DO_RELOAD = 'YES'
    END
    /* Parse JSON. */
    WHEN COMMAND = 'PARSE' THEN DO
      /* Parse exactly what the user entered. */
      RC = JSON_PARSE(SUBSTR(USER_INPUT, 6))
      IF RC < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Success!'
      DO_RELOAD = 'YES'
    END
    /* Get or set the pointer path. */
    WHEN COMMAND = 'PATH' THEN DO
      IF ARGA = '' THEN DO
        PATH = JSON_PATH()
        CONS_SCR.MSG = 'Path to current element:' PATH
      END
      ELSE DO
        PATH = JSON_PATH(ARGA)
        IF DATATYPE(PATH) = 'NUM' & PATH < 0 THEN
          CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
        ELSE IF PATH = '.' THEN
          CONS_SCR.MSG = 'Moved to the root.'
        ELSE
          CONS_SCR.MSG = 'New path:' PATH
      END
      DO_RELOAD = 'YES'
    END
    /* Pretty Print the JSON. */
    WHEN COMMAND = 'PRETTY' THEN DO
      CALL _CONS_PRETTY ARGA
      DO_RELOAD = 'YES'
    END
    /* Previous array or object element. */
    WHEN COMMAND = 'PREV' | COMMAND = 'P' THEN DO
      IF ARGA = '' THEN
        NEW_INDX = JSON_PREV()
      ELSE
        NEW_INDX = JSON_PREV(ARGA)
      IF NEW_INDX = 0 THEN
        CONS_SCR.MSG = 'Already on the first element.'
      ELSE IF JSON._ERRORCODE \= '' & JSON._ERRORCODE < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE DO
        IF ARGA = '' THEN
          CONS_SCR.MSG = 'New element index:' NEW_INDX
        ELSE
          CONS_SCR.MSG = 'New path:' NEW_INDX
      END
      DO_RELOAD = 'YES'
    END
    /* Move the pointer to the root. */
    WHEN COMMAND = 'ROOT' THEN DO
      CALL JSON_ROOT
      CONS_SCR.MSG = 'Moved to the root.'
      DO_RELOAD = 'YES'
    END
    /* Set an elements type. */
    WHEN COMMAND = 'SET_TYPE' THEN DO
      IF ARGA = '' THEN
        RC = JSON_SET_TYPE()
      ELSE IF ARGB = '' THEN
        RC = JSON_SET_TYPE(ARGA)
      ELSE
        RC = JSON_SET_TYPE(ARGA, ARGB)
      IF RC = '' THEN
        CONS_SCR.MSG = 'Type set to:' JSON_TYPE()
      ELSE IF RC < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Old Type:' RC 'New Type:' JSON_TYPE()
      DO_RELOAD = 'YES'
    END
    /* Set an elements value. */
    WHEN COMMAND = 'SET_VALUE' THEN DO
      IF ARGA = '' THEN
        RC = JSON_SET_VALUE()
      ELSE IF ARGB = '' THEN
        RC = JSON_SET_VALUE(ARGA)
      ELSE
        RC = JSON_SET_VALUE(ARGA, ARGB)
      IF RC < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Value set.'
      DO_RELOAD = 'YES'
    END
    /* Setting types. */
    WHEN ABBREV(COMMAND, 'SET') THEN DO
      IF COMMAND = 'SET' THEN DO
        /* The two word format: SET STRING */
        NAME = UPPER(ARGA)
        ARGA = ARGB
      END
      ELSE
        /* One word format: SET_STRING */
        NAME = SUBSTR(COMMAND, 5)
      IF  NAME \= 'ARRAY' &,
          NAME \= 'OBJECT' &,
          NAME \= 'NUMBER' &,
          NAME \= 'STRING' &,
          NAME \= 'TRUE' &,
          NAME \= 'FALSE' &,
          NAME \= 'NULL' THEN DO
        CONS_SCR.MSG = 'Unknown command:' USER_INPUT
        RETURN 'NO'
      END
      IF ARGA = '' THEN DO
        OLD_TYPE = JSON_TYPE()
        INTERPRET 'CALL JSON_SET_' || NAME
        NEW_TYPE = JSON_TYPE()
      END
      ELSE DO
        OLD_TYPE = JSON_TYPE(ARGA)
        INTERPRET 'CALL JSON_SET_' || NAME ARGA
        NEW_TYPE = JSON_TYPE(ARGA)
      END
      IF JSON._ERRORCODE \= '' & JSON._ERRORCODE < 0 THEN
        CONS_SCR.MSG = 'ERROR!' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Old Type:' OLD_TYPE 'New Type:' NEW_TYPE
      DO_RELOAD = 'YES'
    END
    /* Convert the JSON back to a string. */
    WHEN COMMAND = 'STRING' THEN DO
      CONS_SCR.MSG = JSON_STRING()
    END
    /* Run the parser tests. */
    WHEN COMMAND = 'TEST' THEN DO
      RC = _CONS_TESTS()
      IF RC < 0 THEN
        CONS_SCR.MSG = 'ERROR:' JSON_ERROR_TEXT()
      DO_RELOAD = 'YES'
    END
    /* Type at the pointer. */
    WHEN COMMAND = 'TYPE' THEN DO
      IF ARGA = '' THEN
        TYPE = JSON_TYPE()
      ELSE
        TYPE = JSON_TYPE(ARGA)
      IF JSON._ERRORCODE \= '' & JSON._ERRORCODE < 0 THEN
        CONS_SCR.MSG = 'ERROR!' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Type:' TYPE '-' JSON_TYPE_STRING(TYPE)
    END
    /* Value at the pointer. */
    WHEN COMMAND = 'VALUE' THEN DO
      IF ARGA = '' THEN
        VALUE = JSON_VALUE()
      ELSE
        VALUE = JSON_VALUE(ARGA)
      IF JSON._ERRORCODE \= '' & JSON._ERRORCODE < 0 THEN
        CONS_SCR.MSG = 'ERROR!' JSON_ERROR_TEXT()
      ELSE
        CONS_SCR.MSG = 'Value:' VALUE
    END
    /* The heck you say? */
    OTHERWISE DO
      CONS_SCR.OPTION = USER_INPUT
      CONS_SCR.MSG = 'Unknown command:' USER_INPUT
    END
  END
  RETURN DO_RELOAD

/* JSON Console HELP ==================================================== */

_CONS_HELP: PROCEDURE EXPOSE CONS_DATA. CONS_SCR. CONS_HELP. JSON.
  IF ARG() > 0 THEN
    TOPIC = ARG(1)
  ELSE
    TOPIC = ''

  /* Save the current state. */
  SAVE. = ''
  SAVE.SOURCE     = CONS_DATA.SOURCE
  SAVE.FIND_TEXT  = CONS_SCR.FIND_TEXT
  SAVE.CUR_POS    = CONS_SCR.CUR_POS
  SAVE.SCROLL     = CONS_SCR.SCROLL
  SAVE.SCROLL_AMT = CONS_DATA.SCROLL_AMT

  /* Load the help data. */
  IF CONS_HELP.0 = '' THEN
    CALL _CONS_LOAD_HELP
  CONS_DATA.SOURCE = 'HELP'
  CONS_SCR.CUR_POS = 1
  CALL _CONS_DATA_LOAD
  IF TOPIC \= '' THEN
    CALL _CONS_HELP_TOPIC TOPIC
  CALL _CONS_FILL_SCR

  /* Help loop. */
  CALL _JSON_CONSOLE_LOOP 'JSONHELP'

  /* Restore state. */
  CONS_DATA.SOURCE      = SAVE.SOURCE
  CONS_SCR.FIND_TEXT    = SAVE.FIND_TEXT
  CONS_SCR.CUR_POS      = SAVE.CUR_POS
  CONS_SCR.SCROLL       = SAVE.SCROLL
  CONS_DATA.SCROLL_AMT  = SAVE.SCROLL_AMT
  IF CONS_SCR.FIND_TEXT \= '' THEN
    CALL _CONS_FIND '', 'NO'
  RETURN

/* Locate a help topic. */
_CONS_HELP_TOPIC: PROCEDURE EXPOSE CONS_SCR. CONS_DATA.
  TOPIC = ARG(1)
  IF TOPIC = '' THEN
    RETURN

  DO INDX = 1 TO CONS_DATA.0
    ROW_TEXT = CONS_DATA.INDX
    IF ABBREV(ROW_TEXT, '#') THEN DO
      /* Found a topic. Is it the one we want? */
      IF ABBREV(UPPER(WORD(ROW_TEXT, 2)), UPPER(TOPIC)) THEN DO
        CONS_SCR.CUR_POS = INDX + 1
        RETURN
      END
    END
  END

  CONS_SCR.MSG = 'Topic "' || TOPIC || '" not found.'
  RETURN

/* Loads the console help text into CONS_HELP. */
_CONS_LOAD_HELP: PROCEDURE EXPOSE CONS_HELP.
  CONS_HELP.0 = 0
  CALL _CONS_LOAD_HELP_PUSH '# Welcome to the JSON Explorer help text'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '! To exit this help press PF3 or Type: QUIT'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'This is an overly complicated DEMO of my REXX JSON Library for Bricks.'
  CALL _CONS_LOAD_HELP_PUSH 'The intention is to demonstrate how the JSON library works.'
  CALL _CONS_LOAD_HELP_PUSH 'Nearly the entire library is accessible from this interface.'
  CALL _CONS_LOAD_HELP_PUSH 'And perhaps be a tool for working with JSON in general.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'What you see when you start JSON is the internal representation of the'
  CALL _CONS_LOAD_HELP_PUSH 'parsed JSON text. More details under the "Internals" topic.'
  CALL _CONS_LOAD_HELP_PUSH 'To jump there type:'
  CALL _CONS_LOAD_HELP_PUSH '@ ?Internals'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Note the symbols at the start of some lines:'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* "*" is a list.'
  CALL _CONS_LOAD_HELP_PUSH '* "#" is a help topic.'
  CALL _CONS_LOAD_HELP_PUSH '* "!" is an important note.'
  CALL _CONS_LOAD_HELP_PUSH '* "@" is something you type.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# Topics - Available help topics.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'To jump to a topic use one of:'
  CALL _CONS_LOAD_HELP_PUSH '@ HELP TOPIC or ?TOPIC'
  CALL _CONS_LOAD_HELP_PUSH 'Or enter the topic name then press PF1.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* Welcome    - Welcome to the JSON Explorer help text'
  CALL _CONS_LOAD_HELP_PUSH '* Topics     - Available help topics.'
  CALL _CONS_LOAD_HELP_PUSH '* Keys       - AID Keys'
  CALL _CONS_LOAD_HELP_PUSH '* Shortcuts  - Handy shortcuts are for convenience.'
  CALL _CONS_LOAD_HELP_PUSH '* JSON       - Commands for working with the parsed JSON.'
  CALL _CONS_LOAD_HELP_PUSH '* Paths      - Notes on using paths.'
  CALL _CONS_LOAD_HELP_PUSH '* RC         - Return codes.'
  CALL _CONS_LOAD_HELP_PUSH '* Types      - Type codes.'
  CALL _CONS_LOAD_HELP_PUSH '* DEMO       - The Bricks Metrics DEMO for the JSON Library.'
  CALL _CONS_LOAD_HELP_PUSH '* Internals  - How the JSON library works from the inside.'
  CALL _CONS_LOAD_HELP_PUSH '* Colors     - What the line colors mean.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# Keys - AID Keys'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* PF1  - Open the help to an optional topic.'
  CALL _CONS_LOAD_HELP_PUSH '* PF2  - Search for the entered text or search again with no text.'
  CALL _CONS_LOAD_HELP_PUSH '* PF3  - Exit JSON Explorer.'
  CALL _CONS_LOAD_HELP_PUSH '* PF4  - Recall the previously entered command.'
  CALL _CONS_LOAD_HELP_PUSH '* PF5  - Reload the parsed JSON data.'
  CALL _CONS_LOAD_HELP_PUSH '* PF6  - Jump to the top of the displayed data.'
  CALL _CONS_LOAD_HELP_PUSH '* PF7  - Scroll up.'
  CALL _CONS_LOAD_HELP_PUSH '* PF8  - Scroll down.'
  CALL _CONS_LOAD_HELP_PUSH '* PF9  - Jump to the bottom of the displayed data.'
  CALL _CONS_LOAD_HELP_PUSH '* PF10 - Scroll the screen to put the current path at the top.'
  CALL _CONS_LOAD_HELP_PUSH '* PF11 - Rotate the scroll amount: THIRD, HALF, PAGE, and LINE'
  CALL _CONS_LOAD_HELP_PUSH '* PF12 - Exit.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# Shortcuts - Handy shortcuts for your convenience.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '| Type this   | This happens    | Which means'
  CALL _CONS_LOAD_HELP_PUSH '+-------------+-----------------+-----------------------------------'
  CALL _CONS_LOAD_HELP_PUSH '| /TEXT       | FIND TEXT       | Search for TEXT.'
  CALL _CONS_LOAD_HELP_PUSH '| ?TOPIC      | HELP TOPIC      | Open HELP to TOPIC.'
  CALL _CONS_LOAD_HELP_PUSH '| -           | PARENT          | Go up one level in the JSON path.'
  CALL _CONS_LOAD_HELP_PUSH '| .           | ROOT            | Go to the root of the parsed JSON.'
  CALL _CONS_LOAD_HELP_PUSH '| .PATH.PATH  | PATH .PATH.PATH | Go directly to the absolute path.'
  CALL _CONS_LOAD_HELP_PUSH '| +PATH       | PATH +PATH      | Go to the relative path.'
  CALL _CONS_LOAD_HELP_PUSH '| {"M":"E"}   | PARSE {"M":"E"} | Parse JSON.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# Commands - Commands for working with the JSON Explorer Console.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'These commands are available in all modes, JSON, Help, Pretty and Test.'
  CALL _CONS_LOAD_HELP_PUSH 'Each command can be abbreviated as noted.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* B | BOT          - Jump to the bottom of the data or help text.'
  CALL _CONS_LOAD_HELP_PUSH '* M | DEMO         - Run the Bricks Metrics DEMO.'
  CALL _CONS_LOAD_HELP_PUSH '* E | EXIT         - Exit the JSON Transaction.'
  CALL _CONS_LOAD_HELP_PUSH '* D | DOWN         - Scroll down by the Scroll amount.'
  CALL _CONS_LOAD_HELP_PUSH '* H | HELP [TOPIC] - Display help on a given TOPIC.'
  CALL _CONS_LOAD_HELP_PUSH '* F | FIND [TEXT]  - Search for the given TEXT. With no args find again.'
  CALL _CONS_LOAD_HELP_PUSH '* L | LOCATE #     - Move to the given line #.'
  CALL _CONS_LOAD_HELP_PUSH '* Q | QUIT         - Quite JSON, or return from help.'
  CALL _CONS_LOAD_HELP_PUSH '* R | RELOAD       - Reload the data. Should not be needed.'
  CALL _CONS_LOAD_HELP_PUSH '*     RESET        - Clear the search text and highlighting.'
  CALL _CONS_LOAD_HELP_PUSH '* S | SCROLL [AMT] - Set the scroll amount: THIRD, HALF, PAGE, and LINE'
  CALL _CONS_LOAD_HELP_PUSH '* T | TOP          - Jump to the top of the data or help text.'
  CALL _CONS_LOAD_HELP_PUSH '* U | UP           - Scroll up by the Scroll amount.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# JSON - Commands for working with the parsed JSON.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Each of these commands are the Library API minus the leading "JSON_".'
  CALL _CONS_LOAD_HELP_PUSH 'Meaning to use this library to parse JSON you would use:'
  CALL _CONS_LOAD_HELP_PUSH '@ RC = JSON_PARSE("null")'
  CALL _CONS_LOAD_HELP_PUSH 'But in the JSON Explorer you would enter:'
  CALL _CONS_LOAD_HELP_PUSH '@ PARSE null'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'These commands are only available in the JSON Explorer mode.'
  CALL _CONS_LOAD_HELP_PUSH 'By default these work on the current pointer.'
  CALL _CONS_LOAD_HELP_PUSH 'Most commands will also work with an optional path.'
  CALL _CONS_LOAD_HELP_PUSH 'See Paths below for more details.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* CLEAR        - Clears the JSON data.'
  CALL _CONS_LOAD_HELP_PUSH '* COUNT [PATH] - Returns the number of elements in an array or object.'
  CALL _CONS_LOAD_HELP_PUSH '* DEPTH [PATH] - Return the depth at the current element or path.'
  CALL _CONS_LOAD_HELP_PUSH '* ERROR        - Display the most recent error text.'
  CALL _CONS_LOAD_HELP_PUSH '* ERROR_CODE   - Display the most recent error code.'
  CALL _CONS_LOAD_HELP_PUSH '* ESCAPE STR   - Escapes special characters in STR.'
  CALL _CONS_LOAD_HELP_PUSH '* GET          - Fetch then previously used URL then parse the JSON.'
  CALL _CONS_LOAD_HELP_PUSH '* GET URL      - Fetch then URL then parse the JSON.'
  CALL _CONS_LOAD_HELP_PUSH '* GO PATH      - Set the pointer then scroll the screen like HOME.'
  CALL _CONS_LOAD_HELP_PUSH '* HOME [PATH]  - Scroll the screen to put the current/given path on top.'
  CALL _CONS_LOAD_HELP_PUSH '* LIST [PATH]  - List the members of the current object or given path.'
  CALL _CONS_LOAD_HELP_PUSH '* LIST SEP     - List the members of the current object separated by SEP.'
  CALL _CONS_LOAD_HELP_PUSH '* MEMBER NAME  - Move the pointer to the given member name.'
  CALL _CONS_LOAD_HELP_PUSH '* METRICS      - Fetch the Bricks Metrics from: http://localhost:9000/metrics'
  CALL _CONS_LOAD_HELP_PUSH '* NAME [PATH]  - The name of the current member or path.'
  CALL _CONS_LOAD_HELP_PUSH '* NEXT         - Moves to the next element in the current array or object.'
  CALL _CONS_LOAD_HELP_PUSH '* NEXT PATH    - Moves to the next element at the given path.'
  CALL _CONS_LOAD_HELP_PUSH '* PARENT       - Moves to the parent of the current element.'
  CALL _CONS_LOAD_HELP_PUSH '* PARSE JSON   - Parse the given JSON. Do not quote the JSON.'
  CALL _CONS_LOAD_HELP_PUSH '* PATH         - Returns the path for the current element.'
  CALL _CONS_LOAD_HELP_PUSH '* PATH PATH    - Moves the pointer to the given path.'
  CALL _CONS_LOAD_HELP_PUSH '* PRETTY       - Pretty prints the parsed JSON.'
  CALL _CONS_LOAD_HELP_PUSH '* PREV         - Moves to the previous element in the current array or object.'
  CALL _CONS_LOAD_HELP_PUSH '* PREV PATH    - Moves to the previous element at the given path.'
  CALL _CONS_LOAD_HELP_PUSH '* ROOT         - Moves the pointer to the JSON root.'
  CALL _CONS_LOAD_HELP_PUSH '* STRING       - Converts the parsed JSON back into a string.'
  CALL _CONS_LOAD_HELP_PUSH '* TEST         - Run the JSON tests.'
  CALL _CONS_LOAD_HELP_PUSH '* TYPE [PATH]  - Returns the type of the current element or given path.'
  CALL _CONS_LOAD_HELP_PUSH '* VALUE [PATH] - Returns the value of the current element or given path.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'These are special cases for checking the type of an element.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* IS_ARRAY       - Checks if the current element is an Array.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_ARRAY PATH  - Checks if the element at the given path is an Array.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_OBJECT      - Checks if the current element is an Object.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_OBJECT PATH - Checks if the element at the given path is an Object.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_NUMBER      - Checks if the current element is a Number.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_NUMBER PATH - Checks if the element at the given path is a Number.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_STRING      - Checks if the current element is a String.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_STRING PATH - Checks if the element at the given path is a String.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_TRUE        - Checks if the current element is true.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_TRUE PATH   - Checks if the element at the given path is true.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_FALSE       - Checks if the current element is false.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_FALSE PATH  - Checks if the element at the given path is false.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_NULL        - Checks if the current element is null.'
  CALL _CONS_LOAD_HELP_PUSH '* IS_NULL PATH   - Checks if the element at the given path is null.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Can also be used without the underscore. For example:'
  CALL _CONS_LOAD_HELP_PUSH '@ IS NULL .member_name'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'These commands permute the parsed JSON.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* ADD                - Add a new element to the current array.'
  CALL _CONS_LOAD_HELP_PUSH '* ADD PATH           - Add a new element to the array at the given path.'
  CALL _CONS_LOAD_HELP_PUSH '* DELETE             - Delete the current element.'
  CALL _CONS_LOAD_HELP_PUSH '* DELETE PATH        - Delete the element at the given path.'
  CALL _CONS_LOAD_HELP_PUSH '* NEW NAME           - Create a new member in the current object.'
  CALL _CONS_LOAD_HELP_PUSH '* NEW PATH NAME      - Create a new member at the given path.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_TYPE TYPE      - Sets the type of the current element.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_TYPE PATH TYPE - Sets the type for the element at the given path.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_VALUE VAL      - Sets the value for the current element.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_VALUE PATH VAL - Sets the value for the element at the given path.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'These are special cases for setting the type and value at once.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* SET_ARRAY              - Set to an Array.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_ARRAY PATH         - Set to an Array.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_OBJECT             - Set to an Object.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_OBJECT PATH        - Set to an Object.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_NUMBER VALUE       - Set type to Number and set value.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_NUMBER PATH VALUE  - Set type to Number and set value.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_STRING VALUE       - Set type to String and set value.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_STRING PATH VALUE  - Set type to String and set value.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_TRUE               - Set to True.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_TRUE PATH          - Set to True.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_FALSE              - Set to False.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_FALSE PATH         - Set to False.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_NULL               - Set to Null.'
  CALL _CONS_LOAD_HELP_PUSH '* SET_NULL PATH          - Set to Null.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Can also be used without the underscore. For example:'
  CALL _CONS_LOAD_HELP_PUSH '@ SET STRING .1 "String?"'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# Paths - Notes on using paths.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Paths start with a period "." or plus "+" and contain indexes or member'
  CALL _CONS_LOAD_HELP_PUSH 'names separated by periods. Paths starting with a period "." are absolute'
  CALL _CONS_LOAD_HELP_PUSH 'and start from the root. Paths starting with a plus "+" start at the'
  CALL _CONS_LOAD_HELP_PUSH 'current element.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'If a member name contains a period "." or is only a number then quote it.'
  CALL _CONS_LOAD_HELP_PUSH 'Anywhere a path is accepted you may also give an array index or member name.'
  CALL _CONS_LOAD_HELP_PUSH 'A path is really just the tail off the JSON STEM of the array indexes.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Examples:'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '@ ["This", {"is": "JSON!"}, [1234, null, true, "String."]]'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* ".1" is the string "This".'
  CALL _CONS_LOAD_HELP_PUSH '* ".2.is" and ".2.1" are both the member "is" in the nested object.'
  CALL _CONS_LOAD_HELP_PUSH '* ".2.''is''" is the same path with the member name quoted.'
  CALL _CONS_LOAD_HELP_PUSH '* ".3.2" is the null in the nested array.'
  CALL _CONS_LOAD_HELP_PUSH '* "+1" is the number 1234 in the nested array when the pointer is ".3".'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# RC - Return codes.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Functions normally returns either a new value or 1 on success.'
  CALL _CONS_LOAD_HELP_PUSH 'If there is an error a negative value will be returned.'
  CALL _CONS_LOAD_HELP_PUSH 'Use JSON_ERROR_TEXT() to get the text for the most recent error.'
  CALL _CONS_LOAD_HELP_PUSH 'Use JSON_ERROR_CODE() to get the most recent error code.'
  CALL _CONS_LOAD_HELP_PUSH '0 is never used as an error.'
  CALL _CONS_LOAD_HELP_PUSH '0 is only used by next and prev to indicate end of list reached.'
  CALL _CONS_LOAD_HELP_PUSH 'Note that JSON_VALUE() will return '' on error. Check JSON_ERROR_CODE().'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'General error codes:'
  CALL _CONS_LOAD_HELP_PUSH '+-------+--------------------------------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Code  | Description                                                        |'
  CALL _CONS_LOAD_HELP_PUSH '+-------+--------------------------------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '|  0    | No further results.                                                |'
  CALL _CONS_LOAD_HELP_PUSH '| -1    | Something failed.                                                  |'
  CALL _CONS_LOAD_HELP_PUSH '|       | You should not see this unless I made a big mistake.               |'
  CALL _CONS_LOAD_HELP_PUSH '| -20   | Missing argument.                                                  |'
  CALL _CONS_LOAD_HELP_PUSH '| -21   | Invalid type for the function.                                     |'
  CALL _CONS_LOAD_HELP_PUSH '| -22   | Already at the root.                                               |'
  CALL _CONS_LOAD_HELP_PUSH '| -23   | Member already exists in the object.                               |'
  CALL _CONS_LOAD_HELP_PUSH '| -24   | Path is invalid or does not exist.                                 |'
  CALL _CONS_LOAD_HELP_PUSH '| -25   | Index out of range or does not exist.                              |'
  CALL _CONS_LOAD_HELP_PUSH '| -26   | Member does not exist.                                             |'
  CALL _CONS_LOAD_HELP_PUSH '+-------+--------------------------------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'JSON_GET(URL) error codes:'
  CALL _CONS_LOAD_HELP_PUSH '+-------+--------------------------------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Code  | Description                                                        |'
  CALL _CONS_LOAD_HELP_PUSH '+-------+--------------------------------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| -30   | Error parsing the given URL.                                       |'
  CALL _CONS_LOAD_HELP_PUSH '| -31   | Error opening a connection to the host in the URL.                 |'
  CALL _CONS_LOAD_HELP_PUSH '| -32   | Error sending the HTTP request to the given URL.                   |'
  CALL _CONS_LOAD_HELP_PUSH '+-------+--------------------------------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Parsing specific errors codes:'
  CALL _CONS_LOAD_HELP_PUSH '+-------+---------------------+----------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Code  | Function            | Description                                  |'
  CALL _CONS_LOAD_HELP_PUSH '+-------+---------------------+----------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| -10   | JSON_PARSE          | Unexpected end of JSON.                      |'
  CALL _CONS_LOAD_HELP_PUSH '| -13   | _JSON_PARSE_OBJECT  | Expected a quoted member name.               |'
  CALL _CONS_LOAD_HELP_PUSH '| -14   | _JSON_PARSE_OBJECT  | Expected a colon, ":", after member name.    |'
  CALL _CONS_LOAD_HELP_PUSH '| -16   | _JSON_PARSE_STRING  | Unexpected end of string.                    |'
  CALL _CONS_LOAD_HELP_PUSH '| -11   | _JSON_PARSE_ELEMENT | Unknown element type.                        |'
  CALL _CONS_LOAD_HELP_PUSH '+-------+---------------------+----------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Integrated test specific errors codes:'
  CALL _CONS_LOAD_HELP_PUSH '+-------+---------------------+----------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Code  | Function            | Description                                  |'
  CALL _CONS_LOAD_HELP_PUSH '+-------+---------------------+----------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| -90   | JSON_TESTS          | Unable to read the tests file.               |'
  CALL _CONS_LOAD_HELP_PUSH '| -91   | JSON_TESTS          | Required test variable missing.              |'
  CALL _CONS_LOAD_HELP_PUSH '+-------+---------------------+----------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# Types - Type codes.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Types are stored as a single letter code.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '+------+----------+-----------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Code | Meaning  | JSON                  |'
  CALL _CONS_LOAD_HELP_PUSH '+------+----------+-----------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| A    | Array    | ["Array"]             |'
  CALL _CONS_LOAD_HELP_PUSH '| F    | False    | false                 |'
  CALL _CONS_LOAD_HELP_PUSH '| N    | Number   | 123.456               |'
  CALL _CONS_LOAD_HELP_PUSH '| O    | Object   | {"Member": "Element"} |'
  CALL _CONS_LOAD_HELP_PUSH '| S    | String   | "String"              |'
  CALL _CONS_LOAD_HELP_PUSH '| T    | True     | true                  |'
  CALL _CONS_LOAD_HELP_PUSH '| U    | NULL     | null                  |'
  CALL _CONS_LOAD_HELP_PUSH '| ?    | Not set. |                       |'
  CALL _CONS_LOAD_HELP_PUSH '+------+----------+-----------------------+'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# DEMO - The Bricks Metrics DEMO for the JSON Library.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'As a demo of the JSON library the Bricks metrics are fetched then displayed.'
  CALL _CONS_LOAD_HELP_PUSH 'The metrics are retrieved from the URL: http://localhost:9000/metrics'
  CALL _CONS_LOAD_HELP_PUSH 'The metrics are displayed in a similar format to the CEMT MONITOR node.'
  CALL _CONS_LOAD_HELP_PUSH 'Pressing ENTER or PF5 will refresh the metrics.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# Internals - How the JSON library works from the inside.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '! The JSON Explorer makes assumptions about the JSON data.'
  CALL _CONS_LOAD_HELP_PUSH '! Messing with internals can cause unusual behavior.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'This information is if you want to bypass the public interface and work'
  CALL _CONS_LOAD_HELP_PUSH 'directly with the parsed JSON data.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'The parsed data is stored in the STEM "JSON." starting at the top level.'
  CALL _CONS_LOAD_HELP_PUSH 'The type for each element is stored in "STEM.TYPE". See "Types" above.'
  CALL _CONS_LOAD_HELP_PUSH 'The value for scalar values are stored in "STEM.VALUE".'
  CALL _CONS_LOAD_HELP_PUSH 'Arrays and objects are stored as REXX arrays.'
  CALL _CONS_LOAD_HELP_PUSH 'The number of elements in an array or object is stored in "STEM.0".'
  CALL _CONS_LOAD_HELP_PUSH 'Each element is stored in as STEM with an incrementing number. Eg. .1, .2 ...'
  CALL _CONS_LOAD_HELP_PUSH 'Objects store the member name in "STEM.MEMBER".'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'To scan an array simply loop over the TAILs of the array STEM.'
  CALL _CONS_LOAD_HELP_PUSH 'To find a member in an object check each of the "MEMBER" tails for the name.'
  CALL _CONS_LOAD_HELP_PUSH 'See the functions JSON_NEXT(), JSON_PREV() and JSON_PATH(NAME) for examples.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'For example this table shows the internal representation of the JSON:'
  CALL _CONS_LOAD_HELP_PUSH '@ ["This", {"is": "JSON!"}, [1234, null, true, "String."]]'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '+---------------------------+---------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| STEM                      | Meaning                                     |'
  CALL _CONS_LOAD_HELP_PUSH '+---------------------------+---------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.TYPE = A             | The root level element is an array.         |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.0 = 3                | The root level array has 3 elements.        |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.1.TYPE = S           | This element is a string.                   |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.1.VALUE = This       | The first element in the root level array.  |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.TYPE = O           | This element is an object.                  |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.0 = 1              | The number of elements in the object.       |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.1.MEMBER = is      | The name of the first member.               |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.1.TYPE = S         | The type of the first member.               |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.1.VALUE = JSON     | The value for first member is "is".         |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.TYPE = A           | This element is an array.                   |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.0 = 4              | The second array has 4 elements.            |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.1.TYPE = N         | This element is a number.                   |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.1.VALUE = 1234     | First element of the second array.          |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.2.TYPE = U         | This element is null.                       |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.2.VALUE = null     | The second element in the second array.     |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.3.TYPE = T         | This element is a number,                   |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.3.VALUE = true     | The third element of the second array.      |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.4.TYPE = S         | This element is a string.                   |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.4.VALUE = String.  | The fourth element in the second array.     |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._JSON = ["This",     | The original JSON text that was parsed.     |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._LEN = 61            | Length of the text.                         |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._END = 63            | Where parsing ended in the original text.   |'
  CALL _CONS_LOAD_HELP_PUSH '+---------------------------+---------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'The same example, rearranged to show how the parsed JSON matches the text.'
  CALL _CONS_LOAD_HELP_PUSH '+--------------------------+---------------+-------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| STEM                     | JSON          | Meaning                 |'
  CALL _CONS_LOAD_HELP_PUSH '+--------------------------+---------------+-------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.TYPE = A            | [             | This is an array.       |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.0 = 3               |               | 3 items in this array.  |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.1.TYPE = S          |               | This is a string.       |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.1.VALUE = This      |   "This",     | The string "This".      |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.TYPE = O          |   {           | This is an object       |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.0 = 1             |               | One item in the object. |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.1.MEMBER = is     |     "is":     | The Member "is".        |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.1.TYPE = S        |               | This is a string        |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.2.1.VALUE = JSON    |     "JSON!"   | The string "JSON!".     |'
  CALL _CONS_LOAD_HELP_PUSH '|                          |   },          | Illustration only.      |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.TYPE = A          |   [           | This is of an array.    |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.0 = 4             |               | 4 items in this array.  |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.1.TYPE = N        |               | This is a number.       |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.1.VALUE = 1234    |     1234,     | The number 1234         |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.2.TYPE = U        |               | This is null.           |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.2.VALUE = null    |     null,     | null                    |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.3.TYPE = T        |               | This is true.           |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.3.VALUE = true    |     true,     | true                    |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.4.TYPE = S        |               | This is a string.       |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON.3.4.VALUE = String. |     "String." | The string "String."    |'
  CALL _CONS_LOAD_HELP_PUSH '|                          |   ]           | Illustration only.      |'
  CALL _CONS_LOAD_HELP_PUSH '|                          | ]             | Illustration only.      |'
  CALL _CONS_LOAD_HELP_PUSH '+--------------------------+---------------+-------------------------+'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'How each type is represented internally.'
  CALL _CONS_LOAD_HELP_PUSH '+---------+------------------+-----------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Type    | Tail             | Meaning                           |'
  CALL _CONS_LOAD_HELP_PUSH '+---------+------------------+-----------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Array   | .TYPE = A        | Array type.                       |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .0 = 1           | Number of elements in the array.  |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .1.VALUE         | The value of the first element.   |'
  CALL _CONS_LOAD_HELP_PUSH '+---------+------------------+-----------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Object  | .TYPE = O        | Object type.                      |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .0 = 1           | Number of elements in the object. |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .1.MEMBER = NAME | The NAME of the first member.     |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .1.VALUE         | The value of the first member.    |'
  CALL _CONS_LOAD_HELP_PUSH '+---------+------------------+-----------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| String  | .TYPE = S        | String type.                      |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .VALUE = STRING  | The SRING value of the string.    |'
  CALL _CONS_LOAD_HELP_PUSH '+---------+------------------+-----------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Number  | .TYPE = N        | Number type.                      |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .VALUE = NUMBER  | The NUMBER value of the number.   |'
  CALL _CONS_LOAD_HELP_PUSH '+---------+------------------+-----------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| true    | .TYPE = T        | True type.                        |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .VALUE = true    | The value true.                   |'
  CALL _CONS_LOAD_HELP_PUSH '+---------+------------------+-----------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| false   | .TYPE = F        | False type.                       |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .VALUE = false   | The value false.                  |'
  CALL _CONS_LOAD_HELP_PUSH '+---------+------------------+-----------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| null    | .TYPE = U        | Null type.                        |'
  CALL _CONS_LOAD_HELP_PUSH '|         | .VALUE = null    | The value null.                   |'
  CALL _CONS_LOAD_HELP_PUSH '+---------+------------------+-----------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'JSON Element Tails:'
  CALL _CONS_LOAD_HELP_PUSH '+-----------------+-------------------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Tail            | Purpose                                               |'
  CALL _CONS_LOAD_HELP_PUSH '+-----------------+-------------------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| .0              | The number of elements in Arrays and Objects.         |'
  CALL _CONS_LOAD_HELP_PUSH '| .MEMBER         | The name of the member. For Objects.                  |'
  CALL _CONS_LOAD_HELP_PUSH '| .TYPE           | The element type.                                     |'
  CALL _CONS_LOAD_HELP_PUSH '| .VALUE          | The element value. Not used for Arrays or Objects.    |'
  CALL _CONS_LOAD_HELP_PUSH '+-----------------+-------------------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Internal meta data:'
  CALL _CONS_LOAD_HELP_PUSH '+-------------------+---------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| Variable          | Purpose                                     |'
  CALL _CONS_LOAD_HELP_PUSH '+-------------------+---------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._END         | The position in the string parsing stopped. |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._ERROR       | Text from the most recent error.            |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._ERRORCODE   | The most recent error code.                 |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._LEN         | The length of the original JSON.            |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._PP          | Pretty printed JSON array.                  |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._PTR         | Used to explore the parsed JSON.            |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._STATUS      | HTTP Status code from JSON_GET(URL).        |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._JSON        | The original JSON text.                     |'
  CALL _CONS_LOAD_HELP_PUSH '| JSON._URL         | The URL passed to JSON_GET(URL).            |'
  CALL _CONS_LOAD_HELP_PUSH '+-------------------+---------------------------------------------+'
  CALL _CONS_LOAD_HELP_PUSH '(Please do not modify these.)'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '# Colors - What the line colors mean.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH '* CYAN     Line contains the search text.'
  CALL _CONS_LOAD_HELP_PUSH '* YELLOW   The line is so wide it wrapped. Note the "..." ath the end.'
  CALL _CONS_LOAD_HELP_PUSH '* GREEN    JSON internal meta data.'
  CALL _CONS_LOAD_HELP_PUSH '* PINK     The line matches the current path. but not for the root.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Colors specific to HELP:'
  CALL _CONS_LOAD_HELP_PUSH '* BLUE     General text.'
  CALL _CONS_LOAD_HELP_PUSH '* GREEN    Formatted tables and lists, like this one.'
  CALL _CONS_LOAD_HELP_PUSH '* PINK     REXX code examples.'
  CALL _CONS_LOAD_HELP_PUSH '* RED      Take note. This might be important.'
  CALL _CONS_LOAD_HELP_PUSH '* WHITE    Topic header. Separates sections.'
  CALL _CONS_LOAD_HELP_PUSH ''
  CALL _CONS_LOAD_HELP_PUSH 'Press PF6 to return to the top.'
  RETURN

/* Push text into CONS_HELP like a stack. */
_CONS_LOAD_HELP_PUSH: PROCEDURE EXPOSE CONS_HELP.
  CONS_HELP.0 = CONS_HELP.0 + 1
  INDX = CONS_HELP.0
  CONS_HELP.INDX = ARG(1)
  RETURN

/* JSON Tests Console =================================================== */

/* Run the JSON Tests then display the result. */
_CONS_TESTS: PROCEDURE EXPOSE CONS_DATA. CONS_SCR. CONS_HELP. JSON. JSON_TESTS.
  /* Save the current state. */
  SAVE. = ''
  SAVE.SOURCE     = CONS_DATA.SOURCE
  SAVE.FIND_TEXT  = CONS_SCR.FIND_TEXT
  SAVE.CUR_POS    = CONS_SCR.CUR_POS
  SAVE.SCROLL     = CONS_SCR.SCROLL
  SAVE.SCROLL_AMT = CONS_DATA.SCROLL_AMT

  /* Run the tests. */
  RC = JSON_TESTS()
  IF RC < 0 THEN
    RETURN RC

  /* Setup the data and screen. */
  CONS_SCR.TTOTAL = JSON_TESTS.TOTAL
  CONS_SCR.TFAIL = JSON_TESTS.FAIL
  CONS_SCR.TPASS = JSON_TESTS.PASS
  CONS_DATA.SHOW_DETAIL = 'YES'
  CONS_DATA.SOURCE = 'TEST'
  CONS_SCR.CUR_POS = 1
  CALL _CONS_DATA_LOAD
  CALL _CONS_FILL_SCR

  /* Test result loop. */
  CALL _JSON_CONSOLE_LOOP 'JSONTESTS'

  /* Restore state. */
  CONS_DATA.SOURCE      = SAVE.SOURCE
  CONS_SCR.FIND_TEXT    = SAVE.FIND_TEXT
  CONS_SCR.CUR_POS      = SAVE.CUR_POS
  CONS_SCR.SCROLL       = SAVE.SCROLL
  CONS_DATA.SCROLL_AMT  = SAVE.SCROLL_AMT
  IF CONS_SCR.FIND_TEXT \= '' THEN
    CALL _CONS_FIND '', 'NO'
  RETURN 1

/* JSON Pretty Print ==================================================== */

/* Run the JSON Tests then display the result. */
_CONS_PRETTY: PROCEDURE EXPOSE CONS_DATA. CONS_SCR. CONS_HELP. JSON. JSON_TESTS.
  IF ARG() > 0 THEN
    INDENT = ARG(1)

  /* Save the current state. */
  SAVE. = ''
  SAVE.SOURCE     = CONS_DATA.SOURCE
  SAVE.FIND_TEXT  = CONS_SCR.FIND_TEXT
  SAVE.CUR_POS    = CONS_SCR.CUR_POS
  SAVE.SCROLL     = CONS_SCR.SCROLL
  SAVE.SCROLL_AMT = CONS_DATA.SCROLL_AMT

  /* Pretty print the parsed JSON. */
  RC = JSON_PRETTY(INDENT)
  IF RC < 0 THEN
    RETURN RC

  /* Setup the data and screen. */
  CONS_DATA.SOURCE = 'PRETTY'
  CONS_SCR.CUR_POS = 1
  CALL _CONS_DATA_LOAD
  CALL _CONS_FILL_SCR

  /* Test result loop. */
  CALL _JSON_CONSOLE_LOOP 'JSONPRETTY'

  /* Restore state. */
  CONS_DATA.SOURCE      = SAVE.SOURCE
  CONS_SCR.FIND_TEXT    = SAVE.FIND_TEXT
  CONS_SCR.CUR_POS      = SAVE.CUR_POS
  CONS_SCR.SCROLL       = SAVE.SCROLL
  CONS_DATA.SCROLL_AMT  = SAVE.SCROLL_AMT
  IF CONS_SCR.FIND_TEXT \= '' THEN
    CALL _CONS_FIND '', 'NO'
  RETURN

/* Bricks Metrics DEMO ================================================== */

/* A demonstration using the Bricks metrics. */
/* Note: The JSON STEM is not exposed, creating a new blank STEM. */
_CONS_DEMO: PROCEDURE EXPOSE CONS_DATA.
  /* Screen interface. */
  DEMO_SCR. = ''

  EXEC CICS ASSIGN
    TERMID(SYSTERM)
    USERID(SYSUSER)
  END-EXEC

  /* Demo loop. */
  DO FOREVER
    /* Load the metrics. */
    DROP DEMO_SCR
    CALL _CONS_DEMO_LOAD

    EXEC CICS ASKTIME ABSTIME(NOW) END-EXEC
    EXEC CICS FORMATTIME
      ABSTIME(NOW)
      YYYYMMDD(SYSDATE) DATESEP('-')
      TIME(SYSTIME)  TIMESEP(':')
      DAYOFWEEK(WS-DOW)
    END-EXEC
    DEMO_SCR.SDATE = SYSDATE
    DEMO_SCR.STIME = SYSTIME
    DEMO_SCR.TIME = TIME()
    DEMO_SCR.TERMID = SYSTERM
    DEMO_SCR.USERID = UPPER(SYSUSER)
    EXEC CICS CONVERSE MAP('METRICSDEMO') MAPSET(CONS_DATA.MAPSET) FROM(DEMO_SCR.) INTO(DEMO_SCR.) ERASE END-EXEC

    /* Handle the AID keys. */
    AID = C2X(EIBAID)
    SELECT
      /* Exit. */
      WHEN AID = 'F3' THEN DO
        RETURN
      END
      /* Reload. */
      WHEN AID = 'F5' THEN DO
        CONS_DATA.SOURCE = 'JSON'
        DO_RELOAD = 'YES'
      END
      /* Exit. */
      WHEN AID = '7C' THEN DO /* PF12 */
        RETURN
      END
      OTHERWISE NOP
    END

  END
  RETURN

/* Load the metrics data into DEMO_SCR. */
_CONS_DEMO_LOAD: PROCEDURE EXPOSE CONS_DATA. DEMO_SCR.
    RC = JSON_GET('http://localhost:9000/metrics')
    IF RC < 0 THEN DO
      DEMO_SCR.MSG = 'Unable to load metrics. Are they enabled?' JSON_ERROR_TEXT()
    END

    /* Copy the metrics to the screen. */
    DEMO_SCR.UPTIME   = RIGHT(_CONS_DEMO_UPTIME(JSON_VALUE('.uptime_seconds')), 9)
    DEMO_SCR.MEM_HEAP = RIGHT(_CONS_DEMO_BYTES(JSON_VALUE('.memory.heap_alloc_bytes')), 12)
    DEMO_SCR.MEM_SYS  = RIGHT(_CONS_DEMO_BYTES(JSON_VALUE('.memory.sys_bytes')), 12)
    DEMO_SCR.MEM_OBJ  = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.memory.heap_objects')), 10)
    DEMO_SCR.GC_NUM   = RIGHT(JSON_VALUE('.gc.num'), 9)
    DEMO_SCR.GC_LAST  = RIGHT(_CONS_DEMO_NS(JSON_VALUE('.gc.last_pause_ns')), 12)
    DEMO_SCR.GC_TOTAL = RIGHT(_CONS_DEMO_NS(JSON_VALUE('.gc.total_pause_ns')), 12)
    DEMO_SCR.CPU_USER = RIGHT(_CONS_DEMO_SECONDS(JSON_VALUE('.cpu.user_seconds')), 11)
    DEMO_SCR.CPU_SYS  = RIGHT(_CONS_DEMO_SECONDS(JSON_VALUE('.cpu.sys_seconds')), 11)
    DEMO_SCR.RUN_GOR  = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.runtime.goroutines')), 9)
    DEMO_SCR.RUN_CPUS = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.runtime.num_cpu')), 9)
    DEMO_SCR.RUN_GOV  = RIGHT(JSON_VALUE('.runtime.go_version'), 9)

    DEMO_SCR.REG_TERM = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.active_terminals')), 6)
    DEMO_SCR.REG_SON  = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.signed_on_users')), 6)
    DEMO_SCR.REG_ATXN = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.active_transactions')), 6)
    DEMO_SCR.REG_FILE = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.known_files')), 6)
    DEMO_SCR.REG_ACPT = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.accepts')), 6)
    DEMO_SCR.REG_REJT = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.rejects')), 6)
    DEMO_SCR.REG_AS   = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.auth_success')), 6)
    DEMO_SCR.REG_AF   = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.auth_failure')), 6)
    DEMO_SCR.REG_TTR  = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.total_txn_run')), 6)
    DEMO_SCR.REG_TTF  = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.registry.total_txn_failed')), 6)
    DEMO_SCR.WALL     = RIGHT(JSON_VALUE('.wallclock_unix'), 10)

    /* Add the verbs from '.exec_cics.by_verb'. */
    DEMO_SCR.CTOTAL   = RIGHT(_CONS_DEMO_NUM(JSON_VALUE('.exec_cics.total')), 8)
    CALL JSON_PATH '.exec_cics.by_verb.1' /* The first verb. */
    INDX = 1
    DO FOREVER
      CALL VALUE 'DEMO_SCR.CVERB'  || INDX, JSON_NAME()
      CALL VALUE 'DEMO_SCR.CVALUE' || INDX, RIGHT(_CONS_DEMO_NUM(JSON_VALUE()), 8)

      /* Loop until the last verb is encountered. */
      IF JSON_NEXT() = 0 THEN
        LEAVE

      /* Or until the last row in the map. */
      INDX = INDX + 1
      IF INDX > 18 THEN
        LEAVE
    END
  RETURN

/* Convert bytes into a human friendly form. */
_CONS_DEMO_BYTES: PROCEDURE
  IF ARG() < 1 | ARG(1) = '' THEN
    RETURN ''
  NUM = ARG(1)

  /* Gigabytes? */
  IF NUM > (1024 * 1024 * 1024) THEN DO
    RETURN TRUNC(NUM / (1024 * 1024 * 1024), 2) 'GB'
  END

  /* Megabytes? */
  IF NUM > (1024 * 1024) THEN DO
    RETURN TRUNC(NUM / (1024 * 1024), 2) 'MB'
  END

  /* Kilobytes. */
  IF NUM > 1024 THEN DO
    RETURN TRUNC(NUM / 1024, 2) 'KB'
  END

  /* Bytes. */
  RETURN NUM 'B'

/* Convert number into a human friendly form. */
_CONS_DEMO_NUM: PROCEDURE
  IF ARG() < 1 | ARG(1) = '' THEN
    RETURN ''
  NUM = ARG(1)
  STR = ''
  DO WHILE LENGTH(NUM) > 3
    STR = ',' || SUBSTR(NUM, LENGTH(NUM) - 2) || STR
    NUM = SUBSTR(NUM, 1, LENGTH(NUM) - 3)
  END
  RETURN NUM || STR

/* Convert nano seconds into a human friendly form. */
_CONS_DEMO_NS: PROCEDURE
  IF ARG() < 1 | ARG(1) = '' THEN
    RETURN ''
  NUM = ARG(1)
  RETURN TRUNC(NUM / 1000000, 2) 'ms'

/* Convert seconds into a human friendly form. */
_CONS_DEMO_SECONDS: PROCEDURE
  IF ARG() < 1 | ARG(1) = '' THEN
    RETURN ''
  SECS = ARG(1)
  MINS = 0
  IF SECS > 60 THEN DO
    MINS = INT(SECS / 60)
    SECS = TRUNC(SECS // 60, 0)
    RETURN MINS 'm' TRUNC(SECS, 2) 's'
  END
  RETURN TRUNC(SECS, 2) 's'

/* Convert uptime seconds into an elapsed time. */
_CONS_DEMO_UPTIME: PROCEDURE
  IF ARG() < 1 | ARG(1) = '' THEN
    RETURN ''
  SECS = TRUNC(ARG(1), 0)
  MINS = 0
  HOURS = 0

  IF SECS > (60 * 60) THEN DO
    HOURS = INT(SECS / (60 * 60))
    SECS = TRUNC(SECS // (60 * 60))
  END

  IF SECS > 60 THEN DO
    MINS = INT(SECS / 60)
    SECS = TRUNC(SECS // 60, 0)
  END

  RETURN HOURS || ':' || RIGHT(MINS, 2, '0') || ':' || SECS

/* vim: set ts=2 sw=2  sts=2: */
