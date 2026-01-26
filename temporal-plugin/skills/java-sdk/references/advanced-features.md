# Java SDK Advanced Features

## Continue-as-New

Use continue-as-new to prevent unbounded history growth in long-running workflows.

```java
import io.temporal.workflow.Workflow;

public class BatchProcessingWorkflowImpl implements BatchProcessingWorkflow {
    @Override
    public String run(ProcessingState state) {
        while (!state.isComplete()) {
            // Process next batch
            state = activities.processNextBatch(state);

            // Check history size and continue-as-new if needed
            if (Workflow.getInfo().getHistoryLength() > 10000) {
                Workflow.continueAsNew(state);
            }
        }

        return "completed";
    }
}
```

### Continue-as-New with Options

```java
import io.temporal.workflow.ContinueAsNewOptions;

// Continue with modified options
ContinueAsNewOptions options = ContinueAsNewOptions.newBuilder()
    .setWorkflowRunTimeout(Duration.ofHours(24))
    .setMemo(Map.of("lastProcessed", itemId))
    .build();

Workflow.continueAsNew(options, state);
```

## Workflow Updates

Updates allow synchronous interaction with running workflows.

### Defining Update Handlers

```java
import io.temporal.workflow.UpdateMethod;
import io.temporal.workflow.UpdateValidatorMethod;

@WorkflowInterface
public interface OrderWorkflow {
    @WorkflowMethod
    String run(Order order);

    @UpdateMethod
    int addItem(String item);

    @UpdateMethod(name = "addItemValidated")
    int addItemWithValidation(String item);

    @UpdateValidatorMethod(updateName = "addItemValidated")
    void validateAddItem(String item);
}

public class OrderWorkflowImpl implements OrderWorkflow {
    private final List<String> items = new ArrayList<>();

    @Override
    public String run(Order order) {
        // Wait for completion signal
        Workflow.await(() -> completed);
        return "Order with " + items.size() + " items completed";
    }

    @Override
    public int addItem(String item) {
        items.add(item);
        return items.size();
    }

    @Override
    public int addItemWithValidation(String item) {
        items.add(item);
        return items.size();
    }

    @Override
    public void validateAddItem(String item) {
        if (item == null || item.isEmpty()) {
            throw new IllegalArgumentException("Item cannot be empty");
        }
        if (items.size() >= 100) {
            throw new IllegalArgumentException("Order is full");
        }
    }
}
```

### Calling Updates from Client

```java
import io.temporal.client.UpdateOptions;

WorkflowStub stub = client.newUntypedWorkflowStub("order-123");

// Execute update and wait for result
int count = stub.update("addItem", int.class, "new-item");
System.out.println("Order now has " + count + " items");

// Or with typed stub
OrderWorkflow workflow = client.newWorkflowStub(OrderWorkflow.class, "order-123");
count = workflow.addItem("new-item");
```

## Asynchronous Activity Completion

### WHY: Complete activities from external systems (webhooks, human tasks, external services)
### WHEN:
- **Human approval workflows** - Wait for human to complete task externally
- **Webhook-based integrations** - External service calls back when done
- **Long-polling external systems** - Activity starts work, external system finishes it

```java
import io.temporal.activity.Activity;
import io.temporal.activity.ActivityExecutionContext;
import io.temporal.client.ActivityCompletionClient;

@ActivityInterface
public interface GreetingActivities {
    String composeGreeting(String greeting, String name);
}

public class GreetingActivitiesImpl implements GreetingActivities {
    private final ActivityCompletionClient completionClient;

    public GreetingActivitiesImpl(ActivityCompletionClient completionClient) {
        this.completionClient = completionClient;
    }

    @Override
    public String composeGreeting(String greeting, String name) {
        ActivityExecutionContext context = Activity.getExecutionContext();

        // Get task token for external completion
        byte[] taskToken = context.getTaskToken();

        // Start external work (e.g., send to external service, queue for human)
        startExternalWork(taskToken, greeting, name);

        // Tell Temporal this activity will be completed externally
        context.doNotCompleteOnReturn();

        // Return value is ignored when doNotCompleteOnReturn() is called
        return "ignored";
    }

    // Called by external system when work is done
    public void completeGreetingExternally(byte[] taskToken, String result) {
        completionClient.complete(taskToken, result);
    }

    // Or fail the activity externally
    public void failGreetingExternally(byte[] taskToken, Exception error) {
        completionClient.completeExceptionally(taskToken, error);
    }
}

// Worker setup
ActivityCompletionClient completionClient = client.newActivityCompletionClient();
worker.registerActivitiesImplementations(new GreetingActivitiesImpl(completionClient));
```

