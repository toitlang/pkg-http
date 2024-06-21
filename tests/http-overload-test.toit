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
  port := start-server network
  run-client network port

run-client network port/int -> none:
  20.repeat: | client-number |
    print client-number
    client := http.Client network
    response := client.get --host="localhost" --port=port --path="/"
    connection := client.connection_

    page := ""
    while data := response.body.read:
      page += data.to-string
    expect-equals INDEX-HTML.size page.size

    task::
      10.repeat:
        sleep --ms=50
        print "  $client-number Getting cat"
        cat-response := client.get --host="localhost" --port=port --path="/cat.png"
        expect-equals connection client.connection_  // Check we reused the connection.
        expect-equals "image/png"
            cat-response.headers.single "Content-Type"
        size := 0
        while data := cat-response.body.read:
          size += data.size
      client.close

start-server network -> int:
  server-socket1 := network.tcp-listen 0
  port1 := server-socket1.local-address.port
  server1 := http.Server --max-tasks=5
  print ""
  print "Listening on http://localhost:$port1/"
  print ""
  task --background:: listen server1 server-socket1 port1
  return port1

listen server server-socket my-port:
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
    else:
      response-writer.write-headers http.STATUS-NOT-FOUND --message="Not Found"
