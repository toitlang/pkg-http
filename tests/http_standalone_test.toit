// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import encoding.json
import expect show *
import http
import net

import .cat

// Sets up a web server on localhost and connects to it.

main:
  network := net.open
  port := start_server network
  run_client network port

run_client network port/int -> none:
  client := http.Client network

  connection := null

  2.repeat:

    response := client.get --host="localhost" --port=port --path="/"

    if connection:
      expect_equals connection client.connection_  // Check we reused the connection.
    else:
      connection = client.connection_

    page := ""
    while data := response.body.read:
      page += data.to_string
    expect_equals INDEX_HTML.size page.size

    response = client.get --host="localhost" --port=port --path="/cat.png"
    expect_equals connection client.connection_  // Check we reused the connection.
    expect_equals "image/png"
        response.headers.single "Content-Type"
    size := 0
    while data := response.body.read:
      size += data.size

    expect_equals CAT.size size

    response = client.get --host="localhost" --port=port --path="/unobtainium.jpeg"
    expect_equals connection client.connection_  // Check we reused the connection.
    expect_equals 404 response.status_code

    response = client.get --uri="http://localhost:$port/204_no_content"
    expect_equals 204 response.status_code
    expect_equals "Nothing more to say" (response.headers.single "X-Toit-Message")

    response = client.get --host="localhost" --port=port --path="/foo.json"
    expect_equals connection client.connection_  // Check we reused the connection.

    expect_equals "application/json"
        response.headers.single "Content-Type"
    crock := #[]
    while data := response.body.read:
      crock += data
    json.decode crock

  response := client.get --uri="http://localhost:$port/redirect_back"
  expect connection != client.connection_  // Because of the redirect we had to make a new connection.
  expect_equals "application/json"
      response.headers.single "Content-Type"
  crock := #[]
  while data := response.body.read:
    crock += data
  json.decode crock

  expect_throw "Too many redirects": client.get --uri="http://localhost:$port/redirect_loop"

  response = client.get --uri="http://localhost:$port/500_because_nothing_written"
  expect_equals 500 response.status_code

  response2 := client.get --uri="http://localhost:$port/500_because_throw_before_headers"
  expect_equals 500 response2.status_code

  exception3 := catch:
    response3 := client.get --uri="http://localhost:$port/hard_close_because_wrote_too_little"
    if 200 <= response3.status_code <= 299:
      while response3.body.read: null
  expect_equals "UNEXPECTED_END_OF_READER" exception3

  exception4 := catch:
    response4 := client.get --uri="http://localhost:$port/hard_close_because_throw_after_headers"
    if 200 <= response4.status_code <= 299:
      while response4.body.read: null
  expect_equals "UNEXPECTED_END_OF_READER" exception4

  response5 := client.get --uri="http://localhost:$port/redirect_from"
  expect connection != client.connection_  // Because of two redirects we had to make two new connections.
  expect_equals "application/json"
      response5.headers.single "Content-Type"
  crock2 := #[]
  while data := response5.body.read:
    crock2 += data
  json.decode crock2

  client.close

start_server network -> int:
  server_socket1 := network.tcp_listen 0
  port1 := server_socket1.local_address.port
  server1 := http.Server
  server_socket2 := network.tcp_listen 0
  port2 := server_socket2.local_address.port
  server2 := http.Server
  task --background::
    listen server1 server_socket1 port1 port2
  task --background::
    listen server2 server_socket2 port2 port1
  print ""
  print "Listening on http://localhost:$port1/"
  print "Listening on http://localhost:$port2/"
  print ""
  return port1


listen server server_socket my_port other_port:
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
      response_writer.redirect http.STATUS_FOUND "http://localhost:$other_port/redirect_back"
    else if request.path == "/redirect_back":
      response_writer.redirect http.STATUS_FOUND "http://localhost:$other_port/foo.json"
    else if request.path == "/redirect_loop":
      response_writer.redirect http.STATUS_FOUND "http://localhost:$other_port/redirect_loop"
    else if request.path == "/204_no_content":
      response_writer.headers.set "X-Toit-Message" "Nothing more to say"
      response_writer.write_headers http.STATUS_NO_CONTENT
    else if request.path == "/500_because_nothing_written":
      // Forget to write anything - the server should send 500 - Internal error.
    else if request.path == "/500_because_throw_before_headers":
      throw "** Expect a stack trace here caused by testing\n** that we send 500 when server throws"
    else if request.path == "/hard_close_because_wrote_too_little":
      response_writer.headers.set "Content-Length" "2"
      response_writer.write "x"  // Only writes half the message.
    else if request.path == "/hard_close_because_throw_after_headers":
      response_writer.headers.set "Content-Length" "2"
      response_writer.write "x"  // Only writes half the message.
      throw "** Expect a stack trace here caused by testing\n** that we close the connection on a throw"
    else:
      response_writer.write_headers http.STATUS_NOT_FOUND --message="Not Found"
