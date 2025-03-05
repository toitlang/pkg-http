// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import encoding.json
import encoding.url
import expect show *
import host.file
import http
import http.connection show is-close-exception_
import io
import net

import .webdriver

main args/List:
  if args.is-empty: return

  started := Time.now
  time-log := :: | message/string |
    print "$message: $(Duration.since started)"

  network := net.open

  browser := args.first
  server-task := start-server network

  if browser == "--serve":
    // Just run the server.
    return

  if not DRIVERS_.get browser:
    // This test may be called from the Toit repository with the wrong arguments.
    // We don't want to fail in that case.
    print "*********************************************"
    print "IGNORING UNSUPPORTED BROWSER: $browser"
    print "*********************************************"
    server-task.cancel
    return

  web-driver := WebDriver browser
  web-driver.start
  try:
    time-log.call "Testing status"
    test-status web-driver
    print "Testing json"
    test-json web-driver
    print "Testing json content-length"
    test-json-content-length web-driver
    print "Testing 204 no content"
    test-204-no-content web-driver
    print "Testing 500 because nothing written"
    test-500-because-nothing-written web-driver
    print "Testing 500 because throw before headers"
    test-500-because-throw-before-headers web-driver
    print "Testing hard close because wrote too little"
    test-hard-close-because-wrote-too-little web-driver
    print "Testing hard close because throw after headers"
    test-hard-close-because-throw-after-headers web-driver
    print "Testing post json"
    test-post-json web-driver
    print "Testing post form"
    test-post-form web-driver
    print "Testing get with parameters"
    test-get-with-parameters web-driver
    print "Testing websocket"
    test-websocket web-driver
    print "Testing done"
  finally:
    web-driver.close
    server-task.cancel

// Is set by start-server.
URL/string? := null

HTML ::= """
<!DOCTYPE html>
<html>
  <head>
    <title>Test</title>
  </head>
  <body>
    <div id="status">Pending</div>
    <script type="text/javascript">
    try {
      SCRIPT
    } catch (e) {
      document.getElementById('status').innerText = 'Bad';
      throw e;
    }
    </script>
  </body>
</html>
"""

build-xml-request -> string
    path/string
    expected-status/int
    response-check/string
    --expect-send-error/bool=false
    --method="GET"
    --payload/string="":
  send-error-handler := ""
  catch-handler := ""
  if expect-send-error:
    send-error-handler = """
      if (xhr.status !== 0) {
        throw 'Error: Unexpected status ' + xhr.status;
      } else {
        document.getElementById('status').innerText = 'OK';
        return;
      }
      """
  else:
    catch-handler = """
      throw e;
    """

  return """
    var xhr = new XMLHttpRequest();
    xhr.open('$method', '$path', true);
    xhr.onreadystatechange = function() {
      if (xhr.readyState == 4) {
        $send-error-handler
        if (xhr.status !== $expected-status) {
          throw 'Error ' + xhr.status + ' ' + xhr.statusText;
        }
        $response-check
        document.getElementById('status').innerText = 'OK';
      }
    };
    try {
      xhr.send('$payload');
    } catch (e) {
      $catch-handler
    }
  """

get-text driver/WebDriver --id/string -> string:
  for i := 0; i < 10; i++:
    driver-ids := driver.find "#$id"
    if driver-ids.is-empty:
      sleep --ms=(10 * i)
      continue
    return driver.get-text driver-ids.first
  throw "Timeout waiting for element with id '$id'"

expect-ok path/string driver/WebDriver -> none:
  start-time := Time.now
  driver.goto "$URL/$path"
  for i := 0; i < 10; i++:
    print "Waiting for status ($((Duration.since start-time).in-s)s..."
    text := get-text driver --id="status"
    print "Status: $text"
    if text != "Pending":
      expect-equals "OK" text
      return
    sleep --ms=(10 * i)
  throw "Timeout waiting for 'OK'"

test-status driver/WebDriver -> none:
  expect-ok "test-status" driver

html-status -> string:
  return HTML.replace "SCRIPT" """
    document.getElementById('status').innerText = 'OK';
    """

test-json driver/WebDriver -> none:
  expect-ok "test-json" driver

html-json path/string -> string:
  return HTML.replace "SCRIPT"
      build-xml-request path 200 """
        var json = JSON.parse(xhr.responseText);
        if (json.foo !== 123) {
          throw 'Error ' + json.foo;
        }
        // Check that the content-length header is *not* present.
        if (xhr.getResponseHeader('Content-Length') !== null) {
          throw 'Error: Content-Length header is present';
        }
        """

test-json-content-length driver/WebDriver -> none:
  expect-ok "test-json-content-length" driver

