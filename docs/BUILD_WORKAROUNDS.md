# Building PiSky-iOS with no Mac & no bill — researched & ranked

Deep-research pass (4 parallel agents, live sources, 2026-06-01). The question: get a **native
SwiftUI** app compiled and onto an **iPhone 11 Pro Max** from a **Windows** PC with **no Mac**, ideally
**$0** and **no credit card**. Short answer: **yes, fully achievable** — and you don't need the exotic
stuff. Quotas verified against vendor docs; they change, so links are dated.

---

## ★ RECOMMENDED END-TO-END PATH ($0, no Mac, no card, works today)

1. **Make `pisky-ios` a PUBLIC GitHub repo.** macOS Actions runners are **free and effectively
   unlimited on public repos** — no minute cap, no payment method. (Private repos are the ones that
   bill: macOS = 10× minutes, only ~200 real min/mo free, and a card is required past that.) This repo
   has **no secrets** (no keys/tokens/passwords; only your LAN IP `192.168.1.207`, meaningless off your
   network), so public is safe.
2. **CI builds an unsigned `.ipa`** — the workflow already does this (`CODE_SIGNING_ALLOWED=NO`).
3. **Install it from Windows with Sideloadly** — it re-signs the unsigned `.ipa` with your **free
   Apple ID** and pushes it to the phone. Enable **Settings → Privacy & Security → Developer Mode** on
   the iPhone first (iOS 16+ requirement).
4. **Re-sign every 7 days** (free-Apple-ID limit; Sideloadly's daemon auto-refreshes while the phone
   can reach your PC). Lifting that to ~1 year needs a paid Apple Developer account ($99/yr) — optional.

That's the whole chain, free, no Mac. Commands you run (you're already `gh`-authenticated):
```powershell
& "C:\Program Files\GitHub CLI\gh.exe" repo edit --visibility public --accept-visibility-change-consequences
& "C:\Program Files\GitHub CLI\gh.exe" workflow run ios.yml
```
Then grab the `PiSky-unsigned-ipa` artifact from the Actions run → open it in **Sideloadly**.

**If a public repo is a dealbreaker:** use **Codemagic free tier** instead (500 macOS min/mo, **no card**,
**private** repos OK) → same Sideloadly install. 5-minute web signup.

---

## Tier A — get to a real Apple toolchain in the cloud (the sane options)

| Option | SwiftUI? | Cost | Card? | Private repo? | Effort | Verdict |
|---|---|---|---|---|---|---|
| **GitHub Actions — public repo** | ✅ | **Free, unlimited** | No | n/a (public) | trivial (done) | ★ **Use this** |
| GitHub Actions — private repo | ✅ | ~200 macOS min/mo free, then $0.062/min | **Yes** (past quota) | Yes | trivial | OK for occasional builds |
| **Codemagic** free tier | ✅ | **500 macOS min/mo** | **No** | **Yes** | 5-min signup | ★ **Best private-repo option** |
| Bitrise Hobby | ✅ | ~150 macOS min/mo (300 credits) | No | Yes (1 app) | signup | Solid backup; 90-min build cap |
| Xcode Cloud | ✅ | 25 hr/mo | **Yes** ($99/yr Apple Dev) | Yes | **needs a Mac to set up** | ✗ not no-Mac |
| Semaphore free | ✅ | $15 credits | ~no | **public only** | — | ✗ no private on free |
| AppVeyor free | ✅ | — | No | **public only** | — | ✗ public-only, weak macOS |
| GitLab CI free | ✅ | — | **Yes** | **macOS blocked on Free** | — | ✗ free tier can't use macOS runners |
| ~~Cirrus CI~~ | — | — | — | — | — | ✗ **shut down 2026-06-01** |

