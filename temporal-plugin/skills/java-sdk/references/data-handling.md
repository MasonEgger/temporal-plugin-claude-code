# Java SDK Data Handling

## Overview

The Java SDK uses data converters to serialize/deserialize workflow inputs, outputs, and activity parameters.

## Default Data Converter

The default converter handles:
- `null`
- `byte[]` (as binary)
- Protobuf messages
- Jackson-serializable types (JSON)

## Search Attributes

Custom searchable fields for workflow visibility.

### Defining Typed Search Attribute Keys

```java
import io.temporal.common.SearchAttributeKey;

// Define typed keys for compile-time safety
public class SearchAttributeKeys {
    public static final SearchAttributeKey<String> ORDER_ID =
        SearchAttributeKey.forKeyword("OrderId");
    public static final SearchAttributeKey<String> CUSTOMER_TYPE =
        SearchAttributeKey.forKeyword("CustomerType");
    public static final SearchAttributeKey<Double> ORDER_TOTAL =
        SearchAttributeKey.forDouble("OrderTotal");
    public static final SearchAttributeKey<String> ORDER_STATUS =
        SearchAttributeKey.forKeyword("OrderStatus");
    public static final SearchAttributeKey<OffsetDateTime> CREATED_AT =
        SearchAttributeKey.forOffsetDateTime("CreatedAt");
}
```

### Setting Search Attributes at Start

```java
import io.temporal.common.SearchAttributes;
import io.temporal.client.WorkflowOptions;

WorkflowOptions options = WorkflowOptions.newBuilder()
    .setWorkflowId("order-" + orderId)
    .setTaskQueue("orders")
    .setTypedSearchAttributes(
        SearchAttributes.newBuilder()
            .set(SearchAttributeKeys.ORDER_ID, orderId)
            .set(SearchAttributeKeys.CUSTOMER_TYPE, "premium")
            .set(SearchAttributeKeys.ORDER_TOTAL, 99.99)
            .set(SearchAttributeKeys.CREATED_AT, OffsetDateTime.now())
            .build()
    )
    .build();

OrderWorkflow workflow = client.newWorkflowStub(OrderWorkflow.class, options);
```

### Upserting Search Attributes from Workflow

```java
import io.temporal.workflow.Workflow;

public class OrderWorkflowImpl implements OrderWorkflow {
    @Override
    public String run(Order order) {
        // Update status as workflow progresses
        Workflow.upsertTypedSearchAttributes(
            SearchAttributeKeys.ORDER_STATUS.valueSet("processing")
        );

        activities.processOrder(order);

        Workflow.upsertTypedSearchAttributes(
            SearchAttributeKeys.ORDER_STATUS.valueSet("completed")
        );

        return "done";
    }
}
```

### Reading Search Attributes from Workflow

```java
import io.temporal.workflow.Workflow;

public class OrderWorkflowImpl implements OrderWorkflow {
    @Override
    public void run() {
        var searchAttrs = Workflow.getTypedSearchAttributes();
        String orderId = searchAttrs.get(SearchAttributeKeys.ORDER_ID);
        Double total = searchAttrs.get(SearchAttributeKeys.ORDER_TOTAL);
    }
}
```

## Workflow Memo

Store arbitrary metadata with workflows (not searchable).

```java
import io.temporal.client.WorkflowOptions;
import java.util.Map;

// Set memo at workflow start
WorkflowOptions options = WorkflowOptions.newBuilder()
    .setWorkflowId("order-" + orderId)
    .setTaskQueue("orders")
    .setMemo(Map.of(
        "customerName", order.getCustomerName(),
        "notes", "Priority customer"
    ))
    .build();

// Read memo from workflow
import io.temporal.workflow.Workflow;

public class OrderWorkflowImpl implements OrderWorkflow {
    @Override
    public void run() {
        Map<String, Object> memo = Workflow.getMemo();
        String notes = (String) memo.get("notes");
    }
}
```

## Custom Data Converter

Create custom converters for special serialization needs.

