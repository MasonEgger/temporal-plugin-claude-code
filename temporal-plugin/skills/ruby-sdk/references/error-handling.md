# Ruby SDK Error Handling

## Overview

The Ruby SDK uses `Temporalio::Error::ApplicationError` for application-specific errors.

## Application Errors

```ruby
class ValidateActivity < Temporalio::Activity::Definition
  def execute(input)
    unless valid?(input)
      raise Temporalio::Error::ApplicationError.new(
        "Invalid input: #{input}",
        type: 'ValidationError'
      )
    end
    process(input)
  end
end
```

## Non-Retryable Errors

```ruby
raise Temporalio::Error::ApplicationError.new(
  "Credit card permanently declined",
  type: 'PaymentError',
  non_retryable: true
)
```

## Handling Errors in Workflows

```ruby
class OrderWorkflow < Temporalio::Workflow::Definition
  def execute(order)
    result = Temporalio::Workflow.execute_activity(
      ProcessPaymentActivity,
      order,
      schedule_to_close_timeout: 300
    )
    result
  rescue Temporalio::Error::ActivityError => e
    Temporalio::Workflow.logger.error("Payment failed: #{e.message}")

    if e.cause.is_a?(Temporalio::Error::ApplicationError)
      if e.cause.type == 'PaymentDeclined'
        return handle_payment_declined(order)
      end
    end

    raise Temporalio::Error::ApplicationError.new(
      "Order processing failed",
      type: 'OrderError'
    )
  end
end
```

## Retry Policy Configuration

```ruby
Temporalio::Workflow.execute_activity(
  MyActivity,
  arg,
  schedule_to_close_timeout: 600,
  retry_policy: Temporalio::RetryPolicy.new(
    initial_interval: 1,
    backoff_coefficient: 2.0,
    maximum_interval: 60,
    maximum_attempts: 5,
    non_retryable_error_types: ['ValidationError', 'PaymentError']
  )
)
```

## Timeout Configuration

```ruby
Temporalio::Workflow.execute_activity(
  MyActivity,
  arg,
  start_to_close_timeout: 300,       # Single attempt (seconds)
  schedule_to_close_timeout: 1800,   # Including retries
  heartbeat_timeout: 30              # Between heartbeats
)
```

## Activity Cancellation

```ruby
class CancellableActivity < Temporalio::Activity::Definition
  # Disable automatic cancel raise
  activity_cancel_raise false

  def execute(input)
    loop do
      # Check cancellation manually
      if Temporalio::Activity.cancellation.canceled?
        cleanup
        raise Temporalio::Error::CanceledError
      end

      do_work
      Temporalio::Activity.heartbeat
    end
  end
end
```

## Idempotency Patterns

Activities may be retried due to failures or timeouts. Design activities to be idempotent - safe to execute multiple times with the same result.

### Use Idempotency Keys

```ruby
class CreateOrderActivity < Temporalio::Activity::Definition
  def execute(order_id, data)
    # Use order_id as idempotency key - if order exists, return existing
    existing = @db.find_order(order_id)
    return existing.id if existing

    # Create new order
    @db.create_order(order_id, data)
  end
end
```

### Workflow-Level Idempotency

Workflow IDs are natural idempotency keys:

```ruby
# Use deterministic workflow ID based on business entity
handle = client.start_workflow(
  OrderWorkflow,
  order,
  id: "order-#{order[:customer_id]}-#{order[:order_number]}",  # Deterministic
  task_queue: 'orders',
  id_reuse_policy: :reject_duplicate
)
```

### Heartbeat for Progress Tracking

Use heartbeat details to resume from last successful point:

```ruby
class ProcessItemsActivity < Temporalio::Activity::Definition
  def execute(items)
    # Get last processed index from heartbeat
    context = Temporalio::Activity::Context.current
    start_index = context.info.heartbeat_details.first || 0

    items[start_index..].each_with_index do |item, i|
      process_item(item)
      context.heartbeat(start_index + i + 1)  # Record progress
    end
  end
end
```

## Best Practices

1. Use specific error types for different failure modes
2. Set `non_retryable: true` for permanent failures
3. Configure `non_retryable_error_types` in retry policy
4. Log errors before re-raising
5. Handle `ActivityError` to access wrapped exceptions
6. **Design activities to be idempotent** - safe to retry
7. **Use workflow IDs as idempotency keys** for deduplication
8. **Use heartbeat details** to track progress and resume from failures
