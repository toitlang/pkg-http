// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import bytes

class Headers:
  headers_ := Map

  /**
  Returns a single string value for the header or null if the header is not
    present.  If there are multiple values, the last value is returned.
  */
  single key -> string?:
    key = ascii_normalize_ key
    if not headers_.contains key: return null
    values := headers_[key]
    return values[values.size - 1]

  /**
  Does ASCII case independent match of whether a key has a value.
  */
  matches key/string value/string -> bool:
    from_headers := single key
    if not from_headers: return false
    return from_headers == value or (ascii_normalize_ from_headers) == (ascii_normalize_ value)

  /**
  Does ASCII case independent match of whether a header value starts with a prefix.
  Returns false if the header is not present.  Only checks the last header if there are
    several of the same name.
  */
  starts_with key/string prefix/string -> bool:
    from_headers := single key
    if not from_headers: return false
    return from_headers.starts_with prefix or (ascii_normalize_ from_headers).starts_with (ascii_normalize_ prefix)

  /**
  Removes the given header.

  Does nothing if the $key doesn't exist.
  */
  remove key/string -> none:
    headers_.remove key

  /**
  Returns the stored values for the given $key.

  Returns null if the header is not present.
  */
  get key/string -> List?:
    return headers_.get (ascii_normalize_ key)

  /**
  Sets the $key to the given $value.

  If this instance had another (one or more) values for this $key, then
    the old values are discarded.
  */
  set key/string value/string -> none:
    headers_[ascii_normalize_ key] = [value]

  /**
  Adds a new $value to the $key.

  A key can have multiple values and this function simply adds the new
    value to the list.
  */
  add key/string value/string -> none:
    key = ascii_normalize_ key
    headers_.get key
      --if_present=: it.add value
      --if_absent=:  headers_[key] = [value]

  write_to writer -> none:
    headers_.do: | key values |
      values.do: | value |
        writer.write key
        writer.write ": "
        writer.write value
        writer.write "\r\n"

  stringify -> string:
    buffer := bytes.Buffer
    write_to buffer
    return buffer.to_string

  /**
  Creates a copy of this instance.
  */
  copy -> Headers:
    result := Headers
    headers_.do: | key values/List |
      copied := List values.size: values[it]
      result.headers_[key] = copied
    return result

  // Camel-case a string.  Only works for ASCII in accordance with the HTTP
  // standard.  If the string is already camel cased (the norm) then no
  // allocation occurs.
  ascii_normalize_ str:
    alpha := false  // Was the previous character an alphabetic (ASCII) letter.
    bytes/ByteArray? := null  // Allocate byte array later if needed.
    str.size.repeat:
      char := str.at --raw it
      problem := alpha ? (is_ascii_upper_case_ char) : (is_ascii_lower_case_ char)
      if problem and not bytes:
        bytes = ByteArray str.size
        str.write_to_byte_array bytes 0 it 0
      if bytes:
        bytes[it] = problem ? (char ^ 32) : char
      alpha = is_ascii_alpha_ char
    if not bytes: return str
    return bytes.to_string

  is_ascii_upper_case_ char:
    return 'A' <= char <= 'Z'

  is_ascii_lower_case_ char:
    return 'a' <= char <= 'z'

  is_ascii_alpha_ char:
    return is_ascii_lower_case_ char or is_ascii_upper_case_ char
