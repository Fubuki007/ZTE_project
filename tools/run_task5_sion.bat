@echo off
chcp 65001 >nul

REM 自动定位项目根目录（本批处理在 tools/ 下）
set "PROJECT_DIR=%~dp0.."
pushd "%PROJECT_DIR%"

echo ============================================
echo   Task5 SI-ON: 禁用休眠 → 跑 MATLAB → 恢复
echo   项目: %CD%
echo ============================================

REM 1. 禁用休眠 + 合盖不睡
echo [1/3] 禁用休眠 + 合盖不睡...
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setactive SCHEME_CURRENT
echo       已禁用。跑完自动恢复。

REM 2. 找 MATLAB
echo [2/3] 启动 MATLAB (预计 ~6.3 小时)...
set "MATLAB="
for %%p in (
    "C:\Program Files\MATLAB\R2024a\bin\matlab.exe"
    "E:\Matlab R2024a\bin\matlab.exe"
    "D:\Matlab R2024a\bin\matlab.exe"
    "C:\Matlab R2024a\bin\matlab.exe"
) do if exist %%p set "MATLAB=%%p"
if "%MATLAB%"=="" (
    REM 最后尝试 PATH
    where matlab >nul 2>&1 && set "MATLAB=matlab"
)
if "%MATLAB%"=="" (
    echo [错误] 找不到 MATLAB！请检查安装路径。
    pause
    goto restore
)
echo       MATLAB: %MATLAB%
echo       保持插电！可以合盖。

"%MATLAB%" -batch "run('task5_rmse_vs_snr_si.m');"

REM 3. 恢复
:restore
echo.
echo [3/3] 恢复休眠超时 + 合盖动作...
powercfg /change standby-timeout-ac 180
powercfg /change standby-timeout-dc 5
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1
powercfg /setactive SCHEME_CURRENT
echo       已恢复。
echo ============================================
echo   完成！数据在 mat数据\task5_rmse_vs_snr_si_results.mat
echo ============================================
popd
pause
