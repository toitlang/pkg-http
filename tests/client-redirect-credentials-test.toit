// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http

import .memory-socket

main:
  ["GET", "POST"].do: | method/string |
    [true, false].do: | same-origin/bool |
      [303, 307].do: | status/int |
        test method status --same-origin=same-origin

test method/string status/int --same-origin/bool:
  location := same-origin ? "/next" : "http://other.example/next"
  redirect := "HTTP/1.1 $status Redirect\r\nLocation: $location\r\nContent-Length: 0\r\n\r\n"
  ok := "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
  first := MemorySocket [(redirect + (same-origin ? ok : "")).to-byte-array]
  second := MemorySocket [ok.to-byte-array]
  client := http.Client (ScriptedNetwork [first, second])
  headers := http.Headers.from-map {
    "Authorization": "Bearer synthetic-test-value",
    "Cookie": "session=synthetic-test-value",
    "Proxy-Authorization": "Basic synthetic-test-value",
    "X-Request": "keep",
  }
  try:
    if method == "GET":
      client.get --uri="http://original.example/" --headers=headers
    else:
      client.post #[] --uri="http://original.example/" --headers=headers
    sent := (same-origin ? first : second).out.buffer.to-string
    redirected-method := status == 303 ? "GET" : method
    start := sent.index-of --last "$redirected-method /next HTTP/1.1"
    expect start >= 0
    sent = sent[start..]
    expect (sent.contains "X-Request: keep\r\n")
    ["Authorization", "Cookie", "Proxy-Authorization"].do: | key/string |
      expect-equals same-origin (sent.contains "$key: ")
      expect (headers.contains key)
  finally:
    client.close
