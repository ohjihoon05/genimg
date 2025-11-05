-- GenImg Database Schema
-- PostgreSQL 15+
--
-- This schema supports:
-- - User management and authentication
-- - API key management
-- - Image generation jobs and results
-- - Provider metrics and performance tracking
-- - Usage analytics and billing
-- - Webhook management

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- USERS AND AUTHENTICATION
-- =============================================================================

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    company VARCHAR(255),
    role VARCHAR(50) DEFAULT 'user' CHECK (role IN ('user', 'admin', 'enterprise')),
    email_verified BOOLEAN DEFAULT FALSE,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_created_at ON users(created_at);

-- API Keys table
CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    key_hash VARCHAR(255) UNIQUE NOT NULL,
    key_prefix VARCHAR(20) NOT NULL, -- For display (e.g., "genimg_sk_abc...")
    scopes TEXT[] DEFAULT ARRAY['images:read', 'images:write'],
    rate_limit_per_minute INTEGER DEFAULT 60,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
    last_used_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX idx_api_keys_key_hash ON api_keys(key_hash);
CREATE INDEX idx_api_keys_status ON api_keys(status);

-- Sessions table (for web dashboard)
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) UNIQUE NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_token_hash ON sessions(token_hash);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);

-- =============================================================================
-- SUBSCRIPTIONS AND BILLING
-- =============================================================================

-- Subscription tiers
CREATE TYPE subscription_tier AS ENUM ('free', 'starter', 'pro', 'business', 'enterprise');
CREATE TYPE subscription_status AS ENUM ('active', 'cancelled', 'past_due', 'trialing');
CREATE TYPE billing_cycle AS ENUM ('monthly', 'yearly');

-- Subscriptions table
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tier subscription_tier NOT NULL DEFAULT 'free',
    status subscription_status NOT NULL DEFAULT 'active',
    billing_cycle billing_cycle DEFAULT 'monthly',
    price_cents INTEGER NOT NULL DEFAULT 0,
    currency VARCHAR(3) DEFAULT 'USD',
    stripe_customer_id VARCHAR(255),
    stripe_subscription_id VARCHAR(255),
    current_period_start TIMESTAMP WITH TIME ZONE,
    current_period_end TIMESTAMP WITH TIME ZONE,
    cancel_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_subscriptions_stripe_customer_id ON subscriptions(stripe_customer_id);

-- Usage quotas table
CREATE TABLE usage_quotas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    monthly_limit INTEGER NOT NULL,
    used INTEGER DEFAULT 0,
    overage_allowed BOOLEAN DEFAULT FALSE,
    reset_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT usage_within_limit CHECK (NOT overage_allowed OR used <= monthly_limit * 1.2)
);

CREATE UNIQUE INDEX idx_usage_quotas_user_id ON usage_quotas(user_id);
CREATE INDEX idx_usage_quotas_reset_at ON usage_quotas(reset_at);

-- Invoices table
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    amount_cents INTEGER NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),
    period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    period_end TIMESTAMP WITH TIME ZONE NOT NULL,
    stripe_invoice_id VARCHAR(255),
    paid_at TIMESTAMP WITH TIME ZONE,
    due_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_invoices_user_id ON invoices(user_id);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_created_at ON invoices(created_at);

-- =============================================================================
-- PROVIDERS
-- =============================================================================

-- Provider types
CREATE TYPE provider_type AS ENUM ('hunyuan', 'gemini', 'imagen', 'seedream', 'gpt-image');

-- Providers table (configuration and metadata)
CREATE TABLE providers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type provider_type UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    rank INTEGER NOT NULL,
    score DECIMAL(6, 2) NOT NULL,
    organization VARCHAR(255) NOT NULL,
    license VARCHAR(100),
    api_endpoint TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'available' CHECK (status IN ('available', 'degraded', 'unavailable')),
    max_resolution_width INTEGER DEFAULT 2048,
    max_resolution_height INTEGER DEFAULT 2048,
    supports_negative_prompt BOOLEAN DEFAULT TRUE,
    supports_seed BOOLEAN DEFAULT TRUE,
    base_cost_cents INTEGER NOT NULL, -- Cost in cents per image
    currency VARCHAR(3) DEFAULT 'USD',
    avg_latency_ms INTEGER,
    success_rate DECIMAL(5, 2), -- Percentage (0-100)
    config JSONB, -- Provider-specific configuration
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_providers_type ON providers(type);
CREATE INDEX idx_providers_rank ON providers(rank);
CREATE INDEX idx_providers_status ON providers(status);

-- Provider API keys (for calling external APIs)
CREATE TABLE provider_api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_id UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
    key_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    daily_quota INTEGER,
    daily_used INTEGER DEFAULT 0,
    last_used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_provider_api_keys_provider_id ON provider_api_keys(provider_id);
