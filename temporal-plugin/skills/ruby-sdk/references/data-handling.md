# Ruby SDK Data Handling

## Overview

The Ruby SDK provides flexible data conversion through payload converters, codecs, and failure converters.

## Data Converter Architecture

```
Ruby Objects
     ↓ (PayloadConverter)
   Payloads
     ↓ (PayloadCodec - optional)
Encoded Payloads
     ↓
 Temporal Server
```

## Default Data Conversion

The default `PayloadConverter` supports:
- `nil`
- "bytes" (`String` with `Encoding::ASCII_8BIT` encoding)
- `Google::Protobuf::MessageExts` instances
- Everything else via Ruby's `JSON` module

### JSON Serialization Behavior

Normal Ruby objects use `JSON.generate` when serializing and `JSON.parse` when deserializing (with `create_additions: true` set by default).

**Important notes:**
- Ruby objects often appear as hashes when deserialized
- Symbol keys become string keys after deserialization
- "JSON Additions" are supported but not cross-SDK-language compatible

## ActiveModel Support

By default, ActiveModel objects don't support the `JSON` module. Add a mixin:

```ruby
module ActiveModelJSONSupport
  extend ActiveSupport::Concern
  include ActiveModel::Serializers::JSON

  included do
    def as_json(*)
      super.merge(::JSON.create_id => self.class.name)
    end

    def to_json(*args)
      as_json.to_json(*args)
    end

    def self.json_create(object)
      object = object.dup
      object.delete(::JSON.create_id)
      new(**object.symbolize_keys)
    end
  end
end

# Usage in your model
class MyModel
  include ActiveModelJSONSupport
  # ...
end
```

## Payload Codecs (Encryption/Compression)

Payload codecs transform bytes to bytes for encryption or compression:

```ruby
require 'openssl'
require 'securerandom'
require 'temporalio/converters'
require 'temporalio/api'
require 'temporalio/converters/payload_codec'

class EncryptionCodec < Temporalio::Converters::PayloadCodec
  DEFAULT_KEY_ID = 'test-key-id'
  DEFAULT_KEY = 'test-key-test-key-test-key-test!'.b

  def initialize(key_id: DEFAULT_KEY_ID, key: DEFAULT_KEY)
    super()
    @key_id = key_id
    @cipher_key = key
  end

  def encode(payloads)
    payloads.map do |p|
      Temporalio::Api::Common::V1::Payload.new(
        metadata: {
          'encoding' => 'binary/encrypted'.b,
          'encryption-key-id' => @key_id.b
        },
        data: encrypt(p.to_proto)
      )
    end
  end

  def decode(payloads)
    payloads.map do |p|
      if p.metadata['encoding'] == 'binary/encrypted'
        key_id = p.metadata['encryption-key-id']
        raise "Unrecognized key ID #{key_id}" unless key_id == @key_id

        Temporalio::Api::Common::V1::Payload.decode(decrypt(p.data))
      else
        p
      end
    end
  end

  private

  def encrypt(data)
    nonce = SecureRandom.random_bytes(12)
    cipher = OpenSSL::Cipher.new('aes-256-gcm')
    cipher.encrypt
    cipher.key = @cipher_key
    cipher.iv = nonce
    nonce + cipher.update(data) + cipher.final + cipher.auth_tag
  end

  def decrypt(data)
    cipher = OpenSSL::Cipher.new('aes-256-gcm')
    cipher.decrypt
    cipher.key = @cipher_key
    cipher.iv = data[0, 12]
    cipher.auth_tag = data[-16, 16]
    cipher.update(data[12...-16]) + cipher.final
  end
end

# Usage
client = Temporalio::Client.connect(
  'localhost:7233', 'default',
  data_converter: Temporalio::Converters::DataConverter.new(
    payload_codec: EncryptionCodec.new
  )
)
```

## Raw Values

Use `Temporalio::Converters::RawValue` to defer conversion or handle dynamic types:

```ruby
class DynamicWorkflow < Temporalio::Workflow::Definition
  workflow_raw_args

  def execute(*args)
    # args are RawValue instances
    first_arg = Temporalio::Workflow.payload_converter.from_payload(
      args[0].payload,
      MyType  # Target type hint
    )

    # Process...
  end
end
```

## Converter Hints

Hints help converters with type information. Define them at activity/workflow level:

```ruby
class MyActivity < Temporalio::Activity::Definition
  # Define expected argument types
  activity_arg_hint MyInputType
  activity_result_hint MyOutputType

  def execute(input)
    # input will be converted to MyInputType
    MyOutputType.new(result: process(input))
  end
end

class MyWorkflow < Temporalio::Workflow::Definition
  workflow_arg_hint OrderInput
  workflow_result_hint OrderResult

  def execute(order_input)
    # order_input will be converted to OrderInput
    OrderResult.new(status: 'completed')
  end
end
```

For signals, queries, and updates:

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  workflow_signal arg_hints: [String, Integer]
  def my_signal(name, count)
    # ...
  end

  workflow_query result_hint: StatusResult
  def get_status
    StatusResult.new(@status)
  end

  workflow_update arg_hints: [UpdateInput], result_hint: UpdateResult
  def my_update(input)
    UpdateResult.new(old_value: @value, new_value: input.value)
  end
end
```

## Best Practices

1. **Don't reuse ActiveRecord models** for Temporal - create separate models specific to workflows/activities
2. **Avoid complex object graphs** that may have circular references
3. **Use `workflow_raw_args`** for dynamic or multi-type scenarios
4. **Encrypt sensitive data** using payload codecs
5. **Test serialization** - ensure types round-trip correctly
6. **Use consistent converters** across all clients and workers
7. **Symbol keys become strings** - be aware of this when deserializing
