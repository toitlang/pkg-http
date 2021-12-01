import http
import encoding.json
import net

ITEMS := ["FOO", "BAR", "BAZ"]

main:
  network := net.open
  server := http.Server network
  server.listen 8080:: | request/http.Request writer/http.ResponseWriter |
    ITEMS.do:
      writer.write
        json.encode {
          "item": it,
        }
      writer.write "\n"