CREATE INDEX idx_provider_api_keys_is_active ON provider_api_keys(is_active);

-- =============================================================================
-- IMAGE GENERATION
-- =============================================================================

-- Job status types
CREATE TYPE job_status AS ENUM ('queued', 'processing', 'completed', 'failed', 'cancelled');
CREATE TYPE job_priority AS ENUM ('low', 'standard', 'high', 'critical');
CREATE TYPE routing_strategy AS ENUM ('quality', 'speed', 'cost', 'balanced', 'custom');

-- Jobs table
CREATE TABLE jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    api_key_id UUID NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
    status job_status NOT NULL DEFAULT 'queued',
    priority job_priority NOT NULL DEFAULT 'standard',

    -- Request details
    prompt TEXT NOT NULL,
    negative_prompt TEXT,
    provider_type provider_type,
    routing_strategy routing_strategy NOT NULL DEFAULT 'balanced',

    -- Image options
    width INTEGER DEFAULT 1024,
    height INTEGER DEFAULT 1024,
    num_images INTEGER DEFAULT 1,
    style VARCHAR(50),
    seed INTEGER,

    -- Metadata
    metadata JSONB,

    -- Processing details
    selected_provider_id UUID REFERENCES providers(id),
    queue_position INTEGER,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,

    -- Timing
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    queued_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,

    -- Error handling
    error_code VARCHAR(100),
    error_message TEXT,
    error_details JSONB,

    -- Webhook
    webhook_url TEXT,
    webhook_delivered BOOLEAN DEFAULT FALSE,
    webhook_delivered_at TIMESTAMP WITH TIME ZONE,

    -- Cost tracking
    estimated_cost_cents INTEGER,
    actual_cost_cents INTEGER,

    CONSTRAINT valid_dimensions CHECK (width >= 512 AND width <= 2048 AND height >= 512 AND height <= 2048),
    CONSTRAINT valid_num_images CHECK (num_images >= 1 AND num_images <= 4)
);

CREATE INDEX idx_jobs_user_id ON jobs(user_id);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_priority ON jobs(priority);
CREATE INDEX idx_jobs_created_at ON jobs(created_at DESC);
CREATE INDEX idx_jobs_provider_type ON jobs(provider_type);
CREATE INDEX idx_jobs_queue_position ON jobs(queue_position) WHERE status = 'queued';

-- Images table
CREATE TABLE images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Storage
    storage_key VARCHAR(500) NOT NULL, -- S3 key
    url TEXT NOT NULL, -- Direct S3 URL
    cdn_url TEXT NOT NULL, -- CloudFront URL
    thumbnail_url TEXT,

    -- Image properties
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    format VARCHAR(10) DEFAULT 'png',
    size_bytes BIGINT,

    -- Metadata
    prompt TEXT NOT NULL,
    provider_type provider_type NOT NULL,
    generation_time_ms INTEGER,
    seed INTEGER,
    metadata JSONB,

    -- Lifecycle
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE,

    -- User ratings (for quality tracking)
    user_rating INTEGER CHECK (user_rating >= 1 AND user_rating <= 5),
    user_feedback TEXT
);

CREATE INDEX idx_images_job_id ON images(job_id);
CREATE INDEX idx_images_user_id ON images(user_id);
CREATE INDEX idx_images_created_at ON images(created_at DESC);
CREATE INDEX idx_images_expires_at ON images(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX idx_images_provider_type ON images(provider_type);

-- Batch jobs (for bulk generation)
CREATE TABLE batch_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255),
    total_jobs INTEGER NOT NULL,
    completed_jobs INTEGER DEFAULT 0,
    failed_jobs INTEGER DEFAULT 0,
    status VARCHAR(50) DEFAULT 'processing' CHECK (status IN ('processing', 'completed', 'partially_completed', 'failed')),
    webhook_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_batch_jobs_user_id ON batch_jobs(user_id);
CREATE INDEX idx_batch_jobs_status ON batch_jobs(status);

-- Link jobs to batches
ALTER TABLE jobs ADD COLUMN batch_id UUID REFERENCES batch_jobs(id) ON DELETE SET NULL;
CREATE INDEX idx_jobs_batch_id ON jobs(batch_id);

-- =============================================================================
-- ANALYTICS AND METRICS
-- =============================================================================

-- Usage logs (for detailed analytics)
CREATE TABLE usage_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    provider_type provider_type NOT NULL,

    -- Cost
    cost_cents INTEGER NOT NULL,
    provider_cost_cents INTEGER NOT NULL,
    margin_cents INTEGER GENERATED ALWAYS AS (cost_cents - provider_cost_cents) STORED,

    -- Performance
    queue_time_ms INTEGER,
    processing_time_ms INTEGER,
    total_time_ms INTEGER,

    -- Success metrics
    success BOOLEAN NOT NULL,
    error_code VARCHAR(100),

    -- Context
    routing_strategy routing_strategy,
    priority job_priority,

    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_usage_logs_user_id ON usage_logs(user_id);
