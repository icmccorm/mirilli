DROP VIEW IF EXISTS population CASCADE;
CREATE VIEW population AS (
    select t1.crate_id,
        crates.name as crate_name,
        crates.downloads as downloads,
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
        parent.id as parent_crate_id,
        parent_v.version as parent_version,
        parent_v.version_id as parent_version_id,
        child.name as child_name,
        dependencies.crate_id as child_crate_id
    FROM dependencies
        INNER JOIN crates child on dependencies.crate_id = child.id
        INNER JOIN population parent_v on dependencies.version_id = parent_v.version_id
        INNER JOIN crates parent on parent_v.crate_id = parent.id
);
CREATE VIEW downloads_percentile_all_time AS (
    select crate_name,
        ntile(100) over (
            order by downloads
        )
    from population
);
CREATE VIEW downloads_percentile_last_month AS (
    SELECT *,
        ntile(100) over (
            order by t.downloads
        ) as percentile
    FROM (
            SELECT p.crate_name,
                p.crate_id,
                sum(version_downloads.downloads) as downloads
            FROM version_downloads
                INNER JOIN population p ON version_downloads.version_id = p.version_id
            where date >= '2023-04-06'
                and date <= '2023-05-06'
            group by p.crate_name,
                p.crate_id
        ) as t
);