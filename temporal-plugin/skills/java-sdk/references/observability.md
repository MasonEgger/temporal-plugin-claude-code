# Java SDK Observability

## Overview

The Java SDK provides comprehensive observability through logging, metrics, tracing, and visibility (Search Attributes).

## Logging

### Workflow Logging (Replay-Safe)

Use `Workflow.getLogger()` for replay-safe logging:

```java
import io.temporal.workflow.Workflow;
import org.slf4j.Logger;

public class MyWorkflowImpl implements MyWorkflow {
    private static final Logger logger = Workflow.getLogger(MyWorkflowImpl.class);

    @Override
    public String run(String input) {
        // These logs are automatically suppressed during replay
        logger.info("Workflow started with input: {}", input);

        String result = activities.process(input);

        logger.info("Workflow completed with result: {}", result);
        return result;
    }
}
```

The workflow logger:
- Suppresses duplicate logs during replay
- Includes workflow context (workflow ID, run ID, etc.)
- Uses SLF4J interface

### Activity Logging

Use standard SLF4J logging in activities:

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import io.temporal.activity.Activity;

public class MyActivitiesImpl implements MyActivities {
    private static final Logger logger = LoggerFactory.getLogger(MyActivitiesImpl.class);

    @Override
    public String process(String input) {
        logger.info("Processing input: {}", input);

        // Get activity context for additional info
        var info = Activity.getExecutionContext().getInfo();
        logger.info("Activity attempt: {}, WorkflowId: {}",
            info.getAttempt(), info.getWorkflowId());

        return "processed: " + input;
    }
}
```

### Custom Logger Configuration

```java
import io.temporal.client.WorkflowClientOptions;
import io.temporal.serviceclient.WorkflowServiceStubsOptions;

// Configure logging via SLF4J binding (logback, log4j2, etc.)
// Example logback.xml configuration:
/*
<configuration>
    <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>

    <logger name="io.temporal" level="INFO"/>

    <root level="INFO">
        <appender-ref ref="STDOUT"/>
    </root>
</configuration>
*/
```

## Metrics

### Enabling Micrometer Metrics

```java
import io.temporal.client.WorkflowClient;
import io.temporal.client.WorkflowClientOptions;
import io.temporal.serviceclient.WorkflowServiceStubs;
import io.temporal.serviceclient.WorkflowServiceStubsOptions;
import io.micrometer.prometheus.PrometheusConfig;
import io.micrometer.prometheus.PrometheusMeterRegistry;
import io.temporal.common.reporter.MicrometerClientStatsReporter;

// Create Prometheus registry
PrometheusMeterRegistry prometheusRegistry =
    new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);

// Create metrics reporter
MicrometerClientStatsReporter reporter =
    new MicrometerClientStatsReporter(prometheusRegistry);

// Configure service stubs with metrics
WorkflowServiceStubsOptions stubsOptions = WorkflowServiceStubsOptions.newBuilder()
    .setMetricsScope(reporter)
    .build();

WorkflowServiceStubs service = WorkflowServiceStubs.newServiceStubs(stubsOptions);
WorkflowClient client = WorkflowClient.newInstance(service);
```

### Key SDK Metrics

- `temporal_request` - Client requests to server
- `temporal_workflow_task_execution_latency` - Workflow task processing time
- `temporal_activity_execution_latency` - Activity execution time
- `temporal_workflow_task_replay_latency` - Replay duration

### Custom Metrics in Workflows

```java
import io.temporal.workflow.Workflow;
import io.micrometer.core.instrument.Counter;

public class MyWorkflowImpl implements MyWorkflow {
    @Override
    public void run() {
        // Access metrics scope from workflow (replay-safe)
        var scope = Workflow.getMetricsScope();

        // Record custom metrics
        Counter counter = scope.counter("my_custom_counter");
        counter.increment();
    }
}
```

## Tracing

### OpenTelemetry Integration

```java
import io.temporal.opentracing.OpenTracingClientInterceptor;
import io.temporal.opentracing.OpenTracingWorkerInterceptor;
import io.temporal.opentracing.OpenTracingOptions;
import io.opentracing.Tracer;
import io.opentracing.util.GlobalTracer;

