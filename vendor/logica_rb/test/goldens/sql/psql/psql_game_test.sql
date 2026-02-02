-- Initializing PostgreSQL environment.
set client_min_messages to warning;
create schema if not exists logica_home;
-- Empty logica type: logicarecord893574736;
DO $$ BEGIN if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord893574736') then create type logicarecord893574736 as (nirvana numeric); end if; END $$;


DO $$
BEGIN
-- Logica type: logicarecord481217614
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord481217614') then create type logicarecord481217614 as (r logicarecord893574736); end if;
-- Logica type: logicarecord86796764
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord86796764') then create type logicarecord86796764 as (s text); end if;
-- Logica type: logicarecord57208616
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord57208616') then create type logicarecord57208616 as (argpod numeric); end if;
-- Logica type: logicarecord884343024
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord884343024') then create type logicarecord884343024 as (arg numeric, value numeric); end if;
-- Logica type: logicarecord889724469
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord889724469') then create type logicarecord889724469 as (arg logicarecord57208616, value numeric); end if;
END $$;
WITH t_2_E AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      2 AS col1 UNION ALL
  
    SELECT
      2 AS col0,
      1 AS col1 UNION ALL
  
    SELECT
      2 AS col0,
      3 AS col1 UNION ALL
  
    SELECT
      3 AS col0,
      4 AS col1 UNION ALL
  
    SELECT
      4 AS col0,
      5 AS col1
) AS UNUSED_TABLE_NAME  ),
t_5_V AS (SELECT
  x_28 AS col0
FROM
  t_2_E AS t_6_E, UNNEST(ARRAY[t_6_E.col0, t_6_E.col1]::numeric[]) as x_28
GROUP BY x_28),
t_166_Advantage_MultBodyAggAux_recursive_head_f1 AS (SELECT * FROM (
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_168_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_168_V
) AS UNUSED_TABLE_NAME  ),
t_165_Advantage_recursive_head_f1 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f1.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f1.logica_value) AS logica_value
FROM
  t_166_Advantage_MultBodyAggAux_recursive_head_f1 AS Advantage_MultBodyAggAux_recursive_head_f1
GROUP BY Advantage_MultBodyAggAux_recursive_head_f1.col0),
t_160_BestMove_r0 AS (SELECT
  t_161_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_161_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f1.logica_value))[1]).argpod AS target,
  MIN(t_164_Advantage_recursive_head_f1.logica_value) AS value
FROM
  t_2_E AS t_161_E, t_165_Advantage_recursive_head_f1 AS Advantage_recursive_head_f1, t_165_Advantage_recursive_head_f1 AS t_164_Advantage_recursive_head_f1
WHERE
  (Advantage_recursive_head_f1.col0 = t_161_E.col1) AND
  (t_164_Advantage_recursive_head_f1.col0 = t_161_E.col1)
GROUP BY t_161_E.col0 ORDER BY col0),
t_158_Advantage_MultBodyAggAux_recursive_head_f2 AS (SELECT * FROM (
  
    SELECT
      t_159_V.col0 AS col0,
      - ((BestMove_r0.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_159_V, t_160_BestMove_r0 AS BestMove_r0
    WHERE
      (BestMove_r0.col0 = t_159_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_177_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_177_V
) AS UNUSED_TABLE_NAME  ),
t_157_Advantage_recursive_head_f2 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f2.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f2.logica_value) AS logica_value
FROM
  t_158_Advantage_MultBodyAggAux_recursive_head_f2 AS Advantage_MultBodyAggAux_recursive_head_f2
GROUP BY Advantage_MultBodyAggAux_recursive_head_f2.col0),
t_152_BestMove_r1 AS (SELECT
  t_153_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_153_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f2.logica_value))[1]).argpod AS target,
  MIN(t_156_Advantage_recursive_head_f2.logica_value) AS value
FROM
  t_2_E AS t_153_E, t_157_Advantage_recursive_head_f2 AS Advantage_recursive_head_f2, t_157_Advantage_recursive_head_f2 AS t_156_Advantage_recursive_head_f2
