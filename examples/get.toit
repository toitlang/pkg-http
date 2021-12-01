import http
import net

main:
  network := net.open
  client := http.Client network

  response := client.get "localhost:8080" "/"
  while data := response.read:
    print data.to_string
