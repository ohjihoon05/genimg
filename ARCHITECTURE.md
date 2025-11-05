# GenImg - System Architecture

## Architecture Overview

GenImg follows a microservices architecture with clear separation of concerns, designed for scalability, reliability, and maintainability.

## System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         Load Balancer (Nginx)                   │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                ┌───────────────┴───────────────┐
                │                               │
        ┌───────▼────────┐             ┌───────▼────────┐
        │   API Gateway  │             │  Web Dashboard │
        │   (Node.js)    │             │    (React)     │
        └───────┬────────┘             └────────────────┘
                │
        ┌───────┴────────┐
        │                │
┌───────▼────────┐ ┌────▼──────────┐
│  Auth Service  │ │ Image Service │
│   (Node.js)    │ │   (Node.js)   │
└───────┬────────┘ └────┬──────────┘
        │               │
        │       ┌───────┴──────────┬──────────────┐
        │       │                  │              │
        │  ┌────▼────────┐  ┌──────▼─────┐ ┌─────▼──────┐
        │  │ Job Queue   │  │  Provider  │ │  Storage   │
        │  │  (Redis)    │  │  Router    │ │  Manager   │
        │  └────┬────────┘  └──────┬─────┘ └─────┬──────┘
        │       │                  │              │
        │  ┌────▼────────┐  ┌──────▼─────────────────────┐
        │  │  Workers    │  │    Provider Adapters       │
        │  │  (Node.js)  │  │  ┌─────────────────────┐  │
        │  └─────────────┘  │  │ Hunyuan  │ Gemini  │  │
        │                   │  │ Imagen   │ Seedream│  │
        │                   │  │ GPT-Img  │         │  │
        │                   │  └─────────────────────┘  │
        │                   └──────────────────────────┘
        │
┌───────▼────────────────────────────────────────────┐
│              PostgreSQL Database                   │
│  ┌──────────┐ ┌──────────┐ ┌────────────────────┐│
│  │  Users   │ │  Jobs    │ │  Images/Metadata   ││
│  │  API Keys│ │  Usage   │ │  Billing           ││
│  └──────────┘ └──────────┘ └────────────────────┘│
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│           External Services                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │   S3     │ │  Redis   │ │  CDN (CloudFront)│  │
│  │ Storage  │ │  Cache   │ │                  │  │
│  └──────────┘ └──────────┘ └──────────────────┘  │
└────────────────────────────────────────────────────┘
```

## Component Details

### 1. API Gateway
**Technology**: Node.js + Express + TypeScript

**Responsibilities**:
- Request routing and validation
- Rate limiting and throttling
- API key authentication
- Request/response transformation
- Logging and monitoring

**Key Features**:
- OpenAPI/Swagger documentation
- Request schema validation
- CORS handling
- Request ID tracking
- Error standardization

### 2. Auth Service
**Technology**: Node.js + TypeScript + JWT

**Responsibilities**:
- User authentication and authorization
- API key management (generation, rotation, revocation)
- OAuth 2.0 integration
- Session management
- Permission control

**Key Features**:
- JWT token generation/validation
- Refresh token mechanism
- Role-based access control (RBAC)
- Multi-factor authentication (2FA)
- API key scoping

### 3. Image Service
**Technology**: Node.js + TypeScript

**Responsibilities**:
- Image generation request handling
- Job creation and tracking
- Provider selection and routing
- Result aggregation
- Webhook notifications

**Key Features**:
- Async job processing
- Priority queue management
- Provider failover logic
- Result caching
- Webhook management

### 4. Provider Router
**Technology**: Node.js + TypeScript

**Responsibilities**:
- Intelligent provider selection
- Load balancing across providers
- Health checking
- Performance monitoring
- Cost optimization

**Algorithms**:
```typescript
// Routing strategies
enum RoutingStrategy {
  QUALITY,    // Route to highest-ranked model
  SPEED,      // Route to fastest model
  COST,       // Route to cheapest model
  BALANCED,   // Balance between quality/speed/cost
  CUSTOM      // User-specified provider
}

// Provider selection with fallback
async function selectProvider(
  strategy: RoutingStrategy,
  fallbackEnabled: boolean = true
): Promise<Provider> {
  const providers = await getHealthyProviders();
  const selected = await applyStrategy(strategy, providers);

  if (!selected && fallbackEnabled) {
    return await selectFallbackProvider(providers);
  }

  return selected;
}
```

### 5. Provider Adapters
**Technology**: Node.js + TypeScript

**Responsibilities**:
- Normalize API requests/responses across providers
- Handle provider-specific authentication
- Implement retry logic with exponential backoff
- Track provider-specific metrics

**Provider Interface**:
```typescript
interface ProviderAdapter {
  name: string;
  rank: number;
  score: number;

  // Generate image
  generateImage(params: ImageRequest): Promise<ImageResponse>;

  // Check health status
  healthCheck(): Promise<boolean>;

  // Get pricing info
  getPricing(): Promise<PricingInfo>;

