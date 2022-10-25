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
  very easy to use.

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
  connection_/Connection? := null

  /**
  Constructs a new client instance over the given interface.
  The client will default to an insecure HTTP connection, but this can be
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
  Variant of $(new_request method --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "http://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "http" (no "s") will disable TLS even if the Client
    was created as a TLS client.
  */
  new_request method/string -> Request
      --uri/string
      --headers/Headers=Headers:
    parsed := parse_ uri --web_socket=false
    ensure_connection_ parsed
    request := connection_.new_request method parsed.path headers
    return request

  /**
  Creates a new request for $path on the given server ($host, $port) using the given method.

  The $method is usually one of $GET, $POST, $PUT, $DELETE.

  The returned $Request should be sent with $Request.send.
  */
  new_request method/string -> Request
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers=Headers
      --use_tls/bool?=null:
    parsed := parse_ host port path use_tls --web_socket=false
    ensure_connection_ parsed
    request := connection_.new_request method parsed.path headers
    return request

  /**
  Creates a new request for $host, $port, $path.

  This method will not be in the next major version of the library -
    instead use the version with the named host and path arguments.

  The $method is usually one of $GET, $POST, $PUT, $DELETE.

  The returned $Request should be sent with $Request.send.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the default port is used.
  */
  new_request method/string host/string --port/int?=null path/string --headers/Headers=Headers -> Request:
    parsed := ParsedUri_.private_
        --scheme=(use_tls_by_default_ ? "https" : "http")
        --host=host
        --port=port
        --path=path
        --parse_port_in_host=true
    if not parsed.scheme.starts_with "http": throw "INVALID_SCHEME"
    ensure_connection_ parsed
    request := connection_.new_request method parsed.path headers
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
  Variant of $(get --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "http://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "http" (no "s") will disable TLS even if the Client
    was created as a TLS client.
  */
  get -> Response
      --uri/string
      --headers/Headers=Headers
      --follow_redirects/bool=true:
    parsed := parse_ uri --web_socket=false
    return get_ parsed headers --follow_redirects=follow_redirects

  /**
  Fetches data for $path on the given server ($host, $port) with a GET request.

  If no port is specified then the default port is used.  The $host is not
    parsed for a port number (but see $(get --uri)).

  If $follow_redirects is true, follows redirects (when the status code is 3xx).

  The $use_tls argument can be used to override the default TLS usage of the
    client.
  */
  get -> Response
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers=Headers
      --follow_redirects/bool=true
      --use_tls/bool?=null:
    parsed := parse_ host port path use_tls --web_socket=false
    return get_ parsed headers --follow_redirects=follow_redirects

  /**
  Fetches data at $path from the given server ($host, $port) using the $GET method.

  This method will not be in the next major version of the library -
    instead use the version with the named host and path arguments.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the default port is used.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  get host/string --port/int?=null path/string --headers/Headers=Headers --follow_redirects/bool=true --use_tls/bool=use_tls_by_default_ -> Response:
    if headers.get "Transfer-Encoding": throw "INVALID_ARGUMENT"
    if headers.get "Host": throw "INVALID_ARGUMENT"

    parsed := ParsedUri_.private_
        --scheme=(use_tls ? "https" : "http")
        --host=host
        --port=port
        --path=path
        --parse_port_in_host
    return get_ parsed headers --follow_redirects=follow_redirects

  get_ parsed/ParsedUri_ headers --follow_redirects/bool -> Response:
    MAX_REDIRECTS.repeat:
      response/Response? := null
      try_to_reuse_ parsed: | connection |
        request := connection.new_request GET parsed.path headers
        response = request.send

      if follow_redirects and
          (is_regular_redirect_ response.status_code
            or response.status_code == STATUS_SEE_OTHER):
        parsed = get_location_ response parsed
        continue.repeat
      else:
        return response

    throw "Too many redirects"

  get_location_ response/Response previous/ParsedUri_ -> ParsedUri_:
    location := response.headers.single "Location"
    return ParsedUri_.parse_ location --previous=previous

  /**
  Variant of $(web_socket --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "ws://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "ws:" (not "wss:") will disable TLS even if the Client
    was created as a TLS client.
  */
  web_socket -> WebSocket
      --uri/string
      --headers=Headers
      --follow_redirects/bool=true:
    parsed := parse_ uri --web_socket
    return web_socket_ parsed headers follow_redirects

  /**
  Makes an HTTP/HTTPS connection to the given server ($host, $port), then
    immediately upgrades to a $WebSocket connection with the given $path.

  If no port is specified then the default port is used.  The $host is not
    parsed for a port number (but see $(web_socket --uri)).

  The $use_tls argument can be used to override the default TLS usage of the
    client.
  */
  web_socket -> WebSocket
      --host/string
      --port/int?=null
      --path/string="/"
      --headers=Headers
      --follow_redirects/bool=true
      --use_tls/bool?=null:
    parsed := parse_ host port path use_tls --web_socket
    return web_socket_ parsed headers follow_redirects

  web_socket_ parsed/ParsedUri_ headers/Headers follow_redirects/bool -> WebSocket:
    MAX_REDIRECTS.repeat:
      nonce := WebSocket.add_client_upgrade_headers_ headers
      headers.add "Host" parsed.host_with_port
      response/Response? := null
      try_to_reuse_ parsed: | connection |
        request := connection.new_request GET parsed.path headers
        response = request.send
      if follow_redirects and
          (is_regular_redirect_ response.status_code
            or response.status_code == STATUS_SEE_OTHER):
        parsed = get_location_ response parsed
        continue.repeat
      else:
        WebSocket.check_client_upgrade_response_ response nonce
        connection := connection_
        connection_ = null  // Can't reuse it any more.
        return WebSocket connection.detach

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
  Variant of $(post data --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "http://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "http" (no "s") will disable TLS even if the Client
    was created as a TLS client.
  */
  post data/ByteArray -> Response
      --uri/string
      --headers/Headers=Headers
      --content_type/string?=null
      --follow_redirects/bool=true:
    parsed := parse_ uri --web_socket=false
    return post_ data parsed --headers=headers --content_type=content_type --follow_redirects=follow_redirects

  /**
  Posts data on $path for the given server ($host, $port) using the $POST method.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`. (Not recommended)

  If no port is specified then the default port is used.  The $host is
    parsed for a port number, but this feature will not be in the next major
    version of this library.  See $(post data --uri).

  If $content_type is not null, sends the content type header with that value.
    If the content type is given, then the $headers must not contain any "Content-Type" entry.

  If $follow_redirects is true, follows redirects (when the status code is 3xx).

  The $use_tls argument can be used to override the default TLS usage of the
    client.

  # Advanced
  If the data can be generated dynamically, it's more efficient to create a new
    request with $new_request and to set the $Request.body to a reader that produces
    the data only when needed.
  */
  post data/ByteArray -> Response
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers=Headers
      --content_type/string?=null
      --follow_redirects/bool=true
      --use_tls/bool?=null:
    parsed := parse_ host port path use_tls --web_socket=false
    return post_ data parsed --headers=headers --content_type=content_type --follow_redirects=follow_redirects

  parse_ uri/string --web_socket/bool -> ParsedUri_:
    default_scheme := use_tls_by_default_
        ? (web_socket ? "wss" : "https")
        : (web_socket ? "ws" : "http")
    result := ParsedUri_.parse_ uri --default_scheme=default_scheme
    if web_socket == true and result.scheme.starts_with "http": throw "INVALID_SCHEME"
    if web_socket == false and result.scheme.starts_with "ws": throw "INVALID_SCHEME"
    return result

  /// Rather than verbose named args, this private method has the args in the
  /// order in which they appear in a URI.
  parse_ host/string port/int? path/string use_tls/bool? --web_socket/bool -> ParsedUri_:
    default_scheme := (use_tls == null ? use_tls_by_default_ : use_tls)
        ? (web_socket ? "wss" : "https")
        : (web_socket ? "ws" : "http")
    return ParsedUri_.private_
        --scheme=default_scheme
        --host=host
        --port=port
        --path=path
        --parse_port_in_host=false

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
      response := null
      try_to_reuse_ parsed: | connection |
        request := connection.new_request POST parsed.path headers
        request.body = bytes.Reader data
        response = request.send

      if follow_redirects and is_regular_redirect_ response.status_code:
        parsed = get_location_ response parsed
        continue.repeat
      else if follow_redirects and response.status_code == STATUS_SEE_OTHER:
        parsed = get_location_ response parsed
        headers = headers.copy
        clear_payload_headers_ headers
        return get_ parsed headers --follow_redirects=true // Switch from POST to GET.
      else:
        return response

    throw "Too many redirects"

  /**
  Variant of $(post_json object --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "http://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "http" (no "s") will disable TLS even if the Client
    was created as a TLS client.
  */
  post_json object/any -> Response
      --uri/string
      --headers/Headers=Headers
      --follow_redirects/bool=true:
    // TODO(florian): we should create the json dynamically.
    encoded := json.encode object
    parsed := parse_ uri --web_socket=false
    return post_ encoded parsed --headers=headers --content_type="application/json" --follow_redirects=follow_redirects

  /**
  Posts the $object on $path for the given server ($host, $port) using the $POST method.

  Encodes the $object first as JSON.

  Sets the 'Content-type' header to "application/json".

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`. (Not recommended.)

  If no port is specified then the default port is used.  The $host is
    parsed for a port number, but this feature will not be in the next major
    version of this library.  See $(post_json object --uri).

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  post_json object/any -> Response
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers=Headers
      --follow_redirects/bool=true
      --use_tls/bool?=null:
    // TODO(florian): we should create the json dynamically.
    encoded := json.encode object
    parsed := parse_ host port path use_tls --web_socket=false
    return post_ encoded parsed --headers=headers --content_type="application/json" --follow_redirects=follow_redirects

  /**
  Variant of $(post_form map --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "http://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "http" (no "s") will disable TLS even if the Client
    was created as a TLS client.
  */
  post_form map/Map -> Response
      --uri/string
      --headers/Headers=Headers
      --follow_redirects/bool=true:
    parsed := parse_ uri --web_socket=false
    return post_form_ map parsed --headers=headers --follow_redirects=follow_redirects

  /**
  Posts the $map on $path for the given server ($host, $port) using the $POST method.

  Encodes the $map using URL encoding, like an HTML form submit button.
    For example: "from=123&to=567".

  The keys of the $map should be strings.

  If the values of the $map are not strings or byte arrays they are converted
    to strings by calling stringify on them.

  Sets the 'Content-type' header to "application/x-www-form-urlencoded".

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`. (Not recommended.)

  If no port is specified then the default port is used.  The $host is
    parsed for a port number, but this feature will not be in the next major
    version of this library.  See $(post_form map --uri).

  If $follow_redirects is true, follows redirects (when the status code is 3xx).
  */
  post_form map/Map -> Response
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers=Headers
      --follow_redirects/bool=true
      --use_tls/bool?=null:
    parsed := parse_ host port path use_tls --web_socket=false
    return post_form_ map parsed --headers=headers --follow_redirects=follow_redirects


  post_form_ map/Map parsed/ParsedUri_ -> Response
      --headers/Headers=Headers
      --follow_redirects/bool=true:
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

  try_to_reuse_ location/ParsedUri_ [block]:
    // We try to reuse an existing connection to a server, but a web server can
    // lose interest in a long-running connection at any time and close it, so
    // if it fails we need to reconnect.
    reused := ensure_connection_ location
    catch --unwind=(: not reused or it != reader.UNEXPECTED_END_OF_READER_EXCEPTION and it != "Broken pipe"):
      block.call connection_
      return
    // We tried to reuse an already-open connection, but the server closed it.
    connection_.close
    connection_ = null
    // Try a second time with a fresh connection.  Since we just closed it,
    // this will create a new one.
    ensure_connection_ location
    block.call connection_

  /// Returns true if the connection was reused.
  ensure_connection_ location/ParsedUri_ -> bool:
    if connection_:
      if location.can_reuse_connection connection_.location_:
        connection_.drain  // Remove any remnants of previous requests.
        return true
      // Hostname etc. didn't match so we need a new connection.
      connection_.close
      connection_ = null
    socket := interface_.tcp_connect location.host location.port
    if location.use_tls:
      socket = tls.Socket.client socket
        --server_name=server_name_ or location.host
        --certificate=certificate_
        --root_certificates=root_certificates_
    connection_ = Connection socket --location=location --host=location.host_with_port
    return false

  /**
  The default port used based on the type of connection.
  Returns 80 for unencrypted and 443 for encrypted connections.

  Users may provide different ports during connection.

  Deprecated.
  */
  default_port -> int:
    return use_tls_by_default_ ? 443 : 80

  close:
    if connection_:
      connection_.close
      connection_ = null

// TODO: This is just a slower version of string.to_ascii_lower, which is in
// newer SDKs.
to_ascii_lower_ str/string -> string:
  str.do:
    if 'A' <= it <= 'Z':
      byte_array := str.to_byte_array
      byte_array.size.repeat:
        if 'A' <= byte_array[it] <= 'Z':
          byte_array[it] ^= 0x20
      return byte_array.to_string
  return str

class ParsedUri_:
  scheme/string
  host/string
  port/int
  path/string
  fragment/string?

  static SCHEMES_ ::= {
      "https": 443,
      "wss": 443,
      "http": 80,
      "ws": 80
  }

  constructor.private_
      --.scheme/string="https"
      --host/string
      --port/int?=null
      --.path/string
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

  use_tls -> bool:
    return SCHEMES_[scheme] == 443

  stringify -> string: return "$scheme://$host_with_port$path$(fragment ? "#$fragment" : "")"

  // When redirecting we need to take the old URI into account to interpret the new one.
  constructor.parse_ uri/string --previous/ParsedUri_?=null:
    parsed := ParsedUri_.parse_ uri --default_scheme=null
    new_scheme := parsed.scheme
    if previous and (new_scheme.starts_with "ws") != (previous.scheme.starts_with "ws"):
      throw "INVALID_REDIRECT"  // Can't redirect a WebSockets URI to an HTTP URI or vice versa.
    scheme = new_scheme
    host = parsed.host
    port = parsed.port
    path = parsed.path
    fragment = parsed.fragment or (previous ? previous.fragment : null)

  can_reuse_connection previous/ParsedUri_ -> bool:
    // The wording of https://www.rfc-editor.org/rfc/rfc6455#section-4.1 seems
    // to indicate that WebSockets connections should be fresh HTTP
    // connections, not ones that have previously been used for plain HTTP.
    // Therefore we require an exact scheme match here, rather than allowing an
    // upgrade from http to ws or https to wss.  This matches what browsers do.
    scheme_is_compatible := scheme == previous.scheme
    return  host == previous.host
        and port == previous.port
        and scheme_is_compatible

  /// Returns the hostname, with the port appended if it is non-default.
  host_with_port -> string:
    default_port := SCHEMES_[scheme]
    return default_port == port ? host : "$host:$port"

  constructor.parse_ uri/string --default_scheme/string?:
    colon := uri.index_of ":/"
    scheme/string? := default_scheme
    // Recognize a prefix like "https:/"
    if colon > 0:
      up_to_colon := uri[..colon]
      if is_alpha_ up_to_colon:
        scheme = to_ascii_lower_ up_to_colon
        uri = uri[colon + 1..]
    if uri.contains "/" and not uri.starts_with "//": throw "URI_PARSING_ERROR"
    if not scheme or not SCHEMES_.contains scheme: throw "Unknown scheme: $scheme"
    if uri.starts_with "//": uri = uri[2..]
    host := null
    port := null
    path := ?
    slash := uri.index_of "/"
    // Named block.
    get_host_and_port := : | h p |
      host = h
      port = p
    if slash < 0:
      extract_host_with_optional_port_ scheme uri get_host_and_port
      path = "/"
    else:
      extract_host_with_optional_port_ scheme uri[..slash] get_host_and_port
      path = uri[slash..]
    hash := path.index_of "#"
    fragment := null
    if hash > 0:
      fragment = path[hash + 1..]
      path = path[..hash]
    return ParsedUri_.private_
        --scheme=scheme
        --host=host
        --port=port
        --path=path
        --fragment=fragment
        --parse_port_in_host=false

  static extract_host_with_optional_port_ scheme/string host/string [block] -> none:
    // Four cases:
    // 1) host
    // 2) host:port
    port := SCHEMES_[scheme]
    ipv6 := false
    colon := host.index_of --last ":"
    if host.starts_with "[":
      // either [ipv6-address] or [ipv6-address]:port
      // This is a little tricky because the IPv6 address contains colons.
      square_end := host.index_of "]"
      if square_end < 0 or colon > square_end + 1:
        throw "URI_PARSING_ERROR"
      if colon > square_end:
        port = int.parse host[colon + 1..]
        host = host[1..square_end]
      else:
        if square_end != host.size - 1:
          throw "URI_PARSING_ERROR"
        host = host[1..square_end]
      ipv6 = true
    else:
      if colon > 0:
        port = int.parse host[colon + 1..]
        host = host[..colon]
    previous := '.'
    if ipv6:
      host.do:
        if      not '0' <= it <= '9'
            and not 'a' <= it <= 'f'
            and not 'A' <= it <= 'F'
            and not it == ':':
          throw "ILLEGAL_HOSTNAME"
    else:
      if host.size == 0 or host[0] == '.': throw "URI_PARSING_ERROR"
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
