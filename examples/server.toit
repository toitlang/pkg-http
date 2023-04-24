// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import http
import encoding.json
import net

ITEMS := ["FOO", "BAR", "BAZ"]

main:
  network := net.open
  // Listen on a free port.
  tcp_socket := network.tcp_listen 0
  print "Server on http://localhost:$tcp_socket.local_address.port/"
  server := http.Server
  server.listen tcp_socket:: | request/http.Request writer/http.ResponseWriter |
    if request.path == "/empty":
    else if request.path == "/":
      writer.headers.set "Content-Type" "text/html"
      writer.write """
        <html>
          <head>
            <title>Test</title>
          </head>
          <body>
            <h1>Test</h1>
            <p>Test</p>
          </body>
        </html>
        """
    else if request.path == "/json":
      writer.headers.set "Content-Type" "application/json"
      writer.write
        json.encode ITEMS
    else if request.path == "/headers":
      writer.headers.set "Http-Test-Header" "going strong"
      writer.write_headers 200
    else if request.path == "/500":
      writer.headers.set "Content-Type" "text/plain"
      writer.write_headers 500
      writer.write "Failure\n"
    else if request.path == "/599":
      writer.headers.set "Content-Type" "text/plain"
      writer.write_headers 599 --message="Dazed and confused"
    else:
      writer.headers.set "Content-Type" "text/plain"
      writer.write_headers 404
      writer.write "Not found\n"
    writer.close
