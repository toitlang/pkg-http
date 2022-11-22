// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import encoding.json
import expect show *
import http
import net

import .cat

// Sets up a web server on localhost and connects to it.
// Then makes sure we can clean up with simple use of finalizer.
// Ideally you will see no "Forgot to close" messages on the output.

main:
  network := net.open
  port := start_server network
  run_client network port
  expect_not try_finally_didnt_work

try_finally_didnt_work := false

SERVER_CALL_IN_FINALIZER ::= ::
  try_finally_didnt_work = true
  throw "Server finalizer was called"

CLIENT_CALL_IN_FINALIZER ::= ::
  try_finally_didnt_work = true
  throw "Client finalizer was called"

run_client network port/int -> none:
  client := null

  10.repeat:
    // Just hit the finally clause after making a GET request.
    try:
      client = http.Client network
      response := client.get --host="localhost" --port=port --path="/cat.png"
      client.connection_.call_in_finalizer_ = CLIENT_CALL_IN_FINALIZER
    finally:
      client.close

  MESSAGE ::= "Expect to see this thrown once with a stack trace"
  exception := catch --trace:
    try:
      client = http.Client network
      response := client.get --host="localhost" --port=port --path="/cat.png"
      client.connection_.call_in_finalizer_ = CLIENT_CALL_IN_FINALIZER
      throw MESSAGE
    finally:
      client.close
  expect_equals MESSAGE exception

  10.repeat:
    // Hit the finally clause after making a GET request and reading a bit.
    try:
      client = http.Client network
      response := client.get --host="localhost" --port=port --path="/cat.png"
      client.connection_.call_in_finalizer_ = CLIENT_CALL_IN_FINALIZER
      data := response.body.read
      expect data != null
    finally:
      client.close

  10.repeat:
    // Hit the finally clause getting a 500
    try:
      client = http.Client network
      response := client.get --host="localhost" --port=port --path="/cause_500"
      client.connection_.call_in_finalizer_ = CLIENT_CALL_IN_FINALIZER
    finally:
      client.close

start_server network -> int:
  server_socket := network.tcp_listen 0
  port := server_socket.local_address.port
  server := http.Server
  task --background::
    listen server server_socket port
  print ""
  print "Listening on http://localhost:$port/"
  print ""
  return port

listen server server_socket my_port:
  server.call_in_finalizer_ = SERVER_CALL_IN_FINALIZER
  server.listen server_socket:: | request/http.RequestIncoming response_writer/http.ResponseWriter |
    if request.path == "/":
      response_writer.headers.set "Content-Type" "text/html"
      response_writer.write INDEX_HTML
    else if request.path == "/foo.json":
      response_writer.headers.set "Content-Type" "application/json"
      response_writer.write
        json.encode {"foo": 123, "bar": 1.0/3, "fizz": [1, 42, 103]}
    else if request.path == "/cat.png":
      response_writer.headers.set "Content-Type" "image/png"
      response_writer.write CAT
    else if request.path == "/redirect_from":
      response_writer.redirect http.STATUS_FOUND "http://localhost:$my_port/redirect_back"
    else if request.path == "/redirect_back":
      response_writer.redirect http.STATUS_FOUND "http://localhost:$my_port/foo.json"
    else if request.path == "/redirect_loop":
      response_writer.redirect http.STATUS_FOUND "http://localhost:$my_port/redirect_loop"
    else if request.path == "/cause_500":
      // Forget to write anything - the server should send 500 - Internal error.
    else if request.path == "/throw":
      throw "** Expect a stack trace here caused by testing\n** that we send 500 when server throws"
    else:
      response_writer.write_headers http.STATUS_NOT_FOUND --message="Not Found"
