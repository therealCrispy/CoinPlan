# CoinPlan — iOS Native Migration Brief

> Feed this entire file to Claude Code on the Mac. It contains everything needed to build the native SwiftUI version of CoinPlan from scratch. The UI will be redesigned, so do NOT try to replicate the web CSS — port the logic and data exactly, design the UI fresh in SwiftUI.

## 1. What CoinPlan is

A personal budgeting app for one user (Brody). Core concept: **weekly budgeting** — paychecks are logged per week, bills reserve money out of the week, transactions spend from it, and the headline number is "Available This Week". Weeks run **Monday → Sunday**.

Current version is a single-file web PWA hosted at https://therealcrispy.github.io/CoinPlan (repo: therealCrispy/CoinPlan). Keep it untouched; the iOS app is a separate project.

## 2. Project setup

- Xcode → New Project → iOS App, name `CoinPlan`, SwiftUI, **SwiftData** storage
- Bundle ID: `com.brody.coinplan`
- Min target: iOS 17+ (or 26 if available and the device supports it — user wants Liquid Glass eventually)
- Free Apple ID signing, run on device via cable
- New git repo `coinplan-ios`

## 3. Data models (port exactly)

```
Transaction: id, amount (Double), merchant (String), category (String), date (Date, day precision), note (String)
IncomeEntry: id, amount (Double), note (String), date (Date)
Bill: id, name (String), amount (Double),
      frequency (enum: monthly | weekly | biweekly),
      dueDay (Int 1–31, only meaningful for monthly),
      category (String), active (Bool), spread (Bool)
```

Categories (fixed list, id + label + emoji icon):
```
groceries 🛒, dining 🍔, gas ⛽, shopping 🛍️, entertainment 🎮,
health 💊, pet 🐾, bills 📄, other 💸
```
Income entries display with 💵 and green; expenses red.

## 4. Business logic (port exactly — this is the heart of the app)

### Week summary (dashboard headline)
For the current Mon–Sun week:
- `earned` = sum of income entries dated in the week
- `spent` = sum of transactions dated in the week
- `reserved` = weekly bill reservation (below)
- `available` = earned − reserved − spent

### Weekly bill reservation rules
For each **active** bill:
- `weekly` → reserve full amount every week
- `biweekly` → reserve amount / 2 every week
- `monthly` with `spread == true` → reserve amount / 4.33 every week
- `monthly` with `spread == false` → reserve the full amount ONLY in the week containing its dueDay; otherwise 0

### "Due this week" list (dashboard)
Show weekly + biweekly bills always; monthly spread bills always (labelled "Reserving $X/wk toward $Y/mo"); monthly non-spread only if dueDay falls in the current week.

### Bill occurrences for a calendar month (`getBillsForMonth(year, month)`)
- `monthly` → one hit on min(dueDay, daysInMonth)
- `weekly` → a hit on **every Monday** of the month
- `biweekly` → first Monday of the month, then every 14 days within the month
Returns list of (bill, dayOfMonth).

### Monthly totals (dashboard "This Month" card)
- transactions total = sum of transactions in current calendar month
- bills total = sum of amounts of all occurrences from getBillsForMonth for current month
- grand total = both added

### Bills tab monthly total
Sum over active bills: weekly × 4.33, biweekly × 2.17, monthly × 1.

## 5. Screens (current feature set — redesign freely)

1. **Dashboard** — hero "Available This Week" (green normal / yellow when < 20% of earned / red negative), Earned/Reserved/Spent stats, progress bar of (reserved+spent)/earned, This Month card (transactions + bills + total), 5 most recent transactions, bills due this week.
2. **Transactions (history)** — all transactions + income merged, grouped by week (Mon–Sun headers), each week shows In / Out / Net totals. Tap to delete (confirm).
3. **Budget / Bills** — month-view calendar with colored dots per bill category on due days, arrows to change month, tap a day → list of that day's bills with amounts. Below: bill list (monthly section, weekly/biweekly section), tap to edit. Monthly total card. Add-bill form: name, amount, frequency, due day, spread toggle, category.
4. **Add flows** — Add Transaction (amount, merchant, category picker, date, note), Log Paycheck (amount, note, date), Scan Receipt (below).
5. Tab bar had: Dashboard | Transactions | center + Add button | Budget | More. "Accounts" and "Cash Flow" were Work-in-Progress placeholders — optional.
6. **Settings** — Clear All Data (confirm), version label.

## 6. Receipt scanning (keep the backend as-is)

POST to the existing Cloudflare Worker — do NOT put any AI API keys in the app:

```
URL:  https://coinplan-receipt.coinplan-brody.workers.dev
Body: JSON { "image": "<base64 JPEG, no data: prefix>" }
Resp: JSON { "merchant": String?, "amount": Double?, "date": "YYYY-MM-DD"?, "category": String? }
      or { "error": ... }
```

Flow: user takes photo / picks from library (PhotosPicker + camera), send full-quality JPEG base64 (do NOT compress — quality matters for reading receipts), show spinner, then a confirm card (merchant/amount/date/category) with "Save" and "Edit before saving". Fallbacks: date → today, category → "other". The worker uses a free OpenRouter vision model; it is slow-ish (several seconds) — design for that.

## 7. Supabase (phase 2, don't block on it)

User has an existing Supabase project (used by his MealPlan app). Later, add the Supabase Swift SDK for cross-device sync of transactions/income/bills. Start local-only with SwiftData; architect the storage layer so a sync backend can be added without rewriting views (e.g., repository pattern).

## 8. Design direction

The web app currently uses a Monarch Money-inspired look: warm cream background #F5F0EB, orange accent #E8622A, white cards with 16px radius and soft shadows, teal #3DAB8E / green #2E9B5F / red #D94F3D accents, dark navy gradient hero card. Use this as the palette starting point but build it natively — SF Symbols, native materials (`.ultraThinMaterial`), spring animations, haptics, native swipe-to-delete, sheets for add/edit forms. User cares about it feeling like a real iOS app.

## 9. Build order (suggested)

1. Scaffold + models + seed nothing (start empty, no fake data)
2. Dashboard with week math
3. Add transaction / log paycheck sheets
4. Transactions history grouped by week
5. Bills CRUD + weekly reservation logic
6. Bill calendar month view
7. Receipt scan (camera + worker call + confirm sheet)
8. Settings / polish / haptics
9. (Later) Supabase sync

## 10. Conventions

- Weeks are Monday-based everywhere. Careful: Swift `Calendar` weeks default to Sunday in the US locale — set `firstWeekday = 2` or compute Monday manually.
- Money displays with `$` and drops trailing `.00` (e.g. `$48`, `$13.50`).
- The user pushes versions frequently and likes visible version numbers in the UI.
