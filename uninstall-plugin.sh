#!/bin/bash
# ABOUTME: Uninstalls the temporal plugin for Claude Code by removing files
# ABOUTME: and cleaning up all configuration files.

set -e

# Configuration
MARKETPLACE_NAME="masonegger"
PLUGIN_NAME="temporal"
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE_NAME}"

# Paths
CLAUDE_DIR="$HOME/.claude"
CLAUDE_PLUGINS_DIR="$CLAUDE_DIR/plugins"
MARKETPLACES_DIR="$CLAUDE_PLUGINS_DIR/marketplaces"
MARKETPLACE_PATH="$MARKETPLACES_DIR/$MARKETPLACE_NAME"
CACHE_DIR="$CLAUDE_PLUGINS_DIR/cache"
INSTALLED_PLUGINS_FILE="$CLAUDE_PLUGINS_DIR/installed_plugins.json"
KNOWN_MARKETPLACES_FILE="$CLAUDE_PLUGINS_DIR/known_marketplaces.json"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CACHE_PATH="$CACHE_DIR/$MARKETPLACE_NAME"

# Check for required tools
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Install with: brew install jq"
    exit 1
fi

echo "Uninstalling plugin '$PLUGIN_NAME'..."

# Remove marketplace directory
if [ -d "$MARKETPLACE_PATH" ]; then
    echo "Removing marketplace: $MARKETPLACE_PATH"
    rm -rf "$MARKETPLACE_PATH"
else
    echo "Marketplace not found at: $MARKETPLACE_PATH"
fi

# Remove cache directory
if [ -d "$CACHE_PATH" ]; then
    echo "Removing cache: $CACHE_PATH"
    rm -rf "$CACHE_PATH"
else
    echo "Cache not found at: $CACHE_PATH"
fi

# Remove from known_marketplaces.json
if [ -f "$KNOWN_MARKETPLACES_FILE" ]; then
    if jq -e ".[\"$MARKETPLACE_NAME\"]" "$KNOWN_MARKETPLACES_FILE" > /dev/null 2>&1; then
        echo "Removing from known_marketplaces.json..."
        jq "del(.[\"$MARKETPLACE_NAME\"])" "$KNOWN_MARKETPLACES_FILE" > "$KNOWN_MARKETPLACES_FILE.tmp"
        mv "$KNOWN_MARKETPLACES_FILE.tmp" "$KNOWN_MARKETPLACES_FILE"
    else
        echo "Marketplace not found in known_marketplaces.json"
    fi
else
    echo "known_marketplaces.json not found"
fi

# Remove from installed_plugins.json
if [ -f "$INSTALLED_PLUGINS_FILE" ]; then
    if jq -e ".plugins[\"$PLUGIN_KEY\"]" "$INSTALLED_PLUGINS_FILE" > /dev/null 2>&1; then
        echo "Removing from installed_plugins.json..."
        jq "del(.plugins[\"$PLUGIN_KEY\"])" "$INSTALLED_PLUGINS_FILE" > "$INSTALLED_PLUGINS_FILE.tmp"
        mv "$INSTALLED_PLUGINS_FILE.tmp" "$INSTALLED_PLUGINS_FILE"
    else
        echo "Plugin not found in installed_plugins.json"
    fi
else
    echo "installed_plugins.json not found"
fi

# Remove from settings.json
if [ -f "$SETTINGS_FILE" ]; then
    if jq -e ".enabledPlugins[\"$PLUGIN_KEY\"]" "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo "Removing from settings.json..."
        jq "del(.enabledPlugins[\"$PLUGIN_KEY\"])" "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    else
        echo "Plugin not found in settings.json"
    fi
else
    echo "settings.json not found"
fi

echo ""
echo "Uninstall complete!"
echo "Restart Claude Code to apply changes."
