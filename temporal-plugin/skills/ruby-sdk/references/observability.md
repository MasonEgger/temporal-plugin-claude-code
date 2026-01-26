# Ruby SDK Observability

## Overview

The Ruby SDK provides comprehensive observability features including OpenTelemetry tracing, metrics, and replay-aware logging.

## Replay-Aware Logging

Workflow logging must use `Temporalio::Workflow.logger` to avoid duplicate logs during replay.

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  def execute
    # CORRECT - replay-aware, won't duplicate on replay
    Temporalio::Workflow.logger.info("Processing workflow #{Temporalio::Workflow.info.workflow_id}")

    # WRONG - will log on every replay
    # puts "Processing..."
    # Logger.new(STDOUT).info("Processing...")

    'done'
  end
end
```

### Why Replay-Aware Logging Matters

When a workflow resumes (due to worker restart, crash recovery, or continue-as-new), Temporal replays the workflow history to rebuild state. During replay:
- All workflow code executes again
- Normal logging would produce duplicate log entries
- `Temporalio::Workflow.logger` automatically detects replay and suppresses logs

## OpenTelemetry Tracing

### Basic Setup

```ruby
require 'opentelemetry/api'
require 'opentelemetry/sdk'
require 'temporalio/client'
require 'temporalio/contrib/open_telemetry'

# Assumes my_otel_tracer_provider is a tracer provider created by the user
my_tracer = my_otel_tracer_provider.tracer('my-otel-tracer')

my_client = Temporalio::Client.connect(
  'localhost:7233', 'my-namespace',
  interceptors: [Temporalio::Contrib::OpenTelemetry::TracingInterceptor.new(my_tracer)]
)
```

### Workflow Tracing Considerations

**IMPORTANT**: OpenTelemetry spans cannot be resumed across process boundaries. Workflow spans are immediately started and stopped because workflows may resume on different machines.

```ruby
require 'temporalio/contrib/open_telemetry'

class MyWorkflow < Temporalio::Workflow::Definition
  def execute
    # Create custom span - completes immediately but provides proper parenting
    Temporalio::Contrib::OpenTelemetry::Workflow.with_completed_span(
      'my-custom-span',
      attributes: { 'my-attr' => 'some-value' }
    ) do
      Temporalio::Workflow.execute_activity(
        MyActivity,
        start_to_close_timeout: 300
      )
    end
  end
end
```

### Span Hierarchy Example

Running a workflow might produce this span hierarchy:

```
StartWorkflow:MyWorkflow          <-- created by client outbound
  RunWorkflow:MyWorkflow          <-- created inside workflow on first task
    my-custom-span                <-- created inside workflow by code
      StartActivity:MyActivity    <-- created inside workflow when first called
        RunActivity:MyActivity    <-- created inside activity attempt
    CompleteWorkflow:MyWorkflow   <-- created inside workflow on last task
```

If a worker crashes and the workflow resumes on another worker, spans may not be properly nested under `RunWorkflow` due to OpenTelemetry limitations. However, all spans remain connected to the parent `StartWorkflow` span.

## Custom Metrics

The SDK provides replay-aware metrics via `Temporalio::Workflow.metric_meter`:

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  def initialize
    # Create replay-safe counter with additional attributes
    @my_counter = Temporalio::Workflow.metric_meter
      .create_metric(:counter, 'my-workflow-counter')
      .with_additional_attributes({ 'my-attr' => 'workflows' })
  end

  def execute
    # Record metric - only counted during live execution, not replay
    @my_counter.record(1)
    'done'
  end
end
```

## Metrics Configuration

### Prometheus

```ruby
require 'temporalio/runtime'

Temporalio::Runtime.default = Temporalio::Runtime.new(
  telemetry: Temporalio::Runtime::TelemetryOptions.new(
    metrics: Temporalio::Runtime::MetricsOptions.new(
      prometheus: Temporalio::Runtime::PrometheusMetricsOptions.new(
        bind_address: '127.0.0.1:9000'
      )
    )
  )
)
```

### OpenTelemetry Metrics

```ruby
Temporalio::Runtime.default = Temporalio::Runtime.new(
  telemetry: Temporalio::Runtime::TelemetryOptions.new(
    metrics: Temporalio::Runtime::MetricsOptions.new(
      opentelemetry: Temporalio::Runtime::OpenTelemetryMetricsOptions.new(
        # Configure OpenTelemetry options
      )
    )
  )
)
```

## Best Practices

1. **Always use `Temporalio::Workflow.logger`** for workflow logging to prevent duplicates
2. **Use `with_completed_span`** for custom spans in workflows
3. **Use `Temporalio::Workflow.metric_meter`** for replay-safe metrics in workflows
4. **Check `Temporalio::Workflow.replaying?`** only when absolutely necessary for side effects
5. **Configure tracing early** - set up interceptors before creating workers
6. **Configure runtime before clients** - set `Runtime.default` before connecting clients
