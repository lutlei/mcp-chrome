#!/usr/bin/env bash

# Helper script to configure MCP Chrome Server host binding
# This sets up the host IP address for the MCP server to listen on

set -e

SCRIPT_NAME="configure-host.sh"
DEFAULT_HOST="0.0.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [HOST_IP]

Configure the MCP Chrome Server host binding.

Options:
    -h, --help          Show this help message
    -i, --info          Show current configuration
    -r, --reset         Reset to default (0.0.0.0 - all interfaces)
    -t, --tailscale     Auto-detect and use Tailscale IP
    -l, --local         Use localhost only (127.0.0.1)
    -g, --global        Use all interfaces (0.0.0.0) - default

Arguments:
    HOST_IP             IP address to bind to (e.g., 100.121.150.44)

Examples:
    $SCRIPT_NAME 100.121.150.44              # Set specific IP
    $SCRIPT_NAME --tailscale                  # Auto-detect Tailscale IP
    $SCRIPT_NAME --local                      # Use localhost only
    $SCRIPT_NAME --reset                      # Reset to default

Configuration files (checked in order):
    1. ~/.mcp-chrome/host (user config - recommended)
    2. {install_dir}/.mcp-chrome-host (installation config)

EOF
}

detect_tailscale_ip() {
    # Try to detect Tailscale IP
    local tailscale_ip=""
    
    # Method 1: Check ifconfig/ip for tailscale interface
    if command -v ifconfig &> /dev/null; then
        tailscale_ip=$(ifconfig | grep -A 1 "tailscale0" | grep "inet " | awk '{print $2}' | head -1)
    elif command -v ip &> /dev/null; then
        tailscale_ip=$(ip addr show tailscale0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | head -1)
    fi
    
    # Method 2: Check Tailscale CLI if available
    if [ -z "$tailscale_ip" ] && command -v tailscale &> /dev/null; then
        tailscale_ip=$(tailscale ip -4 2>/dev/null | head -1)
    fi
    
    echo "$tailscale_ip"
}

get_install_dir() {
    # Try to find the installation directory
    local script_dir=""
    
    # Check if we're in a development environment
    if [ -f "package.json" ]; then
        script_dir="$(pwd)/dist"
    else
        # Try to find global installation
        if command -v mcp-chrome-bridge &> /dev/null; then
            local bridge_path=$(which mcp-chrome-bridge)
            script_dir=$(dirname "$(dirname "$bridge_path")")
        elif [ -n "$NODE_PATH" ]; then
            script_dir="$NODE_PATH/mcp-chrome-bridge/dist"
        fi
    fi
    
    echo "$script_dir"
}

get_current_config() {
    local user_config="$HOME/.mcp-chrome/host"
    local install_dir=$(get_install_dir)
    local install_config=""
    
    if [ -n "$install_dir" ] && [ -d "$install_dir" ]; then
        install_config="$install_dir/.mcp-chrome-host"
    fi
    
    if [ -f "$user_config" ]; then
        echo "User config: $(cat "$user_config") ($user_config)"
    fi
    
    if [ -n "$install_config" ] && [ -f "$install_config" ]; then
        echo "Install config: $(cat "$install_config") ($install_config)"
    fi
    
    if [ ! -f "$user_config" ] && [ ! -f "$install_config" ]; then
        echo "No configuration found. Using default: $DEFAULT_HOST"
    fi
}

