# GenImg - API Specification

## API Overview

GenImg provides a RESTful API for generating images using multiple AI providers through a unified interface.

**Base URL**: `https://api.genimg.io/v1`

**Authentication**: API Key via Bearer token

**Content Type**: `application/json`

## Authentication

### API Key

All requests must include an API key in the Authorization header:

```http
Authorization: Bearer genimg_sk_1234567890abcdef
```

### Rate Limits

| Tier | Requests/min | Images/month |
|------|--------------|--------------|
| Free | 10 | 50 |
| Starter | 60 | 500 |
| Pro | 300 | 2,000 |
| Business | 1000 | 10,000 |
| Enterprise | Custom | Unlimited |

**Rate Limit Headers**:
```http
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1699564800
```

## API Endpoints

### 1. Generate Image

Create an image generation job.

**Endpoint**: `POST /v1/images/generate`

**Request Body**:
```json
{
  "prompt": "A serene mountain landscape at sunset with cherry blossoms",
  "negative_prompt": "blurry, low quality, watermark",
  "provider": "auto",
  "routing_strategy": "quality",
  "options": {
    "width": 1024,
    "height": 1024,
    "num_images": 1,
    "style": "photorealistic",
    "seed": 42
  },
  "webhook_url": "https://your-app.com/webhook",
  "metadata": {
    "user_id": "usr_123",
    "project": "marketing_campaign"
  }
}
```

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `prompt` | string | Yes | The text description of the image |
| `negative_prompt` | string | No | Things to avoid in the image |
| `provider` | enum | No | Specific provider: `auto`, `hunyuan`, `gemini`, `imagen`, `seedream`, `gpt-image` |
| `routing_strategy` | enum | No | `quality`, `speed`, `cost`, `balanced`. Default: `balanced` |
| `options.width` | integer | No | Image width (512-2048). Default: 1024 |
| `options.height` | integer | No | Image height (512-2048). Default: 1024 |
| `options.num_images` | integer | No | Number of images (1-4). Default: 1 |
| `options.style` | enum | No | `photorealistic`, `artistic`, `anime`, `3d-render`, `sketch` |
| `options.seed` | integer | No | Seed for reproducibility |
| `webhook_url` | string | No | URL to receive completion notification |
| `metadata` | object | No | Custom metadata (max 10 key-value pairs) |

**Response** (202 Accepted):
```json
{
  "id": "job_7a8b9c0d1e2f3g4h",
  "status": "queued",
  "prompt": "A serene mountain landscape at sunset with cherry blossoms",
  "provider": "gemini",
  "routing_strategy": "quality",
  "estimated_completion": "2024-11-05T10:30:00Z",
  "created_at": "2024-11-05T10:25:00Z",
  "priority": "standard",
  "queue_position": 5
}
```

**Example cURL**:
```bash
curl -X POST https://api.genimg.io/v1/images/generate \
  -H "Authorization: Bearer genimg_sk_YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "A serene mountain landscape at sunset",
    "routing_strategy": "quality",
    "options": {
      "width": 1024,
      "height": 1024
    }
  }'
```

### 2. Get Job Status

Retrieve the status of an image generation job.

**Endpoint**: `GET /v1/jobs/{job_id}`

**Response** (200 OK):
```json
{
  "id": "job_7a8b9c0d1e2f3g4h",
  "status": "completed",
  "prompt": "A serene mountain landscape at sunset with cherry blossoms",
  "provider": "gemini",
  "created_at": "2024-11-05T10:25:00Z",
  "started_at": "2024-11-05T10:25:30Z",
  "completed_at": "2024-11-05T10:26:00Z",
  "duration_ms": 30000,
  "images": [
    {
      "id": "img_1a2b3c4d5e6f",
      "url": "https://cdn.genimg.io/images/img_1a2b3c4d5e6f.png",
      "width": 1024,
      "height": 1024,
      "format": "png",
      "size_bytes": 2457600,
      "cdn_url": "https://cdn.genimg.io/images/img_1a2b3c4d5e6f.png",
      "thumbnail_url": "https://cdn.genimg.io/thumbs/img_1a2b3c4d5e6f.jpg"
    }
  ],
  "cost": {
    "amount": 0.05,
    "currency": "USD",
    "provider_cost": 0.04
  },
  "metadata": {
    "user_id": "usr_123",
    "project": "marketing_campaign"
  }
}
```

**Status Values**:
- `queued`: Job is waiting in queue
- `processing`: Job is being processed
- `completed`: Job completed successfully
- `failed`: Job failed
- `cancelled`: Job was cancelled

