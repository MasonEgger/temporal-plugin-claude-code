# Ruby SDK Determinism

## Overview

The Ruby SDK uses a custom deterministic Fiber scheduler and illegal call tracing to enforce determinism.

## Why Determinism Matters: History Replay

When a workflow resumes after being suspended (worker restart, crash, continue-as-new), Temporal **replays** the workflow's event history to rebuild the workflow's state. During replay:

1. Temporal loads the workflow's complete event history
2. The workflow code re-executes from the beginning
3. Instead of actually performing operations (activities, timers), Temporal matches them against history
4. The workflow state is reconstructed to where it left off

**If workflow code produces different commands during replay than it did originally, the workflow fails with a non-determinism error.**

Example of what happens during replay:
```
Original execution:       Replay:
1. Start workflow         1. Start workflow (match history)
2. Execute Activity A     2. Execute Activity A (match - return cached result)
3. Execute Activity B     3. Execute Activity B (match - return cached result)
4. Timer 5 min           4. Timer 5 min (match - skip)
5. (worker crashes)      5. (state rebuilt, continue from here)
```

## Safe Alternatives

| Forbidden | Safe Alternative |
|-----------|------------------|
| `Time.now` | `Temporalio::Workflow.now` |
| `Kernel.sleep` | `Temporalio::Workflow.sleep(seconds)` |
| `Random.rand` | `Temporalio::Workflow.random.rand` |
| `Thread.new` | `Temporalio::Workflow::Future.new` |
| `Mutex.new` | `Temporalio::Workflow::Mutex.new` |
| `Queue.new` | `Temporalio::Workflow::Queue.new` |

## Illegal Calls by Default

These operations are traced and raise errors in workflows:
- `Logger`
- `sleep`
- `Timeout.timeout`
- `Queue`, `Mutex`
- Standard library I/O operations

## Escaping the Scheduler

```ruby
# Bypass durable scheduler for local operations
Temporalio::Workflow::Unsafe.durable_scheduler_disabled do
  # Local stdout, logging, etc.
  puts "Debug output"
end

# Enable I/O wait (use sparingly)
Temporalio::Workflow::Unsafe.io_enabled do
  # I/O operations
end

# Disable illegal call tracing
Temporalio::Workflow::Unsafe.illegal_call_tracing_disabled do
  # Known-safe calls that would otherwise be flagged
end
```

## Workflow Futures for Concurrency

```ruby
class ParallelWorkflow < Temporalio::Workflow::Definition
  def execute
    fut1 = Temporalio::Workflow::Future.new do
      Temporalio::Workflow.execute_activity(Activity1, schedule_to_close_timeout: 300)
    end

    fut2 = Temporalio::Workflow::Future.new do
      Temporalio::Workflow.execute_activity(Activity2, schedule_to_close_timeout: 300)
    end

    # Wait for all
    Temporalio::Workflow::Future.all_of(fut1, fut2).wait

    # Or wait for first
    # Temporalio::Workflow::Future.any_of(fut1, fut2).wait

    [fut1.result, fut2.result]
  end
end
```

## Workflow-Safe Concurrency Primitives

```ruby
# Workflow-safe mutex
mutex = Temporalio::Workflow::Mutex.new
mutex.synchronize do
  # Protected code
end

# Workflow-safe queue
queue = Temporalio::Workflow::Queue.new
queue.push(item)
item = queue.pop

# Sized queue
sized_queue = Temporalio::Workflow::SizedQueue.new(10)
```

## Deterministic Iteration

```ruby
# WRONG - non-deterministic order
hash.each { |k, v| process(k, v) }

# CORRECT - sort for deterministic order
hash.sort.each { |k, v| process(k, v) }
```

## Activity Executor Types

```ruby
class MyActivity < Temporalio::Activity::Definition
  # Default: thread pool executor
  # activity_executor :thread_pool

  # Fiber executor (Ruby 3.3+)
  activity_executor :fiber

  def execute(input)
    # Activity logic
  end
end
```

## Fiber Compatibility Note

Due to Ruby implementation details, fibers (and the `async` gem) are only fully supported on Ruby 3.3+.

## Best Practices

1. Use `Temporalio::Workflow.*` methods for time, sleep, random
2. Use `Temporalio::Workflow::Future` for concurrency
3. Sort collections before iteration
4. Use escape hatches sparingly
5. Test with replay to catch non-determinism
