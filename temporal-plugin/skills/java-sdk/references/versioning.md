# Java SDK Versioning

## Overview

The Java SDK provides multiple approaches for managing workflow version changes: the Patching API (`getVersion`), Workflow Type Versioning, and Worker Versioning. Choose based on your deployment strategy and workflow characteristics.

## Workflow Versioning with getVersion

The `getVersion` method enables backwards-compatible changes by preserving execution paths for each supported version:

```java
public static int getVersion(String changeId, int minSupported, int maxSupported)
```

**Parameters:**
- `changeId`: A unique string identifying the change
- `minSupported`: Minimum supported version (`Workflow.DEFAULT_VERSION` for original code)
- `maxSupported`: Maximum supported version (current version)

### Basic Usage

```java
int version = Workflow.getVersion("ChangedNotificationActivity", Workflow.DEFAULT_VERSION, 1);

String result;
if (version == Workflow.DEFAULT_VERSION) {
    result = activities.sendFax();
} else {
    result = activities.sendEmail();
}
```

The `Workflow.DEFAULT_VERSION` constant has value `-1` and identifies the original code before `getVersion` was added.

### Branching with Multiple Versions

Use if/else chains or switch statements for multiple versions:

```java
int version = Workflow.getVersion("ChangedNotificationActivity", Workflow.DEFAULT_VERSION, 3);

String result;
if (version == Workflow.DEFAULT_VERSION) {
    result = activities.sendFax();
} else if (version == 1) {
    result = activities.sendEmail();
} else if (version == 2) {
    result = activities.sendTextMessage();
} else {
    result = activities.sendTweet();
}
```

### Adding Support for New Versions

Increment the `maxSupported` value and add a new branch:

```java
// Before: maxSupported was 1
int version = Workflow.getVersion("ChangedNotificationActivity", Workflow.DEFAULT_VERSION, 2);

if (version == Workflow.DEFAULT_VERSION) {
    result = activities.sendFax();
} else if (version == 1) {
    result = activities.sendEmail();
} else {
    result = activities.sendTextMessage();  // New version 2
}
```

### Removing Support for Old Versions

After confirming no open executions use old versions, update `minSupported`:

```java
// Removed support for DEFAULT_VERSION and version 1
int version = Workflow.getVersion("ChangedNotificationActivity", 2, 3);

if (version == 2) {
    result = activities.sendTextMessage();
} else {
    result = activities.sendTweet();
}
```

### Setting TemporalChangeVersion Search Attribute

The Java SDK does not automatically set the `TemporalChangeVersion` search attribute. Set it manually:

```java
import io.temporal.common.SearchAttributeKey;
import java.util.Arrays;
import java.util.List;

public class MyWorkflowImpl implements MyWorkflow {
    // Define the search attribute key
    public static final SearchAttributeKey<List<String>> TEMPORAL_CHANGE_VERSION =
        SearchAttributeKey.forKeywordList("TemporalChangeVersion");

    @Override
    public String execute() {
        int version = Workflow.getVersion("MyChange", Workflow.DEFAULT_VERSION, 1);

        // Set search attribute for non-default versions
        if (version != Workflow.DEFAULT_VERSION) {
            Workflow.upsertTypedSearchAttributes(
                TEMPORAL_CHANGE_VERSION.valueSet(Arrays.asList("MyChange-" + version))
            );
        }

        // ... workflow logic
    }
}
```

**For multiple `getVersion` calls:**

```java
List<String> versionList = new ArrayList<>();

int versionOne = Workflow.getVersion("ChangeOne", Workflow.DEFAULT_VERSION, 1);
int versionTwo = Workflow.getVersion("ChangeTwo", Workflow.DEFAULT_VERSION, 1);

if (versionOne != Workflow.DEFAULT_VERSION) {
    versionList.add("ChangeOne-" + versionOne);
}
if (versionTwo != Workflow.DEFAULT_VERSION) {
    versionList.add("ChangeTwo-" + versionTwo);
}

if (!versionList.isEmpty()) {
    Workflow.upsertTypedSearchAttributes(TEMPORAL_CHANGE_VERSION.valueSet(versionList));
}
```

### Query Filters for Finding Workflows by Version

Find workflows running a specific version:

```sql
WorkflowType = "MyWorkflow"
    AND ExecutionStatus = "Running"
    AND TemporalChangeVersion = "MyChange-1"
```

Find workflows running the original (pre-versioning) code:

```sql
WorkflowType = "MyWorkflow"
    AND ExecutionStatus = "Running"
    AND TemporalChangeVersion IS NULL
```

## Workflow Type Versioning

For incompatible changes, create a new workflow type instead of using `getVersion`:

```java
// Original workflow interface
@WorkflowInterface
public interface PizzaWorkflow {
    @WorkflowMethod
    OrderConfirmation pizzaWorkflow(PizzaOrder order);
}

public class PizzaWorkflowImpl implements PizzaWorkflow {
    @Override
    public OrderConfirmation pizzaWorkflow(PizzaOrder order) {
        // Original implementation
    }
}

// New version with different interface
@WorkflowInterface
public interface PizzaWorkflowV2 {
    @WorkflowMethod
    OrderConfirmation pizzaWorkflow(PizzaOrder order);
}

public class PizzaWorkflowImplV2 implements PizzaWorkflowV2 {
    @Override
    public OrderConfirmation pizzaWorkflow(PizzaOrder order) {
        // New implementation with incompatible changes
    }
}
```

