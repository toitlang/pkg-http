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
  tcp-socket := network.tcp-listen 0
  print "Server on http://localhost:$tcp-socket.local-address.port/"
  server := http.Server --max-tasks=5
  server.listen tcp-socket:: | request/http.RequestIncoming writer/http.ResponseWriter |
    resource := request.query.resource
    if resource == "/empty":
    else if resource == "/":
      writer.headers.set "Content-Type" "text/html"
      writer.out.write """
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
    else if resource == "/post-json" and request.method == http.POST:
      decoded := json.decode-stream request.body
      print "Received JSON: $decoded"
    else if resource == "/json":
      writer.headers.set "Content-Type" "application/json"
      writer.out.write
        json.encode ITEMS
    else if resource == "/headers":
      writer.headers.set "Http-Test-Header" "going strong"
      writer.write-headers 200
    else if resource == "/500":
      writer.headers.set "Content-Type" "text/plain"
      writer.write-headers 500
      writer.out.write "Failure\n"
    else if resource == "/599":
      writer.headers.set "Content-Type" "text/plain"
      writer.write-headers 599 --message="Dazed and confused"
    else:
      writer.headers.set "Content-Type" "text/plain"
      writer.write-headers 404
      writer.out.write "Not found\n"
    writer.close
