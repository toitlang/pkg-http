// Copyright (C) 2024 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import fs
import host.pipe
import http
import encoding.json
import net
import system

DRIVERS_ ::= {
  "chrome": "chromedriver",
  "firefox": "geckodriver",
  "safari": "safaridriver",
  "edge": "msedgedriver",
}

class WebDriver:
  driver-app_/string
  child-process_/any := null
  session-url_/string? := null
  network_/net.Interface? := null
  client_/http.Client? := null

  constructor browser/string:
    driver := DRIVERS_.get browser
    if driver == null:
      throw "Unsupported browser: $browser"
    driver-app_ = driver


  start:
    program-path := system.program-path
    program-dir := fs.dirname program-path
    extension := system.platform == system.PLATFORM-WINDOWS ? ".exe" : ""
    port/string := pipe.backticks
        "python$extension"
        "$program-dir/third-party/ephemeral-port-reserve/ephemeral_port_reserve.py"
    port = port.trim
    command := ["$driver-app_$extension", "--port=$port"]
    fork-data := pipe.fork
        true                // use_path
        pipe.PIPE-INHERITED   // stdin.
        pipe.PIPE-INHERITED   // stdout
        pipe.PIPE-INHERITED   // stderr
        command.first
        command
    child-process_ = fork-data[3]
    network_ = net.open
    client_ = http.Client network_

    url := "http://localhost:$port"

    MAX-ATTEMPTS := 20
    sleep-time := 100
    start-time := Time.now
    for i := 0; i < MAX-ATTEMPTS; i++:
      exception := catch --unwind=(: i == MAX-ATTEMPTS - 1):
        print "Attempting ($i) to contact the driver. ($((Duration.since start-time).in_s))s"
        with-timeout --ms=1_000:
          response := client_.get --uri="$url/status"
          if response.status-code != 200:
            throw "Failed to contact driver: $response.status-code."
        response := client_.post-json --uri="$url/session" {
          "capabilities": {
            "alwaysMatch": {:},
            "firstMatch": [
              {
                "browserName": "chrome",
                "goog:chromeOptions": {
                  "args": ["--disable-gpu", "--headless"]
                }
              },
              {
                "browserName": "safari"
              },
              {
                "browserName": "firefox",
                "moz:firefoxOptions": {
                  "args": ["-headless"]
                }
              },
              {
                "browserName": "MicrosoftEdge",
                "ms:edgeOptions": {
                  "args": ["--headless"]
                }
              },
            ],
          }
        }

        decoded := json.decode-stream response.body
        print "Decoded: $decoded"
        session-id := decoded["value"]["sessionId"]
        session-url_ = "$url/session/$session-id"

      if not exception: return
      if (Duration.since start-time).in-s >= 10:
        print "Failed to contact driver: $exception."
      // Probably hasn't started yet. Just try again.
      sleep --ms=sleep-time
      sleep-time *= 2
    print "Started"

  close:
    pid := child-process_
    if not pid: return
    // Delete the session.
    // This doesn't shut down the driver, but is good practice.
    request := client_.new-request http.DELETE --uri=session-url_
    request.send
    // Some drivers have a shutdown endpoint. It doesn't hurt to send it
    // to all drivers.
    client_.get --uri="$session-url_/shutdown"
    client_.close
    network_.close
    child-process_ = null
    if system.platform == system.PLATFORM-WINDOWS:
      // On Windows we only have kill 9.
      pipe.kill_ pid 9
    else:
      pipe.kill_ pid 15
    exception := catch --unwind=(: it != DEADLINE-EXCEEDED-ERROR):
      with-timeout --ms=3_000:
        pipe.wait-for pid
    if exception:
      pipe.kill_ pid 9

  post_ --url/string=session-url_ path/string payload/any -> any:
    response := client_.post-json --uri="$url/$path" payload
    result := json.decode-stream response.body
    response.drain
    return result

  get_ path/string -> any:
    response := client_.get --uri="$session-url_/$path"
    result := json.decode-stream response.body
    response.drain
    return result

  goto url/string:
    post_ "url" { "url": url }

  find css-selector/string -> List:
    response := post_ "element" { "using": "css selector", "value": css-selector }
    element-json := response["value"]
    if element-json.contains "error": return []
    if not element-json: return []
    return element-json.values

  get-text element-id/string -> string:
    response := get_ "element/$element-id/text"
    return response["value"]

  click element-id/string:
    post_ "element/$element-id/click" {:}