Sources: GitHub [Actions billing](https://docs.github.com/billing/managing-billing-for-github-actions/about-billing-for-github-actions) + [pricing changelog 2025-12-16](https://github.blog/changelog/2025-12-16-coming-soon-simpler-pricing-and-a-better-experience-for-github-actions/) + [minute multipliers](https://docs.github.com/en/billing/reference/actions-minute-multipliers); [Codemagic pricing](https://docs.codemagic.io/billing/pricing/); [Bitrise pricing](https://bitrise.io/pricing); [Semaphore FAQ](https://docs.semaphore.io/getting-started/faq) (private blocked on free); [AppVeyor pricing](https://www.appveyor.com/pricing/); [GitLab hosted macOS](https://docs.gitlab.com/ci/runners/hosted_runners/macos/) (Premium/Ultimate only) + [credit-card requirement](https://gitlab.com/gitlab-org/gitlab/-/issues/9916); [Xcode Cloud 25 hrs](https://developer.apple.com/news/?id=ik9z4ll6); Cirrus shutdown via [CircleCI blog](https://circleci.com/blog/cirrus-ci-alternative/).

## The install step (also free, also no Mac)

| Tool | Windows-native? | Re-signs unsigned CI `.ipa`? | Free-Apple-ID limit | Notes |
|---|---|---|---|---|
| **Sideloadly** | ✅ | ✅ (its core job) | 7-day, 3 apps | ★ **recommended**; handles Dev Mode; USB/Wi-Fi auto-refresh |
| AltStore Classic + AltServer | ✅ | ✅ | 7-day, 3 apps | best **OTA** auto-refresh (PC must stay reachable) |
| SideStore | once (pairing) | ~yes | 7-day, 3 apps | beta, finicky; refresh without PC via on-device WireGuard |
| AltStore PAL | n/a (on-device) | ✗ (marketplace, not a re-signer) | none | **EU-only — not usable in Illinois** |

A paid Apple Developer account ($99/yr) turns the 7-day/3-app cap into ~1-year/unlimited for any of
these. Sources: [Sideloadly FAQ](https://sideloadly.io/faq.html), [build-unsigned-ipa-for-Sideloadly](https://oivoodoo.medium.com/build-unsigned-ios-ipa-to-install-via-sideloadly-930e00ac9b26), [AltStore FAQ](https://faq.altstore.io/altstore-classic/app-ids), [SideStore FAQ](https://docs.sidestore.io/docs/faq), [AltStore PAL](https://faq.altstore.io/altstore-pal/what-is-altstore-pal).

---

## Tier B — "there's always a way": no-Mac COMPILE  🐉 here be dragons

You asked me to go as far as writing an emulator. I checked all of it. Honest verdict: **one route
actually compiles SwiftUI without a Mac (xtool), but none of these beat the free public-repo CI above,
and two are legally off-limits.**

- **xtool** (github.com/xtool-org/xtool) — the real find. Open-source SwiftPM-based toolchain that
  builds/signs/installs iOS apps from **Windows/WSL/Linux**, and it **does support SwiftUI** (it
  extracts the iOS SDK that vends UIKit+SwiftUI). **Catches:** (1) you must download Apple's
  multi-GB `Xcode.xip` and let xtool extract the SDK — which the **Apple Developer Program License
  Agreement §2.1 explicitly forbids** ("not to install, use or run the Apple SDKs on any
  non-Apple-branded computer"); the author won't bless it and suggests doing the real build on macOS
  CI. (2) **No** app entitlements/extensions/widgets, no binary-dependency frameworks, no asset-catalog
  niceties — fine for a code-only SwiftUI app, risky for PiSky's full feature set. (3) On-device
  **install** was reported flaky on WSL/Windows (build→IPA works; USB install often falls back to
  Sideloadly anyway). Signing still goes through Apple (free 7-day). → *Interesting, genuinely works
  for simple SwiftUI, but more fragile and more legally dubious than just using free GitHub macOS CI.*
  Sources: [Swift Forums announce + §2.1 debate](https://forums.swift.org/t/xtool-cross-platform-xcode-replacement-build-and-deploy-ios-apps-with-swiftpm/79803), [hands-on + limitations (Ricouard)](https://dimillian.medium.com/build-an-ios-app-faster-than-ever-with-xtool-2024485a4319), [DeepWiki: SwiftUI via extracted SDK](https://deepwiki.com/xtool-org/xtool).
- **theos** — can compile Swift for iOS, but it's a jailbreak/tweak + CLI toolchain, still needs the
  Xcode-extracted SDK, and has **no turnkey SwiftUI-app → signed `.ipa`** flow. Superseded by xtool here.
- **Darling** (macOS-on-Linux, "Wine for macOS") — **does not run Xcode** ("Xcode itself doesn't run
  yet"; `xcodebuild` segfaults). Dead end. ([github.com/darlinghq/darling](https://github.com/darlinghq/darling))
- **macOS in a VM (OSX-KVM/QEMU) / Hackintosh** — technically gives you the *full real* toolchain, but
  the **macOS SLA permits macOS only on Apple-branded hardware**; running it on your PC is a license
  violation. Functional, not legitimate. ([macOS SLA](https://www.apple.com/legal/sla/docs/macOSSequoia.pdf))
- **Writing an emulator from scratch** — not feasible. The blocker was never the CPU/compiler (the
  Swift compiler is open source); it's that **SwiftUI/UIKit are closed Apple frameworks** and **signing
  is an Apple online service**. An emulator can't conjure Apple's SDK or sign for a real device. Every
  working path reuses Apple's SDK + Apple's signing — there is no clean-room route.

**The one unavoidable truth:** you always need (a) Apple's iOS SDK from somewhere and (b) an Apple
signing credential. The recommended path satisfies both *legitimately* (GitHub's licensed macOS image
builds it; your free Apple ID signs it). Tier B only changes *where* the SDK runs — and the legit-free
answer is "on GitHub's Macs," which is exactly Tier A.

---

## What needs YOU (can't be automated from here)
- **Flip the repo to public** (one `gh` command above) — or sign up for Codemagic if keeping it private.
- **Trigger / watch the Actions build** and download the `.ipa` artifact.
- **Install Sideloadly** on Windows, enable **Developer Mode** on the iPhone, sign in with your free
  Apple ID, drop in the `.ipa`.
- Work the **compile-error loop**: first CI run will surface Swift errors (this is a 110-file port that
  never hit a compiler) — paste them to me and I'll fix + you re-push until it's green.

## Bottom line
**Public repo → free GitHub macOS build → Sideloadly.** $0, no Mac, no card, fully legitimate. Codemagic
free tier is the private-repo equivalent. The exotic no-Mac compilers (xtool et al.) are real but
inferior here — keep them in your back pocket, not on the critical path.
