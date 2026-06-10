# Clean Pro — Architecture Diagrams

## 1. Context Diagram

```mermaid
C4Context
  title Clean Pro — System Context

  Person(user, "Smartphone User", "iPhone or Android owner running low on storage")
  Person(admin, "Support Agent", "Handles subscription issues and refunds")

  System(cleanpro_mobile, "Clean Pro Mobile App", "Flutter app — on-device AI photo duplicate detection and cleanup")
  System(cleanpro_backend, "Clean Pro Backend", "ASP.NET Core API — user profile and subscription entitlement")

  System_Ext(app_store, "App Store / Google Play", "Apple IAP and Google Play Billing — subscription payments")
  System_Ext(revenuecat, "RevenueCat", "Subscription entitlement management and webhook delivery")
  System_Ext(cognito, "AWS Cognito", "User authentication and JWT issuance")
  System_Ext(photo_library, "Device Photo Library", "iOS PHPhotoLibrary / Android MediaStore — local photos only")

  Rel(user, cleanpro_mobile, "Scans, reviews, and deletes duplicate photos")
  Rel(user, app_store, "Pays for subscription via native IAP")
  Rel(admin, cleanpro_backend, "Manages user subscriptions via admin API")

  Rel(cleanpro_mobile, photo_library, "Reads photo metadata and thumbnails — on-device only, never uploaded")
  Rel(cleanpro_mobile, cognito, "Authenticates user — gets JWT")
  Rel(cleanpro_mobile, cleanpro_backend, "Checks entitlement, syncs user profile — HTTPS/TLS")
  Rel(cleanpro_mobile, revenuecat, "Validates and restores subscription entitlement")
  Rel(app_store, revenuecat, "Sends server-to-server purchase notifications")
  Rel(revenuecat, cleanpro_backend, "Delivers subscription lifecycle webhooks")
```

## 2. System Architecture Diagram

```mermaid
graph TB
  subgraph Mobile["Mobile App (Flutter)"]
    direction TB
    UI[Presentation Layer<br/>Pages + Widgets + BLoC]
    APP_M[Application Layer<br/>Use Cases + Commands]
    DOM_M[Domain Layer<br/>Entities + Interfaces]
    INFRA_M[Infrastructure Layer<br/>Photo Manager + TFLite + RevenueCat]
    AI[On-Device AI<br/>pHash Engine + TFLite MobileNetV3]
    PHOTO[Photo Library<br/>iOS PHPhotoLibrary / Android MediaStore]

    UI --> APP_M --> DOM_M
    INFRA_M --> DOM_M
    INFRA_M --> AI
    INFRA_M --> PHOTO
  end

  subgraph Backend["Backend (AWS)"]
    direction TB
    APIGW[API Gateway<br/>REST API]
    subgraph Lambdas["Lambda Functions"]
      L1[UserProfile<br/>Function]
      L2[Entitlement<br/>Function]
      L3[Subscription<br/>Webhook Function]
    end
    DDB[(DynamoDB<br/>Single Table)]
    CW[CloudWatch<br/>Logs + Metrics + Alarms]
    XRAY[X-Ray Tracing]

    APIGW --> L1 & L2 & L3
    L1 & L2 & L3 --> DDB
    L1 & L2 & L3 --> CW
    L1 & L2 & L3 --> XRAY
  end

  subgraph Auth["Auth (AWS Cognito)"]
    UP[User Pool]
    AC[App Client]
    UP --> AC
  end

  subgraph Subscriptions["Subscriptions"]
    RC[RevenueCat]
    IAP[App Store IAP /<br/>Google Play Billing]
    RC --> IAP
  end

  Mobile -->|JWT + HTTPS| APIGW
  Mobile -->|Auth| Auth
  Mobile -->|Entitlement SDK| RC
  RC -->|Webhook HTTPS| APIGW
```

## 3. Component Diagram — Mobile

```mermaid
graph LR
  subgraph Features
    ONB[Onboarding\nPermissionFlow]
    SCAN[Scan\nScanBloc\nPhotoScannerRepo\nDuplicateDetector]
    REVIEW[Review\nReviewBloc\nGroupRepo]
    SUB[Subscription\nSubscriptionBloc\nRevenueCatService]
    RES[Results\nResultsBloc]
  end

  subgraph Core
    DI[DI - GetIt]
    ROUTER[Router - GoRouter]
    THEME[Theme]
  end

  subgraph Shared
    WIDGETS[Shared Widgets]
    UTILS[Utilities]
  end

  subgraph Infrastructure
    PHOTO_MGR[photo_manager]
    TFLITE[tflite_flutter]
    PHASH[pHash Engine - Dart]
    RC_SDK[purchases_flutter<br/>RevenueCat SDK]
    COGNITO_SDK[amazon_cognito_identity_dart_2]
    HTTP_CLIENT[Dio HTTP Client]
  end

  SCAN --> PHOTO_MGR
  SCAN --> TFLITE
  SCAN --> PHASH
  SUB --> RC_SDK
  Features --> DI
  Features --> ROUTER
  Features --> WIDGETS
```

