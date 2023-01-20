DROP VIEW IF EXISTS population;
DROP VIEW IF EXISTS depends_on;

CREATE VIEW population AS (
    select t1.crate_id,
        crates.name,
        t2.version_id,
        t2.num
    from (
            select crate_id,
                max(created_at) as created_at
            from versions
            group by crate_id
            where not yanked
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
        parent_v.num,
        child.name as child_name
    FROM dependencies
        INNER JOIN crates child on dependencies.crate_id = child.id
        INNER JOIN population parent_v on dependencies.version_id = parent_v.version_id
        INNER JOIN crates parent on parent_v.crate_id = parent.id
);