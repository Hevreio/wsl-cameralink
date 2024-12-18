@echo off
setlocal EnableDelayedExpansion

:: 脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "CONFIG_FILE=%SCRIPT_DIR%camera_config.yaml"

:: 检查配置文件是否存在
if not exist "%CONFIG_FILE%" (
    echo Error: Configuration file not found at %CONFIG_FILE%
    echo Creating default configuration file...
    
    :: 创建默认配置文件
    (
        echo # camera_config.yaml
        echo search_keyword: "HP 5MP Camera"
        echo device_description: "HP Laptop Camera"
        echo verbose: true
        echo wsl:
        echo   distribution: ""
    ) > "%CONFIG_FILE%"
    
    echo Default configuration file created. Please review and modify if needed.
    pause
    exit /b 1
)

:: 读取配置文件
for /f "tokens=1,* delims=:" %%a in ('type "%CONFIG_FILE%" ^| findstr /v "#" ^| findstr ":"') do (
    set "key=%%a"
    set "value=%%b"
    set "!key: =!=!value: =!"
)

echo Searching for camera using keyword: %search_keyword%

:: 使用配置的关键词搜索设备
for /f "tokens=1-5" %%a in ('usbipd list ^| findstr "%search_keyword%"') do (
    set "busid=%%a"
)

if not defined busid (
    echo Error: Camera device not found.
    echo Please check the search_keyword in %CONFIG_FILE%
    pause
    exit /b 1
)

echo Found camera at BUSID: %busid%
if "%verbose%"=="true" echo Device description: %device_description%

:: 绑定设备
echo Binding camera device...
usbipd bind -b %busid%

if %ERRORLEVEL% neq 0 (
    if %ERRORLEVEL% equ 1 (
        echo Camera is already bound, continuing...
    ) else (
        echo Error binding camera device.
        pause
        exit /b 1
    )
)

:: 附加设备到WSL
echo Attaching camera to WSL...
if "%wsl_distribution%"=="" (
    usbipd attach -w -b %busid%
) else (
    usbipd attach -w -d %wsl_distribution% -b %busid%
)

if %ERRORLEVEL% neq 0 (
    echo Error attaching camera to WSL.
    pause
    exit /b 1
)

echo Camera successfully shared with WSL!
pause
exit /b 0