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
      ITEMS.do:
        writer.write
          json.encode {
            "item": it,
          }
        writer.write "\n"
    else if request.path == "/headers":
      writer.headers.set "Http-Test-Header" "going strong"
    else if request.path == "/500":
      writer.write_headers 500
    else if request.path == "/599":
      writer.write_headers 599 --message="Dazed and confused"