WHERE
  (Advantage_recursive_head_f2.col0 = t_153_E.col1) AND
  (t_156_Advantage_recursive_head_f2.col0 = t_153_E.col1)
GROUP BY t_153_E.col0 ORDER BY col0),
t_150_Advantage_MultBodyAggAux_recursive_head_f3 AS (SELECT * FROM (
  
    SELECT
      t_151_V.col0 AS col0,
      - ((BestMove_r1.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_151_V, t_152_BestMove_r1 AS BestMove_r1
    WHERE
      (BestMove_r1.col0 = t_151_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_191_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_191_V
) AS UNUSED_TABLE_NAME  ),
t_149_Advantage_recursive_head_f3 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f3.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f3.logica_value) AS logica_value
FROM
  t_150_Advantage_MultBodyAggAux_recursive_head_f3 AS Advantage_MultBodyAggAux_recursive_head_f3
GROUP BY Advantage_MultBodyAggAux_recursive_head_f3.col0),
t_144_BestMove_r2 AS (SELECT
  t_145_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_145_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f3.logica_value))[1]).argpod AS target,
  MIN(t_148_Advantage_recursive_head_f3.logica_value) AS value
FROM
  t_2_E AS t_145_E, t_149_Advantage_recursive_head_f3 AS Advantage_recursive_head_f3, t_149_Advantage_recursive_head_f3 AS t_148_Advantage_recursive_head_f3
WHERE
  (Advantage_recursive_head_f3.col0 = t_145_E.col1) AND
  (t_148_Advantage_recursive_head_f3.col0 = t_145_E.col1)
GROUP BY t_145_E.col0 ORDER BY col0),
t_142_Advantage_MultBodyAggAux_recursive_head_f4 AS (SELECT * FROM (
  
    SELECT
      t_143_V.col0 AS col0,
      - ((BestMove_r2.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_143_V, t_144_BestMove_r2 AS BestMove_r2
    WHERE
      (BestMove_r2.col0 = t_143_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_205_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_205_V
) AS UNUSED_TABLE_NAME  ),
t_141_Advantage_recursive_head_f4 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f4.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f4.logica_value) AS logica_value
FROM
  t_142_Advantage_MultBodyAggAux_recursive_head_f4 AS Advantage_MultBodyAggAux_recursive_head_f4
GROUP BY Advantage_MultBodyAggAux_recursive_head_f4.col0),
t_136_BestMove_r3 AS (SELECT
  t_137_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_137_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f4.logica_value))[1]).argpod AS target,
  MIN(t_140_Advantage_recursive_head_f4.logica_value) AS value
FROM
  t_2_E AS t_137_E, t_141_Advantage_recursive_head_f4 AS Advantage_recursive_head_f4, t_141_Advantage_recursive_head_f4 AS t_140_Advantage_recursive_head_f4
WHERE
  (Advantage_recursive_head_f4.col0 = t_137_E.col1) AND
  (t_140_Advantage_recursive_head_f4.col0 = t_137_E.col1)
GROUP BY t_137_E.col0 ORDER BY col0),
t_134_Advantage_MultBodyAggAux_recursive_head_f5 AS (SELECT * FROM (
  
    SELECT
      t_135_V.col0 AS col0,
      - ((BestMove_r3.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_135_V, t_136_BestMove_r3 AS BestMove_r3
    WHERE
      (BestMove_r3.col0 = t_135_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_219_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_219_V
) AS UNUSED_TABLE_NAME  ),
t_133_Advantage_recursive_head_f5 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f5.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f5.logica_value) AS logica_value
FROM
  t_134_Advantage_MultBodyAggAux_recursive_head_f5 AS Advantage_MultBodyAggAux_recursive_head_f5
GROUP BY Advantage_MultBodyAggAux_recursive_head_f5.col0),
t_128_BestMove_r4 AS (SELECT
  t_129_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_129_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f5.logica_value))[1]).argpod AS target,
  MIN(t_132_Advantage_recursive_head_f5.logica_value) AS value
