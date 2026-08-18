// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

// A client that connects, sends a request and closes before the server
// writes the response must be treated as a normal disconnect: the server
// keeps serving and doesn't log any extraneous traces. The only acceptable
// trace is the one the server emits when the handler lets the socket error
// itself escape.

import expect show *
import http
import monitor
import net
import system.api.trace show TraceService
import system.services show ServiceProvider ServiceHandler

class TraceRecorder extends ServiceProvider implements ServiceHandler:
  traces/List := []

  constructor:
    super "test/trace" --major=1 --minor=0
    provides TraceService.SELECTOR --handler=this

  handle index/int arguments/any --gid/int --client/int -> any:
    if index == TraceService.HANDLE-TRACE-INDEX:
      traces.add arguments
      // Print traces to stdout as well.
      return arguments
    unreachable

// Test scenarios:
// Exception escapes the handler, expect one trace to be displayed.
PROPAGATE ::= "propagate"
// Handler swallows exception and calls close.
CATCH-CLOSE ::= "catch-close"
// Handler swallows exception and tries to send a 500.
CATCH-500 ::= "catch-500"

main:
  recorder := TraceRecorder
  recorder.install
  failures := []
  try:
    [1, 4].do: | max-tasks/int |
      [PROPAGATE, CATCH-CLOSE, CATCH-500].do: | scenario/string |
        print "---------------------------------------"
        print "scenario=$scenario max-tasks=$max-tasks"
        print "---------------------------------------"
        recorder.traces.clear
        test --max-tasks=max-tasks --scenario=scenario
        traces_seen := recorder.traces.size
        allowed := scenario == PROPAGATE ? 1 : 0
        if traces_seen != allowed:
          failures.add "$scenario/max-tasks=$max-tasks ($traces_seen != $allowed)"
  finally:
    recorder.uninstall
  expect failures.is-empty --message="$failures"

test --max-tasks/int --scenario/string:
  network := net.open
  listen-socket := network.tcp-listen 0
  port := listen-socket.local-address.port
  server := http.Server --max-tasks=max-tasks
  client-closed := monitor.Latch
  slow-handled := monitor.Latch
  done := monitor.Latch

  task::
    server.listen listen-socket:: | request/http.Request writer/http.ResponseWriter |
      if request.path == "/slow":
        try:
          client-closed.get  // Peer is gone by now.
          if scenario == PROPAGATE:
            writer.out.write "hello"
          else:
            catch: writer.out.write "hello"
            if scenario == CATCH-500:
              catch: writer.write-headers http.STATUS-INTERNAL-SERVER-ERROR
        finally:
          slow-handled.set true
      else:
        writer.out.write "ok"
      writer.close
    done.set true

  socket := network.tcp-connect "localhost" port
  socket.out.write "GET /slow HTTP/1.1\r\nHost: localhost\r\n\r\n"
  socket.close  // FIN before the response is written.
  client-closed.set true
  slow-handled.get

  // The server must still work.
  client := http.Client network
  response := client.get --uri="http://localhost:$port/fast"
  expect-equals 200 response.status-code
  expect-equals "ok" response.body.read-all.to-string
  client.close

  server.close
  listen-socket.close
  done.get
  // Connection tasks are background tasks; wait for them to finish (they
  // trace before decrementing the count) so the caller can count traces.
  with-timeout --ms=2000:
    server.signal_.wait: server.task-count_ == 0
  network.close
