// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import http
import net

main:
  network := net.open
  client := http.Client network

  response := client.get "localhost:8080" "/"
  data := #[]
  while chunk := response.body.read:
    data += chunk
  print data.to_string