FROM
  t_2_E AS t_129_E, t_133_Advantage_recursive_head_f5 AS Advantage_recursive_head_f5, t_133_Advantage_recursive_head_f5 AS t_132_Advantage_recursive_head_f5
WHERE
  (Advantage_recursive_head_f5.col0 = t_129_E.col1) AND
  (t_132_Advantage_recursive_head_f5.col0 = t_129_E.col1)
GROUP BY t_129_E.col0 ORDER BY col0),
t_126_Advantage_MultBodyAggAux_recursive_head_f6 AS (SELECT * FROM (
  
    SELECT
      t_127_V.col0 AS col0,
      - ((BestMove_r4.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_127_V, t_128_BestMove_r4 AS BestMove_r4
    WHERE
      (BestMove_r4.col0 = t_127_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_233_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_233_V
) AS UNUSED_TABLE_NAME  ),
t_125_Advantage_recursive_head_f6 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f6.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f6.logica_value) AS logica_value
FROM
  t_126_Advantage_MultBodyAggAux_recursive_head_f6 AS Advantage_MultBodyAggAux_recursive_head_f6
GROUP BY Advantage_MultBodyAggAux_recursive_head_f6.col0),
t_120_BestMove_r5 AS (SELECT
  t_121_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_121_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f6.logica_value))[1]).argpod AS target,
  MIN(t_124_Advantage_recursive_head_f6.logica_value) AS value
FROM
  t_2_E AS t_121_E, t_125_Advantage_recursive_head_f6 AS Advantage_recursive_head_f6, t_125_Advantage_recursive_head_f6 AS t_124_Advantage_recursive_head_f6
WHERE
  (Advantage_recursive_head_f6.col0 = t_121_E.col1) AND
  (t_124_Advantage_recursive_head_f6.col0 = t_121_E.col1)
GROUP BY t_121_E.col0 ORDER BY col0),
t_118_Advantage_MultBodyAggAux_recursive_head_f7 AS (SELECT * FROM (
  
    SELECT
      t_119_V.col0 AS col0,
      - ((BestMove_r5.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_119_V, t_120_BestMove_r5 AS BestMove_r5
    WHERE
      (BestMove_r5.col0 = t_119_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_247_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_247_V
) AS UNUSED_TABLE_NAME  ),
t_117_Advantage_recursive_head_f7 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f7.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f7.logica_value) AS logica_value
FROM
  t_118_Advantage_MultBodyAggAux_recursive_head_f7 AS Advantage_MultBodyAggAux_recursive_head_f7
GROUP BY Advantage_MultBodyAggAux_recursive_head_f7.col0),
t_112_BestMove_r6 AS (SELECT
  t_113_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_113_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f7.logica_value))[1]).argpod AS target,
  MIN(t_116_Advantage_recursive_head_f7.logica_value) AS value
FROM
  t_2_E AS t_113_E, t_117_Advantage_recursive_head_f7 AS Advantage_recursive_head_f7, t_117_Advantage_recursive_head_f7 AS t_116_Advantage_recursive_head_f7
WHERE
  (Advantage_recursive_head_f7.col0 = t_113_E.col1) AND
  (t_116_Advantage_recursive_head_f7.col0 = t_113_E.col1)
GROUP BY t_113_E.col0 ORDER BY col0),
t_110_Advantage_MultBodyAggAux_recursive_head_f8 AS (SELECT * FROM (
  
    SELECT
      t_111_V.col0 AS col0,
      - ((BestMove_r6.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_111_V, t_112_BestMove_r6 AS BestMove_r6
    WHERE
      (BestMove_r6.col0 = t_111_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_261_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_261_V
) AS UNUSED_TABLE_NAME  ),
t_109_Advantage_recursive_head_f8 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f8.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f8.logica_value) AS logica_value
FROM
  t_110_Advantage_MultBodyAggAux_recursive_head_f8 AS Advantage_MultBodyAggAux_recursive_head_f8
GROUP BY Advantage_MultBodyAggAux_recursive_head_f8.col0),
t_104_BestMove_r7 AS (SELECT
  t_105_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_105_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f8.logica_value))[1]).argpod AS target,
  MIN(t_108_Advantage_recursive_head_f8.logica_value) AS value
