// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import encoding.json
import expect show *
import http
import http.connection show is_close_exception_
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

    expect_json response:
      expect_equals 123 it["foo"]

  response := client.get --uri="http://localhost:$port/redirect_back"
  expect connection != client.connection_  // Because of the redirect we had to make a new connection.
  expect_equals "application/json"
      response.headers.single "Content-Type"
  expect_json response:
    expect_equals 123 it["foo"]

  expect_throw "Too many redirects": client.get --uri="http://localhost:$port/redirect_loop"

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect_equals 200 response.status_code
  response.drain

  connection = client.connection_

  response = client.get --uri="http://localhost:$port/500_because_nothing_written"
  expect_equals 500 response.status_code

  expect_equals connection client.connection_  // Check we reused the connection.

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect_equals 200 response.status_code
  expect_equals connection client.connection_  // Check we reused the connection.
  response.drain

  response2 := client.get --uri="http://localhost:$port/500_because_throw_before_headers"
  expect_equals 500 response2.status_code

  expect_equals connection client.connection_  // Check we reused the connection.

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect_equals 200 response.status_code
  expect_equals connection client.connection_  // Check we reused the connection.
  response.drain

  exception3 := catch --trace=(: it != "UNEXPECTED_END_OF_READER"):
    response3 := client.get --uri="http://localhost:$port/hard_close_because_wrote_too_little"
    if 200 <= response3.status_code <= 299:
      while response3.body.read: null
  // TODO: This should be a smaller number of different exceptions and the
  // library should export a non-private method that recognizes them.
  expect (is_close_exception_ exception3)

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect_equals 200 response.status_code
  // We will not be reusing the connection here because the server had to close it
  // after the user's router did not write enough data.
  expect_not_equals connection client.connection_  // Check we reused the connection.
  response.drain

  connection = client.connection_

  exception4 := catch --trace=(: it != "UNEXPECTED_END_OF_READER"):
    response4 := client.get --uri="http://localhost:$port/hard_close_because_throw_after_headers"
    if 200 <= response4.status_code <= 299:
      while response4.body.read: null
  expect (is_close_exception_ exception4)

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect_equals 200 response.status_code
  // We will not be reusing the connection here because the server had to close it
  expect_equals "UNEXPECTED_END_OF_READER" exception4
  // after the user's router threw after writing success headers.
  expect_not_equals connection client.connection_  // Check we reused the connection.
  response.drain

  connection = client.connection_

  response5 := client.get --uri="http://localhost:$port/redirect_from"
  expect connection != client.connection_  // Because of two redirects we had to make two new connections.
  expect_json response5:
    expect_equals 123 it["foo"]

  data := {"foo": "bar", "baz": [42, 103]}

  response6 := client.post_json data --uri="http://localhost:$port/post_json"
  expect_equals "application/json"
      response6.headers.single "Content-Type"
  expect_json response6:
    expect_equals data["foo"] it["foo"]
    expect_equals data["baz"] it["baz"]

  response7 := client.post_json data --uri="http://localhost:$port/post_json_redirected_to_cat"
  expect_equals "image/png"
      response7.headers.single "Content-Type"
  round_trip_cat := #[]
  while byte_array := response7.body.read:
    round_trip_cat += byte_array
  expect_equals CAT round_trip_cat

  response8 := client.get --uri="http://localhost:$port/subdir/redirect_relative"
  expect_json response8:
    expect_equals 345 it["bar"]

  response9 := client.get --uri="http://localhost:$port/subdir/redirect_absolute"
  expect_json response9:
    expect_equals 123 it["foo"]

  request := client.new_request "HEAD" --host="localhost" --port=port --path="/foohead.json"
  response10 := request.send
  expect_equals 405 response10.status_code

  client.close

expect_json response/http.Response [verify_block]:
  expect_equals "application/json"
      response.headers.single "Content-Type"
  crock := #[]
  while data := response.body.read:
    crock += data
  result := json.decode crock
  verify_block.call result

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
    else if request.path == "/subdir/redirect_relative":
      response_writer.redirect http.STATUS_FOUND "bar.json"
    else if request.path == "/subdir/bar.json":
      response_writer.headers.set "Content-Type" "application/json"
      response_writer.write
        json.encode {"bar": 345 }
    else if request.path == "/subdir/redirect_absolute":
      response_writer.redirect http.STATUS_FOUND "/foo.json"
    else if request.path == "/redirect_loop":
      response_writer.redirect http.STATUS_FOUND "http://localhost:$other_port/redirect_loop"
    else if request.path == "/204_no_content":
      response_writer.headers.set "X-Toit-Message" "Nothing more to say"
      response_writer.write_headers http.STATUS_NO_CONTENT
    else if request.path == "/500_because_nothing_written":
      // Forget to write anything - the server should send 500 - Internal error.
    else if request.path == "/500_because_throw_before_headers":
      throw "** Expect a stack trace here caused by testing: throws_before_headers **"
    else if request.path == "/hard_close_because_wrote_too_little":
      response_writer.headers.set "Content-Length" "2"
      response_writer.write "x"  // Only writes half the message.
    else if request.path == "/hard_close_because_throw_after_headers":
      response_writer.headers.set "Content-Length" "2"
      response_writer.write "x"  // Only writes half the message.
      throw "** Expect a stack trace here caused by testing: throws_after_headers **"
    else if request.path == "/post_json":
      response_writer.headers.set "Content-Type" "application/json"
      while data := request.body.read:
        response_writer.write data
    else if request.path == "/post_json_redirected_to_cat":
      response_writer.headers.set "Content-Type" "application/json"
      while data := request.body.read:
      response_writer.redirect http.STATUS_SEE_OTHER "http://localhost:$my_port/cat.png"
    else:
      response_writer.write_headers http.STATUS_NOT_FOUND --message="Not Found"
