# Go SDK Data Handling

## Overview

The Go SDK uses data converters to serialize/deserialize workflow inputs, outputs, and activity parameters.

## Default Data Converter

The default converter handles:
- `nil`
- `[]byte` (as binary)
- Protobuf messages
- JSON-serializable types (via encoding/json)

## Using Protobuf

```go
import (
    "google.golang.org/protobuf/proto"
    "myapp/pb"  // Generated protobuf code
)

// Activities and workflows can use protobuf messages directly
func ProcessOrderActivity(ctx context.Context, order *pb.Order) (*pb.OrderResult, error) {
    // Process order...
    return &pb.OrderResult{
        OrderId: order.Id,
        Status:  pb.OrderStatus_COMPLETED,
    }, nil
}

func OrderWorkflow(ctx workflow.Context, order *pb.Order) (*pb.OrderResult, error) {
    var result *pb.OrderResult
    err := workflow.ExecuteActivity(ctx, ProcessOrderActivity, order).Get(ctx, &result)
    return result, err
}
```

## Custom Data Converter

Create custom converters for special serialization needs.

```go
import "go.temporal.io/sdk/converter"

type CustomPayloadConverter struct {
    converter.DefaultPayloadConverter
}

func (c *CustomPayloadConverter) ToPayload(value interface{}) (*commonpb.Payload, error) {
    // Custom serialization logic
    return c.DefaultPayloadConverter.ToPayload(value)
}

func (c *CustomPayloadConverter) FromPayload(payload *commonpb.Payload, valuePtr interface{}) error {
    // Custom deserialization logic
    return c.DefaultPayloadConverter.FromPayload(payload, valuePtr)
}

// Apply custom converter
dataConverter := converter.NewCompositeDataConverter(
    converter.NewNilPayloadConverter(),
    converter.NewByteSlicePayloadConverter(),
    &CustomPayloadConverter{},
)

c, err := client.Dial(client.Options{
    DataConverter: dataConverter,
})
```

## Payload Encryption

Encrypt sensitive workflow data using a codec.

```go
import (
    "go.temporal.io/sdk/converter"
    "crypto/aes"
    "crypto/cipher"
    "crypto/rand"
)

type EncryptionCodec struct {
    gcm cipher.AEAD
}

func NewEncryptionCodec(key []byte) (*EncryptionCodec, error) {
    block, err := aes.NewCipher(key)
    if err != nil {
        return nil, err
    }
    gcm, err := cipher.NewGCM(block)
    if err != nil {
        return nil, err
    }
    return &EncryptionCodec{gcm: gcm}, nil
}

func (c *EncryptionCodec) Encode(payloads []*commonpb.Payload) ([]*commonpb.Payload, error) {
    result := make([]*commonpb.Payload, len(payloads))
    for i, p := range payloads {
        // Encrypt each payload
        data, _ := proto.Marshal(p)
        nonce := make([]byte, c.gcm.NonceSize())
        rand.Read(nonce)
        encrypted := c.gcm.Seal(nonce, nonce, data, nil)

        result[i] = &commonpb.Payload{
            Metadata: map[string][]byte{
                "encoding": []byte("binary/encrypted"),
            },
            Data: encrypted,
        }
    }
    return result, nil
}

func (c *EncryptionCodec) Decode(payloads []*commonpb.Payload) ([]*commonpb.Payload, error) {
    result := make([]*commonpb.Payload, len(payloads))
    for i, p := range payloads {
        if string(p.Metadata["encoding"]) == "binary/encrypted" {
            // Decrypt
            nonceSize := c.gcm.NonceSize()
            nonce, ciphertext := p.Data[:nonceSize], p.Data[nonceSize:]
            decrypted, err := c.gcm.Open(nil, nonce, ciphertext, nil)
            if err != nil {
                return nil, err
            }

            decoded := &commonpb.Payload{}
            proto.Unmarshal(decrypted, decoded)
            result[i] = decoded
        } else {
            result[i] = p
        }
    }
    return result, nil
}

// Apply encryption codec
codec, _ := NewEncryptionCodec(encryptionKey)
dataConverter := converter.NewCodecDataConverter(
    converter.GetDefaultDataConverter(),
    codec,
)

c, err := client.Dial(client.Options{
    DataConverter: dataConverter,
})
```

