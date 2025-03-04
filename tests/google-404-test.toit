// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import certificate-roots show *
import expect show *
import http
import net

HOST ::= "google.com"
PATH ::= "/nogood"
CODE ::= 404

main:
  install-all-trusted-roots
  network := net.open
  client := http.Client.tls network

  response := client.get --host=HOST --path=PATH

  expect-equals CODE response.status-code
