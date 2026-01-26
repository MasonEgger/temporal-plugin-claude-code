# Temporal Plugin for Claude Code

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

Copy or symlink the `temporal-plugin` directory to your Claude Code plugins directory:

```bash
# Copy
cp -r temporal-plugin ~/.claude/plugins/

# Or symlink
ln -s "$(pwd)/temporal-plugin" ~/.claude/plugins/temporal
```

## What's Included

The plugin provides skills that are automatically triggered when discussing Temporal topics. Each skill covers:

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
