// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import http
import encoding.json
import net

ITEMS := ["FOO", "BAR", "BAZ"]

main:
  network := net.open
  server := http.Server
  server.listen network 8080:: | request/http.Request writer/http.ResponseWriter |
    if request.path == "/empty":
    else if request.path == "/json":
      writer.headers.set "Content-Type" "application/json"
      writer.write
        json.encode ITEMS
    else if request.path == "/headers":
      writer.headers.set "Http-Test-Header" "going strong"
      writer.headers.set "Content-Type" "text/plain"
      writer.write "Going away\n"
    else if request.path == "/500":
      writer.headers.set "Content-Type" "text/plain"
      writer.write_headers 500
      writer.write "Failure\n"
    else if request.path == "/599":
      writer.headers.set "Content-Type" "text/plain"
      writer.write_headers 599 --message="Dazed and confused"
      writer.write "Failure\n"
    writer.close
