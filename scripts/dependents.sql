DROP TABLE IF EXISTS had_ffi;
CREATE TEMPORARY TABLE had_ffi (
    crate_name VARCHAR,
    version VARCHAR
);
COPY had_ffi(crate_name, version)
FROM '/usr/src/mirilli/build/stage1/had_ffi.csv'
DELIMITER ','
CSV HEADER;

DROP TABLE IF EXISTS had_ffi_ids CASCADE;
CREATE TEMPORARY TABLE had_ffi_ids (
    crate_id INTEGER
);

INSERT INTO had_ffi_ids
SELECT distinct valid_crates.crate_id
FROM valid_crates INNER JOIN had_ffi hfi ON valid_crates.crate_name = hfi.crate_name;

DROP VIEW IF EXISTS depends_on;
CREATE VIEW depends_on AS (
    SELECT versions.crate_id AS parent_crate_id, dependencies.crate_id AS child_crate_id
        FROM dependencies
            INNER JOIN versions
                ON dependencies.version_id = versions.id
            INNER JOIN had_ffi_ids
                ON dependencies.crate_id = had_ffi_ids.crate_id
            INNER JOIN valid_crates on valid_crates.crate_id = versions.crate_id
);

DO $$
DECLARE
    num_crates INTEGER;
    num_valid_crates FLOAT;
    num_dependent_crates INTEGER;
    max_dep INTEGER;
    mean_dep FLOAT;
    stdev_dep FLOAT;
BEGIN
    SELECT COUNT(DISTINCT(crate_name)) INTO num_crates FROM had_ffi;
    RAISE NOTICE 'Number of Crates: %', num_crates;
    SELECT COUNT(DISTINCT(crate_name)) INTO num_valid_crates FROM valid_crates;
    RAISE NOTICE 'Percent of All: %', round((num_crates::FLOAT / num_valid_crates * 100)::NUMERIC, 1);
    SELECT COUNT(DISTINCT(depends_on.parent_crate_id)) FROM depends_on INTO num_dependent_crates;
    RAISE NOTICE 'Number of Dependent Crates: %', num_dependent_crates;
    RAISE NOTICE 'Percent Dependent of All: %',round((num_dependent_crates::FLOAT / num_valid_crates * 100)::NUMERIC, 1);

    SELECT max(n), avg(n), stddev(n) INTO max_dep, mean_dep, stdev_dep FROM (SELECT COUNT(DISTINCT parent_crate_id) as n FROM depends_on GROUP BY child_crate_id) as t;
    RAISE NOTICE 'Max Dependent: %',max_dep;
    RAISE NOTICE 'Mean Dependent: %', round(mean_dep::NUMERIC, 1);
    RAISE NOTICE 'St.Dev Dependent: %',round(stdev_dep::NUMERIC, 1);
END $$;