FROM
  t_2_E AS t_105_E, t_109_Advantage_recursive_head_f8 AS Advantage_recursive_head_f8, t_109_Advantage_recursive_head_f8 AS t_108_Advantage_recursive_head_f8
WHERE
  (Advantage_recursive_head_f8.col0 = t_105_E.col1) AND
  (t_108_Advantage_recursive_head_f8.col0 = t_105_E.col1)
GROUP BY t_105_E.col0 ORDER BY col0),
t_102_Advantage_MultBodyAggAux_recursive_head_f9 AS (SELECT * FROM (
  
    SELECT
      t_103_V.col0 AS col0,
      - ((BestMove_r7.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_103_V, t_104_BestMove_r7 AS BestMove_r7
    WHERE
      (BestMove_r7.col0 = t_103_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_275_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_275_V
) AS UNUSED_TABLE_NAME  ),
t_101_Advantage_recursive_head_f9 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f9.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f9.logica_value) AS logica_value
FROM
  t_102_Advantage_MultBodyAggAux_recursive_head_f9 AS Advantage_MultBodyAggAux_recursive_head_f9
GROUP BY Advantage_MultBodyAggAux_recursive_head_f9.col0),
t_96_BestMove_r8 AS (SELECT
  t_97_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_97_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f9.logica_value))[1]).argpod AS target,
  MIN(t_100_Advantage_recursive_head_f9.logica_value) AS value
FROM
  t_2_E AS t_97_E, t_101_Advantage_recursive_head_f9 AS Advantage_recursive_head_f9, t_101_Advantage_recursive_head_f9 AS t_100_Advantage_recursive_head_f9
WHERE
  (Advantage_recursive_head_f9.col0 = t_97_E.col1) AND
  (t_100_Advantage_recursive_head_f9.col0 = t_97_E.col1)
GROUP BY t_97_E.col0 ORDER BY col0),
t_94_Advantage_MultBodyAggAux_recursive_head_f10 AS (SELECT * FROM (
  
    SELECT
      t_95_V.col0 AS col0,
      - ((BestMove_r8.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_95_V, t_96_BestMove_r8 AS BestMove_r8
    WHERE
      (BestMove_r8.col0 = t_95_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_289_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_289_V
) AS UNUSED_TABLE_NAME  ),
t_93_Advantage_recursive_head_f10 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f10.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f10.logica_value) AS logica_value
FROM
  t_94_Advantage_MultBodyAggAux_recursive_head_f10 AS Advantage_MultBodyAggAux_recursive_head_f10
GROUP BY Advantage_MultBodyAggAux_recursive_head_f10.col0),
t_88_BestMove_r9 AS (SELECT
  t_89_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_89_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f10.logica_value))[1]).argpod AS target,
  MIN(t_92_Advantage_recursive_head_f10.logica_value) AS value
FROM
  t_2_E AS t_89_E, t_93_Advantage_recursive_head_f10 AS Advantage_recursive_head_f10, t_93_Advantage_recursive_head_f10 AS t_92_Advantage_recursive_head_f10
WHERE
  (Advantage_recursive_head_f10.col0 = t_89_E.col1) AND
  (t_92_Advantage_recursive_head_f10.col0 = t_89_E.col1)
