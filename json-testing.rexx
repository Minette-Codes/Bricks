/* Top of JSON Testing. */

/* This is only the testing part of the JSON library.                     */
/* This does not include the parsing or permutation code.                 */
/* See the files 'json-library.rexx' 'json-permutation.rexx'.             */
/* To run the tests all three parts of the library are required.          */

/* JSON Testing ================================================ Public = */

/* Runs tests from the file 'json_tests.txt'.                             */
/*                                                                        */
/* Returns:                                                               */
/*  The total number of tests run.                                        */
/*  -90 if the test file could not be read.                               */
/*  -91 if the test variables name or json are missing.                   */
JSON_TESTS: PROCEDURE EXPOSE JSON. JSON_TESTS.
  CALL _JSON_CLEAR_ERROR
  DO TAIL OVER JSON_TESTS
    INTERPRET 'DROP JSON_TESTS.' || TAIL
  END

  JSON_TESTS. = ''
  TEST_FILE = 'json_tests.json'
  RESULT_FILE = 'json_results.json'
  JSON_TESTS.TOTAL = 0
  JSON_TESTS.PASS = 0
  JSON_TESTS.FAIL = 0
  JSON_TESTS.ERROR = ''
  JSON_TESTS.CODE = 0

  EXEC CICS DELETEQ TD QUEUE(RESULT_FILE) END-EXEC

  /* Read in the test JSON. */
  TEST_JSON = ''
  DO FOREVER
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

    TEST_JSON = TEST_JSON REC
  END

  /* Parse the test JSON. */
  RC = JSON_PARSE(TEST_JSON)
  IF RC < 0 THEN
    RETURN _JSON_SET_ERROR('JSON_TESTS() Unable parse the test. Error:' JSON._ERROR 'Test:' REC, -90)

  /* Move to the first test case in the array. */
  RC = JSON_PATH(".1")
  IF RC < 0 THEN
    RETURN RC

  /* Process the test cases. */
  EXEC CICS WRITEQ TD QUEUE(RESULT_FILE) FROM("[") END-EXEC
  DO FOREVER
    /* Strings that start with '#' are added to the results as a section. */
    IF JSON_IS_STRING() & SUBSTR(JSON_VALUE(), 1, 1) = '#' THEN DO
      INDX = JSON_TESTS.TOTAL + 1
      JSON_TESTS.TOTAL = INDX
      JSON_TESTS.INDX.SECTION = JSON_VALUE()
    END

    /* Skip anything that is not an object. */
    IF JSON_IS_OBJECT() THEN DO
      /* Execute the test. */
      JSON_TESTS.TOTAL = JSON_TESTS.TOTAL + 1
      RESULT_JSON = _JSON_TEST_CASE(JSON_STRING(JSON_PATH()))
      IF JSON_TESTS.CODE < 0 THEN
        RETURN _JSON_SET_ERROR(JSON_TESTS.ERROR, JSON_TESTS.CODE)

      /* Write the results. */
      RESULT_JSON = RESULT_JSON || ','
      EXEC CICS WRITEQ TD QUEUE(RESULT_FILE) FROM(RESULT_JSON) END-EXEC
    END

    /* More? */
    IF \JSON_NEXT() THEN
      LEAVE
  END
  EXEC CICS WRITEQ TD QUEUE(RESULT_FILE) FROM("]") END-EXEC

  /* Save and return the totals. */
  RETURN JSON_TESTS.TOTAL