### 3. List Jobs

Retrieve a list of image generation jobs.

**Endpoint**: `GET /v1/jobs`

**Query Parameters**:
- `limit` (integer): Number of results (1-100). Default: 20
- `offset` (integer): Pagination offset. Default: 0
- `status` (enum): Filter by status: `queued`, `processing`, `completed`, `failed`
- `provider` (string): Filter by provider
- `from_date` (ISO8601): Filter jobs from date
- `to_date` (ISO8601): Filter jobs to date

**Response** (200 OK):
```json
{
  "jobs": [
    {
      "id": "job_7a8b9c0d1e2f3g4h",
      "status": "completed",
      "prompt": "A serene mountain landscape...",
      "provider": "gemini",
      "created_at": "2024-11-05T10:25:00Z",
      "completed_at": "2024-11-05T10:26:00Z"
    }
  ],
  "pagination": {
    "total": 150,
    "limit": 20,
    "offset": 0,
    "has_more": true
  }
}
```

### 4. Cancel Job

Cancel a queued or processing job.

**Endpoint**: `POST /v1/jobs/{job_id}/cancel`

**Response** (200 OK):
```json
{
  "id": "job_7a8b9c0d1e2f3g4h",
  "status": "cancelled",
  "cancelled_at": "2024-11-05T10:27:00Z"
}
```

### 5. Get Image

Retrieve image metadata and URLs.

**Endpoint**: `GET /v1/images/{image_id}`

**Response** (200 OK):
```json
{
  "id": "img_1a2b3c4d5e6f",
  "job_id": "job_7a8b9c0d1e2f3g4h",
  "url": "https://cdn.genimg.io/images/img_1a2b3c4d5e6f.png",
  "cdn_url": "https://cdn.genimg.io/images/img_1a2b3c4d5e6f.png",
  "thumbnail_url": "https://cdn.genimg.io/thumbs/img_1a2b3c4d5e6f.jpg",
  "width": 1024,
  "height": 1024,
  "format": "png",
  "size_bytes": 2457600,
  "created_at": "2024-11-05T10:26:00Z",
  "expires_at": "2024-12-05T10:26:00Z",
  "metadata": {
    "prompt": "A serene mountain landscape...",
    "provider": "gemini",
    "seed": 42
  }
}
```

### 6. Delete Image

Delete an image from storage.

**Endpoint**: `DELETE /v1/images/{image_id}`

**Response** (204 No Content)

### 7. List Providers

Get information about available providers.

**Endpoint**: `GET /v1/providers`

**Response** (200 OK):
```json
{
  "providers": [
    {
      "id": "hunyuan",
      "name": "Tencent Hunyuan Image 3.0",
      "rank": 1,
      "score": 1161,
      "status": "available",
      "features": {
        "max_resolution": "2048x2048",
        "styles": ["photorealistic", "artistic", "anime"],
        "supports_negative_prompt": true,
        "supports_seed": true
      },
      "pricing": {
        "base_cost": 0.06,
        "currency": "USD"
      },
      "performance": {
        "avg_latency_ms": 8000,
        "success_rate": 99.5
      }
    },
    {
      "id": "gemini",
      "name": "Google Gemini 2.5 Flash Image",
      "rank": 1,
      "score": 1154,
      "status": "available",
      "features": {
        "max_resolution": "2048x2048",
        "styles": ["photorealistic", "artistic"],
        "supports_negative_prompt": true,
        "supports_seed": true
      },
      "pricing": {
        "base_cost": 0.04,
        "currency": "USD"
      },
      "performance": {
        "avg_latency_ms": 5000,
        "success_rate": 99.8
      }
    }
  ]
}
```

### 8. Get Usage Statistics

Retrieve usage statistics for your account.

**Endpoint**: `GET /v1/usage`

**Query Parameters**:
- `period` (enum): `day`, `week`, `month`, `year`. Default: `month`
- `from_date` (ISO8601): Start date
- `to_date` (ISO8601): End date

**Response** (200 OK):
```json
{
  "period": "month",
  "from_date": "2024-10-01T00:00:00Z",
  "to_date": "2024-10-31T23:59:59Z",
  "summary": {
    "total_images": 1247,
    "total_cost": 62.35,
    "quota_used": 1247,
    "quota_limit": 2000,
    "quota_remaining": 753
  },
  "by_provider": [
    {
      "provider": "gemini",
      "images": 580,
      "cost": 23.20,
      "avg_latency_ms": 5200
    },
    {
      "provider": "hunyuan",
      "images": 420,
      "cost": 25.20,
      "avg_latency_ms": 8100
    }
  ],
  "by_status": {
    "completed": 1210,
    "failed": 37
  },
  "daily_breakdown": [
    {
      "date": "2024-10-01",
      "images": 45,
      "cost": 2.25
    }
  ]
}
```

