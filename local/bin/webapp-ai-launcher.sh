#!/bin/bash
# AI Webapp Launcher - triggered by Copilot hardware button
# Location: ~/.local/bin/webapp-ai-launcher.sh

# Check which menu is available (rofi preferred, dmenu fallback)
if command -v rofi >/dev/null 2>&1; then
    # Use rofi with MatteBlack theme
    choice=$(echo -e "ChatGPT\nClaude\nDeepSeek\nGrok\nCopilot\nGemini" | \
        rofi -dmenu -i -p "🤖 AI Launcher" \
        -theme-str 'window {background-color: #0f0f10; border-color: #5a5a60;} 
                     listview {background-color: #0f0f10;} 
                     element selected {background-color: #3a3a3d; text-color: #e5e5e5;}')
elif command -v dmenu >/dev/null 2>&1; then
    # Fallback to dmenu with MatteBlack colors
    choice=$(echo -e "ChatGPT\nClaude\nDeepSeek\nGrok\nCopilot\nGemini" | \
        dmenu -i -p "🤖 AI:" -nb "#0f0f10" -nf "#a8a8a8" -sb "#3a3a3d" -sf "#e5e5e5")
else
    notify-send "Error" "Neither rofi nor dmenu is installed"
    exit 1
fi

# Launch selected AI webapp using existing scripts in ~/.local/bin/
case $choice in
    "ChatGPT")  ~/.local/bin/chatgptai ;;
    "Claude")   ~/.local/bin/claudeai ;;
    "DeepSeek") ~/.local/bin/deepseekai ;;
    "Grok")     ~/.local/bin/grokai ;;
    "Copilot")  ~/.local/bin/microsoftcopilotai ;;
    "Gemini")   ~/.local/bin/googlegemimiai ;;
esac
