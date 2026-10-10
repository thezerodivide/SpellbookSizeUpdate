@echo off
title Spellbook 1440 - Rollback
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rollback.ps1"
pause
