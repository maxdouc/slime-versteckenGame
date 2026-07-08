# ⚠️ WEB-FIRST OVERRIDES (v1.1 · 08.07.2026 · Team-Beschluss)

Diese Overrides haben Vorrang vor dem Originaltext darunter. Der Originaltext
(v1.0) bleibt unverändert als Referenz stehen. Bei Widerspruch gilt dieser Block.

1. **Plattform:** Web (HTML5) ZUERST. Steam = V2. Grund: ein Link statt Build-
   Verteilung für den ~100-Personen-Community-Playtest.
2. **Engine/Netzwerk:** KEIN GodotSteam (native Lib, läuft nicht im Browser).
   Stattdessen Godot High-Level-MP über **WebRTC** + kleiner **WebSocket-
   Signaling-Server** (`/server`). Transport liegt hinter dem `Net`-Autoload;
   Steam-Port später = Peer-Tausch in `_create_peer()`.
3. **Lobby:** Kein Steam-Matchmaking. **6-stelliger Raum-Code** zum Beitreten.
4. **Monetarisierung:** Kein Steam-Cosmetics-Shop in V1 (Web hat keinen Store).
   Abschnitt 12 gilt erst ab Steam-Port.
5. **Baureihenfolge:** Nur Schritt 1 wird ersetzt (Steam-Lobby -> Web-MP-
   Scaffold). Schritte 2-8 unverändert.
6. **Web-Zwänge:** Threads-Export braucht COOP/COEP-Header -> Hosting auf
   itch.io (nicht GitHub Pages). Paint-Texturen klein halten (256²/512²).
   Brush-Strokes strikt als Events, nie ganze Texturen (verschärft 9.3).

---

# ORIGINAL v1.0 (unverändert)

also das war meine Idee Slime-Verstecken (Arbeitstitel) — Game Design Spec

Version 1.0 · Stand: 08.07.2026 · Team: Maxim + Partner (2 Entwickler, kein Artist)
Status: Design gelockt. Änderungen nur per Team-Beschluss und Update dieses Dokuments.


0. Hinweis für Claude Code / Codex

Dieses Dokument ist die einzige Wahrheitsquelle für Gameplay-Entscheidungen. Bei Widerspruch zwischen Code und Spec gilt das Spec. Verweise auf "Meccha Chameleon" oder "Prop Hunt" sind Einordnung, keine Anforderung — alles Bindende steht explizit hier.


1. Pitch

Multiplayer-Verstecken für 6–8 Spieler auf Steam: Spieler sind Slimes, die sich in Objekte verwandeln und ihre weiße Form per Malwerkzeug in die Umgebung eintarnen. In der Vorbereitungsphase gefressene NPC-Slimes schalten kleinere, schnellere Formen und Klone frei. Ein individueller Rotations-Timer zwingt alle 60 Sekunden zum Raumwechsel — Tarnung ist nie fertig, sondern ein Dauerloop: verwandeln → malen → umziehen → neu malen.

Abgrenzung: Meccha Chameleon = malen ohne Verwandlung. Prop Hunt = verwandeln ohne malen. Wir = beides, plus Fress-Progression und Rotationszwang. Kein Punktesystem — reines Überleben.


2. Entscheidungsübersicht (Kurzfassung für den Partner)

