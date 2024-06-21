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
  network := net.open
  client := http.Client.tls network

  client.root-certificates_.add GTS-ROOT-R1

  response := client.get --host=HOST --path=PATH

  expect-equals CODE response.status-code
