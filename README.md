# Brunello 🐾

A shared diary for two pet parents. Each parent taps what the pet did (food, poo, pee, a walk, a health note, a photo) and the other parent gets a notification written in the pet's own voice: *"Mama, I made a good poo! 💩✨"*. It also keeps track of what each parent spends on the pet and who owes whom.

There is no chat, on purpose. The app only carries the pet's updates.

## What is in this repository

| Folder | What it is |
| --- | --- |
| `Brunello/` | The iOS app (SwiftUI, iOS 17+) |
| `Brunello.xcodeproj/` | The Xcode project; open this to run the app |
| `supabase/migrations/` | The database: tables, access rules, invite codes, expenses |
| `supabase/functions/notify-parent/` | The server function that sends the push notification |
| `simulation/` | A clickable two-phone demo of the app that runs in a browser |
| `tests/` | Backend checks that run on Linux with Docker |

## How the app works

- **Two parents, one pet.** The first parent adds the pet and gets a six-character invite code. The second parent joins with that code. After that the code stops working, so nobody else can get in.
- **Name and nickname.** Each parent has a name (shown to the other parent in the diary) and a nickname (what the pet calls them in notifications).
- **Two taps to log.** Tap a kind, tap how it went. The entry lands in both diaries and the other parent is notified.
- **Day by day.** The Today tab counts meals, poos, pees and walks for the day and lets you step back through earlier days.
- **Photos.** Photos go into the diary and into a shared album.
- **Money.** Either parent adds an expense (amount and category) and chooses how it is shared: half each, the other parent pays it all, not shared, or any other amount. The Money tab shows who owes whom, and the parent who owes can record paying it back.
- **Dogs and cats.** Cats get a Play button where dogs have Walk.

## Running the app

You need a Mac with Xcode 16.3 or newer. The app is already connected to its Supabase project (`Brunello/App/AppConfig.swift`), where the database and the notification function are installed.

1. **One switch in Supabase.** Open the project in the Supabase dashboard, go to **Authentication > Sign In / Providers** and turn on **Allow anonymous sign-ins**. The app signs each phone in silently; who gets in is decided by the invite code.
2. **Run it.** Open `Brunello.xcodeproj`, select the Brunello target, open **Signing & Capabilities** and choose your team. Pick an iPhone simulator or your phone and press Run.

### Notifications

1. In the Apple Developer site, open **Certificates, Identifiers & Profiles > Keys**, create a key with **Apple Push Notifications service (APNs)** enabled and download the `.p8` file. Note its Key ID and your Team ID.
2. In the Supabase dashboard, open **Edge Functions > Secrets** and add four secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` (the app's bundle identifier, `com.bilgaaaaa.brunello` unless you change it) and `APNS_PRIVATE_KEY` (the full text of the `.p8` file).

Until those secrets are set the app works normally, just without notifications.

### Sharing it through TestFlight

1. In Xcode choose **Product > Archive**, then **Distribute App > TestFlight & App Store**.
2. In App Store Connect, open the app's **TestFlight** tab and add the other parent as a tester with their Apple ID email.
3. Both parents install the app from the TestFlight app. The first one adds the pet and sends the invite code; the second one joins with it.

### Using your own Supabase project

Run `supabase/migrations/20261125000000_brunello_schema.sql` in the project's SQL editor, deploy the function with `supabase functions deploy notify-parent --no-verify-jwt` (the function checks the caller's session itself), turn on anonymous sign-ins, and put the project's URL and publishable key in `Brunello/App/AppConfig.swift`.

## Naming used everywhere

The app, the database, the server function and the simulation use the same words:

| Word | Meaning |
| --- | --- |
| `pet` | The dog or cat |
| `parent` | One of the two people; has a `name` and a `nickname` |
| `entry` | One diary line; has a `kind` and a `detail` |
| `kind` | `food`, `poo`, `pee`, `walk`, `play`, `health`, `photo` |
| `detail` | How it went, for example `good`, `half`, `long` |
| `voiceLine` | The sentence the pet says for an entry |
| `expense` | Money a parent spent on the pet; has a `category`, `amountCents` and `owedCents` (the part the other parent owes the payer) |
| `category` | `food`, `vet`, `medicine`, `grooming`, `toys`, `other`, or `settle_up` for paying the other parent back |

The pet's sentences live in two places that must stay in step: `Brunello/Models/EntryKind.swift` (diary) and `supabase/functions/notify-parent/petVoice.ts` (notifications, including the ones about money).

## Checks

- **iOS build** (`.github/workflows/ios-build.yml`) compiles the app with Xcode on every change.
- **Backend checks** (`.github/workflows/backend-checks.yml`) run `tests/run.sh`: the database access rules are tried by three people (two parents and a stranger), then the app's real data code runs end to end against a local stand-in for Supabase, including the notification function with a fake Apple server.
