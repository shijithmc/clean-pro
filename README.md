# Clean Pro — AI Smart Photo Cleaner

AI-powered duplicate photo cleaner for iOS and Android. Finds and removes duplicate, near-duplicate, and junk photos to reclaim device storage — all processing happens on-device, zero photos uploaded.

## Architecture

```
mobile/          Flutter app (iOS + Android)
backend/         ASP.NET Core 9 — subscription/user account API
infrastructure/  AWS CDK (C#) — Lambda, DynamoDB, Cognito, API Gateway
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter 3.27 / Dart 3.6 |
| On-device AI | TFLite (Android) + Core ML (iOS) |
| Backend | ASP.NET Core 9 (C#) |
| Cloud | AWS (ap-southeast-1) |
| IaC | AWS CDK (C#) |
| Database | DynamoDB (single-table) |
| Auth | AWS Cognito |
| Subscriptions | RevenueCat SDK |
| CI/CD | GitHub Actions |

## Privacy

All photo analysis runs on-device. No photos, thumbnails, or metadata are ever transmitted to any server. App Store privacy label: **No Data Collected**.

## Subscription

- 7-day free trial (no credit card required)
- Monthly: $2.99/month
- Annual: $17.99/year (save 50%)

## Development

```bash
# Mobile
cd mobile && flutter pub get && flutter run

# Backend
cd backend && dotnet restore && dotnet run --project src/Api

# Infrastructure
cd infrastructure && dotnet restore && cdk synth
```

## Issues / PBI

[GitHub Issues](https://github.com/shijithmc/clean-pro/issues)
