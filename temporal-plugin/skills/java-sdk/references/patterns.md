# Java SDK Patterns

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

```java
@WorkflowInterface
public interface OrderWorkflow {
    @WorkflowMethod
    String processOrder(Order order);

    @SignalMethod
    void approve();

    @SignalMethod
    void addItem(String item);
}

public class OrderWorkflowImpl implements OrderWorkflow {
    private boolean approved = false;
    private List<String> items = new ArrayList<>();

    @Override
    public String processOrder(Order order) {
        Workflow.await(() -> approved);
        return "Processed " + items.size() + " items";
    }

    @Override
    public void approve() {
        this.approved = true;
    }

    @Override
    public void addItem(String item) {
        this.items.add(item);
    }
}
```

### Signal-with-Start

Start a workflow and send a signal atomically. Essential for accumulator patterns.

```java
WorkflowStub workflowStub = client.newUntypedWorkflowStub(
    "OrderWorkflow",
    WorkflowOptions.newBuilder()
        .setWorkflowId("order-123")
        .setTaskQueue(TASK_QUEUE)
        .build()
);

// Atomically start workflow and send signal
workflowStub.signalWithStart(
    "addItem",                          // Signal name
    new Object[] { "first-item" },      // Signal arguments
    new Object[] { new Order("123") }   // Workflow arguments
);
```

## Queries

### WHY: Read workflow state without affecting execution - queries are read-only
### WHEN:
- **Progress tracking dashboards** - Display workflow progress to users
- **Status endpoints** - Check workflow state for API responses
- **Debugging** - Inspect internal workflow state
- **Health checks** - Verify workflow is functioning correctly

**Important:** Queries must NOT modify workflow state or have side effects.