html-json-content-length path/string -> string:
  return HTML.replace "SCRIPT"
      build-xml-request path 200 """
        var json = JSON.parse(xhr.responseText);
        if (json.foo !== 1234) {
          throw 'Error ' + json.foo;
        }
        // Check that the content-length header is present.
        if (xhr.getResponseHeader('Content-Length') === null) {
          throw 'Error: Content-Length header missing';
        }
        """

test-204-no-content driver/WebDriver -> none:
  expect-ok "test-204-no-content" driver

html-204-no-content path/string -> string:
  return HTML.replace "SCRIPT"
      build-xml-request path 204 """
        if (xhr.getResponseHeader('X-Toit-Message') !== 'Nothing more to say') {
          throw 'Error ' + xhr.getResponseHeader('X-Toit-Message');
        }
        """

test-500-because-nothing-written driver/WebDriver -> none:
  expect-ok "test-500-because-nothing-written" driver

html-500-because-nothing-written path/string -> string:
  return HTML.replace "SCRIPT"
      build-xml-request path 500 """
        if (xhr.status !== 500) {
          throw 'Error ' + xhr.status + ' ' + xhr.statusText;
        }
        """

test-500-because-throw-before-headers driver/WebDriver -> none:
  expect-ok "test-500-because-throw-before-headers" driver

html-500-because-throw-before-headers path/string -> string:
  return HTML.replace "SCRIPT"
      build-xml-request path 500 """
        if (xhr.status !== 500) {
          throw 'Error ' + xhr.status + ' ' + xhr.statusText;
        }
        """

test-hard-close-because-wrote-too-little driver/WebDriver -> none:
  expect-ok "test-hard-close-because-wrote-too-little" driver

html-hard-close-because-wrote-too-little path/string -> string:
  return HTML.replace "SCRIPT"
      build-xml-request path 200 "" --expect-send-error

test-hard-close-because-throw-after-headers driver/WebDriver -> none:
  expect-ok "test-hard-close-because-throw-after-headers" driver

html-hard-close-because-throw-after-headers path/string -> string:
  return HTML.replace "SCRIPT"
      build-xml-request path 200 "" --expect-send-error

test-post-json driver/WebDriver -> none:
  expect-ok "test-post-json" driver

html-post-json path/string -> string:
  payload := """{"foo": "bar", "baz": [42, 103]}"""
  return HTML.replace "SCRIPT"
      build-xml-request path 200
        --method="POST"
        --payload=payload
        """
        var json = JSON.parse(xhr.responseText);
        if (json.foo !== 'bar') {
          throw 'Error ' + json.foo;
        }
        if (json.baz[0] !== 42) {
          throw 'Error ' + json.baz[0];
        }
        if (xhr.getResponseHeader('Content-Type') !== 'application/json') {
          throw 'Error: Content-Type header is missing';
        }
        """

POST-FORM-DATA ::= {
  "foo": "bar",
  "date": "2023-04-25",
  "baz": "42?103",
  "/&%": "slash",
  "slash": "/&%"
}

test-form driver/WebDriver path/string -> none:
  driver.goto "$URL/$path"
  id := driver.find "#submit"
  driver.click id.first
  expect-equals "OK" (get-text driver --id="status")

test-post-form driver/WebDriver -> none:
  test-form driver "test-post-form"

html-form --method/string --path/string -> string:
  return """
    <DOCTYPE html>
    <html>
      <head>
        <title>Test</title>
      </head>
      <body>
        <form name="inputform" id="inputform" action="$path" method="$method">
          <input type="text" id="foo" name="foo" value="bar">
          <input type="text" id="date" name="date" value="2023-04-25">
          <input type="text" id="baz" name="baz" value="42?103">
          <input type="text" id="/&%" name="/&%" value="slash">
          <input type="text" id="slash" name="slash" value="/&%">
          <input type="submit" value="Submit" id="submit">
        </form>
      </body>
    </html>
    """

html-form-ok -> string:
  return HTML.replace "SCRIPT" """
      document.getElementById('status').innerText = 'OK';
      """

html-post-form path/string -> string:
  return html-form --path=path --method="post"

test-get-with-parameters driver/WebDriver -> none:
  test-form driver "test-get-with-parameters"

html-get-with-parameters path/string -> string:
  return html-form --path=path --method="get"

test-websocket driver/WebDriver -> none:
  expect-ok "test-websocket" driver

