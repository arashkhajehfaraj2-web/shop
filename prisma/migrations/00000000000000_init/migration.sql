-- Stage 04 initial migration
-- Source of truth: Database Design v1.6
-- PostgreSQL >= 15 required (UNIQUE NULLS NOT DISTINCT).
-- This migration is assembled from the supplied Stage 04.1 draft and its stated corrections.
-- It has NOT been executed against a live PostgreSQL database in this environment.

-- STEP 1: extensions and schemas
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gin;

CREATE SCHEMA IF NOT EXISTS reference;
CREATE SCHEMA IF NOT EXISTS eventing;
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS sellers;
CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS media;
CREATE SCHEMA IF NOT EXISTS content;
CREATE SCHEMA IF NOT EXISTS reviews;
CREATE SCHEMA IF NOT EXISTS affiliate;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS currency;
CREATE SCHEMA IF NOT EXISTS discounts;
CREATE SCHEMA IF NOT EXISTS cart;
CREATE SCHEMA IF NOT EXISTS orders;
CREATE SCHEMA IF NOT EXISTS payments;
CREATE SCHEMA IF NOT EXISTS notifications;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE reference.provinces (
  id UUID PRIMARY KEY,
  code VARCHAR(10) NOT NULL UNIQUE,
  name_fa VARCHAR(100) NOT NULL,
  name_en VARCHAR(100) NOT NULL
);

