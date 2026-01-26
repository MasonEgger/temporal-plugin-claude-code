# Ruby SDK Patterns

## Signals

### WHY: Use signals to send data or commands to a running workflow from external sources
### WHEN:
- **Order approval workflows** - Wait for human approval before proceeding
- **Live configuration updates** - Change workflow behavior without restarting
- **Fire-and-forget communication** - Notify workflow of external events
- **Workflow coordination** - Allow workflows to communicate with each other

**Signals vs Queries vs Updates:**
- Signals: Fire-and-forget, no response, can modify state
- Queries: Read-only, returns data, cannot modify state
- Updates: Synchronous, returns response, can modify state

```ruby
class OrderWorkflow < Temporalio::Workflow::Definition
  workflow_query_attr_reader :status

  workflow_signal
  def approve
    @approved = true
  end

  workflow_signal
  def add_item(item)
    @items << item
  end

  def execute
    @approved = false
    @items = []
    @status = 'pending'

    Temporalio::Workflow.wait_condition { @approved }

    @status = 'approved'
    "Processed #{@items.length} items"
  end
end
```

## Queries

### WHY: Read workflow state without affecting execution - queries are read-only
### WHEN:
- **Progress tracking dashboards** - Display workflow progress to users
- **Status endpoints** - Check workflow state for API responses
- **Debugging** - Inspect internal workflow state
- **Health checks** - Verify workflow is functioning correctly

**Important:** Queries must NOT modify workflow state or have side effects.

```ruby
class StatusWorkflow < Temporalio::Workflow::Definition
  workflow_query
  def get_status
    @status
  end

  workflow_query
  def get_progress
    @progress
  end

  def execute
    @status = 'running'
    @progress = 0

    100.times do |i|
      @progress = i
      Temporalio::Workflow.execute_activity(
        ProcessItemActivity, i,
        schedule_to_close_timeout: 60
      )
    end

    @status = 'completed'
    'done'
  end
end
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

```ruby
class ParentWorkflow < Temporalio::Workflow::Definition
  def execute(orders)
    orders.map do |order|
      Temporalio::Workflow.execute_child_workflow(
        ProcessOrderWorkflow,
        order,
        id: "order-#{order[:id]}",
        # Control what happens to child when parent completes
        parent_close_policy: Temporalio::Workflow::ParentClosePolicy::ABANDON
      )
    end
  end
end
```

## Local Activities

### WHY: Reduce latency for short, lightweight operations by skipping the task queue
### WHEN:
- **Short operations** - Activities completing in milliseconds/seconds
- **High-frequency calls** - When task queue overhead is significant
- **Low-latency requirements** - When you can't afford task queue round-trip

**Tradeoffs:** Local activities don't appear in history until the workflow task completes, and don't benefit from task queue load balancing.

```ruby
class WorkflowWithLocalActivity < Temporalio::Workflow::Definition
  def execute(key)
    # Use local activity for fast, local operations
    result = Temporalio::Workflow.execute_local_activity(
      QuickLookupActivity, key,
      schedule_to_close_timeout: 5
    )
    result
  end
end
```

## Parallel Execution with Futures

### WHY: Execute multiple independent operations concurrently for better throughput
### WHEN:
- **Batch processing** - Process multiple items simultaneously
- **Fan-out patterns** - Distribute work across multiple activities
- **Independent operations** - Operations that don't depend on each other's results

```ruby
class ParallelWorkflow < Temporalio::Workflow::Definition
  def execute(items)
    futures = items.map do |item|
      Temporalio::Workflow::Future.new do
        Temporalio::Workflow.execute_activity(
          ProcessItemActivity, item,
          schedule_to_close_timeout: 300
        )
      end
    end

    # Wait for all
    Temporalio::Workflow::Future.all_of(*futures).wait

    # Collect results
    futures.map(&:result)
  end
end
```

## Continue-as-New

### WHY: Prevent unbounded event history growth in long-running or infinite workflows
### WHEN:
- **Event history approaching 10,000+ events** - Temporal recommends continue-as-new before hitting limits
- **Infinite/long-running workflows** - Polling, subscription, or daemon-style workflows
- **Memory optimization** - Reset workflow state to reduce memory footprint

**Recommendation:** Check history length periodically and continue-as-new around 10,000 events.

```ruby
class LongRunningWorkflow < Temporalio::Workflow::Definition
  def execute(state)
    loop do
      state = process_batch(state)

      return 'done' if state[:complete]

      # Continue-as-new before hitting history limits
      if Temporalio::Workflow.info.history_length > 10_000
        Temporalio::Workflow.continue_as_new(state)
      end
    end
  end
