// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import bytes
import encoding.json
import net
import net.tcp
import reader
import tls

import .connection
import .headers
import .method
import .request
import .response
import .status_codes
import .web_socket

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

URI ::= "httpbin.org"
PATH ::= "/get"

main:
  network := net.open
  client := http.Client network
  response := client.get URI PATH
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

  use_tls_by_default_ ::= false
  certificate_/tls.Certificate? ::= null
  server_name_/string? ::= null
  root_certificates_/List ::= []

  /**
  Constructs a new client instance over the given interface.
  The client will default to a insecure HTTP connection, but this can be
    overridden by a redirect or a URI specifying a secure scheme.
  Therefore it can be meaningful to provide certificate roots despite the
    insecure default.
  If the client is used for secure connections, the $root_certificates must
    contain the root certificate of the server.
  See the `certificate_roots` package for common roots:
    https://pkg.toit.io/package/github.com%2Ftoitware%2Ftoit-cert-roots
  Use `net.open` to obtain an interface.
  */
  constructor .interface_
      --root_certificates/List=[]:
    root_certificates_ = root_certificates

  /**
  Constructs a new client.
  The client will default to a secure HTTPS connection, but this can be
    overridden by a redirect or a URI specifying an insecure scheme.
  The $root_certificates must contain the root certificate of the server.
  See the `certificate_roots` package for common roots:
    https://pkg.toit.io/package/github.com%2Ftoitware%2Ftoit-cert-roots
  A client $certificate can be specified for the rare case where the client
    authenticates itself.
  The $server_name can be specified for verifying the TLS certificate.  This is
    for the rare case where we wish to verify the TLS connections with a
    different server name from the one used to establish the connection.
  */
  constructor.tls .interface_
      --root_certificates/List=[]
      --server_name/string?=null
      --certificate/tls.Certificate?=null:
    use_tls_by_default_ = true
    root_certificates_ = root_certificates
    server_name_ = server_name
    certificate_ = certificate

  /**
  Creates a new request for the given URI, of the form
    "http://www.example.com:1080/path/to/file#fragment" using the given method.

  The $method is usually one of $GET, $POST, $PUT, $DELETE.

  The returned $Request should be sent with $Request.send.

  The connection is automatically closed when the response's body ($Response.body) is
    completely read.
  */
  new_request method/string --uri/string --headers/Headers=Headers -> Request:
    parsed := ParsedUri_.parse uri
    connection := new_connection_ parsed --auto_close
    request := connection.new_request method parsed.path headers
    return request

  /**
  Creates a new request for $host, $port, $path.

  The $method is usually one of $GET, $POST, $PUT, $DELETE.

  The returned $Request should be sent with $Request.send.

  The connection is automatically closed when the response's body ($Response.body) is
    completely read.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the default port is used.
  */
  new_request method/string host/string --port/int?=null path/string --headers/Headers=Headers -> Request:
    parsed := ParsedUri_ host path --port=port --scheme=(use_tls_by_default_ ? "https" : "http")
    connection := new_connection_ parsed --auto_close
    request := connection.new_request method parsed.path headers
    return request

  static starts_with_ignore_case_ str/string needle/string -> bool:
    if str.size < needle.size: return false
    for i := 0; i < needle.size; i++:
      a := str[i]
      b := needle[i]
      if 'a' <= a <= 'z': a -= 'a' - 'A'
      if 'a' <= b <= 'z': b -= 'a' - 'A'
      if a != b: return false
    return true

  /**
  Fetches data from the given URI, of the form
    "http://www.example.com:1080/path/to/file#fragment" using the $GET method.

  The connection is automatically closed when the response is completely read.

  If no port is specified then the default port is used.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  get --uri/string --headers/Headers=Headers --follow_redirects/bool=true -> Response:
    parsed := ParsedUri_.parse uri
    if not parsed.scheme.starts_with "http": throw "INVALID_SCHEME"
    return get_ parsed headers --follow_redirects=follow_redirects

  /**
  Fetches data at $path from the given server ($host, $port) using the $GET method.

  The connection is automatically closed when the response is completely read.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the default port is used.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  get host/string --port/int?=null path/string --headers/Headers=Headers --follow_redirects/bool=true --use_tls/bool=use_tls_by_default_ -> Response:
    if headers.get "Transfer-Encoding": throw "INVALID_ARGUMENT"
    if headers.get "Host": throw "INVALID_ARGUMENT"

    parsed := ParsedUri_ host path --port=port --scheme=(use_tls ? "https" : "http")
    return get_ parsed headers --follow_redirects=follow_redirects

  get_ parsed/ParsedUri_ headers --follow_redirects/bool -> Response:
    MAX_REDIRECTS.repeat:
      connection := new_connection_ parsed --auto_close
      request := connection.new_request GET parsed.path headers
      response := request.send

      if follow_redirects and
          (is_regular_redirect_ response.status_code
            or response.status_code == STATUS_SEE_OTHER):
        connection.close
        parsed = get_location_ response parsed
        continue.repeat
      else:
        return response

    throw "Too many redirects"

  get_location_ response/Response previous/ParsedUri_ -> ParsedUri_:
    location := response.headers.single "Location"
    return ParsedUri_.parse location --previous=previous

  /**
  Makes an HTTP connection, then immediately upgrades to a $WebSocket connection.
  Connects to the given URI, of the form "wss://api.example.com:1080/path/to/end-point".
  After this call, this client can no longer be used for regular HTTP requests.
  */
  web_socket --uri/string --headers=Headers --follow_redirects/bool=true -> WebSocket:
    return web_socket --uri=uri --headers=headers --follow_redirects=follow_redirects: | response |
      if response == null: throw "Too many redirects"
      throw "WebSocket upgrade failed with $response.status_code $response.status_message"

  /**
  Makes an HTTP connection, then immediately upgrades to a $WebSocket connection.
  Connects to the given URI, of the form "wss://api.example.com:1080/path/to/end-point".
  On an error, the block is called with the $Response as its argument.
  In the case that there are too many redirects, the block is called with null
    as its argument.
  After this call, this client can no longer be used for regular HTTP requests.
  */
  web_socket --uri/string --headers=Headers --follow_redirects/bool=true [on_error] -> WebSocket:
    if headers.get "Host": throw "INVALID_ARGUMENT"
    parsed := ParsedUri_.parse uri
    if not parsed.scheme.starts_with "ws": throw "INVALID_SCHEME"
    return web_socket_ parsed --headers=headers --follow_redirects=follow_redirects on_error

  /**
  Makes an HTTP connection, then immediately upgrades to a $WebSocket connection.
  On error, throws an exception.
  After this call, this client can no longer be used for regular HTTP requests.
  */
  web_socket host/string --port/int?=null path/string --headers=Headers --follow_redirects/bool=true -> WebSocket:
    return web_socket host --port=port path --headers=headers --follow_redirects=follow_redirects: | response |
      if response == null: throw "Too many redirects"
      throw "WebSocket upgrade failed with $response.status_code $response.status_message"

  /**
  Makes an HTTP connection, then immediately upgrades to a $WebSocket connection.
  On an error, the block is called with the $Response as its argument.
  In the case that there are too many redirects, the block is called with null
    as its argument.
  After this call, this client can no longer be used for regular HTTP requests.
  */
  web_socket host/string --port/int?=null path/string --headers=Headers --follow_redirects/bool=true --use_tls=use_tls_by_default_ [on_error] -> WebSocket:
    if headers.get "Host": throw "INVALID_ARGUMENT"
    parsed := ParsedUri_ host path --port=port --scheme=(use_tls ? "wss" : "ws")
    return web_socket_ parsed --headers=headers --follow_redirects=follow_redirects on_error

  web_socket_ parsed --headers/Headers --follow_redirects/bool [on_error] -> WebSocket:
    MAX_REDIRECTS.repeat:
      connection := new_connection_ parsed --auto_close=false
      nonce := WebSocket.add_client_upgrade_headers_ headers
      headers.add "Host" connection.host_
      request := connection.new_request GET parsed.path headers
      response := request.send
      if follow_redirects and
          (is_regular_redirect_ response.status_code
            or response.status_code == STATUS_SEE_OTHER):
        connection.close
        parsed = get_location_ response parsed
        continue.repeat
      else:
        WebSocket.check_client_upgrade_response_ response nonce on_error
        return WebSocket connection.socket_

    on_error.call null
    throw "TOO_MANY_REDIRECTS"

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

  Instead of specifying host and path, you can specify a $uri, of the form
    "http://www.example.com:1080/path".

  The connection is automatically closed when the response is completely read.

  A port can be provided in three ways:
  - using the $uri parameter, or
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If no port is specified then the default port is used.

  If $content_type is not null, sends the content type header with that value.
    If the content type is given, then the $headers must not contain any "Content-Type" entry.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).

  # Advanced
  If the data can be generated dynamically, it's more efficient to create a new
    request with $new_request and to set the $Request.body to a reader that produces
    the data only when needed.
  */
  post data/ByteArray -> Response
      --uri/string?=null
      --host/string?=null
      --port/int?=null
      --path/string?=null
      --headers/Headers=Headers
      --content_type/string?=null
      --follow_redirects/bool=true
      --use_tls/bool?=null:

    parsed := parse_ uri host port path use_tls

    return post_ data parsed --headers=headers --content_type=content_type --follow_redirects=follow_redirects

  parse_ uri/string? host/string? port/int? path/string? use_tls/bool? -> ParsedUri_:
    if uri:
      if host or port or path or use_tls: throw "Cannot combine --uri with host, port or path arguments"
      return ParsedUri_.parse uri
    else:
      if not host or not path: throw "Must specify either --uri or --host and --path"
      scheme := (use_tls == null ? use_tls_by_default_ : use_tls)
          ? "https"
          : "http"
      return ParsedUri_ host path --port=port --scheme=scheme

  post_ data/ByteArray parsed/ParsedUri_ -> Response
      --headers/Headers
      --content_type/string?
      --follow_redirects/bool:

    if content_type and headers.get "Content-Type": throw "INVALID_ARGUMENT"
    if headers.get "Transfer-Encoding": throw "INVALID_ARGUMENT"
    if headers.get "Host": throw "INVALID_ARGUMENT"

    if content_type:
      headers = headers.copy
      headers.set "Content-Type" content_type

    MAX_REDIRECTS.repeat:
      connection := new_connection_ parsed --auto_close
      request := connection.new_request POST parsed.path headers
      request.body = bytes.Reader data
      response := request.send

      if follow_redirects and is_regular_redirect_ response.status_code:
        connection.close
        parsed = get_location_ response parsed
        continue.repeat
      else if follow_redirects and response.status_code == STATUS_SEE_OTHER:
        connection.close
        parsed = get_location_ response parsed
        headers = headers.copy
        clear_payload_headers_ headers
        return get_ parsed headers --follow_redirects=true // Switch from POST to GET.
      else:
        return response

    throw "Too many redirects"

  /**
  Posts the $object on $path for the given server ($host, $port) using the $POST method.

  Instead of specifying host and path, you can specify a $uri, of the form
    "http://www.example.com:1080/path".

  Encodes the $object first as JSON.

  Sets the 'Content-type' header to "application/json".

  The connection is automatically closed when the response is completely read.

  A port can be provided in three ways:
  - using the $uri parameter, or
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If no port is specified then the default port is used.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  post_json object/any -> Response
      --uri/string?=null
      --host/string?=null
      --port/int?=null
      --path/string?=null
      --headers/Headers=Headers
      --follow_redirects/bool=true
      --use_tls/bool?=null:
    // TODO(florian): we should create the json dynamically.
    encoded := json.encode object

    parsed := parse_ uri host port path use_tls

    return post_ encoded parsed --headers=headers --content_type="application/json" --follow_redirects=follow_redirects

  /**
  Posts the $map on $path for the given server ($host, $port) using the $POST method.

  Instead of specifying host and path, you can specify a $uri, of the form
    "http://www.example.com:1080/path".

  Encodes the $map using URL encoding, like an HTML form submit button.
    For example: "from=123&to=567".

  The keys of the $map should be strings.

  If the values of the $map are not strings or byte arrays they are converted
    to strings by calling stringify on them.

  Sets the 'Content-type' header to "application/x-www-form-urlencoded".

  The connection is automatically closed when the response is completely read.

  A port can be provided in three ways:
  - using the $uri parameter, or
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If no port is specified then the default port is used.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  post_form map/Map -> Response
      --uri/string?=null
      --host/string?=null
      --port/int?=null
      --path/string?=null
      --headers/Headers=Headers
      --follow_redirects/bool=true
      --use_tls/bool?=null:
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

    parsed := parse_ uri host port path use_tls

    return post_ encoded parsed --headers=headers --content_type="application/x-www-form-urlencoded" --follow_redirects=follow_redirects

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

  new_connection_ parsed/ParsedUri_ --auto_close=false -> Connection:
    socket := interface_.tcp_connect parsed.host parsed.port
    if parsed.use_tls:
      socket = tls.Socket.client socket
        --server_name=server_name_ or parsed.host
        --certificate=certificate_
        --root_certificates=root_certificates_
    return Connection socket --host=parsed.host_with_port --auto_close=auto_close

  /**
  The default port used based on the type of connection.
  Returns 80 for unencrypted and 443 for encrypted connections.

  Users may provide different ports during connection.

  Deprecated.
  */
  default_port -> int:
    return use_tls_by_default_ ? 443 : 80

