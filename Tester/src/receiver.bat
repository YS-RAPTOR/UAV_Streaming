@echo off
REM Usage: receiver.bat [udp|rtp|srt]

set PROTO=%1
set PORT=2004

if "%PROTO%"=="" (
    echo Usage: %~nx0 [udp^|rtp^|srt]
    exit /b 1
)

if /i "%PROTO%"=="udp" (
    ffplay "udp://127.0.0.1:%PORT%"
    exit /b
) else if /i "%PROTO%"=="rtp" (
    ffplay "rtp://127.0.0.1:%PORT%"
    exit /b
) else if /i "%PROTO%"=="srt" (
    ffplay "srt://127.0.0.1:%PORT%?mode=listener"
    exit /b
) else (
    echo Unsupported protocol: %PROTO%
    exit /b 1
)
