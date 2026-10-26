# Voxie 1.0.0 — Apple Watch Walkietalkie

Geel-zwarte, zelfstandige Apple Watch-app. Houd de gele knop ingedrukt om maximaal 15 seconden op te nemen; laat los om te verzenden. Als beide Watches Voxie open hebben en elkaar als vriend hebben toegevoegd, speelt de ontvanger de spraakblokken automatisch af.

## Projectinstellingen

| Instelling | Waarde |
| --- | --- |
| Watch Bundle ID | `nl.lrvdlinden.Voxie` |
| Widget/Control Bundle ID | `nl.lrvdlinden.Voxie.control` |
| Development Team | `EU3UY476T6` |
| Marketingversie | `1.0.0` |
| Build | `1` |
| Type | Standalone/watch-only |
| Backend | Supabase Edge Function |

## Supabase instellen

De Watch-code bevat de publieke configuratie voor project `qalcgyzkicazkmzsouiu`. **Het verstrekken van de project-URL en publishable key heeft de database en Edge Function nog niet geïnstalleerd.** Voer één keer de volgende stappen uit met je eigen Supabase-projectrechten:

1. Installeer de [Supabase CLI](https://supabase.com/docs/guides/cli) en meld je aan: `supabase login`.
2. Open deze projectmap in Terminal en koppel het project: `supabase link --project-ref qalcgyzkicazkmzsouiu`.
3. Controleer de SQL-migratie `supabase/migrations/20261026000000_voxie.sql` en voer `supabase db push` uit. Alternatief: plak de migratie in Supabase SQL Editor en voer deze uit.
4. Deploy de serverloze functie: `supabase functions deploy voxie --no-verify-jwt`.
5. Controleer via `https://qalcgyzkicazkmzsouiu.supabase.co/functions/v1/voxie/health` of de functie `{ "ok": true }` teruggeeft.

> De Edge Function gebruikt Supabase's server-side secret key uit de serveromgeving. Zet de `service_role` of `sb_secret_...` **nooit** in de Watch-app, je GitHub-repository of een publieke build. In `supabase/config.toml` staat `verify_jwt = false` omdat Voxie eigen willekeurige bearer tokens gebruikt, die de functie aan gehashte tokens in de database koppelt. Dit is een ontwikkelontwerp dat vóór publieke lancering een security review en rate limiting vereist.

De Edge Function en SQL-migratie verzorgen registratie, uitnodigingen, accepteren/weigeren, vrienden selecteren, beschikbaarheid en audioblokken. Audioframes worden na 15 seconden niet meer opgehaald. Voor een productieomgeving moet je ook periodieke opschoning configureren (zie de SQL-migratie), quotas, misbruikpreventie en privacybeleid toevoegen. De communicatie is via HTTPS versleuteld, maar niet end-to-end: Supabase verwerkt de spraakblokken.

## Xcode

1. Open `Voxie.xcodeproj` op je Mac met Xcode 27 en selecteer je Development Team.
2. Activeer eventueel de capability **Push Notifications** als je later APNs wilt gebruiken.
3. Kies een echte Apple Watch. Controleer zowel het target `Voxie Watch App` als `Voxie Control`.
4. Start Voxie, open instellingen, vul je naam in en tik op **Verbind**. Dit maakt een nieuwe identiteit met een eigen uitnodigingscode.
5. Laat een vriend zijn code delen, verstuur een uitnodiging en laat hem accepteren. Kies elkaar op beide horloges.
6. Houd de gele knop ingedrukt, spreek, laat los. De ander hoort het bericht automatisch wanneer Voxie open is.

## Apple Watch-integratie

- Het geel-zwarte app-icoon heeft een eigen handradio/V-symbool.
- De **Voxie Control**-extensie levert een snelle knop voor het Bedieningspaneel, de Smart Stack en de Action Button op ondersteunde Watches.
- WidgetKit-complicaties: rond, rechthoekig, inline en hoek.
- `WKWatchOnly = YES`: de app draait zonder een iOS-companion.

## Wat nog niet hetzelfde werkt als Apple's oude app

- Automatisch spraak afspelen terwijl Voxie volledig gesloten is, wordt door watchOS niet gegarandeerd en is niet geïmplementeerd.
- APNs-device-tokenregistratie zit in de Watch-code, maar de Supabase Edge Function verstuurt momenteel **geen** APNs-pushmeldingen. Daarvoor zijn Apple APNs-credentials, een uitbreiding van de functie en een echte Watch-test nodig.
- De spraak gaat pas na loslaten naar de ontvanger. Het is snelle om-en-om-spraak, geen continue full-duplex of Apple's FaceTime-techniek.
- Er is nog geen volledige Xcode- of audiotest op fysieke Watches uitgevoerd binnen deze omgeving.

## Bestanden

- `Voxie Watch App/` — SwiftUI, audio, vrienden, Supabase-configuratie, APNs-registratie en app-icoon
- `Voxie Control/` — Watch Control Center-regelaar en complicaties
- `supabase/functions/voxie/` — serverloze API
- `supabase/migrations/` — database + RLS
