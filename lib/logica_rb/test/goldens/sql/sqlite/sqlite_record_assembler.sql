SELECT * FROM (
  
    SELECT
      1 AS col0,
      AssembleRecord(JSON_ARRAY(JSON_OBJECT('arg', 'planet', 'value', 'Earth'), JSON_OBJECT('arg', 'species', 'value', 'Humans'))) AS col1 UNION ALL
  
    SELECT
      2 AS col0,
      DisassembleRecord(JSON_OBJECT('planet', 'Mars', 'species', 'Apes')) AS col1 UNION ALL
  
    SELECT
      3 AS col0,
      AssembleRecord(JSON_ARRAY(JSON_OBJECT('arg', JOIN_STRINGS((SELECT
      JSON_GROUP_ARRAY(MagicalEntangle(JSON_EXTRACT(x_81.value, "$.arg"), x_82.value)) AS logica_value
    FROM
      JSON_EACH(DisassembleRecord(JSON_OBJECT('fire', 1, 'water', 2, 'air', 3))) as x_81, JSON_EACH(JSON_ARRAY(0)) as x_82
    WHERE
      (x_81.value = JSON_OBJECT('arg', JSON_EXTRACT(x_81.value, "$.arg"), 'value', JSON_EXTRACT(x_81.value, "$.value")))), '_'), 'value', (SELECT
      SUM(MagicalEntangle(JSON_EXTRACT(x_90.value, "$.value"), x_91.value)) AS logica_value
    FROM
      JSON_EACH(DisassembleRecord(JSON_OBJECT('fire', 1, 'water', 2, 'air', 3))) as x_90, JSON_EACH(JSON_ARRAY(0)) as x_91
    WHERE
      (x_90.value = JSON_OBJECT('arg', JSON_EXTRACT(x_90.value, "$.arg"), 'value', JSON_EXTRACT(x_90.value, "$.value"))))))) AS col1
) AS UNUSED_TABLE_NAME  ;
