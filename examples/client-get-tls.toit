// Copyright (C) 2025 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import certificate-roots
import http
import net

main:
  certificate-roots.install-all-trusted-roots

  network := net.open
  client := http.Client network
  response := client.get --uri="https://www.example.com"
  while data := response.body.read:
    print data.to-string

  client.close
