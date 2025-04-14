#!/usr/bin/env bash

PROTO="$1"
TARGET_IP="127.0.0.1" # Change to your receiver's IP
PORT=2003             # Common base port

if [[ -z "$PROTO" ]]; then
    echo "Usage: $0 [udp|rtp|srt]"
    exit 1
fi

INPUT=(-re -f lavfi -i testsrc=rate=60:size=1920x1080
    -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Time\: %{localtime} (%{pts\\:hms})\\nFrame\: %{n}':fontsize=48:fontcolor=white:x=10:y=10")

case "$PROTO" in
udp)
    exec ffmpeg "${INPUT[@]}" -f mpegts "udp://$TARGET_IP:$PORT"
    ;;
rtp)
    exec ffmpeg "${INPUT[@]}" -f rtp "rtp://$TARGET_IP:$PORT"
    ;;
srt)
    exec ffmpeg "${INPUT[@]}" -f mpegts "srt://$TARGET_IP:$PORT"
    ;;
*)
    echo "Unsupported protocol: $PROTO"
    exit 1
    ;;
esac
