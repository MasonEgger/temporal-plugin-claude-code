# Go SDK Versioning

## Overview

Workflow versioning allows you to safely deploy incompatible changes to Workflow code while maintaining backwards compatibility with open Workflow Executions. The Go SDK provides multiple approaches: the GetVersion API for code-level branching, Workflow Type versioning for simple cases, and Worker Versioning for deployment-level control.

## Why Versioning Matters

When Workers restart after deployment, they resume open Workflow Executions through **history replay**. During replay, the SDK re-executes your Workflow code and compares the generated Commands against the Events in history. If your updated code produces different Commands than the original execution, it causes a non-determinism error.

Versioning allows old and new code paths to coexist, ensuring that:
- Open Workflow Executions replay correctly with original behavior
- New Workflow Executions use the updated behavior

## Workflow Versioning with GetVersion API

### GetVersion Function Signature

```go
workflow.GetVersion(ctx workflow.Context, changeID string, minSupported, maxSupported workflow.Version) workflow.Version
```

**Parameters:**
- `ctx` - The Workflow context
- `changeID` - A string uniquely identifying this change
- `minSupported` - Minimum supported version (oldest compatible revision)
- `maxSupported` - Maximum supported version (current revision)

**Return value:** The version number to use for branching logic.

### Basic Usage

When you need to make an incompatible change, wrap the old and new code paths with `GetVersion`:

```go
func NotifyWorkflow(ctx workflow.Context, customer Customer) error {
    ao := workflow.ActivityOptions{StartToCloseTimeout: time.Minute}
    ctx = workflow.WithActivityOptions(ctx, ao)

    // Branch based on version
    version := workflow.GetVersion(ctx, "NotificationMethod", workflow.DefaultVersion, 1)

    if version == workflow.DefaultVersion {
        // Original code path - send fax
        return workflow.ExecuteActivity(ctx, SendFax, customer).Get(ctx, nil)
    }
    // New code path - send email
    return workflow.ExecuteActivity(ctx, SendEmail, customer).Get(ctx, nil)
}
```

The `workflow.DefaultVersion` constant (value `-1`) identifies the original code that existed before `GetVersion` was added.

### How GetVersion Works

When `GetVersion` executes:
1. For **new Workflow Executions**: Records a `MarkerRecorded` Event in history with the current version number
2. For **replaying Workflow Executions**: Reads the version from the existing Marker and returns it

This ensures the same code path executes during replay as during the original execution.

### Branching with Multiple Versions

A single Workflow can have multiple Change IDs, each tracking a different modification:

```go
func OrderWorkflow(ctx workflow.Context, order Order) error {
    ao := workflow.ActivityOptions{StartToCloseTimeout: 5 * time.Minute}
    ctx = workflow.WithActivityOptions(ctx, ao)

    // First versioned change
    v1 := workflow.GetVersion(ctx, "PaymentMethod", workflow.DefaultVersion, 1)
    if v1 == workflow.DefaultVersion {
        workflow.ExecuteActivity(ctx, ProcessCash, order).Get(ctx, nil)
    } else {
        workflow.ExecuteActivity(ctx, ProcessCard, order).Get(ctx, nil)
    }

    // Second versioned change (independent)
    v2 := workflow.GetVersion(ctx, "ShippingProvider", workflow.DefaultVersion, 1)
    if v2 == workflow.DefaultVersion {
        workflow.ExecuteActivity(ctx, ShipUSPS, order).Get(ctx, nil)
    } else {
        workflow.ExecuteActivity(ctx, ShipFedEx, order).Get(ctx, nil)
    }

    return nil
}
```

You can use the same Change ID for multiple changes **only** if they are deployed together. Never reuse a Change ID for modifications deployed at different times.

### Adding Support for Additional Versions

As requirements evolve, add new version branches:

```go
func NotifyWorkflow(ctx workflow.Context, customer Customer) error {
    ao := workflow.ActivityOptions{StartToCloseTimeout: time.Minute}
    ctx = workflow.WithActivityOptions(ctx, ao)

    version := workflow.GetVersion(ctx, "NotificationMethod", workflow.DefaultVersion, 3)

    switch version {
    case workflow.DefaultVersion:
        return workflow.ExecuteActivity(ctx, SendFax, customer).Get(ctx, nil)
    case 1:
        return workflow.ExecuteActivity(ctx, SendEmail, customer).Get(ctx, nil)
    case 2:
        return workflow.ExecuteActivity(ctx, SendSMS, customer).Get(ctx, nil)
    default: // version 3
        return workflow.ExecuteActivity(ctx, SendPushNotification, customer).Get(ctx, nil)
    }
}
```

