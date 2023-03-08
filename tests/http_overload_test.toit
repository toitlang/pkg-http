// Copyright (C) 2023 Toitware ApS.
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
  20.repeat: | client_number |
    print client_number
    client := http.Client network
    response := client.get --host="localhost" --port=port --path="/"
    connection := client.connection_

    page := ""
    while data := response.body.read:
      page += data.to_string
    expect_equals INDEX_HTML.size page.size

    task::
      10.repeat:
        sleep --ms=50
        print "  $client_number Getting cat"
        cat_response := client.get --host="localhost" --port=port --path="/cat.png"
        expect_equals connection client.connection_  // Check we reused the connection.
        expect_equals "image/png"
            cat_response.headers.single "Content-Type"
        size := 0
        while data := cat_response.body.read:
          size += data.size
      client.close

start_server network -> int:
  server_socket1 := network.tcp_listen 0
  port1 := server_socket1.local_address.port
  server1 := http.Server --max_tasks=5
  print ""
  print "Listening on http://localhost:$port1/"
  print ""
  task --background:: listen server1 server_socket1 port1
  return port1

listen server server_socket my_port:
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
    else:
      response_writer.write_headers http.STATUS_NOT_FOUND --message="Not Found"
