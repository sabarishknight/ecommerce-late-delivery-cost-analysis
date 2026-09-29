DROP TABLE IF EXISTS dim_geo;
CREATE TABLE dim_geo AS
SELECT CAST(geolocation_zip_code_prefix AS INTEGER) AS zip_prefix,
       AVG(CAST(geolocation_lat AS REAL)) AS lat, AVG(CAST(geolocation_lng AS REAL)) AS lng,
       COUNT(*) AS n_points
FROM raw_geolocation
WHERE CAST(geolocation_lat AS REAL) BETWEEN -34.0 AND 5.5
  AND CAST(geolocation_lng AS REAL) BETWEEN -74.5 AND -34.5
GROUP BY 1;

DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer AS
SELECT customer_unique_id, zip_prefix, city, state, first_purchase_ts, n_orders
FROM (
    SELECT c.customer_unique_id, c.zip_prefix, c.city, c.state, o.purchase_ts AS first_purchase_ts,
           COUNT(*)     OVER (PARTITION BY c.customer_unique_id) AS n_orders,
           ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.purchase_ts) AS rn
    FROM stg_customers c JOIN stg_orders o USING (customer_id))
WHERE rn = 1;

DROP TABLE IF EXISTS dim_seller;
CREATE TABLE dim_seller AS
SELECT s.seller_id, s.zip_prefix, s.city, s.state,
       MIN(o.purchase_ts) AS first_sale_ts, COUNT(DISTINCT i.order_id) AS n_orders
FROM stg_sellers s
LEFT JOIN stg_order_items i USING (seller_id)
LEFT JOIN stg_orders o USING (order_id)
GROUP BY 1, 2, 3, 4;

DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product AS SELECT * FROM stg_products;

DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date AS
WITH RECURSIVE d(dt) AS (
    SELECT date(MIN(purchase_ts)) FROM stg_orders
    UNION ALL
    SELECT date(dt, '+1 day') FROM d WHERE dt < (SELECT date(MAX(COALESCE(delivered_ts, purchase_ts))) FROM stg_orders))
SELECT dt AS date, CAST(strftime('%Y', dt) AS INTEGER) AS year, CAST(strftime('%m', dt) AS INTEGER) AS month,
       strftime('%Y-%m', dt) AS year_month, CAST(strftime('%w', dt) AS INTEGER) AS dow,
       CASE WHEN strftime('%w', dt) IN ('0','6') THEN 1 ELSE 0 END AS is_weekend
FROM d;