CREATE INDEX idx_usage_logs_timestamp ON usage_logs(timestamp DESC);
CREATE INDEX idx_usage_logs_provider_type ON usage_logs(provider_type);
CREATE INDEX idx_usage_logs_success ON usage_logs(success);

-- Partitioning by month for better performance
CREATE TABLE usage_logs_y2024m11 PARTITION OF usage_logs
    FOR VALUES FROM ('2024-11-01') TO ('2024-12-01');

-- Provider metrics (aggregated performance data)
CREATE TABLE provider_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_type provider_type NOT NULL,

    -- Time period
    date DATE NOT NULL,
    hour INTEGER CHECK (hour >= 0 AND hour < 24),

    -- Volume
    total_requests INTEGER DEFAULT 0,
    successful_requests INTEGER DEFAULT 0,
    failed_requests INTEGER DEFAULT 0,

    -- Performance
    avg_latency_ms INTEGER,
    p50_latency_ms INTEGER,
    p95_latency_ms INTEGER,
    p99_latency_ms INTEGER,

    -- Cost
    total_cost_cents INTEGER DEFAULT 0,
    avg_cost_cents INTEGER,

    -- Quality
    avg_user_rating DECIMAL(3, 2),

    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (provider_type, date, hour)
);

CREATE INDEX idx_provider_metrics_provider_date ON provider_metrics(provider_type, date DESC);
CREATE INDEX idx_provider_metrics_date ON provider_metrics(date DESC);

-- Provider health checks
CREATE TABLE provider_health_checks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_type provider_type NOT NULL,
    status VARCHAR(50) NOT NULL CHECK (status IN ('healthy', 'degraded', 'unhealthy')),
    response_time_ms INTEGER,
    error_message TEXT,
    checked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_provider_health_checks_provider ON provider_health_checks(provider_type);
CREATE INDEX idx_provider_health_checks_checked_at ON provider_health_checks(checked_at DESC);

-- =============================================================================
-- WEBHOOKS
-- =============================================================================

-- Webhook configurations
CREATE TABLE webhooks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    secret VARCHAR(255) NOT NULL,
    events TEXT[] NOT NULL DEFAULT ARRAY['job.completed', 'job.failed'],
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'failed')),
    failure_count INTEGER DEFAULT 0,
    last_failure_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_webhooks_user_id ON webhooks(user_id);
CREATE INDEX idx_webhooks_status ON webhooks(status);

-- Webhook delivery logs
CREATE TABLE webhook_deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    webhook_id UUID NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    event VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(50) NOT NULL CHECK (status IN ('pending', 'delivered', 'failed')),
    response_status_code INTEGER,
    response_body TEXT,
    attempt_count INTEGER DEFAULT 0,
    next_retry_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_webhook_deliveries_webhook_id ON webhook_deliveries(webhook_id);
CREATE INDEX idx_webhook_deliveries_job_id ON webhook_deliveries(job_id);
CREATE INDEX idx_webhook_deliveries_status ON webhook_deliveries(status);
CREATE INDEX idx_webhook_deliveries_next_retry ON webhook_deliveries(next_retry_at) WHERE status = 'pending';

-- =============================================================================
-- FUNCTIONS AND TRIGGERS
-- =============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to relevant tables
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_usage_quotas_updated_at BEFORE UPDATE ON usage_quotas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_providers_updated_at BEFORE UPDATE ON providers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_webhooks_updated_at BEFORE UPDATE ON webhooks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to automatically update usage quota
CREATE OR REPLACE FUNCTION increment_usage_quota()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        UPDATE usage_quotas
        SET used = used + NEW.num_images
        WHERE user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_quota_on_job_complete AFTER UPDATE ON jobs
    FOR EACH ROW EXECUTE FUNCTION increment_usage_quota();

-- Function to update batch job progress
CREATE OR REPLACE FUNCTION update_batch_progress()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IN ('completed', 'failed') AND NEW.batch_id IS NOT NULL THEN
        UPDATE batch_jobs
        SET
            completed_jobs = completed_jobs + CASE WHEN NEW.status = 'completed' THEN 1 ELSE 0 END,
            failed_jobs = failed_jobs + CASE WHEN NEW.status = 'failed' THEN 1 ELSE 0 END,
            status = CASE
                WHEN (completed_jobs + failed_jobs + 1) >= total_jobs THEN
                    CASE WHEN (failed_jobs + CASE WHEN NEW.status = 'failed' THEN 1 ELSE 0 END) > 0
                    THEN 'partially_completed'
                    ELSE 'completed'
                    END
                ELSE 'processing'
            END,
            completed_at = CASE
                WHEN (completed_jobs + failed_jobs + 1) >= total_jobs THEN CURRENT_TIMESTAMP
                ELSE NULL
            END
        WHERE id = NEW.batch_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_batch_on_job_complete AFTER UPDATE ON jobs
    FOR EACH ROW EXECUTE FUNCTION update_batch_progress();

