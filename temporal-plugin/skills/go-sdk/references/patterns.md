# Go SDK Patterns

## Signals

### WHY: Use signals to send data or commands to a running workflow from external sources
### WHEN:
- **Order approval workflows** - Wait for human approval before proceeding
- **Live configuration updates** - Change workflow behavior without restarting
- **External event notifications** - Notify workflow of events from other systems
- **Workflow coordination** - Allow workflows to communicate with each other

```go
func SignalWorkflow(ctx workflow.Context) error {
    var approved bool
    signalChan := workflow.GetSignalChannel(ctx, "approve")

    // Wait for signal
    signalChan.Receive(ctx, &approved)

    if approved {
        return workflow.ExecuteActivity(ctx, ProcessActivity).Get(ctx, nil)
    }
    return errors.New("not approved")
}

// With selector for multiple signals
func MultiSignalWorkflow(ctx workflow.Context) error {
    selector := workflow.NewSelector(ctx)

    approveChan := workflow.GetSignalChannel(ctx, "approve")
    rejectChan := workflow.GetSignalChannel(ctx, "reject")

    var result string
    selector.AddReceive(approveChan, func(c workflow.ReceiveChannel, more bool) {
        c.Receive(ctx, nil)
        result = "approved"
    })
    selector.AddReceive(rejectChan, func(c workflow.ReceiveChannel, more bool) {
        c.Receive(ctx, nil)
        result = "rejected"
    })

    selector.Select(ctx)
    return nil
}
```

## Signal-with-Start

### WHY: Atomically start a workflow and send it a signal in a single operation
### WHEN:
- **Idempotent workflow triggering** - Ensure signal reaches workflow whether it exists or not
- **Event-driven workflow initialization** - Start workflow with initial event data
- **Race condition prevention** - Avoid window where workflow exists but hasn't received signal

```go
// From client code - starts workflow if not running, then sends signal
run, err := c.SignalWithStartWorkflow(
    ctx,
    "order-123",           // workflow ID
    "add-item",            // signal name
    itemData,              // signal arg
    client.StartWorkflowOptions{
        TaskQueue: "orders",
    },
    OrderWorkflow,         // workflow function
    orderInput,            // workflow args
)
```

## Queries

### WHY: Read workflow state without affecting execution - queries are read-only
### WHEN:
- **Progress tracking dashboards** - Display workflow progress to users
- **Status checks** - Check if workflow is ready for next step
- **Debugging** - Inspect internal workflow state
- **Health checks** - Verify workflow is functioning correctly

**Important:** Queries must NOT modify workflow state or have side effects.

```go
func QueryableWorkflow(ctx workflow.Context) error {
    var status string = "running"
    var progress int = 0

    // Register query handlers
    workflow.SetQueryHandler(ctx, "status", func() (string, error) {
        return status, nil
    })

    workflow.SetQueryHandler(ctx, "progress", func() (int, error) {
        return progress, nil
    })

    // Workflow logic
    for i := 0; i < 100; i++ {
        progress = i
        workflow.ExecuteActivity(ctx, ProcessItem, i).Get(ctx, nil)
    }

    status = "completed"
    return nil
}
```

## Child Workflows

### WHY: Break complex workflows into smaller, manageable units with independent failure domains
### WHEN:
- **Failure domain isolation** - Child failures don't automatically fail parent
- **Different retry policies** - Each child can have its own retry configuration
- **Reusability** - Share workflow logic across multiple parent workflows
- **Independent scaling** - Child workflows can run on different task queues
- **History size management** - Each child has its own event history

**Use activities instead when:** Operation is short-lived, doesn't need its own failure domain, or doesn't need independent retry policies.

```go
func ParentWorkflow(ctx workflow.Context, orders []Order) error {
    for _, order := range orders {
        cwo := workflow.ChildWorkflowOptions{
            WorkflowID: "order-" + order.ID,
            // ParentClosePolicy controls what happens to child when parent completes
            ParentClosePolicy: enumspb.PARENT_CLOSE_POLICY_ABANDON,
        }
        ctx := workflow.WithChildOptions(ctx, cwo)

        err := workflow.ExecuteChildWorkflow(ctx, ProcessOrderWorkflow, order).Get(ctx, nil)
        if err != nil {
            return err
        }
    }
    return nil
}
```

