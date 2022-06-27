// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import net
import net.tcp
import reader
import tls
import bytes
import encoding.json

import .request
import .response
import .connection
import .method
import .headers
import .status_codes

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
  /**
  The maximum number of redirects to follow if 'follow_redirect' is true for $get and $post requests.
  */
  static MAX_REDIRECTS /int ::= 20

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

  The returned $Request should be sent with $Request.send.

  The connection is automatically closed when the response's body ($Response.body) is
    completely read.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the $default_port is used.
  */
  new_request method/string host/string --port/int?=null path/string --headers/Headers=Headers -> Request:
    connection := new_connection_ host port --auto_close
    request := connection.new_request method path headers
    return request

  starts_with_ignore_case_ str/string needle/string -> bool:
    if str.size < needle.size: return false
    for i := 0; i < needle.size; i++:
      a := str[i]
      b := needle[i]
      if 'a' <= a <= 'z': a -= 'a' - 'A'
      if 'a' <= b <= 'z': b -= 'a' - 'A'
      if a != b: return false
    return true

  // Extracts the redirection target: host and path.
  extract_redirect_target_ headers/Headers -> List:
    redirection_target /string := (headers.get "Location")[0]
    if starts_with_ignore_case_ redirection_target "http://":
      redirection_target = redirection_target[7..]
    else if starts_with_ignore_case_ redirection_target "https://":
      redirection_target = redirection_target[8..]
    else:
      throw "Unexpected redirection target: $redirection_target"
    slash_pos := redirection_target.index_of "/"
    if slash_pos < 0: throw "Unexpected url"
    host := redirection_target[0..slash_pos]
    path := redirection_target[slash_pos+1..]
    return [host, path]

  /**
  Fetches data at $path from the given server ($host, $port) using the $GET method.

  The connection is automatically closed when the response is completely read.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the $default_port is used.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  get host/string --port/int?=null path/string --headers/Headers=Headers --follow_redirects/bool=true -> Response:
    MAX_REDIRECTS.repeat:
      connection := new_connection_ host port --auto_close
      request := connection.new_request GET path headers
      response := request.send

      if follow_redirects and
          (response.status_code == STATUS_MOVED_PERMANENTLY
            or response.status_code == STATUS_FOUND
            or response.status_code == STATUS_SEE_OTHER
            or response.status_code == STATUS_TEMPORARY_REDIRECT
            or response.status_code == STATUS_PERMANENT_REDIRECT):
        connection.close
        redirection_target := extract_redirect_target_ response.headers
        host = redirection_target[0]
        path = redirection_target[1]
        port = null
        continue.repeat
      else:
        return response

    throw "Too many redirects"

  /**
  Removes all headers that are only relevant for payloads.

  This includes `Content-Length`, or `Transfer_Encoding`.
  */
  clear_payload_headers_ headers/Headers:
    headers.remove "Content-Length"
    headers.remove "Content-Type"
    headers.remove "Content-Encoding"
    headers.remove "Content-Language"
    headers.remove "Content-Location"
    headers.remove "Transfer-Encoding"


  /**
  Posts data on $path for the given server ($host, $port) using the $POST method.

  The connection is automatically closed when the response is completely read.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the $default_port is used.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).

  # Advanced
  If the data can be generated dynamically, it's more efficient to create a new
    request with $new_request and to set the $Request.body to a reader that produces
    the data only when needed.
  */
  post data/ByteArray --host/string --port/int?=null --path/string --headers/Headers=Headers --follow_redirects/bool=true -> Response:
    MAX_REDIRECTS.repeat:
      connection := new_connection_ host port --auto_close
      request := connection.new_request POST path headers
      request.body = bytes.Reader data
      response := request.send

      if follow_redirects and
          (response.status_code == STATUS_MOVED_PERMANENTLY
            or response.status_code == STATUS_FOUND
            or response.status_code == STATUS_TEMPORARY_REDIRECT
            or response.status_code == STATUS_PERMANENT_REDIRECT):
        connection.close
        redirection_target := extract_redirect_target_ response.headers
        host = redirection_target[0]
        path = redirection_target[1]
        port = null
        continue.repeat
      else if follow_redirects and response.status_code == STATUS_SEE_OTHER:
        connection.close
        redirection_target := extract_redirect_target_ response.headers
        host = redirection_target[0]
        path = redirection_target[1]
        clear_payload_headers_ headers
        return get host path --headers=headers
      else:
        return response

    throw "Too many redirects"

  /**
  Posts the $object on $path for the given server ($host, $port) using the $POST method.

  Encodes the $object first as JSON.

  Sets the 'Content-type' header to "application/json".

  The connection is automatically closed when the response is completely read.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the $default_port is used.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  post_json object/any --host/string --port/int?=null --path/string --headers/Headers=Headers --follow_redirects/bool=true -> Response:
    // TODO(florian): we should create the json dynamically.
    encoded := json.encode object
    headers.add "Content-type" "application/json"
    return post encoded --host=host --port=port --path=path --headers=headers --follow_redirects=follow_redirects

  /**
  Posts the $map on $path for the given server ($host, $port) using the $POST method.

  Encodes the $map using URL encoding, like an HTML form submit button.
    For example: "from=123&to=567".

  The keys of the $map should be strings.

  If the values of the $map are not strings or byte arrays they are converted
    to strings by calling stringify on them.

  Sets the 'Content-type' header to "application/x-www-form-urlencoded".

  The connection is automatically closed when the response is completely read.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the $default_port is used.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  post_form map/Map --host/string --port/int?=null --path/string --headers/Headers=Headers --follow_redirects/bool=true -> Response:
    buffer := bytes.Buffer
    first := true
    map.do: | key value |
      if key is not string: throw "WRONG_OBJECT_TYPE"
      if value is not ByteArray:
        value = value.stringify
        if value is not string: throw "WRONG_OBJECT_TYPE"
      if first:
        first = false
      else:
        buffer.write "&"
      buffer.write
        url_encode_ key
      buffer.write "="
      buffer.write
        url_encode_ value
    encoded := buffer.bytes
    headers.add "Content-type" "application/x-www-form-urlencoded"
    return post encoded --host=host --port=port --path=path --headers=headers --follow_redirects=follow_redirects

  // TODO: This is a copy of the code in the standard lib/encoding/url.toit.
  // Remove when an SDK release has made this available to the HTTP package.

  static NEEDS_ENCODING_ ::= ByteArray '~' - '-' + 1:
    c := it + '-'
    (c == '-' or c == '_' or c == '.' or c == '~' or '0' <= c <= '9' or 'A' <= c <= 'Z' or 'a' <= c <= 'z') ? 0 : 1

  // Takes an ASCII string or a byte array.
  // Counts the number of bytes that need escaping.
  count_escapes_ data -> int:
    count := 0
    table := NEEDS_ENCODING_
    data.do: | c |
      if not '-' <= c <= '~':
        count++
      else if table[c - '-'] == 1:
        count++
    return count

  // Takes an ASCII string or a byte array.
  url_encode_ from -> any:
    if from is string and from.size != (from.size --runes):
      from = from.to_byte_array
    escaped := count_escapes_ from
    if escaped == 0: return from
    result := ByteArray from.size + escaped * 2
    pos := 0
    table := NEEDS_ENCODING_
    from.do: | c |
      if not '-' <= c <= '~' or table[c - '-'] == 1:
        result[pos] = '%'
        result[pos + 1] = "0123456789ABCDEF"[c >> 4]
        result[pos + 2] = "0123456789ABCDEF"[c & 0xf]
        pos += 3
      else:
        result[pos++] = c
    return result

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
