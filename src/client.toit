// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import encoding.json
import encoding.url
import io
import net
import net.tcp
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

When the client is no longer needed, resources should be freed up with the
  $close method.  This is an API incompatibility with version one of the
  package, which would automatically close the client after one request.
  See the documentation of the constructor for details.

This client has built-in websocket support.  The separate websockets package
  should no longer be used.

The client caches connections to servers, so a second request to the same
  server will use the same socket and may save a lot of CPU time for setting
  up TLS connections.  It also caches session state for TLS connections, so
  subsequent connections to a server will use the session state to speed up
  the TLS handshake from about 1000ms to about 150ms (on ESP32).

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
  client := null
  try:
    client = http.Client network
    response := client.get URI PATH
    data := json.decode_stream response.body
  finally:
    if client: client.close
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
  security_store_/SecurityStore

  /**
  Constructs a new client instance over the given interface.
  The client will default to an insecure HTTP connection, but this can be
    overridden by a redirect or a URI specifying a secure scheme.
  Therefore it can be meaningful to provide certificate roots despite the
    insecure default.
  If the client is used for secure connections, the $root_certificates must
    contain the root certificate of the server.
  A client will try to keep a connection open to the last server it
    contacted, in the hope that the next request will connect to the same
    server.  This can save a lot of CPU time for TLS connections which are
    expensive to set up, but it also reserves a fairly large amount of
    buffer memory for the TLS connection.  Call $close (perhaps in a finally
    clause) to release the connection.
  See the `certificate_roots` package for common roots:
    https://pkg.toit.io/package/github.com%2Ftoitware%2Ftoit-cert-roots
  Use `net.open` to obtain an interface.
  */
  constructor .interface_
      --root_certificates/List=[]
      --security_store/SecurityStore=SecurityStoreInMemory:
    security_store_ = security_store
    root_certificates_ = root_certificates
    add_finalizer this:: this.finalize_

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
      --certificate/tls.Certificate?=null
      --security_store/SecurityStore=SecurityStoreInMemory:
    security_store_ = security_store
    use_tls_by_default_ = true
    root_certificates_ = root_certificates
    server_name_ = server_name
    certificate_ = certificate
    add_finalizer this:: this.finalize_

  /**
  Variant of $(new_request method --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "http://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "http" (no "s") will disable TLS even if the Client
    was created as a TLS client.
  */
  new_request method/string -> RequestOutgoing
      --uri/string
      --headers/Headers?=null:
    parsed := parse_ uri --web_socket=false
    request := null
    try_to_reuse_ parsed: | connection |
      request = connection.new_request method parsed.path headers
    return request

  /**
  Creates a new request for $path on the given server ($host, $port) using the given method.

  The $method is usually one of $GET, $POST, $PUT, $DELETE.

  The returned $RequestOutgoing should be sent with $RequestOutgoing.send.
  */
  new_request method/string -> RequestOutgoing
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers?=null
      --use_tls/bool?=null:
    parsed := parse_ host port path use_tls --web_socket=false
    request := null
    try_to_reuse_ parsed: | connection |
      request = connection.new_request method parsed.path headers
    return request

  /**
  Creates a new request for $host, $port, $path.

  This method will not be in the next major version of the library -
    instead use the version with the named host and path arguments.

  The $method is usually one of $GET, $POST, $PUT, $DELETE.

  The returned $RequestOutgoing should be sent with $RequestOutgoing.send.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the default port is used.

  Deprecated. Use $(new_request method --host) instead.
  */
  new_request method/string host/string --port/int?=null path/string --headers/Headers?=null -> RequestOutgoing:
    parsed := ParsedUri_.private_
        --scheme=(use_tls_by_default_ ? "https" : "http")
        --host=host
        --port=port
        --path=path
        --parse_port_in_host=true
    if not parsed.scheme.starts_with "http": throw "INVALID_SCHEME"
    request := null
    try_to_reuse_ parsed: | connection |
      request = connection.new_request method parsed.path headers
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
      --headers/Headers?=null
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
      --headers/Headers?=null
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
  get host/string --port/int?=null path/string --headers/Headers?=null --follow_redirects/bool=true --use_tls/bool=use_tls_by_default_ -> Response:
    if headers and headers.contains "Transfer-Encoding": throw "INVALID_ARGUMENT"
    if headers and headers.contains "Host": throw "INVALID_ARGUMENT"

    parsed := ParsedUri_.private_
        --scheme=(use_tls ? "https" : "http")
        --host=host
        --port=port
        --path=path
        --parse_port_in_host
    return get_ parsed headers --follow_redirects=follow_redirects

  get_ parsed/ParsedUri_ headers/Headers? --follow_redirects/bool -> Response:
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
      --headers/Headers?=null
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
      --headers/Headers?=null
      --follow_redirects/bool=true
      --use_tls/bool?=null:
    parsed := parse_ host port path use_tls --web_socket
    return web_socket_ parsed headers follow_redirects

  web_socket_ parsed/ParsedUri_ headers/Headers? follow_redirects/bool -> WebSocket:
    headers = headers ? headers.copy : Headers
    MAX_REDIRECTS.repeat:
      nonce := WebSocket.add_client_upgrade_headers_ headers
      response/Response? := null
      try_to_reuse_ parsed: | connection |
        request/RequestOutgoing := connection.new_request GET parsed.path headers
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
        return WebSocket connection.detach --client

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
      --headers/Headers?=null
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
    request with $new_request and to set the $RequestOutgoing.body to a reader
    that produces the data only when needed.
  */
  post data/ByteArray -> Response
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers?=null
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
      --headers/Headers?
      --content_type/string?
      --follow_redirects/bool:

    headers = headers ? headers.copy : Headers

    if headers.single "Transfer-Encoding": throw "INVALID_ARGUMENT"
    if headers.single "Host": throw "INVALID_ARGUMENT"

    if content_type:
      existing_content_type := headers.single "Content-Type"
      if existing_content_type:
        // Keep the existing entry, but check that the content is the same.
        if existing_content_type.to_ascii_lower != content_type.to_ascii_lower:
          throw "INVALID_ARGUMENT"
      else:
        headers.set "Content-Type" content_type

    MAX_REDIRECTS.repeat:
      response := null
      try_to_reuse_ parsed: | connection |
        request := connection.new_request POST parsed.path headers
        request.body = io.Reader data
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
      --headers/Headers?=null
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
      --headers/Headers?=null
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
      --headers/Headers?=null
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
      --headers/Headers?=null
      --follow_redirects/bool=true
      --use_tls/bool?=null:
    parsed := parse_ host port path use_tls --web_socket=false
    return post_form_ map parsed --headers=headers --follow_redirects=follow_redirects


  post_form_ map/Map parsed/ParsedUri_ -> Response
      --headers/Headers?
      --follow_redirects/bool=true:
    buffer := io.Buffer
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
        url.encode key
      buffer.write "="
      buffer.write
        url.encode value
    encoded := buffer.bytes

    return post_ encoded parsed --headers=headers --content_type="application/x-www-form-urlencoded" --follow_redirects=follow_redirects

  try_to_reuse_ location/ParsedUri_ [block]:
    // We try to reuse an existing connection to a server, but a web server can
    // lose interest in a long-running connection at any time and close it, so
    // if it fails we need to reconnect.
    success := false
    try:
      // Three attempts.  One with a reused connection, one with reused session
      // info and then a clean attempt.  The reason is that our TLS
      // implementation cannot currently fall back from an attempt with session
      // info to a from-scratch connection attempt.
      for attempt := 0; attempt < 3; attempt++:
        reused := ensure_connection_ location
        catch --unwind=(: attempt == 2 or ((not reused or not is_close_exception_ it) and it != "RESUME_FAILED")):
          sock := connection_.socket_
          if sock is tls.Socket and not reused:
            tls_socket := sock as tls.Socket
            use_stored_session_state_ tls_socket location
            tls_socket.handshake
            update_stored_session_state_ tls_socket location
          block.call connection_
          success = true
          return
        // We tried to reuse an already-open connection, but the server closed it.
        connection_.close
        connection_ = null
        // Don't try again with session data if the connection attempt failed.
        if not reused: security_store_.delete_session_data location.host location.port
    finally:
      if not success:
        security_store_.delete_session_data location.host location.port
        if connection_:
          connection_.close
          connection_ = null

  use_stored_session_state_ tls_socket/tls.Socket location/ParsedUri_:
    if data := security_store_.retrieve_session_data location.host location.port:
      tls_socket.session_state = data

  update_stored_session_state_ tls_socket/tls.Socket location/ParsedUri_:
    state := tls_socket.session_state
    if state:
      security_store_.store_session_data location.host location.port state
    else:
      security_store_.delete_session_data location.host location.port

  /// Returns true if the connection was reused.
  ensure_connection_ location/ParsedUri_ -> bool:
    if connection_ and connection_.is_open_:
      if location.can_reuse_connection connection_.location_:
        connection_.drain  // Remove any remnants of previous requests.
        return true
      // Hostname etc. didn't match so we need a new connection.
      connection_.close
      connection_ = null
    socket/tcp.Socket := interface_.tcp_connect location.host location.port
    if location.use_tls:
      // Wrap the socket in TLS.
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
      remove_finalizer this

  finalize_:
    // TODO: We should somehow warn people that they forgot to close the
    // client.  It releases the memory earlier than relying on the
    // finalizer, so it can avoid some out-of-memory situations.
    close

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
    parsed := ParsedUri_.parse_ uri --default_scheme=null --previous=previous
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

  constructor.parse_ uri/string --default_scheme/string? --previous/ParsedUri_?=null:
    // We recognize a scheme if it's either one of the four we support or if it's
    // followed by colon-slash.  This lets us recognize localhost:1080.
    colon := uri.index_of ":"
    scheme/string? := null
    // Recognize a prefix like "https:/"
    if 0 < colon < uri.size - 2:
      up_to_colon := uri[..colon]
      if is_alpha_ up_to_colon:
        lower := up_to_colon.to_ascii_lower
        if SCHEMES_.contains lower or uri[colon + 1] == '/':
          scheme = lower
          uri = uri[colon + 1..]

    scheme = scheme or default_scheme or (previous and previous.scheme)
    if not scheme: throw "Missing scheme in '$uri'"
    if not SCHEMES_.contains scheme: throw "Unknown scheme: '$scheme'"
    // If this is a URI supplied by the library user (no previous), we allow
    // plain hostnames with no path, but if there is a previous we require a
    // double slash to indicate a hostname because otherwise it is a relative
    // URI.
    if not previous and uri.contains "/" and not uri.starts_with "//": throw "URI_PARSING_ERROR"
    host := null
    port := null
    path := ?
    // Named block.
    get_host_and_port := : | h p |
      host = h
      port = p
    has_host := not previous  // If there's no previous URI we assume there is a hostname.
    if uri.starts_with "//":
      uri = uri[2..]
      has_host = true
    if has_host:
      slash := uri.index_of "/"
      if slash < 0:
        extract_host_with_optional_port_ scheme uri get_host_and_port
        path = "/"
      else:
        extract_host_with_optional_port_ scheme uri[..slash] get_host_and_port
        path = uri[slash..]
    else:
      host = previous.host
      port = previous.port
      path = uri
    hash := path.index_of "#"
    fragment := null
    if hash > 0:
      fragment = path[hash + 1..]
      path = path[..hash]
    if previous and not path.starts_with "/":
      // Relative path.
      path = merge_paths_ previous.path path
    return ParsedUri_.private_
        --scheme=scheme
        --host=host
        --port=port
        --path=path
        --fragment=fragment
        --parse_port_in_host=false

  static merge_paths_ old_path/string new_path/string -> string:
    assert: old_path.starts_with "/"
    // Conform to note in RFC 3986 section 5.2.4.
    query := old_path.index_of "?"
    if query > 0: old_path = old_path[..query]
    old_parts := old_path.split "/"
    old_parts = old_parts[1..old_parts.size - 1]
    new_parts := new_path.split "/"
    while new_parts.size != 0:
      if new_parts[0] == ".":
        new_parts = new_parts[1..]
      else if new_parts[0] == "..":
        if old_parts.size == 0: throw "ILLEGAL_PATH"
        old_parts = old_parts[..old_parts.size - 1]
        new_parts = new_parts[1..]
      else:
        old_parts += new_parts
        break
    return "/" + (old_parts.join "/")

  static extract_host_with_optional_port_ scheme/string host/string [block] -> none:
    // Two cases:
    // 1) host
    // 2) host:port
    // In either case the host may be an IPv6 address that contains colons.
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

/**
The interface of an object you can provide to the $Client to store and
  retrieve security data.  Currently only supports session data, which is
  data that can be used to speed up reconnections to TLS servers.
*/
abstract class SecurityStore:
  /// Store session data (eg a TLS ticket) for a given host and port.
  abstract store_session_data host/string port/int data/ByteArray -> none
  /// After a failed attempt to use session data we should not try to use it
  /// again.  This method should delete it from the store.
  abstract delete_session_data host/string port/int -> none
  /// If we have session data stored for a given host and port, this method
  /// should return it.
  abstract retrieve_session_data host/string port/int -> ByteArray?

/**
Default implementation of $SecurityStore that stores the data in an in-memory
  hash map. This is not very useful, since data is not persisted over deep
  sleep or between Clients, but it's an example of how to implement the
  interface.
*/
class SecurityStoreInMemory extends SecurityStore:
  session_data_ ::= {:}

  store_session_data host/string port/int data/ByteArray -> none:
    session_data_["$host:$port"] = data

  delete_session_data host/string port/int -> none:
    session_data_.remove "$host:$port"

  retrieve_session_data host/string port/int -> ByteArray?:
    return session_data_.get "$host:$port"