end
```

## Saga Pattern

### WHY: Implement distributed transactions with compensating actions for rollback
### WHEN:
- **Multi-step transactions** - Operations that span multiple services
- **Eventual consistency** - When you can't use traditional ACID transactions
- **Rollback requirements** - When partial failures require undoing previous steps

**Important:** Compensation activities should be idempotent - they may be retried.

```ruby
class SagaWorkflow < Temporalio::Workflow::Definition
  def execute(order)
    compensations = []

    begin
      Temporalio::Workflow.execute_activity(
        ReserveInventoryActivity, order,
        schedule_to_close_timeout: 300
      )
      compensations << -> { release_inventory(order) }

      Temporalio::Workflow.execute_activity(
        ChargePaymentActivity, order,
        schedule_to_close_timeout: 300
      )
      compensations << -> { refund_payment(order) }

      Temporalio::Workflow.execute_activity(
        ShipOrderActivity, order,
        schedule_to_close_timeout: 300
      )

      'Order completed'
    rescue StandardError => e
      Temporalio::Workflow.logger.error("Order failed: #{e.message}")

      # Run compensations in reverse order
      compensations.reverse_each do |compensate|
        begin
          compensate.call
        rescue StandardError => comp_err
          Temporalio::Workflow.logger.error("Compensation failed: #{comp_err.message}")
        end
      end

      raise
    end
  end

  private

  def release_inventory(order)
    Temporalio::Workflow.execute_activity(
      ReleaseInventoryActivity, order,
      schedule_to_close_timeout: 300
    )
  end

  def refund_payment(order)
    Temporalio::Workflow.execute_activity(
      RefundPaymentActivity, order,
      schedule_to_close_timeout: 300
    )
  end
end
```

## Versioning with Patching

### WHY: Safely deploy workflow code changes without breaking running workflows
### WHEN:
- **Adding new steps** - New code path for new executions, old path for replays
- **Changing activity calls** - Modify activity parameters or logic
- **Deprecating features** - Gradually remove old code paths

### Four-Stage Migration Pattern

**Stage 1: Initial Code** - Original workflow

**Stage 2: Patched (Both Paths)** - Use `patched` to branch between old and new

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  def execute
    if Temporalio::Workflow.patched(:new_greeting)
      # New implementation for new workflows
      Temporalio::Workflow.execute_activity(
        NewGreetActivity,
        schedule_to_close_timeout: 60
      )
    else
      # Old implementation for replaying workflows
      Temporalio::Workflow.execute_activity(
        OldGreetActivity,
        schedule_to_close_timeout: 60
      )
    end
  end
end
```

**Stage 3: Deprecated** - After all old workflows complete, remove old path

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  def execute
    # Mark patch as deprecated - old workflows still replay correctly
    Temporalio::Workflow.deprecate_patch(:new_greeting)

    # Only new implementation remains
    Temporalio::Workflow.execute_activity(
      NewGreetActivity,
      schedule_to_close_timeout: 60
    )
  end
end
```

**Stage 4: Complete** - After all Stage 2 workflows complete, remove deprecate_patch call

## Timers

### WHY: Schedule delays or deadlines within workflows in a durable way
### WHEN:
- **Scheduled delays** - Wait for a specific duration before continuing
- **Deadlines** - Set timeouts for operations
- **Reminder patterns** - Schedule future notifications

```ruby
class TimerWorkflow < Temporalio::Workflow::Definition
  def execute
    # Simple sleep (30 seconds)
    Temporalio::Workflow.sleep(30)

    # Or with duration
    Temporalio::Workflow.sleep(5 * 60)  # 5 minutes

    'Timer fired'
  end
end
```

## Rails Integration

```ruby
# config/initializers/temporal.rb
Rails.application.config.to_prepare do
  # Eager load workflow/activity classes
  Dir[Rails.root.join('app/workflows/**/*.rb')].each { |f| require f }
  Dir[Rails.root.join('app/activities/**/*.rb')].each { |f| require f }
end

# Handle lazy loading issues
# config/application.rb
config.eager_load = true

# Or explicitly require in workflow files
require_relative '../activities/my_activity'
```

## Workflow Class Methods DSL

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  workflow_name 'CustomWorkflowName'     # Override registered name
  workflow_dynamic                        # Handle unregistered workflows
  workflow_raw_args                       # Receive RawValue args

  workflow_query_attr_reader :my_state    # Query + attr_reader combined

  workflow_init
  def initialize(arg)
    @arg = arg
  end

  workflow_signal
  def my_signal(data)
    @data = data
  end

  workflow_query
  def my_query
    @data
  end

  workflow_update
  def my_update(data)
    old = @data
    @data = data
    old
  end

  def execute
    # Workflow logic
  end
end
```

## Forking Warning

Temporal objects (runtimes, clients, workers) cannot be used across forks. Create objects inside the fork.

```ruby
# WRONG
client = Temporalio::Client.connect(...)
fork do
  client.execute_workflow(...)  # Will fail
end

# CORRECT
fork do
  client = Temporalio::Client.connect(...)
  client.execute_workflow(...)
end
```
