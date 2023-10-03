\ ir../../ data / population.sql;
DROP TABLE IF EXISTS has_bytecode CASCADE;
DROP TABLE IF EXISTS has_tests CASCADE;
DROP TABLE IF EXISTS engaged;
CREATE TABLE has_bytecode (
    crate_name VARCHAR NOT NULL,
    version VARCHAR NOT NULL,
    PRIMARY KEY (crate_name, version)
);
\copy has_bytecode (crate_name, version) from './data/results/stage1/has_bytecode.csv' WITH DELIMITER ',' CSV;

CREATE TABLE has_tests (
    crate_name VARCHAR NOT NULL,
    version VARCHAR NOT NULL,
    PRIMARY KEY (crate_name, version)
);
\copy has_tests (crate_name, version) from './data/results/stage1/has_tests.csv' WITH DELIMITER ',' CSV;

CREATE VIEW crates_with_bytecode AS(
    SELECT *
    FROM has_bytecode
        INNER JOIN crates ON has_bytecode.crate_name = crates.name
);
CREATE VIEW first_order_dependencies AS (
    SELECT distinct parent_crate_id as crate_id, parent_name as crate_name, parent_version as version FROM crates_with_bytecode INNER JOIN depends_on ON crates_with_bytecode.id = depends_on.child_crate_id
);
CREATE VIEW second_order_dependencies AS (
    SELECT distinct parent_crate_id as crate_id, parent_name as crate_name, parent_version as version FROM first_order_dependencies INNER JOIN depends_on ON first_order_dependencies.crate_id = depends_on.child_crate_id
);
CREATE VIEW crates_to_test AS
(
SELECT distinct t.crate_name, t.version
from (select distinct crate_name, version
      from first_order_dependencies
      UNION ALL
      select distinct crate_name, version
      from second_order_dependencies
      UNION ALL
      select distinct *
      from has_bytecode) as t
         INNER JOIN has_tests on has_tests.crate_name = t.crate_name
    );
\copy (select distinct crate_name, version from crates_to_test) TO './data/compiled/stage1/stage2.csv' WITH DELIMITER ',' CSV;