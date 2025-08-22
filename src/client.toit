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
import .status-codes
import .web-socket

/**
HTTP Client.

# Get
Use the $Client.get method to fetch data using a $GET request.

The $Client.get method keeps track of the underlying resources and is thus
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
  client/http.Client := null
  try:
    client = http.Client network
    response := client.get URI PATH
    data := json.decode_stream response.body
  finally:
    if client: client.close
```

For https connections either use the $Client.tls constructor or provide
  a uri with the https scheme. You need to make sure that the server's
  root certificate is installed or provided in the root-certificates list.
  For public root certificates see the `certificate_roots` package.

On embedded devices we recommend to provide a $SecurityStore if the server
  supports TLS resume. See the tls-resume.toit example.

```
import certificate-roots
import http
import net

URI ::= "https://www.example.com"

main:
  certificate-roots.install-common-trusted-roots
  network := net.open
  // On embedded devices consider providing a SecurityStore to speed up
  // subsequent connections to the same server.
  client := http.Client network
  response := client.get --uri=URI
  while data := response.body.read:
    print data.to-string
  client.close
```
*/

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
*/
class Client:
  /**
  The maximum number of redirects to follow if 'follow_redirect' is true for $get and $post requests.
  */
  static MAX-REDIRECTS /int ::= 20

  interface_/tcp.Interface

  use-tls-by-default_ ::= false
  certificate_/tls.Certificate? ::= null
  server-name_/string? ::= null
  root-certificates_/List ::= []
  connection_/Connection? := null
  security-store_/SecurityStore

  /**
  Constructs a new client instance over the given $network.

  Use `net.open` to obtain an $network.

  Clients that connect to secure servers may provide a $security-store.  This
    is used to store session state for TLS connections, which can speed up
    the TLS handshake from about 1000ms to about 150ms (on ESP32). The
    handshake then also uses less memory.

  The $root-certificates parameter is nowadays mostly unused, as the
    recommended way to provide root certificates is to `install` them
    instead.

  The client will default to an insecure HTTP connection, but this can be
    overridden by a redirect or a URI specifying a secure scheme. Therefore
    it can be meaningful to provide certificate roots despite the
    insecure default.

  If the client is used for secure connections, its root certificate must
    be installed or provided in the $root-certificates list.

  A client will try to keep a connection open to the last server it
    contacted, in the hope that the next request will connect to the same
    server.  This can save a lot of CPU time for TLS connections which are
    expensive to set up, but it also reserves a fairly large amount of
    buffer memory for the TLS connection.  Call $close (perhaps in a finally
    clause) to release the connection.

  See the `certificate_roots` package for common roots:
    https://pkg.toit.io/package/github.com%2Ftoitware%2Ftoit-cert-roots
  */
  constructor network/tcp.Interface
      --root-certificates/List=[]
      --security-store/SecurityStore=SecurityStoreInMemory:
    interface_ = network
    security-store_ = security-store
    root-certificates_ = root-certificates
    add-finalizer this:: this.finalize_

  /**
  Variant of $constructor.

  Constructs a client that defaults to a secure HTTPS connection.

  A client $certificate can be specified for the rare case where the client
    authenticates itself.

  The $server-name can be specified for verifying the TLS certificate.  This is
    for the rare case where we wish to verify the TLS connections with a
    different server name from the one used to establish the connection.
  */
  constructor.tls .interface_
      --root-certificates/List=[]
      --server-name/string?=null
      --certificate/tls.Certificate?=null
      --security-store/SecurityStore=SecurityStoreInMemory:
    security-store_ = security-store
    use-tls-by-default_ = true
    root-certificates_ = root-certificates
    server-name_ = server-name
    certificate_ = certificate
    add-finalizer this:: this.finalize_

  /**
  Variant of $(new-request method --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "http://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "http" (no "s") will disable TLS even if the Client
    was created as a TLS client.
  */
  new-request method/string -> RequestOutgoing
      --uri/string
      --headers/Headers?=null:
    parsed := parse_ uri --web-socket=false
    request := null
    try-to-reuse_ parsed: | connection |
      request = connection.new-request method parsed.path headers
    return request

  /**
  Creates a new request for $path on the given server ($host, $port) using the given method.

  The $method is usually one of $GET, $POST, $PUT, $DELETE.

  The returned $RequestOutgoing should be sent with $RequestOutgoing.send.

  The $query-parameters argument is used to encode key-value parameters in the
    request path using the ?key=value&key2=value2&... format.

  Do not use $query-parameters for a $POST request.  See instead $post-form,
    which encodes the key-value pairs in the body as expected for a POST
    request.
  */
  new-request method/string -> RequestOutgoing
      --host/string
      --port/int?=null
      --path/string="/"
      --query-parameters/Map?=null
      --headers/Headers?=null
      --use-tls/bool?=null:
    if method == POST and query-parameters: throw "INVALID_ARGUMENT"
    parsed := parse_ host port path query-parameters use-tls --web-socket=false
    request := null
    try-to-reuse_ parsed: | connection |
      request = connection.new-request method parsed.path headers
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

  Deprecated. Use $(new-request method --host) instead.
  */
  new-request method/string host/string --port/int?=null path/string --headers/Headers?=null -> RequestOutgoing:
    parsed := ParsedUri_.private_
        --scheme=(use-tls-by-default_ ? "https" : "http")
        --host=host
        --port=port
        --path=path
        --parse-port-in-host=true
    if not parsed.scheme.starts-with "http": throw "INVALID_SCHEME"
    request := null
    try-to-reuse_ parsed: | connection |
      request = connection.new-request method parsed.path headers
    return request

  static starts-with-ignore-case_ str/string needle/string -> bool:
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
      --follow-redirects/bool=true:
    parsed := parse_ uri --web-socket=false
    return get_ parsed headers --follow-redirects=follow-redirects

  /**
  Fetches data for $path on the given server ($host, $port) with a GET request.

  If no port is specified then the default port is used.  The $host is not
    parsed for a port number (but see $(get --uri)).

  If $follow-redirects is true, follows redirects (when the status code is 3xx).

  The $use-tls argument can be used to override the default TLS usage of the
    client.

  The $query-parameters argument is used to encode key-value parameters in the
    request path using the ?key=value&key2=value2&... format.
  */
  get -> Response
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers?=null
      --query-parameters/Map?=null
      --follow-redirects/bool=true
      --use-tls/bool?=null:
    parsed := parse_ host port path query-parameters use-tls --web-socket=false
    return get_ parsed headers --follow-redirects=follow-redirects

  /**
  Fetches data at $path from the given server ($host, $port) using the $GET method.

  This method will not be in the next major version of the library -
    instead use the version with the named host and path arguments.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`.

  If neither is specified then the default port is used.

  If $follow-redirects is true, follows redirects (when the status code is 3xx).
  */
  get host/string --port/int?=null path/string --headers/Headers?=null --follow-redirects/bool=true --use-tls/bool=use-tls-by-default_ -> Response:
    if headers and headers.contains "Transfer-Encoding": throw "INVALID_ARGUMENT"
    if headers and headers.contains "Host": throw "INVALID_ARGUMENT"

    parsed := ParsedUri_.private_
        --scheme=(use-tls ? "https" : "http")
        --host=host
        --port=port
        --path=path
        --parse-port-in-host
    return get_ parsed headers --follow-redirects=follow-redirects

  get_ parsed/ParsedUri_ headers/Headers? --follow-redirects/bool -> Response:
    MAX-REDIRECTS.repeat:
      response/Response? := null
      try-to-reuse_ parsed: | connection |
        request := connection.new-request GET parsed.path headers
        response = request.send

      if follow-redirects and
          (is-regular-redirect_ response.status-code
            or response.status-code == STATUS-SEE-OTHER):
        parsed = get-location_ response parsed
        continue.repeat
      else:
        return response

    throw "Too many redirects"

  get-location_ response/Response previous/ParsedUri_ -> ParsedUri_:
    location := response.headers.single "Location"
    return ParsedUri_.parse_ location --previous=previous

  /**
  Variant of $(web-socket --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "ws://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "ws:" (not "wss:") will disable TLS even if the Client
    was created as a TLS client.
  */
  web-socket -> WebSocket
      --uri/string
      --headers/Headers?=null
      --follow-redirects/bool=true:
    parsed := parse_ uri --web-socket
    return web-socket_ parsed headers follow-redirects

  /**
  Makes an HTTP/HTTPS connection to the given server ($host, $port), then
    immediately upgrades to a $WebSocket connection with the given $path.

  If no port is specified then the default port is used.  The $host is not
    parsed for a port number (but see $(web-socket --uri)).

  The $use-tls argument can be used to override the default TLS usage of the
    client.

  The $query-parameters argument is used to encode key-value parameters in the
    request path using the ?key=value&key2=value2&... format.
  */
  web-socket -> WebSocket
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers?=null
      --query-parameters/Map?=null
      --follow-redirects/bool=true
      --use-tls/bool?=null:
    parsed := parse_ host port path query-parameters use-tls --web-socket
    return web-socket_ parsed headers follow-redirects

  web-socket_ parsed/ParsedUri_ headers/Headers? follow-redirects/bool -> WebSocket:
    headers = headers ? headers.copy : Headers
    MAX-REDIRECTS.repeat:
      nonce := WebSocket.add-client-upgrade-headers_ headers
      response/Response? := null
      try-to-reuse_ parsed: | connection |
        request/RequestOutgoing := connection.new-request GET parsed.path headers
        response = request.send
      if follow-redirects and
          (is-regular-redirect_ response.status-code
            or response.status-code == STATUS-SEE-OTHER):
        parsed = get-location_ response parsed
        continue.repeat
      else:
        WebSocket.check-client-upgrade-response_ response nonce
        connection := connection_
        connection_ = null  // Can't reuse it any more.
        return WebSocket connection.detach --client

    throw "TOO_MANY_REDIRECTS"

  /**
  Removes all headers that are only relevant for payloads.

  This includes `Content-Length`, or `Transfer_Encoding`.
  */
  clear-payload-headers_ headers/Headers:
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
      --content-type/string?=null
      --follow-redirects/bool=true:
    parsed := parse_ uri --web-socket=false
    return post_ data parsed --headers=headers --content-type=content-type --follow-redirects=follow-redirects

  /**
  Posts data on $path for the given server ($host, $port) using the $POST method.

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`. (Not recommended)

  If no port is specified then the default port is used.  The $host is
    parsed for a port number, but this feature will not be in the next major
    version of this library.  See $(post data --uri).

  If $content-type is not null, sends the content type header with that value.
    If the content type is given, then the $headers must not contain any "Content-Type" entry.

  If $follow-redirects is true, follows redirects (when the status code is 3xx).

  The $use-tls argument can be used to override the default TLS usage of the
    client.

  # Advanced
  If the data can be generated dynamically, it's more efficient to create a new
    request with $new-request and to set the $RequestOutgoing.body to a reader
    that produces the data only when needed.
  */
  post data/ByteArray -> Response
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers?=null
      --content-type/string?=null
      --follow-redirects/bool=true
      --use-tls/bool?=null:
    parsed := parse_ host port path null use-tls --web-socket=false
    return post_ data parsed --headers=headers --content-type=content-type --follow-redirects=follow-redirects

  parse_ uri/string --web-socket/bool -> ParsedUri_:
    default-scheme := use-tls-by-default_
        ? (web-socket ? "wss" : "https")
        : (web-socket ? "ws" : "http")
    result := ParsedUri_.parse_ uri --default-scheme=default-scheme
    if web-socket == true and result.scheme.starts-with "http": throw "INVALID_SCHEME"
    if web-socket == false and result.scheme.starts-with "ws": throw "INVALID_SCHEME"
    return result

  /// Rather than verbose named args, this private method has the args in the
  /// order in which they appear in a URI.
  parse_ host/string port/int? path/string query-parameters/Map? use-tls/bool? --web-socket/bool -> ParsedUri_:
    default-scheme := (use-tls == null ? use-tls-by-default_ : use-tls)
        ? (web-socket ? "wss" : "https")
        : (web-socket ? "ws" : "http")
    if query-parameters and not query-parameters.is-empty:
      path += "?"
      path += (url-encode_ query-parameters).to-string
    return ParsedUri_.private_
        --scheme=default-scheme
        --host=host
        --port=port
        --path=path
        --parse-port-in-host=false

  post_ data/ByteArray parsed/ParsedUri_ -> Response
      --headers/Headers?
      --content-type/string?
      --follow-redirects/bool:

    headers = headers ? headers.copy : Headers

    if headers.single "Transfer-Encoding": throw "INVALID_ARGUMENT"
    if headers.single "Host": throw "INVALID_ARGUMENT"

    if content-type:
      existing-content-type := headers.single "Content-Type"
      if existing-content-type:
        // Keep the existing entry, but check that the content is the same.
        if existing-content-type.to-ascii-lower != content-type.to-ascii-lower:
          throw "INVALID_ARGUMENT"
      else:
        headers.set "Content-Type" content-type

    MAX-REDIRECTS.repeat:
      response := null
      try-to-reuse_ parsed: | connection |
        request := connection.new-request POST parsed.path headers
        request.body = io.Reader data
        response = request.send

      if follow-redirects and is-regular-redirect_ response.status-code:
        parsed = get-location_ response parsed
        continue.repeat
      else if follow-redirects and response.status-code == STATUS-SEE-OTHER:
        parsed = get-location_ response parsed
        headers = headers.copy
        clear-payload-headers_ headers
        return get_ parsed headers --follow-redirects=true // Switch from POST to GET.
      else:
        return response

    throw "Too many redirects"

  /**
  Variant of $(post-json object --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "http://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "http" (no "s") will disable TLS even if the Client
    was created as a TLS client.
  */
  post-json object/any -> Response
      --uri/string
      --headers/Headers?=null
      --follow-redirects/bool=true:
    // TODO(florian): we should create the json dynamically.
    encoded := json.encode object
    parsed := parse_ uri --web-socket=false
    return post_ encoded parsed --headers=headers --content-type="application/json" --follow-redirects=follow-redirects

  /**
  Posts the $object on $path for the given server ($host, $port) using the $POST method.

  Encodes the $object first as JSON.

  Sets the 'Content-type' header to "application/json".

  A port can be provided in two ways:
  - using the $port parameter, or
  - suffixing the $host parameter with ":port", for example `localhost:8080`. (Not recommended.)

  If no port is specified then the default port is used.  The $host is
    parsed for a port number, but this feature will not be in the next major
    version of this library.  See $(post-json object --uri).

  If $follow-redirects is true, follows redirects (when the status code is 3xx).
  */
  post-json object/any -> Response
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers?=null
      --follow-redirects/bool=true
      --use-tls/bool?=null:
    // TODO(florian): we should create the json dynamically.
    encoded := json.encode object
    parsed := parse_ host port path null use-tls --web-socket=false
    return post_ encoded parsed --headers=headers --content-type="application/json" --follow-redirects=follow-redirects

  /**
  Variant of $(post-form map --host).

  Instead of specifying host and path, this variant lets you specify a $uri, of
    the form "http://www.example.com:1080/path/to/file#fragment".

  A URI that starts with "http" (no "s") will disable TLS even if the Client
    was created as a TLS client.
  */
  post-form map/Map -> Response
      --uri/string
      --headers/Headers?=null
      --follow-redirects/bool=true:
    parsed := parse_ uri --web-socket=false
    return post-form_ map parsed --headers=headers --follow-redirects=follow-redirects

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
    version of this library.  See $(post-form map --uri).

  If $follow-redirects is true, follows redirects (when the status code is 3xx).
  */
  post-form map/Map -> Response
      --host/string
      --port/int?=null
      --path/string="/"
      --headers/Headers?=null
      --follow-redirects/bool=true
      --use-tls/bool?=null:
    parsed := parse_ host port path null use-tls --web-socket=false
    return post-form_ map parsed --headers=headers --follow-redirects=follow-redirects

  url-encode_ map/Map -> ByteArray:
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
    return buffer.bytes

  post-form_ map/Map parsed/ParsedUri_ -> Response
      --headers/Headers?
      --follow-redirects/bool=true:
    encoded := url-encode_ map

    return post_ encoded parsed --headers=headers --content-type="application/x-www-form-urlencoded" --follow-redirects=follow-redirects

  try-to-reuse_ location/ParsedUri_ [block]:
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
        reused := ensure-connection_ location
        catch --unwind=(: attempt == 2 or ((not reused or not is-close-exception_ it) and it != "RESUME_FAILED")):
          sock := connection_.socket_
          if sock is tls.Socket and not reused:
            tls-socket := sock as tls.Socket
            use-stored-session-state_ tls-socket location
            tls-socket.handshake
            update-stored-session-state_ tls-socket location
          block.call connection_
          success = true
          return
        // We tried to reuse an already-open connection, but the server closed it.
        connection_.close
        connection_ = null
        // Don't try again with session data if the connection attempt failed.
        if not reused: security-store_.delete-session-data location.host location.port
    finally:
      if not success:
        security-store_.delete-session-data location.host location.port
        if connection_:
          connection_.close
          connection_ = null

  use-stored-session-state_ tls-socket/tls.Socket location/ParsedUri_:
    if data := security-store_.retrieve-session-data location.host location.port:
      tls-socket.session-state = data

  update-stored-session-state_ tls-socket/tls.Socket location/ParsedUri_:
    state := tls-socket.session-state
    if state:
      security-store_.store-session-data location.host location.port state
    else:
      security-store_.delete-session-data location.host location.port

  /// Returns true if the connection was reused.
  ensure-connection_ location/ParsedUri_ -> bool:
    if connection_ and connection_.is-open_:
      if location.can-reuse-connection connection_.location_:
        connection_.drain_  // Remove any remnants of previous requests.
        // The 'drain' may have closed the connection. Check again.
        if connection_ and connection_.is-open_: return true
      else:
        // Hostname etc. didn't match so we need a new connection.
        connection_.close
    connection_ = null
    socket/tcp.Socket := interface_.tcp-connect location.host location.port
    if location.use-tls:
      // Wrap the socket in TLS.
      socket = tls.Socket.client socket
        --server-name=server-name_ or location.host
        --certificate=certificate_
        --root-certificates=root-certificates_
    connection_ = Connection socket --location=location --host=location.host-with-port
    return false

  /**
  The default port used based on the type of connection.
  Returns 80 for unencrypted and 443 for encrypted connections.

  Users may provide different ports during connection.

  Deprecated.
  */
  default-port -> int:
    return use-tls-by-default_ ? 443 : 80

  close:
    if connection_:
      connection_.close
      connection_ = null
      remove-finalizer this

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
      --parse-port-in-host/bool=true:
    colon := host.index-of ":"
    if parse-port-in-host and colon > 0:
      this.port = int.parse host[colon + 1..]
      if port and port != this.port: throw "Conflicting ports given"
      this.host = host[..colon]
    else:
      this.host = host
      this.port = port ? port : SCHEMES_[scheme]

  use-tls -> bool:
    return SCHEMES_[scheme] == 443

  stringify -> string: return "$scheme://$host-with-port$path$(fragment ? "#$fragment" : "")"

  // When redirecting we need to take the old URI into account to interpret the new one.
  constructor.parse_ uri/string --previous/ParsedUri_?=null:
    parsed := ParsedUri_.parse_ uri --default-scheme=null --previous=previous
    new-scheme := parsed.scheme
    if previous and (new-scheme.starts-with "ws") != (previous.scheme.starts-with "ws"):
      throw "INVALID_REDIRECT"  // Can't redirect a WebSockets URI to an HTTP URI or vice versa.
    scheme = new-scheme
    host = parsed.host
    port = parsed.port
    path = parsed.path
    fragment = parsed.fragment or (previous ? previous.fragment : null)

  can-reuse-connection previous/ParsedUri_ -> bool:
    // The wording of https://www.rfc-editor.org/rfc/rfc6455#section-4.1 seems
    // to indicate that WebSockets connections should be fresh HTTP
    // connections, not ones that have previously been used for plain HTTP.
    // Therefore we require an exact scheme match here, rather than allowing an
    // upgrade from http to ws or https to wss.  This matches what browsers do.
    scheme-is-compatible := scheme == previous.scheme
    return  host == previous.host
        and port == previous.port
        and scheme-is-compatible

  /// Returns the hostname, with the port appended if it is non-default.
  host-with-port -> string:
    default-port := SCHEMES_[scheme]
    return default-port == port ? host : "$host:$port"

  constructor.parse_ uri/string --default-scheme/string? --previous/ParsedUri_?=null:
    // We recognize a scheme if it's either one of the four we support or if it's
    // followed by colon-slash.  This lets us recognize localhost:1080.
    colon := uri.index-of ":"
    scheme/string? := null
    // Recognize a prefix like "https:/"
    if 0 < colon < uri.size - 2:
      up-to-colon := uri[..colon]
      if is-alpha_ up-to-colon:
        lower := up-to-colon.to-ascii-lower
        if SCHEMES_.contains lower or uri[colon + 1] == '/':
          scheme = lower
          uri = uri[colon + 1..]

    scheme = scheme or default-scheme or (previous and previous.scheme)
    if not scheme: throw "Missing scheme in '$uri'"
    if not SCHEMES_.contains scheme: throw "Unknown scheme: '$scheme'"
    // If this is a URI supplied by the library user (no previous), we allow
    // plain hostnames with no path, but if there is a previous we require a
    // double slash to indicate a hostname because otherwise it is a relative
    // URI.
    if not previous and uri.contains "/" and not uri.starts-with "//": throw "URI_PARSING_ERROR"
    host := null
    port := null
    path := ?
    // Named block.
    get-host-and-port := : | h p |
      host = h
      port = p
    has-host := not previous  // If there's no previous URI we assume there is a hostname.
    if uri.starts-with "//":
      uri = uri[2..]
      has-host = true
    if has-host:
      slash := uri.index-of "/"
      if slash < 0:
        extract-host-with-optional-port_ scheme uri get-host-and-port
        path = "/"
      else:
        extract-host-with-optional-port_ scheme uri[..slash] get-host-and-port
        path = uri[slash..]
    else:
      host = previous.host
      port = previous.port
      path = uri
    hash := path.index-of "#"
    fragment := null
    if hash > 0:
      fragment = path[hash + 1..]
      path = path[..hash]
    if previous and not path.starts-with "/":
      // Relative path.
      path = merge-paths_ previous.path path
    return ParsedUri_.private_
        --scheme=scheme
        --host=host
        --port=port
        --path=path
        --fragment=fragment
        --parse-port-in-host=false

  static merge-paths_ old-path/string new-path/string -> string:
    assert: old-path.starts-with "/"
    // Conform to note in RFC 3986 section 5.2.4.
    query := old-path.index-of "?"
    if query > 0: old-path = old-path[..query]
    old-parts := old-path.split "/"
    old-parts = old-parts[1..old-parts.size - 1]
    new-parts := new-path.split "/"
    while new-parts.size != 0:
      if new-parts[0] == ".":
        new-parts = new-parts[1..]
      else if new-parts[0] == "..":
        if old-parts.size == 0: throw "ILLEGAL_PATH"
        old-parts = old-parts[..old-parts.size - 1]
        new-parts = new-parts[1..]
      else:
        old-parts += new-parts
        break
    return "/" + (old-parts.join "/")

  static extract-host-with-optional-port_ scheme/string host/string [block] -> none:
    // Two cases:
    // 1) host
    // 2) host:port
    // In either case the host may be an IPv6 address that contains colons.
    port := SCHEMES_[scheme]
    ipv6 := false
    colon := host.index-of --last ":"
    if host.starts-with "[":
      // either [ipv6-address] or [ipv6-address]:port
      // This is a little tricky because the IPv6 address contains colons.
      square-end := host.index-of "]"
      if square-end < 0 or colon > square-end + 1:
        throw "URI_PARSING_ERROR"
      if colon > square-end:
        port = int.parse host[colon + 1..]
        host = host[1..square-end]
      else:
        if square-end != host.size - 1:
          throw "URI_PARSING_ERROR"
        host = host[1..square-end]
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
  static is-alpha_ str/string -> bool:
    str.do: if not 'a' <= it <= 'z' and not 'A' <= it <= 'Z': return false
    return true

/**
The interface of an object you can provide to the $Client to store and
  retrieve security data.  Currently only supports session data, which is
  data that can be used to speed up reconnections to TLS servers.
*/
abstract class SecurityStore:
  /// Store session data (eg a TLS ticket) for a given host and port.
  abstract store-session-data host/string port/int data/ByteArray -> none
  /// After a failed attempt to use session data we should not try to use it
  /// again.  This method should delete it from the store.
  abstract delete-session-data host/string port/int -> none
  /// If we have session data stored for a given host and port, this method
  /// should return it.
  abstract retrieve-session-data host/string port/int -> ByteArray?

/**
Default implementation of $SecurityStore that stores the data in an in-memory
  hash map. This is not very useful, since data is not persisted over deep
  sleep or between Clients, but it's an example of how to implement the
  interface.
*/
class SecurityStoreInMemory extends SecurityStore:
  session-data_ ::= {:}

  store-session-data host/string port/int data/ByteArray -> none:
    session-data_["$host:$port"] = data

  delete-session-data host/string port/int -> none:
    session-data_.remove "$host:$port"

  retrieve-session-data host/string port/int -> ByteArray?:
    return session-data_.get "$host:$port"
