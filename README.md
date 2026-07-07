# AirFinder

AirFinder is a native iPhone app for finding places where you can fill car tires with air, with a focus on free locations first.

## What is implemented

- SwiftUI app shell with MapKit-based map browsing
- Free, paid, and unknown pricing badges
- Search across name, address, city, state, postal code, notes, and source
- Anonymous submission flow with pending moderation
- Local demo seed data when Supabase is not configured
- Supabase/PostGIS schema and RPC functions for production data
- Unit tests for pricing labels, validation, duplicate detection, and search behavior

## Project file

- Open `AirFinder.xcodeproj` in Xcode 15 or later.
- The app target uses `AirFinder/Info.plist` and bundles demo seed data from `AirFinder/Resources/SeedLocations.json`.

## Backend setup

1. Apply the SQL in `supabase/migrations/0001_airfinder_schema.sql`.
2. Seed starter data with `supabase/seed.sql`.
3. In the iOS app target Info.plist, set:
   - `SupabaseURL`
   - `SupabaseAnonKey`
4. Keep the location permission string in `AirFinder/Info.plist` or the equivalent app target plist:
   - `NSLocationWhenInUseUsageDescription`

## App behavior

- If Supabase is configured, the app queries `rest/v1/rpc/search_locations` and submits anonymous suggestions through `rest/v1/rpc/submit_location`.
- If Supabase is not configured, the app falls back to bundled demo data in `AirFinder/Resources/SeedLocations.json`.

## Notes

- The app is scoped to iOS 17+.
- The first release intentionally avoids accounts, favorites, and Android support.
- Demo locations are clearly marked and should be replaced with verified listings before release.
