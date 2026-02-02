SELECT
  (SELECT
  GROUP_CONCAT(MagicalEntangle(CAST(x_5.value AS TEXT), x_6.value)) AS logica_value
FROM
  JSON_EACH((SELECT
    ArgMin(JSON_EXTRACT(MagicalEntangle(JSON_OBJECT('arg', x_14.value, 'value', CAST(ROUND((((POW(((1) + ((POW(5, 0.5)))), x_14.value))) / ((((POW(2, x_14.value))) * ((POW(5, 0.5))))))) AS INT64)), x_15.value), "$.value"), JSON_EXTRACT(MagicalEntangle(JSON_OBJECT('arg', x_14.value, 'value', CAST(ROUND((((POW(((1) + ((POW(5, 0.5)))), x_14.value))) / ((((POW(2, x_14.value))) * ((POW(5, 0.5))))))) AS INT64)), x_15.value), "$.arg"), null) AS logica_value
  FROM
    JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 10) select n from t) where n < 10)) as x_14, JSON_EACH(JSON_ARRAY(0)) as x_15)) as x_5, JSON_EACH(JSON_ARRAY(0)) as x_6) AS logica_value;
