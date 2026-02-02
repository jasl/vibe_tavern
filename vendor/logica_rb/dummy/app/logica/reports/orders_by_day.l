@Engine("sqlite");

OrdersByDay(day:, orders_count:, total_cents:) :-
  `((select
      date(ordered_at) as day,
      count(*) as orders_count,
      sum(amount_cents) as total_cents
    from orders
    group by date(ordered_at)
    order by day desc
    limit 30))`(day:, orders_count:, total_cents:);