### 9. Batch Generate

Generate multiple images with different prompts.

**Endpoint**: `POST /v1/images/batch`

**Request Body**:
```json
{
  "batch": [
    {
      "prompt": "A serene mountain landscape",
      "options": { "width": 1024, "height": 1024 }
    },
    {
      "prompt": "A futuristic city at night",
      "options": { "width": 1024, "height": 1024 }
    }
  ],
  "routing_strategy": "balanced",
  "webhook_url": "https://your-app.com/webhook"
}
```

**Response** (202 Accepted):
```json
{
  "batch_id": "batch_9x8y7z6w5v4u",
  "jobs": [
    { "id": "job_1", "status": "queued" },
    { "id": "job_2", "status": "queued" }
  ],
  "created_at": "2024-11-05T10:30:00Z",
  "estimated_completion": "2024-11-05T10:35:00Z"
}
```

### 10. Webhook Management

#### Register Webhook
**Endpoint**: `POST /v1/webhooks`

**Request Body**:
```json
{
  "url": "https://your-app.com/webhook",
  "events": ["job.completed", "job.failed"],
  "secret": "whsec_your_secret_key"
}
```

**Response** (201 Created):
```json
{
  "id": "wh_1a2b3c4d",
  "url": "https://your-app.com/webhook",
  "events": ["job.completed", "job.failed"],
  "status": "active",
  "created_at": "2024-11-05T10:30:00Z"
}
```

#### List Webhooks
**Endpoint**: `GET /v1/webhooks`

#### Delete Webhook
**Endpoint**: `DELETE /v1/webhooks/{webhook_id}`

## Webhook Events

### Job Completed Event

```json
{
  "event": "job.completed",
  "timestamp": "2024-11-05T10:26:00Z",
  "data": {
    "id": "job_7a8b9c0d1e2f3g4h",
    "status": "completed",
    "images": [
      {
        "id": "img_1a2b3c4d5e6f",
        "url": "https://cdn.genimg.io/images/img_1a2b3c4d5e6f.png"
      }
    ]
  }
}
```

### Job Failed Event

```json
{
  "event": "job.failed",
  "timestamp": "2024-11-05T10:26:00Z",
  "data": {
    "id": "job_7a8b9c0d1e2f3g4h",
    "status": "failed",
    "error": {
      "code": "PROVIDER_ERROR",
      "message": "Provider API returned error",
      "details": "Content policy violation"
    }
  }
}
```

### Webhook Signature Verification

Verify webhook authenticity using HMAC-SHA256:

```javascript
const crypto = require('crypto');

function verifyWebhook(payload, signature, secret) {
  const hmac = crypto.createHmac('sha256', secret);
  const digest = hmac.update(payload).digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(digest)
  );
}

// Usage
const signature = req.headers['x-genimg-signature'];
const isValid = verifyWebhook(req.body, signature, 'whsec_your_secret_key');
```

## Error Responses

### Error Format

```json
{
  "error": {
    "code": "INVALID_PROMPT",
    "message": "Prompt contains prohibited content",
    "details": {
      "field": "prompt",
      "reason": "Content policy violation"
    },
    "request_id": "req_1a2b3c4d",
    "documentation_url": "https://docs.genimg.io/errors/invalid-prompt"
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `INVALID_API_KEY` | 401 | API key is invalid or expired |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `QUOTA_EXCEEDED` | 403 | Monthly quota exceeded |
| `INVALID_PROMPT` | 400 | Prompt validation failed |
| `INVALID_PARAMETERS` | 400 | Request parameters are invalid |
| `JOB_NOT_FOUND` | 404 | Job ID does not exist |
| `PROVIDER_ERROR` | 500 | Provider API returned error |
| `PROVIDER_UNAVAILABLE` | 503 | All providers are unavailable |
| `INTERNAL_ERROR` | 500 | Internal server error |
| `WEBHOOK_FAILED` | 500 | Failed to deliver webhook |

## SDK Examples

### Python SDK

```python
from genimg import GenImg

# Initialize client
client = GenImg(api_key="genimg_sk_YOUR_API_KEY")

