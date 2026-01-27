#!/bin/bash
# ABOUTME: Installs the temporal plugin for Claude Code by cloning the repo
# ABOUTME: and setting it up as a local marketplace.

set -e

# Configuration
GITHUB_REPO="https://github.com/MasonEgger/temporal-plugin-claude-code.git"
MARKETPLACE_NAME="masonegger"
PLUGIN_NAME="temporal"
PLUGIN_VERSION="0.1.0"
PLUGIN_SUBDIR="temporal-plugin"

# Paths
CLAUDE_DIR="$HOME/.claude"
CLAUDE_PLUGINS_DIR="$CLAUDE_DIR/plugins"
MARKETPLACES_DIR="$CLAUDE_PLUGINS_DIR/marketplaces"
MARKETPLACE_PATH="$MARKETPLACES_DIR/$MARKETPLACE_NAME"
CACHE_DIR="$CLAUDE_PLUGINS_DIR/cache"
INSTALLED_PLUGINS_FILE="$CLAUDE_PLUGINS_DIR/installed_plugins.json"
KNOWN_MARKETPLACES_FILE="$CLAUDE_PLUGINS_DIR/known_marketplaces.json"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
INSTALL_PATH="$CACHE_DIR/$MARKETPLACE_NAME/$PLUGIN_NAME/$PLUGIN_VERSION"

# Check for required tools
if ! command -v git &> /dev/null; then
    echo "Error: git is required but not installed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Install with: brew install jq"
    exit 1
fi

# Create directories
mkdir -p "$MARKETPLACES_DIR"
mkdir -p "$CACHE_DIR"

# Clone or update the marketplace repo
if [ -d "$MARKETPLACE_PATH" ]; then
    echo "Updating existing marketplace..."
    cd "$MARKETPLACE_PATH"
    git pull --ff-only || true
else
    echo "Cloning repository as marketplace..."
    git clone "$GITHUB_REPO" "$MARKETPLACE_PATH"
fi

# Get the git commit SHA
cd "$MARKETPLACE_PATH"
GIT_COMMIT_SHA=$(git rev-parse HEAD)
echo "Commit SHA: $GIT_COMMIT_SHA"

# Create the plugins directory structure expected by Claude Code
# The marketplace needs a plugins/ directory containing the plugin
PLUGINS_DIR="$MARKETPLACE_PATH/plugins"
mkdir -p "$PLUGINS_DIR"

# Create symlink or copy from temporal-plugin to plugins/temporal
if [ -d "$PLUGINS_DIR/$PLUGIN_NAME" ]; then
    rm -rf "$PLUGINS_DIR/$PLUGIN_NAME"
fi
cp -r "$MARKETPLACE_PATH/$PLUGIN_SUBDIR" "$PLUGINS_DIR/$PLUGIN_NAME"

# Create the .claude-plugin/marketplace.json file
echo "Creating marketplace.json..."
MARKETPLACE_PLUGIN_DIR="$MARKETPLACE_PATH/.claude-plugin"
mkdir -p "$MARKETPLACE_PLUGIN_DIR"

cat > "$MARKETPLACE_PLUGIN_DIR/marketplace.json" << 'MKJSON'
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "masonegger",
  "description": "Mason Egger's Claude Code plugins",
  "owner": {
    "name": "Mason Egger"
  },
  "plugins": [
    {
      "name": "temporal",
      "description": "Temporal SDK best practices for Python, Go, TypeScript, Java, .NET, and Ruby",
      "version": "0.1.0",
      "author": {
        "name": "Temporal Technologies"
      },
      "source": "./plugins/temporal",
      "category": "development"
    }
  ]
}
MKJSON

# Create the cache directory for the installed plugin
echo "Creating cache directory: $INSTALL_PATH"
mkdir -p "$INSTALL_PATH"
cp -r "$PLUGINS_DIR/$PLUGIN_NAME/." "$INSTALL_PATH/"

# Get current timestamp in ISO format
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE_NAME}"

# Update known_marketplaces.json
echo "Updating known_marketplaces.json..."

if [ ! -f "$KNOWN_MARKETPLACES_FILE" ]; then
    echo '{}' > "$KNOWN_MARKETPLACES_FILE"
fi

MARKETPLACE_ENTRY=$(cat <<EOF
{
  "source": {
    "source": "github",
    "repo": "MasonEgger/temporal-plugin-claude-code"
  },
  "installLocation": "$MARKETPLACE_PATH",
  "lastUpdated": "$TIMESTAMP"
}
EOF
)

jq --arg key "$MARKETPLACE_NAME" --argjson entry "$MARKETPLACE_ENTRY" \
   '.[$key] = $entry' "$KNOWN_MARKETPLACES_FILE" > "$KNOWN_MARKETPLACES_FILE.tmp"
mv "$KNOWN_MARKETPLACES_FILE.tmp" "$KNOWN_MARKETPLACES_FILE"

# Update installed_plugins.json
echo "Updating installed_plugins.json..."

if [ ! -f "$INSTALLED_PLUGINS_FILE" ]; then
    echo '{"version": 2, "plugins": {}}' > "$INSTALLED_PLUGINS_FILE"
fi

NEW_ENTRY=$(cat <<EOF
{
  "scope": "user",
  "installPath": "$INSTALL_PATH",
  "version": "$PLUGIN_VERSION",
  "installedAt": "$TIMESTAMP",
  "lastUpdated": "$TIMESTAMP",
  "gitCommitSha": "$GIT_COMMIT_SHA"
}
EOF
)

jq --arg key "$PLUGIN_KEY" --argjson entry "[$NEW_ENTRY]" \
   '.plugins[$key] = $entry' "$INSTALLED_PLUGINS_FILE" > "$INSTALLED_PLUGINS_FILE.tmp"
mv "$INSTALLED_PLUGINS_FILE.tmp" "$INSTALLED_PLUGINS_FILE"

# Enable the plugin in settings.json
echo "Enabling plugin in settings.json..."

if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{"enabledPlugins": {}}' > "$SETTINGS_FILE"
fi

if jq -e '.enabledPlugins' "$SETTINGS_FILE" > /dev/null 2>&1; then
    jq --arg key "$PLUGIN_KEY" '.enabledPlugins[$key] = true' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
else
    jq --arg key "$PLUGIN_KEY" '. + {"enabledPlugins": {($key): true}}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
fi
mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

echo ""
echo "Installation complete!"
echo "Marketplace created at: $MARKETPLACE_PATH"
echo "Plugin cached at: $INSTALL_PATH"
echo "Plugin '$PLUGIN_KEY' enabled in settings.json"
echo ""
echo "Restart Claude Code to load the new plugin."