### Removing Support for Old Versions

Once no open Workflow Executions use an old version, you can remove its code path. First, verify no executions use that version using List Filters.

**Find workflows using a specific version:**
```
WorkflowType = "NotifyWorkflow"
    AND ExecutionStatus = "Running"
    AND TemporalChangeVersion = "NotificationMethod-1"
```

**Find workflows predating GetVersion (no marker):**
```
WorkflowType = "NotifyWorkflow"
    AND ExecutionStatus = "Running"
    AND TemporalChangeVersion IS NULL
```

**CLI command:**
```bash
temporal workflow list --query 'WorkflowType = "NotifyWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion = "NotificationMethod-1"'
```

After confirming no open executions, update `minSupported` and remove old code:

```go
func NotifyWorkflow(ctx workflow.Context, customer Customer) error {
    ao := workflow.ActivityOptions{StartToCloseTimeout: time.Minute}
    ctx = workflow.WithActivityOptions(ctx, ao)

    // Removed support for versions DefaultVersion and 1
    version := workflow.GetVersion(ctx, "NotificationMethod", 2, 3)

    if version == 2 {
        return workflow.ExecuteActivity(ctx, SendSMS, customer).Get(ctx, nil)
    }
    return workflow.ExecuteActivity(ctx, SendPushNotification, customer).Get(ctx, nil)
}
```

**Warning:** Any Workflow Execution with a version less than `minSupported` will fail. Verify no such executions exist before updating.

## Workflow Type Versioning

For simpler cases, create a new Workflow Type instead of using GetVersion:

```go
// Original workflow
func PizzaWorkflow(ctx workflow.Context, order PizzaOrder) (OrderConfirmation, error) {
    // Original implementation
}

// New version with incompatible changes
func PizzaWorkflowV2(ctx workflow.Context, order PizzaOrder) (OrderConfirmation, error) {
    // Updated implementation
}
```

Register both with the Worker:

```go
w.RegisterWorkflow(pizza.PizzaWorkflow)
w.RegisterWorkflow(pizza.PizzaWorkflowV2)
```

Update client code to start new executions with the new type. Use List Filters to monitor when the original type has no open executions:

```
WorkflowType = "PizzaWorkflow" AND ExecutionStatus = "Running"
```

**Trade-offs:**
- Simpler than GetVersion branching
- Requires duplicating code
- Requires updating all code/commands that start the Workflow

## Worker Versioning

Worker Versioning shifts version management from code-level branching to deployment infrastructure, enabling blue-green and rainbow deployments.

### Key Concepts

**Worker Deployment:** A logical service grouping all versions of your Workers (e.g., "loan-processor"). Identified by a deployment name.

**Worker Deployment Version:** A specific build within a deployment, identified by combining deployment name and Build ID (e.g., "loan-processor:abc123").

**Build ID:** A unique identifier for a specific code build (git commit hash, version number, or timestamp).

### Configuring Workers for Versioning

```go
import (
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/worker"
    "go.temporal.io/sdk/workflow"
)

func main() {
    c, _ := client.Dial(client.Options{})
    defer c.Close()

    buildID := os.Getenv("BUILD_ID") // e.g., git commit hash or version number

    w := worker.New(c, "my-task-queue", worker.Options{
        DeploymentOptions: worker.DeploymentOptions{
            UseVersioning: true,
            Version: worker.WorkerDeploymentVersion{
                DeploymentName: "order-processor",
                BuildId:        buildID,
            },
            DefaultVersioningBehavior: workflow.VersioningBehaviorPinned,
        },
    })

    w.RegisterWorkflow(OrderWorkflow)
    w.RegisterActivity(ProcessOrder)

    w.Run(worker.InterruptCh())
}
```

