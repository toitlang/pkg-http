// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import bytes
import expect show *
import http

main:
  test_from_map
  test_keys

/**
Converts the given $headers to a string.

The $http.Headers class has a stringify method that does pretty much
  the same, but we don't want to rely on `stringify` since that could change.
*/
stringify headers/http.Headers -> string:
  buffer := bytes.Buffer
  headers.write_to buffer
  return buffer.bytes.to_string_non_throwing

test_from_map:
  headers := http.Headers.from_map {:}
  expect_equals "" (stringify headers)

  headers = http.Headers.from_map {"foo": "bar"}
  expect_equals "Foo: bar\r\n" (stringify headers)

  headers = http.Headers.from_map {"foo": ["bar", "baz"]}
  expect_equals "Foo: bar\r\nFoo: baz\r\n" (stringify headers)

  headers = http.Headers.from_map {"foo": ["bar", "baz"], "qux": "quux"}
  expect_equals "Foo: bar\r\nFoo: baz\r\nQux: quux\r\n" (stringify headers)

  headers = http.Headers.from_map {"foo": ["bar", "baz"], "Foo": "corge"}
  expect_equals "Foo: bar\r\nFoo: baz\r\nFoo: corge\r\n" (stringify headers)

test_keys:
  headers := http.Headers.from_map {"foo": ["bar", "baz"], "qux": "quux"}
  expect_list_equals ["Foo", "Qux"] headers.keys

  headers = http.Headers
  expect_list_equals [] headers.keys
