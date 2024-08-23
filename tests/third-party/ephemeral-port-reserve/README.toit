Name: Ephemeral Port Reserve
URL: https://github.com/Yelp/ephemeral-port-reserve
Copy: https://github.com/toitware/ephemeral-port-reserve
Revision: 6cf5addc2f1d5c0a25be4ba4af62104da1d8fc51
Date: 2024-08-22
License: MIT

Description:
A utility to bind to an ephemeral port, force it into the TIME_WAIT state, and unbind it.

This means that further ephemeral port alloctions won't pick this "reserved" port, but
subprocesses can still bind to it explicitly, given that they use SO_REUSEADDR. By
default on linux you have a grace period of 60 seconds to reuse this port.

Changes:
No changes except to remove unnecessary files.
