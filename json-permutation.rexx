/* Top of JSON Permutation. */

/* This is the permutation part of the JSON library for modifying JSON.   */
/* This does not include the parsing or testing code.                     */
/* See the files 'json-library.rexx' and 'json-testing.rexx'.             */

/* JSON Permutation Interface ================================== Public = */

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

/* JSON Permutation Shortcuts ================================== Public = */

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
/*  VALUE   - The string value for the new element.                       */
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
/*  VALUE   - The number value for the new element.                       */
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

/* JSON Permutation Utilities ================================= Private = */

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

/* Bottom of JSON Permutation. */
