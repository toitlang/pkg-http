import certificate_roots
import encoding.json
import http
import net

SUPABASE_HOST ::= "fjdivzfiphllkyxczmgw.supabase.co"
ANON_ ::= "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZqZGl2emZpcGhsbGt5eGN6bWd3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE2NjQ5NTQxMjIsImV4cCI6MTk4MDUzMDEyMn0.ge4XAeh3xEHQokn-ayPKi1N0cQO_c8bhBzLli-I9bqU"

supabase_create_client network/net.Interface -> http.Client:
  return http.Client.tls network
      --root_certificates=[certificate_roots.BALTIMORE_CYBERTRUST_ROOT]

supabase_add_auth_headers headers/http.Headers:
  headers.add "apikey" ANON_
  headers.add "Authorization" "Bearer $ANON_"

supabase_create_headers -> http.Headers:
  headers := http.Headers
  supabase_add_auth_headers headers
  return headers

NOUNS ::= [
    "horse", "fish", "cat", "dog", "cow", "chicken", "duck", "goose", "swan",
    "goat", "ox", "bull", "rabbit", "guinea pig", "pallas cat", "lion",
    "tiger", "leopard", "cheetah", "jaguar", "puma", "lynx", "jungle cat",
    "wolf", "bear", "polar bear", "whale", "bigfoot", "deer", "badger",
    "honey badger", "pangolin", "anteater", "fox", "hamster", "gerbil",
    "cod", "salmon", "octopus",
]

ADJECTIVES ::= [
    "green", "blue", "brave", "shy", "white", "black", "grey", "red", "yellow",
    "magenta", "brown", "pink", "orange", "cyan", "purple", "enthusiastic",
    "tired", "lazy", "overwhelming", "underwhelming", "angry", "wooden", "rare",
    "endangered", "colourful", "iridescent", "shimmering", "livid", "depressed",
    "cromulent", "adequate", "super", "great", "fab", "awesome", "exaggerated",
    "overwhelming", "underwhelming", "huge", "large", "medium", "small", "tiny",
    "microscopic", "galactic", "universal", "rotten", "putrid", "smelly",
    "vicious", "obvious", "soft", "appalling", "transcendent",
]

random_text -> string:
  return "$ADJECTIVES[random ADJECTIVES.size] $NOUNS[random NOUNS.size]"

main args:
  network := net.open

  if args[0] == "add":
    add_line network
  if args[0] == "list":
    get network
  if args[0] == "monitor":
    monitor_updates network

get network -> none:
  client := supabase_create_client network
  headers := supabase_create_headers
  response := client.get --uri="https://$SUPABASE_HOST/rest/v1/realtimetesting" --headers=headers
  print response
  reader := response.body
  while data2 := reader.read:
    print data2.to_string

monitor_updates network -> none:
  client := supabase_create_client network
  web_socket := client.web_socket --uri="wss://$SUPABASE_HOST/realtime/v1/websocket?vsn=1.0.0&apikey=$ANON_"
  print "Connected to Supabase"
  counter := 0
  task::
    while true:
      print "Sending heartbeat $counter"
      web_socket.send
          json.encode {"topic": "phoenix", "event": "heartbeat", "payload": {:}, "ref": counter++}
      sleep --ms=10_000

  sleep --ms=1000
  web_socket.send
      json.encode {"topic": "room:realtimetesting", "event": "phx_join", "payload": {:}, "ref": counter++}

  while data := web_socket.receive:
    print data

add_line network -> none:
  client := supabase_create_client network
  data := json.encode {"foo": random_text}
  print data.to_string
  headers := supabase_create_headers
  response := client.post data --uri="https://$SUPABASE_HOST/rest/v1/realtimetesting" --headers=headers
  print response
  reader := response.body
  while data2 := reader.read:
    print data2.to_string
