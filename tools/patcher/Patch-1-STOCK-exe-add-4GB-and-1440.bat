@echo off
title eqgame.exe patcher - stock exe to 4GB + 1440 spellbook
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch-eqgame.ps1" -Mode stock -InputPath "%~1"
pause