```java
@WorkflowInterface
public interface StatusWorkflow {
    @WorkflowMethod
    void run();

    @QueryMethod
    String getStatus();

    @QueryMethod
    int getProgress();
}

public class StatusWorkflowImpl implements StatusWorkflow {
    private String status = "pending";
    private int progress = 0;

    @Override
    public void run() {
        status = "running";
        for (int i = 0; i < 100; i++) {
            progress = i;
            activities.processItem(i);
        }
        status = "completed";
    }

    @Override
    public String getStatus() {
        return status;
    }

    @Override
    public int getProgress() {
        return progress;
    }
}
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

```java
@Override
public List<String> processOrders(List<Order> orders) {
    List<String> results = new ArrayList<>();

    for (Order order : orders) {
        ProcessOrderWorkflow child = Workflow.newChildWorkflowStub(
            ProcessOrderWorkflow.class,
            ChildWorkflowOptions.newBuilder()
                .setWorkflowId("order-" + order.getId())
                // Control what happens to child when parent completes
                .setParentClosePolicy(ParentClosePolicy.PARENT_CLOSE_POLICY_ABANDON)
                .build()
        );

        String result = child.process(order);
        results.add(result);
    }

    return results;
}
```

## Parallel Execution

### WHY: Execute multiple independent operations concurrently for better throughput
### WHEN:
- **Batch processing** - Process multiple items simultaneously
- **Fan-out patterns** - Distribute work across multiple activities
- **Independent operations** - Operations that don't depend on each other's results

```java
@Override
public List<String> processItems(List<String> items) {
    List<Promise<String>> promises = new ArrayList<>();

    for (String item : items) {
        Promise<String> promise = Async.function(activities::processItem, item);
        promises.add(promise);
    }

    // Wait for all to complete
    List<String> results = new ArrayList<>();
    for (Promise<String> promise : promises) {
        results.add(promise.get());
    }

    return results;
}
```

### Wait for First Result (Race Pattern)

```java
// Wait for the first activity to complete, cancel the rest
Promise<String> first = Promise.anyOf(promises);
String result = first.get();
```

## Continue-as-New

### WHY: Prevent unbounded event history growth in long-running or infinite workflows
### WHEN:
- **Event history approaching 10,000+ events** - Temporal recommends continue-as-new before hitting limits
- **Infinite/long-running workflows** - Polling, subscription, or daemon-style workflows
- **Memory optimization** - Reset workflow state to reduce memory footprint

**Recommendation:** Check history length periodically and continue-as-new around 10,000 events.

```java
@Override
public void longRunningWorkflow(State state) {
    while (true) {
        state = processNextBatch(state);

        if (state.isComplete()) {
            return;
        }

        if (Workflow.getInfo().getHistoryLength() > 10000) {
            Workflow.continueAsNew(state);
        }
    }
}
```

## Saga Pattern

### WHY: Implement distributed transactions with compensating actions for rollback
### WHEN:
- **Multi-step transactions** - Operations that span multiple services
- **Eventual consistency** - When you can't use traditional ACID transactions
- **Rollback requirements** - When partial failures require undoing previous steps

**Important:**
- Add compensation BEFORE the action to handle timeout scenarios where success is unclear
- Compensation activities should be idempotent - they may be retried
- Use DetachedCancellationScope for compensations to ensure they run even if workflow is cancelled

```java
@Override
public void bookTrip(String name) {
    Saga.Options sagaOptions = new Saga.Options.Builder().build();
    Saga saga = new Saga(sagaOptions);

    try {
        // Add compensation BEFORE the action to handle timeout scenarios
        // where the action's success is unclear
        String carRequestId = Workflow.randomUUID().toString();
        saga.addCompensation(compensationActivities::cancelCar, carRequestId, name);
        String carReservationId = activities.reserveCar(carRequestId, name);

        String hotelRequestId = Workflow.randomUUID().toString();
        saga.addCompensation(compensationActivities::cancelHotel, hotelRequestId, name);
        String hotelReservationId = activities.bookHotel(hotelRequestId, name);

        String flightRequestId = Workflow.randomUUID().toString();
        saga.addCompensation(compensationActivities::cancelFlight, flightRequestId, name);
        String flightReservationId = activities.bookFlight(flightRequestId, name);

    } catch (ActivityFailure e) {
        // Ensure compensations run even if workflow is cancelled
        Workflow.newDetachedCancellationScope(() -> saga.compensate()).run();
        throw e;
    }
}
```

## Cancellation Scopes

### WHY: Control cancellation behavior for groups of operations
### WHEN:
- **Race conditions** - Cancel remaining activities when one completes
- **Timeouts** - Cancel operations that exceed a deadline
- **Cleanup operations** - Ensure cleanup runs even after cancellation

### Basic CancellationScope

```java
@Override
public String getGreeting(String name) {
    List<Promise<String>> results = new ArrayList<>();

    // Create cancellation scope for parallel activities
    CancellationScope scope = Workflow.newCancellationScope(() -> {
        for (String greeting : greetings) {
            results.add(Async.function(activities::composeGreeting, greeting, name));
        }
    });

    // Run activities within the scope
    scope.run();

    // Wait for first result
    String result = Promise.anyOf(results).get();

    // Cancel all other activities
    scope.cancel();

    // Wait for cancellation to complete (with WAIT_CANCELLATION_COMPLETED)
    for (Promise<String> promise : results) {
        try {
            promise.get();
        } catch (ActivityFailure e) {
            if (!(e.getCause() instanceof CanceledFailure)) {
                throw e;
            }
        }
    }

    return result;
}
```

### DetachedCancellationScope for Cleanup

Use DetachedCancellationScope when you need to run cleanup code that should not be cancelled even if the workflow is cancelled.

```java
@Override
public String getGreeting(String name) {
    try {
        return activities.sayHello(name);
    } catch (ActivityFailure af) {
        // Cleanup runs even if workflow is cancelled
        CancellationScope detached = Workflow.newDetachedCancellationScope(
            () -> greeting = activities.sayGoodBye(name)
        );
        detached.run();
        throw af;
    }
}
```

### Activity Cancellation Types

Control how activities respond to workflow cancellation:

```java
ActivityOptions options = ActivityOptions.newBuilder()
    .setStartToCloseTimeout(Duration.ofSeconds(30))
    .setHeartbeatTimeout(Duration.ofSeconds(5))
    // TRY_CANCEL (default): Request cancellation, report cancelled immediately
    // WAIT_CANCELLATION_COMPLETED: Wait for activity to acknowledge cancellation
    // ABANDON: Don't request cancellation, just report as cancelled
    .setCancellationType(ActivityCancellationType.WAIT_CANCELLATION_COMPLETED)
    .build();
