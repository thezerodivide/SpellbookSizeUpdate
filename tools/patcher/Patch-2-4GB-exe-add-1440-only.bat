@echo off
title eqgame.exe patcher - 4GB exe to 1440 spellbook
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch-eqgame.ps1" -Mode 4gb -InputPath "%~1"
pause
