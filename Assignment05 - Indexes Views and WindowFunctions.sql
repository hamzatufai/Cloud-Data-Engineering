-- ============================================================
--   ASSIGNMENT 05 — INDEXES, VIEWS & WINDOW FUNCTIONS
--   Database  : BikeStores
--   Topics    : Indexes (Clustered & Non-Clustered)
--               Views
--               ROW_NUMBER / RANK / DENSE_RANK
--               LAG / LEAD
--               COALESCE
-- ============================================================
SET STATISTICS TIME ON;
SET STATISTICS IO ON;

EXEC sp_helpindex 'production.products';
-- ============================================================
--  SECTION A — INDEXES
-- ============================================================

-- Q1.
-- The marketing team frequently runs campaigns filtered by brand.
-- They search products like this:
--
  DBCC DROPCLEANBUFFERS;

   SELECT product_id, product_name, list_price    -- 4ms after indexing 0ms
   FROM production.products
   WHERE brand_id = 3;
--
-- This query is slow. Create an appropriate index to fix it.
-- Then run the query to confirm it returns results correctly.



DROP INDEX ix_brand_id
ON production.products;

CREATE NONCLUSTERED INDEX ix_brand_id
ON production.products (brand_id)
INCLUDE(product_name, list_price);



-- Q2.
-- The finance team runs a monthly report that filters orders
-- by a date range, for example:
--
EXEC sp_helpindex 'sales.orders';

DBCC DROPCLEANBUFFERS;

   SELECT order_id, customer_id, order_date
   FROM sales.orders
   WHERE order_date BETWEEN '2018-01-01' AND '2018-06-30';  -- 5ms AFTER INDEXING 1ms
--
-- Create an index to make this query more efficient.

CREATE NONCLUSTERED INDEX ix_order_date
ON sales.orders (order_date);

DROP INDEX ix_order_date
ON sales.orders;

-- ============================================================
--  SECTION B — VIEWS
-- ============================================================

-- Q3.
-- The customer support team needs a daily list of all
-- pending and processing orders so they can follow up.
-- Create a view that shows:
--   order_id, customer full name, phone, email,
--   order_date, and order status as a readable label
--   (not a number — use 1=Pending, 2=Processing).
-- After creating it, query the view to see today's workload.

CREATE VIEW sales.vw_daily_list
AS
SELECT 
    o.order_id,
    c.first_name + ' ' + c.last_name AS fullname,
    c.phone,
    c.email,
    o.order_date,
    CASE
        WHEN o.order_status = 1 THEN 'Pending'
        WHEN o.order_status = 2 THEN 'Processing'
        ELSE 'Unknown'
    END AS order_status_label
FROM sales.customers c
JOIN sales.orders o
    ON c.customer_id = o.customer_id;


SELECT *
FROM sales.vw_daily_list;

-- Q4.
-- The inventory manager wants a single view to monitor stock
-- across all stores without writing complex joins every time.
-- Create a view that shows:
--   store_name, product_name, brand_name, category_name, quantity
-- After creating it, query the view to find all products
-- that have fewer than 3 units remaining in any store.

CREATE VIEW sales.vw_monitor_stock
AS
SELECT 
        ss.store_name,
        pp.product_name,
        pb.brand_name,
        pc.category_name,
        ps.quantity

FROM sales.stores AS ss
JOIN production.stocks AS ps
    ON ss.store_id = ps.store_id
JOIN production.products AS pp
    ON pp.product_id = ps.product_id
JOIN production.categories AS pc
    ON pp.category_id = pc.category_id
JOIN production.brands AS pb 
    ON pp.brand_id = pb.brand_id;

SELECT *
FROM sales.vw_monitor_stock
WHERE quantity > 3
ORDER BY quantity;
-- ============================================================
--  SECTION C — ROW_NUMBER, RANK & DENSE_RANK
-- ============================================================

-- Q5.
-- The sales director wants to see the top 2 best-selling products
-- per store based on total quantity sold.
-- Show store_id, product_id, total_quantity, and their rank within the store.
-- Return only rank 1 and rank 2 for each store.
WITH rank_product AS
(
        SELECT 
                ss.store_id,
                pp.product_id,
                SUM(ps.quantity) AS total_quantity,
                RANK() OVER(PARTITION BY ss.store_id ORDER BY SUM(ps.quantity) DESC) AS store_rank

        FROM sales.stores AS ss
        JOIN production.stocks AS ps
            ON ss.store_id = ps.store_id
        JOIN production.products AS pp
            ON ps.product_id = pp.product_id
        GROUP BY ss.store_id,
                pp.product_id

)
SELECT *
FROM rank_product
WHERE total_quantity <= 2;


