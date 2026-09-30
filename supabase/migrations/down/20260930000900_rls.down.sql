do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy if exists %I on %I', r.policyname, r.tablename);
  end loop;
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table %I disable row level security', r.tablename);
  end loop;
end $$;
drop function if exists entries_column_guard() cascade;
drop function if exists submitters_column_guard() cascade;
drop function if exists films_column_guard() cascade;
