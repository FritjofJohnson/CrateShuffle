# CrateShuffle (WoW: Forever)

Scans your auction house and plans the cheapest **Forged Delivery Receipt** route to
Azeroth Commerce Authority / Durotar Supply and Logistics reputation. Then it tells you
**BUY**, **BUY SOME** or **HOLD**.

## How the method works

Each turn-in costs:
- 1 Forged Delivery Receipt = **15 Merchant's Favor** (camp vendor, needs Friendly)
- 1 **empty** Waylaid Crate of any type, including an unread "Waylaid Crate"

You get **50 rep** (+1s) per turn-in. Favor comes from filling crates
(crate + materials − silver paid back) ÷ favor (white crates 5/10/15/20 by tier; green crafted crates pay double).

## Install
Copy the `CrateShuffle` folder to `World of Warcraft\_forever_\Interface\AddOns\` and `/reload`.

## Use
1. Open the auction house, then click **Crate Shuffle** (top right of the AH) or type `/crate`.
2. Press **Scan AH**. This takes about 1–3 minutes, because it reads the full order book for 96 materials and every crate type.
3. Read the result:
   - **Price / rep right now**: what the next turn-in costs, in copper per rep and rep per gold.
   - **Plan**: how many crates to fill, with what, and which crates to keep empty for receipts.
   - **Shopping list**: quantities and the *max unit price* to pay for each item.
   - **HOLD** when nothing usable is listed, when prices are more than 15% above their 30-day median,
     or when the price is over your cap. **BUY SOME** when only part of your goal is available at a good price.

The goal is read from your reputation (next standing by default). Your current Merchant's Favor is counted.

## 30-day history and volatility
Each scan saves a daily price for every material, crate and route (per realm and faction).
Once there are 3 or more days of history, CrateShuffle compares against the 30-day median and marks
items as **volatile** (daily swings over 30%) or **above/below their 30d median**. Scan once a day to build it up.

## Commands
| Command | Effect |
|---|---|
| `/crate` | Show or hide the window |
| `/crate scan` | Scan (AH must be open) |
| `/crate target next\|honored\|revered\|exalted\|<turn-ins>` | Goal |
| `/crate silver <apprentice\|journeyman\|expert\|artisan\|receipt> <silver>` | Silver paid back per turn-in. Defaults: Journeyman 5s and receipt 1s (from the method post); the others are unknown and start at 0, so set them after a turn-in. |
| `/crate perk <0-3>` | Performance Bonus ranks (5% double-favor chance each) |
| `/crate rep <n>` | Rep per receipted crate, if Diplomat raises it |
| `/crate hold <pct>` | HOLD threshold versus the 30-day median (default 15) |
| `/crate cap <silver per turn-in\|off>` | Hard price cap |
| `/crate favor on\|off` | Count the favor you already have |
| `/crate settings`, `/crate resethistory`, `/crate debug` | |

## Notes
- Crafted fill items (bars, bolts, cured hides, engineering parts) are priced as bought from the AH.
  If you can make them cheaper yourself, the plan overstates the cost of those routes.
- Artisan favor (20/40) is the community's expected value, not a confirmed one.
- The addon never buys anything. You buy from the shopping list yourself.
