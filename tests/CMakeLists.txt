# Copyright (C) 2022 Toitware ApS.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the tests/TESTS_LICENSE file.

file(GLOB TESTS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "*-test.toit")
file(GLOB HTTPBIN_TESTS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "*-test-httpbin.toit")

set(TOIT_EXEC "toit.run${CMAKE_EXECUTABLE_SUFFIX}" CACHE FILEPATH "The executable used to run the tests")
set(TPKG_EXEC "toit.pkg${CMAKE_EXECUTABLE_SUFFIX}" CACHE FILEPATH "The executable used to install the packages")
set(TEST_TIMEOUT 40 CACHE STRING "The maximal amount of time each test is allowed to run")
set(ENABLE_HTTPBIN_TESTS ON CACHE BOOL "Whether to run tests that depend on httpbin.org docker")
set(USE_HTTPBIN_DOCKER OFF CACHE BOOL "Whether to use the httpbin.org docker container")

if (${ENABLE_HTTPBIN_TESTS})
  if (${USE_HTTPBIN_DOCKER})
    set(HTTPBIN_URL "localhost:8765")
  else()
    set(HTTPBIN_URL "httpbin.org")
  endif()
endif()

message("TPKG: ${TPKG_EXEC}")
add_custom_target(
  "install-pkgs"
  COMMAND "${TPKG_EXEC}" install
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

foreach(file ${TESTS})
  set(test_name "/tests/${file}")
  if("${test_name}" IN_LIST SKIP_TESTS)
    continue()
  endif()
  add_test(
    NAME "${test_name}"
    COMMAND "${TOIT_EXEC}" "-Xenable-asserts" "${file}"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
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
      COMMAND "${TOIT_EXEC}" "-Xenable-asserts" "${file}" "${HTTPBIN_URL}"
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
