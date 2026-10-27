# Voxie 1.0.0 — iPhone + Apple Watch Walkietalkie

Geel-zwarte iPhone- en Apple Watch-app. Houd de gele knop ingedrukt om maximaal 15 seconden op te nemen; laat los om te verzenden. Wanneer twee apparaten Voxie open hebben en elkaar als vriend hebben toegevoegd, speelt de ontvanger de spraakblokken automatisch af. Het maakt niet uit of een deelnemer een iPhone of Apple Watch gebruikt.

## Projectinstellingen

| Instelling | Waarde |
| --- | --- |
| iPhone-app / App Store-bundle | `nl.lrvdlinden.Voxie` |
| Watch Bundle ID | `nl.lrvdlinden.Voxie.watchkitapp` |
| Widget/Control Bundle ID | `nl.lrvdlinden.Voxie.watchkitapp.control` |
| Development Team | `EU3UY476T6` |
| Marketingversie | `1.0.0` |
| Build | `1` |
| Type | iPhone-companion met zelfstandig werkende Watch-app |
| Backend | Supabase Edge Function |

## Supabase automatisch installeren met GitHub Actions

Voxie bevat al de publieke configuratie voor project `qalcgyzkicazkmzsouiu`. De database en Edge Function kunnen pas worden gepubliceerd nadat jij de volgende **twee GitHub Actions Secrets** hebt ingesteld:

