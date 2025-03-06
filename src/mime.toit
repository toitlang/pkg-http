// Copyright (C) 2025 Toit contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Common mime types.

From https://developer.mozilla.org/en-US/docs/Web/HTTP/MIME_types/Common_types.
*/
COMMON-MIME-TYPES ::= {
  "aac": "audio/aac",  // AAC audio.
  "abw": "application/x-abiword",  // AbiWord document.
  "apng": "image/apng",  // Animated Portable Network Graphics (APNG) image.
  "arc": "application/x-freearc",  // Archive document (multiple files embedded).
  "avif": "image/avif",  // AVIF image.
  "avi": "video/x-msvideo",  // AVI: Audio Video Interleave.
  "azw": "application/vnd.amazon.ebook",  // Amazon Kindle eBook format.
  "bin": "application/octet-stream",  // Any kind of binary data.
  "bmp": "image/bmp",  // Windows OS/2 Bitmap Graphics.
  "bz": "application/x-bzip",  // BZip archive.
  "bz2": "application/x-bzip2",  // BZip2 archive.
  "cda": "application/x-cdf",  // CD audio.
  "csh": "application/x-csh",  // C-Shell script.
  "css": "text/css",  // Cascading Style Sheets (CSS).
  "csv": "text/csv",  // Comma-separated values (CSV).
  "doc": "application/msword",  // Microsoft Word.
  "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",  // Microsoft Word (OpenXML).
  "eot": "application/vnd.ms-fontobject",  // MS Embedded OpenType fonts.
  "epub": "application/epub+zip",  // Electronic publication (EPUB).
  "gz": "application/gzip",  // GZip Compressed Archive.
  "gif": "image/gif",  // Graphics Interchange Format (GIF).
  "htm": "text/html",  // HyperText Markup Language (HTML).
  "html": "text/html",  // HyperText Markup Language (HTML).
  "ico": "image/vnd.microsoft.icon",  // Icon format.
  "ics": "text/calendar",  // iCalendar format.
  "jar": "application/java-archive",  // Java Archive (JAR).
  "jpeg": "image/jpeg",  // JPEG images.
  "jpg": "image/jpeg",  // JPEG images.
  "js": "text/javascript",  // JavaScript.
  "json": "application/json",  // JSON format.
  "jsonld": "application/ld+json",  // JSON-LD format.
  "mid": "audio/midi",  // Musical Instrument Digital Interface (MIDI).
  "midi": "audio/midi",  // Musical Instrument Digital Interface (MIDI).
  "mjs": "text/javascript",  // JavaScript module.
  "mp3": "audio/mpeg",  // MP3 audio.
  "mp4": "video/mp4",  // MP4 video.
  "mpeg": "video/mpeg",  // MPEG Video.
  "mpkg": "application/vnd.apple.installer+xml",  // Apple Installer Package.
  "odp": "application/vnd.oasis.opendocument.presentation",  // OpenDocument presentation document.
  "ods": "application/vnd.oasis.opendocument.spreadsheet",  // OpenDocument spreadsheet document.
  "odt": "application/vnd.oasis.opendocument.text",  // OpenDocument text document.
  "oga": "audio/ogg",  // Ogg audio.
  "ogv": "video/ogg",  // Ogg video.
  "ogx": "application/ogg",  // Ogg.
  "opus": "audio/ogg",  // Opus audio in Ogg container.
  "otf": "font/otf",  // OpenType font.
  "png": "image/png",  // Portable Network Graphics.
  "pdf": "application/pdf",  // Adobe Portable Document Format (PDF).
  "php": "application/x-httpd-php",  // Hypertext Preprocessor (Personal Home Page).
  "ppt": "application/vnd.ms-powerpoint",  // Microsoft PowerPoint.
  "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",  // Microsoft PowerPoint (OpenXML).
  "rar": "application/vnd.rar",  // RAR archive.
  "rtf": "application/rtf",  // Rich Text Format (RTF).
  "sh": "application/x-sh",  // Bourne shell script.
  "svg": "image/svg+xml",  // Scalable Vector Graphics (SVG).
  "tar": "application/x-tar",  // Tape Archive (TAR).
  "tif": "image/tiff",  // Tagged Image File Format (TIFF).
  "tiff": "image/tiff",  // Tagged Image File Format (TIFF).
  "ts": "video/mp2t",  // MPEG transport stream.
  "ttf": "font/ttf",  // TrueType Font.
  "txt": "text/plain",  // Text, (generally ASCII or ISO 8859-n).
  "vsd": "application/vnd.visio",  // Microsoft Visio.
  "wav": "audio/wav",  // Waveform Audio Format.
  "weba": "audio/webm",  // WEBM audio.
  "webm": "video/webm",  // WEBM video.
  "webp": "image/webp",  // WEBP image.
  "woff": "font/woff",  // Web Open Font Format (WOFF).
  "woff2": "font/woff2",  // Web Open Font Format (WOFF).
  "xhtml": "application/xhtml+xml",  // XHTML.
  "xls": "application/vnd.ms-excel",  // Microsoft Excel.
  "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",  // Microsoft Excel (OpenXML).
  "xml": "application/xml",  // XML.
  "xul": "application/vnd.mozilla.xul+xml",  // XUL.
  "zip": "application/zip",  // ZIP archive.
  "3gp": "video/3gpp",  // 3GPP audio/video container.
  "3g2": "video/3gpp2",  // 3GPP2 audio/video container.
  "7z": "application/x-7z-compressed",  // 7-zip archive.
}

get-extension_ path/string -> string:
  // Get the file extension from a path.
  last-dot := path.index-of --last "."
  if last-dot == -1:
    return ""
  return path[last-dot + 1..]

/**
Returns the content type for a file based on its extension.

Returns "application/octet-stream" if the extension is unknown.
See $COMMON-MIME-TYPES for a list of known extensions.
*/
content-type --path/string -> string:
  // Get the content type for a file based on its extension.
  extension := get-extension_ path
  return (COMMON-MIME-TYPES.get extension) or "application/octet-stream"
