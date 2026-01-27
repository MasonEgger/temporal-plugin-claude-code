# Temporal Plugin for Claude Code

> **Prototype / Unofficial**: This is an experimental plugin and is NOT an official Temporal product. Use at your own discretion. Feedback and contributions welcome.

A Claude Code plugin providing Temporal SDK best practices, patterns, and guidance for all supported languages.

## Overview

This plugin helps Claude Code assist with Temporal application development by providing SDK-specific knowledge for:

- **Python** (`temporalio`)
- **Go** (`go.temporal.io/sdk`)
- **TypeScript** (`@temporalio/*`)
- **Java** (`io.temporal`)
- **.NET** (`Temporalio`)
- **Ruby** (`temporalio` gem)

## Installation

This plugin is not published to an official Claude Code marketplace, so it requires a manual installation process. The install script sets up a local "marketplace" directory and registers the plugin with Claude Code's plugin system.

### Quick Install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/MasonEgger/temporal-plugin-claude-code/main/install-plugin.sh | sh
```

### Manual Install

Clone the repository and run the install script:

```bash
git clone https://github.com/MasonEgger/temporal-plugin-claude-code.git
cd temporal-plugin-claude-code
./install-plugin.sh
```

### What the Install Script Does

Since this plugin isn't on an official marketplace, the install script:
1. Clones the repo to `~/.claude/plugins/marketplaces/masonegger/`
2. Creates a `marketplace.json` manifest so Claude Code recognizes it
3. Copies the plugin to the cache directory
4. Registers the plugin in `installed_plugins.json` and `known_marketplaces.json`
5. Enables the plugin in `settings.json`

### Requirements

- `git`
- `jq` (install with `brew install jq` on macOS)

After installation, restart Claude Code to load the plugin.

## Uninstallation

```bash
curl -fsSL https://raw.githubusercontent.com/MasonEgger/temporal-plugin-claude-code/main/uninstall-plugin.sh | sh
```

Or if you have the repo cloned:

```bash
./uninstall-plugin.sh
```

## Usage

The plugin provides **skills** that are automatically triggered based on context. When you ask Claude Code questions about Temporal (e.g., "How do I create a workflow in Python?" or "What are the determinism rules in Go?"), the relevant SDK skill loads automatically.

**Note**: Skills don't appear in slash command autocomplete. They're designed to activate automatically when Claude detects relevant context in your questions. You don't need to explicitly invoke them.

## What's Included

Each SDK skill covers:

| Topic | Description |
|-------|-------------|
| **Determinism** | Workflow determinism rules, sandboxing, safe alternatives |
| **Error Handling** | Application failures, retry policies, compensation patterns |
| **Testing** | Time-skipping environments, activity mocking, replay testing |
| **Patterns** | Signals, queries, updates, child workflows, sagas |
| **Versioning** | Patching API, Worker Versioning, deployment strategies |
| **Observability** | Replay-aware logging, metrics, tracing, search attributes |
| **Advanced Features** | Continue-as-new, interceptors, schedules |
| **Data Handling** | Custom converters, encryption, payload codecs |

## Repository Structure

```
temporal-plugin-claude-code/
├── README.md                    # This file
└── temporal-plugin/             # The Claude Code plugin
    ├── .claude-plugin/
    │   └── plugin.json          # Plugin manifest
    ├── skills/
    │   ├── python-sdk/
    │   ├── go-sdk/
    │   ├── typescript-sdk/
    │   ├── java-sdk/
    │   ├── dotnet-sdk/
    │   └── ruby-sdk/
    ├── README.md                # Plugin documentation
    └── LICENSE
```

## Contributing

1. Fork this repository
2. Edit or add content in `temporal-plugin/skills/`
3. Submit a pull request

See [temporal-plugin/README.md](temporal-plugin/README.md) for details on the skill structure.

## License

MIT License - see [temporal-plugin/LICENSE](temporal-plugin/LICENSE)
