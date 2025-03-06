// Copyright (C) 2025 Toit contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http

main:
  expect-equals "text/html" (http.content-type --path="/index.html")
  expect-equals "text/plain" (http.content-type --path="/hello.txt")
  expect-equals "application/json" (http.content-type --path="/data.json")
  expect-equals "application/octet-stream" (http.content-type --path="/data.bin")
  expect-equals "application/octet-stream" (http.content-type --path="/data.unknown")
  expect-equals "application/msword" (http.content-type --path="/data.doc")
  expect-equals "image/jpeg" (http.content-type --path="/data.jpg")
  expect-equals "image/png" (http.content-type --path="/data.png")
  expect-equals "image/gif" (http.content-type --path="/data.gif")
  expect-equals "image/svg+xml" (http.content-type --path="/data.svg")
  expect-equals "application/pdf" (http.content-type --path="/data.pdf")
