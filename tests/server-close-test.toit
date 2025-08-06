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
  served-ten := monitor.Latch
  closed := monitor.Latch
  task::
    requests := 0
    server.listen tcp-socket:: | request/http.Request writer/http.ResponseWriter |
      requests++
      if requests == 10: served-ten.set true
      sleep --ms=100  // Make it more likely to have parallel requests.
      if request.path == "/":
        writer.headers.set "Content-Type" "text/html"
        writer.out.write "<html><body>hello world</body></html>"
      writer.close

  task::
    client := http.Client network
    // 10 requests should be no problem.
    CLOSE-AFTER-REQUESTS.repeat:
      client.get --uri="http://localhost:$port/"

    if request-more:
      // There might still be some requests that made it through, but
      // now we should soon have issues.
      e := catch:
        with-timeout --ms=1000:
          while true:
            client.get --uri="http://localhost:$port/"
            sleep --ms=10
      expect-not-null e

  served-ten.get
  server.close
  tcp-socket.close
