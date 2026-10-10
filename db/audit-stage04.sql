\set ON_ERROR_STOP on

DO $audit$
DECLARE
  schemas text[] := ARRAY['reference','eventing','identity','sellers','catalog','media','content','reviews',
    'affiliate','inventory','currency','discounts','cart','orders','payments','notifications','analytics','audit'];
  n int;
BEGIN
  -- 1. Base tables
  SELECT count(*) INTO n
  FROM information_schema.tables
  WHERE table_schema = ANY (schemas) AND table_type = 'BASE TABLE';
  IF n <> 64 THEN RAISE EXCEPTION 'AUDIT FAIL [1] base tables: % (expected 64)', n; END IF;

  -- 2. Foreign keys
  SELECT count(*) INTO n
  FROM pg_constraint c JOIN pg_namespace ns ON ns.oid = c.connamespace
  WHERE c.contype = 'f' AND ns.nspname = ANY (schemas);
  IF n <> 96 THEN RAISE EXCEPTION 'AUDIT FAIL [2] FKs: % (expected 96)', n; END IF;

  -- 3. Composite foreign keys (one pg_constraint row per FK; count columns in conkey)
  SELECT count(*) INTO n
  FROM pg_constraint c JOIN pg_namespace ns ON ns.oid = c.connamespace
  WHERE c.contype = 'f' AND array_length(c.conkey, 1) > 1 AND ns.nspname = ANY (schemas);
  IF n <> 17 THEN RAISE EXCEPTION 'AUDIT FAIL [3] composite FKs: % (expected 17)', n; END IF;

  -- 4. CHECK constraints
  SELECT count(*) INTO n
  FROM pg_constraint c JOIN pg_namespace ns ON ns.oid = c.connamespace
  WHERE c.contype = 'c' AND ns.nspname = ANY (schemas);
  IF n <> 89 THEN RAISE EXCEPTION 'AUDIT FAIL [4] CHECKs: % (expected 89)', n; END IF;

  -- 5. CASCADE foreign keys
  SELECT count(*) INTO n
  FROM pg_constraint c JOIN pg_namespace ns ON ns.oid = c.connamespace
  WHERE c.contype = 'f' AND c.confdeltype = 'c' AND ns.nspname = ANY (schemas);
  IF n <> 3 THEN RAISE EXCEPTION 'AUDIT FAIL [5] CASCADE FKs: % (expected 3)', n; END IF;

  -- 6. UNIQUE NULLS NOT DISTINCT indexes
  SELECT count(*) INTO n
  FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
  JOIN pg_namespace ns ON ns.oid = ic.relnamespace
  WHERE i.indisunique AND i.indnullsnotdistinct AND ns.nspname = ANY (schemas);
  IF n <> 3 THEN RAISE EXCEPTION 'AUDIT FAIL [6] NND unique indexes: % (expected 3)', n; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_index i WHERE i.indrelid = 'inventory.stock_levels'::regclass
      AND i.indisunique AND i.indnullsnotdistinct
      AND pg_get_indexdef(i.indexrelid) ~* '\(offer_id, variant_id\)'
  ) THEN RAISE EXCEPTION 'AUDIT FAIL [6a] missing NND on inventory.stock_levels(offer_id, variant_id)'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_index i WHERE i.indrelid = 'cart.cart_items'::regclass
      AND i.indisunique AND i.indnullsnotdistinct
      AND pg_get_indexdef(i.indexrelid) ~* '\(cart_id, offer_id, variant_id\)'
  ) THEN RAISE EXCEPTION 'AUDIT FAIL [6b] missing NND on cart.cart_items(cart_id, offer_id, variant_id)'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_index i WHERE i.indrelid = 'affiliate.affiliate_offers'::regclass
      AND i.indisunique AND i.indnullsnotdistinct
      AND pg_get_indexdef(i.indexrelid) ~* '\(provider_id, external_product_id, external_variant_id\)'
  ) THEN RAISE EXCEPTION 'AUDIT FAIL [6c] missing NND on affiliate.affiliate_offers(provider_id, external_product_id, external_variant_id)'; END IF;

  -- 7. Partial indexes: 9 total = 6 unique + 3 non-unique (includes in-app notifications index)
  SELECT count(*) INTO n
  FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
  JOIN pg_namespace ns ON ns.oid = ic.relnamespace
  WHERE i.indpred IS NOT NULL AND ns.nspname = ANY (schemas);
  IF n <> 9 THEN RAISE EXCEPTION 'AUDIT FAIL [7] partial indexes: % (expected 9)', n; END IF;

  SELECT count(*) INTO n
  FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
  JOIN pg_namespace ns ON ns.oid = ic.relnamespace
  WHERE i.indpred IS NOT NULL AND i.indisunique AND ns.nspname = ANY (schemas);
  IF n <> 6 THEN RAISE EXCEPTION 'AUDIT FAIL [7a] partial UNIQUE indexes: % (expected 6)', n; END IF;

  SELECT count(*) INTO n
  FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
  JOIN pg_namespace ns ON ns.oid = ic.relnamespace
  WHERE i.indpred IS NOT NULL AND NOT i.indisunique AND ns.nspname = ANY (schemas);
  IF n <> 3 THEN RAISE EXCEPTION 'AUDIT FAIL [7b] partial non-unique indexes: % (expected 3)', n; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_index i WHERE i.indrelid = 'notifications.notifications'::regclass
      AND NOT i.indisunique
      AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%channel%in_app%'
      AND pg_get_indexdef(i.indexrelid) ILIKE '%user_id, created_at%'
  ) THEN RAISE EXCEPTION 'AUDIT FAIL [7c] missing partial notifications in-app index'; END IF;

  -- 8. The four required JSON/JSONB defaults must exist.
  SELECT count(*) INTO n
  FROM information_schema.columns
  WHERE (table_schema, table_name, column_name) IN (
    ('affiliate','providers','capabilities'),
    ('media','media_assets','variants'),
    ('content','content_items','related_product_ids'),
    ('notifications','templates','variables')
  ) AND column_default IS NOT NULL;
  IF n <> 4 THEN RAISE EXCEPTION 'AUDIT FAIL [8] required JSONB defaults: % (expected 4)', n; END IF;

  RAISE NOTICE 'AUDIT PASS — 64 tables; 96 FKs (17 composite); 89 CHECKs; 3 CASCADE; 3 NND; 9 partial indexes (6 unique + 3 non-unique); 4 JSON/JSONB defaults.';