BereichEntscheidungKernbegründungPlattformSteam, eigene IP~100-Personen-Community als Playtest-Pool vorhandenEngineGodot 4 + GodotSteamTextdateien = ideal für AI-Agenten; Multiplayer eingebaut; Steam-P2P-Relay = 0 € ServerkostenLobby6–8 Spieler, 1–2 SucherKleine Maps, testbar; hochskalieren geht später, runterskalieren nieRundenmodellPrep-Phase (fressen) → Jagd-Phase (verstecken)Löst den Konflikt "Fressen braucht Bewegung, Verstecken braucht Stillstand"Anti-PassivitätRotationszwang: individueller 60-s-Timer pro Verstecker (Idee: Maxim)Erzwingt Bewegung statt Statuen-Simulator — ohne MCs Punktesystem zu kopierenSiegÜberleben bis Timer-Ende, kein ScoreBilligster Build; die Spannung liefert die RotationProgressionFressen schaltet kleinere Formen + Klone frei (umgedrehte Tabelle, Idee: Maxim)Klein = stark in Prop Hunt; Fressen belohnt mit Stärke, nie mit NachteilVerwandlungLiefert nur die Form; Objekt spawnt immer neutral weiß; Anstrich macht der SpielerVerzahnt beide Kernmechaniken; verhindert gekaufte Tarnung über SkinsMalsystemMC-Prinzip (Eyedropper, Farbrad, HSV) + eigener Grundieren-KnopfRotation verlangt Schnell-Anstrich; Detailmalerei bleibt Skill-AusdruckKloneMax. 3, Todes-Link, Tausch-TeleportEinzige Version, in der der Todes-Link ein Preis für etwas ist; zuletzt gebaut, zuerst gestrichenSucherPaintball-Gun, Fehlschuss = 4-s-CooldownFarbe passt zur Kernmechanik; Splatter verändert die TarnflächenNPCs2× Versteckerzahl, schlafend, verschwinden bei Jagdstart (Veto Maxim gegen Jagd-NPCs)Pechvogel-Schutz in der Prep; maximale Lesbarkeit in der JagdMonetarisierungNur Kosmetik/Identität; P2W-Idee ersatzlos gestrichenSteam-Reviews und Community sind das Startkapital — beides stirbt an P2WMaps1. Wohnhaus, 2. Casino — strikt nacheinanderMap 1 beweist die Pipeline, Map 2 nutzt sieAssetsKenney (kostenlos, CC0); Entscheidungstor nach Playtest 1 für Synty (~100–200 €)Kein Artist im Team; weiße Props = Spieler malen den Content selbstProzessFeature-Branches + PRs; "wie bei Spiel X" ist verboten; 2-Rechner-TestregelAI-Team-Disziplin; Desyncs existieren nur im echten Netz


3. Technik & Team


Engine: Godot 4 mit GodotSteam. Lobbys, Matchmaking und P2P-Verbindungen laufen über Steams Relay-Server — keine eigenen Game-Server, keine laufenden Kosten.
Perspektive: 3D, Third-Person. Beim Malen ist die Kamera um den eigenen Körper rotierbar (Sucher-Blickwinkel prüfen).
Team & Tools: 2 Entwickler, 2× Claude Code, 1× Codex, gemeinsames GitHub-Repo.
Git-Regeln: Jeder arbeitet auf eigenem Feature-Branch. Merges ausschließlich per Pull Request. Kein direkter Commit auf main — auch nicht durch AI-Agenten.
Testregel: Jedes Netzwerk-Feature wird auf zwei physischen Rechnern getestet, nie nur im Editor.
Zeithorizont: In Monaten denken, nicht in Wochen.



4. Lobby & Einstellungen


6–8 Spieler pro Lobby.
Sucher: 1 bei bis zu 6 Spielern, 2 ab 7 Spielern. Host-Regler.
Host-einstellbar (Among-Us-Prinzip): Prep-Zeit, Jagd-Zeit, Rotations-Timer, NPC-Anzahl, Sucher-Anzahl.
Defaults: Prep 60 s · Jagd 4 min · Rotation 60 s · Paintball-Cooldown 4 s · NPCs = 2× Versteckerzahl.



5. Rundenablauf

5.1 Prep-Phase (Default 60 s)


Verstecker: NPC-Slimes suchen und fressen, verwandeln, anmalen, positionieren. Kein Rotationszwang.
Sucher: warten in abgetrenntem Spawn-Raum, blind.


5.2 Jagd-Phase (Default 4 min)


Ungefressene NPCs verschwinden bei Jagdbeginn mit sichtbarem Poof-Partikel.
Rotations-Timer aktiv (Abschnitt 6).
Malen und Verwandeln bleiben jederzeit erlaubt.


5.3 Sieg, Tod, Rundenende


