# Go SDK Testing

## Overview

The Go SDK provides `testsuite` package for unit testing workflows with activity mocking and time control.

## Test Suite Setup

```go
import (
    "testing"
    "github.com/stretchr/testify/suite"
    "go.temporal.io/sdk/testsuite"
)

type UnitTestSuite struct {
    suite.Suite
    testsuite.WorkflowTestSuite
    env *testsuite.TestWorkflowEnvironment
}

func (s *UnitTestSuite) SetupTest() {
    s.env = s.NewTestWorkflowEnvironment()
}

func (s *UnitTestSuite) AfterTest(suiteName, testName string) {
    s.env.AssertExpectations(s.T())
}

func TestUnitTestSuite(t *testing.T) {
    suite.Run(t, new(UnitTestSuite))
}
```

## Testing Workflows

```go
func (s *UnitTestSuite) TestGreetingWorkflow() {
    s.env.RegisterWorkflow(GreetingWorkflow)
    s.env.RegisterActivity(GreetActivity)

    s.env.ExecuteWorkflow(GreetingWorkflow, "World")

    s.True(s.env.IsWorkflowCompleted())
    s.NoError(s.env.GetWorkflowError())

    var result string
    s.NoError(s.env.GetWorkflowResult(&result))
    s.Equal("Hello, World!", result)
}
```

## Mocking Activities

```go
func (s *UnitTestSuite) TestWithMockedActivity() {
    s.env.RegisterWorkflow(MyWorkflow)

    // Mock activity to return specific value
    s.env.OnActivity(MyActivity, mock.Anything).Return("mocked result", nil)

    s.env.ExecuteWorkflow(MyWorkflow, "input")

    s.True(s.env.IsWorkflowCompleted())
    s.NoError(s.env.GetWorkflowError())
}

func (s *UnitTestSuite) TestActivityError() {
    s.env.RegisterWorkflow(MyWorkflow)

    // Mock activity to return error
    s.env.OnActivity(MyActivity, mock.Anything).Return("", errors.New("activity failed"))

    s.env.ExecuteWorkflow(MyWorkflow, "input")

    s.True(s.env.IsWorkflowCompleted())
    s.Error(s.env.GetWorkflowError())
}
```

## Testing with Timers

```go
func (s *UnitTestSuite) TestWorkflowWithTimer() {
    s.env.RegisterWorkflow(TimerWorkflow)

    // Time automatically advances in test environment
    s.env.ExecuteWorkflow(TimerWorkflow)

    s.True(s.env.IsWorkflowCompleted())
}
```

## Testing Signals

```go
func (s *UnitTestSuite) TestSignalWorkflow() {
    s.env.RegisterWorkflow(SignalWorkflow)

    // Send signal during workflow execution
    s.env.RegisterDelayedCallback(func() {
        s.env.SignalWorkflow("approve-signal", true)
    }, time.Second)

    s.env.ExecuteWorkflow(SignalWorkflow)

    s.True(s.env.IsWorkflowCompleted())
    s.NoError(s.env.GetWorkflowError())
}
```

## Testing Queries

```go
func (s *UnitTestSuite) TestQueryWorkflow() {
    s.env.RegisterWorkflow(QueryableWorkflow)

    // Execute workflow
    s.env.ExecuteWorkflow(QueryableWorkflow)

    // Query result
    result, err := s.env.QueryWorkflow("status")
    s.NoError(err)

    var status string
    s.NoError(result.Get(&status))
    s.Equal("completed", status)
}
```

## Activity Unit Testing

```go
func TestActivity(t *testing.T) {
    // Activities can be tested directly
    ctx := context.Background()
    result, err := GreetActivity(ctx, "World")

    assert.NoError(t, err)
    assert.Equal(t, "Hello, World!", result)
}
```

## Replay Testing for Determinism Verification

### WHY: Verify workflow code changes don't break determinism for existing executions
### WHEN:
- **Before deploying workflow changes** - Ensure backwards compatibility
- **CI/CD pipelines** - Automate determinism checks
- **Debugging non-determinism** - Replay production history locally

Replay testing executes workflow code against recorded event histories to detect non-deterministic changes.

### Using WorkflowReplayer

```go
import (
    "testing"
    "go.temporal.io/sdk/worker"
    "go.temporal.io/sdk/client"
)

func TestReplayWorkflowHistory(t *testing.T) {
    // Create a replayer
    replayer := worker.NewWorkflowReplayer()

    // Register the workflow(s) you want to replay
    replayer.RegisterWorkflow(MyWorkflow)

    // Replay from a JSON history file (exported from Temporal UI or CLI)
    err := replayer.ReplayWorkflowHistoryFromJSONFile(nil, "testdata/workflow_history.json")
    if err != nil {
        t.Fatalf("Replay failed: %v", err)
    }
}
```

### Replaying from History Object

```go
func TestReplayFromHistory(t *testing.T) {
    replayer := worker.NewWorkflowReplayer()
    replayer.RegisterWorkflow(MyWorkflow)

    // Load history from JSON reader
    file, _ := os.Open("testdata/workflow_history.json")
    defer file.Close()

    history, err := client.HistoryFromJSON(file, client.HistoryJSONOptions{})
    if err != nil {
        t.Fatalf("Failed to load history: %v", err)
    }

    // Replay the history
    err = replayer.ReplayWorkflowHistory(nil, history)
    if err != nil {
        t.Fatalf("Replay failed: %v", err)
    }
}
```

### Exporting Workflow History

To get history for replay testing:

```bash
# Using temporal CLI
temporal workflow show --workflow-id my-workflow-id --output json > workflow_history.json

# Or from Temporal UI: Download JSON from workflow execution page
```

### Replay with Options

```go
func TestReplayWithOptions(t *testing.T) {
    replayer := worker.NewWorkflowReplayer()
    replayer.RegisterWorkflow(MyWorkflow)

    err := replayer.ReplayWorkflowHistoryWithOptions(
        nil,
        history,
        worker.ReplayWorkflowHistoryOptions{
            // Add replay options here
        },
    )
    if err != nil {
        t.Fatalf("Replay failed: %v", err)
    }
}
```

## Best Practices

1. Use test suite for consistent setup/teardown
2. Mock activities for isolated workflow testing
3. Register delayed callbacks for signal testing
4. Test error scenarios explicitly
5. Use `mock.Anything` for flexible argument matching
6. **Include replay tests in CI/CD** to catch determinism issues before deployment
7. **Save production histories** from critical workflows for regression testing
8. Test both happy path and error/cancellation paths
