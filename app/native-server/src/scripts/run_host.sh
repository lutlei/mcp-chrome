#!/usr/bin/env bash

# Configuration
ENABLE_LOG_ROTATION="true"
LOG_RETENTION_COUNT=5

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

# Load MCP_CHROME_HOST from config file if it exists
# Priority: 1) Config file in script directory, 2) User home config, 3) Environment variable, 4) Default
MCP_CHROME_HOST="${MCP_CHROME_HOST:-}"
CONFIG_FILE="${SCRIPT_DIR}/.mcp-chrome-host"
USER_CONFIG_FILE="${HOME}/.mcp-chrome/host"

if [ -z "${MCP_CHROME_HOST}" ]; then
    if [ -f "${CONFIG_FILE}" ]; then
        MCP_CHROME_HOST=$(cat "${CONFIG_FILE}" 2>/dev/null | tr -d '\n\r ' | head -c 50)
        echo "Loaded MCP_CHROME_HOST from ${CONFIG_FILE}: ${MCP_CHROME_HOST}" >> "${LOG_DIR}/wrapper_config.log" 2>&1 || true
    elif [ -f "${USER_CONFIG_FILE}" ]; then
        MCP_CHROME_HOST=$(cat "${USER_CONFIG_FILE}" 2>/dev/null | tr -d '\n\r ' | head -c 50)
        echo "Loaded MCP_CHROME_HOST from ${USER_CONFIG_FILE}: ${MCP_CHROME_HOST}" >> "${LOG_DIR}/wrapper_config.log" 2>&1 || true
    fi
fi

# Export the environment variable for the Node.js process
export MCP_CHROME_HOST="${MCP_CHROME_HOST:-0.0.0.0}"

# Log rotation
if [ "${ENABLE_LOG_ROTATION}" = "true" ]; then
    ls -tp "${LOG_DIR}/native_host_wrapper_macos_"* 2>/dev/null | tail -n +$((LOG_RETENTION_COUNT + 1)) | xargs -I {} rm -- {}
    ls -tp "${LOG_DIR}/native_host_stderr_macos_"* 2>/dev/null | tail -n +$((LOG_RETENTION_COUNT + 1)) | xargs -I {} rm -- {}
fi

# Logging setup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
WRAPPER_LOG="${LOG_DIR}/native_host_wrapper_macos_${TIMESTAMP}.log"
STDERR_LOG="${LOG_DIR}/native_host_stderr_macos_${TIMESTAMP}.log"
NODE_SCRIPT="${SCRIPT_DIR}/index.js"

# Initial logging
{
    echo "--- Wrapper script called at $(date) ---"
    echo "SCRIPT_DIR: ${SCRIPT_DIR}"
    echo "LOG_DIR: ${LOG_DIR}"
    echo "NODE_SCRIPT: ${NODE_SCRIPT}"
    echo "Initial PATH: ${PATH}"
    echo "User: $(whoami)"
    echo "Current PWD: $(pwd)"
} > "${WRAPPER_LOG}"

# Node.js discovery
NODE_EXEC=""

# Priority 1: Installation-time node path
NODE_PATH_FILE="${SCRIPT_DIR}/node_path.txt"
echo "Searching for Node.js..." >> "${WRAPPER_LOG}"
echo "[Priority 1] Checking installation-time node path" >> "${WRAPPER_LOG}"
if [ -f "${NODE_PATH_FILE}" ]; then
    EXPECTED_NODE=$(cat "${NODE_PATH_FILE}" 2>/dev/null | tr -d '\n\r')
    if [ -n "${EXPECTED_NODE}" ] && [ -x "${EXPECTED_NODE}" ]; then
        NODE_EXEC="${EXPECTED_NODE}"
        echo "Found installation-time node at ${NODE_EXEC}" >> "${WRAPPER_LOG}"
    fi
fi

