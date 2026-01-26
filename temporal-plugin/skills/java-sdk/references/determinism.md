# Java SDK Determinism

## Overview

The Java SDK has no sandbox. Determinism must be enforced through code review and testing.

## Why Determinism Matters

Understanding WHY determinism is required helps you write correct workflows.

### The Replay Problem

Consider this workflow:

```java
@Override
public String badWorkflow() {
    String result = activities.importData();

    // WRONG - Non-deterministic!
    if (new Random().nextDouble() > 0.5) {
        Workflow.sleep(Duration.ofMinutes(30));
    }

    return activities.sendReport();
}
```

**First execution:**
1. `importData()` runs, Worker sends `ScheduleActivityTask` command
2. `Random.nextDouble()` returns 0.3, sleep is skipped
3. `sendReport()` runs, Worker sends another `ScheduleActivityTask` command

**Replay (Worker restarts):**
1. Worker re-executes code, sees `importData()` call
2. History has `ActivityTaskCompleted` - returns stored result (no re-execution)
3. `Random.nextDouble()` returns 0.8 this time - Worker sends `StartTimer` command
4. **MISMATCH!** History expects `ScheduleActivityTask` for sendReport, but got `StartTimer`
5. **Non-deterministic error** - Workflow cannot continue

### The Rule

**During replay, your workflow code must generate the same Commands in the same sequence given the same input.**

This is why `Workflow.newRandom()` exists - it returns the same sequence during replay.

## Safe Alternatives

| Forbidden | Safe Alternative |
|-----------|------------------|
| `System.currentTimeMillis()` | `Workflow.currentTimeMillis()` |
| `new Date()` | `new Date(Workflow.currentTimeMillis())` |
| `Thread.sleep()` | `Workflow.sleep(Duration)` |
| `new Random()` | `Workflow.newRandom()` |
| `UUID.randomUUID()` | `Workflow.randomUUID()` |

## HashMap vs LinkedHashMap

```java
// WRONG - non-deterministic iteration order
Map<String, String> map = new HashMap<>();
for (Map.Entry<String, String> entry : map.entrySet()) {
    process(entry);
}

// CORRECT - deterministic iteration order
Map<String, String> map = new LinkedHashMap<>();
for (Map.Entry<String, String> entry : map.entrySet()) {
    process(entry);
}
```

## Versioning with GetVersion

```java
@Override
public String processOrder(Order order) {
    int version = Workflow.getVersion("order-processing", Workflow.DEFAULT_VERSION, 1);

    if (version == Workflow.DEFAULT_VERSION) {
        // Old implementation
        return oldProcessOrder(order);
    } else {
        // New implementation (version 1)
        return newProcessOrder(order);
    }
}
```

## SideEffect for Non-Deterministic Values

```java
String uuid = Workflow.sideEffect(String.class, () -> UUID.randomUUID().toString());
```

## Forbidden Operations

- Direct threading (`new Thread()`, `ExecutorService`)
- I/O operations (network, filesystem)
- `System.currentTimeMillis()`, `new Date()`
- `Thread.sleep()`
- `new Random()`
- `HashMap` iteration (use `LinkedHashMap`)

## Best Practices

1. Use `Workflow.*` methods for time, sleep, random
2. Use `LinkedHashMap` instead of `HashMap`
3. Use `Workflow.getVersion()` for code changes
4. Test with replay to catch non-determinism
5. Keep workflows focused on orchestration
