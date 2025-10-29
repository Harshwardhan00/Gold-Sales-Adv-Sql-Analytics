use [first project ]
Select Year(order_date) as order_year,
month(order_date) as order_month,
sum(sales_amount) as total_sales,
Count(Distinct customer_key) as total_customers,
sum(quantity) as total_quantity
From dbo.[gold.fact_sales]
Where order_date is not null
Group by Year(order_date),month(order_date) 
order by Year(order_date),month(order_date) 





Select
Datetrunc(month,order_date) as order_date,
sum(sales_amount) as total_sales,
Count(Distinct customer_key) as total_customers,
sum(quantity) as total_quantity
From dbo.[gold.fact_sales]
Where order_date is not null
Group by Datetrunc(month,order_date) 
order by Datetrunc(month,order_date)


--Calculate the Total sales per month
-- and the running total of sales over time 

select 
order_date,
total_sales,
sum(total_sales) over( order by order_date) as running_total_sales,
Avg(average_price) over( order by order_date) as moving_average_sales
from
(select datetrunc(year, order_date) as order_date,
Sum(sales_amount) as total_sales,
avg(price) as average_price
From dbo.[gold.fact_sales]
where order_date is not null 
Group by datetrunc(year, order_date)) as t


-- Analyze the yearly performance of products by comparing their sales
-- to both the average sales performance of the product and the previous year's sales
with yearly_product_sales as (
select 
year(f.order_date) as order_year,
p.product_name,
sum(f.sales_amount) as current_sales
from dbo.[gold.fact_sales] as f 
left join dbo.[gold.dim_products] as p 
on f.product_key = p.product_key
where f.order_date is not null 
group by year(f.order_date) , 
p.product_name )


select 
order_year,
product_name,
current_sales,
avg(current_sales) over(partition by product_name) as avg_sales,
current_sales -avg(current_sales) over(partition by product_name) as diff_avg,
case when current_sales -avg(current_sales) over(partition by product_name)> 0 then 'above avg'
     when current_sales -avg(current_sales) over(partition by product_name)<0 then 'Below avg'
	 else 'avg'
end avg_change,
lag(current_sales) over(partition by product_name order by order_year) as py_sales,
current_sales - lag(current_sales) over(partition by product_name order by order_year) as diff_py,
case when current_sales -lag(current_sales) over(partition by product_name order by order_year)> 0 then 'Increase'
     when current_sales -lag(current_sales) over(partition by product_name order by order_year)<0 then 'Decrease'
else 'no change' end py_change
from yearly_product_sales
order by product_name, order_year


 -- which categories contribute the most to overall sales
 with category_sales as(select 
 category,
 sum(sales_amount) as total_sales
 from dbo.[gold.fact_sales] as f 
 left join dbo.[gold.dim_products] as  p 
 on p.product_key = f.product_key
 group by category)

 select 
 category,
 total_sales,
 sum(total_sales) over() overall_sales,
concat(round((cast (total_sales as float)/ sum(total_sales) over())*100,2),'%') as percentage_of_total_sales
from category_sales
order by total_sales desc


 -- segment products into cost ranges and count 
 --how many products fall into each segment

 with product_segments as(select 
 product_key,
 product_name,
 cost,
 case when cost<100 then 'below 100'
      when cost between 100 and 500 then '100-500'
	  when cost between 500 and 1000 then '500-1000'
	  else 'above 1000' end cost_range
 from dbo.[gold.dim_products] )
 select cost_range,
 count(product_key) as total_products
 from product_segments
 group by cost_range
 order by total_products desc


 /* group customers into three segments based on their spending behavior:
     - vip: customer with at least 12 months of history and spending more than 5000.
	 - regular: customers with at least 12 month of hiistory but spending 5000 or less
	 - new: customers with a lifespan less than 12 months.
and find the total number of customers by each group */
 
	with  customer_spending as  (select 
	c.customer_key,
	sum(f.sales_amount) as total_spending,
	min(order_date) as first_order ,
	max(order_date) as last_order,
	datediff(month,min(order_date),max(order_date)) as lifespan
	from dbo.[gold.fact_sales] as f
	left join dbo.[gold.dim_customers] as c
	on f.customer_key = c.customer_key
	group by c.customer_key)
 

	select
	customer_segment,
	count(customer_key) as total_customer
	from(
		select 
		customer_key,
		case when lifespan>=12 and total_spending>5000 then'VIP'
			 when lifespan>=12 and total_spending<=5000 then'Regular'
			 else 'new'
			 end customer_segment
		from customer_spending) as t 
	group by customer_segment
	order by total_customer