## Search Attributes

Custom searchable fields for workflow visibility.

```go
import "go.temporal.io/sdk/temporal"

// Define typed keys
var (
    OrderIDKey      = temporal.NewSearchAttributeKeyString("OrderId")
    OrderStatusKey  = temporal.NewSearchAttributeKeyString("OrderStatus")
    OrderTotalKey   = temporal.NewSearchAttributeKeyFloat64("OrderTotal")
    CreatedAtKey    = temporal.NewSearchAttributeKeyTime("CreatedAt")
)

// Set at workflow start
options := client.StartWorkflowOptions{
    ID:        "order-123",
    TaskQueue: "orders",
    SearchAttributes: temporal.NewSearchAttributes(
        OrderIDKey.ValueSet("123"),
        OrderStatusKey.ValueSet("pending"),
        OrderTotalKey.ValueSet(99.99),
        CreatedAtKey.ValueSet(time.Now()),
    ),
}

// Upsert from within workflow
workflow.UpsertTypedSearchAttributes(ctx,
    OrderStatusKey.ValueSet("completed"),
)
```

## Workflow Memo

Store arbitrary metadata with workflows (not searchable).

```go
// Set memo at workflow start
options := client.StartWorkflowOptions{
    ID:        "order-123",
    TaskQueue: "orders",
    Memo: map[string]interface{}{
        "customerName": order.CustomerName,
        "notes":        "Priority customer",
    },
}

// Read memo from workflow
func OrderWorkflow(ctx workflow.Context, order Order) (string, error) {
    info := workflow.GetInfo(ctx)
    memo := info.Memo
    // Memo fields need to be decoded from payload
    return "", nil
}
```

## SideEffect for Non-Deterministic Values

Use `SideEffect` to capture values that would otherwise be non-deterministic.

```go
func WorkflowWithUUID(ctx workflow.Context) (string, error) {
    var uuid string
    err := workflow.SideEffect(ctx, func(ctx workflow.Context) interface{} {
        return generateUUID()
    }).Get(&uuid)
    if err != nil {
        return "", err
    }

    return uuid, nil
}

func WorkflowWithRandom(ctx workflow.Context) (int, error) {
    var randomNum int
    err := workflow.SideEffect(ctx, func(ctx workflow.Context) interface{} {
        return rand.Intn(100)
    }).Get(&randomNum)
    if err != nil {
        return 0, err
    }

    return randomNum, nil
}
```

## MutableSideEffect

Use `MutableSideEffect` when the value might change and you want to capture updates.

```go
func WorkflowWithConfig(ctx workflow.Context) error {
    var config Config

    // Get initial config, and update if it changes
    encoded := workflow.MutableSideEffect(ctx, "config", func(ctx workflow.Context) interface{} {
        return fetchCurrentConfig()
    }, func(a, b interface{}) bool {
        return reflect.DeepEqual(a, b)
    })

    err := encoded.Get(&config)
    if err != nil {
        return err
    }

    // Use config...
    return nil
}
```

## Large Payloads

For large data, consider:

1. **Store externally**: Put large data in S3/GCS, pass references in workflows
2. **Use compression codec**: Compress payloads automatically
3. **Chunk data**: Split large slices across multiple activities

```go
// Example: Reference pattern for large data
func UploadToStorageActivity(ctx context.Context, data []byte) (string, error) {
    key := fmt.Sprintf("data/%s", uuid.New().String())
    err := storageClient.Upload(ctx, key, data)
    return key, err
}

func DownloadFromStorageActivity(ctx context.Context, key string) ([]byte, error) {
    return storageClient.Download(ctx, key)
}
```

## Best Practices

1. Use protobuf for cross-language compatibility
2. Keep payloads small (< 2MB recommended)
3. Encrypt sensitive data with PayloadCodec
4. Store large data externally with references
5. Use structs with proper json tags for JSON converter
6. Use `SideEffect` for random/UUID values in workflows
7. Use typed Search Attribute keys for type safety
