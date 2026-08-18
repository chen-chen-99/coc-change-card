@echo off
cd /d %~dp0
echo ============================================
echo  Card Clash Local Server
echo  Front-end:  http://localhost:5173/
echo  Admin:      http://localhost:5173/admin.html
echo  Press Ctrl+C to stop.
echo ============================================
call pnpm dev