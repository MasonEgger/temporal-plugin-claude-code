# Ruby SDK Versioning

## Overview

Workflow versioning allows you to safely deploy changes to Workflow code without causing non-deterministic errors in running Workflow Executions. The Ruby SDK provides multiple approaches: the Patching API for code-level version management, Workflow Type versioning for incompatible changes, and Worker Versioning for deployment-level control.

## Why Versioning is Needed

When Workers restart after a deployment, they resume open Workflow Executions through History Replay. If the updated Workflow Definition produces a different sequence of Commands than the original code, it causes a non-deterministic error. Versioning ensures backward compatibility by preserving the original execution path for existing workflows while allowing new workflows to use updated code.

## Workflow Versioning with Patching API

### The patched() Method

The `Temporalio::Workflow.patched()` method checks whether a Workflow should run new or old code:

```ruby
class ShippingWorkflow < Temporalio::Workflow::Definition
  def execute
    if Temporalio::Workflow.patched('send-email-instead-of-fax')
      # New code path
      Temporalio::Workflow.execute_activity(
        SendEmailActivity,
        start_to_close_timeout: 300
      )
    else
      # Old code path (for replay of existing workflows)
      Temporalio::Workflow.execute_activity(
        SendFaxActivity,
        start_to_close_timeout: 300
      )
    end
  end
end
```

**How it works:**
- For new executions: `patched()` returns `true` and records a marker in the Workflow history
- For replay with the marker: `patched()` returns `true` (history includes this patch)
- For replay without the marker: `patched()` returns `false` (history predates this patch)

### Three-Step Patching Process

**Step 1: Patch in New Code**

Add the patch with both old and new code paths:

```ruby
class OrderWorkflow < Temporalio::Workflow::Definition
  def execute(order)
    if Temporalio::Workflow.patched('add-fraud-check')
      # New: Run fraud check before payment
      Temporalio::Workflow.execute_activity(
        CheckFraudActivity,
        order,
        start_to_close_timeout: 120
      )
    end

    # Original payment logic runs for both paths
    Temporalio::Workflow.execute_activity(
      ProcessPaymentActivity,
      order,
      start_to_close_timeout: 300
    )
  end
end
```

**Step 2: Deprecate the Patch**

Once all pre-patch Workflow Executions have completed, remove the old code and use `deprecate_patch()`:

```ruby
class OrderWorkflow < Temporalio::Workflow::Definition
  def execute(order)
    Temporalio::Workflow.deprecate_patch('add-fraud-check')

    # Only new code remains
    Temporalio::Workflow.execute_activity(
      CheckFraudActivity,
      order,
      start_to_close_timeout: 120
    )

    Temporalio::Workflow.execute_activity(
      ProcessPaymentActivity,
      order,
      start_to_close_timeout: 300
    )
  end
end
```

**Step 3: Remove the Patch**

After all workflows with the deprecated patch marker have completed, remove the `deprecate_patch()` call entirely:

```ruby
class OrderWorkflow < Temporalio::Workflow::Definition
  def execute(order)
    Temporalio::Workflow.execute_activity(
      CheckFraudActivity,
      order,
      start_to_close_timeout: 120
    )

    Temporalio::Workflow.execute_activity(
      ProcessPaymentActivity,
      order,
      start_to_close_timeout: 300
    )
  end
end
```

### Query Filters for Finding Workflows by Version

Use List Filters to find workflows with specific patch versions:

```bash
# Find running workflows with a specific patch
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion = "add-fraud-check"'

# Find running workflows without any patch (pre-patch versions)
temporal workflow list --query \
  'WorkflowType = "OrderWorkflow" AND ExecutionStatus = "Running" AND TemporalChangeVersion IS NULL'
```

## Workflow Type Versioning

For incompatible changes, create a new Workflow Type instead of using patches:

```ruby
class PizzaWorkflow < Temporalio::Workflow::Definition
  def execute(order)
    # Original implementation
    process_order_v1(order)
  end
end

class PizzaWorkflowV2 < Temporalio::Workflow::Definition
  def execute(order)
    # New implementation with incompatible changes
    process_order_v2(order)
  end
end
```

Register both with the Worker:

```ruby
worker = Temporalio::Worker.new(
  client:,
  task_queue: 'pizza-task-queue',
  workflows: [PizzaWorkflow, PizzaWorkflowV2],
  activities: [MakePizzaActivity, DeliverPizzaActivity]
)
```

