// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

// The server's task counter must return to its idle value after
// connections are done.

import expect show *
import http
import net

main:
  network := net.open
  listen-socket := network.tcp-listen 0
  port := listen-socket.local-address.port
  server := http.Server --max-tasks=4
  task::
    server.listen listen-socket:: | request/http.Request writer/http.ResponseWriter |
      writer.out.write "ok"
      writer.close

  5.repeat:
    client := http.Client network
    response := client.get --uri="http://localhost:$port/"
    expect-equals 200 response.status-code
    response.body.read-all
    client.close  // Fresh connection every time.
    expect server.task-count_ >= 0

  // Wait for the connection tasks to finish. The listen loop always holds
  // one reservation for the connection it is about to accept.
  with-timeout --ms=2000:
    server.signal_.wait: server.task-count_ == 1

  server.close
  listen-socket.close
  network.close
