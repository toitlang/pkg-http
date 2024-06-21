// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import encoding.json
import encoding.url
import expect show *
import http
import http.connection show is-close-exception_
import io
import net

import .cat

// Sets up a web server on localhost and connects to it.

main:
  network := net.open
  port := start-server network
  run-client network port

POST-DATA ::= {
    "foo": "bar",
    "date": "2023-04-25",
    "baz": "42?103",
    "/&%": "slash",
    "slash": "/&%"
}

class NonSizedTestReader extends io.Reader:
  call-count_ := 0
  chunks_ := List 5: "$it" * it

  read_ -> ByteArray?:
    if call-count_ == chunks_.size:
      return null
    call-count_++
    return chunks_[call-count_ - 1].to-byte-array

  full-data -> ByteArray:
    return (chunks_.join "").to-byte-array

run-client network port/int -> none:
  client := http.Client network

  connection := null

  2.repeat:

    response := client.get --host="localhost" --port=port --path="/"

    if connection:
      expect-equals connection client.connection_  // Check we reused the connection.
    else:
      connection = client.connection_

    page := ""
    while data := response.body.read:
      page += data.to-string
    expect-equals INDEX-HTML.size page.size

    response = client.get --host="localhost" --port=port --path="/cat.png"
    expect-equals connection client.connection_  // Check we reused the connection.
    expect-equals "image/png"
        response.headers.single "Content-Type"
    size := 0
    while data := response.body.read:
      size += data.size

    expect-equals CAT.size size

    response = client.get --host="localhost" --port=port --path="/unobtainium.jpeg"
    expect-equals connection client.connection_  // Check we reused the connection.
    expect-equals 404 response.status-code

    response = client.get --uri="http://localhost:$port/204_no_content"
    expect-equals 204 response.status-code
    expect-equals "Nothing more to say" (response.headers.single "X-Toit-Message")

    response = client.get --host="localhost" --port=port --path="/foo.json"
    expect-equals connection client.connection_  // Check we reused the connection.

    expect-json response:
      expect-equals 123 it["foo"]

  // Try to buffer the whole response.
  response := client.get --host="localhost" --port=port --path="/foo.json"
  expect-equals 200 response.status-code
  response.body.buffer-all
  bytes := response.body.read-all
  decoded := json.decode bytes
  expect-equals 123 decoded["foo"]

  response = client.get --uri="http://localhost:$port/content-length.json"
  expect-equals 200 response.status-code
  expect-equals "application/json"
      response.headers.single "Content-Type"
  content-length := response.headers.single "Content-Length"
  expect-not-null content-length
  expect-json response:
    expect-equals 123 it["foo"]

  // Try to buffer the whole response.
  response = client.get --uri="http://localhost:$port/content-length.json"
  expect-equals 200 response.status-code
  response.body.buffer-all
  bytes = response.body.read-all
  decoded = json.decode bytes
  expect-equals 123 decoded["foo"]

  response = client.get --uri="http://localhost:$port/redirect_back"
  expect connection != client.connection_  // Because of the redirect we had to make a new connection.
  expect-equals "application/json"
      response.headers.single "Content-Type"
  expect-json response:
    expect-equals 123 it["foo"]

  expect-throw "Too many redirects": client.get --uri="http://localhost:$port/redirect_loop"

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect-equals 200 response.status-code
  response.drain

  connection = client.connection_

  response = client.get --uri="http://localhost:$port/500_because_nothing_written"
  expect-equals 500 response.status-code

  expect-equals connection client.connection_  // Check we reused the connection.

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect-equals 200 response.status-code
  expect-equals connection client.connection_  // Check we reused the connection.
  response.drain

  response2 := client.get --uri="http://localhost:$port/500_because_throw_before_headers"
  expect-equals 500 response2.status-code

  expect-equals connection client.connection_  // Check we reused the connection.

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect-equals 200 response.status-code
  expect-equals connection client.connection_  // Check we reused the connection.
  response.drain

  exception3 := catch --trace=(: not is-close-exception_ it):
    response3 := client.get --uri="http://localhost:$port/hard_close_because_wrote_too_little"
    if 200 <= response3.status-code <= 299:
      while response3.body.read: null
  // TODO: This should be a smaller number of different exceptions and the
  // library should export a non-private method that recognizes them.
  expect (is-close-exception_ exception3)

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect-equals 200 response.status-code
  // We will not be reusing the connection here because the server had to close it
  // after the user's router did not write enough data.
  expect-not-equals connection client.connection_  // Check we reused the connection.
  response.drain

  connection = client.connection_

  exception4 := catch --trace=(: not is-close-exception_ it):
    response4 := client.get --uri="http://localhost:$port/hard_close_because_throw_after_headers"
    if 200 <= response4.status-code <= 299:
      while response4.body.read: null
  expect (is-close-exception_ exception4)

  response = client.get --host="localhost" --port=port --path="/foo.json"
  expect-equals 200 response.status-code
  // We will not be reusing the connection here because the server had to close it
  expect
    is-close-exception_ exception4
  // after the user's router threw after writing success headers.
  expect-not-equals connection client.connection_  // Check we reused the connection.
  response.drain

  connection = client.connection_

  response5 := client.get --uri="http://localhost:$port/redirect_from"
  expect connection != client.connection_  // Because of two redirects we had to make two new connections.
  expect-json response5:
    expect-equals 123 it["foo"]

  data := {"foo": "bar", "baz": [42, 103]}

  response6 := client.post-json data --uri="http://localhost:$port/post_json"
  expect-equals "application/json"
      response6.headers.single "Content-Type"
  expect-json response6:
    expect-equals data["foo"] it["foo"]
    expect-equals data["baz"] it["baz"]

  response7 := client.post-json data --uri="http://localhost:$port/post_json_redirected_to_cat"
  expect-equals "image/png"
      response7.headers.single "Content-Type"
  round-trip-cat := #[]
  while byte-array := response7.body.read:
    round-trip-cat += byte-array
  expect-equals CAT round-trip-cat

  response8 := client.get --uri="http://localhost:$port/subdir/redirect_relative"
  expect-json response8:
    expect-equals 345 it["bar"]

  response9 := client.get --uri="http://localhost:$port/subdir/redirect_absolute"
  expect-json response9:
    expect-equals 123 it["foo"]

  request := client.new-request "HEAD" --host="localhost" --port=port --path="/foohead.json"
  response10 := request.send
  expect-equals 405 response10.status-code

  response11 := client.post-form --host="localhost" --port=port --path="/post_form" POST-DATA
  expect-equals 200 response11.status-code

  test-reader := NonSizedTestReader
  request = client.new-request "POST" --host="localhost" --port=port --path="/post_chunked"
  request.body = test-reader
  response12 := request.send
  expect-equals 200 response12.status-code
  response-data := #[]
  while chunk := response12.body.read:
    response-data += chunk
  expect-equals test-reader.full-data response-data

  response13 := client.get --host="localhost" --port=port --path="/get_with_parameters" --query-parameters=POST-DATA
  response-data = #[]
  while chunk := response13.body.read:
    response-data += chunk
  expect-equals "Response with parameters" response-data.to-string

  request = client.new-request "GET" --host="localhost" --port=port --path="/get_with_parameters" --query-parameters=POST-DATA
  response14 := request.send
  expect-equals 200 response14.status-code
  while chunk := response13.body.read:
    response-data += chunk
  expect-equals "Response with parameters" response-data.to-string

  client.close