-- =============================================================================
-- SEED DATA (for development/testing)
-- =============================================================================

-- Insert provider data based on rankings
INSERT INTO providers (type, name, rank, score, organization, license, api_endpoint, base_cost_cents, max_resolution_width, max_resolution_height) VALUES
('hunyuan', 'Tencent Hunyuan Image 3.0', 1, 1161, 'Tencent', 'tencent-hunyuan-community', 'https://api.hunyuan.tencent.com/v1', 6, 2048, 2048),
('gemini', 'Google Gemini 2.5 Flash Image', 1, 1154, 'Google', 'Proprietary', 'https://generativelanguage.googleapis.com/v1', 4, 2048, 2048),
('imagen', 'Google Imagen 4.0 Ultra', 3, 1145, 'Google', 'Proprietary', 'https://imagen.googleapis.com/v1', 8, 2048, 2048),
('seedream', 'Bytedance Seedream 4', 3, 1144, 'Bytedance', 'Proprietary', 'https://api.seedream.bytedance.com/v1', 5, 2048, 2048),
('gpt-image', 'OpenAI GPT Image 1', 7, 1123, 'OpenAI', 'Proprietary', 'https://api.openai.com/v1/images', 7, 2048, 2048);

-- =============================================================================
-- VIEWS (for common queries)
-- =============================================================================

-- Active users with current subscription info
CREATE VIEW active_users_with_subscriptions AS
SELECT
    u.id,
    u.email,
    u.first_name,
    u.last_name,
    u.created_at,
    s.tier,
    s.status as subscription_status,
    uq.monthly_limit,
    uq.used as monthly_used,
    uq.monthly_limit - uq.used as remaining
FROM users u
LEFT JOIN subscriptions s ON u.id = s.user_id AND s.status = 'active'
LEFT JOIN usage_quotas uq ON u.id = uq.user_id
WHERE u.status = 'active';

-- Job statistics by user
CREATE VIEW user_job_statistics AS
SELECT
    user_id,
    COUNT(*) as total_jobs,
    COUNT(*) FILTER (WHERE status = 'completed') as completed_jobs,
    COUNT(*) FILTER (WHERE status = 'failed') as failed_jobs,
    COUNT(*) FILTER (WHERE status = 'queued') as queued_jobs,
    AVG(EXTRACT(EPOCH FROM (completed_at - created_at))) FILTER (WHERE status = 'completed') as avg_completion_time_seconds,
    SUM(actual_cost_cents) FILTER (WHERE status = 'completed') as total_cost_cents
FROM jobs
GROUP BY user_id;

-- Provider performance summary
CREATE VIEW provider_performance_summary AS
SELECT
    p.type,
    p.name,
    p.rank,
    p.score,
    COUNT(j.id) as total_jobs,
    COUNT(j.id) FILTER (WHERE j.status = 'completed') as successful_jobs,
    ROUND(100.0 * COUNT(j.id) FILTER (WHERE j.status = 'completed') / NULLIF(COUNT(j.id), 0), 2) as success_rate,
    AVG(EXTRACT(EPOCH FROM (j.completed_at - j.started_at)) * 1000) FILTER (WHERE j.status = 'completed') as avg_processing_time_ms,
    AVG(i.user_rating) FILTER (WHERE i.user_rating IS NOT NULL) as avg_user_rating
FROM providers p
LEFT JOIN jobs j ON p.id = j.selected_provider_id
LEFT JOIN images i ON j.id = i.job_id
GROUP BY p.id, p.type, p.name, p.rank, p.score;

-- =============================================================================
-- INDEXES FOR ANALYTICS QUERIES
-- =============================================================================

-- Composite indexes for common analytics queries
CREATE INDEX idx_jobs_user_created_status ON jobs(user_id, created_at DESC, status);
CREATE INDEX idx_usage_logs_user_timestamp ON usage_logs(user_id, timestamp DESC);
CREATE INDEX idx_images_user_created ON images(user_id, created_at DESC);

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE users IS 'User accounts';
COMMENT ON TABLE api_keys IS 'API keys for programmatic access';
COMMENT ON TABLE subscriptions IS 'User subscription information';
COMMENT ON TABLE providers IS 'AI image generation provider configurations';
COMMENT ON TABLE jobs IS 'Image generation jobs';
COMMENT ON TABLE images IS 'Generated images metadata and storage references';
COMMENT ON TABLE usage_logs IS 'Detailed usage analytics for billing and metrics';
COMMENT ON TABLE webhooks IS 'Webhook configurations for event notifications';
