# Q1
/*Compare total orders across pre-crisis (Jan–May 2025) vs crisis (Jun–Sep 2025). How severe is the decline?*/

WITH monthly_orders AS (
    SELECT 
        month_start,
        COUNT(*) AS total_orders
    FROM (
        SELECT 
            DATE_FORMAT(order_timestamp, '%Y-%m-01') AS month_start
        FROM fact_order
        WHERE order_timestamp BETWEEN '2025-01-01' AND '2025-09-30'
    ) AS t
    GROUP BY month_start
),
period_summary AS (
    SELECT
        SUM(CASE WHEN month_start BETWEEN '2025-01-01' AND '2025-05-01'
                 THEN total_orders END) AS pre_crisis_orders,
        SUM(CASE WHEN month_start BETWEEN '2025-06-01' AND '2025-09-01'
                 THEN total_orders END) AS crisis_orders
    FROM monthly_orders
)
SELECT 
    pre_crisis_orders,
    crisis_orders,
    ROUND(
        ((pre_crisis_orders - crisis_orders) * 100.0) / pre_crisis_orders,
        2
    ) AS percentage_decline
FROM period_summary;


#Q2
/*Which top 5 city groups experienced the highest percentage decline in orders during the crisis period compared to the pre-crisis period?*/

WITH city_monthly AS (
    SELECT 
        dc.city,
        DATE_FORMAT(fo.order_timestamp, '%Y-%m-01') AS month_start,
        COUNT(*) AS total_orders
    FROM fact_order fo
    JOIN dim_customer dc 
        ON fo.customer_id = dc.customer_id
    WHERE fo.order_timestamp BETWEEN '2025-01-01' AND '2025-09-30'
    GROUP BY 
        dc.city,
        DATE_FORMAT(fo.order_timestamp, '%Y-%m-01')
),

city_period AS (
    SELECT
        city,
        SUM(CASE WHEN month_start BETWEEN '2025-01-01' AND '2025-05-01'
                 THEN total_orders END) AS pre_crisis_orders,
        SUM(CASE WHEN month_start BETWEEN '2025-06-01' AND '2025-09-01'
                 THEN total_orders END) AS crisis_orders
    FROM city_monthly
    GROUP BY city
),

city_decline AS (
    SELECT
        city,
        pre_crisis_orders,
        crisis_orders,
        ROUND(
            ((pre_crisis_orders - crisis_orders) * 100.0) / pre_crisis_orders,
            2
        ) AS percentage_decline
    FROM city_period
    WHERE pre_crisis_orders > 0
)
SELECT *
FROM city_decline
ORDER BY percentage_decline DESC
LIMIT 5;


#Q3
/*Among restaurants with at least 50 pre-crisis orders, which top 10 
high-volume restaurants experienced the largest percentage decline in order counts during the crisis period?*/

WITH restaurant_orders AS (
    SELECT
        restaurant_id,
        SUM(CASE 
                WHEN order_timestamp BETWEEN '2025-01-01' AND '2025-05-31'
                THEN 1 ELSE 0 
            END) AS pre_crisis_orders,
        SUM(CASE 
                WHEN order_timestamp BETWEEN '2025-06-01' AND '2025-09-30'
                THEN 1 ELSE 0 
            END) AS crisis_orders
    FROM fact_order
    GROUP BY restaurant_id
),
filtered AS (
    SELECT
        restaurant_id,
        pre_crisis_orders,
        crisis_orders,
        ROUND(
            ((pre_crisis_orders - crisis_orders) * 100.0) / pre_crisis_orders,
            2
        ) AS percent_decline
    FROM restaurant_orders
    WHERE pre_crisis_orders >= 10      
)
SELECT *
FROM filtered
ORDER BY percent_decline DESC
LIMIT 10;


#Q4
/*What is the cancellation rate trend pre-crisis vs crisis, and which cities are most affected?*/

WITH delivery_calc AS (
    SELECT 
        order_id,
        TIMESTAMPDIFF(MINUTE, order_timestamp, delivered_timestamp) AS delivery_time_mins,
        CASE
            WHEN order_timestamp BETWEEN '2025-01-01' AND '2025-05-31' THEN 'Pre-Crisis'
            WHEN order_timestamp BETWEEN '2025-06-01' AND '2025-09-30' THEN 'Crisis'
        END AS period
    FROM fact_order
    WHERE delivered_timestamp IS NOT NULL
)
SELECT
    period,
    ROUND(AVG(delivery_time_mins), 2) AS avg_delivery_time_mins
FROM delivery_calc
GROUP BY period;

SELECT
    period,
    total_orders,
    cancelled_orders,
    ROUND((cancelled_orders * 100.0) / total_orders, 2) AS cancellation_rate
FROM (
    SELECT 
        CASE
            WHEN order_timestamp BETWEEN '2025-01-01' AND '2025-05-31' THEN 'Pre-Crisis'
            WHEN order_timestamp BETWEEN '2025-06-01' AND '2025-09-30' THEN 'Crisis'
        END AS period,
        COUNT(*) AS total_orders,
        SUM(CASE WHEN is_cancelled = 'Y' THEN 1 ELSE 0 END) AS cancelled_orders
    FROM fact_order
    WHERE order_timestamp BETWEEN '2025-01-01' AND '2025-09-30'
    GROUP BY period
) AS t;


