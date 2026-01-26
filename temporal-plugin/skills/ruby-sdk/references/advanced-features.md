# Ruby SDK Advanced Features

## Workflow Updates

Updates allow synchronous, validated mutations to workflow state with return values.

```ruby
class OrderWorkflow < Temporalio::Workflow::Definition
  workflow_query_attr_reader :total

  def initialize
    @items = []
    @total = 0
  end

  def execute
    Temporalio::Workflow.wait_condition { @items.any? }
    @total
  end

  workflow_update
  def add_item(item, price)
    @items << item
    @total += price
    @items.length
  end

  workflow_update_validator :add_item
  def validate_add_item(item, price)
    raise Temporalio::Error::ApplicationError, 'Item cannot be empty' if item.nil? || item.empty?
    raise Temporalio::Error::ApplicationError, 'Price must be positive' if price <= 0
  end
end

# Client usage
count = handle.execute_update(OrderWorkflow.add_item, 'Widget', 9.99)
```

## Cancellation Patterns

### Activity Cancellation Types

Control how activities respond to workflow cancellation:

```ruby
# TRY_CANCEL (default): Send cancel request, report activity cancelled immediately
Temporalio::Workflow.execute_activity(
  MyActivity, arg,
  schedule_to_close_timeout: 300,
  cancellation_type: Temporalio::Activity::CancellationType::TRY_CANCEL
)

# WAIT_CANCELLATION_COMPLETED: Wait for activity to acknowledge cancellation
Temporalio::Workflow.execute_activity(
  MyActivity, arg,
  schedule_to_close_timeout: 300,
  cancellation_type: Temporalio::Activity::CancellationType::WAIT_CANCELLATION_COMPLETED
)

# ABANDON: Don't request cancellation, just report as cancelled
Temporalio::Workflow.execute_activity(
  MyActivity, arg,
  schedule_to_close_timeout: 300,
  cancellation_type: Temporalio::Activity::CancellationType::ABANDON
)
```

### Custom Cancellation Tokens

Create custom cancellation scopes for fine-grained control:

```ruby
class CancellableWorkflow < Temporalio::Workflow::Definition
  def execute
    # Create a custom cancellation token
    cancellation, cancel_proc = Temporalio::Cancellation.new

    # Start activity with custom cancellation
    future = Temporalio::Workflow::Future.new do
      Temporalio::Workflow.execute_activity(
        LongRunningActivity,
        schedule_to_close_timeout: 3600,
        cancellation: cancellation
      )
    end

    # Cancel after some condition
    Temporalio::Workflow.sleep(60)
    cancel_proc.call(reason: 'Timeout exceeded')

    'Done'
  end
end
```

### Shielding Critical Sections

Protect critical code from cancellation:

```ruby
class WorkflowWithCleanup < Temporalio::Workflow::Definition
  def execute
    begin
      Temporalio::Workflow.execute_activity(
        MainActivity,
        schedule_to_close_timeout: 300
      )
    ensure
      # Shield cleanup from cancellation
      Temporalio::Workflow.cancellation.shield do
        # This runs even if workflow is cancelled
        Temporalio::Workflow.execute_activity(
          CleanupActivity,
          schedule_to_close_timeout: 60
        )
      end
    end
  end
end
```

## Temporal Cloud Connection

### mTLS Authentication

```ruby
client = Temporalio::Client.connect(
  'your-namespace.tmprl.cloud:7233',
  'your-namespace',
  tls: Temporalio::Client::Connection::TLSOptions.new(
    client_cert: File.read('/path/to/client.pem'),
    client_private_key: File.read('/path/to/client.key'),
    # Optional: Custom CA cert
    server_root_ca_cert: File.read('/path/to/ca.pem')
  )
)
```

### API Key Authentication

```ruby
client = Temporalio::Client.connect(
  'your-namespace.tmprl.cloud:7233',
  'your-namespace',
  api_key: ENV['TEMPORAL_API_KEY'],
  tls: Temporalio::Client::Connection::TLSOptions.new
)
```

## Schedules

Create recurring workflow executions:

```ruby
# Create a schedule
schedule_id = 'daily-report'
client.create_schedule(
  schedule_id,
  Temporalio::Client::Schedule.new(
    action: Temporalio::Client::Schedule::Action::StartWorkflow.new(
      DailyReportWorkflow,
      id: 'daily-report',
      task_queue: 'reports'
    ),
    spec: Temporalio::Client::Schedule::Spec.new(
      intervals: [
        Temporalio::Client::Schedule::Spec::Interval.new(every: 24 * 60 * 60) # 24 hours
      ]
    )
  )
)

# Or with cron expressions
client.create_schedule(
  'cron-job',
  Temporalio::Client::Schedule.new(
    action: Temporalio::Client::Schedule::Action::StartWorkflow.new(
      CronWorkflow,
      task_queue: 'cron'
    ),
    spec: Temporalio::Client::Schedule::Spec.new(
      cron_expressions: ['0 9 * * MON-FRI']  # 9 AM weekdays
    )
  )
)

# Manage schedules
schedule = client.get_schedule_handle(schedule_id)
schedule.pause('Maintenance window')
schedule.unpause
schedule.trigger  # Run immediately
schedule.delete
```

