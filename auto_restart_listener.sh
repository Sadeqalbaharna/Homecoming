#!/bin/bash
# Homecoming Auto-Restart Script
# Place in /home/pi/homecoming/auto_restart_listener.sh

LOG_FILE="/home/pi/homecoming/listener_monitor.log"
PID_FILE="/home/pi/homecoming/listener.pid"
LISTENER_SCRIPT="/home/pi/homecoming/firebase_rest_listener_debug.py"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

start_listener() {
    log_message "Starting Firebase listener..."
    cd /home/pi/homecoming
    
    # Start listener in background and save PID
    sudo python3 "$LISTENER_SCRIPT" &
    echo $! > "$PID_FILE"
    
    log_message "Firebase listener started with PID: $(cat $PID_FILE)"
}

stop_listener() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            log_message "Stopping Firebase listener (PID: $PID)..."
            sudo kill $PID
            rm -f "$PID_FILE"
            log_message "Firebase listener stopped"
        else
            log_message "PID $PID not running, removing stale PID file"
            rm -f "$PID_FILE"
        fi
    fi
}

check_listener() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            # Process is running, check if it's responsive
            if curl -s --connect-timeout 3 http://localhost:5001/kai/status > /dev/null 2>&1; then
                return 0  # Listener is running and responsive
            else
                log_message "Listener process exists but not responsive"
                return 1  # Process exists but not responding
            fi
        else
            log_message "PID file exists but process not running"
            rm -f "$PID_FILE"
            return 1  # Process not running
        fi
    else
        return 1  # No PID file
    fi
}

# Main monitoring loop
case "$1" in
    start)
        log_message "=== Homecoming Auto-Restart Monitor Started ==="
        
        while true; do
            if ! check_listener; then
                log_message "Firebase listener not running or not responsive"
                stop_listener  # Clean up any stale processes
                sleep 2
                start_listener
                sleep 10  # Give it time to start up
            else
                log_message "Firebase listener healthy"
            fi
            
            sleep 30  # Check every 30 seconds
        done
        ;;
    
    stop)
        log_message "=== Stopping Homecoming Auto-Restart Monitor ==="
        stop_listener
        # Kill monitor script itself
        pkill -f "auto_restart_listener.sh"
        ;;
    
    restart)
        log_message "=== Restarting Firebase Listener ==="
        stop_listener
        sleep 3
        start_listener
        ;;
    
    status)
        if check_listener; then
            echo "✅ Firebase listener is running and responsive"
            PID=$(cat "$PID_FILE")
            echo "🔢 PID: $PID"
            echo "🌐 API: http://192.168.29.5:5001/kai/status"
        else
            echo "❌ Firebase listener is not running or not responsive"
        fi
        ;;
    
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        echo "  start   - Start monitoring and auto-restart"
        echo "  stop    - Stop listener and monitoring"  
        echo "  restart - Restart the listener"
        echo "  status  - Check listener status"
        exit 1
        ;;
esac