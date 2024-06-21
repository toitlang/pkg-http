// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import certificate-roots
import expect show *
import http
import net

URI ::= "wss://echo.websocket.events/"
// This header is required by the WebSocket endpoint.
ORIGIN ::= { "Origin": "http://echo.websocket.events" }
MSG1 ::= "Hello, from Toit!"
MSG2 ::= #[0xff, 0x00, 103]

main:
  network := net.open
  client := http.Client network --root-certificates=[certificate-roots.ISRG-ROOT-X1]
  web-socket := client.web-socket --uri=URI --headers=(http.Headers.from-map ORIGIN)
  greeting := web-socket.receive
  expect-equals "echo.websocket.events sponsored by Lob.com" greeting
  print greeting
  web-socket.send MSG1
  web-socket.ping "Hello"
  web-socket.ping #[0xff, 0x80, 0x23]
  echo := web-socket.receive
  expect-equals MSG1 echo
  web-socket.send MSG2
  echo-bytes := web-socket.receive
  expect-equals MSG2 echo-bytes
