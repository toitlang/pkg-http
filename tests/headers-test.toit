// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import io

main:
  test-from-map
  test-keys

/**
Converts the given $headers to a string.

The $http.Headers class has a stringify method that does pretty much
  the same, but we don't want to rely on `stringify` since that could change.
*/
stringify headers/http.Headers -> string:
  buffer := io.Buffer
  headers.write-to buffer
  return buffer.bytes.to-string-non-throwing

test-from-map:
  headers := http.Headers.from-map {:}
  expect-equals "" (stringify headers)

  headers = http.Headers.from-map {"foo": "bar"}
  expect-equals "Foo: bar\r\n" (stringify headers)

  headers = http.Headers.from-map {"foo": ["bar", "baz"]}
  expect-equals "Foo: bar\r\nFoo: baz\r\n" (stringify headers)

  headers = http.Headers.from-map {"foo": ["bar", "baz"], "qux": "quux"}
  expect-equals "Foo: bar\r\nFoo: baz\r\nQux: quux\r\n" (stringify headers)

  headers = http.Headers.from-map {"foo": ["bar", "baz"], "Foo": "corge"}
  expect-equals "Foo: bar\r\nFoo: baz\r\nFoo: corge\r\n" (stringify headers)

test-keys:
  headers := http.Headers.from-map {"foo": ["bar", "baz"], "qux": "quux"}
  expect-list-equals ["Foo", "Qux"] headers.keys

  headers = http.Headers
  expect-list-equals [] headers.keys