Register both versions with the worker:

```java
worker.registerWorkflowImplementationTypes(PizzaWorkflowImpl.class);
worker.registerWorkflowImplementationTypes(PizzaWorkflowImplV2.class);
```

Update client code to start new executions with the new type (`PizzaWorkflowV2`). After all old executions complete, remove the original implementation.

## Worker Versioning

Worker Versioning allows multiple worker versions to run simultaneously, enabling rainbow deployments without modifying workflow code.

### Key Concepts

- **Worker Deployment**: A logical grouping of workers running the same application
- **Worker Deployment Version**: A specific build/revision within a deployment (deployment name + build ID)
- **PINNED**: Workflows stay on their assigned version throughout execution
- **AUTO_UPGRADE**: Workflows can move to newer versions when deployed

### Configuring Workers

```java
import io.temporal.worker.Worker;
import io.temporal.worker.WorkerOptions;
import io.temporal.worker.WorkerDeploymentOptions;
import io.temporal.worker.WorkerDeploymentVersion;
import io.temporal.workflow.VersioningBehavior;

WorkerOptions options = WorkerOptions.newBuilder()
    .setDeploymentOptions(
        WorkerDeploymentOptions.newBuilder()
            .setVersion(new WorkerDeploymentVersion("order-service", "1.0.0"))
            .setUseVersioning(true)
            .setDefaultVersioningBehavior(VersioningBehavior.PINNED)
            .build())
    .build();

Worker worker = factory.newWorker("my-task-queue", options);
```

**Configuration parameters:**
- `setUseVersioning(true)`: Enables Worker Versioning
- `setVersion()`: Sets the deployment name and build ID
- `setDefaultVersioningBehavior()`: Sets default behavior for workflows

### PINNED Behavior

Use `PINNED` for short-running workflows where consistency is critical:

```java
WorkerDeploymentOptions.newBuilder()
    .setVersion(new WorkerDeploymentVersion("order-service", "1.0.0"))
    .setUseVersioning(true)
    .setDefaultVersioningBehavior(VersioningBehavior.PINNED)
    .build();
```

**Characteristics:**
- Workflows run only on their assigned version
- No patching required in workflow code
- Cannot use other versioning APIs (`getVersion`)
- Simplified interface management between versions

**When to use:**
- Short-running workflows (minutes to hours)
- Stability and consistency are priorities
- New applications wanting simple development experience

### AUTO_UPGRADE Behavior

Use `AUTO_UPGRADE` for long-running workflows or when migrating from rolling deploys:

```java
WorkerDeploymentOptions.newBuilder()
    .setVersion(new WorkerDeploymentVersion("order-service", "1.0.0"))
    .setUseVersioning(true)
    .setDefaultVersioningBehavior(VersioningBehavior.AUTO_UPGRADE)
    .build();
```

**Characteristics:**
- Workflows can move to newer versions when current deployment changes
- Requires patching (`getVersion`) to handle version transitions safely
- Can still use Temporal's versioning APIs
- Workflows move forward only (cannot return to older versions)

**When to use:**
- Long-running workflows (weeks to months)
- Workflows need bug fixes during execution
- Migrating from traditional rolling deployments
- Want to minimize infrastructure by retiring old versions quickly

### Deployment Strategies

**Blue-Green Deploys:**
Maintain two environments (blue and green). Deploy to idle environment, validate, then switch traffic. Provides zero-downtime and instant rollback.

**Rainbow Deploys:**
Multiple versions run simultaneously. New versions are added alongside existing ones rather than replacing them. Ideal for:
- Long-running workflows that cannot be interrupted
- Emergency fixes without disrupting in-progress work
- Gradual traffic ramping to new versions

### Build ID Patterns

```java
// Using git commit hash
new WorkerDeploymentVersion("order-service", "abc123def");

// Using semantic versioning
new WorkerDeploymentVersion("order-service", "1.2.0");

// Using build numbers
new WorkerDeploymentVersion("payment-handler", "build-456");
```

## Choosing a Versioning Strategy

| Scenario | Recommended Approach |
|----------|---------------------|
| Minor workflow logic changes | `getVersion` patching |
| Incompatible signature changes | Workflow Type Versioning |
| Short-running workflows, stability critical | Worker Versioning with PINNED |
| Long-running workflows needing bug fixes | Worker Versioning with AUTO_UPGRADE |
| New applications, unknown patterns | Start without default, learn patterns first |

## Best Practices

1. Never reuse a change ID for modifications deployed at different times
2. Set search attributes immediately after `getVersion` calls for visibility
3. Use query filters to verify no open executions before removing version support
4. Use semantic versioning or git hashes for build IDs
5. For PINNED workflows, keep old versions running until all executions complete
6. For AUTO_UPGRADE workflows, always use patching to handle version transitions