## Dynamic Workflows, Signals, and Queries

Handle unregistered workflow types or dynamic message routing:

```ruby
class DynamicWorkflow < Temporalio::Workflow::Definition
  workflow_dynamic
  workflow_raw_args

  def execute(*args)
    workflow_type = Temporalio::Workflow.info.workflow_type

    case workflow_type
    when 'TypeA'
      handle_type_a(args)
    when 'TypeB'
      handle_type_b(args)
    else
      raise Temporalio::Error::ApplicationError, "Unknown type: #{workflow_type}"
    end
  end
end
```

### Dynamic Signal Handlers

```ruby
class FlexibleWorkflow < Temporalio::Workflow::Definition
  def execute
    # Set up dynamic signal handler at runtime
    Temporalio::Workflow.signal_handlers[nil] = proc do |signal_name, *args|
      Temporalio::Workflow.logger.info("Received signal: #{signal_name}")
      # Handle dynamically
    end

    Temporalio::Workflow.wait_condition { @done }
  end
end
```

## Interceptors

Interceptors provide cross-cutting concerns like logging, metrics, and context propagation.

```ruby
class LoggingInterceptor
  include Temporalio::Client::Interceptor
  include Temporalio::Worker::Interceptor

  def intercept_client(next_interceptor)
    ClientOutbound.new(next_interceptor)
  end

  def intercept_workflow(next_interceptor)
    WorkflowInbound.new(next_interceptor)
  end

  class ClientOutbound < Temporalio::Client::Interceptor::Outbound
    def start_workflow(input)
      puts "Starting workflow: #{input.workflow}"
      super
    end
  end

  class WorkflowInbound < Temporalio::Worker::Interceptor::WorkflowInbound
    def execute(input)
      Temporalio::Workflow.logger.info('Executing workflow')
      super
    end
  end
end

# Usage
client = Temporalio::Client.connect(
  'localhost:7233', 'default',
  interceptors: [LoggingInterceptor.new]
)
```

## Memo and Search Attributes

### Memo (Unindexed Metadata)

```ruby
# Set memo on start
handle = client.start_workflow(
  MyWorkflow,
  id: 'my-workflow',
  task_queue: 'my-queue',
  memo: {
    'description' => 'Important workflow',
    'priority' => 5
  }
)

# Update memo in workflow
class MyWorkflow < Temporalio::Workflow::Definition
  def execute
    Temporalio::Workflow.upsert_memo({ 'status' => 'processing' })
    # ...
  end
end

# Read memo
description = Temporalio::Workflow.memo['description']
```

### Search Attributes (Indexed, Queryable)

```ruby
# Set on start
handle = client.start_workflow(
  MyWorkflow,
  id: 'my-workflow',
  task_queue: 'my-queue',
  search_attributes: Temporalio::SearchAttributes.new(
    'CustomStatus' => Temporalio::SearchAttributes::Key.new('CustomStatus', :keyword).value_set('pending'),
    'Priority' => Temporalio::SearchAttributes::Key.new('Priority', :int).value_set(5)
  )
)

# Update in workflow
class MyWorkflow < Temporalio::Workflow::Definition
  def execute
    status_key = Temporalio::SearchAttributes::Key.new('CustomStatus', :keyword)

    Temporalio::Workflow.upsert_search_attributes(
      status_key.value_set('processing')
    )

    # ...
  end
end

# Query workflows by search attributes
workflows = client.list_workflows("CustomStatus = 'pending'")
```

## External Workflow Handles

Signal or cancel workflows from within another workflow:

```ruby
class CoordinatorWorkflow < Temporalio::Workflow::Definition
  def execute(target_workflow_id)
    # Get handle to external workflow
    external_handle = Temporalio::Workflow.external_workflow_handle(target_workflow_id)

    # Signal it
    external_handle.signal('notify', 'Hello from other workflow')

    # Or cancel it
    # external_handle.cancel
  end
end
```

## Advanced Workflow Safety: Escaping the Scheduler

For advanced cases where you need to bypass workflow safety:

```ruby
# Bypass durable scheduler for local operations (e.g., debugging)
Temporalio::Workflow::Unsafe.durable_scheduler_disabled do
  puts "Debug output"  # Local stdout
end

# Enable I/O wait (use sparingly)
Temporalio::Workflow::Unsafe.io_enabled do
  # I/O operations
end

# Disable illegal call tracing
Temporalio::Workflow::Unsafe.illegal_call_tracing_disabled do
  # Known-safe calls that would otherwise be flagged
end
```

**WARNING**: Use these escape hatches sparingly and only when absolutely necessary.

## Best Practices

1. **Use validators for updates** to reject invalid input before it's stored in history
2. **Prefer typed search attributes** for queryable workflow metadata
3. **Use interceptors** for cross-cutting concerns instead of modifying each workflow
4. **External handles** are for cross-workflow communication within the same Temporal cluster
5. **Use `workflow_query_attr_reader`** for simple queryable state
6. **Shield cleanup code** from cancellation to ensure resources are released
7. **Use mTLS** for production Temporal Cloud connections
