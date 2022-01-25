// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import net
import net.tcp
import reader
import tls

import .request
import .response
import .connection
import .method
import .headers

/**
An HTTP v1.1 client.

This class provides methods to fetch data from HTTP servers.

# Get
Use the $get method to fetch data using a $GET request.

The $get method keeps track of the underlying resources and is thus
  very easy to use. Once the data is fully read it automatically
  closes the connection.

Example that takes the incoming data and reads it as JSON:
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
  data := json.decode_stream response.body
```

For https connection use the $Client.tls constructor with the certificate of
  the server:
```
  client := http.Client.tls network
      --root_certificates=[CERTIFICATE]
```
The certificate is server dependendent, and must be obtained before-hand.
Most commonly one uses a combination of inspecting the certificate in Google Chrome,
  and the package `certificate_roots`:
  https://pkg.toit.io/package/github.com%2Ftoitware%2Ftoit-cert-roots

For example, the `httpbin.org` server uses the `AMAZON_ROOT_CA_1` certificate:
```
import certificate_roots

CERTIFICATE ::= certificate_roots.AMAZON_ROOT_CA_1
```
*/
class Client:
  interface_/tcp.Interface

  use_tls_ ::= false
  certificate_/tls.Certificate? ::= null
  server_name_/string? ::= null
  root_certificates_/List ::= []

  /**
  Constructs a new client instance over the given interface.
  Use `net.open` to obtain an interface.
  */
  constructor .interface_:

  /**
  Constructs a new client on a secure https connection.

  The $root_certificates must contain the root certificate of the server.
  See the `certificate_roots` package for common roots:
    https://pkg.toit.io/package/github.com%2Ftoitware%2Ftoit-cert-roots
  */
  constructor.tls .interface_
      --root_certificates/List=[]
      --server_name/string?=null
      --certificate/tls.Certificate?=null:
    use_tls_ = true
    root_certificates_ = root_certificates
    server_name_ = server_name
    certificate_ = certificate

  /**
  Creates a new request for $host, $port, $path.

  The $method is usually one of $GET, $POST, $PUT, $DELETE.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the $default_port is used.
  */
  new_request method/string host/string --port/int?=null path/string --headers/Headers=Headers -> Request:
    connection := new_connection_ host port
    request := connection.new_request method path headers
    return request

  /**
  Fetches data at $path from the given server ($host, $port) using the $GET method.

  The connection is automatically closed when the response is completely drained.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the $default_port is used.
  */
  get host/string --port/int?=null path/string --headers/Headers=Headers -> Response:
    connection := new_connection_ host port --auto_close
    request := connection.new_request GET path headers
    return request.send

  new_connection_ host/string port/int? --auto_close=false -> Connection:
    index := host.index_of ":"
    if index >= 0:
      given_port := port
      port = int.parse host[index+1..]
      host = host[..index]
      if given_port and port != given_port:
        throw "Conflicting ports given"

    if not port: port = default_port
    socket := interface_.tcp_connect host port
    if use_tls_:
      socket = tls.Socket.client socket
        --server_name=server_name_ or host
        --certificate=certificate_
        --root_certificates=root_certificates_
    return Connection socket --host=host --auto_close=auto_close

  /**
  The default port used based on the type of connection.
  Returns 80 for unencrypted and 443 for encrypted connections.

  Users may provide different ports during connection.
  */
  default_port -> int:
    return use_tls_ ? 443 : 80
