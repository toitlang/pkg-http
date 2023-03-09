# Toit package: http

A HTTP server and client.

This package implements the HTTP/1.1 protocol. It supports 'GET' and 'POST'
requests with convenience methods, and can be used to implement REST servers.

It has support for HTTPS connections. See the 'tls' examples for details.

## Examples

### Get request

```
import http
import net

main:
  network := net.open
  client := http.Client network

  response := client.get "www.example.com" "/"
  data := #[]
  while chunk := response.body.read:
    data += chunk
  print data.to_string

  client.close
```

### JSON Post request

This example encodes the data to the server with JSON and then decodes
the response as JSON as well.
```
import http
import net
import encoding.json

URL ::= "httpbin.org"
PATH ::= "/post"

main:
  network := net.open
  client := http.Client network
  response := client.post_json --host=URL --path=PATH {
    "foo": 42,
    "bar": 499,
  }
  data := json.decode_stream response.body
  client.close
  print data
```