# Priority 1.5: Fallback to relative path
if [ -z "${NODE_EXEC}" ]; then
    EXPECTED_NODE="${SCRIPT_DIR}/../../../bin/node"
    echo "[Priority 1.5] Checking relative path" >> "${WRAPPER_LOG}"
    if [ -x "${EXPECTED_NODE}" ]; then
        NODE_EXEC="${EXPECTED_NODE}"
        echo "Found node at relative path: ${NODE_EXEC}" >> "${WRAPPER_LOG}"
    fi
fi

# Priority 2: NVM
if [ -z "${NODE_EXEC}" ]; then
    echo "[Priority 2] Checking NVM" >> "${WRAPPER_LOG}"
    NVM_DIR="$HOME/.nvm"
    if [ -d "${NVM_DIR}" ]; then
        # Try default version first
        if [ -L "${NVM_DIR}/alias/default" ]; then
            NVM_DEFAULT_VERSION=$(readlink "${NVM_DIR}/alias/default")
            NVM_DEFAULT_NODE="${NVM_DIR}/versions/node/${NVM_DEFAULT_VERSION}/bin/node"
            if [ -x "${NVM_DEFAULT_NODE}" ]; then
                NODE_EXEC="${NVM_DEFAULT_NODE}"
                echo "Found NVM default node: ${NODE_EXEC}" >> "${WRAPPER_LOG}"
            fi
        fi

        # Fallback to latest version
        if [ -z "${NODE_EXEC}" ]; then
            LATEST_NVM_VERSION_PATH=$(ls -d ${NVM_DIR}/versions/node/v* 2>/dev/null | sort -V | tail -n 1)
            if [ -n "${LATEST_NVM_VERSION_PATH}" ] && [ -x "${LATEST_NVM_VERSION_PATH}/bin/node" ]; then
                NODE_EXEC="${LATEST_NVM_VERSION_PATH}/bin/node"
                echo "Found NVM latest node: ${NODE_EXEC}" >> "${WRAPPER_LOG}"
            fi
        fi
    fi
fi

# Priority 3: Common paths
if [ -z "${NODE_EXEC}" ]; then
    echo "[Priority 3] Checking common paths" >> "${WRAPPER_LOG}"
    COMMON_NODE_PATHS=(
        "/opt/homebrew/bin/node"
        "/usr/local/bin/node"
    )
    for path_to_node in "${COMMON_NODE_PATHS[@]}"; do
        if [ -x "${path_to_node}" ]; then
            NODE_EXEC="${path_to_node}"
            echo "Found node at: ${NODE_EXEC}" >> "${WRAPPER_LOG}"
            break
        fi
    done
fi

# Priority 4: command -v
if [ -z "${NODE_EXEC}" ]; then
    echo "[Priority 4] Trying 'command -v node'" >> "${WRAPPER_LOG}"
    if command -v node &>/dev/null; then
        NODE_EXEC=$(command -v node)
        echo "Found node using 'command -v': ${NODE_EXEC}" >> "${WRAPPER_LOG}"
    fi
fi

# Priority 5: PATH search
if [ -z "${NODE_EXEC}" ]; then
    echo "[Priority 5] Searching PATH" >> "${WRAPPER_LOG}"
    OLD_IFS=$IFS
    IFS=:
    for path_in_env in $PATH; do
        if [ -x "${path_in_env}/node" ]; then
            NODE_EXEC="${path_in_env}/node"
            echo "Found node in PATH: ${NODE_EXEC}" >> "${WRAPPER_LOG}"
            break
        fi
    done
    IFS=$OLD_IFS
fi

# Execution
if [ -z "${NODE_EXEC}" ]; then
    {
        echo "ERROR: Node.js executable not found!"
        echo "Searched: installation path, relative path, NVM, common paths, command -v, PATH"
    } >> "${WRAPPER_LOG}"
    exit 1
fi

{
    echo "Using Node executable: ${NODE_EXEC}"
    echo "Node version: $(${NODE_EXEC} -v)"
    echo "Executing: ${NODE_EXEC} ${NODE_SCRIPT}"
} >> "${WRAPPER_LOG}"

exec "${NODE_EXEC}" "${NODE_SCRIPT}" 2>> "${STDERR_LOG}"