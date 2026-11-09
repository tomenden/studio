# הסטודיו של יעל

Yael's learning games in one place.

- `docs/` is the lobby, served at https://tomenden.github.io/studio/.
- `docs/games.json` controls what's in the studio. Each game has a `status`:
  - `active`: shown in the lobby.
  - `archive`: moved under "ארכיון", still playable.
  - `hidden`: gone from the lobby, and the iPhone app won't open it.

  Edit it on GitHub (works from a phone too). It's live in about a minute, with no app rebuild.
- `ios/` is a thin iPhone app that shows the lobby full screen, so Screen Time can treat it as one app ("Always Allowed").

## Install on Yael's iPhone (once, then about once a year)

1. Connect the phone by cable, unlock it, tap **Trust**.
2. On the phone: Settings → Privacy & Security → **Developer Mode** → on (the phone restarts).
3. Run `ios/install.sh`.
4. On the phone: Screen Time → Always Allowed → add **הסטודיו**.

Development signing lasts a year. When the app stops opening, run step 3 again.
