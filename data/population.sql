DROP VIEW IF EXISTS depends_on;
DROP VIEW IF EXISTS population;
DROP TABLE IF EXISTS sample;

CREATE VIEW population AS (
    select t1.crate_id,
        crates.name as crate_name,
        t2.version_id,
        t2.num as version
    from (
            select crate_id,
                max(created_at) as created_at
            from versions
            where not yanked
            group by crate_id

        ) as t1
        INNER JOIN (
            select crate_id,
                id as version_id,
                num,
                created_at
            from versions
            where not yanked
        ) as t2 ON t1.crate_id = t2.crate_id
        AND t2.created_at = t1.created_at
        INNER JOIN crates on t1.crate_id = crates.id
);
CREATE VIEW depends_on AS (
    SELECT parent.name as parent_name,
        parent.id as parent_id,
        parent_v.version,
        child.name as child_name
    FROM dependencies
        INNER JOIN crates child on dependencies.crate_id = child.id
        INNER JOIN population parent_v on dependencies.version_id = parent_v.version_id
        INNER JOIN crates parent on parent_v.crate_id = parent.id
);
CREATE TABLE sample (
    crate_name VARCHAR,
    version VARCHAR
);
COPY sample(crate_name, version)
FROM '/Users/icmccorm/git/ffickle/data/captured_abi_subset.csv'
DELIMITER ','
CSV HEADER;

CREATE VIEW crates_with_ffi AS (
select sample.crate_name, p.crate_id, sample.version, p.version_id from sample inner join population p on sample.crate_name = p.crate_name and sample.version = p.version
                               );