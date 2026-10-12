# Shutter Manager 1.0 in App Store Connect

What to enter for version 1.0.0. The text fields live in the `.txt` files next to this one, so
they can be pasted as they are; `Tools/ci/check_conventions.py` fails if one passes App Store
Connect's length limit.

## Text

| Field | File | Limit |
|---|---|---|
| Name | `name.txt` | 30 |
| Subtitle | `subtitle.txt` | 30 |
| Promotional text | `promotional_text.txt` | 170 |
| Keywords | `keywords.txt` | 100 |
| Description | `description.txt` | 4000 |
| What's New | `whats_new.txt` | 4000 |
| App Review notes | `review_notes.txt` | 4000 |

Keywords leave out the words already in the name and subtitle, which App Store search uses anyway.

## App information

| Question | Answer |
|---|---|
| Primary category | Photo & Video (matches `LSApplicationCategoryType`) |
| Secondary category | Utilities |
| Price | Free |
| Age rating | 4+: answer "None" or "No" to every question. Marketplace searches open in Safari, so there is no in-app web browsing. |
| Content rights | The app shows product details from UPCitemdb after a barcode scan. Answer as your agreement with UPCitemdb allows. |
| Sign-in required | No. Leave the demo account empty. |
| Export compliance | No non-exempt encryption (`ITSAppUsesNonExemptEncryption` is `NO`). |
| Copyright | 2026 Furey Labs |
| Privacy policy URL | Where you host `docs/PRIVACY.md` (see the release checklist in `ROADMAP.md`). |
| Support URL | A page with the support address, `jcfurey@furey-labs.com`. |

## App Privacy

Answer **Data Not Collected**. Apple counts data as collected when it leaves the device and is
kept longer than it takes to answer the request. This app:
- stores the library on the device and in the user's own private iCloud database, which the
  developer can't read;
- sends a scanned barcode's number to UPCitemdb, in real time, to look up the product;
- sends map searches and picked points to Apple Maps;
- has no analytics, ads, crash reporting SDK, account or server.

If you ever add analytics or a server, this answer has to change before that version ships.

## In-app purchases

Three consumables, matching `ShutterManager.storekit` (a unit test checks the file against the
app's `TipProduct` list):

| Product ID | Reference name | Price | Display name | Description |
|---|---|---|---|---|
| `jcameronfurey.shuttermanager.tip.small` | Small Tip | 0.99 USD | Small Tip | A small thank-you for Shutter Manager. |
| `jcameronfurey.shuttermanager.tip.medium` | Medium Tip | 2.99 USD | Medium Tip | A medium thank-you for Shutter Manager. |
| `jcameronfurey.shuttermanager.tip.large` | Large Tip | 4.99 USD | Large Tip | A large thank-you for Shutter Manager. |

Family Sharing stays off. Each needs a review screenshot of Settings → Tip Jar, and the three go
in for review with the 1.0 build.

## Screenshots

Upload the iPhone 6.9" and iPad 13" sets; App Store Connect scales them down for the smaller
sizes. They come from CI, as `marketing/README.md` describes, and go up in file-name order:

1. Inventory
2. Gear detail
3. Shoots
4. Shoot detail, with its light and packing list
5. Sun & Moon
6. Tools
7. Light Meter
8. Film Rolls
