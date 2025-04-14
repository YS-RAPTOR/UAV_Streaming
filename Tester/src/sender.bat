@echo off
REM Usage: sender.bat [udp|rtp|srt]

set PROTO=%1
set TARGET_IP=127.0.0.1
set PORT=2003

if "%PROTO%"=="" (
    echo Usage: %~nx0 [udp^|rtp^|srt]
    exit /b 1
)

REM Set input options
set FONT="C\\:/Windows/Fonts/arial.ttf"
set TIME="Time\\: %%{localtime} (%%{pts\\:hms})"
set FRAME="Frame\\: %%{n}"
set INPUT=-re -f lavfi -i testsrc=rate=60:size=1920x1080 -vf drawtext=fontfile=%FONT%:text=%TIME%:fontsize=48:fontcolor=white:x=10:y=10,drawtext=fontfile=%FONT%:text=%FRAME%:fontsize=48:fontcolor=white:x=10:y=100

if /i "%PROTO%"=="udp" (
    ffmpeg %INPUT% -f mpegts "udp://%TARGET_IP%:%PORT%"
    exit /b
) else if /i "%PROTO%"=="rtp" (

    ffmpeg %INPUT% -f rtp "rtp://%TARGET_IP%:%PORT%"
    exit /b
) else if /i "%PROTO%"=="srt" (
    ffmpeg %INPUT% -f mpegts "srt://%TARGET_IP%:%PORT%"
    exit /b
) else (
    echo Unsupported protocol: %PROTO%
    exit /b 1
)