Check for open executions before removing the old type:

```bash
temporal workflow list --query 'WorkflowType = "PizzaWorkflow" AND ExecutionStatus = "Running"'
```

## Worker Versioning

Worker Versioning manages versions at the deployment level, allowing multiple Worker versions to run simultaneously.

### Key Concepts

**Worker Deployment**: A logical service grouping similar Workers together (e.g., "order-processor"). All versions of your code live under this umbrella.

**Worker Deployment Version**: A specific snapshot of your code identified by a deployment name and Build ID (e.g., "order-processor:v1.0" or "order-processor:abc123").

### Configuring Workers for Versioning

```ruby
worker = Temporalio::Worker.new(
  client:,
  task_queue: 'my-task-queue',
  workflows: [MyWorkflow],
  activities: [MyActivity],
  deployment_options: Temporalio::Worker::DeploymentOptions.new(
    version: Temporalio::WorkerDeploymentVersion.new(
      deployment_name: 'my-service',
      build_id: ENV['BUILD_ID'] || 'v1.0.0'
    ),
    use_worker_versioning: true,
    default_versioning_behavior: Temporalio::VersioningBehavior::UNSPECIFIED
  )
)
```

**Configuration parameters:**
- `use_worker_versioning`: Enables Worker Versioning
- `version`: Identifies the Worker Deployment Version (deployment name + build ID)
- Build ID: Typically a git commit hash, version number, or timestamp

### PINNED vs AUTO_UPGRADE Behaviors

**PINNED Behavior**

Workflows stay locked to their original Worker version. Mark a workflow as pinned:

```ruby
class StableWorkflow < Temporalio::Workflow::Definition
  workflow_versioning_behavior Temporalio::VersioningBehavior::PINNED

  def execute
    # This workflow will always run on its assigned version
    Temporalio::Workflow.execute_activity(
      ProcessOrderActivity,
      start_to_close_timeout: 300
    )
  end
end
```

**When to use PINNED:**
- Short-running workflows (minutes to hours)
- Consistency is critical (e.g., financial transactions)
- Building new applications and want simplest development experience

**AUTO_UPGRADE Behavior**

Workflows can move to newer versions:

```ruby
class LongRunningWorkflow < Temporalio::Workflow::Definition
  workflow_versioning_behavior Temporalio::VersioningBehavior::AUTO_UPGRADE

  def execute
    # This workflow can be upgraded to newer versions
    # ...
  end
end
```

**When to use AUTO_UPGRADE:**
- Long-running workflows (weeks or months)
- Workflows need to benefit from bug fixes during execution
- Migrating from traditional rolling deployments

**Important:** AUTO_UPGRADE workflows still need patching to handle version transitions safely.

### Deployment Strategies

**Blue-Green Deployments**

Maintain two environments and switch traffic between them:
1. Deploy new code to idle environment
2. Run tests and validation
3. Switch traffic to new environment
4. Keep old environment for instant rollback

**Rainbow Deployments**

Multiple versions run simultaneously:
- New workflows use latest version
- Existing workflows complete on their original version
- Add new versions alongside existing ones
- Gradually sunset old versions as workflows complete

### Querying Workflows by Worker Version

```bash
# Find workflows on a specific Worker version
temporal workflow list --query \
  'TemporalWorkerDeploymentVersion = "my-service:v1.0.0" AND ExecutionStatus = "Running"'
```

## Testing Replay Compatibility

Use the Replayer to verify code changes are compatible with existing histories:

```ruby
require 'temporalio/worker/workflow_replayer'

replayer = Temporalio::Worker::WorkflowReplayer.new(
  workflows: [MyWorkflow]
)

# Load history from JSON file
history_json = File.read('workflow_history.json')

# This will raise if replay detects non-determinism
replayer.replay_workflow(
  workflow_id: 'my-workflow-id',
  history_json: history_json
)
```

## Best Practices

1. **Check for open executions** before removing old code paths
2. **Use descriptive patch IDs** that explain the change (e.g., "add-fraud-check" not "patch-1")
3. **Deploy patches incrementally**: patch, deprecate, remove
4. **Use PINNED for short workflows** to simplify version management
5. **Use AUTO_UPGRADE with patching** for long-running workflows that need updates
6. **Generate Build IDs from code** (git hash) to ensure changes produce new versions
7. **Avoid rolling deployments** for high-availability services with long-running workflows
8. **Test with replay** before deploying changes to catch non-determinism early
