// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import bytes
import log
import monitor
import net
import net.tcp
import tls
import writer

import .chunked
import .connection
import .headers
import .request
import .status_codes
import .web_socket

class Server:
  static DEFAULT_READ_TIMEOUT/Duration ::= Duration --s=30

  read_timeout/Duration

  logger_/log.Logger
  use_tls_/bool ::= false
  certificate_/tls.Certificate? ::= null
  root_certificates_/List ::= []
  semaphore_/monitor.Semaphore? ::= null

  // For testing.
  call_in_finalizer_/Lambda? := null

  constructor --.read_timeout=DEFAULT_READ_TIMEOUT --max_tasks/int=1 --logger=log.default:
    logger_ = logger
    if max_tasks > 1: semaphore_ = monitor.Semaphore --count=max_tasks

  constructor.tls
      --.read_timeout=DEFAULT_READ_TIMEOUT
      --max_tasks/int=1
      --logger=log.default
      --certificate/tls.Certificate
      --root_certificates/List=[]:
    logger_ = logger
    use_tls_ = true
    certificate_ = certificate
    root_certificates_ = root_certificates
    if max_tasks > 1: semaphore_ = monitor.Semaphore --count=max_tasks

  listen interface/tcp.Interface port/int handler/Lambda -> none:
    server_socket := interface.tcp_listen port
    listen server_socket handler

  listen server_socket/tcp.ServerSocket handler/Lambda -> none:
    while true:
      parent_task_semaphore := null
      if semaphore_:
        parent_task_semaphore = semaphore_
        // Down the semaphore before the accept, so we just don't accept
        // connections if we are at the limit.
        semaphore_.down
      try:  // A try to ensure the semaphore is upped.
        accepted := server_socket.accept
        if not accepted: continue

        socket := accepted
        if use_tls_:
          socket = tls.Socket.server socket
            --certificate=certificate_
            --root_certificates=root_certificates_

        connection := Connection --location=null socket
        address := socket.peer_address
        logger := logger_.with_tag "peer" address
        logger.debug "client connected"

        // This code can be run in the current task or in a child task.
        handle_connection_closure := ::
          try:  // A try to ensure the semaphore is upped in the child task.
            detached := false
            e := catch --trace=(: not is_close_exception_ it and it != DEADLINE_EXCEEDED_ERROR):
              detached = run_connection_ connection handler logger
            connection.close_write
            close_logger := e ? logger.with_tag "reason" e : logger
            if detached:
              close_logger.debug "client socket detached"
            else:
              close_logger.debug "connection ended"
          finally:
            if semaphore_: semaphore_.up  // Up the semaphore when the task ends.
        // End of code that can be run in the current task or in a child task.

        parent_task_semaphore = null  // We got this far, the semaphore is ours.
        if semaphore_:
          task --background handle_connection_closure
        else:
          // For the single-task case, just run the connection in the current task.
          handle_connection_closure.call
      finally:
        // Up the semaphore if we threw before starting the task.
        if parent_task_semaphore: parent_task_semaphore.up

  web_socket request/RequestIncoming response_writer/ResponseWriter -> WebSocket?:
    nonce := WebSocket.check_server_upgrade_request_ request response_writer
    if nonce == null: return null
    response_writer.write_headers STATUS_SWITCHING_PROTOCOLS
    return WebSocket response_writer.detach --no-client

  // Returns true if the connection was detached, false if it was closed.
  run_connection_ connection/Connection handler/Lambda logger/log.Logger -> bool:
    if call_in_finalizer_: connection.call_in_finalizer_ = call_in_finalizer_
    while true:
      request := null
      with_timeout read_timeout:
        request = connection.read_request
      if not request: return false  // Client closed connection.
      request_logger := logger
      if request.method != "GET":
        request_logger = request_logger.with_tag "method" request.method
      request_logger = request_logger.with_tag "path" request.path
      request_logger.debug "incoming request"
      writer ::= ResponseWriter connection request request_logger
      unwind_block := : | exception |
        // If there's an error we can either send a 500 error message or close
        // the connection.  This depends on whether we had already sent the
        // headers - can't send a 500 if we already sent a success header.
        closed := writer.close_on_exception_ "Internal Server error - $exception"
        closed   // Unwind if the connection is dead.
      if request.method == "HEAD":
        writer.write_headers STATUS_METHOD_NOT_ALLOWED --message="HEAD not implemented"
      else:
        catch --trace --unwind=unwind_block:
          handler.call request writer  // Calls the block passed to listen.
      if writer.detached_: return true
      if request.body.read:
        // The request (eg. a POST request) was not fully read - should have
        // been closed and return null from read.
        closed := writer.close_on_exception_ "Internal Server error - request not fully read"
        assert: closed
        throw "request not fully read: $request.path"
      writer.close

class ResponseWriter:
  static VERSION ::= "HTTP/1.1"

  connection_/Connection? := null
  request_/RequestIncoming
  logger_/log.Logger
  headers_/Headers
  body_writer_/BodyWriter? := null
  detached_/bool := false

  constructor .connection_ .request_ .logger_:
    headers_ = Headers

  headers -> Headers:
    if body_writer_: throw "headers already written"
    return headers_

  write_headers status_code/int --message/string?=null:
    if body_writer_: throw "headers already written"
    has_body := status_code != STATUS_NO_CONTENT
    write_headers_ status_code --message=message --has_body=has_body

  write data:
    write_headers_ STATUS_OK --message=null --has_body=true
    body_writer_.write data

  write_headers_ status_code/int --message/string? --has_body/bool:
    if body_writer_: return
    body_writer_ = connection_.send_headers
        "$VERSION $status_code $(message or (status_message status_code))\r\n"
        headers
        --is_client_request=false
        --has_body=has_body

  redirect status_code/int location/string --message/string?=null --body/string?=null -> none:
    headers.set "Location" location
    if body and body.size > 0:
      write_headers_ status_code --message=message --has_body=true
      body_writer_.write body
    else:
      write_headers_ status_code --message=message --has_body=false

  // Returns true if the connection was closed due to an error.
  close_on_exception_ message/string -> bool:
    logger_.info message
    if body_writer_:
      // We already sent a good response code, but then something went
      // wrong.  Hard close (RST) the connection to signal to the other end
      // that we failed.
      connection_.close
      connection_ = null
      return true
    else:
      // We don't have a body writer, so perhaps we didn't send a response
      // yet.  Send a 500 to indicate an internal server error.
      write_headers_ STATUS_INTERNAL_SERVER_ERROR --message=message --has_body=false
      return false

  // Close the response.  We call this automatically after the block if the
  // user's router did not call it.  Returns true if the connection was closed
  // due to an error.
  close -> none:
    if body_writer_:
      too_little := not body_writer_.is_done
      body_writer_.close
      if too_little:
        // This is typically the case if the user's code set a Content-Length
        // header, but then didn't write enough data.
        // Will hard close the connection.
        close_on_exception_ "Not enough data produced by server"
        return
    else:
      // Nothing was written, yet we are already closing.  This indicates
      // We return a 500 error code and log the issue.  We don't need to close
      // the connection.
      write_headers_ STATUS_INTERNAL_SERVER_ERROR --message=null --has_body=false
      logger_.info "Returned from router without any data for the client"

  detach -> tcp.Socket:
    detached_ = true
    connection := connection_
    connection_ = null
    return connection.detach
