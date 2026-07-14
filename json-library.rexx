/* Top of JSON Library. */

/* This is the main part of the JSON library.                             */
/* This does not include the permutation or testing code.                 */
/* See the files 'json-permutation.rexx' and 'json-testing.rexx'.         */

/* JSON Parser Interface ======================================= Public = */

/* Parse JSON, placing it into the STEM JSON.                             */
/* Returns the position in the string parsing ended.                      */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to store the parsed JSON. Optional.   */
/*  STRING  - The JSON string to parse.                                   */
/*                                                                        */
/* Returns:                                                               */
/*  The position in the JSON string where parsing stopped.                */
/*  -10 if there is nothing to parse or expected end of JSON.             */
/*  Any other negative value from parsing.                                */
JSON_PARSE: PROCEDURE EXPOSE JSON.
  CALL _JSON_CLEAR_ERROR
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('Nothing to parse.', -10)

  /* If a pointer was given append to it. Otherwise start from scratch. */
  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_PARSE')
    IF POINTER <= 0 THEN
      RETURN POINTER
    STRING = ARG(2)
  END
  ELSE DO
    STRING = ARG(1)
    CALL JSON_CLEAR
    POINTER = JSON._PTR
  END

  /* Save the JSON text and length. */
  /* Simplifies the parsing a bit. */
  JSON._JSON = STRING
  JSON._LEN = LENGTH(STRING)
  IF JSON._LEN = 0 THEN
    RETURN _JSON_SET_ERROR('Nothing to parse.', -10)

  /* Do the parsing. */
  INDX = _JSON_PARSE_ELEMENT(POINTER, 1)

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
  JSON. = ''
  JSON._PTR = 'JSON'
  JSON.TYPE = 'U'
  JSON.VALUE = 'null'
  RETURN 1

/* Return the error text. */
JSON_ERROR_TEXT: PROCEDURE EXPOSE JSON.
  IF JSON._ERROR = '' | JSON._ERROR = 'JSON._ERROR' THEN
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
  RETURN JSON._END

/* JSON Main Interface ========================================= Public = */

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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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
/*  1 if the pointer has been advanced to the next element.               */
/*  If a path is given returns the new path.                              */
/*  0 if the pointer or path are already at the last element.             */
/*  -21 if the current element is not an array or object.                 */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_NEXT: PROCEDURE EXPOSE JSON.
  CALL _JSON_CLEAR_ERROR
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
    /* Return true. */
    RETURN 1
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
  IF JSON._PTR = 'JSON' THEN
    RETURN _JSON_SET_ERROR('JSON_PARENT() Already at the root', -22)
  JSON._PTR = SUBSTR(JSON._PTR, 1, LASTPOS('.', JSON._PTR) - 1)
  RETURN JSON_DEPTH()

/* Pretty Print the JSON. */
/* Turns the JSON into an array. */
/* From there it is up to you to make use of it. */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the type for. Optional.        */
/*  INDENT  - The number of characters to indent each element.            */
/*            Defaults to 1. Optional.                                    */
/* Returns:                                                               */
/*  1 on success. */
/*  -24 if the path is invalid.                                           */
JSON_PRETTY: PROCEDURE EXPOSE JSON.
  CALL _JSON_CLEAR_ERROR
  INDENT = 1
  POINTER = 'JSON'

  IF ARG() > 1 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_STRING')
    IF POINTER <= 0 THEN
      RETURN POINTER
    IF ARG(2) \= '' THEN
      INDENT = ARG(2)
  END
  ELSE IF ARG() > 0 & ARG(1) \= '' THEN
    INDENT = ARG(1)

  /* Clear any previous pretty print data. */
  IF JSON._PP.0 \= '' THEN DO
    DO INDX = 1 TO JSON._PP.0
      INTERPRET 'DROP JSON._PP.' || INDX
    END
  END

  JSON._PP.0 = 0
  RETURN _JSON_PP_ELEMENT(POINTER, 0, INDENT)

/* Move the pointer to the previous element in an array.                  */
/*                                                                        */
/* Returns:                                                               */
/*  1 if the pointer has been advanced to the previous element.           */
/*  0 if the pointer is already at the first element.                     */
/*  -21 if the current element is not an array or object.                 */
/*  -24 if the path is invalid.                                           */
/*  -26 if the member was not found.                                      */
JSON_PREV: PROCEDURE EXPOSE JSON.
  CALL _JSON_CLEAR_ERROR
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
    /* Return true. */
    RETURN 1
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
  CALL _JSON_CLEAR_ERROR
  JSON._PTR = 'JSON'
  RETURN 1

/* Transforms JSON back into a string.                                    */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the type for. Optional.        */
/*                                                                        */
/* Returns:                                                               */
/*  A string representation of the parsed JSON.                           */
/*  Returns '' if there is an error.                                      */
JSON_STRING: PROCEDURE EXPOSE JSON.
  CALL _JSON_CLEAR_ERROR
  POINTER = 'JSON'

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_STRING')
    IF POINTER <= 0 THEN
      RETURN ''
  END

  RETURN _JSON_STRING_ELEMENT(POINTER)

/* Returns the type of the current element or a given path.               */
/*                                                                        */
/* Arguments:                                                             */
/*  POINTER - A path or member name to get the type for. Optional.        */
/*                                                                        */
/* Returns:                                                               */
/*  The element type. See the table Types: above.                         */
/*  Returns '' if there is an error.                                      */
JSON_TYPE: PROCEDURE EXPOSE JSON.
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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

/* JSON Type Checks ============================================ Public = */

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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
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
  CALL _JSON_CLEAR_ERROR
  POINTER = JSON._PTR

  IF ARG() > 0 THEN DO
    POINTER = _JSON_PATH_RESOLVE(ARG(1), 'JSON_IS_NULL')
    IF POINTER <= 0 THEN
      RETURN POINTER
  END

  RETURN VALUE(POINTER || '.TYPE') = 'U'

/* JSON Utilities ============================================== Public = */

/* Escape special characters in a string. */
JSON_ESCAPE: PROCEDURE
  CALL _JSON_CLEAR_ERROR
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

/* Convert a single character type code to a string type name. */
JSON_TYPE_STRING: PROCEDURE
  CALL _JSON_CLEAR_ERROR
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

/* Turn escaped characters in string to normal characters. */
JSON_UNESCAPE: PROCEDURE
  CALL _JSON_CLEAR_ERROR
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

/* URL encode a string. */
JSON_URL_ENCODE: PROCEDURE
  CALL _JSON_CLEAR_ERROR
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR("JSON_URL_ENCODE() requires a string.", -20)
  STR = ARG(1)
  NEW_STR = ''
  SAFE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
  DO INDX = 1 TO LENGTH(STR)
    CHR = SUBSTR(STR, INDX, 1)
    IF POS(CHR, SAFE) > 0 THEN
      NEW_STR = NEW_STR || CHR
    ELSE
      NEW_STR = NEW_STR || '%' || C2X(CHR)
  END
  RETURN NEW_STR

/* JSON Internal Parsing ====================================== Private = */

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

/* JSON Conversion to Text ==================================== Private = */

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

/* JSON Pretty Printing ======================================= Private = */

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

/* JSON Private Utilities ===================================== Private = */

/* Clear the error code and text.                                         */
_JSON_CLEAR_ERROR: PROCEDURE EXPOSE JSON.
  DROP JSON._ERROR
  DROP JSON._ERRORCODE
  RETURN 1

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

/* Bottom of JSON Library. */
