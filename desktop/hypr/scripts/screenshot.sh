#!/bin/bash

# Create Pictures directory if it doesn't exist
mkdir -p ~/Pictures

# If wf-recorder is running, this script should stop it instead of showing the menu
if pgrep wf-recorder > /dev/null; then
    killall -s SIGINT wf-recorder
    notify-send "Screen Recording" "Recording saved to ~/Pictures/"
    exit 0
fi

# Show rofi menu
CHOICE=$(echo -e "Partial Screen\nFull Screen\nScreen Recording" | rofi -dmenu -p "Capture" -lines 3)

case "$CHOICE" in
    "Partial Screen")
        FILE=~/Pictures/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png
        grim -g "$(slurp)" - | tee "$FILE" | wl-copy
        notify-send "Screenshot" "Partial screenshot saved & copied to clipboard"
        ;;
    "Full Screen")
        FILE=~/Pictures/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png
        grim - | tee "$FILE" | wl-copy
        notify-send "Screenshot" "Full screenshot saved & copied to clipboard"
        ;;
    "Screen Recording")
        if ! command -v wf-recorder &> /dev/null; then
            notify-send "Screen Recording Error" "wf-recorder is not installed. Please install it with: sudo pacman -S wf-recorder"
            exit 1
        fi
        
        FILE=~/Pictures/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4
        
        # Optional: Ask whether to select a region or full screen for recording
        REC_CHOICE=$(echo -e "Select Region\nFull Screen" | rofi -dmenu -p "Record Mode" -lines 2)
        
        if [ "$REC_CHOICE" = "Select Region" ]; then
            notify-send "Screen Recording" "Please select a region to record..."
            REGION=$(slurp)
            if [ -z "$REGION" ]; then
                exit 0
            fi
            wf-recorder -g "$REGION" -f "$FILE" &
        elif [ "$REC_CHOICE" = "Full Screen" ]; then
            wf-recorder -f "$FILE" &
        else
            exit 0
        fi
        
        notify-send "Screen Recording" "Recording started! Press Print Screen again to stop."
        ;;
esac