  // Transform prompt for provider
  transformPrompt(prompt: string): string;
}
```

**Implemented Adapters**:
1. **HunyuanAdapter** (Tencent Hunyuan Image 3.0)
2. **GeminiAdapter** (Google Gemini 2.5 Flash Image)
3. **ImagenAdapter** (Google Imagen 4.0 Ultra)
4. **SeedreamAdapter** (Bytedance Seedream 4)
5. **GPTImageAdapter** (OpenAI GPT Image 1)

### 6. Job Queue & Workers
**Technology**: Redis + Bull Queue

**Responsibilities**:
- Asynchronous job processing
- Job scheduling and prioritization
- Retry mechanism
- Job state tracking
- Dead letter queue handling

**Queue Types**:
- `high-priority`: Paid users, SLA-critical
- `standard`: Regular paid users
- `low-priority`: Free tier users
- `batch`: Batch processing jobs

**Worker Pools**:
```typescript
// Worker configuration
const workerConfig = {
  highPriority: { concurrency: 50, instances: 10 },
  standard: { concurrency: 30, instances: 5 },
  lowPriority: { concurrency: 10, instances: 2 },
  batch: { concurrency: 100, instances: 3 }
};
```

### 7. Storage Manager
**Technology**: Node.js + AWS SDK

**Responsibilities**:
- Image upload to S3/GCS
- CDN integration
- Image optimization (WebP conversion, compression)
- Thumbnail generation
- Storage lifecycle management

**Storage Strategy**:
- **Hot Storage** (< 7 days): S3 Standard + CloudFront CDN
- **Warm Storage** (7-90 days): S3 Infrequent Access
- **Cold Storage** (> 90 days): S3 Glacier (Enterprise only)
- **Automatic Cleanup**: Based on subscription tier

### 8. Database (PostgreSQL)
**Technology**: PostgreSQL 15 + pgvector extension

**Schema Overview**:
```sql
-- Users and Authentication
users (id, email, password_hash, created_at, updated_at)
api_keys (id, user_id, key_hash, scopes, rate_limit, created_at)
sessions (id, user_id, token, expires_at)

-- Subscriptions and Billing
subscriptions (id, user_id, tier, status, billing_cycle)
usage_quotas (id, user_id, monthly_limit, used, reset_at)
invoices (id, user_id, amount, period, status, paid_at)

-- Image Generation
jobs (id, user_id, status, prompt, provider, priority, created_at)
images (id, job_id, url, cdn_url, metadata, size, created_at)
generations (id, job_id, provider, cost, duration, quality_score)

-- Analytics
usage_logs (id, user_id, job_id, provider, cost, timestamp)
provider_metrics (id, provider, latency, success_rate, date)
```

### 9. Caching Layer (Redis)
**Technology**: Redis 7.0

**Cache Types**:
- **API Response Cache**: 5-minute TTL for identical prompts
- **User Session Cache**: JWT token validation
- **Provider Health Cache**: 30-second TTL
- **Rate Limiting**: Sliding window counters
- **Job Status Cache**: Real-time job updates

## Data Flow

### Image Generation Request Flow

```
1. Client → API Gateway
   POST /v1/images/generate
   Headers: { Authorization: "Bearer API_KEY" }
   Body: { prompt, provider, options }

2. API Gateway → Auth Service
   Validate API key, check rate limits, verify quotas

3. API Gateway → Image Service
   Create job, assign priority based on tier

4. Image Service → Job Queue
   Enqueue job with metadata

5. Worker → Provider Router
   Dequeue job, select optimal provider

6. Provider Router → Provider Adapter
   Route to selected provider (e.g., Gemini)

7. Provider Adapter → External API
   Call provider's image generation API

8. External API → Provider Adapter
   Return generated image URL

9. Provider Adapter → Storage Manager
   Download and store in S3, upload to CDN

10. Storage Manager → Database
    Save image metadata, update job status

11. Worker → Webhook (if configured)
    Notify client of completion

12. Client ← API Gateway (polling/webhook)
    Return image URL and metadata
```

## Scalability Strategy

### Horizontal Scaling
- **API Gateway**: Auto-scaling group (2-20 instances)
- **Workers**: Dynamic scaling based on queue depth
- **Database**: Read replicas (3-5 replicas)

### Vertical Scaling
- **Redis**: Cluster mode with sharding
- **PostgreSQL**: Connection pooling (PgBouncer)

### Geographic Distribution
- **Multi-region deployment**: US-East, US-West, EU, Asia-Pacific
- **CDN**: Global edge locations
- **Database**: Cross-region read replicas

## High Availability

### Redundancy
- Multi-AZ deployment for all services
- Database automated backups (point-in-time recovery)
- Redis cluster with replica sets

### Failover Strategy
- **Provider Failover**: Automatic switch to alternative provider
- **Database Failover**: Automatic promotion of read replica
- **Service Failover**: Health check-based instance replacement

### Circuit Breaker Pattern
```typescript
class CircuitBreaker {
  private failures = 0;
  private threshold = 5;
  private timeout = 60000; // 1 minute
  private state: 'CLOSED' | 'OPEN' | 'HALF_OPEN' = 'CLOSED';

  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailure > this.timeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  private onSuccess() {
    this.failures = 0;
    this.state = 'CLOSED';
  }

