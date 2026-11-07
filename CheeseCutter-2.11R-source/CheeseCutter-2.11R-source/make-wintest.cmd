@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "TARGET=%~1"
if not defined TARGET set "TARGET=test"
set "SUPPORTED_TARGET="
for %%T in (all gui ct2util test verify verify-privacy clean toolchain-info) do (
  if /I "%TARGET%"=="%%T" set "SUPPORTED_TARGET=1"
)
if not defined SUPPORTED_TARGET (
  echo Unsupported Windows target "%TARGET%".
  echo Supported targets: all gui ct2util test verify verify-privacy clean toolchain-info
  exit /b 15
)

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo Microsoft Visual Studio Installer discovery is unavailable.
  exit /b 10
)

for /f "usebackq delims=" %%I in (`"%VSWHERE%" -products Microsoft.VisualStudio.Product.BuildTools -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINSTALL=%%I"
if not defined VSINSTALL (
  echo Microsoft x64 C++ Build Tools are unavailable.
  exit /b 11
)

call "%VSINSTALL%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64
if errorlevel 1 exit /b 12

where make.exe >nul 2>nul
if errorlevel 1 (
  echo GNU Make is unavailable in PATH.
  exit /b 13
)
where python3.exe >nul 2>nul
if errorlevel 1 (
  where python.exe >nul 2>nul
  if errorlevel 1 (
    echo Python 3 is unavailable in PATH.
    exit /b 14
  )
  set "PYTHON=python.exe"
) else (
  set "PYTHON=python3.exe"
)

make.exe -f Makefile.win PYTHON=%PYTHON% %TARGET%
exit /b %errorlevel%
