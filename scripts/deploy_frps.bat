@echo off
setlocal enabledelayedexpansion

rem ==============================================================
rem  One-click FRPS deployment script for Windows (Administrator)
rem  - Downloads official frps release
rem  - Installs into %ProgramData%\frp\frps
rem  - Generates minimal config mapping remote port 55555
rem  - Registers and starts a Windows service
rem ==============================================================

rem ---- Configuration (edit if needed) ----
set "FRP_VERSION=0.65.0"
set "FRP_TOKEN=frp-demo-token"
set "FRP_BIND_PORT=7000"
set "FRP_REMOTE_PORT=55555"
set "FRP_SERVICE_NAME=frps"
set "FRP_DISPLAY_NAME=FRP Server (frps)"

rem Install directory (no trailing slash)
set "FRP_INSTALL_ROOT=%ProgramData%\frp"
set "FRP_INSTALL_DIR=%FRP_INSTALL_ROOT%\frps"

rem ---- Privilege check ----
openfiles >nul 2>&1
if not %errorlevel%==0 (
    echo [ERROR] Please run this script from an elevated (Administrator) command prompt.
    exit /b 1
)

rem ---- Determine architecture suffix ----
set "FRP_ARCH_SUFFIX=windows_amd64"
for /f "tokens=*" %%A in ('wmic os get osarchitecture ^| find "64"') do (
    set "FRP_ARCH_SUFFIX=windows_amd64"
)
for /f "tokens=*" %%A in ('wmic os get osarchitecture ^| find "32"') do (
    set "FRP_ARCH_SUFFIX=windows_386"
)

if /i "!FRP_ARCH_SUFFIX!"=="windows_386" (
    echo [ERROR] 32-bit Windows is not supported by the official frps binary.
    echo         Please upgrade to a 64-bit system or provide FRP_ARCH_SUFFIX manually.
    exit /b 1
)

set "FRP_PACKAGE=frp_%FRP_VERSION%_!FRP_ARCH_SUFFIX!.zip"
set "FRP_DOWNLOAD_URL=https://github.com/fatedier/frp/releases/download/v%FRP_VERSION%/%FRP_PACKAGE%"

set "TEMP_DIR=%TEMP%\frp_%RANDOM%%RANDOM%"
set "TEMP_ZIP=%TEMP_DIR%\%FRP_PACKAGE%"
set "EXTRACT_DIR=%TEMP_DIR%\frp_%FRP_VERSION%_!FRP_ARCH_SUFFIX!"

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%" || (
    echo [ERROR] Unable to create temp directory "%TEMP_DIR%".
    exit /b 1
)

rem ---- Download official release ----
echo [INFO] Downloading %FRP_DOWNLOAD_URL%
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%FRP_DOWNLOAD_URL%' -OutFile '%TEMP_ZIP%'" || (
    echo [ERROR] Failed to download frps package.
    rmdir /s /q "%TEMP_DIR%"
    exit /b 1
)

rem ---- Extract package ----
echo [INFO] Extracting package to "%TEMP_DIR%"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%TEMP_ZIP%' -DestinationPath '%TEMP_DIR%' -Force" || (
    echo [ERROR] Failed to extract frps package.
    rmdir /s /q "%TEMP_DIR%"
    exit /b 1
)

if not exist "%EXTRACT_DIR%\frps.exe" (
    echo [ERROR] frps.exe not found after extraction.
    rmdir /s /q "%TEMP_DIR%"
    exit /b 1
)

rem ---- Install binaries ----
echo [INFO] Installing frps into "%FRP_INSTALL_DIR%"
if not exist "%FRP_INSTALL_DIR%" mkdir "%FRP_INSTALL_DIR%"
copy /Y "%EXTRACT_DIR%\frps.exe" "%FRP_INSTALL_DIR%\frps.exe" >nul || (
    echo [ERROR] Failed to copy frps.exe to install directory.
    rmdir /s /q "%TEMP_DIR%"
    exit /b 1
)

rem ---- Generate configuration ----
set "FRP_CONFIG=%FRP_INSTALL_DIR%\frps.toml"
> "%FRP_CONFIG%" echo bindAddr = "0.0.0.0"
>>"%FRP_CONFIG%" echo bindPort = %FRP_BIND_PORT%
>>"%FRP_CONFIG%" echo
>>"%FRP_CONFIG%" echo [auth]
>>"%FRP_CONFIG%" echo token = "%FRP_TOKEN%"
>>"%FRP_CONFIG%" echo
>>"%FRP_CONFIG%" echo [log]
>>"%FRP_CONFIG%" echo to = "%FRP_INSTALL_DIR%\frps.log"
>>"%FRP_CONFIG%" echo level = "info"
>>"%FRP_CONFIG%" echo maxDays = 3
>>"%FRP_CONFIG%" echo
>>"%FRP_CONFIG%" echo [transport]
>>"%FRP_CONFIG%" echo tls.force = false

rem ---- Create Windows service ----
echo [INFO] Configuring Windows service "%FRP_SERVICE_NAME%"
sc.exe query "%FRP_SERVICE_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo [INFO] Existing service found, removing...
    sc.exe stop "%FRP_SERVICE_NAME%" >nul 2>&1
    sc.exe delete "%FRP_SERVICE_NAME%" >nul 2>&1
)

set "SERVICE_BIN=\"%FRP_INSTALL_DIR%\frps.exe\" -c \"%FRP_CONFIG%\""
sc.exe create "%FRP_SERVICE_NAME%" binPath= "%SERVICE_BIN%" start= auto DisplayName= "%FRP_DISPLAY_NAME%" >nul || (
    echo [ERROR] Failed to create Windows service.
    rmdir /s /q "%TEMP_DIR%"
    exit /b 1
)
sc.exe description "%FRP_SERVICE_NAME%" "FRP server mapping remote port %FRP_REMOTE_PORT%" >nul

rem ---- Open firewall ports ----
echo [INFO] Updating Windows Firewall rules
netsh advfirewall firewall add rule name="FRPS Control %FRP_BIND_PORT%" dir=in action=allow protocol=TCP localport=%FRP_BIND_PORT% >nul 2>&1
netsh advfirewall firewall add rule name="FRPS Proxy %FRP_REMOTE_PORT%" dir=in action=allow protocol=TCP localport=%FRP_REMOTE_PORT% >nul 2>&1

rem ---- Start service ----
echo [INFO] Starting frps service
sc.exe start "%FRP_SERVICE_NAME%" >nul || (
    echo [ERROR] Failed to start frps service. Check event viewer or the log file.
    rmdir /s /q "%TEMP_DIR%"
    exit /b 1
)

rem ---- Cleanup ----
rmdir /s /q "%TEMP_DIR%"

echo [SUCCESS] frps is running with control port %FRP_BIND_PORT% and proxy port %FRP_REMOTE_PORT%.
echo            Use "sc query %FRP_SERVICE_NAME%" to verify status.
echo            Logs: %FRP_INSTALL_DIR%\frps.log

endlocal
exit /b 0