set_config() {
    local host_ip="$1"
    local config_location="$2"
    
    if [ -z "$host_ip" ]; then
        echo -e "${RED}Error: Host IP address is required${NC}" >&2
        return 1
    fi
    
    # Validate IP address format (basic check)
    if ! [[ "$host_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && [ "$host_ip" != "0.0.0.0" ] && [ "$host_ip" != "127.0.0.1" ]; then
        echo -e "${YELLOW}Warning: '$host_ip' doesn't look like a valid IP address${NC}" >&2
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$config_location")"
    
    # Write config
    echo "$host_ip" > "$config_location"
    chmod 644 "$config_location"
    
    echo -e "${GREEN}✓ Configuration saved to: $config_location${NC}"
    echo -e "${BLUE}  Host IP: $host_ip${NC}"
}

# Parse arguments
MODE="set"
HOST_IP=""
USE_USER_CONFIG=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_usage
            exit 0
            ;;
        -i|--info)
            MODE="info"
            shift
            ;;
        -r|--reset)
            MODE="reset"
            shift
            ;;
        -t|--tailscale)
            MODE="tailscale"
            shift
            ;;
        -l|--local)
            MODE="set"
            HOST_IP="127.0.0.1"
            shift
            ;;
        -g|--global)
            MODE="set"
            HOST_IP="0.0.0.0"
            shift
            ;;
        --install-dir)
            USE_USER_CONFIG=false
            shift
            ;;
        *)
            if [ -z "$HOST_IP" ] && [ "$MODE" = "set" ]; then
                HOST_IP="$1"
            else
                echo -e "${RED}Error: Unknown option or too many arguments: $1${NC}" >&2
                print_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Main logic
case "$MODE" in
    info)
        echo -e "${BLUE}Current MCP Chrome Server Configuration:${NC}"
        echo ""
        get_current_config
        echo ""
        echo -e "${BLUE}Detected Tailscale IP:${NC}"
        TAILSCALE_IP=$(detect_tailscale_ip)
        if [ -n "$TAILSCALE_IP" ]; then
            echo -e "${GREEN}  $TAILSCALE_IP${NC}"
        else
            echo -e "${YELLOW}  Not detected (Tailscale may not be running or configured)${NC}"
        fi
        ;;
    reset)
        if [ "$USE_USER_CONFIG" = true ]; then
            CONFIG_FILE="$HOME/.mcp-chrome/host"
        else
            INSTALL_DIR=$(get_install_dir)
            if [ -z "$INSTALL_DIR" ] || [ ! -d "$INSTALL_DIR" ]; then
                echo -e "${RED}Error: Could not determine installation directory${NC}" >&2
                exit 1
            fi
            CONFIG_FILE="$INSTALL_DIR/.mcp-chrome-host"
        fi
        
        if [ -f "$CONFIG_FILE" ]; then
            rm "$CONFIG_FILE"
            echo -e "${GREEN}✓ Configuration reset to default ($DEFAULT_HOST)${NC}"
        else
            echo -e "${YELLOW}No configuration file found. Already using default.${NC}"
        fi
        ;;
    tailscale)
        TAILSCALE_IP=$(detect_tailscale_ip)
        if [ -z "$TAILSCALE_IP" ]; then
            echo -e "${RED}Error: Could not detect Tailscale IP address${NC}" >&2
            echo -e "${YELLOW}Make sure Tailscale is running and configured.${NC}" >&2
            exit 1
        fi
        
        CONFIG_FILE="$HOME/.mcp-chrome/host"
        set_config "$TAILSCALE_IP" "$CONFIG_FILE"
        echo ""
        echo -e "${GREEN}✓ Tailscale IP configured successfully!${NC}"
        echo -e "${BLUE}  Your MCP clients should connect to: http://$TAILSCALE_IP:12306/mcp${NC}"
        ;;
    set)
        if [ -z "$HOST_IP" ]; then
            echo -e "${RED}Error: Host IP address is required${NC}" >&2
            print_usage
            exit 1
        fi
        
        CONFIG_FILE="$HOME/.mcp-chrome/host"
        set_config "$HOST_IP" "$CONFIG_FILE"
        echo ""
        echo -e "${GREEN}✓ Configuration saved!${NC}"
        echo -e "${BLUE}  Your MCP clients should connect to: http://$HOST_IP:12306/mcp${NC}"
        echo ""
        echo -e "${YELLOW}Note: You may need to reconnect the Chrome extension for changes to take effect.${NC}"
        ;;
esac

