// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import certificate_roots show *
import expect show *
import http
import net

HOST ::= "google.com"
PATH ::= "/nogood"
CODE ::= 404

main:
  network := net.open
  client := http.Client.tls network

  client.root_certificates_.add GTS_ROOT_R1

  response := client.get --host=HOST --path=PATH

  expect_equals CODE response.status_code
