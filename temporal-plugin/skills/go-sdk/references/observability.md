# Go SDK Observability

## Overview

The Go SDK provides comprehensive observability through logging, metrics, tracing, and visibility (Search Attributes).

## Logging

### Workflow Logging (Replay-Safe)

Use `workflow.GetLogger(ctx)` for replay-safe logging:

```go
func MyWorkflow(ctx workflow.Context, input string) (string, error) {
    logger := workflow.GetLogger(ctx)

    // These logs are automatically suppressed during replay
    logger.Info("Workflow started", "input", input)
    logger.Debug("Processing step 1")

    var result string
    err := workflow.ExecuteActivity(ctx, MyActivity, input).Get(ctx, &result)
    if err != nil {
        logger.Error("Activity failed", "error", err)
        return "", err
    }

    logger.Info("Workflow completed", "result", result)
    return result, nil
}
```

The workflow logger:
- Suppresses duplicate logs during replay
- Includes workflow context (workflow ID, run ID, etc.)
- Uses structured key-value logging

### Activity Logging

Use `activity.GetLogger(ctx)` for context-aware activity logging:

```go
func ProcessOrderActivity(ctx context.Context, orderID string) (string, error) {
    logger := activity.GetLogger(ctx)

    logger.Info("Processing order", "orderID", orderID)

    // Perform work...

    logger.Info("Order processed successfully")
    return "completed", nil
}
```

Activity logger includes:
- Activity ID, type, and task queue
- Workflow ID and run ID
- Attempt number (for retries)

### Custom Logger

```go
import (
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/log"
    "github.com/sirupsen/logrus"
    logrusadapter "logur.dev/adapter/logrus"
)

// Use logrus via adapter
logrusLogger := logrus.New()
logrusLogger.SetLevel(logrus.InfoLevel)
logger := log.NewStructuredLogger(logrusadapter.New(logrusLogger))

c, err := client.Dial(client.Options{
    Logger: logger,
})
```

## Metrics

### Enabling Prometheus Metrics

```go
import (
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/contrib/tally"
    tallyprometheus "github.com/uber-go/tally/v4/prometheus"
)

// Create Prometheus reporter
reporter := tallyprometheus.NewReporter(tallyprometheus.Options{})

// Create metrics scope
scope, closer := tally.NewRootScope(tally.ScopeOptions{
    Reporter: reporter,
}, time.Second)
defer closer.Close()

// Create metrics handler
metricsHandler := tally.NewMetricsHandler(scope)

// Apply to client
c, err := client.Dial(client.Options{
    MetricsHandler: metricsHandler,
})
```

### Key SDK Metrics

- `temporal_request` - Client requests to server
- `temporal_workflow_task_execution_latency` - Workflow task processing time
- `temporal_activity_execution_latency` - Activity execution time
- `temporal_workflow_task_replay_latency` - Replay duration

### Custom Metrics in Workflows

```go
func MyWorkflow(ctx workflow.Context) error {
    metricsHandler := workflow.GetMetricsHandler(ctx)

    // Record custom metrics (replay-safe)
    counter := metricsHandler.Counter("my_custom_counter")
    counter.Inc(1)

    gauge := metricsHandler.Gauge("my_custom_gauge")
    gauge.Update(42.0)

    return nil
}
```

## Tracing

### OpenTelemetry Integration

```go
import (
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/contrib/opentelemetry"
    "go.temporal.io/sdk/interceptor"
)

// Create tracing interceptor
tracingInterceptor, err := opentelemetry.NewTracingInterceptor(
    opentelemetry.TracerOptions{},
)
if err != nil {
    log.Fatal(err)
}

// Apply to client
c, err := client.Dial(client.Options{
    Interceptors: []interceptor.ClientInterceptor{tracingInterceptor},
})

// Apply to worker
w := worker.New(c, "my-queue", worker.Options{
    Interceptors: []interceptor.WorkerInterceptor{tracingInterceptor},
})
```

### Datadog Integration

```go
import "go.temporal.io/sdk/contrib/datadog/tracing"

tracingInterceptor, err := tracing.NewTracingInterceptor(tracing.TracerOptions{})
```

## Search Attributes (Visibility)

### Setting Search Attributes at Start

```go
import "go.temporal.io/sdk/temporal"

options := client.StartWorkflowOptions{
    ID:        "order-123",
    TaskQueue: "orders",
    SearchAttributes: temporal.NewSearchAttributes(
        temporal.NewSearchAttributeKeyString("OrderId").ValueSet("123"),
        temporal.NewSearchAttributeKeyString("CustomerType").ValueSet("premium"),
        temporal.NewSearchAttributeKeyFloat64("OrderTotal").ValueSet(99.99),
    ),
}

we, err := c.ExecuteWorkflow(ctx, options, OrderWorkflow, order)
```

### Upserting Search Attributes from Workflow

```go
func OrderWorkflow(ctx workflow.Context, order Order) (string, error) {
    // Update status as workflow progresses
    workflow.UpsertTypedSearchAttributes(ctx,
        temporal.NewSearchAttributeKeyString("OrderStatus").ValueSet("processing"),
    )

    // Process order...

    workflow.UpsertTypedSearchAttributes(ctx,
        temporal.NewSearchAttributeKeyString("OrderStatus").ValueSet("completed"),
    )

    return "done", nil
}
```

### Querying Workflows by Search Attributes

```go
// List workflows using search attributes
iter := c.ListWorkflow(ctx, &workflowservice.ListWorkflowExecutionsRequest{
    Query: `OrderStatus = "processing" AND CustomerType = "premium"`,
})

for iter.HasNext() {
    we, err := iter.Next()
    if err != nil {
        return err
    }
    fmt.Printf("Workflow %s is still processing\n", we.Execution.WorkflowId)
}
```

## Debugging with Event History

### Fetching Workflow History

```go
iter := c.GetWorkflowHistory(ctx, workflowID, runID, false, enums.HISTORY_EVENT_FILTER_TYPE_ALL_EVENT)

for iter.HasNext() {
    event, err := iter.Next()
    if err != nil {
        return err
    }
    fmt.Printf("Event %d: %s\n", event.EventId, event.EventType)
}
```

### Using Temporal CLI

```bash
# Get workflow history
temporal workflow show -w my-workflow-id

# View in JSON format
temporal workflow show -w my-workflow-id --output json
```

## Best Practices

1. Use `workflow.GetLogger()` in workflows, `activity.GetLogger()` in activities
2. Don't use fmt.Println() in workflows - it produces duplicate output on replay
3. Configure metrics for production monitoring
4. Use Search Attributes for business-level visibility
5. Add tracing for distributed debugging
6. Log with structured key-value pairs for easier querying
