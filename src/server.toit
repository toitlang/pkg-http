// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import bytes
import io
import log
import monitor
import net
import net.tcp
import tls

import .chunked
import .connection
import .headers
import .request
import .status-codes
import .web-socket

/**
HTTP server.

# Examples
```
import encoding.json
import http
import net

main:
  network := net.open
  // Listen on a free port.
  tcp-socket := network.tcp-listen 0
  print "Server on http://$network.address:$tcp-socket.local-address.port/"
  server := http.Server --max-tasks=5
  server.listen tcp-socket:: | request/http.RequestIncoming writer/http.ResponseWriter |
    resource := request.query.resource
    if resource == "/empty":
    else if resource == "/":
      writer.headers.set "Content-Type" "text/html"
      writer.out.write """
        <html>
          <body>
            <p>Hello world</p>
          </body>
        </html>
        """
    else if resource == "/json" and request.method == http.POST:
      decoded := json.decode-stream request.body
      print "Received JSON: $decoded"
    else:
      // When serving other resources based on the path, have a
      // look at `content-type --path=resource` to get the correct
      // content type.
      // Here we just return a 404.
      writer.headers.set "Content-Type" "text/plain"
      writer.write-headers 404
      writer.out.write "Not found\n"
    writer.close
```
*/

/**
An HTTP server.
*/
class Server:
  static DEFAULT-READ-TIMEOUT/Duration ::= Duration --s=30

  read-timeout/Duration

  logger_/log.Logger
  use-tls_/bool ::= false
  certificate_/tls.Certificate? ::= null
  root-certificates_/List ::= []
  signal_/monitor.Signal ::= monitor.Signal
  max-tasks_/int
  task-count_/int := 0
  handling-count_/int := 0
  is-closed_/bool := false

  // The server socket if it was created by the server and needs
  // be closed when the server is closed.
  server-socket_/tcp.ServerSocket? := null

  // For testing.
  call-in-finalizer_/Lambda? := null

  /**
  Constructs an HTTP server with the given $read-timeout and $max-tasks.

  The $max-tasks argument must be tuned to the expected load. More tasks consume
    more memory, but can handle more requests concurrently. If the value is not
    big enough, then browsers will time out when they try to connect to the server.
  */
  constructor --.read-timeout=DEFAULT-READ-TIMEOUT --max-tasks/int=1 --logger=log.default:
    logger_ = logger
    max-tasks_ = max-tasks

  /**
  Variant of $constructor.

  This variant sets up the server to use TLS with the given $certificate.
  */
  constructor.tls
      --.read-timeout=DEFAULT-READ-TIMEOUT
      --max-tasks/int=1
      --logger=log.default
      --certificate/tls.Certificate
      --root-certificates/List=[]:
    logger_ = logger
    use-tls_ = true
    certificate_ = certificate
    root-certificates_ = root-certificates
    max-tasks_ = max-tasks

  /**
  Closes the server.

  If the server is in the process of handling requests, it will
    finish the requests before returning from this method.
  */
  close -> none:
    if is-closed_: return
    is-closed_ = true
    // Wait until all tasks are done.
    signal_.wait: handling-count_ == 0
    if server-socket_:
      server-socket_.close
      server-socket_ = null

  /** Whether this server has been closed. */
  is-closed -> bool:
    return is-closed_

  /**
  Sets up an HTTP server on the given $network and port.
  Use $(listen server-socket handler) if you want to let the system
    pick a free port.
  The handler is called for each incoming request with two arguments:
    The $Request and a $ResponseWriter.
  */
  listen network/tcp.Interface port/int handler/Lambda -> none:
    server-socket_ = network.tcp-listen port
    listen server-socket_ handler

  /**
  Sets up an HTTP server on the given TCP server socket.
  This variant of server_socket gives you more control over the socket,
    eg. to let the system pick a free port.  See examples/server.toit.
  The handler is called for each incoming request with two arguments:
    The $Request and a $ResponseWriter.

  # Examples
  ```
  import http
  import net
  main:
    network := net.open
    // Listen on a free port.
    tcp_socket := network.tcp_listen 0
    print "Server on http://localhost:$tcp_socket.local_address.port/"
    server := http.Server --max-tasks=5
    server.listen tcp_socket:: | request/http.Request writer/http.ResponseWriter |
      if request.path == "/":
        writer.headers.set "Content-Type" "text/html"
        writer.out.write "<html><body>hello world</body></html>"
      writer.close
  ```
  */
  listen server-socket/tcp.ServerSocket handler/Lambda -> none:
    while not is-closed_:
      // Reserve the task we might start.
      signal_.wait: task-count_ < max-tasks_
      task-count_++
      // Keep track of who needs to release the reserved task.
      need-to-release-reserved-task := true
      try:  // A try to ensure that we release the reserved task if necessary.
        if is-closed_: break
        accepted/tcp.Socket? := null
        catch --unwind=(: not is-closed_):
          accepted = server-socket.accept
        if not accepted: continue

        socket := accepted
        if use-tls_:
          socket = tls.Socket.server socket
            --certificate=certificate_
            --root-certificates=root-certificates_

        connection := Connection --location=null socket
        address := socket.peer-address
        logger := logger_.with-tag "peer" address
        logger.debug "client connected"

        // This code can be run in the current task or in a child task.
        handle-connection-closure := ::
          try:  // A try to ensure the semaphore is upped in the child task.
            detached := false
            e := catch --trace=(: not is-close-exception_ it and it != DEADLINE-EXCEEDED-ERROR):
              detached = run-connection_ connection handler logger
            connection.close-write_
            close-logger := e ? logger.with-tag "reason" e : logger
            if detached:
              close-logger.debug "client socket detached"
            else:
              close-logger.debug "connection ended"
          finally:
            task-count_--
            signal_.raise
        // End of code that can be run in the current task or in a child task.

        if max-tasks_ > 1:
          task --background handle-connection-closure
        else:
          // For the single-task case, just run the connection in the current task.
          handle-connection-closure.call
        // At this point the `handle-connection-closure` function is responsible
        // for releasing the reserved task.
        need-to-release-reserved-task = false
      finally:
        // Release the reserved task if the code threw before we entered
        // the `handle-connection-closure` function.
        if need-to-release-reserved-task:
          task-count_--
          signal_.raise

  web-socket request/RequestIncoming response-writer/ResponseWriter -> WebSocket?:
    nonce := WebSocket.check-server-upgrade-request_ request response-writer
    if nonce == null: return null
    response-writer.write-headers STATUS-SWITCHING-PROTOCOLS
    return WebSocket response-writer.detach --no-client

  // Returns true if the connection was detached, false if it was closed.
  run-connection_ connection/Connection handler/Lambda logger/log.Logger -> bool:
    if call-in-finalizer_: connection.call-in-finalizer_ = call-in-finalizer_
    while not is-closed_:
      request/RequestIncoming? := null
      with-timeout read-timeout:
        request = connection.read-request
      if is-closed_: return false
      if not request: return false  // Client closed connection.
      request-logger := logger
      if request.method != "GET":
        request-logger = request-logger.with-tag "method" request.method
      request-logger = request-logger.with-tag "path" request.path
      request-logger.debug "incoming request"
      writer ::= ResponseWriter connection request request-logger
      unwind-block := : | exception |
        // If there's an error we can either send a 500 error message or close
        // the connection.  This depends on whether we had already sent the
        // headers - can't send a 500 if we already sent a success header.
        closed := writer.close-on-exception_ "Internal Server error - $exception"
        closed   // Unwind if the connection is dead.
      if request.method == "HEAD":
        writer.write-headers STATUS-METHOD-NOT-ALLOWED --message="HEAD not implemented"
      else:
        catch --trace --unwind=unwind-block:
          handling-count_++
          try:
            handler.call request writer  // Calls the block passed to listen.
          finally:
            handling-count_--
            signal_.raise
      if writer.detached_: return true
      if request.body.read:
        // The request (eg. a POST request) was not fully read - should have
        // been closed and return null from read.
        closed := writer.close-on-exception_ "Internal Server error - request not fully read"
        assert: closed
        throw "request not fully read: $request.path"
      writer.close
    return false

