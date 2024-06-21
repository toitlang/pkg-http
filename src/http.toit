// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .client
import .server
import .request
import .response
import .headers
import .method
import .status-codes
import .web-socket

export *

/**
HTTP v1.1 library.

# Common use cases
Fetching the content of a URL with `get` and decoding it with json:

```
import http
import net
import encoding.json

URL ::= "httpbin.org"
PATH ::= "/get"

main:
  network := net.open
  client := http.Client network
  response := client.get URL PATH
  data := json.decode-stream response.body
  client.close
```

For https connection the client needs to install certificate roots:
```
import http
import net
import encoding.json
import certificate-roots  // Package github.com/toitware/toit-cert-roots.

HOST ::= "httpbin.org"
PATH ::= "/get"

main:
  certificate-roots.install-common-trusted-roots
  network := net.open
  client := http.Client.tls network
  response := client.get HOST PATH
  data := json.decode-stream response.body
  print data
  client.close
```

Post a JSON encoded message:

```
import http
import net
import encoding.json

HOST ::= "httpbin.org"
PATH ::= "/post"

main:
  network := net.open
  client := http.Client network
  response := client.post-json --host=HOST --path=PATH {
    "foo": 42,
    "bar": 499,
  }
  data := json.decode-stream response.body
  print data
  client.close
```
*/
