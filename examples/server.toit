
// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import http
import encoding.json
import net

ITEMS := ["FOO", "BAR", "BAZ"]

main:
  network := net.open
  server := http.Server network
  server.listen 8080:: | request/http.Request writer/http.ResponseWriter |
    ITEMS.do:
      writer.write
        json.encode {
          "item": it,
        }
      writer.write "\n"