## Schedules

Create recurring workflow executions.

```java
import io.temporal.client.schedules.*;

// Create a schedule
ScheduleClient scheduleClient = ScheduleClient.newInstance(service);

Schedule schedule = Schedule.newBuilder()
    .setAction(ScheduleActionStartWorkflow.newBuilder()
        .setWorkflowType(DailyReportWorkflow.class)
        .setOptions(WorkflowOptions.newBuilder()
            .setWorkflowId("daily-report")
            .setTaskQueue("reports")
            .build())
        .build())
    .setSpec(ScheduleSpec.newBuilder()
        .setIntervals(List.of(
            ScheduleIntervalSpec.newBuilder()
                .setEvery(Duration.ofDays(1))
                .build()
        ))
        .build())
    .build();

ScheduleHandle handle = scheduleClient.createSchedule(
    "daily-report-schedule",
    schedule,
    ScheduleOptions.newBuilder().build()
);

// Manage schedules
handle.pause("Maintenance window");
handle.unpause();
handle.trigger();  // Run immediately
handle.delete();
```

## Interceptors

Interceptors allow cross-cutting concerns like logging, metrics, and auth.

### Creating a Custom Interceptor

```java
import io.temporal.common.interceptors.*;

public class LoggingWorkerInterceptor implements WorkerInterceptor {
    @Override
    public ActivityInboundCallsInterceptor interceptActivity(
            ActivityInboundCallsInterceptorBase next) {
        return new LoggingActivityInterceptor(next);
    }

    private static class LoggingActivityInterceptor
            extends ActivityInboundCallsInterceptorBase {
        private static final Logger logger =
            LoggerFactory.getLogger(LoggingActivityInterceptor.class);

        public LoggingActivityInterceptor(ActivityInboundCallsInterceptorBase next) {
            super(next);
        }

        @Override
        public Object execute(ActivityInput input) {
            logger.info("Activity starting: {}", input.getActivityName());
            try {
                Object result = super.execute(input);
                logger.info("Activity completed: {}", input.getActivityName());
                return result;
            } catch (Exception e) {
                logger.error("Activity failed: {}", input.getActivityName(), e);
                throw e;
            }
        }
    }
}

// Apply to worker factory
WorkerFactoryOptions factoryOptions = WorkerFactoryOptions.newBuilder()
    .setWorkerInterceptors(new LoggingWorkerInterceptor())
    .build();

WorkerFactory factory = WorkerFactory.newInstance(client, factoryOptions);
```

## Dynamic Workflows and Activities

Handle workflows/activities not known at compile time.

### Dynamic Workflow Handler

```java
import io.temporal.workflow.DynamicWorkflow;
import io.temporal.common.converter.EncodedValues;

public class DynamicWorkflowImpl implements DynamicWorkflow {
    @Override
    public Object execute(EncodedValues args) {
        String workflowType = Workflow.getInfo().getWorkflowType();

        switch (workflowType) {
            case "order-workflow":
                return handleOrderWorkflow(args);
            case "refund-workflow":
                return handleRefundWorkflow(args);
            default:
                throw new IllegalArgumentException(
                    "Unknown workflow type: " + workflowType);
        }
    }
}

// Register as dynamic handler
worker.registerWorkflowImplementationTypes(DynamicWorkflowImpl.class);
```

### Dynamic Activity Handler