expect-json response/http.Response [verify-block]:
  expect-equals "application/json"
      response.headers.single "Content-Type"
  crock := #[]
  while data := response.body.read:
    crock += data
  result := json.decode crock
  verify-block.call result

start-server network -> int:
  server-socket1 := network.tcp-listen 0
  port1 := server-socket1.local-address.port
  server1 := http.Server
  server-socket2 := network.tcp-listen 0
  port2 := server-socket2.local-address.port
  server2 := http.Server
  task --background::
    listen server1 server-socket1 port1 port2
  task --background::
    listen server2 server-socket2 port2 port1
  print ""
  print "Listening on http://localhost:$port1/"
  print "Listening on http://localhost:$port2/"
  print ""
  return port1


listen server server-socket my-port other-port:
  server.listen server-socket:: | request/http.RequestIncoming response-writer/http.ResponseWriter |
    if request.method == "POST" and request.path != "/post_chunked":
      expect-not-null (request.headers.single "Content-Length")

    resource := request.query.resource

    writer := response-writer.out
    if resource == "/":
      response-writer.headers.set "Content-Type" "text/html"
      writer.write INDEX-HTML
    else if resource == "/foo.json":
      response-writer.headers.set "Content-Type" "application/json"
      writer.write
        json.encode {"foo": 123, "bar": 1.0/3, "fizz": [1, 42, 103]}
    else if resource == "/content-length.json":
      data := json.encode {"foo": 123, "bar": 1.0/3, "fizz": [1, 42, 103]}
      response-writer.headers.set "Content-Type" "application/json"
      response-writer.headers.set "Content-Length" "$data.size"
      writer.write data
    else if resource == "/cat.png":
      response-writer.headers.set "Content-Type" "image/png"
      writer.write CAT
    else if resource == "/redirect_from":
      response-writer.redirect http.STATUS-FOUND "http://localhost:$other-port/redirect_back"
    else if resource == "/redirect_back":
      response-writer.redirect http.STATUS-FOUND "http://localhost:$other-port/foo.json"
    else if resource == "/subdir/redirect_relative":
      response-writer.redirect http.STATUS-FOUND "bar.json"
    else if resource == "/subdir/bar.json":
      response-writer.headers.set "Content-Type" "application/json"
      writer.write
        json.encode {"bar": 345 }
    else if resource == "/subdir/redirect_absolute":
      response-writer.redirect http.STATUS-FOUND "/foo.json"
    else if resource == "/redirect_loop":
      response-writer.redirect http.STATUS-FOUND "http://localhost:$other-port/redirect_loop"
    else if resource == "/204_no_content":
      response-writer.headers.set "X-Toit-Message" "Nothing more to say"
      response-writer.write-headers http.STATUS-NO-CONTENT
    else if resource == "/500_because_nothing_written":
      // Forget to write anything - the server should send 500 - Internal error.
    else if resource == "/500_because_throw_before_headers":
      throw "** Expect a stack trace here caused by testing: throws_before_headers **"
    else if resource == "/hard_close_because_wrote_too_little":
      response-writer.headers.set "Content-Length" "2"
      writer.write "x"  // Only writes half the message.
    else if resource == "/hard_close_because_throw_after_headers":
      response-writer.headers.set "Content-Length" "2"
      writer.write "x"  // Only writes half the message.
      throw "** Expect a stack trace here caused by testing: throws_after_headers **"
    else if resource == "/post_json":
      response-writer.headers.set "Content-Type" "application/json"
      while data := request.body.read:
        writer.write data
    else if resource == "/post_form":
      expect-equals "application/x-www-form-urlencoded" (request.headers.single "Content-Type")
      response-writer.headers.set "Content-Type" "text/plain"
      str := ""
      while data := request.body.read:
        str += data.to-string
      map := {:}
      str.split "&": | pair |
        parts := pair.split "="
        key := url.decode parts[0]
        value := url.decode parts[1]
        map[key.to-string] = value.to-string
      expect-equals POST-DATA.size map.size
      POST-DATA.do: | key value |
        expect-equals POST-DATA[key] map[key]
      writer.write "OK"
    else if resource == "/post_json_redirected_to_cat":
      response-writer.headers.set "Content-Type" "application/json"
      while data := request.body.read:
      response-writer.redirect http.STATUS-SEE-OTHER "http://localhost:$my-port/cat.png"
    else if resource == "/post_chunked":
      response-writer.headers.set "Content-Type" "text/plain"
      while data := request.body.read:
        writer.write data
    else if request.query.resource == "/get_with_parameters":
      response-writer.headers.set "Content-Type" "text/plain"
      writer.write "Response with parameters"
      POST-DATA.do: | key/string value/string |
        expect-equals value request.query.parameters[key]
    else:
      print "request.query.resource = '$request.query.resource'"
      response-writer.write-headers http.STATUS-NOT-FOUND --message="Not Found"