  private onFailure() {
    this.failures++;
    if (this.failures >= this.threshold) {
      this.state = 'OPEN';
      this.lastFailure = Date.now();
    }
  }
}
```

## Security Architecture

### API Security
- **Authentication**: API key + JWT
- **Authorization**: RBAC with scopes
- **Rate Limiting**: Token bucket algorithm
- **Input Validation**: Schema validation with Joi/Zod
- **Output Sanitization**: XSS prevention

### Data Security
- **Encryption at Rest**: AES-256
- **Encryption in Transit**: TLS 1.3
- **API Key Storage**: Bcrypt hashing
- **Secret Management**: AWS Secrets Manager / HashiCorp Vault

### Network Security
- **WAF**: AWS WAF with OWASP rules
- **DDoS Protection**: CloudFlare / AWS Shield
- **VPC**: Private subnets for databases and internal services
- **Security Groups**: Principle of least privilege

## Monitoring & Observability

### Metrics Collection
- **Application Metrics**: Prometheus + Grafana
- **Logs**: ELK Stack (Elasticsearch, Logstash, Kibana)
- **Tracing**: Jaeger / OpenTelemetry
- **Uptime Monitoring**: UptimeRobot / Pingdom

### Key Metrics
```typescript
// Performance metrics
const metrics = {
  apiLatency: histogram('api_request_duration_ms'),
  generationTime: histogram('image_generation_duration_ms'),
  providerLatency: histogram('provider_api_latency_ms', ['provider']),

  // Business metrics
  jobsCreated: counter('jobs_created_total', ['tier', 'provider']),
  jobsCompleted: counter('jobs_completed_total', ['tier', 'provider', 'status']),
  imagesGenerated: counter('images_generated_total', ['provider']),

  // Error metrics
  apiErrors: counter('api_errors_total', ['endpoint', 'status_code']),
  providerErrors: counter('provider_errors_total', ['provider', 'error_type']),

  // Resource metrics
  queueDepth: gauge('queue_depth', ['priority']),
  activeWorkers: gauge('active_workers', ['type']),
  dbConnections: gauge('db_connections_active')
};
```

### Alerting
- **Critical**: API downtime, database failures, payment failures
- **Warning**: High error rates, queue backup, slow response times
- **Info**: Deployment events, configuration changes

## Deployment Architecture

### CI/CD Pipeline
```
GitHub → GitHub Actions → Docker Build → ECR Push → ECS Deploy
         ↓
         Unit Tests → Integration Tests → E2E Tests
                      ↓
                      Security Scan (Snyk)
```

### Infrastructure as Code
- **Terraform**: Infrastructure provisioning
- **Ansible**: Configuration management
- **Helm**: Kubernetes deployments (if using K8s)

### Environments
1. **Development**: Local Docker Compose
2. **Staging**: AWS ECS with limited resources
3. **Production**: AWS ECS with auto-scaling
4. **DR (Disaster Recovery)**: Standby environment in different region

## Technology Stack Summary

| Layer | Technology |
|-------|-----------|
| API Gateway | Node.js, Express, TypeScript |
| Backend Services | Node.js, TypeScript |
| Database | PostgreSQL 15 |
| Cache | Redis 7.0 |
| Queue | Redis + Bull |
| Storage | AWS S3 + CloudFront |
| Container | Docker |
| Orchestration | AWS ECS / Kubernetes |
| Load Balancer | AWS ALB / Nginx |
| Monitoring | Prometheus + Grafana |
| Logging | ELK Stack |
| CI/CD | GitHub Actions |
| IaC | Terraform |

## Cost Estimation (Monthly)

### AWS Infrastructure
- ECS/EC2: ~$500
- RDS PostgreSQL: ~$200
- ElastiCache Redis: ~$150
- S3 Storage: ~$100
- CloudFront CDN: ~$200
- Load Balancer: ~$50
**Subtotal**: ~$1,200/month

### Provider API Costs (Variable)
- Depends on usage volume
- Estimated: $0.02 - $0.10 per image
- With 10,000 images/month: ~$500-1,000

### Third-party Services
- Monitoring: ~$100
- Logging: ~$100
- Uptime monitoring: ~$50
**Subtotal**: ~$250/month

**Total Estimated**: ~$2,000-2,500/month for MVP infrastructure

## Future Enhancements

1. **GraphQL API**: Add GraphQL alongside REST
2. **WebSocket Support**: Real-time job status updates
3. **Edge Computing**: Deploy workers closer to users
4. **Machine Learning**: AI-powered prompt enhancement
5. **Blockchain**: NFT minting integration
6. **API Mesh**: Service mesh for advanced routing (Istio)
