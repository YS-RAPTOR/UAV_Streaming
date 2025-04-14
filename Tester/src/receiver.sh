#!/usr/bin/env bash

PROTO="$1"
PORT=2003

if [[ -z "$PROTO" ]]; then
    echo "Usage: $0 [udp|rtp|srt]"
    exit 1
fi

case "$PROTO" in
udp)
    exec ffplay "udp://@:${PORT}"
    ;;
rtp)
    exec ffplay "rtp://@:${PORT}"
    ;;
srt)
    exec ffplay "srt://:${PORT}?mode=listener"
    ;;
*)
    echo "Unsupported protocol: $PROTO"
    exit 1
    ;;
esac
