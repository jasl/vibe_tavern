@Engine("sqlite");

TopCustomers(customer_name:, orders_count:, total_cents:) :-
  `((select
      c.name as customer_name,
      count(*) as orders_count,
      sum(o.amount_cents) as total_cents
    from customers c
    join orders o on o.customer_id = c.id
    group by c.name
    order by total_cents desc
    limit 20))`(customer_name:, orders_count:, total_cents:);