/* Execute a test case. Update JSON_TESTS.                                */
/* Sets TEST_CASE_ERROR and TEST_CASE_RC if there is an error.            */
/*                                                                        */
/* Arguments:                                                             */
/*  TEST_JSON - The test case JSON.                                       */
/*                                                                        */
/* Returns:                                                               */
/*  The test results as a JSON string.                                    */
/*  Returns '' if there is an error.                                      */
_JSON_TEST_CASE: PROCEDURE EXPOSE JSON_TESTS.
  IF ARG() < 1 THEN
    RETURN _JSON_SET_ERROR('FATAL ERROR IN _JSON_PARSE_ELEMENT', -1)

  TEST_JSON = ARG(1)
  TEST_NUMBER = JSON_TESTS.TOTAL

  /* Parse the test. */
  RC = JSON_PARSE(TEST_JSON)
  IF RC < 0 THEN DO
    JSON_TESTS.ERROR = 'JSON_TESTS() Unable parse the test. Error:' JSON._ERROR 'Test:' TEST_JSON
    JSON_TESTS.CODE = -90
    RETURN ''
  END

  /* Get the variables we care about. */
  TEST_NAME       = JSON_VALUE('.name')
  IF JSON_ERROR_CODE() < 0 THEN DO
    JSON_TESTS.ERROR = 'JSON_TESTS() Missing member "name". Test:' TEST_JSON
    JSON_TESTS.CODE = -91
    RETURN ''
  END
  TEST_JSON       = CHANGESTR("'", JSON_VALUE('.json'), '"')
  IF JSON_ERROR_CODE() < 0 THEN DO
    JSON_TESTS.ERROR = 'JSON_TESTS() Missing member "json." Test:' TEST_NAME
    JSON_TESTS.CODE = -91
    RETURN ''
  END
  TEST_RC         = JSON_VALUE('.rc')
  TEST_RC_TYPE    = JSON_TYPE('.rc')
  TEST_ERROR      = JSON_VALUE('.error')
  TEST_ERROR_TYPE = JSON_TYPE('.error')
  TEST_STRING     = CHANGESTR("'", JSON_VALUE('.string'), '"')
  TEST_PATH       = JSON_VALUE('.path')
  TEST_FUNC       = JSON_VALUE('.func')
  TEST_ARG1       = JSON_VALUE('.arg1')
  TEST_ARG1_TYPE  = JSON_TYPE('.arg1')
  TEST_ARG2       = JSON_VALUE('.arg2')
  TEST_ARG2_TYPE  = JSON_TYPE('.arg2')
  TEST_ARG3       = JSON_VALUE('.arg3')
  TEST_ARG3_TYPE  = JSON_TYPE('.arg3')
  TEST_RESULT     = JSON_VALUE('.result')

  /* Parse the test JSON. */
  CALL JSON_PARSE TEST_JSON

  /* Is there a path to move to? */
  IF TEST_PATH \= '' THEN DO
    CALL JSON_PATH TEST_PATH
    IF JSON_ERROR_CODE() \= 0 THEN DO
      JSON_TESTS.ERROR = 'JSON_TESTS() Invalid path:' TEST_NAME
      JSON_TESTS.CODE = -92
      RETURN ''
    END
  END

  /* Is there a function to call? */
  FUNC_RESULT = ''
  IF TEST_FUNC \= '' THEN DO
    TEST_FUNC = 'CALL' TEST_FUNC
    IF TEST_ARG1_TYPE \= '' THEN DO
      TEST_FUNC = TEST_FUNC '"' || JSON_ESCAPE(TEST_ARG1) || '"'
      IF TEST_ARG2_TYPE \= '' THEN DO
        TEST_FUNC = TEST_FUNC || ', "' || JSON_ESCAPE(TEST_ARG2) || '"'
        IF TEST_ARG3_TYPE \= '' THEN
          TEST_FUNC = TEST_FUNC || ', "' || JSON_ESCAPE(TEST_ARG3) || '"'
      END
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
    JSON_TESTS.TEST_NUMBER.STRING = TO_STRING
  END
  ELSE
    JSON_TESTS.TEST_NUMBER.STRING = ''

  IF TEST_RESULT \= '' & TEST_RESULT \= FUNC_RESULT THEN DO
    TEST_STATUS = 'FAIL'
    TEST_MESSAGE = TEST_MESSAGE 'Expected function result: "' || TEST_RESULT || '".'
  END

  /* Save the test results. */
  TEST_MESSAGE = STRIP(TEST_MESSAGE)
  IF TEST_STATUS = 'PASS' THEN
    JSON_TESTS.PASS = JSON_TESTS.PASS + 1
  ELSE
    JSON_TESTS.FAIL = JSON_TESTS.FAIL + 1
  JSON_TESTS.TEST_NUMBER.NAME = TEST_NAME
  JSON_TESTS.TEST_NUMBER.STATUS = TEST_STATUS
  JSON_TESTS.TEST_NUMBER.JSON = TEST_JSON
  JSON_TESTS.TEST_NUMBER.MESSAGE = TEST_MESSAGE
  JSON_TESTS.TEST_NUMBER.ERROR = ERROR_TEXT
  JSON_TESTS.TEST_NUMBER.CODE = ERROR_CODE
  IF TEST_FUNC \= '' THEN DO
    JSON_TESTS.TEST_NUMBER.FUNC = TEST_FUNC
    JSON_TESTS.TEST_NUMBER.FRESULT = FUNC_RESULT
  END

  /* Create JSON with the results for the RESULT_FILE. */
  CALL JSON_CLEAR
  CALL JSON_SET_TYPE 'O'
  CALL JSON_NEW_STRING 'name', TEST_NAME
  CALL JSON_NEW_NUMBER 'number', JSON_TESTS.TOTAL
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
  RETURN JSON_STRING()

/* Bottom of JSON Testing. */
