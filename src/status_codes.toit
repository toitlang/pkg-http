
// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

STATUS_OK ::= 200

status_messages_/Map ::= {
  STATUS_OK: "OK",
}

status_message status_code/int -> string:
  return status_messages_.get status_code
    --if_absent=: ""
