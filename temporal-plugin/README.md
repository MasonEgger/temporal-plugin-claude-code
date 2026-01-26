# Temporal Claude Code Plugin

A comprehensive Claude Code plugin providing Temporal SDK best practices for all 6 supported languages.

## Installation

Copy the `temporal-plugin` directory to your Claude Code plugins directory:

```bash
cp -r temporal-plugin ~/.claude/plugins/
```

Or symlink it:

```bash
ln -s /path/to/temporal-plugin ~/.claude/plugins/temporal
```

## Available Skills

| Skill | Trigger Phrases |
|-------|-----------------|
| **python-sdk** | "Temporal Python", "temporalio", "Python workflow", "Python activity" |
| **go-sdk** | "Temporal Go", "go.temporal.io", "Go workflow", "Go activity" |
| **typescript-sdk** | "Temporal TypeScript", "@temporalio", "Node.js Temporal" |
| **java-sdk** | "Temporal Java", "io.temporal", "Java workflow", "Java activity" |
| **dotnet-sdk** | "Temporal .NET", "Temporal C#", ".NET workflow", "C# activity" |
| **ruby-sdk** | "Temporal Ruby", "temporalio gem", "Rails Temporal" |

## Usage

The skills are automatically triggered when you mention relevant keywords. For example:

- "Help me create a Temporal workflow in Python"
- "How do I handle errors in Go Temporal activities?"
- "What are the determinism rules for .NET workflows?"

Each skill provides:
- SDK-specific workflow and activity patterns
- Determinism rules and safe alternatives
- Error handling best practices
- Testing strategies
- Worker configuration examples

## Skill Structure

Each SDK skill follows a progressive disclosure pattern:

```
skills/{sdk-name}/
├── SKILL.md               # Lean overview (~1,500-2,000 words)
└── references/
    ├── determinism.md     # Determinism rules, sandbox, history replay
    ├── error-handling.md  # Exception/error patterns, retry policies
    ├── testing.md         # Testing strategies, time-skipping
    ├── patterns.md        # Signals, queries, child workflows
    ├── observability.md   # Logging, metrics, tracing
    ├── versioning.md      # Patching API, Worker Versioning, deployment strategies
    ├── advanced-features.md # Continue-as-new, updates, interceptors
    └── data-handling.md   # Data converters, encryption, search attributes
```

## Key Topics Covered

### Determinism
- SDK-specific safe alternatives for time, random, sleep
- Sandbox behavior (Python, TypeScript)
- Static analysis tools (Go)
- Task scheduler gotchas (.NET)

### Error Handling
- Application errors/failures
- Non-retryable error marking
- Retry policy configuration
- Saga pattern for compensations

### Testing
- Time-skipping test environments
- Activity mocking
- Workflow replay testing

### Patterns
- Signals, queries, updates
- Child workflows
- Saga pattern for compensations

### Versioning
- Patching API for backward-compatible changes
- Three-step patching process (patch, deprecate, remove)
- Workflow Type versioning for incompatible changes
- Worker Versioning with PINNED and AUTO_UPGRADE behaviors
- Blue-green and rainbow deployment strategies

### Observability
- Replay-aware logging (SDK-specific loggers)
- Metrics with Prometheus/Micrometer
- OpenTelemetry tracing
- Search attributes for workflow visibility

### Advanced Features
- Continue-as-new for unbounded workflows
- Workflow updates (synchronous interaction)
- Interceptors for cross-cutting concerns
- Schedules for recurring workflows

### Data Handling
- Custom data converters
- Payload codecs for encryption
- Search attributes and workflow memo
- Large payload strategies

## Contributing

To update or extend this plugin, edit the skill files and reference documents in the `skills/` directory.