class ResponseWriter extends Object with io.OutMixin:
  static VERSION ::= "HTTP/1.1"

  connection_/Connection? := null
  request_/RequestIncoming
  logger_/log.Logger
  headers_/Headers
  body-writer_/io.CloseableWriter? := null
  content-length_/int? := null
  detached_/bool := false

  constructor .connection_ .request_ .logger_:
    headers_ = Headers

  headers -> Headers:
    if body-writer_: throw "headers already written"
    return headers_

  write-headers status-code/int --message/string?=null:
    if body-writer_: throw "headers already written"
    has-body := status-code != STATUS-NO-CONTENT
    write-headers_
        status-code
        --message=message
        --content-length=null
        --has-body=has-body

  /**
  Deprecated. Use $(out).write instead.
  */
  write data/io.Data:
    out.write data

  try-write_ data/io.Data from/int to/int -> int:
    write-headers_ STATUS-OK --message=null --content-length=null --has-body=true
    return body-writer_.try-write data from to

  write-headers_ status-code/int --message/string? --content-length/int? --has-body/bool:
    if body-writer_: return
    // Keep track of the content length, so we can report an error if not enough
    // data is written.
    if content-length:
      content-length_ = content-length
    else if headers.contains "Content-Length":
      content-length_ = int.parse (headers.single "Content-Length")
    body-writer_ = connection_.send-headers
        "$VERSION $status-code $(message or (status-message status-code))\r\n"
        headers
        --is-client-request=false
        --content-length=content-length
        --has-body=has-body

  /**
  Redirects the request to the given $location.

  Neither $write-headers_ nor any write to $out must have happened.
  */
  redirect status-code/int location/string --message/string?=null --body/string?=null -> none:
    headers.set "Location" location
    if body and body.size > 0:
      write-headers_ status-code --message=message --content-length=body.size --has-body=true
      body-writer_.write body
    else:
      write-headers_ status-code --message=message --content-length=null --has-body=false

  // Returns true if the connection was closed due to an error.
  close-on-exception_ message/string -> bool:
    logger_.info message
    if body-writer_:
      // We already sent a good response code, but then something went
      // wrong.  Hard close (RST) the connection to signal to the other end
      // that we failed.
      connection_.close
      connection_ = null
      return true
    else:
      // We don't have a body writer, so perhaps we didn't send a response
      // yet.  Send a 500 to indicate an internal server error.
      write-headers_ STATUS-INTERNAL-SERVER-ERROR
          --message=message
          --content-length=null
          --has-body=false
      return false

  /**
  Closes the response.

  This method is automatically called after the block if the
    user's router did not call it.
  */
  close -> none:
    mark-writer-closed_
    if body-writer_:
      too-little := content-length_ ? (body-writer_.processed < content-length_) : false
      body-writer_.close
      if too-little:
        // This is typically the case if the user's code set a Content-Length
        // header, but then didn't write enough data.
        // Will hard close the connection.
        close-on-exception_ "Not enough data produced by server"
        return
    else:
      // Nothing was written, yet we are already closing.  This indicates
      // We return a 500 error code and log the issue.  We don't need to close
      // the connection.
      write-headers_ STATUS-INTERNAL-SERVER-ERROR
          --message=null
          --content-length=null
          --has-body=false
      logger_.info "Returned from router without any data for the client"

  detach -> tcp.Socket:
    detached_ = true
    connection := connection_
    connection_ = null
    return connection.detach
