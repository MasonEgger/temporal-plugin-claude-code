# Go SDK Error Handling

## Overview

The Go SDK uses `temporal.ApplicationError` for application-specific errors with support for error types and non-retryable marking.

## Application Errors

```go
import "go.temporal.io/sdk/temporal"

func ValidateActivity(ctx context.Context, input string) error {
    if !isValid(input) {
        return temporal.NewApplicationError(
            "Invalid input: " + input,
            "ValidationError",
            nil,  // cause
            nil,  // details
        )
    }
    return nil
}
```

## Non-Retryable Errors

```go
func PermanentFailureActivity(ctx context.Context) error {
    return temporal.NewNonRetryableApplicationError(
        "Credit card permanently declined",
        "PaymentError",
        nil,
        nil,
    )
}
```

## Handling Errors in Workflows

```go
func WorkflowWithErrorHandling(ctx workflow.Context) error {
    err := workflow.ExecuteActivity(ctx, RiskyActivity).Get(ctx, nil)
    if err != nil {
        var appErr *temporal.ApplicationError
        if errors.As(err, &appErr) {
            logger := workflow.GetLogger(ctx)
            logger.Error("Activity failed",
                "type", appErr.Type(),
                "message", appErr.Message(),
            )

            if appErr.Type() == "ValidationError" {
                // Handle specific error type
                return handleValidationError(ctx, appErr)
            }
        }
        return err
    }
    return nil
}
```

## Retry Policy Configuration

```go
ao := workflow.ActivityOptions{
    StartToCloseTimeout: time.Minute * 10,
    RetryPolicy: &temporal.RetryPolicy{
        InitialInterval:    time.Second,
        BackoffCoefficient: 2.0,
        MaximumInterval:    time.Minute,
        MaximumAttempts:    5,
        NonRetryableErrorTypes: []string{
            "ValidationError",
            "PaymentError",
        },
    },
}
ctx = workflow.WithActivityOptions(ctx, ao)
```

## Timeout Configuration

```go
ao := workflow.ActivityOptions{
    StartToCloseTimeout:    time.Minute * 5,   // Single attempt
    ScheduleToCloseTimeout: time.Minute * 30,  // Including retries
    HeartbeatTimeout:       time.Second * 30,  // Between heartbeats
}
```

## Workflow Failure

```go
func MyWorkflow(ctx workflow.Context) error {
    if someCondition {
        return temporal.NewApplicationError(
            "Cannot process",
            "BusinessError",
        )
    }
    return nil
}
```

## Panic vs Return Error

```go
// Returning error fails the workflow execution
func FailWorkflow(ctx workflow.Context) error {
    return errors.New("workflow failed")
}

// Panic only fails the current workflow task (will be retried)
func PanicWorkflow(ctx workflow.Context) error {
    panic("temporary issue")
}
```

## Idempotency Patterns

When Activities interact with external systems, making them idempotent ensures correctness during retries and replay.

### Using Workflow IDs as Idempotency Keys

```go
func ChargePaymentActivity(ctx context.Context, orderID string, amount float64) (string, error) {
    // Use orderID as idempotency key with payment provider
    result, err := paymentAPI.Charge(ctx, &ChargeRequest{
        Amount:         amount,
        IdempotencyKey: fmt.Sprintf("order-%s", orderID),
    })
    if err != nil {
        return "", err
    }
    return result.TransactionID, nil
}
```

### Tracking Operation Status in Workflow State

```go
func OrderWorkflow(ctx workflow.Context, order Order) (string, error) {
    ao := workflow.ActivityOptions{StartToCloseTimeout: 5 * time.Minute}
    ctx = workflow.WithActivityOptions(ctx, ao)

    var state struct {
        PaymentCompleted bool
        TransactionID    string
    }

    // Check if payment already completed (e.g., after continue-as-new)
    if !state.PaymentCompleted {
        err := workflow.ExecuteActivity(ctx, ChargePaymentActivity, order.ID, order.Total).
            Get(ctx, &state.TransactionID)
        if err != nil {
            return "", err
        }
        state.PaymentCompleted = true
    }

    // Continue with order processing...
    return state.TransactionID, nil
}
```

### Designing Idempotent Activities

1. **Use unique identifiers** as idempotency keys (workflow ID, activity ID, or business ID)
2. **Check before acting**: Query external system state before making changes
3. **Make operations repeatable**: Ensure calling twice produces the same result
4. **Record outcomes**: Store transaction IDs or results for verification

```go
func CreateUserActivity(ctx context.Context, req CreateUserRequest) (*User, error) {
    // Check if user already exists (idempotent pattern)
    existing, err := userService.GetByEmail(ctx, req.Email)
    if err == nil && existing != nil {
        return existing, nil  // Already created, return existing
    }

    // Create new user
    return userService.Create(ctx, req)
}
```

## Best Practices

1. Use specific error types for different failure modes
2. Use `NonRetryableApplicationError` for permanent failures
3. Configure `NonRetryableErrorTypes` in retry policy
4. Log errors with context before handling
5. Use `errors.As()` to check error types
6. Design activities to be idempotent for safe retries
