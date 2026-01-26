# Go SDK Advanced Features

## Local Activities

### WHY: Reduce latency for short, lightweight operations by skipping the task queue
### WHEN:
- **Short operations** - Activities completing in milliseconds/seconds
- **High-frequency calls** - When task queue overhead is significant
- **Low-latency requirements** - When you can't afford task queue round-trip

**Tradeoffs:** Local activities don't appear in history until the workflow task completes, and don't benefit from task queue load balancing.

```go
func WorkflowWithLocalActivity(ctx workflow.Context) error {
    lao := workflow.LocalActivityOptions{
        ScheduleToCloseTimeout: 5 * time.Second,
    }
    ctx = workflow.WithLocalActivityOptions(ctx, lao)

    var result string
    err := workflow.ExecuteLocalActivity(ctx, LocalDataLookup, "key").Get(ctx, &result)
    if err != nil {
        return err
    }
    return nil
}

// Local activity - same signature as regular activity
func LocalDataLookup(ctx context.Context, key string) (string, error) {
    // Short, local operation - e.g., cache lookup, simple computation
    return lookupFromCache(key), nil
}
```

## Async Activity Completion

### WHY: Complete activities from external systems (webhooks, human tasks, external services)
### WHEN:
- **Human approval workflows** - Wait for human to complete task externally
- **Webhook-based integrations** - External service calls back when done
- **Long-polling external systems** - Activity starts work, external system finishes it

```go
// Activity that starts async work
func AsyncActivity(ctx context.Context, taskID string) (string, error) {
    // Get task token for later completion
    info := activity.GetInfo(ctx)
    taskToken := info.TaskToken

    // Store task token for external service to use
    storeTaskToken(taskID, taskToken)

    // Signal external system to start work
    startExternalWork(taskID)

    // Return ErrResultPending - activity stays open until completed externally
    return "", activity.ErrResultPending
}

// External service completes the activity using the client
func CompleteActivityExternally(taskToken []byte, result string) error {
    c, _ := client.Dial(client.Options{})
    defer c.Close()

    return c.CompleteActivity(context.Background(), taskToken, result, nil)
}

// Or complete by ID instead of token
func CompleteActivityByID(workflowID, runID, activityID, result string) error {
    c, _ := client.Dial(client.Options{})
    defer c.Close()

    return c.CompleteActivityByID(context.Background(),
        "default", workflowID, runID, activityID, result, nil)
}
```

## slog Integration (Go 1.21+)

### WHY: Use Go's standard structured logging with Temporal
### WHEN:
- **Go 1.21+ projects** - Native structured logging support
- **Existing slog infrastructure** - Integrate Temporal with your logging setup

```go
import (
    "log/slog"
    "go.temporal.io/sdk/log"
)

// Create a Temporal logger from slog
slogger := slog.Default()
temporalLogger := log.NewStructuredLogger(slogger)

// Use with client
c, _ := client.Dial(client.Options{
    Logger: temporalLogger,
})

// Use with worker
w := worker.New(c, "my-queue", worker.Options{
    Logger: temporalLogger,
})
```

## Continue-as-New

Use continue-as-new to prevent unbounded history growth in long-running workflows.

```go
func BatchProcessingWorkflow(ctx workflow.Context, state ProcessingState) (string, error) {
    ao := workflow.ActivityOptions{StartToCloseTimeout: 5 * time.Minute}
    ctx = workflow.WithActivityOptions(ctx, ao)

    for !state.IsComplete {
        // Process next batch
        err := workflow.ExecuteActivity(ctx, ProcessBatchActivity, state).Get(ctx, &state)
        if err != nil {
            return "", err
        }

        // Check history size and continue-as-new if needed
        info := workflow.GetInfo(ctx)
        if info.GetCurrentHistoryLength() > 10000 {
            return "", workflow.NewContinueAsNewError(ctx, BatchProcessingWorkflow, state)
        }
    }

    return "completed", nil
}
```

