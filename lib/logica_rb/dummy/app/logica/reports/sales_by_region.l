@Engine("sqlite");

SalesByRegion(region:, orders_count:, total_cents:) :-
  `((select
      c.region as region,
      count(*) as orders_count,
      sum(o.amount_cents) as total_cents
    from customers c
    join orders o on o.customer_id = c.id
    group by c.region
    order by total_cents desc))`(region:, orders_count:, total_cents:);
