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

De server controleert Apple ID-tokens met Apple's ondertekende sleutelset en gebruikt korte, eenmalige login-challenges. Hij bewaart een unieke, niet-hoofdlettergevoelige gebruikersnaam, de gekozen avatar en een vriendenlijst per Apple-account. iPhone/iPad en Watch kunnen na afzonderlijke Apple-aanmelding hetzelfde profiel zien. Audioframes worden na 15 seconden niet meer opgehaald. Voor publieke lancering zijn aanvullende beveiligingsmaatregelen nodig, zoals rate limiting, accountverwijdering, sessie-intrekking, quotas, opschoning en een privacybeleid. Audio is HTTPS-versleuteld, maar niet end-to-end-versleuteld.

## Xcode

1. Open `Voxie.xcodeproj` op je Mac met Xcode 27 en selecteer je Development Team.
2. Activeer onder **Signing & Capabilities** de capability **Sign in with Apple** voor de iPhone- en de Watch-targets. De entitlements zijn al aan het project gekoppeld; controleer dat je Apple Developer App IDs/provisioning profiles de capability ondersteunen. Activeer eventueel **Push Notifications** voor APNs.
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

Het iPhone-target gebruikt `com.apple.product-type.application`. De Watch-app gebruikt `WKRunsIndependentlyOfCompanionApp = YES` en verwijst met `WKCompanionAppBundleIdentifier` naar de iPhone-app. De Watch blijft hierdoor zelfstandig functioneren, ook wanneer de iPhone-app niet is geïnstalleerd. Beide targets behouden versie `1.0.0`, build `1`.

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
