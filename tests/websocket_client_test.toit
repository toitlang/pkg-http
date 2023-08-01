// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import certificate_roots
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
  client := http.Client network --root_certificates=[certificate_roots.ISRG_ROOT_X1]
  web_socket := client.web_socket --uri=URI --headers=(http.Headers.from_map ORIGIN)
  greeting := web_socket.receive
  expect_equals "echo.websocket.events sponsored by Lob.com" greeting
  print greeting
  web_socket.send MSG1
  web_socket.ping "Hello"
  web_socket.ping #[0xff, 0x80, 0x23]
  echo := web_socket.receive
  expect_equals MSG1 echo
  web_socket.send MSG2
  echo_bytes := web_socket.receive
  expect_equals MSG2 echo_bytes
