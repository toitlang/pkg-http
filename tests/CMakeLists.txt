# Copyright (C) 2022 Toitware ApS.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the tests/TESTS_LICENSE file.

file(GLOB TESTS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "*-test.toit")
file(GLOB HTTPBIN_TESTS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "*-test-httpbin.toit")

set(TOIT_EXEC "toit${CMAKE_EXECUTABLE_SUFFIX}" CACHE FILEPATH "The executable used to run the tests")
set(TEST_TIMEOUT 180 CACHE STRING "The maximal amount of time each test is allowed to run")
set(ENABLE_HTTPBIN_TESTS ON CACHE BOOL "Whether to run tests that depend on httpbin.org docker")
set(USE_HTTPBIN_DOCKER OFF CACHE BOOL "Whether to use the httpbin.org docker container")

if (${ENABLE_HTTPBIN_TESTS})
  if (${USE_HTTPBIN_DOCKER})
    set(HTTPBIN_URL "localhost:8765")
  else()
    set(HTTPBIN_URL "httpbin.org")
  endif()
endif()

add_custom_target(
  "install-pkgs"
  COMMAND "${TOIT_EXEC}" pkg install
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)

include(ProcessorCount)
ProcessorCount(NUM_CPU)

add_custom_target(
  check
  COMMAND "${CMAKE_CTEST_COMMAND}" -j${NUM_CPU} --output-on-failure -C Debug
  USES_TERMINAL
)

set(TEST_PREFIX "")
include(fail.cmake OPTIONAL)

message("Failing tests: ${FAILING_TESTS}")
message("Skipped tests: ${SKIP_TESTS}")

set(BROWSERS "chrome")
if (APPLE)
  # The macOS GitHub runner doesn't come with geckodriver anymore:
  # https://github.com/actions/runner-images/issues/9974
  # Since that browser is already tested on the other platforms, we skip it here.
  list(APPEND BROWSERS "safari")
elseif (WIN32)
  list(APPEND BROWSERS "edge" "firefox")
else()
  list(APPEND BROWSERS "firefox")
endif()

foreach(file ${TESTS})
  set(test_name "/tests/${file}")
  if("${test_name}" IN_LIST SKIP_TESTS)
    continue()
  endif()
  if ("${file}" MATCHES "webdriver-")
    foreach (browser ${BROWSERS})
      set(test_name "/tests/${file}-${browser}")
      add_test(
        NAME "${test_name}"
        COMMAND "${TOIT_EXEC}" run --enable-asserts "${file}" -- "${browser}"
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
      )
      set_tests_properties("${test_name}" PROPERTIES TIMEOUT ${TEST_TIMEOUT})
      set_tests_properties("${test_name}" PROPERTIES RESOURCE_LOCK "webdriver")
    endforeach()
  else()
    add_test(
      NAME "${test_name}"
      COMMAND "${TOIT_EXEC}" run --enable-asserts "${file}"
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
  endif()
  set_tests_properties(${test_name} PROPERTIES TIMEOUT ${TEST_TIMEOUT})
endforeach()

if (${ENABLE_HTTPBIN_TESTS})
  foreach(file ${HTTPBIN_TESTS})
    set(test_name "/tests/${file}")
    if("${test_name}" IN_LIST SKIP_TESTS)
      continue()
    endif()
    add_test(
      NAME "${test_name}"
      COMMAND "${TOIT_EXEC}" run --enable-asserts "${file}" -- "${HTTPBIN_URL}"
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
      )
    set_tests_properties(${test_name} PROPERTIES TIMEOUT ${TEST_TIMEOUT})
  endforeach()
endif()

foreach(test ${FAILING_TESTS})
  if("${test}" IN_LIST SKIP_TESTS)
    continue()
  endif()
  set_tests_properties("${test}" PROPERTIES WILL_FAIL TRUE)
endforeach()