## 4. Sequence Diagram — Photo Scan & Delete Flow

```mermaid
sequenceDiagram
  actor User
  participant App as Flutter App
  participant PLib as Photo Library
  participant AI as On-Device AI<br/>(pHash + TFLite)
  participant RevCat as RevenueCat SDK
  participant Backend as Clean Pro API

  User->>App: Tap "Start Scan"
  App->>RevCat: checkEntitlement()
  RevCat-->>App: Entitlement(status=Active|Trial)
  alt No valid entitlement
    App-->>User: Show Paywall
  else Valid entitlement
    App->>PLib: fetchAllAssets(type=image)
    PLib-->>App: Stream<AssetEntity>[]
    loop For each photo batch (100 at a time)
      App->>AI: computePHash(imageData)
      AI-->>App: PHash value
      App->>AI: computeEmbedding(imageData) [optional, for near-dups]
      AI-->>App: float32[128] embedding vector
    end
    App->>App: clusterByHammingDistance(threshold=10)
    App->>App: rankByQuality(resolution, recency)
    App-->>User: Show results: N groups, X GB
    User->>App: Review groups, confirm keeps
    User->>App: Tap "Clean Now"
    App-->>User: Confirmation dialog (N photos, X GB, goes to Trash)
    User->>App: Confirm
    loop For each photo to delete
      App->>PLib: deleteAssets([assetId])
      PLib-->>App: success (moved to Trash)
    end
    App-->>User: Results screen: X GB reclaimed
    App->>Backend: POST /scans (aggregate stats only — no photo data)
    Backend-->>App: 201 Created
  end
```

## 5. Sequence Diagram — Subscription Purchase Flow

```mermaid
sequenceDiagram
  actor User
  participant App as Flutter App
  participant RevCat as RevenueCat SDK
  participant Store as App Store / Google Play
  participant Backend as Clean Pro API
  participant DDB as DynamoDB

  User->>App: Tap "Subscribe Annual $17.99"
  App->>RevCat: purchasePackage(annual)
  RevCat->>Store: initiatePurchase()
  Store-->>User: Native payment sheet
  User->>Store: Authenticate + Confirm
  Store-->>RevCat: Purchase receipt
  RevCat->>RevCat: Validate receipt server-side
  RevCat-->>App: CustomerInfo(entitlement=active, expiry=+365d)
  App-->>User: Unlock full app access
  
  Note over RevCat,Backend: Async webhook (≤30s)
  RevCat->>Backend: POST /webhooks/revenuecat (RENEWAL / INITIAL_PURCHASE)
  Backend->>Backend: Verify webhook HMAC signature
  Backend->>DDB: UpdateSubscription(userId, tier=Annual, expiry, status=Active)
  DDB-->>Backend: OK
  Backend-->>RevCat: 200 OK
```

## 6. Deployment Diagram

```mermaid
graph TB
  subgraph Device["User Device"]
    APP[Clean Pro Flutter App<br/>iOS / Android]
    PHOTO_LIB[Photo Library<br/>On-Device]
    AI_MODEL[TFLite Model<br/>Bundled in App]
    APP --> PHOTO_LIB
    APP --> AI_MODEL
  end

  subgraph AWS["AWS ap-southeast-1"]
    subgraph VPC["VPC (Private Subnets)"]
      direction LR
      APIGW[API Gateway<br/>REST API]
      subgraph Lambda["Lambda Functions"]
        L_UP[UserProfile<br/>512MB / 30s]
        L_ENT[Entitlement<br/>256MB / 15s]
        L_WH[WebhookProcessor<br/>256MB / 30s]
      end
    end

    subgraph Data["Data Layer"]
      DDB[(DynamoDB<br/>PAY_PER_REQUEST<br/>SSE-KMS)]
      SM[Secrets Manager<br/>RevenueCat HMAC key<br/>Cognito secrets]
    end

    subgraph Auth["Auth"]
      COGNITO[Cognito User Pool<br/>JWT RS256]
    end

    subgraph Observability["Observability"]
      CW[CloudWatch<br/>Logs / Metrics]
      XRAY[X-Ray Tracing]
      CW_ALARM[CloudWatch Alarms<br/>SNS → PagerDuty]
    end
  end

  subgraph External["External Services"]
    REVENUECAT[RevenueCat<br/>Subscription SaaS]
    APP_STORE[App Store /<br/>Google Play]
  end

  APP -->|HTTPS TLS 1.3| APIGW
  APP -->|Cognito SDK| COGNITO
  APP -->|RevenueCat SDK| REVENUECAT
  REVENUECAT -->|Webhook HTTPS| APIGW
  REVENUECAT --> APP_STORE
  APIGW --> L_UP & L_ENT & L_WH
  L_UP & L_ENT & L_WH --> DDB
  L_UP & L_ENT & L_WH --> SM
  L_UP & L_ENT & L_WH --> CW & XRAY
  CW --> CW_ALARM
```

