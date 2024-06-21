// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import http
import expect show *

main:
  parts := http.ParsedUri_.parse_ "https://www.youtube.com/watch?v=2HJxya0CWco#t=0m6s"
  expect-equals "https"                parts.scheme
  expect-equals "www.youtube.com"      parts.host
  expect-equals 443                    parts.port
  expect-equals "/watch?v=2HJxya0CWco" parts.path
  expect-equals "t=0m6s"               parts.fragment

  parts = http.ParsedUri_.parse_ "https://www.youtube.com/watch?v=2HJxya0CWco"
  expect-equals "https"                parts.scheme
  expect-equals "www.youtube.com"      parts.host
  expect-equals 443                    parts.port
  expect-equals "/watch?v=2HJxya0CWco" parts.path

  parts = http.ParsedUri_.parse_ "https://www.youtube.com:443/watch?v=2:HJxya0CWco"
  expect-equals "https"                 parts.scheme
  expect-equals "www.youtube.com"       parts.host
  expect-equals 443                     parts.port
  expect-equals "/watch?v=2:HJxya0CWco" parts.path

  YT ::= "www.youtube.com:443/watch/?v=10&encoding=json"
  parts = http.ParsedUri_.parse_ "https://$YT"
  expect-equals "https"                 parts.scheme
  expect-equals "www.youtube.com"       parts.host
  expect-equals 443                     parts.port
  expect-equals "/watch/?v=10&encoding=json" parts.path

  expect-throw "Missing scheme in '$YT'": http.ParsedUri_.parse_ YT
  expect-throw "Missing scheme in '/$YT'": http.ParsedUri_.parse_ "/$YT"
  expect-throw "Missing scheme in '//$YT'": http.ParsedUri_.parse_ "//$YT"
  expect-throw "Missing scheme in 'http/$YT'": http.ParsedUri_.parse_ "http/$YT"

  expect-throw "Missing scheme in '192.168.86.26:55321/auth'":
    http.ParsedUri_.parse_ "192.168.86.26:55321/auth"

  http.ParsedUri_.parse_                                   "https://www.youtube.com/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://www.youtube.com-/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://www.youtube.-com/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://www.youtube-.com/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://www.-youtube.com/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://www-.youtube.com/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://-www.youtube.com/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://.www.youtube.com/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://www..youtube.com/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://www..y'utube.com/watch?v=2HJxya0CWco"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "https://www..yøutube.com/watch?v=2HJxya0CWco"

  expect-throw "Unknown scheme: 'fisk'": http.ParsedUri_.parse_ "fisk://fishing.net/"
  expect-throw "Missing scheme in '/a/relative/url'": http.ParsedUri_.parse_ "/a/relative/url"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "http:/127.0.0.1/path"
  expect-throw "URI_PARSING_ERROR": http.ParsedUri_.parse_ "http:127.0.0.1/path"

  parts = http.ParsedUri_.parse_ "wss://api.example.com./end-point"
  expect-equals "wss"               parts.scheme
  expect-equals "api.example.com."  parts.host
  expect-equals 443                 parts.port
  expect-equals "/end-point"        parts.path
  expect-equals null                parts.fragment
  expect                            parts.use-tls

  parts = http.ParsedUri_.parse_ "WSS://api.example.com./end-point"
  expect-equals "wss"               parts.scheme
  parts = http.ParsedUri_.parse_ "htTPs://api.example.com./end-point"
  expect-equals "https"               parts.scheme

  parts = http.ParsedUri_.parse_ "www.yahoo.com" --default-scheme="https"
  expect-equals "https"         parts.scheme
  expect-equals "www.yahoo.com" parts.host
  expect-equals 443             parts.port
  expect-equals "/"             parts.path
  expect-equals null            parts.fragment
  expect                        parts.use-tls

  parts = http.ParsedUri_.parse_ "localhost:1080" --default-scheme="https"
  expect-equals "https"     parts.scheme
  expect-equals "localhost" parts.host
  expect-equals 1080        parts.port
  expect-equals "/"         parts.path
  expect-equals null        parts.fragment
  expect                    parts.use-tls

  parts = http.ParsedUri_.parse_ "http:1080"
  expect-equals "http"      parts.scheme
  expect-equals "1080"      parts.host
  expect-equals "/"         parts.path
  expect-equals null        parts.fragment

  parts = http.ParsedUri_.parse_ "HTTP:1080"
  expect-equals "http"      parts.scheme
  expect-equals "1080"      parts.host
  expect-equals "/"         parts.path
  expect-equals null        parts.fragment

  parts = http.ParsedUri_.parse_ "127.0.0.1:1080" --default-scheme="https"
  expect-equals "https"     parts.scheme
  expect-equals "127.0.0.1" parts.host
  expect-equals 1080        parts.port
  expect-equals "/"         parts.path
  expect-equals null        parts.fragment
  expect                    parts.use-tls

  parts = http.ParsedUri_.parse_ "http://localhost:1080/"
  expect-equals "http"      parts.scheme
  expect-equals "localhost" parts.host
  expect-equals 1080        parts.port
  expect-equals "/"         parts.path
  expect-equals null        parts.fragment
  expect-not                parts.use-tls

  parts = http.ParsedUri_.parse_ "http://localhost:1080/#"
  expect-equals "http"      parts.scheme
  expect-equals "localhost" parts.host
  expect-equals 1080        parts.port
  expect-equals "/"         parts.path
  expect-equals ""          parts.fragment
  expect-not                parts.use-tls

  parts = http.ParsedUri_.parse_ "http://localhost:1080/#x"
  expect-equals "http"      parts.scheme
  expect-equals "localhost" parts.host
  expect-equals 1080        parts.port
  expect-equals "/"         parts.path
  expect-equals "x"         parts.fragment
  expect-not                parts.use-tls

  parts = http.ParsedUri_.parse_ "ws://xn--us--um5a.com/schneemann"
  expect-equals "ws"               parts.scheme
  expect-equals "xn--us--um5a.com" parts.host
  expect-equals 80                 parts.port
  expect-equals "/schneemann"      parts.path
  expect-equals null               parts.fragment
  expect-not                       parts.use-tls

  parts = http.ParsedUri_.parse_ "//127.0.0.1/path" --default-scheme="https"
  expect-equals "https"            parts.scheme
  expect-equals "127.0.0.1"        parts.host
  expect-equals 443                parts.port
  expect-equals "/path"            parts.path
  expect-equals null               parts.fragment
  expect                           parts.use-tls

  parts = http.ParsedUri_.parse_ "http://127.0.0.1/path"
  expect-equals "http"             parts.scheme
  expect-equals "127.0.0.1"        parts.host
  expect-equals 80                 parts.port
  expect-equals "/path"            parts.path
  expect-equals null               parts.fragment
  expect-not                       parts.use-tls

  parts = http.ParsedUri_.parse_ "https://original.com/foo/#fraggy"
  expect-equals "https"            parts.scheme
  expect-equals "original.com"     parts.host
  expect-equals 443                parts.port
  expect-equals "/foo/"            parts.path
  expect-equals "fraggy"           parts.fragment
  expect                           parts.use-tls

  parts2 := http.ParsedUri_.parse_ --previous=parts "http://redirect.com/bar"
  expect-equals "http"             parts2.scheme  // Changed in accordance with redirect.
  expect-equals "redirect.com"     parts2.host
  expect-equals 80                 parts2.port
  expect-equals "/bar"             parts2.path
  expect-equals "fraggy"           parts2.fragment  // Kept from original non-redirected URI.
  expect-not                       parts2.use-tls

  parts2 = http.ParsedUri_.parse_ --previous=parts "/bar#fragment"
  expect-equals "https"            parts2.scheme
  expect-equals "original.com"     parts2.host
  expect-equals 443                parts2.port
  expect-equals "/bar"             parts2.path
  expect-equals "fragment"         parts2.fragment  // Kept from original non-redirected URI.
  expect                           parts2.use-tls

  parts2 = http.ParsedUri_.parse_ --previous=parts "bar#fraggles"
  expect-equals "https"            parts2.scheme
  expect-equals "original.com"     parts2.host
  expect-equals 443                parts2.port
  expect-equals "/foo/bar"         parts2.path      // composed of original path and relative path.
  expect-equals "fraggles"         parts2.fragment  // Kept from original non-redirected URI.
  expect                           parts2.use-tls

  parts = http.ParsedUri_.parse_ "https://original.com"  // No path - we should add a slash.
  expect-equals "https"            parts.scheme
  expect-equals "original.com"     parts.host
  expect-equals 443                parts.port
  expect-equals "/"                parts.path      // Slash was implied.
  expect-equals null               parts.fragment
  expect                           parts.use-tls

  parts = http.ParsedUri_.parse_ "https://original.com/foo/?value=/../"  // Query part.
  expect-equals "https"            parts.scheme
  expect-equals "original.com"     parts.host
  expect-equals 443                parts.port
  expect-equals "/foo/?value=/../" parts.path
  expect-equals null               parts.fragment
  expect                           parts.use-tls

  parts2 = http.ParsedUri_.parse_ --previous=parts "bar?value=dotdot#fraggles"
  expect-equals "https"            parts2.scheme
  expect-equals "original.com"     parts2.host
  expect-equals 443                parts2.port
  expect-equals "/foo/bar?value=dotdot" parts2.path  // Joined, the old query is not used.
  expect-equals "fraggles"         parts2.fragment
  expect                           parts2.use-tls

  // Can't redirect an HTTP connection to a WebSockets connection.
  expect-throw "INVALID_REDIRECT": parts = http.ParsedUri_.parse_ --previous=parts "wss://socket.redirect.com/api"

  parts = http.ParsedUri_.parse_ "https://[::]/foo#fraggy"
  expect-equals "https"            parts.scheme
  expect-equals "::"               parts.host
  expect-equals 443                parts.port
  expect-equals "/foo"             parts.path
  expect-equals "fraggy"           parts.fragment
  expect                           parts.use-tls

  parts = http.ParsedUri_.parse_ "https://[1234::7890]/foo#fraggy"
  expect-equals "https"            parts.scheme
  expect-equals "1234::7890"       parts.host
  expect-equals 443                parts.port
  expect-equals "/foo"             parts.path
  expect-equals "fraggy"           parts.fragment
  expect                           parts.use-tls

  parts = http.ParsedUri_.parse_ "https://[::]:80/foo#fraggy"
  expect-equals "https"            parts.scheme
  expect-equals "::"               parts.host
  expect-equals 80                 parts.port
  expect-equals "/foo"             parts.path
  expect-equals "fraggy"           parts.fragment
  expect                           parts.use-tls

  expect-throw "URI_PARSING_ERROR": parts = http.ParsedUri_.parse_ "https://[::] :80/foo#fraggy"
  expect-throw "URI_PARSING_ERROR": parts = http.ParsedUri_.parse_ "https://[::/foo#fraggy"
  expect-throw "ILLEGAL_HOSTNAME": parts = http.ParsedUri_.parse_ "https://1234::5678/foo#fraggy"
  expect-throw "ILLEGAL_HOSTNAME": parts = http.ParsedUri_.parse_ "https://[www.apple.com]/foo#fraggy"
  expect-throw "ILLEGAL_HOSTNAME": parts = http.ParsedUri_.parse_ "https://[www.apple.com]:80/foo#fraggy"
  expect-throw "ILLEGAL_HOSTNAME": parts = http.ParsedUri_.parse_ "https:// [::]:80/foo#fraggy"
  expect-throw "INTEGER_PARSING_ERROR": parts = http.ParsedUri_.parse_ "https:// [::]/foo#fraggy"

  expect-equals "/foo.txt"
      http.ParsedUri_.merge-paths_ "/" "foo.txt"
  expect-equals "/foo.txt"
      http.ParsedUri_.merge-paths_ "/" "./foo.txt"
  expect-equals "/foo.txt"
      http.ParsedUri_.merge-paths_ "/bar.jpg" "foo.txt"
  expect-equals "/bar/foo.txt"
      http.ParsedUri_.merge-paths_ "/bar/" "foo.txt"
  expect-equals "/bar/foo.txt"
      http.ParsedUri_.merge-paths_ "/bar/sdlkfjsdl.sdlkf" "foo.txt"
  expect-equals "/bar/foo.txt"
      http.ParsedUri_.merge-paths_ "/bar/" "./foo.txt"
  expect-equals "/foo.txt"
      http.ParsedUri_.merge-paths_ "/bar/" "../foo.txt"
  expect-equals "/foo.txt"
      http.ParsedUri_.merge-paths_ "/bar/super-duper.jpg" "../foo.txt"
  expect-equals "/foo.txt"
      http.ParsedUri_.merge-paths_ "/bar/super-duper.jpg" "./.././foo.txt"
  expect-equals "/"
      http.ParsedUri_.merge-paths_ "/bar/" ".."
  expect-throw "ILLEGAL_PATH":
      http.ParsedUri_.merge-paths_ "/" "../foo.txt"
  expect-throw "ILLEGAL_PATH":
      http.ParsedUri_.merge-paths_ "/" "../../foo.txt"
  expect-throw "ILLEGAL_PATH":
      http.ParsedUri_.merge-paths_ "/bar/" "../../foo.txt"
  expect-throw "ILLEGAL_PATH":
      http.ParsedUri_.merge-paths_ "/bar/" "./../../foo.txt"
