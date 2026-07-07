create extension if not exists postgis;
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

do $$
begin
    create type public.pricing_status as enum ('free', 'paid', 'unknown');
exception
    when duplicate_object then null;
end $$;

do $$
begin
    create type public.submission_status as enum ('pending', 'approved', 'rejected');
exception
    when duplicate_object then null;
end $$;

create table if not exists public.locations (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    address_line1 text,
    city text,
    state text,
    postal_code text,
    notes text,
    pricing_status public.pricing_status not null default 'unknown',
    source text not null default 'curated',
    location geography(point, 4326) not null,
    last_verified_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.submissions (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    address_line1 text not null,
    city text,
    state text,
    postal_code text,
    notes text,
    pricing_status public.pricing_status not null default 'unknown',
    source text not null default 'anonymous',
    location geography(point, 4326) not null,
    status public.submission_status not null default 'pending',
    review_notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists locations_location_gist on public.locations using gist (location);
create index if not exists locations_name_trgm on public.locations using gin (name gin_trgm_ops);
create index if not exists locations_search_tsv on public.locations using gin (
    to_tsvector(
        'english',
        coalesce(name, '') || ' ' ||
        coalesce(address_line1, '') || ' ' ||
        coalesce(city, '') || ' ' ||
        coalesce(state, '') || ' ' ||
        coalesce(postal_code, '') || ' ' ||
        coalesce(notes, '')
    )
);

create index if not exists submissions_location_gist on public.submissions using gist (location);
create index if not exists submissions_status_idx on public.submissions (status);

alter table public.locations enable row level security;
alter table public.submissions enable row level security;

drop policy if exists "public can read locations" on public.locations;
create policy "public can read locations"
    on public.locations
    for select
    to anon, authenticated
    using (true);

drop policy if exists "service can manage locations" on public.locations;
create policy "service can manage locations"
    on public.locations
    for all
    to service_role
    using (true)
    with check (true);

drop policy if exists "service can manage submissions" on public.submissions;
create policy "service can manage submissions"
    on public.submissions
    for all
    to service_role
    using (true)
    with check (true);

create or replace function public.search_locations(
    query text default '',
    latitude double precision default null,
    longitude double precision default null,
    radius_meters integer default 50000,
    limit_count integer default 50
)
returns table (
    id uuid,
    name text,
    address_line1 text,
    city text,
    state text,
    postal_code text,
    notes text,
    pricing_status public.pricing_status,
    source text,
    latitude double precision,
    longitude double precision,
    last_verified_at timestamptz,
    distance_meters double precision
)
language sql
stable
as $$
    with params as (
        select
            nullif(btrim(query), '') as search_query,
            latitude as lat,
            longitude as lng,
            greatest(1, least(limit_count, 100)) as max_rows,
            greatest(100, least(radius_meters, 100000)) as radius
    )
    select
        l.id,
        l.name,
        l.address_line1,
        l.city,
        l.state,
        l.postal_code,
        l.notes,
        l.pricing_status,
        l.source,
        st_y(l.location::geometry) as latitude,
        st_x(l.location::geometry) as longitude,
        l.last_verified_at,
        case
            when p.lat is null or p.lng is null then null
            else st_distance(
                l.location,
                st_setsrid(st_makepoint(p.lng, p.lat), 4326)::geography
            )
        end as distance_meters
    from public.locations l
    cross join params p
    where
        p.search_query is null
        or to_tsvector(
            'english',
            coalesce(l.name, '') || ' ' ||
            coalesce(l.address_line1, '') || ' ' ||
            coalesce(l.city, '') || ' ' ||
            coalesce(l.state, '') || ' ' ||
            coalesce(l.postal_code, '') || ' ' ||
            coalesce(l.notes, '')
        ) @@ plainto_tsquery('english', p.search_query)
        or l.name ilike '%' || p.search_query || '%'
        or coalesce(l.address_line1, '') ilike '%' || p.search_query || '%'
        or coalesce(l.city, '') ilike '%' || p.search_query || '%'
        or coalesce(l.state, '') ilike '%' || p.search_query || '%'
        or coalesce(l.postal_code, '') ilike '%' || p.search_query || '%'
    order by
        distance_meters nulls last,
        l.name asc
    limit (select max_rows from params);
$$;

drop function if exists public.submit_location(
    text,
    text,
    text,
    text,
    text,
    text,
    public.pricing_status,
    double precision,
    double precision
);

create or replace function public.submit_location(
    name text,
    address_line1 text,
    city text,
    state text,
    postal_code text,
    notes text,
    pricing_status public.pricing_status,
    latitude double precision,
    longitude double precision
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    submission_id uuid;
begin
    insert into public.submissions (
        name,
        address_line1,
        city,
        state,
        postal_code,
        notes,
        pricing_status,
        source,
        location,
        status
    )
    values (
        submit_location.name,
        submit_location.address_line1,
        nullif(btrim(submit_location.city), ''),
        nullif(btrim(submit_location.state), ''),
        nullif(btrim(submit_location.postal_code), ''),
        nullif(btrim(submit_location.notes), ''),
        submit_location.pricing_status,
        'anonymous',
        st_setsrid(st_makepoint(submit_location.longitude, submit_location.latitude), 4326)::geography,
        'pending'
    )
    returning id into submission_id;

    return submission_id;
end;
$$;

grant select on public.locations to anon, authenticated;
grant execute on function public.search_locations(
    text,
    double precision,
    double precision,
    integer,
    integer
) to anon, authenticated;
grant execute on function public.submit_location(
    text,
    text,
    text,
    text,
    text,
    text,
    public.pricing_status,
    double precision,
    double precision
) to anon, authenticated;