#Q5
/*Measure average delivery time across phases. Did SLA compliance worsen significantly in the crisis period?*/

WITH delivery_period AS (
    SELECT 
        fdp.order_id,
        fdp.actual_delivery_time_mins,
        CASE
            WHEN fo.order_timestamp BETWEEN '2025-01-01' AND '2025-05-31' THEN 'Pre-Crisis'
            WHEN fo.order_timestamp BETWEEN '2025-06-01' AND '2025-09-30' THEN 'Crisis'
        END AS period
    FROM fact_delivery_performance fdp
    JOIN fact_order fo 
        ON fdp.order_id = fo.order_id
    WHERE fo.order_timestamp BETWEEN '2025-01-01' AND '2025-09-30'
)
SELECT
    period,
    ROUND(AVG(actual_delivery_time_mins), 2) AS avg_delivery_time_mins
FROM delivery_period
GROUP BY period;


#Q6
/*Did SLA compliance worsen significantly in the crisis period?*/

WITH delivery_data AS (
    SELECT 
        fdp.order_id,
        fdp.actual_delivery_time_mins,
        fdp.expected_delivery_time_mins,
        
        CASE 
            WHEN fo.order_timestamp BETWEEN '2025-01-01' AND '2025-05-31' 
                THEN 'Pre-Crisis'
            WHEN fo.order_timestamp BETWEEN '2025-06-01' AND '2025-09-30' 
                THEN 'Crisis'
        END AS period,

        CASE 
            WHEN fdp.actual_delivery_time_mins <= fdp.expected_delivery_time_mins 
                THEN 1 
            ELSE 0 
        END AS sla_met
    FROM fact_delivery_performance fdp
    JOIN fact_order fo 
        ON fdp.order_id = fo.order_id
    WHERE fo.order_timestamp BETWEEN '2025-01-01' AND '2025-09-30'
)

SELECT 
    period,
    COUNT(*) AS total_deliveries,
    SUM(sla_met) AS sla_met_count,
    ROUND((SUM(sla_met) * 100.0 / COUNT(*)), 2) AS sla_compliance_pct
FROM delivery_data
GROUP BY period;


#Q7
/*Track average customer rating month-by-month. Which months saw the sharpest drop?*/

WITH ratings_with_month AS (
    SELECT 
        fr.rating,
        DATE_FORMAT(fo.order_timestamp, '%Y-%m') AS month_year
    FROM fact_ratings fr
    JOIN fact_order fo 
        ON fr.order_id = fo.order_id
    WHERE fo.order_timestamp BETWEEN '2025-01-01' AND '2025-12-31'
),
monthly_avg AS (
    SELECT
        month_year,
        ROUND(AVG(rating), 2) AS avg_rating
    FROM ratings_with_month
    GROUP BY month_year
)
SELECT
    month_year,
    avg_rating,
    LAG(avg_rating) OVER (ORDER BY month_year) AS prev_month_rating,
    ROUND(avg_rating - LAG(avg_rating) OVER (ORDER BY month_year), 2) AS change_from_prev
FROM monthly_avg
ORDER BY month_year;


#Q8
/*Estimate revenue loss from pre-crisis vs crisis (based on subtotal, discount, and delivery fee).*/

WITH revenue_calc AS (
    SELECT
        CASE
            WHEN order_timestamp BETWEEN '2025-01-01' AND '2025-05-31'
                THEN 'Pre-Crisis'
            WHEN order_timestamp BETWEEN '2025-06-01' AND '2025-09-30'
                THEN 'Crisis'
        END AS period,
        (subtotal_amount - discount_amount + delivery_fee) AS revenue
    FROM fact_order
    WHERE order_timestamp BETWEEN '2025-01-01' AND '2025-09-30'
      AND is_cancelled = 0   -- exclude cancelled orders
)
SELECT
    period,
    ROUND(SUM(revenue), 2) AS total_revenue
FROM revenue_calc
GROUP BY period;


#Q9
/*Among customers who placed five or more orders before the crisis, determine how many stopped ordering during the crisis, 
and out of those, how many had an average rating above 4.5?*/

WITH pre_crisis_orders AS (
    SELECT 
        customer_id,
        COUNT(*) AS pre_order_count
    FROM fact_order
    WHERE order_timestamp BETWEEN '2025-01-01' AND '2025-05-31'
    GROUP BY customer_id
    HAVING COUNT(*) >= 5
),

crisis_orders AS (
    SELECT 
        customer_id,
        COUNT(*) AS crisis_order_count
    FROM fact_order
    WHERE order_timestamp BETWEEN '2025-06-01' AND '2025-09-30'
    GROUP BY customer_id
),


stopped_customers AS (
    SELECT 
        p.customer_id
    FROM pre_crisis_orders p
    LEFT JOIN crisis_orders c 
        ON p.customer_id = c.customer_id
    WHERE COALESCE(c.crisis_order_count, 0) = 0
),

ratings_summary AS (
    SELECT 
        customer_id,
        AVG(rating) AS avg_rating
    FROM fact_ratings
    GROUP BY customer_id
)

SELECT 
    (SELECT COUNT(*) FROM stopped_customers) AS customers_stopped,
    (SELECT COUNT(*)
     FROM stopped_customers s
     JOIN ratings_summary r ON s.customer_id = r.customer_id
     WHERE r.avg_rating > 4.5
    ) AS high_rating_customers_stopped;









