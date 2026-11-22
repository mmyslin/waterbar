# Waterbar

A minimal, interactive iOS Home Screen widget built with **SwiftUI**, **Swift Charts**, and **App Intents** that displays day-by-day hourly precipitation probability forecasts.

## Features

- **Day-by-Day Interactive Navigation:** Step forward and backward across a 4-day forecast (`TODAY` plus the next three days) using `<` and `>` widget controls powered by `AppIntent`.
- **Midnight-to-Midnight Timeline:** Fixed 24-hour X-axis (`12a` to `12a`) that begins plotting `TODAY`'s forecast curve from the current hour forward.
- **Smooth Precipitation Curve:** Catmull-Rom spline line graph with a vertical gradient transitioning from muted gray (`0%`) to blue (`100%`).
- **Free Public Weather Data:** Fetches hourly precipitation probabilities from the [Open-Meteo API](https://open-meteo.com) with no API key required, paired with local `UserDefaults` caching for instant day switching.

## Tech Stack

- **Frameworks:** SwiftUI, WidgetKit, Swift Charts, AppIntents
- **Data Source:** Open-Meteo Forecast API (`forecast_days=4`)
- **Widget Family:** Medium (`.systemMedium` — 4×2 Home Screen grid)
- **Target:** iOS 17.0+

## Setup & Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com
   ```
2. **Open in Xcode:**
   Open the `.xcodeproj` file in Xcode.
3. **Configure Signing:**
   Select your **Team** (a free personal Apple ID works for personal device deployment) under **Signing & Capabilities** for both the main app target (`MyApp`) and the widget extension target (`WaterbarExtension`).
4. **Customize Location (Optional):**
   Update the default `lat` and `lon` coordinates in `WeatherService.fetchFourDayRain(lat:lon:)` inside `Waterbar.swift`.
5. **Build & Run:**
   Select your physical iPhone as the run destination and press **Cmd + R**.
6. **Add to Home Screen:**
   Long-press an empty area on your iPhone Home Screen, tap **Edit > Add Widget**, search for **Waterbar** / **Daily Rain Forecast**, and add the **Medium (4×2)** widget.

## Notes on Personal Provisioning

If deploying with a free Apple ID rather than a paid Apple Developer Program membership, iOS requires re-running the app from Xcode every **7 days** (over USB or Wi-Fi wireless debugging) to refresh the personal provisioning profile.

