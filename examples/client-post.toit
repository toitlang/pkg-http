// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import certificate-roots
import encoding.json
import http
import net

HOST ::= "httpbin.org"
PATH ::= "/post"

main:
  certificate-roots.install-common-trusted-roots
  network := net.open
  client := http.Client.tls network
  response := client.post-json --host=HOST --path=PATH {
    "foo": 42,
    "bar": 499,
  }
  data := json.decode_stream response.body
  client.close
  print data
