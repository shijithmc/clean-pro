# DynamoDB Single-Table Design — Clean Pro

## Table Name: `CleanPro`

## Access Patterns

| # | Pattern | PK | SK | GSI |
|---|---------|----|----|-----|
| AP-01 | Get user profile by userId | `USER#<userId>` | `PROFILE` | — |
| AP-02 | Get subscription by userId | `USER#<userId>` | `SUB#CURRENT` | — |
| AP-03 | Get subscription by RevenueCat subscriberId | — | — | GSI1: `RC#<rcSubscriberId>` |
| AP-04 | List all active subscriptions (admin/analytics) | — | — | GSI2: `STATUS#ACTIVE` |
| AP-05 | Get scan stats for user | `USER#<userId>` | `SCAN#<timestamp>` | — |
| AP-06 | Get latest N scans for user | `USER#<userId>` | `SCAN#` begins_with | — |
| AP-07 | Get webhook event by idempotency key | `WEBHOOK#<eventId>` | `EVENT` | — |

## Key Design

```
Table: CleanPro
PK: String (partition key)
SK: String (sort key)
TTL: Number (epoch seconds — used for webhook idempotency expiry)

GSI1: gsi1Pk (partition key) + gsi1Sk (sort key)  [RevenueCat subscriber lookup]
GSI2: gsi2Pk (partition key) + gsi2Sk (sort key)  [Status-based queries for admin]
```

## Entity Schema

### UserProfile Record
```
PK: USER#<cognito-sub-uuid>
SK: PROFILE
entityType: "UserProfile"
userId: String (Cognito sub)
email: String (encrypted)
createdAt: ISO-8601
updatedAt: ISO-8601
trialStartedAt: ISO-8601 | null
trialEndsAt: ISO-8601 | null
totalPhotosScanned: Number
totalBytesReclaimed: Number
lastScanAt: ISO-8601 | null
```

### Subscription Record
```
PK: USER#<cognito-sub-uuid>
SK: SUB#CURRENT
entityType: "Subscription"
userId: String
rcSubscriberId: String  (RevenueCat subscriber ID)
tier: "FREE_TRIAL" | "MONTHLY" | "ANNUAL"
status: "ACTIVE" | "EXPIRED" | "CANCELLED" | "GRACE_PERIOD"
currentPeriodStart: ISO-8601
currentPeriodEnd: ISO-8601
autoRenew: Boolean
platform: "IOS" | "ANDROID"
gsi1Pk: "RC#<rcSubscriberId>"
gsi1Sk: "SUB#CURRENT"
gsi2Pk: "STATUS#<status>"
gsi2Sk: "USER#<userId>"
createdAt: ISO-8601
updatedAt: ISO-8601
```

### ScanStats Record
```
PK: USER#<cognito-sub-uuid>
SK: SCAN#<ISO-8601-timestamp>
entityType: "ScanStats"
userId: String
photosScanned: Number
duplicateGroupsFound: Number
photosDeleted: Number
bytesReclaimed: Number
scanDurationSeconds: Number
platform: "IOS" | "ANDROID"
appVersion: String
createdAt: ISO-8601
```

### WebhookEvent Record (idempotency key)
```
PK: WEBHOOK#<revenuecat-event-id>
SK: EVENT
entityType: "WebhookEvent"
eventId: String
eventType: String  (e.g. "INITIAL_PURCHASE", "RENEWAL", "CANCELLATION")
processedAt: ISO-8601
userId: String
TTL: Number  (epoch + 7 days — auto-expire idempotency keys)
```

## Query Patterns

