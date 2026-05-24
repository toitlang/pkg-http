// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import monitor
import net

CLOSE-AFTER-REQUESTS ::= 10

main:
  test
  test --request-more

test --request-more/bool=false:
  server := http.Server --max-tasks=4
  network := net.open
  tcp-socket := network.tcp-listen 0
  port := tcp-socket.local-address.port
  in-tenth-handler := monitor.Latch
  ten-done := monitor.Latch
  client-done := monitor.Latch
  task::
    requests := 0
    server.listen tcp-socket:: | request/http.Request writer/http.ResponseWriter |
      requests++
      if requests == CLOSE-AFTER-REQUESTS: in-tenth-handler.set true
      sleep --ms=100  // Stretch the handler so server.close has to wait.
      if request.path == "/":
        writer.headers.set "Content-Type" "text/html"
        writer.out.write "<html><body>hello world</body></html>"
      writer.close

  task::
    client := http.Client network
    // 10 requests should be no problem.
    CLOSE-AFTER-REQUESTS.repeat:
      client.get --uri="http://localhost:$port/"
    ten-done.set true

    if request-more:
      // There might still be some requests that made it through, but
      // now we should soon have issues.
      e := catch:
        with-timeout --ms=2000:
          while true:
            client.get --uri="http://localhost:$port/"
            sleep --ms=10
      expect-not-null e
    client-done.set true

  // Trigger close while the 10th handler is still in flight, so we verify
  // that server.close waits for in-flight handlers to complete.
  in-tenth-handler.get
  server.close
  // server.close has returned, so all handlers are done. But the client
  // may still be reading the last response. Wait for the client to
  // confirm receipt before tearing down the listening socket, otherwise
  // a mid-stream close on Windows can show up as RST and trigger a retry
  // that hits the closed listener with "actively refused".
  ten-done.get
  tcp-socket.close
  client-done.get
