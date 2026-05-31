-- ============================================================
--   ASSIGNMENT 04 — SET OPERATORS, CTEs, CONSTRAINTS & CASES
--   Database  : BikeStores
-- ============================================================


-- ============================================================
--  SECTION A — SET OPERATORS
-- ============================================================

-- Q1.
-- The marketing team wants a single contact list of everyone in the system
-- — both staff members and customers.
-- Build a unified list showing full name and email for all of them.
-- Make sure no one is accidentally listed twice.

SELECT 
    first_name + ' ' + last_name AS fullname,
    email
FROM sales.customers

UNION

SELECT 
    first_name + ' ' + last_name AS fullname,
    email
FROM sales.staffs;



-- Q2.
-- The logistics team wants to know which states have BOTH
-- a store location AND customers living there.
-- Find those states.

SELECT state FROM sales.stores
INTERSECT
SELECT state FROM sales.customers;



-- Q3.
-- Management wants to identify stores that received zero orders
-- in the year 2018.
-- Find the store_ids that appear in sales.stores but did NOT
-- receive any orders in 2018.

SELECT store_id
FROM sales.stores

EXCEPT

SELECT DISTINCT store_id
FROM sales.orders
WHERE YEAR(order_date) = 2018;



-- ============================================================
--  SECTION B — CTEs
-- ============================================================

-- Q4.
-- The pricing team wants to flag overpriced products.
-- For each category, find all products whose list_price is
-- higher than the average list_price of their own category.
-- Show category_id, product_name, list_price, and the category average.

WITH avg_price AS
(
    SELECT 
        category_id,
        AVG(list_price) AS avg_list_price
    FROM production.products
    GROUP BY category_id
)
SELECT 
    p.category_id,
    p.product_name,
    p.list_price,
    a.avg_list_price
FROM production.products p
JOIN avg_price a
    ON p.category_id = a.category_id
WHERE p.list_price > a.avg_list_price;



-- Q5.
-- HR wants to reward the hardest-working staff member.
-- Find all staff members whose order count is higher than
-- the average order count across all staff.
-- Show staff_id and their order_count.

WITH staff_orders AS
(
    SELECT 
        s.staff_id,
        COUNT(o.order_id) AS order_count
    FROM sales.staffs s
    JOIN sales.orders o
        ON s.staff_id = o.staff_id
    GROUP BY s.staff_id
),
avg_staff AS
(
    SELECT AVG(order_count) AS avg_orders
    FROM staff_orders
)
SELECT 
    so.staff_id,
    so.order_count
FROM staff_orders so
CROSS JOIN avg_staff a
WHERE so.order_count > a.avg_orders;



-- Q6.
-- The finance team needs a yearly performance report per store.
-- For each store and each year, calculate total revenue.
-- Then find only the years where a store's revenue
-- exceeded $1,000,000.
-- Show store_id, year, and total_revenue.

WITH yearly_revenue AS
(
    SELECT 
        o.store_id,
        YEAR(o.order_date) AS order_year,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_revenue
    FROM sales.orders o
    JOIN sales.order_items oi
        ON o.order_id = oi.order_id
    GROUP BY o.store_id, YEAR(o.order_date)
)
SELECT 
    store_id,
    order_year,
    total_revenue
FROM yearly_revenue
WHERE total_revenue > 1000000;



-- ============================================================
--  SECTION C — CONSTRAINTS (DDL)
-- ============================================================

-- Q7.
-- The business wants to launch a customer loyalty program.
-- Constraints applied below.

DROP TABLE IF EXISTS sales.loyalty_cards;

CREATE TABLE sales.loyalty_cards (
    card_number INT PRIMARY KEY,
    customer_id INT NOT NULL,

    points INT CHECK (points >= 0),

    tier VARCHAR(10) CHECK (tier IN ('Bronze','Silver','Gold')),

    join_date DATE NOT NULL,

    FOREIGN KEY (customer_id)
        REFERENCES sales.customers(customer_id)
        ON DELETE CASCADE
);



-- Q8.
-- Prevent shipped_date earlier than order_date

ALTER TABLE test_orders
ADD CONSTRAINT chk_ship_date
CHECK (
    shipped_date IS NULL
    OR shipped_date >= order_date
);



-- ============================================================
--  SECTION D — CASE EXPRESSIONS
-- ============================================================

-- Q9.
-- Shipping speed classification

SELECT 
    order_id,
    order_date,
    shipped_date,
    CASE
        WHEN shipped_date IS NULL THEN 'Pending'
        WHEN DATEDIFF(DAY, order_date, shipped_date) <= 2 THEN 'Fast'
        WHEN DATEDIFF(DAY, order_date, shipped_date) BETWEEN 3 AND 5 THEN 'Normal'
        WHEN DATEDIFF(DAY, order_date, shipped_date) > 5 THEN 'Delayed'
    END AS shipping_speed
FROM sales.orders;



-- Q10.
-- Stock level classification

SELECT 
    store_id,
    product_id,
    quantity,
    CASE
        WHEN quantity = 0 THEN 'Out of Stock'
        WHEN quantity BETWEEN 1 AND 10 THEN 'Low Stock'
        WHEN quantity BETWEEN 11 AND 50 THEN 'Sufficient'
        WHEN quantity > 50 THEN 'Well Stocked'
    END AS stock_status
FROM production.stocks
ORDER BY store_id, quantity;