**Configuration parameters:**
- `UseVersioning` - Enables Worker Versioning
- `Version` - Identifies this Worker deployment name and build
- `DefaultVersioningBehavior` - Sets default behavior for Workflows (`VersioningBehaviorPinned` or `VersioningBehaviorAutoUpgrade`)

### Versioning Behaviors: PINNED vs AUTO_UPGRADE

**PINNED:**
- Workflow runs only on the Worker version assigned at first execution
- No patching required - code never changes mid-execution
- Simplified interface management between Workflows and Activities
- Cannot use other versioning APIs (GetVersion)

```go
DeploymentOptions: worker.DeploymentOptions{
    UseVersioning: true,
    Version: worker.WorkerDeploymentVersion{
        DeploymentName: "order-processor",
        BuildId:        "v1.2.0",
    },
    DefaultVersioningBehavior: workflow.VersioningBehaviorPinned,
},
```

**AUTO_UPGRADE:**
- Workflow can move to newer Worker versions
- Can be rerouted when Current Deployment Version changes
- Patching (GetVersion) often required for safe transitions
- Useful for long-running Workflows that need bug fixes

```go
DeploymentOptions: worker.DeploymentOptions{
    UseVersioning: true,
    Version: worker.WorkerDeploymentVersion{
        DeploymentName: "order-processor",
        BuildId:        "v1.2.0",
    },
    DefaultVersioningBehavior: workflow.VersioningBehaviorAutoUpgrade,
},
```

### When to Use Each Behavior

**Choose PINNED when:**
- Workflows are short-running (minutes to hours)
- Consistency and stability are critical
- You want to eliminate version compatibility complexity
- Building new applications with simple deployment needs

**Choose AUTO_UPGRADE when:**
- Workflows run for weeks or months
- You need to apply bug fixes to in-progress Workflows
- Migrating from traditional rolling deployments
- Infrastructure cost of maintaining old versions is prohibitive

### Deployment Strategies

**Blue-Green Deployment:**
Maintain two environments (blue and green). Deploy new code to idle environment, validate, then switch traffic. Provides instant rollback capability.

**Rainbow Deployment:**
Multiple versions run simultaneously. New versions are added alongside existing ones rather than replacing them. Workflows can be pinned to specific versions throughout their execution.

```go
// Version 1 Worker (blue)
w1 := worker.New(c, "my-task-queue", worker.Options{
    DeploymentOptions: worker.DeploymentOptions{
        UseVersioning: true,
        Version: worker.WorkerDeploymentVersion{
            DeploymentName: "order-processor",
            BuildId:        "v1.0.0",
        },
        DefaultVersioningBehavior: workflow.VersioningBehaviorPinned,
    },
})

// Version 2 Worker (green) - deployed alongside v1
w2 := worker.New(c, "my-task-queue", worker.Options{
    DeploymentOptions: worker.DeploymentOptions{
        UseVersioning: true,
        Version: worker.WorkerDeploymentVersion{
            DeploymentName: "order-processor",
            BuildId:        "v2.0.0",
        },
        DefaultVersioningBehavior: workflow.VersioningBehaviorPinned,
    },
})
```

### Querying Workflows by Version

The `TemporalWorkerDeploymentVersion` search attribute tracks which version processed each Workflow:

```
WorkflowType = "OrderWorkflow"
    AND ExecutionStatus = "Running"
    AND TemporalWorkerDeploymentVersion = "order-processor:v1.0.0"
```

### Child Workflows and Continue-As-New

- **PINNED Workflows with Continue-As-New:** Remain pinned across all continuations
- **Child Workflows:** Automatically start on same version as pinned Parent, but can move independently if configured with AUTO_UPGRADE (since children can outlive parents)

## Best Practices

1. **Identify open executions first** - Check for running Workflows before deciding if versioning is needed
2. **Use meaningful Change IDs** - Names should describe what changed (e.g., "PaymentProviderSwitch")
3. **Never reuse Change IDs** - Each deployment should use unique Change IDs
4. **Test replay compatibility** - Use `worker.NewWorkflowReplayer()` to verify changes do not break existing histories
5. **Clean up old versions** - Remove unsupported code paths once no executions use them
6. **Choose the right approach:**
   - GetVersion for code-level branching with gradual migration
   - Workflow Type versioning for simple, one-time changes
   - Worker Versioning for deployment-level control with rainbow deploys
