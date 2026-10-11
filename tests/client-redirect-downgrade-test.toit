// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import http.connection show Connection

import .memory-socket

OK ::= "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"

main:
  [false, true].do: | tls-client/bool |
    ["GET", "POST", "JSON", "FORM", "WebSocket"].do: | method/string |
      [301, 302, 303, 307, 308].do: | status/int |
        [false, true].do: | allow/bool |
          [false, true].do: | chain/bool |
            test-redirect method status --tls-client=tls-client --allow=allow --chain=chain
        test-redirect method status --tls-client=tls-client --no-follow
    test-explicit-http --tls-client=tls-client
  test-secure-redirect

redirect status/int location/string -> string:
  return "HTTP/1.1 $status Redirect\r\nLocation: $location\r\nContent-Length: 0\r\n\r\n"

test-redirect method/string status/int
    --tls-client/bool --allow/bool=false --chain/bool=false --follow/bool=true:
  web-socket := method == "WebSocket"
  secure-scheme := web-socket ? "wss" : "https"
  insecure-scheme := web-socket ? "ws" : "http"
  uri := "$secure-scheme://original.example/"
  initial-response := redirect status "$insecure-scheme://other.example/target"
  if chain: initial-response = (redirect 307 "/intermediate") + initial-response
  // Model an established secure connection. The test exercises redirect
  // handling and wire output without certificates or a live TLS server.
  first := MemorySocket [initial-response.to-byte-array]
  second := MemorySocket [OK.to-byte-array]
  network := ScriptedNetwork [second]
  client := tls-client ? (http.Client.tls network) : (http.Client network)
  if allow:
    client.close
    client = tls-client
        ? (http.Client.tls network --allow-insecure-redirects)
        : (http.Client network --allow-insecure-redirects)
  parsed := http.ParsedUri_.parse_ uri
  client.connection_ = Connection first --location=parsed --host=parsed.host-with-port
  try:
    error := catch:
      if web-socket:
        client.web-socket --uri=uri --follow-redirects=follow
      else:
        response := null
        if method == "GET":
          response = client.get --uri=uri --follow-redirects=follow
        else if method == "POST":
          response = client.post "synthetic-secret".to-byte-array --uri=uri --follow-redirects=follow
        else if method == "JSON":
          response = client.post-json {"secret": "synthetic-secret"} --uri=uri --follow-redirects=follow
        else:
          response = client.post-form {"secret": "synthetic-secret"} --uri=uri --follow-redirects=follow
        expect-equals (follow ? 200 : status) response.status-code
    if not follow:
      expect-equals (web-socket ? "WebSocket upgrade failed with $status Redirect" : null) error
    else if not allow:
      expect-equals "INSECURE_REDIRECT" error
    else:
      expect-equals (web-socket ? "WebSocket upgrade failed with 200 OK" : null) error
    expect-equals (follow and allow ? 1 : 0) network.index_
    sent := second.out.buffer.to-string
    if follow and allow:
      redirected-method := (method == "GET" or web-socket or status == 303) ? "GET" : "POST"
      expect (sent.starts-with "$redirected-method /target HTTP/1.1\r\n")
      expect-equals (redirected-method == "POST") (sent.contains "synthetic-secret")
    else:
      expect-equals "" sent
    if chain and follow:
      expect (first.out.buffer.to-string.contains " /intermediate HTTP/1.1\r\n")
  finally:
    client.close

test-explicit-http --tls-client/bool:
  socket := MemorySocket [OK.to-byte-array]
  network := ScriptedNetwork [socket]
  client := tls-client ? (http.Client.tls network) : (http.Client network)
  try:
    response := client.get --uri="http://original.example/"
    expect-equals 200 response.status-code
  finally:
    client.close

test-secure-redirect:
  // A same-origin HTTPS redirect remains allowed with the default policy.
  socket := MemorySocket [((redirect 307 "/next") + OK).to-byte-array]
  client := http.Client (ScriptedNetwork [])
  parsed := http.ParsedUri_.parse_ "https://original.example/"
  client.connection_ = Connection socket --location=parsed --host=parsed.host-with-port
  try:
    response := client.post "synthetic-secret".to-byte-array --uri=parsed.stringify
    expect-equals 200 response.status-code
    expect (socket.out.buffer.to-string.contains "POST /next HTTP/1.1\r\n")
  finally:
    client.close
