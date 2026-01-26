---
name: ruby-sdk
description: "This skill should be used when the user asks to 'create a Temporal workflow in Ruby', 'write a Ruby activity', 'use temporalio gem', 'fix Ruby workflow determinism', 'debug workflow replay', 'Ruby workflow logging', or mentions 'Temporal Ruby SDK' or 'Rails Temporal'. Provides Ruby-specific patterns, Fiber scheduler constraints, and Rails integration guidance."
---

# Temporal Ruby SDK Best Practices

## Overview

The Temporal Ruby SDK uses class-based workflows with a custom deterministic Fiber scheduler. Requires Ruby 3.2+. Fibers only fully supported on Ruby 3.3+.

## How Temporal Works: History Replay

Understanding how Temporal achieves durable execution is essential for writing correct workflows.

### The Replay Mechanism

When a Worker executes workflow code, it creates **Commands** (requests for operations like starting an Activity or Timer) and sends them to the Temporal Cluster. The Cluster maintains an **Event History** - a durable log of everything that happened during the workflow execution.

**Key insight**: During replay, the Worker re-executes your workflow code but uses the Event History to restore state instead of re-executing Activities. When it encounters an Activity call that has a corresponding `ActivityTaskCompleted` event in history, it returns the stored result instead of scheduling a new execution.

This is why **determinism matters**: The Worker validates that Commands generated during replay match the Events in history. A mismatch causes a non-deterministic error because the Worker cannot reliably restore state.

**Ruby SDK uses a custom Fiber scheduler** with illegal call tracing to detect non-deterministic operations at runtime. This provides some protection, but understanding replay helps write correct code.

## Quick Start

```ruby
require 'temporalio/client'
require 'temporalio/worker'

# Activity
class GreetActivity < Temporalio::Activity::Definition
  def execute(name)
    "Hello, #{name}!"
  end
end

# Workflow
class GreetingWorkflow < Temporalio::Workflow::Definition
  def execute(name)
    Temporalio::Workflow.execute_activity(
      GreetActivity,
      name,
      schedule_to_close_timeout: 300
    )
  end
end

# Worker
client = Temporalio::Client.connect('localhost:7233', 'default')
worker = Temporalio::Worker.new(
  client:,
  task_queue: 'greeting-queue',
  workflows: [GreetingWorkflow],
  activities: [GreetActivity]
)
worker.run(shutdown_signals: ['SIGINT'])
```

## Key Concepts

### Workflow Definition
- Extend `Temporalio::Workflow::Definition`
- Implement `execute` method
- Use `workflow_signal`, `workflow_query` class methods for handlers

### Activity Definition
- Extend `Temporalio::Activity::Definition`
- Implement `execute` method
- Can use `activity_executor :fiber` for fiber-based execution

### Worker Setup
- Connect client, create Worker with workflows and activities
- Use `run(shutdown_signals:)` for graceful shutdown

## Determinism Rules

Ruby SDK uses a custom deterministic Fiber scheduler with illegal call tracing.

**Safe alternatives:**
- `Temporalio::Workflow.now` instead of `Time.now`
- `Temporalio::Workflow.sleep(seconds)` instead of `Kernel.sleep`
- `Temporalio::Workflow.random` instead of `Random.rand`
- `Temporalio::Workflow::Future` instead of threads

**Illegal by default:**
- `Logger`, `sleep`, `Timeout.timeout`
- `Queue`, `Mutex` (use workflow versions)

See `references/determinism.md` for detailed rules.

## Replay-Aware Logging

Use `Temporalio::Workflow.logger` inside Workflows for replay-safe logging that avoids duplicate messages:

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  def execute(input)
    # These logs are automatically suppressed during replay
    Temporalio::Workflow.logger.info("Workflow started with input: #{input}")

    result = Temporalio::Workflow.execute_activity(
      ProcessActivity,
      input,
      start_to_close_timeout: 300
    )

    Temporalio::Workflow.logger.info("Workflow completed with result: #{result}")
    result
  end
end
```

For activities, use `Temporalio::Activity.logger` for context-aware logging:

```ruby
class ProcessActivity < Temporalio::Activity::Definition
  def execute(input)
    Temporalio::Activity.logger.info("Processing: #{input}")
    "Processed: #{input}"
  end
end
```

## Common Pitfalls

1. **Using `Time.now` in workflows** - Use `Temporalio::Workflow.now`
2. **Using `Kernel.sleep`** - Use `Temporalio::Workflow.sleep`
3. **Using threads** - Use `Temporalio::Workflow::Future`
4. **Fibers on Ruby < 3.3** - Limited support
5. **Objects across forks** - Cannot use Temporal objects after fork
6. **Using `puts` in workflows** - Use `Temporalio::Workflow.logger` instead

## Additional Resources

### Reference Files
- **`references/determinism.md`** - Fiber scheduler, history replay, illegal calls, escaping scheduler
- **`references/error-handling.md`** - ApplicationError, retry configuration, idempotency patterns
- **`references/testing.md`** - WorkflowEnvironment, time-skipping, RSpec, replay testing
- **`references/patterns.md`** - Signals, queries, futures, Rails integration
- **`references/observability.md`** - OpenTelemetry tracing, replay-aware logging, metrics
- **`references/advanced-features.md`** - Updates, interceptors, search attributes, workflow DSL
- **`references/data-handling.md`** - Data converters, encryption, ActiveModel support
- **`references/versioning.md`** - Patching API, workflow type versioning, Worker Versioning
