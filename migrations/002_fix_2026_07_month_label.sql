-- Fix: the July 2026 analytics CSVs were imported with month = '2026-08'
-- (the CSV modal defaults to the current month, and the import ran on 2026-08-03).
-- Run in Supabase SQL Editor.
--
-- IMPORTANT: close the Link Graph tab first. While it is open, any edit triggers
-- sbSync, which re-upserts state.analytics and would write the '2026-08' rows back.


-- -- Step 1: inspect before changing anything ------------------------------
select month, count(*) as row_count, min(imported_at) as imported_at
from analytics
where month in ('2026-07', '2026-08')
group by month
order by month;

-- Expected: one row, month = '2026-08'. If a '2026-07' row group also exists,
-- read the note on the delete in step 2 before running it.


-- -- Step 2: relabel -------------------------------------------------------
begin;

-- Clears the way for the rename: unique(month, url) would reject the update if
-- a URL already exists under '2026-07'. Only colliding URLs are removed; any
-- '2026-07' rows for URLs absent from the misfiled batch are left untouched.
-- No-op when '2026-07' is empty, which is the expected case.
delete from analytics a
where a.month = '2026-07'
  and exists (
    select 1 from analytics b
    where b.month = '2026-08' and b.url = a.url
  );

update analytics
set month = '2026-07'
where month = '2026-08';

commit;


-- -- Step 3: verify --------------------------------------------------------
select month, count(*) as row_count, sum(clicks) as clicks, sum(pageviews) as pageviews
from analytics
group by month
order by month;

-- '2026-08' should be gone and '2026-07' should hold the imported row count.
-- Then reopen the app: loadFromSupabase() is Supabase-first, so the Analytics
-- view will show the data under Jul 2026.