# Generate image (async)
job = client.images.generate(
    prompt="A serene mountain landscape at sunset",
    routing_strategy="quality",
    options={
        "width": 1024,
        "height": 1024
    }
)

# Wait for completion
result = job.wait()
print(f"Image URL: {result.images[0].url}")

# Or use callback
def on_complete(job):
    print(f"Job completed: {job.id}")

job = client.images.generate(
    prompt="A futuristic city",
    callback=on_complete
)
```

### JavaScript/TypeScript SDK

```typescript
import { GenImg } from '@genimg/sdk';

// Initialize client
const client = new GenImg({
  apiKey: 'genimg_sk_YOUR_API_KEY'
});

// Generate image (promise-based)
const job = await client.images.generate({
  prompt: 'A serene mountain landscape at sunset',
  routingStrategy: 'quality',
  options: {
    width: 1024,
    height: 1024
  }
});

// Poll for completion
const result = await job.wait();
console.log(`Image URL: ${result.images[0].url}`);

// Or use webhook
const job = await client.images.generate({
  prompt: 'A futuristic city',
  webhookUrl: 'https://your-app.com/webhook'
});
```

### Go SDK

```go
package main

import (
    "context"
    "fmt"
    "github.com/genimg/go-sdk"
)

func main() {
    client := genimg.NewClient("genimg_sk_YOUR_API_KEY")

    // Generate image
    job, err := client.Images.Generate(context.Background(), &genimg.GenerateRequest{
        Prompt: "A serene mountain landscape at sunset",
        RoutingStrategy: genimg.RoutingStrategyQuality,
        Options: &genimg.ImageOptions{
            Width:  1024,
            Height: 1024,
        },
    })

    if err != nil {
        panic(err)
    }

    // Wait for completion
    result, err := job.Wait(context.Background())
    if err != nil {
        panic(err)
    }

    fmt.Printf("Image URL: %s\n", result.Images[0].URL)
}
```

## Best Practices

### 1. Prompt Engineering

**Good Prompts**:
- Be specific and descriptive
- Include style, lighting, and composition details
- Use negative prompts to avoid unwanted elements

```json
{
  "prompt": "Professional food photography of a gourmet burger, studio lighting, shallow depth of field, appetizing, high resolution, commercial quality",
  "negative_prompt": "blurry, amateur, low quality, watermark, text"
}
```

### 2. Provider Selection

- Use `quality` strategy for critical images (marketing, portfolio)
- Use `speed` strategy for previews or drafts
- Use `cost` strategy for bulk generation
- Use `balanced` for general use

### 3. Error Handling

Always implement retry logic with exponential backoff:

```javascript
async function generateWithRetry(client, params, maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await client.images.generate(params);
    } catch (error) {
      if (error.code === 'PROVIDER_UNAVAILABLE' && i < maxRetries - 1) {
        await sleep(Math.pow(2, i) * 1000); // Exponential backoff
        continue;
      }
      throw error;
    }
  }
}
```

### 4. Webhook Usage

- Always verify webhook signatures
- Implement idempotency using job IDs
- Return 200 status quickly (process asynchronously)

```javascript
app.post('/webhook', async (req, res) => {
  // Verify signature first
  if (!verifyWebhook(req.body, req.headers['x-genimg-signature'], secret)) {
    return res.status(401).send('Invalid signature');
  }

  // Return 200 immediately
  res.status(200).send('OK');

  // Process asynchronously
  processWebhook(req.body).catch(console.error);
});
```

### 5. Caching

Cache identical prompts to save costs:

```javascript
const cacheKey = crypto.createHash('md5')
  .update(JSON.stringify(params))
  .digest('hex');

const cached = await redis.get(cacheKey);
if (cached) {
  return JSON.parse(cached);
}

const result = await client.images.generate(params);
await redis.setex(cacheKey, 3600, JSON.stringify(result));
return result;
```

## API Versioning

- Current version: `v1`
- Version specified in URL: `/v1/images/generate`
- Breaking changes will introduce new versions (`v2`, etc.)
- Old versions supported for minimum 12 months
- Deprecation notices sent 6 months in advance

## OpenAPI Specification

Full OpenAPI 3.0 specification available at:
`https://api.genimg.io/openapi.json`

Import into Postman, Insomnia, or use with code generators.

## Support

- **Documentation**: https://docs.genimg.io
- **API Status**: https://status.genimg.io
- **Support Email**: support@genimg.io
- **Discord**: https://discord.gg/genimg
- **GitHub**: https://github.com/genimg/sdk