GROUP BY t_89_E.col0 ORDER BY col0),
t_86_Advantage_MultBodyAggAux_recursive_head_f11 AS (SELECT * FROM (
  
    SELECT
      t_87_V.col0 AS col0,
      - ((BestMove_r9.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_87_V, t_88_BestMove_r9 AS BestMove_r9
    WHERE
      (BestMove_r9.col0 = t_87_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_303_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_303_V
) AS UNUSED_TABLE_NAME  ),
t_85_Advantage_recursive_head_f11 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f11.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f11.logica_value) AS logica_value
FROM
  t_86_Advantage_MultBodyAggAux_recursive_head_f11 AS Advantage_MultBodyAggAux_recursive_head_f11
GROUP BY Advantage_MultBodyAggAux_recursive_head_f11.col0),
t_80_BestMove_r10 AS (SELECT
  t_81_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_81_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f11.logica_value))[1]).argpod AS target,
  MIN(t_84_Advantage_recursive_head_f11.logica_value) AS value
FROM
  t_2_E AS t_81_E, t_85_Advantage_recursive_head_f11 AS Advantage_recursive_head_f11, t_85_Advantage_recursive_head_f11 AS t_84_Advantage_recursive_head_f11
WHERE
  (Advantage_recursive_head_f11.col0 = t_81_E.col1) AND
  (t_84_Advantage_recursive_head_f11.col0 = t_81_E.col1)
GROUP BY t_81_E.col0 ORDER BY col0),
t_78_Advantage_MultBodyAggAux_recursive_head_f12 AS (SELECT * FROM (
  
    SELECT
      t_79_V.col0 AS col0,
      - ((BestMove_r10.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_79_V, t_80_BestMove_r10 AS BestMove_r10
    WHERE
      (BestMove_r10.col0 = t_79_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_317_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_317_V
) AS UNUSED_TABLE_NAME  ),
t_77_Advantage_recursive_head_f12 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f12.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f12.logica_value) AS logica_value
FROM
  t_78_Advantage_MultBodyAggAux_recursive_head_f12 AS Advantage_MultBodyAggAux_recursive_head_f12
GROUP BY Advantage_MultBodyAggAux_recursive_head_f12.col0),
t_72_BestMove_r11 AS (SELECT
  t_73_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_73_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f12.logica_value))[1]).argpod AS target,
  MIN(t_76_Advantage_recursive_head_f12.logica_value) AS value
FROM
  t_2_E AS t_73_E, t_77_Advantage_recursive_head_f12 AS Advantage_recursive_head_f12, t_77_Advantage_recursive_head_f12 AS t_76_Advantage_recursive_head_f12
WHERE
  (Advantage_recursive_head_f12.col0 = t_73_E.col1) AND
  (t_76_Advantage_recursive_head_f12.col0 = t_73_E.col1)
GROUP BY t_73_E.col0 ORDER BY col0),
t_70_Advantage_MultBodyAggAux_recursive_head_f13 AS (SELECT * FROM (
  
    SELECT
      t_71_V.col0 AS col0,
      - ((BestMove_r11.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_71_V, t_72_BestMove_r11 AS BestMove_r11
    WHERE
      (BestMove_r11.col0 = t_71_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_331_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_331_V
) AS UNUSED_TABLE_NAME  ),
t_69_Advantage_recursive_head_f13 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f13.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f13.logica_value) AS logica_value
FROM
  t_70_Advantage_MultBodyAggAux_recursive_head_f13 AS Advantage_MultBodyAggAux_recursive_head_f13
GROUP BY Advantage_MultBodyAggAux_recursive_head_f13.col0),
t_64_BestMove_r12 AS (SELECT
  t_65_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_65_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f13.logica_value))[1]).argpod AS target,
  MIN(t_68_Advantage_recursive_head_f13.logica_value) AS value
FROM
  t_2_E AS t_65_E, t_69_Advantage_recursive_head_f13 AS Advantage_recursive_head_f13, t_69_Advantage_recursive_head_f13 AS t_68_Advantage_recursive_head_f13
WHERE
  (Advantage_recursive_head_f13.col0 = t_65_E.col1) AND
  (t_68_Advantage_recursive_head_f13.col0 = t_65_E.col1)
