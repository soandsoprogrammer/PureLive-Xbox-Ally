# PureLive bounded asynchronous property reads

The pinned fork retains its MIT license. NativePlayer.getPropertyAsync uses
mpv_get_property_async and copies MPV_EVENT_GET_PROPERTY_REPLY data before the
next event. Unavailable values return an empty string; other errors retain the
native numeric code. A one-second default timeout retires the Dart completer;
late replies are ignored and player disposal rejects pending reads. Diagnostic
read errors do not also enter the playback error stream. The original
getProperty API remains available to upstream callers.

PureLive MpvEngine uses this API for buffering diagnostics, frame-rate probes
and read-only playback statistics. Its property writes use the fork's existing
setPropertyAsync after initialization, keeping control waits off the UI isolate.
Reference: https://github.com/mpv-player/mpv/blob/master/include/mpv/client.h
