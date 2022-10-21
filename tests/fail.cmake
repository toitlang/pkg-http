# Copyright (C) 2022 Toitware ApS.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the tests/LICENSE file.

set(FAILING_TESTS
)

if ("${CMAKE_SYSTEM_NAME}" STREQUAL "Windows" OR "${CMAKE_SYSTEM_NAME}" STREQUAL "MSYS")
  list(APPEND FAILING_TESTS
    ${TEST_PREFIX}/tests/redirect_test.toit
    ${TEST_PREFIX}/tests/websocket_standalone_test.toit
    ${TEST_PREFIX}/tests/http_standalone_test.toit
  )
endif()
