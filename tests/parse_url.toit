// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import http
import expect show *

main:
  parts := http.ParsedUri_.parse "https://www.youtube.com/watch?v=2HJxya0CWco#t=0m6s"
  expect_equals "https"                parts.scheme
  expect_equals "www.youtube.com"      parts.host
  expect_equals 443                    parts.port
  expect_equals "/watch?v=2HJxya0CWco" parts.path
  expect_equals "t=0m6s"               parts.fragment

  http.ParsedUri_.parse                                   "https://www.youtube.com/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://www.youtube.com-/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://www.youtube.-com/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://www.youtube-.com/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://www.-youtube.com/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://www-.youtube.com/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://-www.youtube.com/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://.www.youtube.com/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://www..youtube.com/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://www..y'utube.com/watch?v=2HJxya0CWco"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "https://www..yøutube.com/watch?v=2HJxya0CWco"

  expect_throw "Unknown scheme: fisk": http.ParsedUri_.parse "fisk://fishing.net/"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "/a/relative/url"
  expect_throw "URI_PARSING_ERROR": http.ParsedUri_.parse "http:/127.0.0.1/path"

  parts = http.ParsedUri_.parse "wss://api.example.com./end-point"
  expect_equals "wss"               parts.scheme
  expect_equals "api.example.com."  parts.host
  expect_equals 443                 parts.port
  expect_equals "/end-point"        parts.path
  expect_equals null                parts.fragment
  expect                            parts.use_tls

  parts = http.ParsedUri_.parse "WSS://api.example.com./end-point"
  expect_equals "wss"               parts.scheme
  parts = http.ParsedUri_.parse "htTPs://api.example.com./end-point"
  expect_equals "https"               parts.scheme

  parts = http.ParsedUri_.parse "www.yahoo.com"
  expect_equals "https"         parts.scheme
  expect_equals "www.yahoo.com" parts.host
  expect_equals 443             parts.port
  expect_equals "/"             parts.path
  expect_equals null            parts.fragment
  expect                        parts.use_tls

  parts = http.ParsedUri_.parse "localhost:1080"
  expect_equals "https"     parts.scheme
  expect_equals "localhost" parts.host
  expect_equals 1080        parts.port
  expect_equals "/"         parts.path
  expect_equals null        parts.fragment
  expect                    parts.use_tls

  parts = http.ParsedUri_.parse "127.0.0.1:1080"
  expect_equals "https"     parts.scheme
  expect_equals "127.0.0.1" parts.host
  expect_equals 1080        parts.port
  expect_equals "/"         parts.path
  expect_equals null        parts.fragment
  expect                    parts.use_tls

  parts = http.ParsedUri_.parse "http://localhost:1080/"
  expect_equals "http"      parts.scheme
  expect_equals "localhost" parts.host
  expect_equals 1080        parts.port
  expect_equals "/"         parts.path
  expect_equals null        parts.fragment
  expect_not                parts.use_tls

  parts = http.ParsedUri_.parse "http://localhost:1080/#"
  expect_equals "http"      parts.scheme
  expect_equals "localhost" parts.host
  expect_equals 1080        parts.port
  expect_equals "/"         parts.path
  expect_equals ""          parts.fragment
  expect_not                parts.use_tls

  parts = http.ParsedUri_.parse "http://localhost:1080/#x"
  expect_equals "http"      parts.scheme
  expect_equals "localhost" parts.host
  expect_equals 1080        parts.port
  expect_equals "/"         parts.path
  expect_equals "x"         parts.fragment
  expect_not                parts.use_tls

  parts = http.ParsedUri_.parse "ws://xn--us--um5a.com/schneemann"
  expect_equals "ws"               parts.scheme
  expect_equals "xn--us--um5a.com" parts.host
  expect_equals 80                 parts.port
  expect_equals "/schneemann"      parts.path
  expect_equals null               parts.fragment
  expect_not                       parts.use_tls

  parts = http.ParsedUri_.parse "//127.0.0.1/path"
  expect_equals "https"            parts.scheme
  expect_equals "127.0.0.1"        parts.host
  expect_equals 443                parts.port
  expect_equals "/path"            parts.path
  expect_equals null               parts.fragment
  expect                           parts.use_tls

  parts = http.ParsedUri_.parse "http://127.0.0.1/path"
  expect_equals "http"             parts.scheme
  expect_equals "127.0.0.1"        parts.host
  expect_equals 80                 parts.port
  expect_equals "/path"            parts.path
  expect_equals null               parts.fragment
  expect_not                       parts.use_tls

  parts = http.ParsedUri_.parse "https://original.com/foo#fraggy"
  expect_equals "https"            parts.scheme
  expect_equals "original.com"     parts.host
  expect_equals 443                parts.port
  expect_equals "/foo"             parts.path
  expect_equals "fraggy"           parts.fragment
  expect                           parts.use_tls

  parts = http.ParsedUri_.parse --previous=parts "http://redirect.com/bar"
  expect_equals "http"             parts.scheme  // Changed in accordance with redirect.
  expect_equals "redirect.com"     parts.host
  expect_equals 80                 parts.port
  expect_equals "/bar"             parts.path
  expect_equals "fraggy"           parts.fragment  // Kept from original non-redirected URI.
  expect_not                       parts.use_tls

  // Can't redirect an HTTP connection to a WebSockets connection.
  expect_throw "INVALID_REDIRECT": parts = http.ParsedUri_.parse --previous=parts "wss://socket.redirect.com/api"
