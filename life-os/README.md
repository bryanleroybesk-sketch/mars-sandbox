# Life OS

A personal life dashboard that installs on your phone like an app (PWA). There's no build step and no server: everything is plain HTML, CSS and JS.

**What it tracks:** water, steps, weight, sleep, mood and energy, daily habits, where your time goes (deep work, investing in yourself, partner, exercise, rest, fun), a focus timer, daily spending against a budget, goals and projects broken into steps, a "where I want to be" vision, and a life balance wheel with 30-day trends.

## Host it free on Vercel
1. Go to vercel.com → **Add New Project** → import this GitHub repo.
2. Set **Root Directory** to `life-os`. Framework preset: **Other**. Leave the build command empty.
3. Deploy. You get a URL like `https://life-os-xyz.vercel.app`.

## Put it on your iPhone like an app
Open the URL in **Safari** → Share → **Add to Home Screen**. It opens full-screen, with no browser bar, and works offline.

## Apple Health / Apple Watch / Xiaomi scale
A website can't read Apple Health directly, so an iOS **Shortcut** bridges it:
- **Xiaomi scale:** in Mi Fitness (or Zepp Life), turn on Apple Health sync for Weight.
- **Shortcut:** use *Find Health Samples* to get today's steps, latest weight and last night's sleep. Put them in a Text action as `lifeos:steps=..;weight=..;sleep=..`, then *Copy to Clipboard*.
- **Automation:** run it every evening (Shortcuts → Automation → Time of Day).
- **In the app:** tap **⟳ Health** and it imports the numbers. The full step-by-step guide is under **More**.
- **Desktop / link import:** `https://your-app/?steps=8000&weight=72.4`

## Your data
Your data is stored on the device (localStorage). Use **More → Export backup** regularly.

## Roadmap ideas
- **Cloud sync** between phone and computer (Supabase free tier): login plus one table of JSON per day.
- **Fully automatic Health sync**: the Shortcut POSTs to a Vercel API route (`Get Contents of URL`), so you don't need to tap anything.
- **Bank import** (CSV or GoCardless) for automatic spending tracking.
- **Weekly review screen** and an AI coach that reads your week and suggests one focus.
- **Native app** (Expo / React Native + HealthKit) if you ever want true background Health sync.
