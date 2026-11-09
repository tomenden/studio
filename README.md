# הסטודיו של יעל

Yael's learning games in one place.

- `docs/` is the lobby, served at https://tomenden.github.io/studio/.
- `docs/allow.json` lists the site paths the iPhone app may open. Add a new game's path here and to `GAMES` in `docs/index.html`; the app picks it up without a rebuild.
- `ios/` is a thin iPhone app that shows the lobby full screen, so Screen Time can treat it as one app ("Always Allowed").

## Install on Yael's iPhone (once, then about once a year)

1. Connect the phone by cable, unlock it, tap **Trust**.
2. On the phone: Settings → Privacy & Security → **Developer Mode** → on (the phone restarts).
3. Run `ios/install.sh`.
4. On the phone: Screen Time → Always Allowed → add **הסטודיו**.

Development signing lasts a year. When the app stops opening, run step 3 again.
