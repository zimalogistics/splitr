# Splitr — Pace & Speed Calculator

A clean, simple iOS app for runners and athletes who are tired of switching between apps or doing mental math mid-training.

---

## The Story

During training runs and races, I constantly found myself needing to convert between paces, speeds, distances, and finish times — and there was no single place to do it cleanly. I'd be mid-run trying to figure out what a 6:45/mile pace works out to in km/h, or how a 4:10 marathon translates to a per-kilometre split, and I'd end up switching between three different apps or scribbling it out by hand.

So I built a spreadsheet. Then another one. Eventually I had a Google Sheet with about a thousand calculations and some seriously long formulas — and it actually worked great.

👉 [Check out the original Google Sheet](https://docs.google.com/spreadsheets/d/1gldIQmkMm5yFFbqAIljI15ee2zE5ol9PyR4PRhBltpY/edit?usp=sharing)

But I wanted something I could pull up in two seconds on my phone without scrolling through rows of data. Something that just gives you the answer the moment you start typing. So I built Splitr.

---

## What It Does

Enter any two values — speed, pace, distance, or time — and Splitr instantly calculates everything else. No submit button. No switching screens. Just the numbers.

- Speed in mph and km/h
- Pace per mile and per kilometre
- Distance in miles and kilometres
- Time in HH:MM:SS
- Distance shortcuts for 5K, 10K, Half Marathon, and Marathon
- Save and name your favourite setups
- iCloud sync across your devices
- Home screen widget showing your most recent preset

---

## Download

Coming soon to the App Store.

---

## Support

Found a bug or have a suggestion? [Open an issue](https://github.com/zimalogistics/splitr/issues) — I actually read them.

---

## Buy Me a Coffee

If Splitr has saved you time or helped with your training, I'd really appreciate it!

- In-app tip jar (App Store) — helps keep the app free
- Venmo: **@GabeLee** ☕

---

## Building Locally

Requires Xcode 15+, iOS 17 deployment target.

```bash
# Install xcodegen if you don't have it
brew install xcodegen

# Generate the Xcode project
./generate.sh

# Open in Xcode
open Splitr.xcodeproj
```

---

*Hope it helps you hit your goals. Happy running! 🏃*
