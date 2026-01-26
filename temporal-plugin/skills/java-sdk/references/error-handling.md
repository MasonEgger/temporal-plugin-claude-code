# Java SDK Error Handling

## Overview

The Java SDK uses `ApplicationFailure` for application errors with support for custom exception types.

## Application Failures

```java
import io.temporal.failure.ApplicationFailure;

@Override
public void validateActivity(String input) {
    if (!isValid(input)) {
        throw ApplicationFailure.newFailure(
            "Invalid input: " + input,
            "ValidationError"
        );
    }
}
```

## Non-Retryable Failures

```java
throw ApplicationFailure.newNonRetryableFailure(
    "Credit card permanently declined",
    "PaymentError"
);
```

## Custom Exception Shortcut

```java
// Define custom exception
public class ValidationException extends RuntimeException {
    public ValidationException(String message) {
        super(message);
    }
}

// Throw in activity - automatically wrapped as ApplicationFailure
@Override
public void validateActivity(String input) {
    if (!isValid(input)) {
        throw new ValidationException("Invalid: " + input);
    }
}
```

## Handling Errors in Workflows

```java
@Override
public String processOrder(Order order) {
    try {
        return activities.processPayment(order);
    } catch (ActivityFailure e) {
        logger.error("Payment failed", e);
        if (e.getCause() instanceof ApplicationFailure) {
            ApplicationFailure appFailure = (ApplicationFailure) e.getCause();
            if ("PaymentDeclined".equals(appFailure.getType())) {
                return handlePaymentDeclined(order);
            }
        }
        throw e;
    }
}
```

## Retry Policy Configuration

```java
ActivityOptions options = ActivityOptions.newBuilder()
    .setStartToCloseTimeout(Duration.ofMinutes(10))
    .setRetryOptions(RetryOptions.newBuilder()
        .setInitialInterval(Duration.ofSeconds(1))
        .setBackoffCoefficient(2.0)
        .setMaximumInterval(Duration.ofMinutes(1))
        .setMaximumAttempts(5)
        .setDoNotRetry("ValidationError", "PaymentError")
        .build())
    .build();
```

## Timeout Configuration

```java
ActivityOptions options = ActivityOptions.newBuilder()
    .setStartToCloseTimeout(Duration.ofMinutes(5))       // Single attempt
    .setScheduleToCloseTimeout(Duration.ofMinutes(30))   // Including retries
    .setHeartbeatTimeout(Duration.ofSeconds(30))         // Between heartbeats
    .build();
```

## Idempotency Patterns

When Temporal retries an activity, it may re-execute code that has external side effects. Use idempotency keys to ensure operations are safe to retry.

### Building Idempotency Keys

Use the activity execution context to build unique, stable keys:

```java
import io.temporal.activity.Activity;
import io.temporal.activity.ActivityExecutionContext;

public class PaymentActivitiesImpl implements PaymentActivities {
    @Override
    public String chargePayment(String customerId, double amount) {
        ActivityExecutionContext ctx = Activity.getExecutionContext();

        // Build idempotency key from workflow context
        // This key is stable across retries of the same activity
        String idempotencyKey = String.format("%s-%s",
            ctx.getInfo().getWorkflowId(),
            ctx.getInfo().getActivityId()
        );

        // Payment service uses key to deduplicate
        PaymentResult result = paymentService.charge(
            customerId,
            amount,
            idempotencyKey
        );

        return result.getTransactionId();
    }
}
```

### Available Context Fields

```java
ActivityExecutionContext ctx = Activity.getExecutionContext();
ActivityInfo info = ctx.getInfo();

// Useful for idempotency keys:
info.getWorkflowId();      // Unique workflow identifier
info.getActivityId();      // Unique within workflow execution
info.getAttempt();         // Current retry attempt (1, 2, 3...)
info.getWorkflowRunId();   // Unique per workflow run

// Example: Include attempt if you want separate keys per retry
String keyWithAttempt = String.format("%s-%s-%d",
    info.getWorkflowId(),
    info.getActivityId(),
    info.getAttempt()
);
```

### External Service Best Practices

1. **Always use idempotency keys** for operations with side effects (payments, emails, database writes)
2. **Let the external service deduplicate** - don't try to track state yourself
3. **Use workflow-scoped keys** (`workflowId + activityId`) for most cases
4. **Use attempt-scoped keys** only when each retry should be a distinct operation

## Best Practices

1. Use specific error types for different failure modes
2. Use `newNonRetryableFailure` for permanent failures
3. Configure `setDoNotRetry` in retry options
4. Log errors with context before re-throwing
5. Use custom exceptions for cleaner code
6. Use idempotency keys for activities with external side effects