Sucher gewinnen, wenn alle Verstecker vor Timer-Ende eliminiert sind.
Jeder überlebende Verstecker gewinnt individuell. Kein Punktesystem.
Eliminierte: freie Zuschauerkamera, Textchat nur mit anderen Toten. Kein Voice-Chat in V1 (Community nutzt Discord).
Kompletter Reset jede Runde. Keine persistenten Freischaltungen (siehe Abschnitt 12).



6. Rotations-Mechanik (Kern-Identität)


Individueller 60-s-Timer pro Verstecker, startet beim Betreten eines Raums. Gilt nur in der Jagd-Phase.
Ein Raumwechsel zählt erst nach 5 Sekunden Aufenthalt im neuen Raum (kein Türschwellen-Pendeln).
Timer abgelaufen: Der Slime verliert den Zusammenhalt — wachsende Pfütze unter dem Objekt, leises Blubbern, 10 s Gnadenfrist, dann Elimination.
Tausch-Teleport (Abschnitt 10) zählt als Raumwechsel und resettet den Timer.
Designziel: Tarnung ist nie fertig. Jeder Raumwechsel entwertet die Bemalung und erzwingt den Loop neu.



7. NPC-Slimes & Fressen


Anzahl: 2× Versteckerzahl (bei 6 Versteckern: 12). Host-Regler.
Erscheinung: Gleiches Modell wie Spieler-Slimes, aber kleiner, neutrale Farbe, schlafend (geschlossene Augen). Bewegen sich nicht, wehren sich nicht. Schlafen erklärt beides und liest sich sofort als "Futter".
Platzierung: Handgesetzte Spawn-Marker im Editor. Map 1: ca. 30 Marker, pro Runde werden 12 zufällig aktiviert — keine Runde gleicht der anderen.
Fressen: E für 1 Sekunde halten, Schlürf-Animation. Interaktions-Prompt erscheint nur an NPCs — Mitspieler sind nicht fressbar.
Fressen ist nur in der Prep-Phase möglich.



8. Progression (Fress-Tabelle)

Lore: Fressen macht den Slime nicht größer, sondern dichter. Ein hungriger Slime ist ein loser Klumpen und kann nur in große, grobe Formen zerlaufen. Mehr gefressene Masse = mehr Kontrolle = Kompression in kleinere Formen.

GefressenVerfügbare Formen (kumulativ)Klone0Groß (Fass, Regal, Karton)01+ Mittel (Eimer, Hocker)12+ Klein (Flasche, Becher, Buch)23Alle Formen (Cap erreicht)3


Kumulativ nach unten: Größere Formen bleiben immer verfügbar.
Cap bei 3 gefressenen Slimes.
Balance-Logik: Kleine Formen sind in Prop-Hunt-Spielen die stärksten Verstecke und haben zusätzlich die geringste Malfläche. Fressen schaltet also Stärke frei — nie einen Nachteil.



9. Verwandlung, Bewegung, Malsystem

9.1 Verwandlung


Verwandlung liefert nur die Form. Das Objekt spawnt immer neutral weiß — unabhängig vom kosmetischen Slime-Skin. (Anti-P2W-Schutz; Weiß ist außerdem sofort als "ungetarnt" lesbar.)
Rückverwandlung zum Slime jederzeit möglich — löscht die Bemalung.


9.2 Bewegung

ZustandTempoSlime100 %Kleine Form80 %Mittlere Form60 %Große Form40 %


Bewegung in verwandelter Form ist erlaubt (das watschelnde Fass). Die Bemalung bleibt erhalten, solange die Form gehalten wird — auch beim Laufen.
Raumwechsel-Trade-off: Als bemaltes Objekt wandern = langsam und auffällig, aber Farbe bleibt. Als Slime sprinten = schnell, aber ungetarnt und im neuen Raum wird von null gemalt.


9.3 Malsystem — V1-Werkzeugkasten