```java
import io.temporal.activity.DynamicActivity;
import io.temporal.activity.Activity;
import io.temporal.common.converter.EncodedValues;

public class DynamicActivityImpl implements DynamicActivity {
    @Override
    public Object execute(EncodedValues args) {
        String activityType = Activity.getExecutionContext()
            .getInfo().getActivityType();

        switch (activityType) {
            case "process-payment":
                return processPayment(args);
            default:
                throw new IllegalArgumentException(
                    "Unknown activity type: " + activityType);
        }
    }
}

// Register as dynamic handler
worker.registerActivitiesImplementations(new DynamicActivityImpl());
```

## Workflow.getInfo()

Access workflow metadata within workflows.

```java
import io.temporal.workflow.Workflow;
import io.temporal.workflow.WorkflowInfo;

public class MyWorkflowImpl implements MyWorkflow {
    @Override
    public void run() {
        WorkflowInfo info = Workflow.getInfo();

        String workflowId = info.getWorkflowId();
        String runId = info.getRunId();
        String workflowType = info.getWorkflowType();
        long historyLength = info.getHistoryLength();
        String taskQueue = info.getTaskQueue();

        // Use for idempotency keys
        String idempotencyKey = workflowId + "-" + runId;
    }
}
```

## WorkflowLock

Mutex for coordinating access to shared resources within a workflow.

```java
import io.temporal.workflow.WorkflowLock;

public class CoordinatedWorkflowImpl implements CoordinatedWorkflow {
    private final WorkflowLock lock = Workflow.newWorkflowLock();
    private int sharedCounter = 0;

    @Override
    public void run() {
        // Multiple concurrent operations can safely update shared state
        List<Promise<Void>> promises = new ArrayList<>();

        for (int i = 0; i < 10; i++) {
            promises.add(Async.procedure(this::incrementCounter));
        }

        Promise.allOf(promises).get();
    }

    private void incrementCounter() {
        lock.lock();
        try {
            // Critical section - only one coroutine at a time
            int current = sharedCounter;
            Workflow.sleep(Duration.ofMillis(100)); // Simulate work
            sharedCounter = current + 1;
        } finally {
            lock.unlock();
        }
    }
}
```

## Waiting for All Handlers to Finish

Ensure all signal/update handlers complete before workflow exits.

```java
public class OrderWorkflowImpl implements OrderWorkflow {
    @Override
    public String run(Order order) {
        // Main workflow logic
        processOrder(order);

        // Wait for all handlers to finish before exiting
        Workflow.await(() -> Workflow.isEveryHandlerFinished());

        return "completed";
    }
}
```

## Exception Hierarchy

Understanding Temporal's exception types helps with proper error handling.

```java
import io.temporal.failure.*;

// CanceledFailure - Workflow or activity was cancelled
try {
    activities.longRunningActivity();
} catch (ActivityFailure e) {
    if (e.getCause() instanceof CanceledFailure) {
        // Handle cancellation
    }
}

// ApplicationFailure - Business logic error (non-retryable by default)
throw ApplicationFailure.newFailure("Order not found", "OrderNotFound");

// Non-retryable application failure
throw ApplicationFailure.newNonRetryableFailure("Invalid input", "ValidationError");

// ChildWorkflowFailure - Child workflow failed
try {
    childWorkflow.process();
} catch (ChildWorkflowFailure e) {
    // e.getCause() contains the actual failure
}

// TemporalFailure - Base class for all Temporal failures
// TimeoutFailure - Activity or workflow timed out
```

## Best Practices

1. Use continue-as-new for long-running workflows to prevent history growth
2. Prefer updates over signals when you need a response
3. Use @UpdateValidatorMethod for input validation before accepting updates
4. Configure interceptors for cross-cutting concerns like tracing
5. Use Workflow.getInfo() for workflow metadata access
6. Add compensation BEFORE actions in Saga patterns for timeout safety
7. Use DetachedCancellationScope for cleanup that must run even after cancellation
8. Set heartbeat timeout for activities that need cancellation responsiveness
