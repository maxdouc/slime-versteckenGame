# Playtest-Protokoll — Slime-Verstecken (Community-Playtest ~100)

Schließt den offenen Punkt aus SPEC.md 16 ("Playtest-Protokoll"). Deckt
BUILD_PLAN Phase 8 ab. Sprache absichtlich Deutsch — die Tester sind die
deutschsprachige Discord-Community.

## 1. Ziel & Nicht-Ziele

- **Ziel:** Beweisen, dass der Kernloop (verwandeln → malen → umziehen →
  neu malen) über echte Browser Spaß macht und technisch hält; Daten für
  die drei Entscheidungstore sammeln (Abschnitt 5).
- **Nicht-Ziel:** Balance-Feintuning einzelner Zahlen (dafür sind spätere
  Runden da), Map 2, Klon-Polish.

## 2. Rollout in drei Wellen (Discord)

| Welle | Tester | Dauer | Zweck |
|---|---|---|---|
| A — Smoke | 4–6 (Freunde) | 1 Abend | Verbindungsqualität, Show-Stopper |
| B — Kern | 15–25 | 3–4 Tage | Loop-Spaß, erste Metriken, Survey v1 |
| C — Breite | bis ~100 | 1 Woche | Skalierung Signaling, finale Survey |

Ablauf pro Welle:
1. Travis aktualisiert den Build (`tools/push_playtest.md`).
2. Link + Zugang NUR im privaten Discord-Kanal teilen — die itch-Seite
   bleibt versteckt/draft (LOCAL_OPERATOR-Policy). Travis entscheidet den
   Mechanismus (geheimer Link/Passwort); Agents ändern NIE die Sichtbarkeit.
3. Feste Spieltermine ansetzen (6–8 Spieler pro Lobby, SPEC.md 4) — ein
   Host streamt den Ablauf in den Voice-Channel (Koordination über
   Discord, kein In-Game-Voice in V1, SPEC.md 5.3).
4. Nach jeder Session: Survey-Link posten, Metriken-Thread pflegen.

## 3. Metriken (pro Session, vom Host notiert + Screenshots)

Technisch:
- Verbindungsversuche vs. erfolgreiche Joins (Signaling-Server-Log zählt
  Räume/Peers mit).
- Disconnects mitten in der Runde (Anzahl, wann).
- Gefühlte FPS im Browser (Tester-Angabe grob: flüssig / ruckelig /
  unspielbar) + 1× echte Messung pro Welle (Browser-Overlay) auf einem
  schwachen Gerät.
- Ladezeit bis Lobby (Stoppuhr, einmal pro Tester-Gerät).

Gameplay (pro Runde):
- Rundenlänge bis Sieg/Timeout.
- Eliminierungen nach Ursache: Paintball / Rotation (zerlaufen) /
  Klon-Todes-Link — das Verhältnis zeigt, ob der Rotationszwang trägt.
- Gefressene NPCs pro Verstecker (0–3) — wird die Progression genutzt?
- Grundieren-Nutzung: malen die Leute überhaupt um (Beobachtung Host)?
- Sucher-Trefferquote grob (Treffer / Schüsse aus dem Cooldown-Log-Gefühl).

## 4. Survey (max. 10 Fragen, nach Welle B und C)

1. Wie viel Spaß hatte die Runde insgesamt? (1–5)
2. Hast du verstanden, WARUM du regelmäßig den Raum wechseln musst? (Ja/Nein)
3. Fühlte sich der 60-Sekunden-Druck fair an? (zu hart / genau richtig /
   zu lasch)
4. Als Verstecker: War das Malen schnell genug für den Loop? (1–5)
5. Als Sucher: Hattest du eine echte Chance? (1–5)
6. Wie oft hast du gefressen, und hat sich das Freischalten gelohnt? (Text)
7. Lief das Spiel flüssig in deinem Browser? (1–5, plus Browser/Gerät)
8. Der Look (Kenney-Möbel): reicht der für den Launch, oder wirkt es
   billig? (reicht / egal / wirkt billig)
9. Was war der beste Moment? (Text)
10. Was hat am meisten genervt? (Text)

## 5. Entscheidungstore (nach Welle C, Team-Beschluss + SPEC-Update)

- **Kenney vs. Synty (SPEC.md 14):** Frage 8 + Beobachtung. Schwelle:
  wenn ≥ ~40 % "wirkt billig", Synty-Investition (~100–200 €) ernsthaft
  prüfen. Achtung: Pack-Wechsel = Map-Neubau in Tagen (Layout bleibt).
- **Cooldown-Tuning (SPEC.md 11):** Trefferquote + Frage 5. Hebel:
  Cooldown-Sekunden (Host-Regler) und die offene Frage, ob auch TREFFER
  cooldownen sollen (aktuell spec-getreu: nur Fehlschüsse).
- **Klon-Schnitt (SPEC.md 10):** Klone sind der erste Streichkandidat.
  Wenn Wellen A/B ohne Klon-Verständnis-Probleme laufen, bleiben sie;
  verwirren sie oder tragen Bugs bei, fliegen sie für den Launch.

## 6. Rollen

- **Travis:** Build-Uploads, itch-Zugang, Discord-Rollout, Metriken-Thread.
- **Maxim:** Session-Host Welle A/B, Signaling-Server-Betrieb, Auswertung.
- Beide: Survey-Auswertung, Entscheidungstore als Team-Beschluss, danach
  SPEC.md-Update (Prozessregel: entweder im Spec mit Baureihenfolge oder
  gestrichen).

## 7. Offene Vorbedingungen (Stand 2026-07-15)

- itch-Upload hängt an der E-Mail-Verifizierung des itch-Kontos
  (`tools/push_playtest.md`, Attempt-Log).
- Signaling-Server braucht für Welle B/C ein öffentlich erreichbares
  Zuhause + WSS/TLS (bewusst aus Branch 1D ausgeklammert) — vor Welle B
  als eigener Task einplanen.
- Browser↔Browser-Join steht noch auf der manuellen Zwei-Maschinen-Liste.
