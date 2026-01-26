# Go SDK Determinism

## Overview

The Go SDK has no sandbox. Determinism must be enforced through code review and static analysis tools.

## Why Determinism Matters: History Replay

Temporal achieves durability through **history replay**. Understanding this mechanism is key to writing correct Workflow code.

### How Replay Works

1. **Initial Execution**: When your Workflow runs for the first time, the SDK records Commands (like "schedule activity") to the Event History stored by Temporal Server.

2. **Recovery/Continuation**: When a Worker restarts, loses connectivity, or picks up a Workflow Task, it must restore the Workflow's state by replaying the code from the beginning.

3. **Command Matching**: During replay, the SDK re-executes your Workflow code but doesn't actually run Activities again. Instead, it compares the Commands your code generates against the Events in history.

4. **Non-determinism Detection**: If your code generates different Commands than what's in history (e.g., different Activity name, different order), the Workflow Task fails.

### Example: Why time.Now() Breaks Replay

```go
// BAD - Non-deterministic
func BadWorkflow(ctx workflow.Context) error {
    if time.Now().Hour() < 12 {  // Different value on replay!
        workflow.ExecuteActivity(ctx, MorningActivity).Get(ctx, nil)
    } else {
        workflow.ExecuteActivity(ctx, AfternoonActivity).Get(ctx, nil)
    }
    return nil
}
```

If this runs at 11:59 AM initially and replays at 12:01 PM, it will try to schedule a different Activity, causing a non-determinism error.

```go
// GOOD - Deterministic
func GoodWorkflow(ctx workflow.Context) error {
    if workflow.Now(ctx).Hour() < 12 {  // Consistent during replay
        workflow.ExecuteActivity(ctx, MorningActivity).Get(ctx, nil)
    } else {
        workflow.ExecuteActivity(ctx, AfternoonActivity).Get(ctx, nil)
    }
    return nil
}
```

### Testing Replay Compatibility

Use the test environment to verify your code changes are compatible:

```go
func TestReplayCompatibility(t *testing.T) {
    replayer := worker.NewWorkflowReplayer()
    replayer.RegisterWorkflow(MyWorkflow)

    // Load a history from a JSON file
    err := replayer.ReplayWorkflowHistoryFromJSONFile(
        nil,
        "testdata/workflow_history.json",
    )
    require.NoError(t, err)
}
```

Or fetch history from a running cluster:

```go
func TestReplayFromCluster(t *testing.T) {
    c, _ := client.Dial(client.Options{})

    replayer := worker.NewWorkflowReplayer()
    replayer.RegisterWorkflow(MyWorkflow)

    // Replay using history from server
    err := replayer.ReplayWorkflowHistory(
        nil,
        getWorkflowHistory(c, "workflow-id", "run-id"),
    )
    require.NoError(t, err)
}
```

## Safe Alternatives

| Forbidden | Safe Alternative |
|-----------|------------------|
| `time.Now()` | `workflow.Now(ctx)` |
| `time.Sleep()` | `workflow.Sleep(ctx, duration)` |
| `go func()` | `workflow.Go(ctx, func(ctx workflow.Context))` |
| Go channels | `workflow.Channel` |
| `select` | `workflow.Selector` |
| `rand.Int()` | `workflow.SideEffect()` |
| `uuid.New()` | `workflow.SideEffect()` |

## Static Analysis Tool

```bash
# Install
go install go.temporal.io/sdk/contrib/tools/workflowcheck@latest

# Run on your code
workflowcheck ./...
```

## workflow.Go() for Concurrency

```go
func MyWorkflow(ctx workflow.Context) error {
    var result1, result2 string

    workflow.Go(ctx, func(ctx workflow.Context) {
        workflow.ExecuteActivity(ctx, Activity1).Get(ctx, &result1)
    })

    workflow.Go(ctx, func(ctx workflow.Context) {
        workflow.ExecuteActivity(ctx, Activity2).Get(ctx, &result2)
    })

    // Wait for both
    workflow.Await(ctx, func() bool {
        return result1 != "" && result2 != ""
    })

    return nil
}
```

## workflow.Channel

```go
func ChannelWorkflow(ctx workflow.Context) error {
    ch := workflow.NewChannel(ctx)

    workflow.Go(ctx, func(ctx workflow.Context) {
        ch.Send(ctx, "data")
    })

    var value string
    ch.Receive(ctx, &value)

    return nil
}
```

## workflow.Selector

```go
func SelectorWorkflow(ctx workflow.Context) error {
    selector := workflow.NewSelector(ctx)

    ch := workflow.GetSignalChannel(ctx, "my-signal")
    selector.AddReceive(ch, func(c workflow.ReceiveChannel, more bool) {
        var signal string
        c.Receive(ctx, &signal)
        // Handle signal
    })

    future := workflow.ExecuteActivity(ctx, MyActivity)
    selector.AddFuture(future, func(f workflow.Future) {
        var result string
        f.Get(ctx, &result)
        // Handle result
    })

    selector.Select(ctx)
    return nil
}
```

## SideEffect for Non-Deterministic Values

```go
func WorkflowWithUUID(ctx workflow.Context) (string, error) {
    var uuid string
    workflow.SideEffect(ctx, func(ctx workflow.Context) interface{} {
        return generateUUID()
    }).Get(&uuid)

    return uuid, nil
}
```

## Map Iteration Warning

```go
// WRONG - non-deterministic order
for k, v := range myMap {
    process(k, v)
}

// CORRECT - sort keys first
keys := make([]string, 0, len(myMap))
for k := range myMap {
    keys = append(keys, k)
}
sort.Strings(keys)
for _, k := range keys {
    process(k, myMap[k])
}
```

## Versioning with GetVersion

```go
func VersionedWorkflow(ctx workflow.Context) error {
    v := workflow.GetVersion(ctx, "change-id", workflow.DefaultVersion, 1)

    if v == workflow.DefaultVersion {
        return oldImplementation(ctx)
    }
    return newImplementation(ctx)
}
```

## Best Practices

1. Run `workflowcheck` in CI pipeline
2. Never use `go` keyword in workflows
3. Never use native Go channels in workflows
4. Sort map keys before iteration
5. Use `workflow.SideEffect()` for random/UUID values
6. Use `workflow.GetVersion()` for code changes
