# Drop – Leergut-Abholung in Stuttgart

Uni-Projekt (Entrepreneurial Thinking). Drop verbindet Leute, die Pfandflaschen und Altglas loswerden wollen, mit Sammlern in der Nähe. Sammler behalten das Pfand und bekommen für Altglas eine kleine Vergütung (bar oder PayPal).

- **App:** https://rubenfahrion.github.io/drop-app/
- **Demo ohne Konto:** https://rubenfahrion.github.io/drop-app/demo.html

## Aufbau
- `index.html` – die App (HTML, CSS, JavaScript in einer Datei)
- `demo.html` – Demo-Version mit Beispieldaten, speichert nur auf dem Gerät
- `supabase/schema.sql` – Datenbank: Tabellen, Sicherheitsregeln, Abläufe
- Backend: [Supabase](https://supabase.com) (Konten, Datenbank, Foto-Speicher, Live-Updates)
- Karte: [Leaflet](https://leafletjs.com) mit Kartendaten von © OpenStreetMap-Mitwirkenden
- Adresssuche: OpenStreetMap Nominatim

## Datenschutz im Ablauf
Die genaue Adresse steht in einer eigenen Tabelle und ist nur für Abgeber und den Sammler sichtbar, der die Abholung angenommen hat. Auf der Karte erscheint für alle anderen nur ein ungefährer Punkt (± 250 m).