3D-Eyedropper: Nimmt die exakte Farbe jeder angepeilten Oberfläche auf.
Farbrad + HSV-Regler: Freie Farbwahl und Feintuning nach dem Sampeln.
Ein Pinsel mit fester Größe.
Grundieren-Knopf: Ein Klick, die Eyedropper-Farbe deckt das gesamte Objekt. Pflicht-Feature — ohne One-Click-Basisanstrich ist der 60-s-Rotationsloop unspielbar. (Ablauf im Feld: Raum betreten → Boden sampeln → grundieren → Details nur bei Restzeit.)
Alles-Löschen.
Kamera-Rotation um den eigenen Körper während des Malens.
Malen ist jederzeit erlaubt (Prep + Jagd).
Netcode-Regel: Pinselstriche als Events synchronisieren und auf jedem Client abspielen. Niemals ganze Texturen verschicken.
V2 (nicht in V1): Metallic-/Roughness-Regler, Muster-Pinsel, gespeicherte Paletten, Undo.



10. Klone (Tausch-Teleport)


Freischaltung über Fressen (Tabelle in Abschnitt 8), maximal 3 gleichzeitig.
Ein Klon ist eine statische Kopie der aktuellen Form inklusive Bemalung zum Zeitpunkt der Platzierung.
Todes-Link: Wird ein Klon zerstört, stirbt der Besitzer. (Bewusste Entscheidung, zweifach bestätigt.)
Kein automatischer Zerfall — Klone bleiben stehen, bis sie genutzt oder zerstört werden.
Tausch-Teleport: Knopfdruck → Spieler teleportiert zur Position eines Klons, der Klon verschwindet. Der Sprung zählt als Raumwechsel und resettet den Rotations-Timer. Nutzung: Fluchtanker bei Entdeckung, vorgeplante Routen über die Map.
Bau-Priorität: Wird als letztes Feature gebaut und ist der erste Streichkandidat bei Zeitnot. Das Kernspiel muss ohne Klone vollständig funktionieren.



11. Sucher-Kit


Waffe: Paintball-Gun. Sichtbares Projektil, Treffer = sofortige Elimination.
Fehlschuss: Farb-Splatter bleibt dauerhaft auf der Map liegen — der Sucher verändert damit selbst die Tarnflächen. Angesprühte Verstecker müssen übermalen oder fliegen auf.
Miss-Penalty: Nur Cooldown. Default 4 s, Host-Regler, Feintuning im Playtest. (Rechenbasis: 2 Sucher × 4 min ÷ 4 s ≈ 120 Schüsse — der Playtest zeigt, ob das zu großzügig ist.)
Genau eine Waffe zum Launch. Waffen-Skins (gleiche Mechanik, andere Optik) sind Post-Launch-Backlog.
Sucher sitzen während der Prep-Phase blind in einem abgetrennten Spawn-Raum.



12. Monetarisierung


Hartes Verbot: Keine kaufbaren Spielvorteile. Die ursprüngliche Idee, Freischaltungen gegen Geld über Runden hinweg zu behalten, ist ersatzlos gestrichen.
Erlaubt (Identität, nie Stärke): Slime-Farben, Gesichter, Hüte, Verwandlungs-Effekte, Sieger-Animationen, Waffen-Skins.
Schutzregel: Verwandlungs-Objekte spawnen immer weiß — Skin-Farben dürfen nie zum Tarnvorteil werden.
Priorität: Nach Launch. Kein Shop-Code in V1.



13. Maps

Regeln für jede Map


Plausible Standorte für große Objekte in jedem Raum (alle Verstecker können groß starten).
Jeder Raum hat mindestens 2 Ausgänge — der Rotationszwang darf keine Todesfallen bauen.
Raumanzahl ≈ 1,5 × Versteckerzahl.
Flächen mit nachmalbaren Farben und Mustern: karierte Böden, Holzwände, Fliesen. Flat-Color-Materialien bevorzugt — Fotorealismus ist schwer nachmalbar und schadet der Kernmechanik.


Map 1: Wohnhaus

Erster Build. Vertraute Objekte, Plausibilität gratis. Muss einen Community-Playtest überleben, bevor eine Minute Arbeit in Map 2 fließt.

Map 2: Casino

Skill-Map: Spielautomaten als große Quader-Props, Chips/Karten/Würfel als kleine Formen, gemusterte Teppiche als Malkönnen-Prüfung. Zum Launch dabei, Bau strikt nach dem Map-1-Playtest.

