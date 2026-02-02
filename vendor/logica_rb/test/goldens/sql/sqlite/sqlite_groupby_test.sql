WITH t_0_T AS (SELECT
  x_2.value AS col0
FROM
  JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 10) select n from t) where n < 10)) as x_2)
SELECT
  ((T.col0) / (2)) AS col0,
  SUM(T.col0) AS logica_value
FROM
  t_0_T AS T
GROUP BY ((T.col0) / (2));