1. Open [Supabase Account → Access Tokens](https://supabase.com/dashboard/account/tokens). Maak een persoonlijke access token met rechten om jouw project te beheren. Kopieer hem één keer en voeg hem toe in GitHub via **Settings → Secrets and variables → Actions → New repository secret** met naam **`SUPABASE_ACCESS_TOKEN`**.
2. Open [Supabase project → Database Settings](https://supabase.com/dashboard/project/qalcgyzkicazkmzsouiu/settings/database). Gebruik het databasewachtwoord dat je bij het aanmaken van het project hebt ingesteld. Weet je dit niet meer, reset het in Supabase en bewaar het nieuwe wachtwoord als GitHub Secret **`SUPABASE_DB_PASSWORD`**.
3. Open GitHub → **Actions → Deploy Voxie backend → Run workflow**. Deze workflow past beide SQL-migraties toe en publiceert de Edge Function. Een push naar `main` die `supabase/` wijzigt, start dezelfde workflow automatisch.
4. Controleer de uitkomst in de Actions-logs en open `https://qalcgyzkicazkmzsouiu.supabase.co/functions/v1/voxie/health`. Bij succes verschijnt `{ "ok": true }`.

**Plak deze secrets nooit in de code, README, GitHub-issues of deze chat.** De publieke publishable key hoort wel in de app; de database/admin-sleutels niet. Voor de verificatie van Apple-aanmeldingen gebruikt de Edge Function Apple's openbare JWKS; er is daarvoor geen Apple private key nodig.

Wanneer de eerste migratie al handmatig is uitgevoerd en niet in Supabase's migratiehistorie staat, controleer dan de workflow voordat je `db push` opnieuw draait. De SQL is grotendeels additief, maar migratiehistorie moet correct worden bijgehouden.

> De Edge Function gebruikt Supabase's server-side secret key uit de serveromgeving. Zet de `service_role` of `sb_secret_...` **nooit** in de Watch-app, je GitHub-repository of een publieke build. In `supabase/config.toml` staat `verify_jwt = false` omdat Voxie eigen willekeurige bearer tokens gebruikt, die de functie aan gehashte tokens in de database koppelt. Dit is een ontwikkelontwerp dat vóór publieke lancering een security review en rate limiting vereist.

De server controleert Apple ID-tokens met Apple's ondertekende sleutelset en gebruikt korte, eenmalige login-challenges. Hij bewaart een unieke, niet-hoofdlettergevoelige gebruikersnaam, de gekozen avatar en een vriendenlijst per Apple-account. Na Apple-aanmelding op de iPhone ontvangt de gekoppelde Watch een eigen sessie via WatchConnectivity. Audioframes worden na 30 seconden niet meer opgehaald. Voor publieke lancering zijn aanvullende beveiligingsmaatregelen nodig, zoals rate limiting, sessie-intrekking, quotas, opschoning en een privacybeleid. Audio is HTTPS-versleuteld, maar niet end-to-end-versleuteld.

## Xcode

1. Open `Voxie.xcodeproj` op je Mac met Xcode 27 en selecteer je Development Team.
2. Activeer onder **Signing & Capabilities** de capability **Sign in with Apple** voor de iPhone-target. De entitlements zijn aan het project gekoppeld; controleer de Apple Developer App IDs/provisioning profiles. De Watch krijgt zijn sessie via WatchConnectivity en heeft geen Apple-aanmeldscherm. Activeer eventueel **Push Notifications** voor APNs.
3. Kies voor testen op Apple Watch het gedeelde schema **Voxie Watch App** en een echte Watch. Kies voor iPhone **Voxie App Store** en een iPhone-simulator of fysiek toestel. Controleer alle drie targets.
4. Start Voxie en kies **Log in met Apple**. De app neemt automatisch contact op met de Voxie-server. Kies op iPhone/iPad een **unieke gebruikersnaam**, zoals `leon_01`, en eventueel een profielfoto.
5. Vrienden nodigen elkaar uit met `@gebruikersnaam`, niet met een code. Accepteren en weigeren kan op iPhone/iPad of Watch.
6. Houd de gele knop ingedrukt, spreek, laat los. De ander hoort het bericht automatisch wanneer Voxie open is.

Op de Apple Watch zijn twee pagina's: **Praten** en **Vrienden**. Instellingen, gebruikersnaam en profielfoto pas je uitsluitend aan in de iPhone/iPad-app. De identiteit en vriendenlijst worden via het online Voxie-profiel gesynchroniseerd wanneer op beide apparaten hetzelfde Apple-account wordt gebruikt. Dit is **geen directe iCloud/CloudKit-databasesynchronisatie**. Je hoeft geen iCloud-ID aan anderen bekend te maken en de app kan niet automatisch iCloud-accounts van contacten uitlezen.

### Archiveren voor TestFlight en de App Store

1. Selecteer bovenaan in Xcode **Voxie App Store** (niet **Voxie Watch App** of **Voxie Control**).
2. Selecteer **Any iOS Device** / generieke iOS-archiefbestemming.
3. Kies **Product → Archive** en open het nieuwe archief in Organizer. Gebruik **Distribute App → TestFlight & App Store**.
4. Selecteer in App Store Connect de iOS-appregistratie met bundle-ID `nl.lrvdlinden.Voxie`. Deze build bevat een **werkende iPhone-app en de Apple Watch-app**.

De iPhone-app gebruikt een expliciete `Voxie iPhone App/Info.plist` met `UILaunchScreen` en alle vier iPad-schermstanden (`UISupportedInterfaceOrientations~ipad`). Dat is nodig voor iPad-multitaskingvalidatie in App Store Connect. De iPhone ondersteunt portret en beide liggende schermstanden.

Het iPhone-target gebruikt `com.apple.product-type.application`. De Watch-app gebruikt `WKRunsIndependentlyOfCompanionApp = YES` en verwijst met `WKCompanionAppBundleIdentifier` naar de iPhone-app. De Watch kan technisch zelfstandig draaien, maar het Voxie-profiel wordt eerst op de iPhone/iPad ingesteld. Beide targets behouden versie `1.0.0`, build `6`.

### Eerste configuratie en ontvangstkeuze (build 6)

- Na Apple-aanmelding toont de iPhone/iPad een eenmalige configuratiepagina zolang er geen gebruikersnaam is. Sla je unieke naam op, kies **Ontvangst** (Watch, iPhone/iPad of beide) en tik pas daarna op **Start Voxie**. De configuratiepagina blijft tijdens deze stappen open. Bij volgende starts wordt het profiel eerst geladen; een bestaand profiel opent direct het hoofdscherm.
- De Watch toont bij een nog oningesteld profiel een verwijzing naar de iPhone/iPad. Meld de Watch aan met hetzelfde Apple-account om dat profiel te kunnen ophalen; automatische overdracht van aanmeldgegevens via WatchConnectivity is nog niet geïmplementeerd.
- In iPhone/iPad-instellingen staat **Berichten ontvangen op**: alleen Apple Watch, alleen iPhone/iPad, of beide. Dit wordt per account op de server opgeslagen. De keuze stuurt de **spraakontvangst terwijl de apps open zijn**; achtergrondmeldingen of automatisch afspelen in een gesloten app zijn nog niet aanwezig.
- Er staat geen extra vast icoon linksboven in de hoofdschermen op iPhone/iPad of Watch; het eigenlijke app-icoon op het beginscherm blijft behouden. Een optionele profielfoto staat afzonderlijk in de profielkaart.
- Onder Instellingen → **Account en gegevens verwijderen** kan de gebruiker na bevestiging het serveraccount definitief wissen. Daarbij verwijdert de database via referentiële cascading de vrienden, uitnodigingen, sessies en spraakframes, en wist de iPhone de lokale sessie uit de Keychain. De Watch wordt bij een volgende servercontrole automatisch afgemeld. Apple biedt geen betrouwbare uninstall-callback: het verwijderen van alleen de app kan het online account **niet** automatisch wissen. Verwijder daarom eerst het account via de app en daarna desgewenst de app. Voxie gebruikt geen eigen CloudKit/iCloud-database.

### Stapsgewijze installatie en Watch-koppeling (build 8)

Op iPhone loopt de eerste installatie door zeven stappen: welkom (met veegbare introductie), Log in met Apple, unieke gebruikersnaam, profielfoto of overslaan, ontvangst op Watch/iPhone/beide, afronding en **Start Voxie**. Op volgende starts opent een geconfigureerd account direct het vriendenoverzicht. Daar is geen praatknop; kies eerst een vriend om zijn of haar gesprekscherm te openen. De Watch werkt hetzelfde: vriend kiezen toont pas dan de praatknop.

Op de Watch is **geen Log in met Apple**-scherm meer beschikbaar. De iPhone vraagt met zijn bestaande sessie een aparte Watch-sessie aan bij de server (`POST /v3/watch-session`) en draagt deze via Apple's WatchConnectivity over aan de gekoppelde Watch. De Watch slaat die lokaal op in de Keychain. Zolang dat niet gebeurd is, toont de Watch alleen de verwijzing naar de iPhone. Hiervoor moet de Watch gekoppeld zijn aan de iPhone en WatchConnectivity de context kunnen bezorgen; de overdracht kan enige tijd duren. Op een iPad kan niet rechtstreeks een Apple Watch worden gekoppeld.

### Vriendschapsverzoeken op het beginscherm (build 11)

- Nieuwe inkomende verzoeken verschijnen direct in een geel blok op het iPhone/iPad-beginscherm, met Accepteren en Weigeren.
- Na verwerken verschijnt duidelijke feedback; bij een fout blijft het verzoek opnieuw te behandelen.
- Een bestaande Apple-sessie toont na het verversen van het profiel niet langer de oude statusmelding “Log in met Apple”.
- Bij het accepteren slaat de server eerst de vriendschap op voordat het uitnodigingsverzoek op geaccepteerd gaat.

### Website en deelbare profiellinks (build 10)

- De statische marketingwebsite in `website/` is voorbereid voor **https://voxie.online** met de boodschap *Binnenkort in de App Store*. De vormgeving gebruikt Voxie's geel-zwart.
- In de iPhone/iPad-app deelt een gebruiker zijn profiel als `https://voxie.online/u/<gebruikersnaam>`.
- Universal Links (of vanaf de website de `voxie://u/<gebruikersnaam>`-link) openen de iOS-app. Voordat er iets gebeurt, vraagt de app bevestiging om een **vriendschapsverzoek te sturen**. De ontvanger moet het verzoek daarna nog zelf accepteren. Er is geen automatische vriendschap zonder wederzijdse toestemming.
- Activeer op het iPhone App ID de Apple capability **Associated Domains** met `applinks:voxie.online`. Host de meegeleverde `website/.well-known/apple-app-site-association` via HTTPS zonder redirects.
- De workflow `.github/workflows/deploy-website.yml` publiceert `website/` via FTPS na het toevoegen van GitHub Secrets `FTP_SERVER`, `FTP_PORT`, `FTP_USER`, `FTP_PASSSWORD` (ook `FTP_PASSWORD` wordt ondersteund). Optionele repositoryvariabelen zijn `FTP_PROTOCOL` en `FTP_REMOTE_DIR`. Raadpleeg `website/README.md`.

### Kortlevende spraakblokken

**Build 9:** de downloadtermijn is 30 seconden. Bij de keuze *beide* moet het audioblok door zowel iPhone als Watch lokaal zijn ontvangen, en minstens één van de twee moet het afspelen hebben voltooid, vóórdat de server het blok verwijdert. Als een apparaat offline blijft, verloopt de downloadtermijn zonder beide bevestigingen.

Spraak wordt in deze versie **nog kortstondig** als PCM-blokken in `voxie_audio_frames` opgeslagen. Bij ontvangstinstelling **beide** bevestigen iPhone én Watch eerst dat het blok lokaal is ontvangen. Zodra daarnaast minstens één apparaat het afspelen bevestigt, wordt het blok van de server verwijderd. Als een apparaat offline is, vervalt de downloadmogelijkheid uiterlijk 30 seconden na verzending. Verlopen blokken worden bij een volgende API-aanroep verwijderd. Voor automatische opschoning bij inactiviteit: schakel de Supabase-database-extensie **pg_cron** in via Dashboard → Database → Extensions. De migratie `20261027030000_audio_expiry_30s.sql` plant een opruimtaak die iedere minuut blokken ouder dan 30 seconden verwijdert. Is pg_cron pas na de migratie ingeschakeld, voer dan de `cron.schedule`-opdracht uit die migratie uit in de SQL Editor. De feitelijke verwijdering kan door het minuutinterval tot circa één minuut later plaatsvinden, maar de API biedt verlopen audio niet meer aan.

Dit is **niet** hetzelfde als audio nooit naar Supabase sturen: daarvoor is een latere WebRTC/Realtime-audiotransportlaag zonder databaseopslag nodig. Een afspeelbevestiging wordt verzonden op de audioplayer-callback `dataPlayedBack`, niet al tijdens het downloaden.

Voor App Store-validatie staat `WKRunsIndependentlyOfCompanionApp` **niet** naast `WKWatchOnly`, want die twee waarden mogen niet beide `YES` zijn. De WidgetKit-extensie bevat daarnaast expliciet `CFBundleDisplayName = Voxie Control`.

**Let op:** na het wijzigen van de Watch bundle-ID naar `nl.lrvdlinden.Voxie.watchkitapp` moet Xcode mogelijk nieuwe automatisch beheerde App IDs/provisioning profiles maken. Als build `1` al voor dezelfde appversie naar App Store Connect is geüpload, is voor een volgende upload een hoger buildnummer nodig.

## Apple Watch-integratie

- Het geel-zwarte app-icoon heeft een eigen handradio/V-symbool.
- De **Voxie Control**-extensie levert een snelle knop voor het Bedieningspaneel, de Smart Stack en de Action Button op ondersteunde Watches.
- WidgetKit-complicaties: rond, rechthoekig, inline en hoek.
- `WKRunsIndependentlyOfCompanionApp = YES`: de Watch-app draait ook zonder een geïnstalleerde iPhone-app.

## Wat nog niet hetzelfde werkt als Apple's oude app

- Automatisch spraak afspelen terwijl Voxie volledig gesloten is, wordt door watchOS niet gegarandeerd en is niet geïmplementeerd.
- APNs-device-tokenregistratie zit in de Watch-code, maar de Supabase Edge Function verstuurt momenteel **geen** APNs-pushmeldingen. Daarvoor zijn Apple APNs-credentials, een uitbreiding van de functie en een echte Watch-test nodig.
- De spraak gaat pas na loslaten naar de ontvanger. Het is snelle om-en-om-spraak, geen continue full-duplex of Apple's FaceTime-techniek.
- Op iPhone wordt audio alleen opgehaald zolang Voxie actief is. Er is geen volledige achtergrond- of gesloten-app-audiofunctionaliteit.
- Vrienden automatisch herkennen op basis van hun privé-iCloud-ID is niet mogelijk via de huidige Apple-API's. Uitnodigen gebeurt op gebruikersnaam.
- De profielgegevens worden via de Voxie-server gesynchroniseerd na Apple-aanmelding, niet via CloudKit; iCloud Key-Value Storage wordt bewust niet gebruikt voor geheime sessietokens.
- Er is nog geen volledige Xcode- of audiotest op fysieke Watches uitgevoerd binnen deze omgeving.

## Bestanden

- `Voxie iPhone App/` — iPhone-interface en eigen app-icoon
- `Voxie Watch App/` — SwiftUI, gedeelde audio-/netwerkcode, vrienden, Supabase-configuratie, APNs-registratie en app-icoon
- `Voxie Control/` — Watch Control Center-regelaar en complicaties
- `supabase/functions/voxie/` — serverloze API
- `supabase/migrations/` — database + RLS
