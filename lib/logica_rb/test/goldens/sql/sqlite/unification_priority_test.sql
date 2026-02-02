SELECT
  x_6.value AS col0,
  x_7.value AS col1
FROM
  JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 3) select n from t) where n < 3)) as x_6, JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 3) select n from t) where n < 3)) as x_7
WHERE
  ((x_6.value = 1) OR (x_7.value != 2));
