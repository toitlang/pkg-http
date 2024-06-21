// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io

class Headers:
  headers_/Map? := null

  constructor:

  constructor.from-map map/Map:
    map.do: | key/string value |
      if value is string:
        // Go through the $add function so that the key is normalized.
        add key value
      else if value is List:
        list := value as List
        // Go through the $add function so that the key is normalized.
        list.do: add key it
      else:
        throw "INVALID_HEADER_VALUE"

  constructor.private_ .headers_:

  /**
  The keys of the header.
  */
  keys -> List:
    if not headers_: return []
    return headers_.keys

  /**
  Returns a single string value for the header or null if the header is not
    present.  If there are multiple values, the last value is returned.
  */
  single key -> string?:
    if not headers_: return null
    values := headers_.get key --if-absent=:
      key = ascii-normalize_ key
      headers_.get key --if-absent=:
        return null
    if values is string: return values
    return values[values.size - 1]

  /**
  Does ASCII case independent match of whether a key has a value.
  */
  matches key/string value/string -> bool:
    from-headers := single key
    if not from-headers: return false
    return from-headers == value or (ascii-normalize_ from-headers) == (ascii-normalize_ value)

  /**
  Does ASCII case independent match of whether a header value starts with a prefix.
  Returns false if the header is not present.  Only checks the last header if there are
    several of the same name.
  */
  starts-with key/string prefix/string -> bool:
    from-headers := single key
    if not from-headers: return false
    return from-headers.starts-with prefix or (ascii-normalize_ from-headers).starts-with (ascii-normalize_ prefix)

  /**
  Removes the given header.

  Does nothing if the $key doesn't exist.
  */
  remove key/string -> none:
    if not headers_: return
    headers_.remove key

  /**
  Returns the stored values for the given $key.

  Do not modify the return value.

  Returns null if the header is not present.
  */
  get key/string -> List?:
    if not headers_: return null
    value := headers_.get key --if-absent=:
      key = ascii-normalize_ key
      headers_.get key --if-absent=:
        return null
    if value is string:
      // Make it in to a one-element list in case the caller wants to modify
      // the list and to save time in case this method is called again.
      value = [value]
      headers_[key] = value
    return value

  /**
  Sets the $key to the given $value.

  If this instance had another (one or more) values for this $key, then
    the old values are discarded.
  */
  set key/string value/string -> none:
    if not headers_: headers_ = {:}
    headers_[ascii-normalize_ key] = value

  /**
  Adds a new $value to the $key.

  A key can have multiple values and this function simply adds the new
    value to the list.
  */
  add key/string value/string -> none:
    key = ascii-normalize_ key
    if not headers_: headers_ = {:}
    headers_.update key --if-absent=(: value): | old |
      if old is string:
        [old, value]
      else:
        old.add value
        old

  /** Whether this instance contains the given $key. */
  contains key/string -> bool:
    if not headers_: return false
    if headers_.contains key: return true
    key = ascii-normalize_ key
    return headers_.contains key

  write-to writer -> none:
    if not headers_: return
    headers_.do: | key values |
      block := : | value |
        writer.write key
        writer.write ": "
        writer.write value
        writer.write "\r\n"
      if values is string:
        block.call values
      else:
        values.do block

  stringify -> string:
    buffer := io.Buffer
    write-to buffer
    return buffer.to-string

  /**
  Creates a copy of this instance.
  */
  copy -> Headers:
    if not headers_: return Headers
    result := {:}
    headers_.do: | key values |
      if values is string:
        result[key] = values
      else:
        if values.size == 1:
          result[key] = values[0]
        else:
          result[key] = values.copy
    return Headers.private_ result

  // Camel-case a string.  Only works for ASCII in accordance with the HTTP
  // standard.  If the string is already camel cased (the norm) then no
  // allocation occurs.
  static ascii-normalize_ str/string -> string:
    alpha := false  // Was the previous character an alphabetic (ASCII) letter.
    bytes/ByteArray? := null  // Allocate byte array later if needed.
    str.size.repeat:
      char := str.at --raw it
      problem := alpha ? (is-ascii-upper-case_ char) : (is-ascii-lower-case_ char)
      if problem and not bytes:
        bytes = ByteArray str.size
        str[..it].write-to-byte-array bytes
      if bytes:
        bytes[it] = problem ? (char ^ 32) : char
      alpha = is-ascii-alpha_ char
    if not bytes: return str
    return bytes.to-string

  static is-ascii-upper-case_ char/int -> bool:
    return 'A' <= char <= 'Z'

  static is-ascii-lower-case_ char/int -> bool:
    return 'a' <= char <= 'z'

  static is-ascii-alpha_ char/int -> bool:
    return is-ascii-lower-case_ char or is-ascii-upper-case_ char
