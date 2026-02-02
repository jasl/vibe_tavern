SELECT * FROM (
  
    SELECT
      'simple_assignment' AS col0,
      JSON_OBJECT('a', 'va', 'b', 'vb') AS col1
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (JSON_OBJECT('a', 'va', 'b', 'vb') = JSON_OBJECT('a', 'va', 'b', 'vb')) UNION ALL
  
    SELECT
      'arrow_assignment' AS col0,
      JSON_OBJECT('a', 'va', 'b', 'vb') AS col1
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (JSON_OBJECT('arg', 'va', 'value', 'vb') = JSON_OBJECT('arg', 'va', 'value', 'vb')) UNION ALL
  
    SELECT
      'assignment_from_list' AS col0,
      JSON_OBJECT('a', JSON_EXTRACT(x_12.value, "$.a"), 'b', JSON_EXTRACT(x_12.value, "$.b")) AS col1
    FROM
      JSON_EACH(JSON_ARRAY(JSON_OBJECT('a', 'va1', 'b', 'vb1'), JSON_OBJECT('a', 'va2', 'b', 'vb2'))) as x_12
    WHERE
      (JSON_OBJECT('a', JSON_EXTRACT(x_12.value, "$.a"), 'b', JSON_EXTRACT(x_12.value, "$.b")) = x_12.value) UNION ALL
  
    SELECT
      'assignment_from_list_with_arrow' AS col0,
      JSON_OBJECT('a', JSON_EXTRACT(x_16.value, "$.arg"), 'b', JSON_EXTRACT(x_16.value, "$.value")) AS col1
    FROM
      JSON_EACH(JSON_ARRAY(JSON_OBJECT('arg', 'va1', 'value', 'vb1'), JSON_OBJECT('arg', 'va2', 'value', 'vb2'))) as x_16
    WHERE
      (x_16.value = JSON_OBJECT('arg', JSON_EXTRACT(x_16.value, "$.arg"), 'value', JSON_EXTRACT(x_16.value, "$.value"))) UNION ALL
  
    SELECT
      'value_lookup' AS col0,
      JSON_EXTRACT(x_38.value, "$.value") AS col1
    FROM
      JSON_EACH(JSON_ARRAY(JSON_OBJECT('arg', 0, 'value', 'a'), JSON_OBJECT('arg', 1, 'value', 'b'), JSON_OBJECT('arg', 2, 'value', 'c'), JSON_OBJECT('arg', 3, 'value', 'd'))) as x_38
    WHERE
      (x_38.value = JSON_OBJECT('arg', 2, 'value', JSON_EXTRACT(x_38.value, "$.value"))) UNION ALL
  
    SELECT
      'assignment_to_one_of' AS col0,
      'vb' AS col1
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (JSON_OBJECT('a', 1, 'b', 'vb') = JSON_OBJECT('a', 1, 'b', 'vb')) UNION ALL
  
    SELECT
      'assignment_aggr_lookup' AS col0,
      JSON_OBJECT('a', x_68.value, 'b', (SELECT
      MAX(MagicalEntangle(JSON_EXTRACT(x_81.value, "$.value"), x_82.value)) AS logica_value
    FROM
      JSON_EACH(JSON_ARRAY(JSON_OBJECT('arg', 1, 'value', 'a'), JSON_OBJECT('arg', 2, 'value', 'b'))) as x_81, JSON_EACH(JSON_ARRAY(0)) as x_82
    WHERE
      (x_81.value = JSON_OBJECT('arg', x_68.value, 'value', JSON_EXTRACT(x_81.value, "$.value"))))) AS col1
    FROM
      JSON_EACH(JSON_ARRAY(0, 1)) as x_68 UNION ALL
  
    SELECT
      'nested_assignment' AS col0,
      JSON_OBJECT('arg', JSON_OBJECT('arg', 'va', 'value', JSON_EXTRACT(JSON_OBJECT('b', 'vb', 'z', JSON_OBJECT('w', 'vc')), "$.b")), 'value', JSON_EXTRACT(JSON_EXTRACT(JSON_OBJECT('b', 'vb', 'z', JSON_OBJECT('w', 'vc')), "$.z"), "$.w")) AS col1
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (JSON_OBJECT('a', 'va', 'x', JSON_OBJECT('b', JSON_EXTRACT(JSON_OBJECT('b', 'vb', 'z', JSON_OBJECT('w', 'vc')), "$.b"), 'z', JSON_OBJECT('w', JSON_EXTRACT(JSON_EXTRACT(JSON_OBJECT('b', 'vb', 'z', JSON_OBJECT('w', 'vc')), "$.z"), "$.w")))) = JSON_OBJECT('a', 'va', 'x', JSON_OBJECT('b', 'vb', 'z', JSON_OBJECT('w', 'vc'))))
) AS UNUSED_TABLE_NAME  ;
