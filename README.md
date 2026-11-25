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

## How the app works

- **Two parents, one pet.** The first parent adds the pet and gets a six-character invite code. The second parent joins with that code. After that the code stops working, so nobody else can get in.
- **Name and nickname.** Each parent has a name (shown to the other parent in the diary) and a nickname (what the pet calls them in notifications).
- **Two taps to log.** Tap a kind, tap how it went. The entry lands in both diaries and the other parent is notified.
- **Day by day.** The Today tab counts meals, poos, pees and walks for the day and lets you step back through earlier days.
- **Photos.** Photos go into the diary and into a shared album.
- **Money.** Either parent adds an expense (amount and category). Every expense is shared half and half, the Money tab shows who owes whom, and the parent who owes can record paying it back.
- **Dogs and cats.** Cats get a Play button where dogs have Walk.

## Running the app

You need a Mac with Xcode 16.3 or newer.

1. Create a Supabase project and run `supabase/migrations/20261125000000_brunello_schema.sql` in its SQL editor.
2. In Supabase, open **Authentication > Sign In / Providers** and turn on **Allow anonymous sign-ins**. The app signs each phone in silently; access is controlled by the invite code.
3. Deploy the function in `supabase/functions/notify-parent/`.
4. Paste your project URL and anon key into `Brunello/App/AppConfig.swift`.
5. Open `Brunello.xcodeproj`, pick an iPhone simulator and press Run.

### Notifications on real phones

Push notifications and installing on two phones need the paid Apple Developer Program.

1. In Xcode, select the Brunello target, open **Signing & Capabilities**, choose your team and change the bundle identifier to one of your own.
2. In the Apple Developer site, create an **APNs key** (.p8 file) and note its Key ID and your Team ID.
3. Add four secrets to the Supabase function: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` and `APNS_PRIVATE_KEY` (the full text of the .p8 file).
4. Send the app to the other parent with TestFlight.

Until those secrets are set the app works normally, just without notifications.

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
| `expense` | Money a parent spent on the pet; has a `category` and `amountCents` |
| `category` | `food`, `vet`, `medicine`, `grooming`, `toys`, `other`, or `settle_up` for paying the other parent back |

The pet's sentences live in two places that must stay in step: `Brunello/Models/EntryKind.swift` (diary) and `supabase/functions/notify-parent/petVoice.ts` (notifications, including the ones about money).
