# HSA Receipts (iPhone)

Scan receipts, see which expenses are most likely HSA-eligible, track your **available-to-reimburse balance**
(overall and by year), let the app **pick receipts that add up to a target amount**, and **export PDF claim
packets** to upload to your HSA provider. Everything is saved as plain files in a **shared iCloud Drive
folder**, so you and your spouse see the same receipts.

## Features

| Tab | What it does |
|---|---|
| **Dashboard** | Available-to-reimburse balance, all-time reimbursed, receipts needing review, eligible vs. reimbursed by year (chart + table), recent receipts |
| **Receipts** | Search, filter (All / Available / Reimbursed / Review), grouped by year. Swipe right to mark reimbursed, left to delete |
| **Reimburse** | Enter an amount → “Find best combination” picks the unreimbursed receipts that add up closest to it (exact subset-sum, oldest receipts win ties; optionally allow going slightly over). Adjust picks by hand, then export |
| **Settings** | Pick the shared iCloud folder, household names, export the full CSV ledger, how-to for sharing |

**Adding receipts:** document camera (auto-crop, multi-page), photo library, or PDF/image from Files (e.g. emailed receipts, provider statements).
Text recognition runs **on the device** with Apple Vision — nothing is uploaded anywhere.

**Eligibility engine** (`HSACore/Sources/HSACore/EligibilityRules.swift`): keyword rules based on IRS Pub 502 + the CARES Act.
Every line item is tagged *Eligible*, *Maybe (needs a Letter of Medical Necessity)*, *Not eligible*, or *Review*.
Doctor/dentist/vision bills count in full; pharmacy receipts that print an “FSA/HSA eligible total” use that number;
otherwise the eligible items are summed and sales tax is prorated. You can override any item or the amount.

**Export for upload:** one combined PDF (summary page listing date, provider, patient, amount + total, followed by every
receipt image) or one PDF per receipt. Share sheet → Save to Files / upload on your HSA provider’s site or app.
Afterwards tap **Mark these as reimbursed** so your balance stays accurate. A copy of every export is kept in `Exports/`.

## Files in iCloud Drive

```
HSA Receipts/                       ← the folder you share with your spouse
  Receipts/2026/2026-11-02 CVS Pharmacy 25.20 a1b2c3.json
  Receipts/2026/2026-11-02 CVS Pharmacy 25.20 a1b2c3-1.jpg
  HSA Ledger.csv                    ← rebuilt on every save; opens in Numbers/Excel
  Exports/HSA Claim 2026-11-18 $412.77.pdf
```
Each receipt is its own file, so two phones adding receipts at the same time don’t conflict.

## Build & install (needs a Mac)

1. Install Xcode 15 or newer from the Mac App Store, and XcodeGen: `brew install xcodegen`
2. In this folder run: `xcodegen generate` → opens as `HSAReceipts.xcodeproj`
3. Open the project, select the **HSAReceipts** target → *Signing & Capabilities* → choose your Team
   (your Apple ID works) and change the bundle ID to something unique, e.g. `com.yourname.hsareceipts`.
4. Plug in your iPhone (enable *Settings › Privacy & Security › Developer Mode*), pick it as the run destination, press ▶.
5. Do the same with your wife’s iPhone.

**Free Apple ID vs. paid developer account:** with a free Apple ID the app must be re-installed from Xcode every
7 days. With the $99/yr Apple Developer Program you can use **TestFlight** to install it on both phones (and get
updates) without cables — recommended for two people.

Run the unit tests (parser, classifier, reimbursement planner): `cd HSACore && swift test`, or ⌘U in Xcode.

## Share the folder with your spouse

1. Files app › iCloud Drive › create a folder **HSA Receipts**.
2. Long-press it › **Share › Collaborate** › *Only invited people* + *Can make changes* › send to your spouse.
3. Spouse accepts; the folder appears in their iCloud Drive.
4. In the app on **both** phones: Settings › *Choose iCloud Drive folder* › pick **HSA Receipts**.

Pull down on any list (or reopen the app) to pick up receipts the other person added.

## Customizing eligibility

Add keywords to the lists in `EligibilityRules.swift`. Short keywords (≤4 letters) must match a whole word, longer ones
match word prefixes (`ibupro` matches `ibuprofen`), and a trailing `*` forces prefix matching (`spf*` matches `SPF50`).
When several keywords match, the longest (plus the rule’s priority) wins — so “diaper rash cream” is eligible but “diapers” isn’t.

> Eligibility is an estimate, not tax advice. Keep receipts and confirm with your HSA provider.