### Continue-as-New with Options

```go
// Continue with modified options
return "", workflow.NewContinueAsNewError(
    ctx,
    BatchProcessingWorkflow,
    newState,
    workflow.WithWorkflowRunTimeout(time.Hour*24),
    workflow.WithMemo(map[string]interface{}{
        "lastProcessed": itemID,
    }),
)
```

## Workflow Updates

Updates allow synchronous interaction with running workflows.

### Defining Update Handlers

```go
func OrderWorkflow(ctx workflow.Context, order Order) (string, error) {
    var items []string

    // Register update handler
    err := workflow.SetUpdateHandler(ctx, "addItem", func(ctx workflow.Context, item string) (int, error) {
        items = append(items, item)
        return len(items), nil
    })
    if err != nil {
        return "", err
    }

    // Register update handler with validator
    err = workflow.SetUpdateHandlerWithOptions(ctx, "addItemValidated",
        func(ctx workflow.Context, item string) (int, error) {
            items = append(items, item)
            return len(items), nil
        },
        workflow.UpdateHandlerOptions{
            Validator: func(ctx workflow.Context, item string) error {
                if item == "" {
                    return errors.New("item cannot be empty")
                }
                if len(items) >= 100 {
                    return errors.New("order is full")
                }
                return nil
            },
        },
    )

    // Wait for completion signal
    workflow.GetSignalChannel(ctx, "complete").Receive(ctx, nil)

    return fmt.Sprintf("Order with %d items completed", len(items)), nil
}
```

### Calling Updates from Client

```go
handle, err := c.GetWorkflowHandle(ctx, "order-123")

// Execute update and wait for result
var count int
err = handle.UpdateWorkflow(ctx, "addItem", client.UpdateWorkflowOptions{}, "new-item").Get(ctx, &count)
if err != nil {
    return err
}
fmt.Printf("Order now has %d items\n", count)
```

## Schedules

Create recurring workflow executions.

```go
import "go.temporal.io/sdk/client"

// Create a schedule
scheduleID := "daily-report"
handle, err := c.ScheduleClient().Create(ctx, client.ScheduleOptions{
    ID: scheduleID,
    Spec: client.ScheduleSpec{
        Intervals: []client.ScheduleIntervalSpec{
            {Every: 24 * time.Hour},
        },
    },
    Action: &client.ScheduleWorkflowAction{
        ID:        "daily-report",
        Workflow:  DailyReportWorkflow,
        TaskQueue: "reports",
    },
})

// Manage schedules
handle, _ = c.ScheduleClient().GetHandle(ctx, scheduleID)
handle.Pause(ctx, client.SchedulePauseOptions{Note: "Maintenance window"})
handle.Unpause(ctx, client.ScheduleUnpauseOptions{})
handle.Trigger(ctx, client.ScheduleTriggerOptions{})  // Run immediately
handle.Delete(ctx)
```

## Worker Sessions

Sessions ensure activities run on the same worker for resource affinity.

```go
func FileProcessingWorkflow(ctx workflow.Context, files []string) error {
    // Create session - all activities will run on the same worker
    sessionOpts := &workflow.SessionOptions{
        CreationTimeout:  time.Minute,
        ExecutionTimeout: time.Hour,
    }

    sessionCtx, err := workflow.CreateSession(ctx, sessionOpts)
    if err != nil {
        return err
    }
    defer workflow.CompleteSession(sessionCtx)

    // Download file (runs on session worker)
    var localPath string
    err = workflow.ExecuteActivity(sessionCtx, DownloadFileActivity, files[0]).Get(sessionCtx, &localPath)
    if err != nil {
        return err
    }

    // Process file (runs on same worker where file was downloaded)
    err = workflow.ExecuteActivity(sessionCtx, ProcessFileActivity, localPath).Get(sessionCtx, nil)
    if err != nil {
        return err
    }

    return nil
}
```

