insert into public.locations (
    id,
    name,
    address_line1,
    city,
    state,
    postal_code,
    notes,
    pricing_status,
    source,
    location,
    last_verified_at
)
values
(
    '2D42C1A3-0F6E-4C54-8D52-2F96C8E3D101',
    'Demo Free Air - West Loop',
    '1200 W Randolph St',
    'Chicago',
    'IL',
    '60607',
    'Demo seed entry. Replace with verified locations before launch.',
    'free',
    'demo-seed',
    st_setsrid(st_makepoint(-87.6592, 41.8842), 4326)::geography,
    '2024-08-30T12:00:00Z'
),
(
    '7E92E7A2-DB55-4C28-9AF1-39A0B66A2A02',
    'Demo Paid Air - South Loop',
    '1550 S Wabash Ave',
    'Chicago',
    'IL',
    '60605',
    'Demo seed entry. Marked paid with a dollar-sign badge.',
    'paid',
    'demo-seed',
    st_setsrid(st_makepoint(-87.6254, 41.8605), 4326)::geography,
    '2024-08-30T12:00:00Z'
),
(
    'C8AE7A93-5D06-4D85-8D91-BF1E8E0A3A03',
    'Demo Free Air - Lakeview',
    '3200 N Clark St',
    'Chicago',
    'IL',
    '60657',
    'Demo seed entry for nearby search behavior.',
    'free',
    'demo-seed',
    st_setsrid(st_makepoint(-87.6533, 41.9389), 4326)::geography,
    '2024-08-30T12:00:00Z'
),
(
    '1B7A66CF-5A2E-40B2-8D73-7D1AB2C4E304',
    'Demo Unknown Air - Evanston',
    '1700 Sherman Ave',
    'Evanston',
    'IL',
    '60201',
    'Demo seed entry with unknown pricing.',
    'unknown',
    'demo-seed',
    st_setsrid(st_makepoint(-87.6940, 42.0462), 4326)::geography,
    '2024-08-30T12:00:00Z'
),
(
    'A0C0E28E-5F73-4A69-8C6E-10B176D2A505',
    'Demo Free Air - Oak Park',
    '714 Lake St',
    'Oak Park',
    'IL',
    '60301',
    'Demo seed entry west of the city.',
    'free',
    'demo-seed',
    st_setsrid(st_makepoint(-87.7885, 41.8889), 4326)::geography,
    '2024-08-30T12:00:00Z'
);