```java
import io.temporal.common.converter.*;

public class CustomDataConverter extends DefaultDataConverter {
    public CustomDataConverter() {
        super(
            new NullPayloadConverter(),
            new ByteArrayPayloadConverter(),
            new ProtobufPayloadConverter(),
            new CustomJsonPayloadConverter()  // Your custom converter
        );
    }
}

// Apply to client
WorkflowClientOptions options = WorkflowClientOptions.newBuilder()
    .setDataConverter(new CustomDataConverter())
    .build();

WorkflowClient client = WorkflowClient.newInstance(service, options);
```

## Payload Codec (Encryption)

Encrypt sensitive workflow data.

```java
import io.temporal.payload.codec.PayloadCodec;
import io.temporal.api.common.v1.Payload;
import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

public class EncryptionCodec implements PayloadCodec {
    private final SecretKeySpec keySpec;

    public EncryptionCodec(byte[] key) {
        this.keySpec = new SecretKeySpec(key, "AES");
    }

    @Override
    public List<Payload> encode(List<Payload> payloads) {
        return payloads.stream()
            .map(this::encrypt)
            .collect(Collectors.toList());
    }

    @Override
    public List<Payload> decode(List<Payload> payloads) {
        return payloads.stream()
            .map(this::decrypt)
            .collect(Collectors.toList());
    }

    private Payload encrypt(Payload payload) {
        try {
            Cipher cipher = Cipher.getInstance("AES");
            cipher.init(Cipher.ENCRYPT_MODE, keySpec);
            byte[] encrypted = cipher.doFinal(payload.getData().toByteArray());

            return Payload.newBuilder()
                .putMetadata("encoding", ByteString.copyFromUtf8("binary/encrypted"))
                .setData(ByteString.copyFrom(encrypted))
                .build();
        } catch (Exception e) {
            throw new RuntimeException("Encryption failed", e);
        }
    }

    private Payload decrypt(Payload payload) {
        String encoding = payload.getMetadataOrDefault("encoding",
            ByteString.EMPTY).toStringUtf8();

        if ("binary/encrypted".equals(encoding)) {
            try {
                Cipher cipher = Cipher.getInstance("AES");
                cipher.init(Cipher.DECRYPT_MODE, keySpec);
                byte[] decrypted = cipher.doFinal(payload.getData().toByteArray());

                return payload.toBuilder()
                    .setData(ByteString.copyFrom(decrypted))
                    .build();
            } catch (Exception e) {
                throw new RuntimeException("Decryption failed", e);
            }
        }
        return payload;
    }
}

// Apply codec
CodecDataConverter codecConverter = new CodecDataConverter(
    DefaultDataConverter.STANDARD_INSTANCE,
    Collections.singletonList(new EncryptionCodec(encryptionKey))
);

WorkflowClientOptions options = WorkflowClientOptions.newBuilder()
    .setDataConverter(codecConverter)
    .build();
```

## Jackson Configuration

Configure JSON serialization with Jackson.

```java
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import io.temporal.common.converter.JacksonJsonPayloadConverter;

// Custom ObjectMapper with Java 8 date/time support
ObjectMapper objectMapper = new ObjectMapper()
    .registerModule(new JavaTimeModule())
    .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

DefaultDataConverter dataConverter = new DefaultDataConverter(
    new NullPayloadConverter(),
    new ByteArrayPayloadConverter(),
    new ProtobufPayloadConverter(),
    new JacksonJsonPayloadConverter(objectMapper)
);
```

## Large Payloads

For large data, consider:

1. **Store externally**: Put large data in S3/GCS, pass references in workflows
2. **Use compression codec**: Compress payloads automatically
3. **Chunk data**: Split large lists across multiple activities

```java
// Example: Reference pattern for large data
@ActivityInterface
public interface StorageActivities {
    String uploadToStorage(byte[] data);
    byte[] downloadFromStorage(String key);
}

public class StorageActivitiesImpl implements StorageActivities {
    @Override
    public String uploadToStorage(byte[] data) {
        String key = "data/" + UUID.randomUUID();
        storageClient.upload(key, data);
        return key;
    }

    @Override
    public byte[] downloadFromStorage(String key) {
        return storageClient.download(key);
    }
}
```

## Best Practices

1. Use typed SearchAttributeKey for compile-time safety
2. Keep payloads small (< 2MB recommended)
3. Encrypt sensitive data with PayloadCodec
4. Store large data externally with references
5. Configure Jackson ObjectMapper for proper date/time handling
6. Use the same data converter on both client and worker
