// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import certificate-roots
import http
import net

main:
  certificate-roots.install-common-trusted-roots
  network := net.open
  client := http.Client network

  response := client.get --uri="https://toitlang.org"
  data := response.body.read-all
  print "$data.size bytes"

  client.close