create view dbo.[gold.reports_customers] as
	-- customer reports
 with base_query as (select 
 f.order_number,
 f.product_key,
 f.order_date,
 f.sales_amount,
 f.quantity,
 c.customer_key,
 c.customer_number,
 concat(c.first_name, '' ,c.last_name) as customer_name,
 datediff(year,c.birthdate , Getdate()) as age
 from dbo.[gold.fact_sales] as f 
 left join dbo.[gold.dim_customers] as  c  
 on c.customer_key = f.customer_key
 where order_date is not null)
 
, customer_aggregation as (
 select 
 customer_key,
 customer_number,
 customer_name,
 age,
 count(distinct order_number) as total_orders,
 sum(sales_amount) as total_sales,
 sum(quantity) as total_quantity,
 count(distinct product_key) as total_products ,
 max(order_date) as last_order_date,
 datediff(month, min(order_date),max(order_date)) as lifespan
 from base_query
 group by 
 customer_key,
 customer_number,
 customer_name,
 age)

 select 
customer_key,
customer_number,
customer_name,
age,
case when age<20 then 'under 20'
when age between 20 and 29 then '20-29'
when age between 30 and 30 then '30-39'
when age between 40 and 49 then '40-49'
else '50 and above'
end as age_group,
case 
when lifespan>= 12 and total_sales>5000 then 'vip'
when lifespan>=12 and total_sales<=5000 then'regular'
else 'new' 
end as customer_segments,
total_orders,
total_sales,
total_quantity,
total_products,
last_order_date,
datediff(month,last_order_date,getdate())as recency,
lifespan,
--aov
case when total_sales=0 then 0
else
total_sales/total_orders 
end as 
   avg_order_value
   ,
--ams
case when lifespan=0 then total_sales
else total_sales/lifespan
end as avg_monthly_spend 
from customer_aggregation





create view dbo.[gold.reports_products] as
-- Product reports
 with base_query as (
 select 
 f.order_number,
 f.customer_key,
 f.order_date,
 f.sales_amount,
 f.quantity,
 p.product_key,
 p.product_name,
 p.category,
 p.subcategory,
 p.cost
 from dbo.[gold.fact_sales] as f 
 left join dbo.[gold.dim_products] as p
 on f.product_key=p.product_key
 where order_date is not null)
 
, product_aggregation as (
 select 
 product_key,
 category,
 subcategory,
 product_name,
 cost,
 count(distinct order_number) as total_orders,
 count(distinct customer_key) as total_customers,
 sum(sales_amount) as total_sales,
 sum(quantity) as total_quantity,
 max(order_date) as last_sale_date,
 datediff(month, min(order_date),max(order_date)) as lifespan,
 round(avg(cast(sales_amount as float)/nullif(quantity,0)),1) as avg_selling_price
 from base_query
 group by 
 product_key,
 product_name,
 category,
 subcategory,
 cost
 )

select 
product_key,
product_name,
category,
subcategory,
cost,
last_sale_date,
datediff(month,last_sale_date,getdate()) as recency_in_month,
case when total_sales>50000 then 'high-performer'
when total_sales >= 10000 then 'mid-range'
else 'low-performer'
end as product_segments,
total_orders,
total_sales,
total_quantity,
total_customers,
lifespan,
avg_selling_price,
--aor
case when total_orders=0 then 0
else
total_sales/total_orders 
end as 
   avg_order_value
   ,
--ams
case when lifespan=0 then total_sales
else total_sales/lifespan
end as avg_monthly_revenue 
from product_aggregation ;