GROUP BY t_65_E.col0 ORDER BY col0),
t_62_Advantage_MultBodyAggAux_recursive_head_f14 AS (SELECT * FROM (
  
    SELECT
      t_63_V.col0 AS col0,
      - ((BestMove_r12.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_63_V, t_64_BestMove_r12 AS BestMove_r12
    WHERE
      (BestMove_r12.col0 = t_63_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_345_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_345_V
) AS UNUSED_TABLE_NAME  ),
t_61_Advantage_recursive_head_f14 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f14.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f14.logica_value) AS logica_value
FROM
  t_62_Advantage_MultBodyAggAux_recursive_head_f14 AS Advantage_MultBodyAggAux_recursive_head_f14
GROUP BY Advantage_MultBodyAggAux_recursive_head_f14.col0),
t_56_BestMove_r13 AS (SELECT
  t_57_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_57_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f14.logica_value))[1]).argpod AS target,
  MIN(t_60_Advantage_recursive_head_f14.logica_value) AS value
FROM
  t_2_E AS t_57_E, t_61_Advantage_recursive_head_f14 AS Advantage_recursive_head_f14, t_61_Advantage_recursive_head_f14 AS t_60_Advantage_recursive_head_f14
WHERE
  (Advantage_recursive_head_f14.col0 = t_57_E.col1) AND
  (t_60_Advantage_recursive_head_f14.col0 = t_57_E.col1)
GROUP BY t_57_E.col0 ORDER BY col0),
t_54_Advantage_MultBodyAggAux_recursive_head_f15 AS (SELECT * FROM (
  
    SELECT
      t_55_V.col0 AS col0,
      - ((BestMove_r13.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_55_V, t_56_BestMove_r13 AS BestMove_r13
    WHERE
      (BestMove_r13.col0 = t_55_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_359_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_359_V
) AS UNUSED_TABLE_NAME  ),
t_53_Advantage_recursive_head_f15 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f15.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f15.logica_value) AS logica_value
FROM
  t_54_Advantage_MultBodyAggAux_recursive_head_f15 AS Advantage_MultBodyAggAux_recursive_head_f15
GROUP BY Advantage_MultBodyAggAux_recursive_head_f15.col0),
t_48_BestMove_r14 AS (SELECT
  t_49_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_49_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f15.logica_value))[1]).argpod AS target,
  MIN(t_52_Advantage_recursive_head_f15.logica_value) AS value
FROM
  t_2_E AS t_49_E, t_53_Advantage_recursive_head_f15 AS Advantage_recursive_head_f15, t_53_Advantage_recursive_head_f15 AS t_52_Advantage_recursive_head_f15
WHERE
  (Advantage_recursive_head_f15.col0 = t_49_E.col1) AND
  (t_52_Advantage_recursive_head_f15.col0 = t_49_E.col1)
GROUP BY t_49_E.col0 ORDER BY col0),
t_46_Advantage_MultBodyAggAux_recursive_head_f16 AS (SELECT * FROM (
  
    SELECT
      t_47_V.col0 AS col0,
      - ((BestMove_r14.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_47_V, t_48_BestMove_r14 AS BestMove_r14
    WHERE
      (BestMove_r14.col0 = t_47_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_373_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_373_V
) AS UNUSED_TABLE_NAME  ),
t_45_Advantage_recursive_head_f16 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f16.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f16.logica_value) AS logica_value
FROM
  t_46_Advantage_MultBodyAggAux_recursive_head_f16 AS Advantage_MultBodyAggAux_recursive_head_f16
GROUP BY Advantage_MultBodyAggAux_recursive_head_f16.col0),
t_40_BestMove_r15 AS (SELECT
  t_41_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_41_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f16.logica_value))[1]).argpod AS target,
  MIN(t_44_Advantage_recursive_head_f16.logica_value) AS value
FROM
  t_2_E AS t_41_E, t_45_Advantage_recursive_head_f16 AS Advantage_recursive_head_f16, t_45_Advantage_recursive_head_f16 AS t_44_Advantage_recursive_head_f16
