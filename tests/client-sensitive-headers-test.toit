// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http

import .memory-socket

OK ::= "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"

main:
  [false, true].do: | tls-client/bool |
    ["GET", "POST", "WebSocket"].do: | method/string |
      [303, 307].do: | status/int |
        ["/next", "//other.example/next", "//original.example:8080/next"].do: | location/string |
          test-redirect method status location --tls-client=tls-client
      test-return-to-origin method --tls-client=tls-client
  test-scheme-change

new-client network/ScriptedNetwork --tls-client/bool -> http.Client:
  sensitive := ["x-aPi-kEy", "X-Session", "Authorization"]
  client := tls-client
      ? (http.Client.tls network --sensitive-headers=sensitive)
      : (http.Client network --sensitive-headers=sensitive)
  // Mutating the caller's configuration must not remove the protection.
  sensitive.clear
  return client

new-headers -> http.Headers:
  headers := http.Headers.from-map {
    "X-Api-Key": ["synthetic-first", "synthetic-second"],
    "x-session": "synthetic-session",
    "Authorization": "Bearer synthetic-token",
    "Cookie": "synthetic-cookie",
    "Proxy-Authorization": "synthetic-proxy",
    "X-Request": "keep",
  }
  return headers

send client/http.Client method/string headers/http.Headers:
  if method == "WebSocket":
    // A final 200 intentionally stops the handshake after headers are sent.
    expect-throw "WebSocket upgrade failed with 200 OK":
      client.web-socket --uri="ws://original.example/" --headers=headers
  else if method == "GET":
    client.get --uri="http://original.example/" --headers=headers
  else:
    client.post "body".to-byte-array --uri="http://original.example/" --headers=headers

redirect status/int location/string -> string:
  return "HTTP/1.1 $status Redirect\r\nLocation: $location\r\nContent-Length: 0\r\n\r\n"

check-headers sent/string --sensitive/bool:
  expect (sent.contains "X-Request: keep\r\n")
  ["X-Api-Key", "X-Session", "Authorization", "Cookie", "Proxy-Authorization"].do: | name/string |
    expect-equals sensitive (sent.contains "$name: ")
  if sensitive:
    expect (sent.contains "X-Api-Key: synthetic-first\r\n")
    expect (sent.contains "X-Api-Key: synthetic-second\r\n")

test-redirect method/string status/int location/string --tls-client/bool:
  same-origin := location == "/next"
  first := MemorySocket [((redirect status location) + (same-origin ? OK : "")).to-byte-array]
  second := MemorySocket [OK.to-byte-array]
  client := new-client (ScriptedNetwork [first, second]) --tls-client=tls-client
  headers := new-headers
  original := headers.stringify
  try:
    send client method headers
    sent := (same-origin ? first : second).out.buffer.to-string
    start := sent.index-of --last " /next HTTP/1.1"
    expect start >= 0
    check-headers sent[start..] --sensitive=same-origin
    check-headers first.out.buffer.to-string --sensitive
    expect-equals original headers.stringify
  finally:
    client.close

test-return-to-origin method/string --tls-client/bool:
  // Keep credentials on a relative hop, strip them on departure, and never
  // restore them when a later hop returns to the initial origin.
  first := MemorySocket [((redirect 307 "/next") + (redirect 307 "//other.example/away")).to-byte-array]
  second := MemorySocket [(redirect 307 "//original.example/back").to-byte-array]
  third := MemorySocket [OK.to-byte-array]
  client := new-client (ScriptedNetwork [first, second, third]) --tls-client=tls-client
  headers := new-headers
  original := headers.stringify
  try:
    send client method headers
    first-sent := first.out.buffer.to-string
    check-headers first-sent[(first-sent.index-of --last " /next HTTP/1.1")..] --sensitive
    check-headers second.out.buffer.to-string --no-sensitive
    check-headers third.out.buffer.to-string --no-sensitive
    expect-equals original headers.stringify
  finally:
    client.close

test-scheme-change:
  client := new-client (ScriptedNetwork []) --tls-client
  try:
    previous := http.ParsedUri_.parse_ "http://original.example:8080/"
    next := http.ParsedUri_.parse_ "https://original.example:8080/"
    headers := new-headers
    filtered := client.redirect-headers_ headers previous next
    check-headers filtered.stringify --no-sensitive
    check-headers headers.stringify --sensitive
    expect-null (client.redirect-headers_ null previous next)
  finally:
    client.close
