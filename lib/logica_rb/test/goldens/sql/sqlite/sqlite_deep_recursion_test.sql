ATTACH DATABASE ':memory:' AS logica_test;



DROP TABLE IF EXISTS logica_test.N_ifr0_f18;
CREATE TABLE logica_test.N_ifr0_f18 AS SELECT * FROM (
  
    SELECT
      100 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N_ifr0_f18

DROP TABLE IF EXISTS logica_test.N_ifr1_f18;
CREATE TABLE logica_test.N_ifr1_f18 AS SELECT * FROM (
  
    SELECT
      ((N_ifr0_f18.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N_ifr0_f18 AS N_ifr0_f18 UNION ALL
  
    SELECT
      100 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N_ifr1_f18

DROP TABLE IF EXISTS logica_test.N_ifr2_f18;
CREATE TABLE logica_test.N_ifr2_f18 AS SELECT * FROM (
  
    SELECT
      ((N_ifr1_f18.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N_ifr1_f18 AS N_ifr1_f18 UNION ALL
  
    SELECT
      100 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N_ifr2_f18

DROP TABLE IF EXISTS logica_test.N_ifr1_f18;
CREATE TABLE logica_test.N_ifr1_f18 AS SELECT * FROM (
  
    SELECT
      ((N_ifr2_f18.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N_ifr2_f18 AS N_ifr2_f18 UNION ALL
  
    SELECT
      100 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N_ifr1_f18

DROP TABLE IF EXISTS logica_test.M;
CREATE TABLE logica_test.M AS SELECT * FROM (
  
    SELECT
      ((N_ifr3_f18.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N_ifr1_f18 AS N_ifr3_f18 UNION ALL
  
    SELECT
      100 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.M

DROP TABLE IF EXISTS logica_test.N_ifr0;
CREATE TABLE logica_test.N_ifr0 AS SELECT * FROM (
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N_ifr0

DROP TABLE IF EXISTS logica_test.N_ifr1;
CREATE TABLE logica_test.N_ifr1 AS SELECT * FROM (
  
    SELECT
      ((N_ifr0.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N_ifr0 AS N_ifr0 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N_ifr1

DROP TABLE IF EXISTS logica_test.N_ifr2;
CREATE TABLE logica_test.N_ifr2 AS SELECT * FROM (
  
    SELECT
      ((N_ifr1.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N_ifr1 AS N_ifr1 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N_ifr2

DROP TABLE IF EXISTS logica_test.N_ifr1;
CREATE TABLE logica_test.N_ifr1 AS SELECT * FROM (
  
    SELECT
      ((N_ifr2.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N_ifr2 AS N_ifr2 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N_ifr1

DROP TABLE IF EXISTS logica_test.N;
CREATE TABLE logica_test.N AS SELECT * FROM (
  
    SELECT
      ((N_ifr3.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N_ifr1 AS N_ifr3 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N

DROP TABLE IF EXISTS logica_test.N30_ifr0;
CREATE TABLE logica_test.N30_ifr0 AS SELECT * FROM (
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N30_ifr0

DROP TABLE IF EXISTS logica_test.N30_ifr1;
CREATE TABLE logica_test.N30_ifr1 AS SELECT * FROM (
  
    SELECT
      ((N30_ifr0.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N30_ifr0 AS N30_ifr0 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N30_ifr1

DROP TABLE IF EXISTS logica_test.N30_ifr2;
CREATE TABLE logica_test.N30_ifr2 AS SELECT * FROM (
  
    SELECT
      ((N30_ifr1.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N30_ifr1 AS N30_ifr1 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N30_ifr2

DROP TABLE IF EXISTS logica_test.N30_ifr1;
CREATE TABLE logica_test.N30_ifr1 AS SELECT * FROM (
  
    SELECT
      ((N30_ifr2.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N30_ifr2 AS N30_ifr2 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N30_ifr1

DROP TABLE IF EXISTS logica_test.N30;
CREATE TABLE logica_test.N30 AS SELECT * FROM (
  
    SELECT
      ((N30_ifr3.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N30_ifr1 AS N30_ifr3 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N30

DROP TABLE IF EXISTS logica_test.N29_ifr0;
CREATE TABLE logica_test.N29_ifr0 AS SELECT * FROM (
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N29_ifr0

DROP TABLE IF EXISTS logica_test.N29_ifr1;
CREATE TABLE logica_test.N29_ifr1 AS SELECT * FROM (
  
    SELECT
      ((N29_ifr0.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N29_ifr0 AS N29_ifr0 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N29_ifr1

DROP TABLE IF EXISTS logica_test.N29_ifr0;
CREATE TABLE logica_test.N29_ifr0 AS SELECT * FROM (
  
    SELECT
      ((N29_ifr1.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N29_ifr1 AS N29_ifr1 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N29_ifr0

DROP TABLE IF EXISTS logica_test.N29;
CREATE TABLE logica_test.N29 AS SELECT * FROM (
  
    SELECT
      ((N29_ifr2.logica_value) + (1)) AS logica_value
    FROM
      logica_test.N29_ifr0 AS N29_ifr2 UNION ALL
  
    SELECT
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_test.N29

WITH t_0_Test_MultBodyAggAux AS (SELECT * FROM (
  
    SELECT
      'M' AS col0,
      M.logica_value AS logica_value
    FROM
      logica_test.M AS M UNION ALL
  
    SELECT
      'N' AS col0,
      N.logica_value AS logica_value
    FROM
      logica_test.N AS N UNION ALL
  
    SELECT
      'N30' AS col0,
      N30.logica_value AS logica_value
    FROM
      logica_test.N30 AS N30 UNION ALL
  
    SELECT
      'N29' AS col0,
      N29.logica_value AS logica_value
    FROM
      logica_test.N29 AS N29
) AS UNUSED_TABLE_NAME  )
SELECT
  Test_MultBodyAggAux.col0 AS col0,
  MAX(Test_MultBodyAggAux.logica_value) AS logica_value
FROM
  t_0_Test_MultBodyAggAux AS Test_MultBodyAggAux
GROUP BY Test_MultBodyAggAux.col0 ORDER BY col0;