## External Workflow Signaling

### WHY: Send signals to workflows that are not children of the current workflow
### WHEN:
- **Cross-workflow coordination** - Coordinate between independent workflows
- **Event broadcasting** - Notify multiple unrelated workflows of an event
- **Workflow-to-workflow communication** - Allow workflows to communicate without a parent-child relationship

```go
func CoordinatorWorkflow(ctx workflow.Context, targetWorkflowID string) error {
    // Signal an external workflow (not a child)
    err := workflow.SignalExternalWorkflow(ctx, targetWorkflowID, "", "data-ready", dataPayload).Get(ctx, nil)
    if err != nil {
        return err
    }
    return nil
}
```

## Parallel Execution

### WHY: Execute multiple independent operations concurrently for better throughput
### WHEN:
- **Batch processing** - Process multiple items simultaneously
- **Fan-out patterns** - Distribute work across multiple activities
- **Independent operations** - Operations that don't depend on each other's results

```go
func ParallelWorkflow(ctx workflow.Context, items []string) ([]string, error) {
    ao := workflow.ActivityOptions{StartToCloseTimeout: time.Minute}
    ctx = workflow.WithActivityOptions(ctx, ao)

    var futures []workflow.Future
    for _, item := range items {
        future := workflow.ExecuteActivity(ctx, ProcessItem, item)
        futures = append(futures, future)
    }

    var results []string
    for _, future := range futures {
        var result string
        if err := future.Get(ctx, &result); err != nil {
            return nil, err
        }
        results = append(results, result)
    }
    return results, nil
}
```

## Continue-as-New

### WHY: Prevent unbounded event history growth in long-running or infinite workflows
### WHEN:
- **Event history approaching 10,000+ events** - Temporal recommends continue-as-new before hitting limits
- **Infinite/long-running workflows** - Polling, subscription, or daemon-style workflows
- **Memory optimization** - Reset workflow state to reduce memory footprint

**Recommendation:** Check history length periodically and continue-as-new around 10,000 events.

```go
func LongRunningWorkflow(ctx workflow.Context, state State) error {
    for {
        state = processNextBatch(ctx, state)

        if state.IsComplete {
            return nil
        }

        // Check history size - continue-as-new before hitting limits
        info := workflow.GetInfo(ctx)
        if info.GetCurrentHistoryLength() > 10000 {
            return workflow.NewContinueAsNewError(ctx, LongRunningWorkflow, state)
        }
    }
}
```

## Saga Pattern

### WHY: Implement distributed transactions with compensating actions for rollback
### WHEN:
- **Multi-step transactions** - Operations that span multiple services
- **Eventual consistency** - When you can't use traditional ACID transactions
- **Rollback requirements** - When partial failures require undoing previous steps

**Important:** Compensation activities should be idempotent - they may be retried.

```go
func SagaWorkflow(ctx workflow.Context, order Order) error {
    ao := workflow.ActivityOptions{StartToCloseTimeout: time.Minute * 5}
    ctx = workflow.WithActivityOptions(ctx, ao)

    var compensations []func(workflow.Context) error

    // Reserve inventory
    err := workflow.ExecuteActivity(ctx, ReserveInventory, order).Get(ctx, nil)
    if err != nil {
        return err
    }
    compensations = append(compensations, func(ctx workflow.Context) error {
        return workflow.ExecuteActivity(ctx, ReleaseInventory, order).Get(ctx, nil)
    })

    // Charge payment
    err = workflow.ExecuteActivity(ctx, ChargePayment, order).Get(ctx, nil)
    if err != nil {
        return runCompensations(ctx, compensations)
    }
    compensations = append(compensations, func(ctx workflow.Context) error {
        return workflow.ExecuteActivity(ctx, RefundPayment, order).Get(ctx, nil)
    })

    // Ship order
    err = workflow.ExecuteActivity(ctx, ShipOrder, order).Get(ctx, nil)
    if err != nil {
        return runCompensations(ctx, compensations)
    }

    return nil
}

func runCompensations(ctx workflow.Context, compensations []func(workflow.Context) error) error {
    // Run compensations in reverse order
    for i := len(compensations) - 1; i >= 0; i-- {
        if err := compensations[i](ctx); err != nil {
            workflow.GetLogger(ctx).Error("Compensation failed", "error", err)
            // Continue with other compensations even if one fails
        }
    }
    return errors.New("saga failed")
}
```

