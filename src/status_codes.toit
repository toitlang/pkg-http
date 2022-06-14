// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .method // For toitdoc.

/**
Status code for when the server switches protocols.

For example, the server sends this status code when it switches to websockets.
*/
STATUS_SWITCHING_PROTOCOLS ::= 101

/**
Status code for when the request succeeded.
*/
STATUS_OK ::= 200

/**
Status code for when a resource has moved permanently.

This might be used when a web site was reorganized.

Similar to $STATUS_PERMANENT_REDIRECT, except that the method is not guaranteed
  except for $GET.

For clients the simplest is to treat $STATUS_MOVED_PERMANENTLY the same as
  $STATUS_PERMANENT_REDIRECT.

# Advanced
If the method was $GET, then the redirected target must also be retrieved with $GET.
  For other methods, the server should not assume that the redirected target is again
  retrieved with the same method. The status code $STATUS_PERMANENT_REDIRECT specifies
  that the method must not be changed.
*/
STATUS_MOVED_PERMANENTLY /int ::= 301

/**
Status code when the target is temporarily unavailable.

For clients the simplest is to treat $STATUS_FOUND the same as
  $STATUS_TEMPORARY_REDIRECT.

# Advanced
If the method was $GET, then the redirected target must also be retrieved with $GET.
  For other methods, the server should not assume that the redirected target is again
  retrieved with the same method. The status code $STATUS_TEMPORARY_REDIRECT specifies
  that the method must not be changed.
*/
STATUS_FOUND /int ::= 302

/**
Status code when the client is redirected to a $GET target.

This is typically used to redirect after a $PUT or $POST, so that refreshing the
  result page doesn't resubmit data.
*/
STATUS_SEE_OTHER /int ::= 303

/**
Status code when the targe is temporarily unavailable.

The method ($GET, $POST, ...) must be the same when accessing the redirection target.
*/
STATUS_TEMPORARY_REDIRECT /int ::= 307

/**
Status code for when a resource has moved permanently.

This might be used when a web site was reorganized.

Search engine robots, RSS readers, and similar tools should update the original URL

The method ($GET, $POST, ...) must be the same when accessing the redirection target.
*/
STATUS_PERMANENT_REDIRECT /int ::= 308

status_messages_/Map ::= {
  STATUS_OK: "OK",
  STATUS_SWITCHING_PROTOCOLS: "Switching Protocols",
}

status_message status_code/int -> string:
  return status_messages_.get status_code
    --if_absent=: ""
