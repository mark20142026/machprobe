# Videos — what to record

Short clips make the README believable at a glance. Record them on the iPhone itself.

## How to record

1. iPhone: Settings → Control Center → add **Screen Recording**.
2. Before recording: **Do Not Disturb on** (no notifications in the video), battery/charging
   as normal, game at the recommended settings.
3. Swipe down from the top-right → tap **Screen Recording** (long-press it to turn the
   **microphone off** unless you want to talk over it).
4. Stop with the red indicator at the top. Clips land in Photos.
5. Optional: film the phone with a second camera for a "real hardware" shot
   (shows it's really a phone, and shows the controller).

## Shot list

| # | Clip | Length | What must be visible |
|---|---|---|---|
| 1 | **Boot** | 60–90 s | Home screen → tap the Cyberpunk 2077 icon → loading → main menu. One continuous take, no cuts (it proves it really boots). |
| 2 | **Load a save** | 30–60 s | Main menu → Load Game → into the world. |
| 3 | **Driving** | 60 s | Night City at night, driving with a controller. The best "wow" clip. |
| 4 | **On foot + combat** | 60 s | Walking, a short fight, the HUD. |
| 5 | **Touch controls** | 30 s | Menus by touch, the on-screen stick and buttons. |
| 6 | **Real hardware** (second camera) | 20–30 s | The phone in hand or on a stand with the controller, game running. |
| 7 | **Benchmark** (optional) | full run | Settings → run the built-in benchmark → result screen (39.44 fps on the tested setup). |
| 8 | **Setup with an agent** (optional, screen recording on the Mac) | 2–5 min, sped up | `setup.py doctor` all PASS → build → install → copy-data progress. |

## Rules for published videos

- **Don't show** the iPhone's settings pages with your Apple ID, the Xcode accounts screen, Steam
  account details, or terminal output with your UDID / team ID / signing identity.
- Gameplay footage of Cyberpunk 2077 is CD PROJEKT RED's content; short gameplay clips for a
  non-commercial project are commonly accepted, but check CDPR's fan-content guidelines before
  monetizing anything.
- **Don't put videos in git** (they're large). Upload to YouTube or attach them to a GitHub
  README edit (GitHub hosts them as `user-attachments`), then replace the "Videos" line at the top
  of the main README with the links.

## README placeholders

The main [README](../README.md) has a `🎬 Videos:` line near the top — replace it with:

```markdown
🎬 **Videos:** [Boot to main menu](LINK) · [Driving in Night City](LINK) · [Controller and touch](LINK)
```