END
$audit$;

\echo '--- Composite foreign keys (names + definitions; expected 17) ---'
SELECT n.nspname AS schema_name, c.conrelid::regclass AS table_name, c.conname,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
WHERE c.contype = 'f' AND array_length(c.conkey, 1) > 1
  AND n.nspname IN ('reference','eventing','identity','sellers','catalog','media','content','reviews',
                    'affiliate','inventory','currency','discounts','cart','orders','payments',
                    'notifications','analytics','audit')
ORDER BY 1, 2, 3;

\echo '--- CASCADE foreign keys (expected 3) ---'
SELECT n.nspname AS schema_name, c.conrelid::regclass AS table_name, c.conname,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
WHERE c.contype = 'f' AND c.confdeltype = 'c'
  AND n.nspname IN ('reference','eventing','identity','sellers','catalog','media','content','reviews',
                    'affiliate','inventory','currency','discounts','cart','orders','payments',
                    'notifications','analytics','audit')
ORDER BY 1, 2, 3;

\echo '--- Partial indexes (expected 9 = 6 unique + 3 non-unique) ---'
SELECT n.nspname AS schema_name, ic.relname AS index_name, i.indisunique AS is_unique,
       pg_get_expr(i.indpred, i.indrelid) AS predicate,
       pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
JOIN pg_namespace n ON n.oid = ic.relnamespace
WHERE i.indpred IS NOT NULL AND n.nspname = ANY (
  ARRAY['reference','eventing','identity','sellers','catalog','media','content','reviews',
    'affiliate','inventory','currency','discounts','cart','orders','payments','notifications','analytics','audit']
)
ORDER BY 1, 2;

\echo '--- NND unique indexes (expected 3) ---'
SELECT n.nspname AS schema_name, ic.relname AS index_name, pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
JOIN pg_namespace n ON n.oid = ic.relnamespace
WHERE i.indisunique AND i.indnullsnotdistinct AND n.nspname = ANY (
  ARRAY['reference','eventing','identity','sellers','catalog','media','content','reviews',
    'affiliate','inventory','currency','discounts','cart','orders','payments','notifications','analytics','audit']
)
ORDER BY 1, 2;

\echo '--- Required JSON/JSONB defaults (expected 4; review values) ---'
SELECT table_schema, table_name, column_name, column_default
FROM information_schema.columns
WHERE (table_schema, table_name, column_name) IN (
  ('affiliate','providers','capabilities'),
  ('media','media_assets','variants'),
  ('content','content_items','related_product_ids'),
  ('notifications','templates','variables')
)
ORDER BY table_schema, table_name, column_name;
