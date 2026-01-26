# Java SDK Testing

## Overview

The Java SDK provides JUnit 5 extensions for testing workflows with automatic environment setup.

## JUnit 5 Test Extension

```java
import io.temporal.testing.TestWorkflowExtension;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.RegisterExtension;

class GreetingWorkflowTest {
    @RegisterExtension
    public static final TestWorkflowExtension testWorkflow =
        TestWorkflowExtension.newBuilder()
            .setWorkflowTypes(GreetingWorkflowImpl.class)
            .setActivityImplementations(new GreetingActivitiesImpl())
            .build();

    @Test
    void testGreetingWorkflow(TestWorkflowEnvironment env,
                               Worker worker,
                               GreetingWorkflow workflow) {
        String result = workflow.getGreeting("World");
        assertEquals("Hello, World!", result);
    }
}
```

## Mocking Activities

```java
import static org.mockito.Mockito.*;

@Test
void testWithMockedActivity() {
    GreetingActivities mockedActivities = mock(GreetingActivities.class);
    when(mockedActivities.greet(anyString())).thenReturn("Mocked!");

    TestWorkflowExtension ext = TestWorkflowExtension.newBuilder()
        .setWorkflowTypes(GreetingWorkflowImpl.class)
        .setActivityImplementations(mockedActivities)
        .build();

    // Run test with mocked activities
}
```

## Activity Testing

```java
import io.temporal.testing.TestActivityExtension;

class ActivityTest {
    @RegisterExtension
    public static final TestActivityExtension testActivity =
        TestActivityExtension.newBuilder()
            .setActivityImplementations(new GreetingActivitiesImpl())
            .build();

    @Test
    void testGreetActivity(GreetingActivities activities) {
        String result = activities.greet("World");
        assertEquals("Hello, World!", result);
    }
}
```

## Testing Signals

```java
@Test
void testSignal(TestWorkflowEnvironment env, Worker worker) {
    OrderWorkflow workflow = env.getWorkflowClient().newWorkflowStub(
        OrderWorkflow.class,
        WorkflowOptions.newBuilder()
            .setWorkflowId("order-test")
            .setTaskQueue(worker.getTaskQueue())
            .build()
    );

    // Start workflow asynchronously
    WorkflowClient.start(workflow::processOrder, order);

    // Send signal
    workflow.approve();

    // Wait for result
    String result = workflow.processOrder(order);
    assertEquals("approved", result);
}
```

## Testing Queries

```java
@Test
void testQuery(TestWorkflowEnvironment env, Worker worker) {
    StatusWorkflow workflow = env.getWorkflowClient().newWorkflowStub(
        StatusWorkflow.class,
        WorkflowOptions.newBuilder()
            .setWorkflowId("status-test")
            .setTaskQueue(worker.getTaskQueue())
            .build()
    );

    WorkflowClient.start(workflow::run);

    // Query state
    String status = workflow.getStatus();
    assertEquals("running", status);
}
```

## Time Skipping

```java
@Test
void testWithTimer(TestWorkflowEnvironment env, Worker worker, TimerWorkflow workflow) {
    // Time automatically advances in test environment
    String result = workflow.waitForTimer();
    assertEquals("timer fired", result);
}
```

## Best Practices

1. Use JUnit 5 extensions for consistent setup
2. Mock activities for isolated workflow testing
3. Test signal/query handlers explicitly
4. Use Mockito for activity mocking
5. Test error scenarios with mocked failures
