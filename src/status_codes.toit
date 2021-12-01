

STATUS_OK ::= 200

status_messages_/Map ::= {
  STATUS_OK: "OK",
}

status_message status_code/int -> string:
  return status_messages_.get status_code
    --if_absent=: ""
