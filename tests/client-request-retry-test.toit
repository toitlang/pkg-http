// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import monitor
import net

READ-TIMEOUT ::= Duration --ms=20
WAIT-FOR-CLOSE ::= Duration --ms=200

PUT-DATA ::= "put payload".to-byte-array
POST-DATA ::= "post payload".to-byte-array

main:
  network := net.open
  server-socket := network.tcp-listen 0
  port := server-socket.local-address.port
  server := http.Server --read-timeout=READ-TIMEOUT
  server-done := monitor.Latch
  received-methods := []

  task::
    try:
      server.listen server-socket:: | request/http.RequestIncoming writer/http.ResponseWriter |
        if request.path == "/warm-up":
          writer.out.write "ready"
        else:
          expect-equals "/upload" request.query.resource
          expect-equals "yes" (request.headers.single "X-Test")
          expect-equals "application/octet-stream" (request.headers.single "Content-Type")
          received-methods.add request.method

          body := request.body.read-all
          if request.method == http.PUT:
            expect-equals "put" request.query.parameters["kind"]
            expect-equals PUT-DATA body
          else:
            expect-equals http.POST request.method
            expect-equals "post" request.query.parameters["kind"]
            expect-equals POST-DATA body
          writer.out.write body
    finally:
      server-done.set true

  client := http.Client network
  headers := http.Headers
  headers.set "X-Test" "yes"
  try:
    warm-up client port
    wait-until-server-closes-idle-connection

    response := client.request http.PUT PUT-DATA
        --host="localhost"
        --port=port
        --path="/upload"
        --query-parameters={"kind": "put"}
        --headers=headers
        --content-type="application/octet-stream"
    expect-equals 200 response.status-code
    expect-equals PUT-DATA response.body.read-all

    warm-up client port
    wait-until-server-closes-idle-connection

    // POST isn't idempotent by definition, so it isn't retried without an
    // explicit opt-in.
    exception := catch:
      client.request http.POST POST-DATA
          --uri="http://localhost:$port/upload?kind=post"
          --headers=headers
          --content-type="application/octet-stream"
    expect-not-null exception
    expect-equals [http.PUT] received-methods

    warm-up client port
    wait-until-server-closes-idle-connection

    exception = catch:
      client.post POST-DATA
          --uri="http://localhost:$port/upload?kind=post"
          --headers=headers
          --content-type="application/octet-stream"
    expect-not-null exception

    warm-up client port
    wait-until-server-closes-idle-connection

    exception = catch:
      client.post-json {"value": 1}
          --uri="http://localhost:$port/upload?kind=post"
          --headers=headers
    expect-not-null exception

    warm-up client port
    wait-until-server-closes-idle-connection

    exception = catch:
      client.post-form {"value": "1"}
          --uri="http://localhost:$port/upload?kind=post"
          --headers=headers
    expect-not-null exception
    expect-equals [http.PUT] received-methods

    warm-up client port
    wait-until-server-closes-idle-connection

    response = client.request http.POST POST-DATA
        --uri="http://localhost:$port/upload?kind=post"
        --headers=headers
        --content-type="application/octet-stream"
        --retry-on-connection-close
    expect-equals 200 response.status-code
    expect-equals POST-DATA response.body.read-all

    expect-equals [http.PUT, http.POST] received-methods
  finally:
    client.close
    server.close
    server-socket.close
    server-done.get
    network.close

warm-up client/http.Client port/int:
  response := client.get --host="localhost" --port=port --path="/warm-up"
  expect-equals 200 response.status-code
  expect-equals "ready" response.body.read-all.to-string

wait-until-server-closes-idle-connection:
  // Leave enough margin that the server has closed its side of the cached
  // connection before the client attempts to reuse it.
  sleep WAIT-FOR-CLOSE