// Configure OpenTracing tracer (e.g., Jaeger)
Tracer tracer = /* your tracer implementation */;
GlobalTracer.registerIfAbsent(tracer);

// Create tracing options
OpenTracingOptions tracingOptions = OpenTracingOptions.newBuilder()
    .setTracer(tracer)
    .build();

// Apply to client
WorkflowClientOptions clientOptions = WorkflowClientOptions.newBuilder()
    .setInterceptors(new OpenTracingClientInterceptor(tracingOptions))
    .build();

// Apply to worker
WorkerFactoryOptions factoryOptions = WorkerFactoryOptions.newBuilder()
    .setWorkerInterceptors(new OpenTracingWorkerInterceptor(tracingOptions))
    .build();
```

### OpenTelemetry (Modern Approach)

```java
import io.temporal.opentelemetry.OpenTelemetryOptions;
import io.opentelemetry.api.OpenTelemetry;

OpenTelemetry otel = /* your OpenTelemetry instance */;

OpenTelemetryOptions otelOptions = OpenTelemetryOptions.newBuilder()
    .setOpenTelemetry(otel)
    .build();

// Apply interceptors similar to OpenTracing
```

## Search Attributes (Visibility)

### Setting Search Attributes at Start

```java
import io.temporal.common.SearchAttributeKey;
import io.temporal.common.SearchAttributes;
import io.temporal.client.WorkflowOptions;

// Define typed search attribute keys
static final SearchAttributeKey<String> ORDER_ID =
    SearchAttributeKey.forKeyword("OrderId");
static final SearchAttributeKey<String> CUSTOMER_TYPE =
    SearchAttributeKey.forKeyword("CustomerType");
static final SearchAttributeKey<Double> ORDER_TOTAL =
    SearchAttributeKey.forDouble("OrderTotal");
static final SearchAttributeKey<String> ORDER_STATUS =
    SearchAttributeKey.forKeyword("OrderStatus");

// Start workflow with search attributes
WorkflowOptions options = WorkflowOptions.newBuilder()
    .setWorkflowId("order-123")
    .setTaskQueue("orders")
    .setTypedSearchAttributes(
        SearchAttributes.newBuilder()
            .set(ORDER_ID, "123")
            .set(CUSTOMER_TYPE, "premium")
            .set(ORDER_TOTAL, 99.99)
            .build()
    )
    .build();

OrderWorkflow workflow = client.newWorkflowStub(OrderWorkflow.class, options);
WorkflowClient.start(workflow::run, order);
```

### Upserting Search Attributes from Workflow

```java
import io.temporal.workflow.Workflow;

public class OrderWorkflowImpl implements OrderWorkflow {
    @Override
    public String run(Order order) {
        // Update status as workflow progresses
        Workflow.upsertTypedSearchAttributes(
            ORDER_STATUS.valueSet("processing")
        );

        activities.processOrder(order);

        Workflow.upsertTypedSearchAttributes(
            ORDER_STATUS.valueSet("completed")
        );

        return "done";
    }
}
```

### Querying Workflows by Search Attributes

```java
import io.temporal.api.workflowservice.v1.ListWorkflowExecutionsRequest;

// List workflows using search attributes
String query = "OrderStatus = 'processing' AND CustomerType = 'premium'";

var request = ListWorkflowExecutionsRequest.newBuilder()
    .setNamespace("default")
    .setQuery(query)
    .build();

var response = service.blockingStub().listWorkflowExecutions(request);
for (var execution : response.getExecutionsList()) {
    System.out.println("Workflow " + execution.getExecution().getWorkflowId() +
        " is still processing");
}
```

## Best Practices

1. Use `Workflow.getLogger()` in workflows, standard SLF4J in activities
2. Don't use System.out.println() in workflows - it produces duplicate output on replay
3. Configure Micrometer metrics for production monitoring
4. Use typed SearchAttributeKey for compile-time safety
5. Add OpenTelemetry tracing for distributed debugging