## 7. Security Architecture Diagram

```mermaid
graph TB
  subgraph Trust_Boundary_Device["Trust Boundary: User Device (Trusted)"]
    APP[Flutter App]
    PHOTO[Photo Library — never leaves this boundary]
    AI[On-Device AI Model]
  end

  subgraph Trust_Boundary_Internet["Trust Boundary: Internet (Untrusted)"]
    REQUEST[HTTPS Request<br/>JWT Bearer Token]
  end

  subgraph Trust_Boundary_AWS["Trust Boundary: AWS (Backend)"]
    subgraph Auth_Layer["Authentication Layer"]
      APIGW_AUTH[API Gateway<br/>Cognito Authorizer]
      JWT_VAL[JWT Validator<br/>RS256, exp check]
    end
    subgraph App_Layer["Application Layer"]
      LAMBDA[Lambda Function<br/>RBAC Policy Check]
    end
    subgraph Data_Layer["Data Layer"]
      DDB[DynamoDB<br/>CMK Encryption at Rest]
      SM_KMS[Secrets Manager<br/>KMS-encrypted]
    end
    subgraph Audit["Audit Trail"]
      CW_LOGS[CloudWatch Logs<br/>Structured JSON<br/>No PII in log messages]
    end
  end

  APP -->|TLS 1.3 — no downgrade| REQUEST
  REQUEST -->|Bearer JWT| APIGW_AUTH
  APIGW_AUTH --> JWT_VAL
  JWT_VAL -->|sub + cognito:groups claims| LAMBDA
  LAMBDA -->|Least-privilege IAM role| DDB
  LAMBDA -->|GetSecretValue| SM_KMS
  LAMBDA --> CW_LOGS
  PHOTO -.->|NEVER crosses this boundary| Trust_Boundary_Internet
```

## 8. Data Flow Diagram

```mermaid
flowchart LR
  subgraph Device["On-Device (Private — no egress)"]
    PL[(Photo Library<br/>iOS / Android)]
    APP_DL[Photo Manager<br/>Fetch assets]
    AI_DL[pHash + TFLite<br/>Compute fingerprints]
    GROUPS[Duplicate Groups<br/>In-memory only]
    TRASH[Device Trash<br/>Recoverable 30d]
    PREFS[Local Prefs<br/>Scan history, trial start date]

    PL --> APP_DL
    APP_DL --> AI_DL
    AI_DL --> GROUPS
    GROUPS --> TRASH
    GROUPS --> PREFS
  end

  subgraph Backend_Flow["Backend (Aggregate Stats Only)"]
    API_IN[POST /scans<br/>photos_scanned:int<br/>duplicates_found:int<br/>bytes_reclaimed:int<br/>NO photo data]
    DDB_SCAN[(DynamoDB<br/>scan_stats record)]
    API_IN --> DDB_SCAN
  end

  subgraph Auth_Flow["Auth Flow"]
    COGNITO_AUTH[Cognito<br/>Email + Password]
    JWT_TOKEN[JWT Bearer Token<br/>sub = userId]
    COGNITO_AUTH --> JWT_TOKEN
  end

  subgraph Sub_Flow["Subscription Flow"]
    RC[RevenueCat<br/>Entitlement Check]
    IAP_RECEIPT[App Store / Play<br/>Receipt]
    DDB_SUB[(DynamoDB<br/>subscription record)]
    RC --> IAP_RECEIPT
    RC -->|Webhook| DDB_SUB
  end

  GROUPS -->|Aggregate stats only| API_IN
  JWT_TOKEN -->|Authenticates| API_IN
  JWT_TOKEN -->|Authenticates| Sub_Flow
```
