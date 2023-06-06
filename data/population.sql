DROP VIEW IF EXISTS ffi_and_dependents;
DROP VIEW IF EXISTS crates_with_ffi;
DROP VIEW IF EXISTS depends_on;
DROP VIEW IF EXISTS population;
DROP VIEW IF EXISTS grep_subsample_min_config;
DROP VIEW IF EXISTS grep_subsample;
DROP VIEW IF EXISTS crates_with_tests_and_ffi;

DROP TABLE IF EXISTS grep_sample;


DROP TABLE IF EXISTS cargo_early_sample;

CREATE TABLE grep_sample
(
    crate_name  VARCHAR,
    version     VARCHAR,
    ffi_c_count INTEGER,
    ffi_count   INTEGER,
    test_count  INTEGER,
    bench_count INTEGER
);

CREATE TABLE cargo_early_sample
(
  crate_name VARCHAR,
  version   VARCHAR
);
/*
 all crates                                 113632
 crates with a valid version                109348
 crates with #[test] or #[bench]             57782
 crates with extern or extern "C"             4202
 crates with > 1000 downloads                 2728
 crates that pass early without config         336
 crates with >= 99 %tile downloads              58
*/


CREATE VIEW population AS
(
select t1.crate_id,
       crates.name as crate_name,
       t2.version_id,
       t2.num      as version
from (select crate_id,
             max(created_at) as created_at
      from versions
      where not yanked
      group by crate_id) as t1
         INNER JOIN (select crate_id,
                            id as version_id,
                            num,
                            created_at
                     from versions
                     where not yanked) as t2 ON t1.crate_id = t2.crate_id
    AND t2.created_at = t1.created_at
         INNER JOIN crates on t1.crate_id = crates.id
    );
CREATE VIEW depends_on AS
(
SELECT parent.name           as parent_name,
       parent.id             as parent_crate_id,
       parent_v.version      as parent_version,
       child.name            as child_name,
       dependencies.crate_id as child_crate_id
FROM dependencies
         INNER JOIN crates child on dependencies.crate_id = child.id
         INNER JOIN population parent_v on dependencies.version_id = parent_v.version_id
         INNER JOIN crates parent on parent_v.crate_id = parent.id
    );

COPY grep_sample (crate_name, version, ffi_c_count, ffi_count, test_count, bench_count)
    FROM '/Users/icmccorm/git/ffickle/data/results/count.csv'
    DELIMITER ','
    CSV HEADER;

copy cargo_early_sample (crate_name, version)
    FROM '/Users/icmccorm/git/ffickle/data/compiled/abi_subset_early.csv'
    DELIMITER ','
    CSV HEADER;

CREATE VIEW crates_with_tests_and_ffi AS
(
select grep_sample.crate_name, crates.id as crate_id, crates.downloads, grep_sample.version, v.id as version_id
from grep_sample
         inner join crates on grep_sample.crate_name = crates.name
         inner join versions v on crates.id = v.crate_id and v.num = grep_sample.version
         where ffi_c_count > 0 and grep_sample.test_count + grep_sample.bench_count > 0
    );


create view grep_subsample as
(
select cf.crate_name, cf.version, ntile(100) over (order by cf.downloads) as percentile
from crates_with_tests_and_ffi  cf
where cf.downloads > 1000
order by percentile desc);

CREATE VIEW ffi_and_dependents as
(
select *
from depends_on
         inner join crates_with_tests_and_ffi on crates_with_tests_and_ffi.crate_id = depends_on.child_crate_id
);

CREATE VIEW grep_subsample_min_config AS (
SELECT grep_subsample.* FROM grep_subsample INNER JOIN cargo_early_sample ces on grep_subsample.crate_name = ces.crate_name
                                         );
