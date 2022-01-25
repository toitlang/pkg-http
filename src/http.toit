// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .client
import .server
import .request
import .response
import .headers
import .method

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
  // The `get` method automatically closes the connection when
  // the response has been fully read.
  response := client.get URL PATH
  data := json.decode_stream response.body
```

For https connection the client needs the certificate of the server:
```
import http
import net
import encoding.json
import certificate_roots  // Package github.com/toitware/toit-cert-roots.

URL ::= "httpbin.org"
PATH ::= "/get"
// This certificate depends on the URL.
CERTIFICATE ::= certificate_roots.AMAZON_ROOT_CA_1

main:
  network := net.open
  client := http.Client.tls network
      --root_certificates=[CERTIFICATE]
  // The `get` method automatically closes the connection when
  // the response has been fully read.
  response := client.get URL PATH
  data := json.decode_stream response.body
```
*/
