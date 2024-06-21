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
  port := start-server network
  run-client network port
  expect-not try-finally-didnt-work

try-finally-didnt-work := false

SERVER-CALL-IN-FINALIZER ::= ::
  try-finally-didnt-work = true
  throw "Server finalizer was called"

CLIENT-CALL-IN-FINALIZER ::= ::
  try-finally-didnt-work = true
  throw "Client finalizer was called"

run-client network port/int -> none:
  client := null

  10.repeat:
    // Just hit the finally clause after making a GET request.
    try:
      client = http.Client network
      response := client.get --host="localhost" --port=port --path="/cat.png"
      client.connection_.call-in-finalizer_ = CLIENT-CALL-IN-FINALIZER
    finally:
      client.close

  MESSAGE ::= "Expect to see this thrown once with a stack trace"
  exception := catch --trace:
    try:
      client = http.Client network
      response := client.get --host="localhost" --port=port --path="/cat.png"
      client.connection_.call-in-finalizer_ = CLIENT-CALL-IN-FINALIZER
      throw MESSAGE
    finally:
      client.close
  expect-equals MESSAGE exception

  10.repeat:
    // Hit the finally clause after making a GET request and reading a bit.
    try:
      client = http.Client network
      response := client.get --host="localhost" --port=port --path="/cat.png"
      client.connection_.call-in-finalizer_ = CLIENT-CALL-IN-FINALIZER
      data := response.body.read
      expect data != null
    finally:
      client.close

  10.repeat:
    // Hit the finally clause getting a 500
    try:
      client = http.Client network
      response := client.get --host="localhost" --port=port --path="/cause_500"
      client.connection_.call-in-finalizer_ = CLIENT-CALL-IN-FINALIZER
    finally:
      client.close

start-server network -> int:
  server-socket := network.tcp-listen 0
  port := server-socket.local-address.port
  server := http.Server
  task --background::
    listen server server-socket port
  print ""
  print "Listening on http://localhost:$port/"
  print ""
  return port

listen server server-socket my-port:
  server.call-in-finalizer_ = SERVER-CALL-IN-FINALIZER
  server.listen server-socket:: | request/http.RequestIncoming response-writer/http.ResponseWriter |
    out := response-writer.out
    if request.path == "/":
      response-writer.headers.set "Content-Type" "text/html"
      out.write INDEX-HTML
    else if request.path == "/foo.json":
      response-writer.headers.set "Content-Type" "application/json"
      out.write
        json.encode {"foo": 123, "bar": 1.0/3, "fizz": [1, 42, 103]}
    else if request.path == "/cat.png":
      response-writer.headers.set "Content-Type" "image/png"
      out.write CAT
    else if request.path == "/redirect_from":
      response-writer.redirect http.STATUS-FOUND "http://localhost:$my-port/redirect_back"
    else if request.path == "/redirect_back":
      response-writer.redirect http.STATUS-FOUND "http://localhost:$my-port/foo.json"
    else if request.path == "/redirect_loop":
      response-writer.redirect http.STATUS-FOUND "http://localhost:$my-port/redirect_loop"
    else if request.path == "/cause_500":
      // Forget to write anything - the server should send 500 - Internal error.
    else if request.path == "/throw":
      throw "** Expect a stack trace here caused by testing\n** that we send 500 when server throws"
    else:
      response-writer.write-headers http.STATUS-NOT-FOUND --message="Not Found"