class ParsedUri_:
  scheme/string
  host/string
  port/int
  path/string
  fragment/string?
  use_tls/bool

  static SCHEMES_ ::= {
      "https": 443,
      "wss": 443,
      "http": 80,
      "ws": 80
  }

  constructor
      --.scheme/string="https"
      host/string
      --port/int?=null
      .path/string
      --.fragment=null
      --parse_port_in_host/bool=true:
    colon := host.index_of ":"
    if parse_port_in_host and colon > 0:
      this.port = int.parse host[colon + 1..]
      if port and port != this.port: throw "Conflicting ports given"
      this.host = host[..colon]
    else:
      this.host = host
      this.port = port ? port : SCHEMES_[scheme]

    use_tls = (SCHEMES_[scheme] == 443)

  stringify -> string: return "$scheme://$host_with_port$path$(fragment ? "#$fragment" : "")"

  constructor.parse url/string --previous/ParsedUri_?=null:
    values := parse_ url
    new_scheme := values[0]
    if previous and (new_scheme.starts_with "ws") != (previous.scheme.starts_with "ws"):
      throw "INVALID_REDIRECT"  // Can't redirect a WebSockets URI to an HTTP URI or vice versa.
    scheme = new_scheme
    host = values[1]
    port = values[2]
    path = values[3]
    fragment = values[4] ? values[4] : (previous ? previous.fragment : null)
    use_tls = (SCHEMES_[new_scheme] == 443)

  /// Returns the hostname, with the port appended if it is non-default.
  host_with_port -> string:
    default_port := SCHEMES_[scheme]
    return default_port == port ? host : "$host:$port"

  static parse_ url/string -> List:
    colon := url.index_of ":/"
    scheme := "https"
    // Recognize a prefix like "https:/"
    if colon > 0:
      up_to_colon := url[..colon]
      if is_alpha_ up_to_colon:
        scheme = up_to_colon.to_ascii_lower
        url = url[colon + 1..]
    if url.contains "/" and not url.starts_with "//": throw "URI_PARSING_ERROR"
    if not SCHEMES_.contains scheme: throw "Unknown scheme: $scheme"
    if url.starts_with "//": url = url[2..]
    host := null
    port := null
    path := ?
    slash := url.index_of "/"
    // Named block.
    get_host_and_port := : | h p |
      host = h
      port = p
    if slash < 0:
      extract_host_with_optional_port_ scheme url get_host_and_port
      path = "/"
    else:
      extract_host_with_optional_port_ scheme url[..slash] get_host_and_port
      path = url[slash..]
    hash := path.index_of "#"
    fragment := null
    if hash > 0:
      fragment = path[hash + 1..]
      path = path[..hash]
    return [scheme, host, port, path, fragment]

  static extract_host_with_optional_port_ scheme/string combined/string [block] -> none:
    colon := combined.index_of ":"
    host := ?
    port := ?
    if colon < 0:
      port = SCHEMES_[scheme]
      host = combined
    else:
      port = int.parse combined[colon + 1..]
      host = combined[..colon]
    if host.size == 0 or host[0] == '.': throw "URI_PARSING_ERROR"
    previous := '.'
    host.do:
      if it == '-':
        if previous == '.': throw "URI_PARSING_ERROR"
      else if it == '.':
        if previous == '-' or previous == '.': throw "URI_PARSING_ERROR"
      else if not '0' <= it <= '9'
          and not 'A' <= it <= 'Z'
          and not 'a' <= it <= 'z'
          and not it == '.':
        throw "ILLEGAL_HOSTNAME"
      previous = it
    if host[host.size - 1] == '-': throw "URI_PARSING_ERROR"
    block.call host port

  // Matches /^[a-zA-Z]+$/.
  static is_alpha_ str/string -> bool:
    str.do: if not 'a' <= it <= 'z' and not 'A' <= it <= 'Z': return false
    return true