html-websocket path/string -> string:
  return """
    <DOCTYPE html>
    <html>
      <head>
        <title>Test</title>
      </head>
      <body>
        <div id="status">Pending</div>
        <script type="text/javascript">
          try {
            var ws = new WebSocket("$path");
            ws.onopen = function() {
              ws.send("Hello");
            };
            ws.onmessage = function(event) {
              if (event.data === "Hello") {
                ws.send("World");
              } else if (event.data === "World") {
                document.getElementById('status').innerText = 'OK';
              } else {
                document.getElementById('status').innerText = 'Bad';
                throw 'Error: Unexpected message ' + event.data;
              }
            };
          } catch (e) {
            document.getElementById('status').innerText = 'Bad';
            throw e;
          }
        </script>
      </body>
    </html>
    """

start-server network -> Task:
  server-socket := network.tcp-listen 0
  port := server-socket.local-address.port
  URL = "http://localhost:$port"
  print "Server running on $URL"
  server := http.Server --max-tasks=50
  return task:: listen server server-socket port

listen server server-socket my-port:
  server.listen server-socket:: | request/http.RequestIncoming response-writer/http.ResponseWriter |
    if request.method == "POST" and request.path != "/post_chunked":
      expect-not-null (request.headers.single "Content-Length")

    resource := request.query.resource

    writer := response-writer.out

    fill-html := : | text/string |
      response-writer.headers.set "Content-Type" "text/html"
      writer.write text

    if resource == "/test-status":
      fill-html.call html-status
    else if resource == "/test-json":
      fill-html.call (html-json "/foo.json")
    else if resource == "/foo.json":
      response-writer.headers.set "Content-Type" "application/json"
      writer.write
        json.encode {"foo": 123, "bar": 1.0/3, "fizz": [1, 42, 103]}
    else if resource == "/test-json-content-length":
      fill-html.call (html-json-content-length "/content-length.json")
    else if resource == "/content-length.json":
      data := json.encode {"foo": 1234, "bar": 1.0/3, "fizz": [1, 42, 103]}
      response-writer.headers.set "Content-Type" "application/json"
      response-writer.headers.set "Content-Length" "$data.size"
      writer.write data
    else if resource == "/test-204-no-content":
      fill-html.call (html-204-no-content "/204-no-content")
    else if resource == "/204-no-content":
      response-writer.headers.set "X-Toit-Message" "Nothing more to say"
      response-writer.write-headers http.STATUS-NO-CONTENT
    else if resource == "/test-500-because-nothing-written":
      fill-html.call (html-500-because-nothing-written "/500-because-nothing-written")
    else if resource == "/500-because-nothing-written":
      // Forget to write anything - the server should send 500 - Internal error.
    else if resource == "/test-500-because-throw-before-headers":
      fill-html.call (html-500-because-throw-before-headers "/500-because-throw-before-headers")
    else if resource == "/500-because-throw-before-headers":
      throw "** Expect a stack trace here caused by testing: throws-before-headers **"
    else if resource == "/test-hard-close-because-wrote-too-little":
      fill-html.call (html-hard-close-because-wrote-too-little "/hard-close-because-wrote-too-little")
    else if resource == "/hard-close-because-wrote-too-little":
      response-writer.headers.set "Content-Length" "2"
      writer.write "x"  // Only writes half the message.
    else if resource == "/test-hard-close-because-throw-after-headers":
      fill-html.call (html-hard-close-because-throw-after-headers "/hard-close-because-throw-after-headers")
    else if resource == "/hard-close-because-throw-after-headers":
      response-writer.headers.set "Content-Length" "2"
      writer.write "x"  // Only writes half the message.
      throw "** Expect a stack trace here caused by testing: throws-after-headers **"
    else if resource == "/test-post-json":
      fill-html.call (html-post-json "/post-json")
    else if resource == "/post-json":
      response-writer.headers.set "Content-Type" "application/json"
      while data := request.body.read:
        writer.write data
    else if resource == "/test-post-form":
      fill-html.call (html-post-form "/post-form")
    else if resource == "/post-form":
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
      expect-equals POST-FORM-DATA.size map.size
      POST-FORM-DATA.do: | key value |
        expect-equals POST-FORM-DATA[key] map[key]
      fill-html.call html-form-ok
    else if resource == "/test-get-with-parameters":
      fill-html.call (html-get-with-parameters "/get-with-parameters")
    else if resource == "/get-with-parameters":
      response-writer.headers.set "Content-Type" "text/plain"
      POST-FORM-DATA.do: | key/string value/string |
        expect-equals value request.query.parameters[key]
      fill-html.call html-form-ok
    else if resource == "/test-websocket":
      fill-html.call (html-websocket "/ws")
    else if resource == "/ws":
      web-socket := server.web-socket request response-writer
      // For this test, the server end of the web socket just echoes back
      // what it gets.
      while data := web-socket.receive:
        web-socket.send data
      web-socket.close
    else:
      print "request.query.resource = '$request.query.resource'"
      response-writer.write-headers http.STATUS-NOT-FOUND --message="Not Found"
