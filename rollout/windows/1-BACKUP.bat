@echo off
title Spellbook 1440 - Backup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup.ps1"
pause
