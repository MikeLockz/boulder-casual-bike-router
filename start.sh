#!/bin/bash

# Navigate to project directory
cd "$(dirname "$0")"

echo "============================================="
echo "   Starting Boulder Casual Bike Router       "
echo "============================================="

# Start backend
./venv/bin/python3 backend/app.py > backend.log 2>&1 &
BACKEND_PID=$!
echo "✓ Backend server started with PID $BACKEND_PID (logging to backend.log)"

# Start frontend
./venv/bin/python3 -m http.server 8081 --directory frontend > frontend.log 2>&1 &
FRONTEND_PID=$!
echo "✓ Frontend server started with PID $FRONTEND_PID (logging to frontend.log)"

# Function to clean up background processes on exit
cleanup() {
    echo ""
    echo "Stopping servers..."
    kill $BACKEND_PID 2>/dev/null
    kill $FRONTEND_PID 2>/dev/null
    echo "✓ Servers stopped. Goodbye!"
    exit 0
}

# Trap Ctrl+C (SIGINT) and exit
trap cleanup SIGINT

echo "Waiting for servers to initialize..."
sleep 2

# Open browser on macOS
echo "Opening browser to http://localhost:8081..."
open "http://localhost:8081"

echo "---------------------------------------------"
echo "Application is running."
echo "Press [Ctrl+C] at any time to stop the servers."
echo "---------------------------------------------"

# Keep script running to listen to trap
wait
