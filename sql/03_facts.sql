DROP TABLE IF EXISTS fct_order_items;
CREATE TABLE fct_order_items AS
SELECT i.order_id, i.order_item_id, i.product_id, i.seller_id, p.category,
       i.price, i.freight_value, i.shipping_limit_ts, p.weight_g, p.volume_cm3
FROM stg_order_items i LEFT JOIN dim_product p USING (product_id);

DROP TABLE IF EXISTS fct_orders;
CREATE TABLE fct_orders AS
WITH items AS (
    SELECT order_id, COUNT(*) AS n_items, COUNT(DISTINCT seller_id) AS n_sellers,
           SUM(price) AS item_value, SUM(freight_value) AS freight_value,
           SUM(weight_g) AS weight_g, SUM(volume_cm3) AS volume_cm3,
           MAX(shipping_limit_ts) AS shipping_limit_ts
    FROM fct_order_items GROUP BY order_id),
primary_line AS (
    SELECT order_id, seller_id, category FROM (
        SELECT order_id, seller_id, category,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY price DESC, order_item_id) AS rn
        FROM fct_order_items) WHERE rn = 1),
pay AS (
    SELECT order_id, SUM(payment_value) AS payment_value, MAX(installments) AS installments,
           MAX(CASE WHEN payment_sequential = 1 THEN payment_type END) AS payment_type
    FROM stg_payments GROUP BY order_id),
base AS (
    SELECT o.*, c.customer_unique_id, c.state AS customer_state, c.zip_prefix AS customer_zip,
           pl.seller_id, s.state AS seller_state, s.zip_prefix AS seller_zip, pl.category,
           i.n_items, i.n_sellers, i.item_value, i.freight_value, i.weight_g, i.volume_cm3, i.shipping_limit_ts,
           pay.payment_value, pay.installments, pay.payment_type,
           r.review_score, r.review_creation_date, r.review_answer_ts, r.n_reviews_raw,
           CASE WHEN r.review_comment_message IS NOT NULL THEN 1 ELSE 0 END AS has_comment
    FROM stg_orders o
    JOIN stg_customers c USING (customer_id)
    LEFT JOIN items i USING (order_id)
    LEFT JOIN primary_line pl USING (order_id)
    LEFT JOIN stg_sellers s ON s.seller_id = pl.seller_id
    LEFT JOIN pay USING (order_id)
    LEFT JOIN stg_reviews r USING (order_id))
SELECT order_id, customer_unique_id, order_status,
       purchase_ts, approved_ts, carrier_ts, delivered_ts, estimated_date, shipping_limit_ts,
       date(purchase_ts) AS purchase_date, strftime('%Y-%m', purchase_ts) AS purchase_ym,
       customer_state, customer_zip, seller_id, seller_state, seller_zip, category,
       n_items, n_sellers, item_value, freight_value,
       COALESCE(item_value, 0) + COALESCE(freight_value, 0) AS gmv,
       payment_value, installments, payment_type, weight_g, volume_cm3,
       CAST(julianday(estimated_date) - julianday(date(purchase_ts)) AS INTEGER) AS promised_days,
       CASE WHEN delivered_ts IS NOT NULL
            THEN CAST(julianday(date(delivered_ts)) - julianday(date(purchase_ts)) AS INTEGER) END AS actual_days,
       CASE WHEN delivered_ts IS NOT NULL
            THEN CAST(julianday(date(delivered_ts)) - julianday(estimated_date) AS INTEGER) END AS delay_days,
       CASE WHEN delivered_ts IS NOT NULL AND date(delivered_ts) > estimated_date THEN 1
            WHEN delivered_ts IS NOT NULL THEN 0 END AS is_late,
       CASE WHEN order_status = 'delivered' AND delivered_ts IS NOT NULL THEN 1 ELSE 0 END AS is_delivered,
       (julianday(approved_ts)  - julianday(purchase_ts)) AS stage_approval_days,
       (julianday(carrier_ts)   - julianday(approved_ts)) AS stage_seller_days,
       (julianday(delivered_ts) - julianday(carrier_ts))  AS stage_carrier_days,
       CASE WHEN carrier_ts > shipping_limit_ts THEN 1 ELSE 0 END AS seller_shipped_late,
       review_score, review_creation_date, review_answer_ts, n_reviews_raw, has_comment,
       CASE WHEN review_creation_date IS NOT NULL AND delivered_ts IS NOT NULL
            THEN CASE WHEN review_creation_date < date(delivered_ts) THEN 1 ELSE 0 END END AS review_before_delivery
FROM base;

DROP TABLE IF EXISTS fct_customer_orders;
CREATE TABLE fct_customer_orders AS
SELECT customer_unique_id, order_id, purchase_ts, delivered_ts, is_late, gmv,
       ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_ts, order_id) AS order_seq,
       LEAD(purchase_ts) OVER (PARTITION BY customer_unique_id ORDER BY purchase_ts, order_id) AS next_purchase_ts
FROM fct_orders
WHERE order_status NOT IN ('canceled', 'unavailable');