WHERE
  (Advantage_recursive_head_f16.col0 = t_41_E.col1) AND
  (t_44_Advantage_recursive_head_f16.col0 = t_41_E.col1)
GROUP BY t_41_E.col0 ORDER BY col0),
t_38_Advantage_MultBodyAggAux_recursive_head_f17 AS (SELECT * FROM (
  
    SELECT
      t_39_V.col0 AS col0,
      - ((BestMove_r15.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_39_V, t_40_BestMove_r15 AS BestMove_r15
    WHERE
      (BestMove_r15.col0 = t_39_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_387_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_387_V
) AS UNUSED_TABLE_NAME  ),
t_37_Advantage_recursive_head_f17 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f17.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f17.logica_value) AS logica_value
FROM
  t_38_Advantage_MultBodyAggAux_recursive_head_f17 AS Advantage_MultBodyAggAux_recursive_head_f17
GROUP BY Advantage_MultBodyAggAux_recursive_head_f17.col0),
t_32_BestMove_r16 AS (SELECT
  t_33_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_33_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f17.logica_value))[1]).argpod AS target,
  MIN(t_36_Advantage_recursive_head_f17.logica_value) AS value
FROM
  t_2_E AS t_33_E, t_37_Advantage_recursive_head_f17 AS Advantage_recursive_head_f17, t_37_Advantage_recursive_head_f17 AS t_36_Advantage_recursive_head_f17
WHERE
  (Advantage_recursive_head_f17.col0 = t_33_E.col1) AND
  (t_36_Advantage_recursive_head_f17.col0 = t_33_E.col1)
GROUP BY t_33_E.col0 ORDER BY col0),
t_30_Advantage_MultBodyAggAux_recursive_head_f18 AS (SELECT * FROM (
  
    SELECT
      t_31_V.col0 AS col0,
      - ((BestMove_r16.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_31_V, t_32_BestMove_r16 AS BestMove_r16
    WHERE
      (BestMove_r16.col0 = t_31_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_401_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_401_V
) AS UNUSED_TABLE_NAME  ),
t_29_Advantage_recursive_head_f18 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f18.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f18.logica_value) AS logica_value
FROM
  t_30_Advantage_MultBodyAggAux_recursive_head_f18 AS Advantage_MultBodyAggAux_recursive_head_f18
GROUP BY Advantage_MultBodyAggAux_recursive_head_f18.col0),
t_24_BestMove_r17 AS (SELECT
  t_25_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_25_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f18.logica_value))[1]).argpod AS target,
  MIN(t_28_Advantage_recursive_head_f18.logica_value) AS value
FROM
  t_2_E AS t_25_E, t_29_Advantage_recursive_head_f18 AS Advantage_recursive_head_f18, t_29_Advantage_recursive_head_f18 AS t_28_Advantage_recursive_head_f18
WHERE
  (Advantage_recursive_head_f18.col0 = t_25_E.col1) AND
  (t_28_Advantage_recursive_head_f18.col0 = t_25_E.col1)
GROUP BY t_25_E.col0 ORDER BY col0),
t_22_Advantage_MultBodyAggAux_recursive_head_f19 AS (SELECT * FROM (
  
    SELECT
      t_23_V.col0 AS col0,
      - ((BestMove_r17.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_23_V, t_24_BestMove_r17 AS BestMove_r17
    WHERE
      (BestMove_r17.col0 = t_23_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_415_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_415_V
) AS UNUSED_TABLE_NAME  ),
t_21_Advantage_recursive_head_f19 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f19.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f19.logica_value) AS logica_value
FROM
  t_22_Advantage_MultBodyAggAux_recursive_head_f19 AS Advantage_MultBodyAggAux_recursive_head_f19
GROUP BY Advantage_MultBodyAggAux_recursive_head_f19.col0),
t_16_BestMove_r18 AS (SELECT
  t_17_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_17_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f19.logica_value))[1]).argpod AS target,
  MIN(t_20_Advantage_recursive_head_f19.logica_value) AS value