```

## Activity Heartbeating

### WHY: Keep long-running activities alive and enable progress checkpointing
### WHEN:
- **Long-running operations** - Activities that run for minutes or hours
- **Progress checkpointing** - Resume from last checkpoint on retry
- **Cancellation detection** - Receive cancellation requests promptly

```java
@Override
public int processRecords() {
    ActivityExecutionContext context = Activity.getExecutionContext();

    // Resume from last heartbeat on retry
    Optional<Integer> heartbeatDetails = context.getHeartbeatDetails(Integer.class);
    int offset = heartbeatDetails.orElse(0);

    while (true) {
        Optional<SingleRecord> record = recordLoader.getRecord(offset);
        if (!record.isPresent()) {
            return offset;
        }

        recordProcessor.processRecord(record.get());

        // Heartbeat with progress - also receives cancellation
        context.heartbeat(offset);
        offset++;
    }
}
```

## Local Activities

### WHY: Reduce latency for short, lightweight operations by skipping the task queue
### WHEN:
- **Short operations** - Activities completing in milliseconds/seconds
- **High-frequency calls** - When task queue overhead is significant
- **Low-latency requirements** - When you can't afford task queue round-trip
- **Same-worker execution** - Operations that must run on the same worker

**Tradeoffs:** Local activities don't appear in history until the workflow task completes, and don't benefit from task queue load balancing.

```java
public class GreetingWorkflowImpl implements GreetingWorkflow {
    private final GreetingActivities activities =
        Workflow.newLocalActivityStub(
            GreetingActivities.class,
            LocalActivityOptions.newBuilder()
                .setStartToCloseTimeout(Duration.ofSeconds(2))
                .build()
        );

    @Override
    public String getGreeting(String name) {
        return activities.composeGreeting("Hello", name);
    }
}
```

## Timers

### WHY: Schedule delays or deadlines within workflows in a durable way
### WHEN:
- **Scheduled delays** - Wait for a specific duration before continuing
- **Deadlines** - Set timeouts for operations
- **Reminder patterns** - Schedule future notifications

```java
@Override
public String timerWorkflow() {
    // Simple sleep
    Workflow.sleep(Duration.ofHours(1));

    // Await with timeout
    boolean completed = Workflow.await(
        Duration.ofMinutes(30),
        () -> someCondition
    );

    if (!completed) {
        return "timed out";
    }
    return "completed";
}
```

## Workflow Init Constructor

### WHY: Initialize workflow state before signals can be received
### WHEN:
- **Signal-with-Start patterns** - Ensure state is initialized before signal handler runs
- **Complex initialization** - Set up state that signals depend on

```java
public class OrderWorkflowImpl implements OrderWorkflow {
    private List<Person> peopleToGreet;

    @WorkflowInit
    public OrderWorkflowImpl(Order order) {
        // Initialize state BEFORE any signal handlers can run
        peopleToGreet = new ArrayList<>();
        // WARNING: Avoid blocking operations here!
    }

    @Override
    public String processOrder() {
        // State is already initialized
        return processWithOrder(this.order);
    }
}
```

## Entity Workflow Pattern

### WHY: Model long-lived entities with message-driven state changes
### WHEN:
- **Entity lifecycle management** - Users, orders, devices with ongoing state
- **Event sourcing** - Accumulate events/messages over time
- **Stateful services** - Replace traditional stateful microservices

```java
@WorkflowInterface
public interface EntityWorkflow {
    @WorkflowMethod
    void run();

    @SignalMethod
    void processMessage(Message message);

    @QueryMethod
    EntityState getState();

    @SignalMethod
    void shutdown();
}

public class EntityWorkflowImpl implements EntityWorkflow {
    private EntityState state = new EntityState();
    private boolean running = true;

    @Override
    public void run() {
        while (running) {
            // Wait for signals
            Workflow.await(() -> !running || state.hasNewMessages());

            // Process accumulated messages
            state.processMessages();

            // Continue-as-new to prevent history growth
            if (Workflow.getInfo().getHistoryLength() > 10000) {
                Workflow.continueAsNew();
            }
        }
    }

    @Override
    public void processMessage(Message message) {
        state.addMessage(message);
    }

    @Override
    public EntityState getState() {
        return state;
    }

    @Override
    public void shutdown() {
        running = false;
    }
}
```
