@echo off
REM Windows test runner with optional coverage reporting

REM Clean up old coverage files
del /Q luacov.stats.out 2>nul
del /Q luacov.report.out 2>nul

REM Run tests
nvim -l tests/minit.lua --minitest
set EXIT_CODE=%errorlevel%

REM Generate and show coverage report if requested
if "%1"=="--coverage" (
    if %EXIT_CODE% equ 0 (
        if exist luacov.stats.out (
            echo.
            echo Generating coverage report...
            luacov

            if exist luacov.report.out (
                echo.
                echo Coverage Report:
                echo ================
                powershell -Command "Get-Content luacov.report.out | Select-Object -Last 20"
            )
        )
    )
)

exit /b %EXIT_CODE%