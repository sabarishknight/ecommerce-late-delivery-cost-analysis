DROP TABLE IF EXISTS stg_orders;
CREATE TABLE stg_orders AS
SELECT order_id, customer_id, order_status,
       datetime(order_purchase_timestamp)      AS purchase_ts,
       datetime(order_approved_at)             AS approved_ts,
       datetime(order_delivered_carrier_date)  AS carrier_ts,
       datetime(order_delivered_customer_date) AS delivered_ts,
       date(order_estimated_delivery_date)     AS estimated_date
FROM raw_orders;

DROP TABLE IF EXISTS stg_order_items;
CREATE TABLE stg_order_items AS
SELECT order_id, CAST(order_item_id AS INTEGER) AS order_item_id, product_id, seller_id,
       datetime(shipping_limit_date) AS shipping_limit_ts,
       CAST(price AS REAL) AS price, CAST(freight_value AS REAL) AS freight_value
FROM raw_order_items;

DROP TABLE IF EXISTS stg_payments;
CREATE TABLE stg_payments AS
SELECT order_id, CAST(payment_sequential AS INTEGER) AS payment_sequential, payment_type,
       CAST(payment_installments AS INTEGER) AS installments, CAST(payment_value AS REAL) AS payment_value
FROM raw_order_payments;

DROP TABLE IF EXISTS stg_reviews;
CREATE TABLE stg_reviews AS
SELECT order_id, review_id, review_score, review_creation_date, review_answer_ts,
       review_comment_title, review_comment_message, n_reviews_raw
FROM (
    SELECT order_id, review_id, CAST(review_score AS INTEGER) AS review_score,
           date(review_creation_date) AS review_creation_date,
           datetime(review_answer_timestamp) AS review_answer_ts,
           review_comment_title, review_comment_message,
           COUNT(*) OVER (PARTITION BY order_id) AS n_reviews_raw,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY review_answer_timestamp DESC, review_creation_date DESC, review_id) AS rn
    FROM raw_order_reviews)
WHERE rn = 1;

DROP TABLE IF EXISTS stg_products;
CREATE TABLE stg_products AS
SELECT p.product_id,
       COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       CAST(p.product_name_lenght AS INTEGER)        AS name_length,
       CAST(p.product_description_lenght AS INTEGER) AS description_length,
       CAST(p.product_photos_qty AS INTEGER)         AS photos_qty,
       CAST(p.product_weight_g AS REAL)              AS weight_g,
       CAST(p.product_length_cm AS REAL) * CAST(p.product_height_cm AS REAL) * CAST(p.product_width_cm AS REAL) AS volume_cm3
FROM raw_products p
LEFT JOIN raw_category_translation t USING (product_category_name);

DROP TABLE IF EXISTS stg_customers;
CREATE TABLE stg_customers AS
SELECT customer_id, customer_unique_id, CAST(customer_zip_code_prefix AS INTEGER) AS zip_prefix,
       customer_city AS city, customer_state AS state
FROM raw_customers;

DROP TABLE IF EXISTS stg_sellers;
CREATE TABLE stg_sellers AS
SELECT seller_id, CAST(seller_zip_code_prefix AS INTEGER) AS zip_prefix, seller_city AS city, seller_state AS state
FROM raw_sellers;
