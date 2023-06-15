DROP VIEW IF EXISTS downloads_percentile_all_time;
DROP VIEW IF EXISTS ffi_and_dependents;
DROP VIEW IF EXISTS crates_with_ffi;
DROP VIEW IF EXISTS first_order;
DROP VIEW IF EXISTS zeroth_order;
DROP VIEW IF EXISTS depends_on_ffi;
DROP VIEW IF EXISTS children_to_select;
DROP VIEW IF EXISTS depends_on;
DROP view if exists downloads_percentile_last_month;
DROP VIEW IF EXISTS crates_with_ffi_lint;
DROP VIEW IF EXISTS population;
DROP VIEW IF EXISTS grep_subsample_min_config;
DROP VIEW IF EXISTS grep_subsample;
DROP VIEW IF EXISTS crates_with_tests;
DROP VIEW IF EXISTS crates_with_tests_and_ffi;
DROP TABLE IF EXISTS grep_sample;
DROP TABLE IF EXISTS passed_cargo_early;
DROP TABLE IF EXISTS passed_cargo_late;
DROP TABLE IF EXISTS lint_found_abi;
select crate_name, version from population order by crate_name asc;
CREATE TABLE grep_sample
(
    crate_name  VARCHAR,
    version     VARCHAR,
    ffi_c_count INTEGER,
    ffi_count   INTEGER,
    test_count  INTEGER,
    bench_count INTEGER
);

CREATE TABLE passed_cargo_late
(
    crate_name VARCHAR
);

CREATE TABLE passed_cargo_early
(
    crate_name VARCHAR
);

CREATE TABLE lint_found_abi
(
    crate_name VARCHAR,
    version    VARCHAR
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
       parent_v.version_id   as parent_version_id,
       child.name            as child_name,
       dependencies.crate_id as child_crate_id
FROM dependencies
         INNER JOIN crates child on dependencies.crate_id = child.id
         INNER JOIN population parent_v on dependencies.version_id = parent_v.version_id
         INNER JOIN crates parent on parent_v.crate_id = parent.id
    );

CREATE VIEW downloads_percentile_all_time AS
(
select id, ntile(100) over (order by downloads)
from crates
    );

CREATE VIEW downloads_percentile_last_month AS
(
SELECT *, ntile(100) over (order by downloads) as percentile
FROM (SELECT p.crate_name, p.crate_id, p.version, p.version_id, sum(downloads) as downloads
      FROM version_downloads
               INNER JOIN population p
                          ON version_downloads.version_id = p.version_id
      where date >= '2023-04-06'
        and date <= '2023-05-06'
      group by p.crate_name, p.crate_id, p.version, p.version_id) as t
    );
;

COPY grep_sample (crate_name, version, ffi_c_count, ffi_count, test_count, bench_count)
    FROM '/Users/icmccorm/git/ffickle/data/results/count.csv'
    DELIMITER ','
    CSV HEADER;

copy lint_found_abi (crate_name, version)
    FROM '/Users/icmccorm/git/ffickle/data/compiled/abi_subset.csv'
    DELIMITER ','
    CSV HEADER;

copy passed_cargo_early (crate_name)
    FROM '/Users/icmccorm/git/ffickle/data/compiled/finished_early.csv'
    DELIMITER ','
    CSV HEADER;

copy passed_cargo_late (crate_name)
    FROM '/Users/icmccorm/git/ffickle/data/compiled/finished_late.csv'
    DELIMITER ','
    CSV HEADER;



select count(*) from passed_cargo_early;
select crate_name, version from population where population.crate_name not in (select crate_name from passed_cargo_early) order by random() limit 20;

select population.crate_name, population.version from population inner join downloads_percentile_last_month on population.crate_id = downloads_percentile_last_month.crate_id
where percentile > 90;

select count(*)
from downloads_percentile_last_month
         inner join passed_cargo_early on passed_cargo_early.crate_name = downloads_percentile_last_month.crate_name
where percentile > 90;

CREATE VIEW crates_with_ffi_lint AS
(
select p.*
from lint_found_abi
         inner join population p on lint_found_abi.crate_name = p.crate_name
    );

CREATE VIEW crates_with_tests AS
(
select grep_sample.crate_name,
       crates.id               as crate_id,
       crates.downloads,
       grep_sample.version,
       v.id                    as version_id,
       grep_sample.test_count  as test_count,
       grep_sample.ffi_count   as ffi_count,
       grep_sample.bench_count as bench_count,
       grep_sample.ffi_c_count as ffi_c_count
from grep_sample
         inner join crates on grep_sample.crate_name = crates.name
         inner join versions v on crates.id = v.crate_id and v.num = grep_sample.version
where grep_sample.test_count + grep_sample.bench_count > 0
    );



create view children_to_select as
(
select distinct child_crate_id
from depends_on
where child_crate_id in (select crate_id from crates_with_ffi_lint)

    );

create view depends_on_ffi as
(
select depends_on.*
from depends_on
         inner join children_to_select on depends_on.child_crate_id = children_to_select.child_crate_id
    );

create view first_order as
(
select parent_name as crate_name, parent_version as version, repository as url
from depends_on_ffi
         inner join crates on crates.id = depends_on_ffi.parent_crate_id

    );
create view zeroth_order as
(
select crate_name, version, repository as url
from lint_found_abi
         inner join crates on crates.name = lint_found_abi.crate_name

    );
select count(*)
from first_order
         inner join crates on crates.name = first_order.crate_name
         inner join downloads_percentile_last_month dplm on crates.id = dplm.crate_id
where percentile >= 80


/*select crate_name, version, crates.repository from crates_with_ffi_lint inner join crates on crates_with_ffi_lint.crate_id = crates.id;
*/
