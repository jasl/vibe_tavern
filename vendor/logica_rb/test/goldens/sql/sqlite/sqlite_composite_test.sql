SELECT
  (select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 5) select n from t) where n < 5) AS r,
  (SELECT
  JSON_GROUP_ARRAY(MagicalEntangle(((x_7.value) * (x_7.value)), x_8.value)) AS logica_value
FROM
  JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 5) select n from t) where n < 5)) as x_7, JSON_EACH(JSON_ARRAY(0)) as x_8) AS r_sq,
  (SELECT
  JSON_GROUP_ARRAY(MagicalEntangle(x_10.value, x_11.value)) AS logica_value
FROM
  JSON_EACH((SELECT
    JSON_GROUP_ARRAY(MagicalEntangle(((x_13.value) * (x_13.value)), x_14.value)) AS logica_value
  FROM
    JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 5) select n from t) where n < 5)) as x_13, JSON_EACH(JSON_ARRAY(0)) as x_14)) as x_10, JSON_EACH(JSON_ARRAY(0)) as x_11
WHERE
  (x_10.value > 5)) AS r_sq_l,
  JSON_ARRAY(JSON_OBJECT('a', 1, 'b', 'one'), JSON_OBJECT('a', 2, 'b', 'two')) AS records;