CREATE TABLE reference.cities (
  id UUID PRIMARY KEY,
  province_id UUID NOT NULL REFERENCES reference.provinces(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  code VARCHAR(10) NOT NULL UNIQUE,
  name_fa VARCHAR(100) NOT NULL,
  name_en VARCHAR(100) NOT NULL
);
CREATE INDEX cities_province_id_idx ON reference.cities (province_id);

-- STEP 2: eventing
CREATE TABLE eventing.outbox (
  event_id UUID PRIMARY KEY,
  event_type VARCHAR(80) NOT NULL,
  aggregate_type VARCHAR(40) NOT NULL,
  aggregate_id UUID NOT NULL,
  aggregate_version BIGINT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  correlation_id UUID,
  causation_id UUID,
  publisher VARCHAR(30) NOT NULL,
  schema_version INT NOT NULL DEFAULT 1,
  payload JSONB NOT NULL,
  dispatched_at TIMESTAMPTZ,
  dispatch_attempts INT NOT NULL DEFAULT 0,
  last_error TEXT,
  UNIQUE (aggregate_type, aggregate_id, aggregate_version)
);
CREATE INDEX outbox_aggregate_id_aggregate_version_idx ON eventing.outbox (aggregate_id, aggregate_version);
CREATE INDEX outbox_pending_idx ON eventing.outbox (occurred_at) WHERE dispatched_at IS NULL;

CREATE TABLE eventing.processed_events (
  event_id UUID NOT NULL REFERENCES eventing.outbox(event_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  consumer VARCHAR(60) NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (event_id, consumer)
);

CREATE TABLE eventing.dead_letter_events (
  id UUID PRIMARY KEY,
  event_id UUID NOT NULL REFERENCES eventing.outbox(event_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  consumer VARCHAR(60) NOT NULL,
  payload JSONB NOT NULL,
  error TEXT NOT NULL,
  failed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at TIMESTAMPTZ,
  resolved_by UUID,
  UNIQUE (event_id, consumer)
);

-- STEP 3: identity core
CREATE TABLE identity.users (
  id UUID PRIMARY KEY,
  phone VARCHAR(20) NOT NULL UNIQUE,
  phone_verified_at TIMESTAMPTZ NOT NULL,
  email CITEXT NOT NULL UNIQUE,
  email_verified_at TIMESTAMPTZ NOT NULL,
  password_hash VARCHAR(255),
  password_set_at TIMESTAMPTZ,
  display_name VARCHAR(100),
  status VARCHAR(12) NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (status IN ('active', 'blocked', 'restricted'))
);
CREATE INDEX users_status_idx ON identity.users (status);

CREATE TABLE identity.roles (
  id UUID PRIMARY KEY,
  code VARCHAR(40) NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  is_system BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE identity.permissions (
  id UUID PRIMARY KEY,
  code VARCHAR(80) NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE identity.role_permissions (
  role_id UUID NOT NULL REFERENCES identity.roles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  permission_id UUID NOT NULL REFERENCES identity.permissions(id) ON DELETE CASCADE ON UPDATE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE identity.user_roles (
  user_id UUID NOT NULL REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  role_id UUID NOT NULL REFERENCES identity.roles(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  granted_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, role_id)
);

CREATE TABLE identity.auth_log (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  event_type VARCHAR(30) NOT NULL,
  ip_hash VARCHAR(64),
  user_agent_hash VARCHAR(64),
  correlation_id UUID,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (event_type IN ('registered','login_otp','login_password','recovery_started','recovery_completed','password_set','password_changed','phone_change','email_change','blocked','unblocked','contact_verified'))
);
CREATE INDEX auth_log_user_id_occurred_at_idx ON identity.auth_log (user_id, occurred_at DESC);

-- STEP 4: sellers
CREATE TABLE sellers.sellers (
  id UUID PRIMARY KEY,
  name VARCHAR(200) NOT NULL,
  contact_name VARCHAR(100),
  contact_phone VARCHAR(20),
  contact_email VARCHAR(255),
  status VARCHAR(10) NOT NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (status IN ('active','inactive'))
);
CREATE INDEX sellers_status_idx ON sellers.sellers (status);

-- STEP 5: media
CREATE TABLE media.media_assets (
  id UUID PRIMARY KEY,
  entity_type VARCHAR(30) NOT NULL,
  entity_id UUID,
  kind VARCHAR(20) NOT NULL,
  storage_key VARCHAR(300) NOT NULL UNIQUE,
  variants JSONB NOT NULL DEFAULT '{}'::jsonb,
  mime VARCHAR(100),
  width INT,
  height INT,
  size_bytes BIGINT,
  checksum VARCHAR(64),
  alt_fa VARCHAR(300),
  alt_en VARCHAR(300),
  locale VARCHAR(2),
  uploaded_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (kind IN ('product_image','article_image','brand_image','logo','og_image','report_export','other')),
  CHECK (locale IS NULL OR locale IN ('fa','en'))
);
CREATE INDEX media_assets_entity_type_entity_id_idx ON media.media_assets (entity_type, entity_id);

-- STEP 6: catalog core
CREATE TABLE catalog.categories (
  id UUID PRIMARY KEY,
  parent_id UUID,
  status VARCHAR(10) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  version INT NOT NULL DEFAULT 1,
  created_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  updated_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (status IN ('active','archived')),
  CHECK (parent_id IS NULL OR parent_id <> id),
  FOREIGN KEY (parent_id) REFERENCES catalog.categories(id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX categories_parent_id_idx ON catalog.categories (parent_id);
CREATE INDEX categories_status_idx ON catalog.categories (status);

CREATE TABLE catalog.category_translations (
  category_id UUID NOT NULL REFERENCES catalog.categories(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  locale VARCHAR(2) NOT NULL,
  name VARCHAR(200) NOT NULL,
  slug VARCHAR(200) NOT NULL,
  meta_title VARCHAR(200),
  meta_description VARCHAR(500),
  PRIMARY KEY (category_id, locale),
  UNIQUE (locale, slug),
  CHECK (locale IN ('fa','en'))
);

CREATE TABLE catalog.attribute_definitions (
  id UUID PRIMARY KEY,
  key VARCHAR(60) NOT NULL UNIQUE,
  data_type VARCHAR(10) NOT NULL,
  unit VARCHAR(20),
  is_filterable BOOLEAN NOT NULL DEFAULT false,
  is_comparable BOOLEAN NOT NULL DEFAULT false,
  is_variant_axis BOOLEAN NOT NULL DEFAULT false,
  status VARCHAR(10) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (data_type IN ('text','number','boolean','term','range')),
  CHECK (status IN ('active','archived'))
);

CREATE TABLE catalog.attribute_definition_translations (
  attribute_definition_id UUID NOT NULL REFERENCES catalog.attribute_definitions(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  locale VARCHAR(2) NOT NULL,
  display_name VARCHAR(100) NOT NULL,
  description TEXT,
  PRIMARY KEY (attribute_definition_id, locale),
  CHECK (locale IN ('fa','en'))
);

CREATE TABLE catalog.attribute_terms (
  id UUID PRIMARY KEY,
  attribute_definition_id UUID NOT NULL REFERENCES catalog.attribute_definitions(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  slug VARCHAR(60) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  UNIQUE (attribute_definition_id, slug)
);

CREATE TABLE catalog.attribute_term_translations (
  attribute_term_id UUID NOT NULL REFERENCES catalog.attribute_terms(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  locale VARCHAR(2) NOT NULL,
  value VARCHAR(100) NOT NULL,
  PRIMARY KEY (attribute_term_id, locale),
  CHECK (locale IN ('fa','en'))
);

CREATE TABLE catalog.category_attributes (
  category_id UUID NOT NULL REFERENCES catalog.categories(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  attribute_definition_id UUID NOT NULL REFERENCES catalog.attribute_definitions(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  is_required BOOLEAN NOT NULL DEFAULT false,
  filter_position INT,
  sort_order INT NOT NULL DEFAULT 0,
  PRIMARY KEY (category_id, attribute_definition_id)
);

CREATE TABLE catalog.brands (
  id UUID PRIMARY KEY,
  status VARCHAR(10) NOT NULL,
  created_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  updated_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (status IN ('active','archived'))
);
CREATE INDEX brands_status_idx ON catalog.brands (status);

CREATE TABLE catalog.brand_translations (
  brand_id UUID NOT NULL REFERENCES catalog.brands(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  locale VARCHAR(2) NOT NULL,
  name VARCHAR(200) NOT NULL,
  slug VARCHAR(200) NOT NULL,
  PRIMARY KEY (brand_id, locale),
  UNIQUE (locale, slug),
  CHECK (locale IN ('fa','en'))
);

CREATE TABLE catalog.products (
  id UUID PRIMARY KEY,
  category_id UUID NOT NULL REFERENCES catalog.categories(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  brand_id UUID REFERENCES catalog.brands(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  status VARCHAR(10) NOT NULL,
  version INT NOT NULL DEFAULT 1,
  rating_avg DECIMAL(3,2) NOT NULL DEFAULT 0,
  rating_count INT NOT NULL DEFAULT 0,
  spec_values_fa JSONB NOT NULL,
  spec_values_en JSONB,
  created_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  updated_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  CHECK (status IN ('draft','active','archived')),
  CHECK (rating_avg >= 0 AND rating_avg <= 5 AND rating_count >= 0)
);
CREATE INDEX products_category_id_status_idx ON catalog.products (category_id, status) WHERE deleted_at IS NULL;
CREATE INDEX products_spec_values_fa_idx ON catalog.products USING GIN (spec_values_fa);

CREATE TABLE catalog.product_translations (
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  locale VARCHAR(2) NOT NULL,
  name VARCHAR(300) NOT NULL,
  slug VARCHAR(300) NOT NULL,
  meta_title VARCHAR(200),
  meta_description VARCHAR(500),
  PRIMARY KEY (product_id, locale),
  UNIQUE (locale, slug),
  CHECK (locale IN ('fa','en'))
);
CREATE INDEX product_translations_name_trgm_idx ON catalog.product_translations USING GIN (name gin_trgm_ops);

CREATE TABLE catalog.product_variants (
  id UUID PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  axis_values JSONB NOT NULL,
  sku VARCHAR(64) UNIQUE,
  spec_values_fa JSONB NOT NULL,
  spec_values_en JSONB,
  status VARCHAR(10) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (id, product_id),
  CHECK (status IN ('active','inactive'))
);
CREATE UNIQUE INDEX product_variants_product_id_axis_values_key ON catalog.product_variants (product_id, axis_values);
CREATE INDEX product_variants_product_id_idx ON catalog.product_variants (product_id);

CREATE TABLE catalog.tah_lonji_offers (
  id UUID PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  seller_id UUID NOT NULL REFERENCES sellers.sellers(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  price_irr DECIMAL(18,2) NOT NULL,
  weight_grams INT,
  status VARCHAR(10) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (product_id, seller_id),
  UNIQUE (id, product_id, seller_id),
  UNIQUE (id, product_id),
  CHECK (status IN ('active','inactive')),
  CHECK (price_irr >= 0),
  CHECK (status <> 'active' OR weight_grams IS NOT NULL),
  CHECK (weight_grams IS NULL OR weight_grams > 0)
);
CREATE INDEX tah_lonji_offers_seller_id_idx ON catalog.tah_lonji_offers (seller_id);

CREATE TABLE catalog.product_images (
  id UUID PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  variant_id UUID,
  media_asset_id UUID NOT NULL REFERENCES media.media_assets(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  sort_order INT NOT NULL DEFAULT 0,
  is_primary BOOLEAN NOT NULL DEFAULT false,
  UNIQUE (product_id, media_asset_id),
  FOREIGN KEY (variant_id, product_id) REFERENCES catalog.product_variants(id, product_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE UNIQUE INDEX product_images_product_id_primary_key ON catalog.product_images (product_id) WHERE is_primary;

-- STEP 7: identity favorites (depends on catalog)
CREATE TABLE identity.favorites (
  user_id UUID NOT NULL REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, product_id)
);

-- STEP 8: content
CREATE TABLE content.content_items (
  id UUID PRIMARY KEY,
  type VARCHAR(24) NOT NULL,
  product_id UUID REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  related_product_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  author_user_id UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  status VARCHAR(12) NOT NULL,
  published_at TIMESTAMPTZ,
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (type IN ('product_article','buying_guide','expert_review','editorial_comparison')),
  CHECK (status IN ('draft','in_review','published','archived')),
  CHECK (type <> 'product_article' OR product_id IS NOT NULL)
);
CREATE INDEX content_items_status_idx ON content.content_items (status);
CREATE INDEX content_items_type_idx ON content.content_items (type);
CREATE UNIQUE INDEX content_items_product_id_article_key ON content.content_items (product_id) WHERE type = 'product_article';

CREATE TABLE content.content_translations (
  content_id UUID NOT NULL REFERENCES content.content_items(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  locale VARCHAR(2) NOT NULL,
  title VARCHAR(300) NOT NULL,
  slug VARCHAR(300) NOT NULL,
  body TEXT NOT NULL,
  summary VARCHAR(500),
  source VARCHAR(8) NOT NULL DEFAULT 'human',
  approved_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  approved_at TIMESTAMPTZ,
  meta_title VARCHAR(200),
  meta_description VARCHAR(500),
  PRIMARY KEY (content_id, locale),
  UNIQUE (locale, slug),
  CHECK (locale IN ('fa','en')),
  CHECK (source IN ('human','ai')),
  CHECK (source = 'human' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);

CREATE TABLE content.content_revisions (
  id BIGSERIAL PRIMARY KEY,
  content_id UUID NOT NULL,
  locale VARCHAR(2) NOT NULL,
  revision_no INT NOT NULL,
  snapshot JSONB NOT NULL,
  created_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (content_id, locale, revision_no),
  FOREIGN KEY (content_id, locale) REFERENCES content.content_translations(content_id, locale) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- STEP 9: reviews
CREATE TABLE reviews.reviews (
  id UUID PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  variant_id UUID REFERENCES catalog.product_variants(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  locale VARCHAR(2) NOT NULL,
  reviewer_name VARCHAR(100) NOT NULL,
  user_id UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  rating SMALLINT NOT NULL,
  body TEXT NOT NULL,
  moderation_status VARCHAR(10) NOT NULL DEFAULT 'pending',
  ip_hash VARCHAR(64),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  moderated_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  moderated_at TIMESTAMPTZ,
  moderation_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (locale IN ('fa','en')),
  CHECK (rating BETWEEN 1 AND 5),
  CHECK (moderation_status IN ('pending','approved','rejected','removed'))
);
CREATE INDEX reviews_product_id_moderation_status_submitted_at_idx ON reviews.reviews (product_id, moderation_status, submitted_at DESC);
CREATE INDEX reviews_moderation_status_idx ON reviews.reviews (moderation_status);

CREATE TABLE reviews.review_replies (
  review_id UUID PRIMARY KEY REFERENCES reviews.reviews(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  admin_user_id UUID NOT NULL REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- STEP 10: affiliate
CREATE TABLE affiliate.providers (
  id UUID PRIMARY KEY,
  code VARCHAR(30) NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  status VARCHAR(10) NOT NULL,
  capabilities JSONB NOT NULL DEFAULT '{}'::jsonb,
  config_ref VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (status IN ('active','inactive','pending'))
);

CREATE TABLE affiliate.affiliate_offers (
  id UUID PRIMARY KEY,
  provider_id UUID NOT NULL REFERENCES affiliate.providers(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  variant_id UUID,
  external_product_id VARCHAR(100) NOT NULL,
  external_variant_id VARCHAR(100),
  price_irr DECIMAL(18,2),
  availability_state VARCHAR(12) NOT NULL,
  affiliate_url_data JSONB NOT NULL,
  sync_state VARCHAR(12) NOT NULL,
  last_synced_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (id, provider_id, product_id),
  CHECK (availability_state IN ('in_stock','out_of_stock','unknown')),
  CHECK (sync_state IN ('synced','stale','error','quarantined')),
  CHECK (price_irr IS NULL OR price_irr >= 0),
  CHECK (external_variant_id IS NOT NULL OR variant_id IS NULL),
  FOREIGN KEY (variant_id, product_id) REFERENCES catalog.product_variants(id, product_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE UNIQUE INDEX affiliate_offers_external_identity_key ON affiliate.affiliate_offers (provider_id, external_product_id, external_variant_id) NULLS NOT DISTINCT;
CREATE INDEX affiliate_offers_product_id_idx ON affiliate.affiliate_offers (product_id);

CREATE TABLE affiliate.clicks (
  id BIGSERIAL PRIMARY KEY,
  provider_id UUID NOT NULL REFERENCES affiliate.providers(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  affiliate_offer_id UUID NOT NULL,
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  visitor_hash VARCHAR(64),
  referrer_host VARCHAR(200),
  locale VARCHAR(2),
  user_id UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CHECK (locale IS NULL OR locale IN ('fa','en')),
  FOREIGN KEY (affiliate_offer_id, provider_id, product_id) REFERENCES affiliate.affiliate_offers(id, provider_id, product_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX clicks_product_id_occurred_at_idx ON affiliate.clicks (product_id, occurred_at);
CREATE INDEX clicks_provider_id_occurred_at_idx ON affiliate.clicks (provider_id, occurred_at);
CREATE INDEX clicks_affiliate_offer_id_occurred_at_idx ON affiliate.clicks (affiliate_offer_id, occurred_at);

CREATE TABLE affiliate.sync_runs (
  id UUID PRIMARY KEY,
  provider_id UUID NOT NULL REFERENCES affiliate.providers(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at TIMESTAMPTZ,
  status VARCHAR(10) NOT NULL,
  created_count INT NOT NULL DEFAULT 0,
  updated_count INT NOT NULL DEFAULT 0,
  failed_count INT NOT NULL DEFAULT 0,
  error_summary TEXT,
  CHECK (status IN ('running','succeeded','failed','partial'))
);
CREATE INDEX sync_runs_provider_id_started_at_idx ON affiliate.sync_runs (provider_id, started_at DESC);

-- STEP 11: inventory part 1
CREATE TABLE inventory.stock_levels (
  id UUID PRIMARY KEY,
  offer_id UUID NOT NULL,
  product_id UUID NOT NULL,
  variant_id UUID,
  quantity_on_hand INT NOT NULL,
  quantity_reserved INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL,
  updated_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CHECK (quantity_on_hand >= 0),
  CHECK (quantity_reserved >= 0),
  CHECK (quantity_reserved <= quantity_on_hand),
  FOREIGN KEY (offer_id, product_id) REFERENCES catalog.tah_lonji_offers(id, product_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY (variant_id, product_id) REFERENCES catalog.product_variants(id, product_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE UNIQUE INDEX stock_levels_offer_id_variant_id_key ON inventory.stock_levels (offer_id, variant_id) NULLS NOT DISTINCT;
CREATE INDEX stock_levels_offer_id_idx ON inventory.stock_levels (offer_id);

CREATE TABLE inventory.stock_adjustments (
  id UUID PRIMARY KEY,
  stock_level_id UUID NOT NULL REFERENCES inventory.stock_levels(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  delta INT NOT NULL,
  quantity_before INT NOT NULL,
  quantity_after INT NOT NULL,
  reason TEXT,
  adjusted_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (delta <> 0),
  CHECK (quantity_before + delta = quantity_after)
);
CREATE INDEX stock_adjustments_stock_level_id_idx ON inventory.stock_adjustments (stock_level_id);

-- STEP 12: currency (immutable observations)
CREATE TABLE currency.exchange_rates (
  id UUID PRIMARY KEY,
  source VARCHAR(20) NOT NULL,
  base VARCHAR(10) NOT NULL DEFAULT 'USDT',
  quote VARCHAR(10) NOT NULL DEFAULT 'IRR',
  rate DECIMAL(20,8) NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (rate > 0)
);
CREATE INDEX exchange_rates_source_base_quote_fetched_at_idx ON currency.exchange_rates (source, base, quote, fetched_at DESC, id DESC);

-- STEP 13: discount definitions
CREATE TABLE discounts.discounts (
  id UUID PRIMARY KEY,
  type VARCHAR(30) NOT NULL,
  name VARCHAR(200) NOT NULL,
  value_type VARCHAR(10) NOT NULL,
  value DECIMAL(18,2) NOT NULL,
  min_order_amount_irr DECIMAL(18,2),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ,
  usage_limit_total INT,
  usage_limit_per_user INT,
  status VARCHAR(10) NOT NULL,
  created_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (value >= 0),
  CHECK (value_type IN ('percent','fixed')),
  CHECK (value_type <> 'percent' OR value <= 100),
  CHECK (min_order_amount_irr IS NULL OR min_order_amount_irr >= 0),
  CHECK (status IN ('active','inactive','archived'))
);

CREATE TABLE discounts.coupons (
  id UUID PRIMARY KEY,
  discount_id UUID NOT NULL REFERENCES discounts.discounts(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  code CITEXT NOT NULL UNIQUE,
  status VARCHAR(10) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (id, discount_id),
  CHECK (status IN ('active','inactive'))
);

-- STEP 14: cart
CREATE TABLE cart.carts (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  anon_token VARCHAR(64),
  status VARCHAR(12) NOT NULL,
  converted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (status IN ('active','converted','merged','abandoned')),
  CHECK (num_nonnulls(user_id, anon_token) <= 1),
  CHECK (status <> 'active' OR num_nonnulls(user_id, anon_token) = 1)
);
CREATE UNIQUE INDEX carts_user_id_active_key ON cart.carts (user_id) WHERE status = 'active';
CREATE UNIQUE INDEX carts_anon_token_active_key ON cart.carts (anon_token) WHERE status = 'active';

CREATE TABLE cart.cart_items (
  id UUID PRIMARY KEY,
  cart_id UUID NOT NULL REFERENCES cart.carts(id) ON DELETE CASCADE ON UPDATE CASCADE,
  offer_id UUID NOT NULL,
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  seller_id UUID NOT NULL,
  variant_id UUID,
  quantity INT NOT NULL,
  added_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  CHECK (quantity > 0),
  FOREIGN KEY (offer_id, product_id, seller_id) REFERENCES catalog.tah_lonji_offers(id, product_id, seller_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY (variant_id, product_id) REFERENCES catalog.product_variants(id, product_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE UNIQUE INDEX cart_items_cart_id_offer_id_variant_id_key ON cart.cart_items (cart_id, offer_id, variant_id) NULLS NOT DISTINCT;
CREATE INDEX cart_items_cart_id_idx ON cart.cart_items (cart_id);

-- STEP 15: orders core (payment_id intentionally added at step 17)
CREATE TABLE orders.orders (
  id UUID PRIMARY KEY,
  order_number VARCHAR(20) NOT NULL UNIQUE,
  user_id UUID NOT NULL REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  status VARCHAR(12) NOT NULL,
  gross_items_irr DECIMAL(18,2) NOT NULL,
  line_discount_irr DECIMAL(18,2) NOT NULL,
  order_discount_irr DECIMAL(18,2) NOT NULL,
  shipping_amount_irr DECIMAL(18,2) NOT NULL,
  total_irr DECIMAL(18,2) NOT NULL,
  payment_currency VARCHAR(8) NOT NULL,
  usdt_rate_id UUID REFERENCES currency.exchange_rates(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  total_usdt DECIMAL(20,8),
  shipping_address JSONB NOT NULL,
  placed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (id, user_id),
  CHECK (status IN ('created','paid','processing','shipped','delivered','cancelled','returned','refunded')),
  CHECK (gross_items_irr >= 0 AND shipping_amount_irr >= 0 AND line_discount_irr >= 0 AND order_discount_irr >= 0),
  CHECK (line_discount_irr + order_discount_irr <= gross_items_irr),
  CHECK (total_irr = gross_items_irr + shipping_amount_irr - line_discount_irr - order_discount_irr),
  CHECK (total_irr >= 0),
  CHECK (payment_currency IN ('irr','usdt')),
  CHECK ((payment_currency = 'usdt' AND usdt_rate_id IS NOT NULL AND total_usdt IS NOT NULL AND total_usdt > 0)
      OR (payment_currency = 'irr' AND usdt_rate_id IS NULL AND total_usdt IS NULL))
);
CREATE INDEX orders_user_id_placed_at_idx ON orders.orders (user_id, placed_at DESC);
CREATE INDEX orders_status_placed_at_idx ON orders.orders (status, placed_at DESC);

CREATE TABLE orders.order_sellers (
  order_id UUID NOT NULL REFERENCES orders.orders(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  seller_id UUID NOT NULL REFERENCES sellers.sellers(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  PRIMARY KEY (order_id, seller_id)
);

CREATE TABLE orders.order_lines (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES orders.orders(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  line_no INT NOT NULL,
  product_id UUID NOT NULL REFERENCES catalog.products(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  offer_id UUID NOT NULL,
  seller_id UUID NOT NULL,
  variant_id UUID,
  quantity INT NOT NULL,
  product_snapshot JSONB NOT NULL,
  seller_snapshot JSONB NOT NULL,
  unit_price_irr DECIMAL(18,2) NOT NULL,
  gross_amount_irr DECIMAL(18,2) NOT NULL,
  discount_allocation_irr DECIMAL(18,2) NOT NULL,
  line_total_irr DECIMAL(18,2) NOT NULL,
  commission_rate_pct DECIMAL(6,3) NOT NULL,
  commission_amount_irr DECIMAL(18,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (order_id, line_no),
  CHECK (quantity > 0 AND unit_price_irr >= 0),
  CHECK (gross_amount_irr = unit_price_irr * quantity),
  CHECK (discount_allocation_irr >= 0),
  CHECK (discount_allocation_irr <= gross_amount_irr),
  CHECK (line_total_irr = gross_amount_irr - discount_allocation_irr AND line_total_irr >= 0),
  FOREIGN KEY (order_id, seller_id) REFERENCES orders.order_sellers(order_id, seller_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY (offer_id, product_id, seller_id) REFERENCES catalog.tah_lonji_offers(id, product_id, seller_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY (variant_id, product_id) REFERENCES catalog.product_variants(id, product_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX order_lines_offer_id_created_at_idx ON orders.order_lines (offer_id, created_at);
CREATE INDEX order_lines_order_id_idx ON orders.order_lines (order_id);

CREATE TABLE orders.seller_fulfillments (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL,
  seller_id UUID NOT NULL,
  status VARCHAR(16) NOT NULL,
  transferred_at TIMESTAMPTZ,
  ready_at TIMESTAMPTZ,
  admin_notes TEXT,
  updated_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (order_id, seller_id),
  CHECK (status IN ('pending_transfer','transferred','preparing','ready_to_ship','issue')),
  FOREIGN KEY (order_id, seller_id) REFERENCES orders.order_sellers(order_id, seller_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX seller_fulfillments_order_id_idx ON orders.seller_fulfillments (order_id);

CREATE TABLE orders.shipments (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL UNIQUE REFERENCES orders.orders(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  carrier VARCHAR(50),
  tracking_code VARCHAR(100) UNIQUE,
  shipped_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE orders.order_status_history (
  id BIGSERIAL PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES orders.orders(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  from_status VARCHAR(12),
  to_status VARCHAR(12) NOT NULL,
  actor_type VARCHAR(10) NOT NULL,
  actor_user_id UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  reason TEXT,
  correlation_id UUID,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (actor_type IN ('admin','system','job','api'))
);
CREATE INDEX order_status_history_order_id_idx ON orders.order_status_history (order_id);

-- STEP 16: payments suite (orders exists; orders.payment_id is added in step 17)
CREATE TABLE payments.payments (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES orders.orders(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  attempt_no SMALLINT NOT NULL,
  method VARCHAR(14) NOT NULL,
  provider_code VARCHAR(30) NOT NULL,
  status VARCHAR(10) NOT NULL,
  amount_irr DECIMAL(18,2) NOT NULL,
  amount_usdt DECIMAL(20,8),
  usdt_rate_id UUID REFERENCES currency.exchange_rates(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  idempotency_key VARCHAR(64) NOT NULL UNIQUE,
  provider_txn_ref VARCHAR(100) UNIQUE,
  initiated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  verified_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  failure_reason TEXT,
  callback_metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (id, order_id),
  UNIQUE (order_id, attempt_no),
  CHECK (status IN ('initiated','pending','succeeded','failed','expired')),
  CHECK (method IN ('bank_gateway','usdt')),
  CHECK (amount_irr >= 0),
  CHECK ((method = 'usdt' AND amount_usdt IS NOT NULL AND amount_usdt > 0 AND usdt_rate_id IS NOT NULL)
      OR (method = 'bank_gateway' AND amount_usdt IS NULL AND usdt_rate_id IS NULL))
);
CREATE UNIQUE INDEX payments_order_id_succeeded_key ON payments.payments (order_id) WHERE status = 'succeeded';
CREATE INDEX payments_order_id_status_idx ON payments.payments (order_id, status);

CREATE TABLE payments.succeeded_payments (
  payment_id UUID PRIMARY KEY,
  order_id UUID NOT NULL UNIQUE REFERENCES orders.orders(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  succeeded_at TIMESTAMPTZ NOT NULL,
  UNIQUE (payment_id, order_id),
  FOREIGN KEY (payment_id, order_id) REFERENCES payments.payments(id, order_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE payments.refunds (
  id UUID PRIMARY KEY,
  payment_id UUID NOT NULL,
  order_id UUID NOT NULL,
  amount_irr DECIMAL(18,2),
  amount_usdt DECIMAL(20,8),
  status VARCHAR(10) NOT NULL,
  reason TEXT NOT NULL,
  requested_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  executed_at TIMESTAMPTZ,
  provider_ref VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (status IN ('pending','succeeded','failed')),
  CHECK (num_nonnulls(amount_irr, amount_usdt) = 1),
  CHECK ((amount_irr IS NULL OR amount_irr >= 0) AND (amount_usdt IS NULL OR amount_usdt >= 0)),
  FOREIGN KEY (payment_id, order_id) REFERENCES payments.payments(id, order_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX refunds_payment_id_idx ON payments.refunds (payment_id);

CREATE TABLE payments.commission_rates (
  id UUID PRIMARY KEY,
  rate_pct DECIMAL(6,3) NOT NULL,
  valid_from TIMESTAMPTZ NOT NULL,
  valid_to TIMESTAMPTZ,
  note TEXT,
  created_by UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (rate_pct >= 0 AND rate_pct <= 100)
);
CREATE UNIQUE INDEX commission_rates_single_current_key ON payments.commission_rates ((1)) WHERE valid_to IS NULL;

-- STEP 17: order -> successful payment pointer (after succeeded_payments exists)
ALTER TABLE orders.orders ADD COLUMN payment_id UUID;
ALTER TABLE orders.orders ADD CONSTRAINT orders_payment_id_check CHECK (payment_id IS NULL OR status <> 'created');
ALTER TABLE orders.orders
  ADD CONSTRAINT orders_payment_id_id_fkey
  FOREIGN KEY (payment_id, id)
  REFERENCES payments.succeeded_payments(payment_id, order_id)
  ON DELETE RESTRICT ON UPDATE RESTRICT;

-- STEP 18: reservations + redemptions
CREATE TABLE inventory.reservations (
  id UUID PRIMARY KEY,
  stock_level_id UUID NOT NULL REFERENCES inventory.stock_levels(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  order_id UUID NOT NULL REFERENCES orders.orders(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  quantity INT NOT NULL,
  status VARCHAR(10) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at TIMESTAMPTZ,
  CHECK (quantity > 0),
  CHECK (status IN ('active','committed','released','expired')),
  CHECK ((status = 'active') = (resolved_at IS NULL))
);
CREATE INDEX reservations_status_expires_at_idx ON inventory.reservations (status, expires_at);
CREATE INDEX reservations_order_id_idx ON inventory.reservations (order_id);

CREATE TABLE discounts.redemptions (
  id UUID PRIMARY KEY,
  discount_id UUID NOT NULL REFERENCES discounts.discounts(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  coupon_id UUID,
  order_id UUID NOT NULL,
  user_id UUID NOT NULL,
  amount_irr DECIMAL(18,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (order_id, discount_id),
  CHECK (amount_irr >= 0),
  FOREIGN KEY (coupon_id, discount_id) REFERENCES discounts.coupons(id, discount_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY (order_id, user_id) REFERENCES orders.orders(id, user_id) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX redemptions_discount_id_idx ON discounts.redemptions (discount_id);
CREATE INDEX redemptions_user_id_idx ON discounts.redemptions (user_id);

-- STEP 19: notifications
CREATE TABLE notifications.templates (
  id UUID PRIMARY KEY,
  code VARCHAR(60) NOT NULL,
  channel VARCHAR(10) NOT NULL,
  locale VARCHAR(2) NOT NULL,
  subject VARCHAR(300),
  body TEXT NOT NULL,
  variables JSONB NOT NULL DEFAULT '[]'::jsonb,
  status VARCHAR(10) NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (code, channel, locale),
  CHECK (channel IN ('in_app','email','sms')),
  CHECK (locale IN ('fa','en')),
  CHECK (status IN ('active','inactive'))
);

CREATE TABLE notifications.notifications (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES identity.users(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  recipient VARCHAR(320),
  channel VARCHAR(10) NOT NULL,
  event_type VARCHAR(60) NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(10) NOT NULL,
  attempts INT NOT NULL DEFAULT 0,
  sent_at TIMESTAMPTZ,
  failure_reason TEXT,
  correlation_id UUID,
  dedupe_key VARCHAR(160) UNIQUE,
  outbox_event_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (channel IN ('in_app','email','sms')),
  CHECK (status IN ('queued','sent','failed','dead')),
  CHECK (channel <> 'in_app' OR user_id IS NOT NULL),
  CHECK (channel = 'in_app' OR recipient IS NOT NULL)
);
CREATE INDEX notifications_user_id_created_at_idx ON notifications.notifications (user_id, created_at DESC) WHERE channel = 'in_app';
CREATE INDEX notifications_status_idx ON notifications.notifications (status);

-- STEP 20: analytics (loose references by design, except provider_reports)
CREATE TABLE analytics.events (
  id BIGSERIAL PRIMARY KEY,
  event_type VARCHAR(40) NOT NULL,
  entity_type VARCHAR(30),
  entity_id UUID,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  locale VARCHAR(2),
  visitor_hash VARCHAR(64),
  user_id UUID,
  metadata JSONB
);
CREATE INDEX analytics_events_event_type_occurred_at_idx ON analytics.events (event_type, occurred_at);
CREATE INDEX analytics_events_entity_type_entity_id_occurred_at_idx ON analytics.events (entity_type, entity_id, occurred_at);

CREATE TABLE analytics.product_daily (
  date DATE NOT NULL,
  product_id UUID NOT NULL,
  views INT NOT NULL DEFAULT 0,
  affiliate_clicks INT NOT NULL DEFAULT 0,
  tlh_units_sold INT NOT NULL DEFAULT 0,
  tlh_sales_irr DECIMAL(18,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (date, product_id)
);

CREATE TABLE analytics.content_daily (
  date DATE NOT NULL,
  content_id UUID NOT NULL,
  views INT NOT NULL DEFAULT 0,
  PRIMARY KEY (date, content_id)
);

CREATE TABLE analytics.site_daily (
  date DATE NOT NULL,
  metric_key VARCHAR(40) NOT NULL,
  value DECIMAL(18,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (date, metric_key)
);

CREATE TABLE analytics.provider_reports (
  id UUID PRIMARY KEY,
  provider_id UUID NOT NULL REFERENCES affiliate.providers(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  report_date DATE NOT NULL,
  conversions INT,
  revenue DECIMAL(18,2),
  currency VARCHAR(10) NOT NULL,
  source_note TEXT,
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (provider_id, report_date)
);

-- STEP 21: audit
CREATE TABLE audit.audit_log (
  id BIGSERIAL PRIMARY KEY,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actor_type VARCHAR(10) NOT NULL,
  actor_user_id UUID,
  actor_name VARCHAR(100),
  action VARCHAR(60) NOT NULL,
  resource_type VARCHAR(40) NOT NULL,
  resource_id VARCHAR(64) NOT NULL,
  before JSONB,
  after JSONB,
  correlation_id UUID,
  ip VARCHAR(45),
  CHECK (actor_type IN ('admin','system','job','api'))
);
CREATE INDEX audit_audit_log_resource_type_resource_id_occurred_at_idx ON audit.audit_log (resource_type, resource_id, occurred_at);
CREATE INDEX audit_audit_log_actor_user_id_occurred_at_idx ON audit.audit_log (actor_user_id, occurred_at);

-- NOTE: This migration intentionally does not seed roles/providers. Seed them using db/seed.sql.
-- NOTE: Cross-table totals, stock/reservation transition logic, payment status membership,
-- and order-line immutability remain application/transaction contracts per Database Design v1.6.
