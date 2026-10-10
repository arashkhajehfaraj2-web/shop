-- DropIndex
DROP INDEX "affiliate"."affiliate_offers_external_identity_key";

-- DropIndex
DROP INDEX "cart"."cart_items_cart_id_offer_id_variant_id_key";

-- DropIndex
DROP INDEX "cart"."carts_anon_token_active_key";

-- DropIndex
DROP INDEX "cart"."carts_user_id_active_key";

-- DropIndex
DROP INDEX "catalog"."product_translations_name_trgm_idx";

-- DropIndex
DROP INDEX "catalog"."product_variants_product_id_axis_values_key";

-- DropIndex
DROP INDEX "catalog"."products_spec_values_fa_idx";

-- DropIndex
DROP INDEX "content"."content_items_product_id_article_key";

-- DropIndex
DROP INDEX "inventory"."stock_levels_offer_id_variant_id_key";

-- DropIndex
DROP INDEX "notifications"."notifications_user_id_created_at_idx";

-- DropIndex
DROP INDEX "payments"."payments_order_id_succeeded_key";

-- CreateIndex
CREATE UNIQUE INDEX "carts_user_id_active_key" ON "cart"."carts"("user_id") WHERE (status = 'active');

-- CreateIndex
CREATE UNIQUE INDEX "carts_anon_token_active_key" ON "cart"."carts"("anon_token") WHERE (status = 'active');

-- CreateIndex
CREATE UNIQUE INDEX "content_items_product_id_article_key" ON "content"."content_items"("product_id") WHERE (type = 'product_article');

-- CreateIndex
CREATE INDEX "notifications_user_id_created_at_idx" ON "notifications"."notifications"("user_id", "created_at" DESC) WHERE (channel = 'in_app');

-- CreateIndex
CREATE UNIQUE INDEX "payments_order_id_succeeded_key" ON "payments"."payments"("order_id") WHERE (status = 'succeeded');
