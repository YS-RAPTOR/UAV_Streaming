@echo off
REM Usage: receiver.bat [udp|rtp|srt|rist] output.mp4

set PROTO=%1
set OUTPUT=%2
set PORT=2004

if "%PROTO%"=="" (
    echo Usage: %~nx0 [udp^|rtp^|srt^|rist] output.mp4
    exit /b 1
)

if "%OUTPUT%"=="" (
    echo You must specify an output filename [e.g. output.mp4]
    exit /b 1
)

REM Text overlay settings (match sender)
set FONT="C\\:/Windows/Fonts/arial.ttf"
set TEXT="Time\\: %%{localtime\\:%%X.%%N} (%%{pts\\:hms}) Frame\\: %%{n}"
set DRAW=drawtext=fontfile=%FONT%:text=%TEXT%:fontsize=48:fontcolor=white:x=10:y=100:box=1:boxcolor=black
set DURATION=300

REM Choose ffmpeg input and apply drawtext filter; re-encode video to allow filtering
if /i "%PROTO%"=="udp" (
    ffmpeg -y -i "udp://127.0.0.1:%PORT%" -t %DURATION% -vf %DRAW% -c:v h264_nvenc -preset fast -cq 23 -c:a copy "%OUTPUT%"
    exit /b
) else if /i "%PROTO%"=="rtp" (
    ffmpeg -y -protocol_whitelist file,udp,rtp -i stream.sdp -t %DURATION% -vf %DRAW% -c:v h264_nvenc -preset fast -cq 23 -c:a copy "%OUTPUT%"
    exit /b
) else if /i "%PROTO%"=="srt" (
    ffmpeg -y -i "srt://127.0.0.1:%PORT%?mode=listener" -t %DURATION% -vf %DRAW% -c:v h264_nvenc -preset fast -cq 23 -c:a copy "%OUTPUT%"
    exit /b
) else if /i "%PROTO%"=="rist" (
    ffmpeg -y -i "rist://@:%PORT%" -t %DURATION% -vf %DRAW% -c:v h264_nvenc -preset fast -cq 23 -c:a copy "%OUTPUT%"
    exit /b
) else (
    echo Unsupported protocol: %PROTO%
    exit /b 1
)
