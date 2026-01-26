---
name: java-sdk
description: "This skill should be used when the user asks to 'create a Temporal workflow in Java', 'write a Java activity', 'use io.temporal', 'fix Java workflow determinism', 'debug workflow replay', 'Java workflow logging', or mentions 'Temporal Java SDK'. Provides Java-specific patterns, interface design, enterprise integration, and observability guidance."
---

# Temporal Java SDK Best Practices

## Overview

The Temporal Java SDK uses interface-based design with annotations for type-safe workflow definitions. Supports Java 1.8+ with Java 21+ recommended.

## How Temporal Works: History Replay

Understanding how Temporal achieves durable execution is essential for writing correct workflows.

### The Replay Mechanism

When a Worker executes workflow code, it creates **Commands** (requests for operations like starting an Activity or Timer) and sends them to the Temporal Cluster. The Cluster maintains an **Event History** - a durable log of everything that happened during the workflow execution.

**Key insight**: During replay, the Worker re-executes your workflow code but uses the Event History to restore state instead of re-executing Activities. When it encounters an Activity call that has a corresponding `ActivityTaskCompleted` event in history, it returns the stored result instead of scheduling a new execution.

This is why **determinism matters**: The Worker validates that Commands generated during replay match the Events in history. A mismatch causes a non-deterministic error because the Worker cannot reliably restore state.

**Java SDK has no sandbox** - you must ensure determinism through code review and using the safe alternatives documented below.

## Quick Start

```java
// Workflow interface
@WorkflowInterface
public interface GreetingWorkflow {
    @WorkflowMethod
    String getGreeting(String name);
}

// Activity interface
@ActivityInterface
public interface GreetingActivities {
    @ActivityMethod
    String greet(String name);
}

// Implementations
public class GreetingWorkflowImpl implements GreetingWorkflow {
    private final GreetingActivities activities =
        Workflow.newActivityStub(GreetingActivities.class,
            ActivityOptions.newBuilder()
                .setStartToCloseTimeout(Duration.ofMinutes(1))
                .build());

    @Override
    public String getGreeting(String name) {
        return activities.greet(name);
    }
}

public class GreetingActivitiesImpl implements GreetingActivities {
    @Override
    public String greet(String name) {
        return "Hello, " + name + "!";
    }
}

// Worker setup
public class Main {
    public static void main(String[] args) {
        WorkflowServiceStubs service = WorkflowServiceStubs.newLocalServiceStubs();
        WorkflowClient client = WorkflowClient.newInstance(service);
        WorkerFactory factory = WorkerFactory.newInstance(client);
        Worker worker = factory.newWorker("greeting-queue");

        worker.registerWorkflowImplementationTypes(GreetingWorkflowImpl.class);
        worker.registerActivitiesImplementations(new GreetingActivitiesImpl());
        factory.start();
    }
}
```

## Key Concepts

### Workflow Interface
- Annotate with `@WorkflowInterface`
- Use `@WorkflowMethod` for entry point (only ONE allowed)
- Use `@SignalMethod`, `@QueryMethod`, `@UpdateMethod` for handlers

### Activity Interface
- Annotate with `@ActivityInterface`
- Use `@ActivityMethod` for activity methods
- Create stub with `Workflow.newActivityStub()`

### Worker Setup
- Create WorkflowServiceStubs, WorkflowClient, WorkerFactory
- Register workflow implementation types
- Register activity instances

## Determinism Rules

Java SDK has no sandbox. Use code review and testing.

**Safe alternatives:**
- `Workflow.currentTimeMillis()` instead of `System.currentTimeMillis()`
- `Workflow.sleep(Duration)` instead of `Thread.sleep()`
- `Workflow.newRandom()` instead of `new Random()`
- `LinkedHashMap` instead of `HashMap` for deterministic iteration

See `references/determinism.md` for detailed rules.

## Common Pitfalls

1. **Multiple `@WorkflowMethod`** - Only ONE per implementation
2. **Using `Thread.sleep()`** - Use `Workflow.sleep()` instead
3. **HashMap iteration** - Use `LinkedHashMap` for determinism
4. **Blocking in `@WorkflowInit`** - Avoid blocking operations
5. **Missing activity registration** - Register instances, not classes

## Replay-Aware Logging

Use `Workflow.getLogger()` inside Workflows for replay-safe logging:

```java
import io.temporal.workflow.Workflow;
import org.slf4j.Logger;

public class MyWorkflowImpl implements MyWorkflow {
    private static final Logger logger = Workflow.getLogger(MyWorkflowImpl.class);

    @Override
    public String run(String input) {
        // These logs are automatically suppressed during replay
        logger.info("Workflow started with input: {}", input);

        String result = activities.process(input);

        logger.info("Workflow completed with result: {}", result);
        return result;
    }
}
```

## Additional Resources

### Reference Files
- **`references/determinism.md`** - Safe alternatives, LinkedHashMap, GetVersion, WHY determinism matters
- **`references/error-handling.md`** - ApplicationFailure, retry policies, idempotency patterns
- **`references/testing.md`** - TestWorkflowExtension, JUnit 5 patterns
- **`references/patterns.md`** - Signals, queries, child workflows
- **`references/observability.md`** - Replay-aware logging, metrics, OpenTelemetry, debugging
- **`references/advanced-features.md`** - Interceptors, updates, schedules, dynamic handlers
- **`references/data-handling.md`** - Search attributes, workflow memo, data converters
- **`references/versioning.md`** - getVersion API, workflow type versioning, Worker Versioning