-- Q6.
-- The pricing team wants to find the 2nd most expensive product
-- in each category.
-- Show category_id, product_name, list_price, and their price rank
-- within the category.
-- Return only the products ranked 2nd in their category.
WITH rank_product AS
(
        SELECT 
                pc.category_id,
                product_name,
                list_price,
                RANK() OVER(PARTITION BY pc.category_id ORDER BY list_price DESC) AS price_rank
        FROM production.products AS pp
        JOIN production.categories AS pc
            ON pp.category_id = pc.category_id
)
SELECT *
FROM rank_product
WHERE price_rank <= 2
ORDER BY price_rank;

-- Q7.
-- The data team suspects there are duplicate customer records.
-- Use the test table below (already has duplicates built in).
-- Write a query to identify the duplicate rows
-- (same first_name, last_name, and phone).
-- Return only the duplicates — not the original/first occurrence.
--
-- Run this setup first:
--
 --CREATE TABLE test_customers (
 --    customer_id  INT,
 --    first_name   VARCHAR(50),
 --    last_name    VARCHAR(50),
 --    phone        VARCHAR(20),
 --    city         VARCHAR(50)
 --);

 --INSERT INTO test_customers VALUES
 --    (1,  'Ali',    'Khan',    '0300-1111111', 'Karachi'),
 --    (2,  'Sara',   'Ahmed',   '0321-2222222', 'Lahore'),
 --    (3,  'Ali',    'Khan',    '0300-1111111', 'Karachi'),   -- duplicate of 1
 --    (4,  'Usman',  'Malik',   '0333-3333333', 'Islamabad'),
 --    (5,  'Sara',   'Ahmed',   '0321-2222222', 'Lahore'),   -- duplicate of 2
 --    (6,  'Sara',   'Ahmed',   '0321-2222222', 'Lahore'),   -- 3rd copy of 2
 --    (7,  'Hina',   'Raza',    '0312-4444444', 'Peshawar');
--
-- Now write your query to find the duplicate rows.
WITH check_duplicate AS
(
    SELECT 
            ROW_NUMBER() OVER(PARTITION BY first_name, last_name, phone ORDER BY customer_id) AS rn
    FROM dbo.test_customers
)
SELECT *
FROM check_duplicate 
WHERE rn > 1
-- ============================================================
--  SECTION D — LAG, LEAD & COALESCE
-- ============================================================

-- Q8.
-- The finance team wants a month-by-month revenue report for 2017.
-- For each month, show total net sales and how much it grew or
-- dropped compared to the previous month.
-- Show month, net_sales, previous_month_sales, and the difference.
-- Net sales = SUM( quantity * list_price * (1 - discount) )
WITH vw_report
AS
(
        SELECT 
                MONTH(o.order_date) AS order_month,
                SUM( quantity * list_price * (1 - discount) ) AS net_sales
        FROM sales.order_items AS oi
        JOIN sales.orders AS o
            ON oi.order_id = o.order_id
        WHERE YEAR(o.order_date) = 2017
        GROUP BY MONTH(o.order_date)
)
SELECT 
        order_month,
        net_sales,
        LAG(net_sales) OVER(ORDER BY order_month) AS previous_month_sales,
        net_sales - LAG(net_sales) OVER(ORDER BY order_month) AS differ

FROM vw_report




-- Q9.
-- The product team wants to see each product's price compared to
-- the next cheaper product in the same category.
-- Show product_name, list_price, and the next lower price
-- in the same category.
-- Sort by category_id and list_price descending.

SELECT 
    pp.product_name,
    pp.list_price,

    LEAD(pp.list_price) OVER(PARTITION BY pp.category_id ORDER BY pp.list_price DESC) AS next_lower_price

FROM production.products pp;

-- Q10.
-- The CRM team is cleaning up customer records.
-- Some customers have no phone number on file.
-- Show each customer's full name, phone, and email.
-- Replace any missing phone with their email address instead.
-- If both are missing, show 'No Contact Info'.
-- Sort by last_name, first_name.

SELECT 
           first_name + ' ' + last_name AS fullname,
           COALESCE(phone, email, 'No Contact Info') AS contacT_info,
           email
FROM sales.customers

-- ============================================================
--  END OF ASSIGNMENT 05
-- ============================================================