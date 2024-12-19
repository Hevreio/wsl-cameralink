@echo off
setlocal EnableDelayedExpansion

:: Debug switch - Set to 0 to disable debug output, 1 to enable
set "DEBUG=0"

:: Debug output function
set "debug_echo=rem"
if "%DEBUG%"=="1" set "debug_echo=echo"

:: 设置目录和文件路径
set "CONFIG_DIR=%LOCALAPPDATA%\Microsoft\WindowsApps\my-scripts\config"
set "CONFIG_FILE=%CONFIG_DIR%\camera_config.yaml"

%debug_echo% [DEBUG] Config directory: %CONFIG_DIR%
%debug_echo% [DEBUG] Config file: %CONFIG_FILE%

:: 检查并创建配置目录
if not exist "%CONFIG_DIR%" (
    %debug_echo% [DEBUG] Creating config directory...
    mkdir "%CONFIG_DIR%" 2>nul
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to create config directory
        pause
        exit /b 1
    )
)

:: 检查 usbipd 命令是否存在
where usbipd >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] usbipd command not found. Please ensure USBIPD is installed.
    pause
    exit /b 1
)

:: 如果配置文件不存在，创建默认配置
if not exist "%CONFIG_FILE%" (
    echo Creating default configuration file...
    (
        echo # Camera configuration file
        echo search_keywords:
        echo   - Camera
        echo   - Berxel
    ) > "%CONFIG_FILE%"
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to create configuration file
        pause
        exit /b 1
    )
    echo Default configuration file created at: %CONFIG_FILE%
)

:: 读取关键词
set "keywords="
set "reading_keywords=0"
echo Reading configuration...
for /f "tokens=1,* delims=:" %%a in ('type "%CONFIG_FILE%" ^| findstr /v "^#"') do (
    set "line=%%a"
    set "value=%%b"
    if "!line!"=="search_keywords" (
        set "reading_keywords=1"
    ) else if "!reading_keywords!"=="1" (
        if "!line:~0,4!"=="  - " (
            set "keyword=!line:~4!"
            if "!keywords!"=="" (
                set "keywords=!keyword!"
            ) else (
                set "keywords=!keywords!,!keyword!"
            )
        )
    )
)

echo Found keywords: !keywords!
echo.

:: 创建临时文件来存储设备列表
set "temp_file=%TEMP%\device_list.txt"
%debug_echo% [DEBUG] Creating temporary file: !temp_file!

:: 运行 usbipd list 并处理输出
echo Scanning for USB devices...
usbipd list > "!temp_file!" 2>nul

:: 检查 usbipd 命令是否成功执行
if !ERRORLEVEL! neq 0 (
    echo [ERROR] Failed to list USB devices. Error code: !ERRORLEVEL!
    pause
    exit /b 1
)

:: 只保存Connected部分到一个新的临时文件
set "filtered_file=%TEMP%\filtered_devices.txt"
%debug_echo% [DEBUG] Creating filtered list: !filtered_file!
set "save_lines=0"
type nul > "!filtered_file!"
for /f "usebackq tokens=*" %%a in ("!temp_file!") do (
    set "line=%%a"
    if "!line!"=="Connected:" (
        set "save_lines=1"
        echo %%a >> "!filtered_file!"
    ) else if "!line!"=="Persisted:" (
        set "save_lines=0"
    ) else if "!save_lines!"=="1" (
        echo %%a >> "!filtered_file!"
    )
)

:: 初始化设备计数
set "device_count=0"

:: 遍历每个关键词
for %%k in (!keywords!) do (
    echo Searching for devices with keyword: %%k
    %debug_echo% [DEBUG] Processing keyword: %%k
    
    for /f "skip=2 usebackq tokens=1,*" %%a in ("!filtered_file!") do (
        set "full_line=%%b"
        echo "!full_line!" | findstr /i "%%k" >nul
        if !errorlevel! equ 0 (
            set /a device_count+=1
            set "busid[!device_count!]=%%a"
            set "desc[!device_count!]=!full_line!"
            echo !device_count!: BUSID=%%a, Description=!full_line!
            %debug_echo% [DEBUG] Found matching device: BUSID=%%a
        )
    )
)

:: 清理临时文件
if exist "!temp_file!" del "!temp_file!"
if exist "!filtered_file!" del "!filtered_file!"

if !device_count! equ 0 (
    echo [ERROR] No devices found matching any of the keywords.
    pause
    exit /b 1
)

:: 让用户选择设备
set /p choice="Please select the device number (1-!device_count!): "
%debug_echo% [DEBUG] User selected device number: !choice!

:: 验证用户选择的输入
if "!choice!" lss "1" (
    echo [ERROR] Invalid selection, please select a valid device number.
    pause
    exit /b 1
)

if "!choice!" gtr "!device_count!" (
    echo [ERROR] Invalid selection, please select a valid device number.
    pause
    exit /b 1
)

set "busid_selected=!busid[%choice%]!"
set "desc_selected=!desc[%choice%]!"

echo.
echo You selected device with BUSID: !busid_selected!
echo Description: !desc_selected!
echo.

:: 检查设备当前状态
%debug_echo% [DEBUG] Checking device status...
usbipd list | findstr "!busid_selected!" | findstr "Bound" >nul
set "already_bound=!errorlevel!"

:: 绑定设备
echo Binding camera device...
%debug_echo% [DEBUG] Attempting to bind device: !busid_selected!
usbipd bind -b "!busid_selected!" 2>nul
set "bind_result=!errorlevel!"

if !bind_result! neq 0 (
    if !already_bound! equ 0 (
        echo Device is already bound, continuing...
    ) else (
        %debug_echo% [DEBUG] Attempting bind with elevated privileges...
        powershell -Command "Start-Process cmd -Verb RunAs -ArgumentList '/c usbipd bind -b !busid_selected!'" 2>nul
        timeout /t 2 >nul
    )
)

:: 附加设备到WSL
echo Attaching camera to WSL...
%debug_echo% [DEBUG] Attempting to attach device to WSL...

if "!wsl_distribution!"=="" (
    %debug_echo% [DEBUG] Using default WSL distribution
    usbipd attach -w -b "!busid_selected!" 
) else (
    %debug_echo% [DEBUG] Using specified WSL distribution: !wsl_distribution!
    usbipd attach -w -d !wsl_distribution! -b "!busid_selected!" 2>nul
)
set "attach_result=!errorlevel!"

if !attach_result! neq 0 (
    echo [ERROR] Failed to attach device to WSL. Error code: !attach_result!
    pause
    exit /b 1
)

echo.
echo Camera successfully shared with WSL!
echo.
pause
exit /b 0