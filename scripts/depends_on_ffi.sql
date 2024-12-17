DROP VIEW IF EXISTS valid_crates CASCADE;

DROP VIEW IF EXISTS crates_avg_downloads CASCADE;

DROP TABLE IF EXISTS has_ffi;

CREATE VIEW
    valid_crates AS (
        SELECT
            t1.crate_id,
            crates.name as crate_name,
            crates.downloads as downloads,
            t2.version_id,
            t2.num as version,
            to_date (cast(t2.updated_at as TEXT), 'YYYY-MM-DD') as last_updated
        FROM
            (
                SELECT
                    crate_id,
                    max(created_at) as created_at
                FROM
                    versions
                WHERE
                    NOT yanked
                GROUP BY
                    crate_id
            ) as t1
            INNER JOIN (
                select
                    crate_id,
                    id as version_id,
                    num,
                    created_at,
                    updated_at
                from
                    versions
                where
                    not yanked
            ) as t2 ON t1.crate_id = t2.crate_id
            AND t2.created_at = t1.created_at
            INNER JOIN crates on t1.crate_id = crates.id
    );

CREATE VIEW
    crates_avg_downloads AS (
        select
            crate_id,
            avg(daily_downloads) as avg_daily_downloads
        from
            (
                select
                    crate_id,
                    sum(version_downloads.downloads) as daily_downloads,
                    date
                from
                    version_downloads
                    inner join versions on version_downloads.version_id = versions.id
                    inner join crates on versions.crate_id = crates.id
                group by
                    crate_id,
                    date
            ) as t
        where
            date >= '2023-03-20'
            and date <= '2023-09-20'
        group by
            crate_id
    );

CREATE VIEW
    population AS (
        SELECT
            vc.crate_name,
            vc.version,
            vc.downloads,
            ntile (100) over (
                order by
                    vc.downloads
            ) as percentile_downloads,
            avg_daily_downloads,
            ntile (100) over (
                order by
                    cad.avg_daily_downloads
            ) as percentile_daily_downloads
        FROM
            valid_crates vc
            INNER JOIN crates_avg_downloads cad on vc.crate_id = cad.crate_id
    );

DROP TABLE IF EXISTS has_ffi;

CREATE TEMP TABLE has_ffi (crate_name varchar, version varchar);

COPY has_ffi (crate_name, version)
FROM
    '/Users/icmccorm/git/mirilli/had_ffi.csv' DELIMITER ',';

CREATE VIEW
    depends_on_ffi AS (
        select distinct
            parent_crates.name as parent_name,
            dependent_crates.name
        from
            dependencies
            inner join crates dependent_crates on dependencies.crate_id = dependent_crates.id
            inner join versions on versions.id = dependencies.version_id
            inner join crates parent_crates on versions.crate_id = parent_crates.id
            inner join has_ffi on has_ffi.crate_name = dependent_crates.name
            inner join valid_crates vc on parent_crates.name = vc.crate_name
    );

select
    *
from
    depends_on_ffi
where
    parent_name = 'inkwell';

select
    count(*)
from
    (
        select distinct
            parent_name
        from
            depends_on_ffi
    ) as t;

select
    max(c),
    avg(c),
    stddev (c)
from
    (
        select
            count(distinct parent_name) as c,
            name
        from
            depends_on_ffi
        group by
            name
    ) as t