FROM
  t_2_E AS t_17_E, t_21_Advantage_recursive_head_f19 AS Advantage_recursive_head_f19, t_21_Advantage_recursive_head_f19 AS t_20_Advantage_recursive_head_f19
WHERE
  (Advantage_recursive_head_f19.col0 = t_17_E.col1) AND
  (t_20_Advantage_recursive_head_f19.col0 = t_17_E.col1)
GROUP BY t_17_E.col0 ORDER BY col0),
t_13_Advantage_MultBodyAggAux_recursive_head_f20 AS (SELECT * FROM (
  
    SELECT
      t_14_V.col0 AS col0,
      - ((BestMove_r18.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS t_14_V, t_16_BestMove_r18 AS BestMove_r18
    WHERE
      (BestMove_r18.col0 = t_14_V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_429_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_429_V
) AS UNUSED_TABLE_NAME  ),
t_12_Advantage_recursive_head_f20 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f20.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f20.logica_value) AS logica_value
FROM
  t_13_Advantage_MultBodyAggAux_recursive_head_f20 AS Advantage_MultBodyAggAux_recursive_head_f20
GROUP BY Advantage_MultBodyAggAux_recursive_head_f20.col0),
t_7_BestMove_r19 AS (SELECT
  t_8_E.col0 AS col0,
  ((ARRAY_AGG(ROW(t_8_E.col1)::logicarecord57208616 order by Advantage_recursive_head_f20.logica_value))[1]).argpod AS target,
  MIN(t_11_Advantage_recursive_head_f20.logica_value) AS value
FROM
  t_2_E AS t_8_E, t_12_Advantage_recursive_head_f20 AS Advantage_recursive_head_f20, t_12_Advantage_recursive_head_f20 AS t_11_Advantage_recursive_head_f20
WHERE
  (Advantage_recursive_head_f20.col0 = t_8_E.col1) AND
  (t_11_Advantage_recursive_head_f20.col0 = t_8_E.col1)
GROUP BY t_8_E.col0 ORDER BY col0),
t_4_Advantage_MultBodyAggAux_recursive_head_f21 AS (SELECT * FROM (
  
    SELECT
      V.col0 AS col0,
      - ((BestMove_r19.value) * (0.90)) AS logica_value
    FROM
      t_5_V AS V, t_7_BestMove_r19 AS BestMove_r19
    WHERE
      (BestMove_r19.col0 = V.col0) UNION ALL
  
    SELECT
      5 AS col0,
      1 AS logica_value UNION ALL
  
    SELECT
      t_443_V.col0 AS col0,
      0 AS logica_value
    FROM
      t_5_V AS t_443_V
) AS UNUSED_TABLE_NAME  ),
t_3_Advantage_recursive_head_f21 AS (SELECT
  Advantage_MultBodyAggAux_recursive_head_f21.col0 AS col0,
  SUM(Advantage_MultBodyAggAux_recursive_head_f21.logica_value) AS logica_value
FROM
  t_4_Advantage_MultBodyAggAux_recursive_head_f21 AS Advantage_MultBodyAggAux_recursive_head_f21
GROUP BY Advantage_MultBodyAggAux_recursive_head_f21.col0)
SELECT
  E.col0 AS col0,
  ((ARRAY_AGG(ROW(E.col1)::logicarecord57208616 order by Advantage_recursive_head_f21.logica_value))[1]).argpod AS target,
  MIN(t_1_Advantage_recursive_head_f21.logica_value) AS value
FROM
  t_2_E AS E, t_3_Advantage_recursive_head_f21 AS Advantage_recursive_head_f21, t_3_Advantage_recursive_head_f21 AS t_1_Advantage_recursive_head_f21
WHERE
  (Advantage_recursive_head_f21.col0 = E.col1) AND
  (t_1_Advantage_recursive_head_f21.col0 = E.col1)
GROUP BY E.col0 ORDER BY col0;
