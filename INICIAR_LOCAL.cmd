@echo off
cd /d "%~dp0"
title Normalizador de video - Servidor local
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0servidor_local.ps1"