Prozessregel

"Vielleicht noch hinzufügen" existiert nicht. Es gibt: im Spec mit Baureihenfolge — oder gestrichen.


14. Assets & Pipeline


Kein Artist im Team. Der AI-Stack (Claude Code, Codex, Claude Design) erzeugt keine 3D-Spiel-Assets — das ist eingeplant, kein Blocker:
Props: 15 Stück für V1 (5 pro Größenklasse), simple Formen (Zylinder, Quader), saubere UVs. Sie spawnen weiß — die "Texturen" liefern die Spieler durchs Bemalen selbst.
Slime: Kugel + Wobble-Vertex-Shader (schreibt Claude Code), Augen für Persönlichkeit, Farbe als Material-Parameter (Andockpunkt für spätere Skins). NPC = gleiches Modell, kleiner, Schlaf-Textur.
Maps: Modulare Kits. Start mit Kenney (kostenlos, CC0, kommerziell nutzbar). Entscheidungstor nach Playtest 1: Kenney behalten oder in Synty (~100–200 €) für den Launch-Look investieren. Achtung: Ein Pack-Wechsel bedeutet Map-Neubau (Tage, nicht Monate — bei unverändertem Raumlayout).
Stilregel: Ein Pack-Ökosystem, nie mischen. Zusammengewürfelte Stile = Asset-Flip-Optik = Steam-Review-Gift.
AI-3D-Generatoren (Meshy, Tripo etc.): Nur Lückenfüller für einzelne fehlende Props. Jedes generierte Modell vor dem Einbau mit einem Testanstrich prüfen — Müll-UVs zerstören die Kernmechanik.
VFX (Splatter, Tropf-Pfütze, Verwandlungs-Poof): Godot-Partikelsysteme, also Code.
Claude Design: UI-Mockups, Steam-Kapselgrafik, Store-Page — nach dem Core, nicht jetzt.



15. Baureihenfolge (nach Risiko sortiert, nicht nach Spaß)


Godot-Projekt + GodotSteam-Lobby: 8 Clients verbinden sich, Kapseln bewegen sich synchron durch einen grauen Raum. Multiplayer zuerst — niemals "später einbauen", daran sterben diese Projekte.
Slime-Bewegung + Verwandlung in weiße Props, Tempo-Stufen.
Malsystem: Eyedropper, Pinsel, Grundieren, Striche als Events synchronisiert.
Rundenloop: Prep-/Jagd-Timer, Fressen, Freischalt-Tabelle, Rotations-Timer mit Tropf-Strafe, Sieg/Tod.
Sucher-Kit: Paintball-Gun, Splatter, Cooldown, Elimination, Spectator-Modus.
Map 1 als Graybox, danach Kenney-Verkleidung.
Playtest mit der Community (~100 Leute). Hier fällt die Kenney-vs-Synty-Entscheidung.
Klone + Tausch-Teleport. Zuletzt gebaut, zuerst gestrichen.


Begleitregel ab Schritt 1: Jedes Feature wird auf zwei echten Rechnern getestet — Desyncs existieren nur im Netz, nicht im Editor.


16. Offene Punkte (bewusst noch nicht entschieden)


Spielname
Steam-Preis
Sound & Musik (komplett unbehandelt)
Exakte finale Prop-Liste (15 Slots — die Beispiele in Abschnitt 8 sind Vorschläge)
Kamera-Detail: Third-Person ist gesetzt; ein FPP-Toggle wie bei MC ist eine V2-Frage
Playtest-Protokoll (was genau gemessen wird)



17. Referenz-Kontext (Einordnung, nicht bindend)


Meccha Chameleon: Vorbild für das Malsystem (Eyedropper, Farbrad, HSV, Kamera-Rotation). Hat keine Verwandlung; vergibt Punkte über Sichtlinie zum Sucher — beides übernehmen wir nicht.
Prop Hunt: Vorbild für die Verwandlung. Hat kein Malen und keine Progression.
Unsere Identität: Verwandeln + Malen + Fress-Progression + Rotationszwang. Überleben statt Punkte.