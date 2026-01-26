# Ruby SDK Testing

## Overview

The Ruby SDK provides `WorkflowEnvironment` for testing with time-skipping support.

## Time-Skipping Test Environment

```ruby
require 'temporalio/testing'
require 'minitest/autorun'

class WorkflowTest < Minitest::Test
  def test_workflow
    Temporalio::Testing::WorkflowEnvironment.start_time_skipping do |env|
      worker = Temporalio::Worker.new(
        client: env.client,
        task_queue: "test-#{SecureRandom.uuid}",
        workflows: [MyWorkflow],
        activities: [MyActivity]
      )

      worker.run do
        result = env.client.execute_workflow(
          MyWorkflow,
          'input',
          id: "wf-#{SecureRandom.uuid}",
          task_queue: worker.task_queue
        )
        assert_equal 'expected', result
      end
    end
  end
end
```

## RSpec Example

```ruby
require 'temporalio/testing'

RSpec.describe MyWorkflow do
  it 'processes order successfully' do
    Temporalio::Testing::WorkflowEnvironment.start_time_skipping do |env|
      worker = Temporalio::Worker.new(
        client: env.client,
        task_queue: "test-#{SecureRandom.uuid}",
        workflows: [MyWorkflow],
        activities: [MyActivity]
      )

      worker.run do
        result = env.client.execute_workflow(
          MyWorkflow,
          order,
          id: "wf-#{SecureRandom.uuid}",
          task_queue: worker.task_queue
        )
        expect(result).to eq('completed')
      end
    end
  end
end
```

## Activity Testing

```ruby
def test_activity
  env = Temporalio::Testing::ActivityEnvironment.new
  activity = MyActivity.new

  result = env.run(activity, 'arg1', 'arg2')

  assert_equal 'expected', result
end
```

## Testing Signals

```ruby
def test_signal
  Temporalio::Testing::WorkflowEnvironment.start_time_skipping do |env|
    worker = Temporalio::Worker.new(...)

    worker.run do
      handle = env.client.start_workflow(
        ApprovalWorkflow,
        id: "approval-#{SecureRandom.uuid}",
        task_queue: worker.task_queue
      )

      # Send signal
      handle.signal('approve')

      # Wait for result
      result = handle.result
      assert_equal 'Approved!', result
    end
  end
end
```

## Testing Queries

```ruby
def test_query
  Temporalio::Testing::WorkflowEnvironment.start_time_skipping do |env|
    worker = Temporalio::Worker.new(...)

    worker.run do
      handle = env.client.start_workflow(
        StatusWorkflow,
        id: "status-#{SecureRandom.uuid}",
        task_queue: worker.task_queue
      )

      # Query state
      status = handle.query('get_status')
      assert_equal 'running', status
    end
  end
end
```

## Workflow Replay Testing

```ruby
def test_replay
  replayer = Temporalio::Worker::WorkflowReplayer.new(
    workflows: [MyWorkflow]
  )

  history = Temporalio::WorkflowHistory.from_history_json(history_json)
  replayer.replay_workflow(history)
end
```

## ARM Processor Note

The time-skipping test server does not work natively on ARM processors. On macOS ARM, it uses x64 translation.

## Best Practices

1. Use time-skipping for workflows with timers
2. Use unique task queues per test
3. Test signal/query handlers explicitly
4. Test replay compatibility when changing code
5. Use SecureRandom for unique IDs