## Interceptors

Interceptors allow cross-cutting concerns like logging, metrics, and auth.

### Creating a Custom Interceptor

```go
import (
    "go.temporal.io/sdk/interceptor"
    "go.temporal.io/sdk/workflow"
)

type LoggingInterceptor struct {
    interceptor.WorkerInterceptorBase
}

func (i *LoggingInterceptor) InterceptActivity(
    ctx context.Context,
    next interceptor.ActivityInboundInterceptor,
) interceptor.ActivityInboundInterceptor {
    return &loggingActivityInterceptor{next}
}

type loggingActivityInterceptor struct {
    interceptor.ActivityInboundInterceptorBase
}

func (i *loggingActivityInterceptor) Execute(
    ctx context.Context,
    in *interceptor.ExecuteActivityInput,
) (interface{}, error) {
    logger := activity.GetLogger(ctx)
    logger.Info("Activity starting")

    result, err := i.Next.Execute(ctx, in)

    if err != nil {
        logger.Error("Activity failed", "error", err)
    } else {
        logger.Info("Activity completed")
    }
    return result, err
}

// Apply to worker
w := worker.New(c, "my-queue", worker.Options{
    Interceptors: []interceptor.WorkerInterceptor{&LoggingInterceptor{}},
})
```

## Dynamic Workflows and Activities

Handle workflows/activities not known at compile time.

### Dynamic Workflow Registration

```go
func DynamicWorkflowHandler(ctx workflow.Context, args ...interface{}) (interface{}, error) {
    workflowType := workflow.GetInfo(ctx).WorkflowType.Name

    // Route based on type
    switch workflowType {
    case "order-workflow":
        return handleOrderWorkflow(ctx, args)
    case "refund-workflow":
        return handleRefundWorkflow(ctx, args)
    default:
        return nil, fmt.Errorf("unknown workflow type: %s", workflowType)
    }
}

// Register as dynamic handler
w.RegisterWorkflowWithOptions(DynamicWorkflowHandler, workflow.RegisterOptions{
    Name: "",  // Empty name means dynamic
})
```

### Dynamic Activity Registration

```go
func DynamicActivityHandler(ctx context.Context, args ...interface{}) (interface{}, error) {
    info := activity.GetInfo(ctx)
    activityType := info.ActivityType.Name

    // Route based on type
    switch activityType {
    case "process-payment":
        return processPayment(ctx, args)
    default:
        return nil, fmt.Errorf("unknown activity type: %s", activityType)
    }
}

// Register as dynamic handler
w.RegisterActivityWithOptions(DynamicActivityHandler, activity.RegisterOptions{
    Name: "",  // Empty name means dynamic
})
```

## Worker Tuning

Configure worker performance settings.

```go
w := worker.New(c, "my-queue", worker.Options{
    // Workflow task concurrency
    MaxConcurrentWorkflowTaskExecutionSize: 100,

    // Activity task concurrency
    MaxConcurrentActivityExecutionSize: 100,

    // Local activity concurrency
    MaxConcurrentLocalActivityExecutionSize: 100,

    // Session worker options (for file processing etc.)
    MaxConcurrentSessionExecutionSize: 1000,

    // Graceful stop timeout
    WorkerStopTimeout: 30 * time.Second,
})
```

## Workflow Info and Metadata

Access workflow metadata from within workflows.

```go
func MyWorkflow(ctx workflow.Context) error {
    info := workflow.GetInfo(ctx)

    workflowID := info.WorkflowExecution.ID
    runID := info.WorkflowExecution.RunID
    taskQueue := info.TaskQueueName
    namespace := info.Namespace
    attempt := info.Attempt
    historyLength := info.GetCurrentHistoryLength()

    workflow.GetLogger(ctx).Info("Workflow info",
        "workflowID", workflowID,
        "attempt", attempt,
        "historyLength", historyLength,
    )

    return nil
}
```