## Timers

### WHY: Schedule delays or deadlines within workflows in a durable way
### WHEN:
- **Scheduled delays** - Wait for a specific duration before continuing
- **Deadlines** - Set timeouts for operations
- **Reminder patterns** - Schedule future notifications
- **Rate limiting** - Pace workflow operations

```go
func TimerWorkflow(ctx workflow.Context) error {
    // Simple sleep
    workflow.Sleep(ctx, time.Hour)

    // Timer with selector for cancellation
    timer := workflow.NewTimer(ctx, time.Hour)
    cancelChan := workflow.GetSignalChannel(ctx, "cancel")

    selector := workflow.NewSelector(ctx)
    selector.AddFuture(timer, func(f workflow.Future) {
        // Timer fired
    })
    selector.AddReceive(cancelChan, func(c workflow.ReceiveChannel, more bool) {
        // Cancelled
    })
    selector.Select(ctx)

    return nil
}
```

## Cancellation Handling

### WHY: Gracefully handle workflow cancellation requests and perform cleanup
### WHEN:
- **Graceful shutdown** - Clean up resources when workflow is cancelled
- **External cancellation** - Respond to cancellation requests from clients
- **Cleanup activities** - Run cleanup logic even after cancellation

**Critical:** Use `workflow.NewDisconnectedContext()` to execute activities after cancellation.

```go
func CancellableWorkflow(ctx workflow.Context) error {
    ao := workflow.ActivityOptions{
        StartToCloseTimeout: 5 * time.Minute,
        HeartbeatTimeout:    5 * time.Second,
        WaitForCancellation: true, // Wait for activities to handle cancellation
    }
    ctx = workflow.WithActivityOptions(ctx, ao)

    defer func() {
        // Only run cleanup if workflow was cancelled
        if !errors.Is(ctx.Err(), workflow.ErrCanceled) {
            return
        }

        // Create disconnected context for cleanup - this context won't be cancelled
        newCtx, _ := workflow.NewDisconnectedContext(ctx)
        err := workflow.ExecuteActivity(newCtx, CleanupActivity).Get(newCtx, nil)
        if err != nil {
            workflow.GetLogger(ctx).Error("Cleanup failed", "error", err)
        }
    }()

    // Main workflow logic
    err := workflow.ExecuteActivity(ctx, LongRunningActivity).Get(ctx, nil)
    return err
}
```

## Heartbeating Long-Running Activities

### WHY: Report progress and detect worker failures for long-running activities
### WHEN:
- **Long-running operations** - Activities that take minutes or hours
- **Progress reporting** - Track activity progress from workflow
- **Fast failure detection** - Detect worker crashes quickly

```go
func LongRunningActivity(ctx context.Context, items []Item) error {
    for i, item := range items {
        // Process item...
        processItem(item)

        // Record heartbeat with progress
        activity.RecordHeartbeat(ctx, i)

        // Check for cancellation
        if ctx.Err() != nil {
            return ctx.Err()
        }
    }
    return nil
}
```

## Deterministic Map Iteration

### WHY: Iterate over maps deterministically for workflow replay compatibility
### WHEN:
- **Iterating over maps in workflows** - Go map iteration order is non-deterministic

```go
func WorkflowWithMap(ctx workflow.Context, data map[string]int) error {
    // Use DeterministicKeys for deterministic iteration order
    keys := workflow.DeterministicKeys(data)
    for _, key := range keys {
        value := data[key]
        // Process key-value pair...
    }
    return nil
}
```