```
Pattern AP-01: Get user profile
  PK = USER#abc-123-def
  SK = PROFILE
  Returns: UserProfile (1 item)

Pattern AP-02: Get current subscription
  PK = USER#abc-123-def
  SK = SUB#CURRENT
  Returns: Subscription (1 item)

Pattern AP-03: Lookup by RevenueCat subscriber ID
  GSI1: gsi1Pk = RC#rc_subscriber_xyz
  Returns: Subscription (1 item)

Pattern AP-04: List active subscriptions (admin)
  GSI2: gsi2Pk = STATUS#ACTIVE
  Returns: List<Subscription>

Pattern AP-05: Get scan stats range (last 30 scans)
  PK = USER#abc-123-def
  SK begins_with SCAN#
  ScanIndexForward = false, Limit = 30
  Returns: List<ScanStats>

Pattern AP-07: Idempotency check for webhook
  PK = WEBHOOK#evt_revenuecat_12345
  SK = EVENT
  Returns: WebhookEvent | null (if TTL expired, item gone)
```

## Sample Records

### Record 1 — UserProfile
```json
{
  "PK": "USER#a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "SK": "PROFILE",
  "entityType": "UserProfile",
  "userId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "email": "AES256(user@example.com)",
  "createdAt": "2026-01-15T10:30:00Z",
  "updatedAt": "2026-06-10T08:15:00Z",
  "trialStartedAt": "2026-01-15T10:30:00Z",
  "trialEndsAt": "2026-01-22T10:30:00Z",
  "totalPhotosScanned": 12450,
  "totalBytesReclaimed": 3145728000,
  "lastScanAt": "2026-06-10T08:12:00Z"
}
```

### Record 2 — Active Annual Subscription
```json
{
  "PK": "USER#a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "SK": "SUB#CURRENT",
  "entityType": "Subscription",
  "userId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "rcSubscriberId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "tier": "ANNUAL",
  "status": "ACTIVE",
  "currentPeriodStart": "2026-01-22T10:30:00Z",
  "currentPeriodEnd": "2027-01-22T10:30:00Z",
  "autoRenew": true,
  "platform": "IOS",
  "gsi1Pk": "RC#a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "gsi1Sk": "SUB#CURRENT",
  "gsi2Pk": "STATUS#ACTIVE",
  "gsi2Sk": "USER#a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "createdAt": "2026-01-22T10:30:00Z",
  "updatedAt": "2026-06-10T00:00:00Z"
}
```

### Record 3 — ScanStats
```json
{
  "PK": "USER#a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "SK": "SCAN#2026-06-10T08:12:00Z",
  "entityType": "ScanStats",
  "userId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "photosScanned": 5240,
  "duplicateGroupsFound": 847,
  "photosDeleted": 834,
  "bytesReclaimed": 1073741824,
  "scanDurationSeconds": 47,
  "platform": "IOS",
  "appVersion": "1.0.0",
  "createdAt": "2026-06-10T08:12:00Z"
}
```

### Record 4 — Free Trial UserProfile
```json
{
  "PK": "USER#b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "SK": "PROFILE",
  "entityType": "UserProfile",
  "userId": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "email": "AES256(newuser@gmail.com)",
  "createdAt": "2026-06-08T14:22:00Z",
  "updatedAt": "2026-06-08T14:22:00Z",
  "trialStartedAt": "2026-06-08T14:22:00Z",
  "trialEndsAt": "2026-06-15T14:22:00Z",
  "totalPhotosScanned": 0,
  "totalBytesReclaimed": 0,
  "lastScanAt": null
}
```

### Record 5 — WebhookEvent (idempotency)
```json
{
  "PK": "WEBHOOK#evt_rc_initial_purchase_20260110_xyz",
  "SK": "EVENT",
  "entityType": "WebhookEvent",
  "eventId": "evt_rc_initial_purchase_20260110_xyz",
  "eventType": "INITIAL_PURCHASE",
  "processedAt": "2026-01-22T10:30:05Z",
  "userId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "TTL": 1753574405
}
```

## Capacity Estimate

| Operation | Frequency | Read/Write Capacity |
|-----------|----------|---------------------|
| Profile read (app launch) | 100k/day | ~1.2 RCU/s |
| Subscription check (per scan) | 50k/day | ~0.6 RCU/s |
| Webhook write | 10k/day | ~0.1 WCU/s |
| Scan stats write | 50k/day | ~0.6 WCU/s |

**Billing mode: PAY_PER_REQUEST** — appropriate for current scale, switch to PROVISIONED at 500k+ daily requests.
