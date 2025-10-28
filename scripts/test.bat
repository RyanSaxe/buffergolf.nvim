@echo off
REM Windows batch script for running tests

REM Check for coverage flag
echo %* | findstr /C:"--coverage" >nul
if %errorlevel% equ 0 (
    echo Running tests with coverage...
    del /Q luacov.stats.out 2>nul
    del /Q luacov.report.out 2>nul
)

REM Run tests using mini.test via the minit.lua bootstrap
nvim -l tests/minit.lua --minitest %*
set EXIT_CODE=%errorlevel%

REM Show coverage report if coverage was enabled and tests passed
echo %* | findstr /C:"--coverage" >nul
if %errorlevel% equ 0 (
    if %EXIT_CODE% equ 0 (
        echo.
        echo Coverage Report:
        echo ================

        if exist luacov.report.out (
            REM Show summary from the report
            powershell -Command "Get-Content luacov.report.out | Select-Object -Last 20"
        ) else (
            echo No coverage report generated. You may need to install luacov.
            echo Install with: luarocks install luacov
        )
    )
)

exit /b %EXIT_CODE%