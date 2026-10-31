# Voxie 1.0.0 — iPhone + Apple Watch Walkietalkie

Geel-zwarte iPhone/iPad-beheerapp en Apple Watch-walkietalkie. Beheer je Apple-account, vrienden en instellingen op iPhone/iPad. Spreken en luisteren kan uitsluitend op Apple Watch: houd daar de gele knop maximaal 15 seconden vast en laat los om je opname te versturen. De ontvanger hoort de spraak automatisch terwijl Voxie actief is op diens Watch.

## Projectinstellingen

| Instelling | Waarde |
| --- | --- |
| iPhone-app / App Store-bundle | `nl.lrvdlinden.Voxie` |
| Watch Bundle ID | `nl.lrvdlinden.Voxie.watchkitapp` |
| Widget/Control Bundle ID | `nl.lrvdlinden.Voxie.watchkitapp.control` |
| Development Team | `EU3UY476T6` |
| Marketingversie | `1.0.0` |
| Build | `20` |
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

### Build 20 — Walkietalkie-ontwerp en pushmeldingen

**Nieuw Watch-ontwerp, naar Apple's Walkietalkie-app**
- Startscherm: schakelaar **Walkietalkie** (beschikbaar) bovenaan, daaronder grote afgeronde kaarten per vriend: **geel** = je kunt praten, **grijs** = niet beschikbaar of uitgenodigd (sectie *Uitgenodigde vrienden*). Uitnodigingen staan bovenaan met **Sta toe** / **Weiger**. Veeg naar links op een vriend voor de verwijderknop (kruisje). Onderaan **Voeg vrienden toe**.
- Tik op een vriend: groot geel praatscherm. Houd vast om te praten, laat los om te versturen (max. 15 s). Tijdens praten gloeit de knop; daarna *Verbinden…* → *Verzonden*.
- Digital Crown regelt het afspeelvolume (met volume-indicator).
- Piepje en tik op de pols bij begin en einde van praten en van ontvangen.
- Als een vriend praat verschijnt zijn of haar foto met pulserende gele ringen en *praat…*.
- **Tik om te praten** (onder *Voeg vrienden toe*): tik één keer om te beginnen en nog eens om te versturen.

**Pushmeldingen**
- Als iemand tegen je praat, krijgt je Watch direct een melding: *@naam — praat met je, tik om te luisteren*, met eigen Voxie-piepje. Tik erop: Voxie opent dat gesprek en speelt het bericht meteen af.
- Staat Voxie al open, dan komt er geen banner maar wordt het bericht direct afgespeeld.
- Ben je niet beschikbaar, dan krijg je *@naam wil met je praten* (net als bij Apple). Ook een nieuwe vriendschapsuitnodiging geeft een melding.
- Niet-afgespeelde spraak blijft nu **2 minuten** op de server staan (was 30 s), zodat een later aangetikte melding het hele bericht nog afspeelt. Daarna wordt hij verwijderd.

**Wat je hiervoor eenmalig moet doen**
1. Apple Developer → Identifiers → `nl.lrvdlinden.Voxie.watchkitapp` → vink **Push Notifications** aan. (Optioneel: **Time Sensitive Notifications**, dan komen meldingen ook door een Focus heen.) In Xcode staat `aps-environment` nu in `VoxieWatch.entitlements`; laat automatische signing het profiel vernieuwen.
2. Maak bij Apple Developer → Keys een **APNs**-sleutel (.p8) als je die nog niet hebt, en zet in GitHub → Settings → Secrets → Actions: `APNS_AUTH_KEY_P8` (volledige inhoud van de .p8), `APNS_KEY_ID`, `APNS_TEAM_ID` = `EU3UY476T6`.
3. Draai GitHub Actions → **Deploy Voxie backend** (gebeurt ook automatisch bij deze push). Die past migratie `20261031000000_watch_alerts.sql` toe en publiceert de functie.
4. Sta op de Watch meldingen toe voor Voxie. Een build vanuit Xcode registreert zich als `sandbox`, TestFlight/App Store als `production`; de server kiest per Watch automatisch de juiste APNs-omgeving (de oude repo-variabele `APNS_ENVIRONMENT` is niet meer nodig).

**Grens van watchOS (eerlijk):** geen enkele app van derden mag op een gesloten of geschorste Apple Watch zelf geluid gaan afspelen. Apple's eigen Walkietalkie kon dat met systeemrechten, en Apple heeft die app in watchOS 27 stopgezet. Voxie doet daarom wat wél mag: direct een melding met geluid en tik op de pols, en meteen afspelen zodra je de melding aantikt of Voxie open is.

### Build 19 — Watch-koppeling en audio gerepareerd

- **Watch bleef op “Stel Voxie in op iPhone” hangen.** De Watch las de WatchConnectivity-context vóórdat de sessie geactiveerd was (dan is die leeg) en kreeg een al eerder verzonden context daarna nooit meer. De context wordt nu pas na activatie verwerkt.
- **Watch vraagt zelf om een sessie.** Bij openen stuurt de Watch een verzoek naar de iPhone (`sendMessage`). watchOS kan de iPhone-app daarvoor op de achtergrond wekken; de iPhone maakt met zijn eigen Keychain-sessie een Watch-sessie aan en antwoordt direct. Op de Watch staat ook een knop **Koppel opnieuw** met de actuele koppelstatus.
- WatchConnectivity wordt op de iPhone al bij het opstarten van de app geactiveerd (nodig voor wekken op de achtergrond), en de context wordt opnieuw verzonden zodra de Watch-app geïnstalleerd raakt.
- Een volume-update van de iPhone logde de Watch uit (context zonder token werd als “afgemeld” gelezen). Alleen een context met `configured` wijzigt nu nog de aanmelding.
- Een verlopen/ingetrokken Watch-sessie (401) vraagt automatisch een nieuwe aan bij de iPhone.
- **Netwerk- en audiolussen stopten bij iedere schermwissel**: `onAppear`/`onDisappear` stonden op een `Group` met voorwaardelijke inhoud en werden zo per scherm uitgevoerd. De levenscyclus zit nu op de scene (`scenePhase`). Een nieuw token wordt ingewisseld zonder de lussen te herstarten.
- **Eén geweigerd bericht blokkeerde alle volgende opnames**: een 403 (vriend niet beschikbaar) werd eindeloos opnieuw geprobeerd, waardoor de wachtrij nooit leeg raakte. Permanente weigeringen en berichten ouder dan 25 seconden worden nu verworpen met een duidelijke melding. Drukken terwijl een bericht nog verstuurd wordt geeft nu een melding in plaats van stil niets te doen.
- **Afspelen bleef stil na zelf praten**: het opname-engine en wijzigingen in de audioroute stoppen de afspeel-engine. Die wordt nu na opname, bij `AVAudioEngineConfigurationChange` en na een onderbreking herstart. De audiosessie wordt eenmalig geconfigureerd in plaats van bij elk frame.
- Geen microfoonroute (0 Hz-formaat) gaf een crash bij `installTap`; nu een foutmelding.
- Voxie Control-extensie gebruikt nu dezelfde versie/build als de app (App Store-validatie eiste dat).
- Nog steeds: ontvangen werkt alleen terwijl de Watch-app actief is (zie OS-beperking build 18). Test met twee fysieke Watches, elk gekoppeld aan een eigen iPhone met een eigen Apple-account.

### Build 18 — iPhone/iPad uitsluitend beheer; Apple Watch uitsluitend audio

- iPhone en iPad: aanmelden met Apple, profiel en profielfoto beheren, vrienden uitnodigen, accepteren en verwijderen, Watch-volume instellen en accountgegevens beheren. **Geen microfoon, geen afspelen, geen praatknop.** Een tik op een vriend verwijst naar spreken op de Watch.
- Apple Watch: vrienden kiezen en onder de gele knop spreken. De Watch ontvangt audioframes tijdens een actieve Voxie-sessie. De Watch verstuurt na het loslaten van de knop via de Voxie-server.
- Het configuratieproces noemt vanaf de eerste welkomslides uitsluitend de Apple Watch als audiotoestel. De zinloze iOS Push to Talk-activatie verdwijnt volledig. Bestaande profielen openen direct het beheerscherm.
- Backend: audio ophalen en afspeelbevestigen kan alleen voor `device=watch`; bestaande accounts met een oude telefoon-/beide-voorkeur worden als Watch-only behandeld. Een afgespeeld frame wordt na de Watch-bevestiging verwijderd; niet afgespeelde frames verlopen na 30 seconden.
- Watch-ontvangst: een frame wordt niet meer weggegooid wanneer de vriendenlijst nog bezig is met laden. De iOS-app start geen audio-netwerktaken meer.
- **OS-beperking:** Apple's `PushToTalk`-framework is hier geen oplossing voor een gesloten Apple Watch-app. watchOS kan apps schorsen en background-pushmeldingen vertragen. Dit project garandeert daarom ontvangst **alleen zolang de Watch-app actief is**. Het automatisch afspelen op een volledig afgesloten Watch is niet gerealiseerd.
- Validatie: broncode en ZIP kunnen lokaal statisch gecontroleerd worden, maar op deze Linux-omgeving is geen Xcode/watchOS SDK aanwezig om een echte Watch-build of end-to-end gesprek te testen.


### Build 17 — Apple Push to Talk-signing en websitehero

- De gemelde `com.apple.pushtotalk.instantiation error 3` komt **vóór servercommunicatie**: de ondertekende app mist de APNs-omgeving (`aps-environment`). Het iPhone-target zet deze nu expliciet op `development` voor Debug en `production` voor Release. De entitlement wordt in de codesignatuur opgenomen als het Apple Developer App ID en provisioningprofiel **Push Notifications** toestaan.
- Na het inschakelen van **Push Notifications** in Apple Developer moet Xcode mogelijk het provisioningprofiel vernieuwen. Controleer bij een echte iPhone-build met `codesign -d --entitlements :- /pad/naar/Voxie.app` dat `aps-environment` aanwezig is. Ontbreekt deze, dan kan de app niet zelf de signingmachtigingen herstellen.
- De app toont nu gerichte Nederlandse uitleg voor Apple-foutcodes 2, 3 en 4.
- De websitehero toont weer de eerdere iPhone/Watch-conceptmockups zonder iPad-overlap. De gele concentrische ringen bewegen rustig; bij gereduceerde beweging blijven ze stil.
- Let op: een geslaagde kanaalactivatie is nog geen bewijs van werkende achtergrondontvangst. Test daarna met twee echte apparaten en een correcte APNs `sandbox`- of `production`-serverconfiguratie.

### Build 16 — Push to Talk startvolgorde en welkomstinstructies

- Een tik op **Activeer Push to Talk** tijdens het initialiseren wordt onthouden; zodra Apple het kanaalbeheer beschikbaar maakt, wordt de eerder expliciet aangevraagde activatie uitgevoerd zolang de iPhone/iPad nog op de voorgrond is. De app blijft niet eindeloos met dezelfde voorbereidingsmelding staan: na twaalf seconden verschijnt concrete uitleg om Xcode-capabilities te controleren.
- De eerste welkomstslides leggen achtergrondontvangst uit. Na aanmelding, gebruikersnaam, profielfoto en ontvangstkeuze volgt een aparte pagina **Ontvang spraak op de achtergrond**, inclusief activeren of overslaan. Daarna volgt pas **Start Voxie**.
- Bestaande profielen houden hun afgeronde configuratie; de nieuwe stap is voor nieuwe installaties. Activatie achteraf blijft beschikbaar in Instellingen. Apple Watch ondersteunt de iOS Push to Talk-activatie zelf niet.
- Deze code moet op een fysieke iPhone/iPad worden geverifieerd met ingeschakelde Apple Push to Talk-capability; een Apple APNs-sleutel is daarnaast vereist voor de servermeldingen.


### Build 15 — iPhone/iPad Push to Talk en NL/EN website

- Op iPhone/iPad staat onder **Instellingen → Ontvangst wanneer de app gesloten is → Activeer Push to Talk** een expliciete Apple-kanaalactivatie. Het systeem kan de app daarna op de achtergrond starten voor een Push to Talk-bericht. iOS brengt de app niet automatisch zichtbaar naar de voorgrond. Apple Watch heeft hiervoor geen overeenkomstige iOS Push to Talk-capability; daar blijft de app voor ontvangst geopend.
- Onder **Signing & Capabilities** van het **iOS-target** moeten **Push to Talk**, **Background Modes → Push to Talk** en **Push Notifications** worden geactiveerd. Het Apple Developer App ID/provisioning profile moet deze capabilities ook toestaan. Zonder profiel kan Xcode een signingfout geven.
- Maak op [Apple Developer Keys](https://developer.apple.com/account/resources/authkeys/list) een APNs-geschikte Auth Key aan (download `.p8` eenmalig). Maak de GitHub Actions Secrets `APNS_AUTH_KEY_P8` (volledige inhoud van de `.p8`, inclusief BEGIN/END-regels), `APNS_KEY_ID` (de Apple Key ID) en `APNS_TEAM_ID` (`EU3UY476T6`). Workflow `Deploy Voxie backend` plaatst ze veilig in de Edge Function-secrets; geen private key komt in de app terecht.
- Standaard gebruikt de server productie-APNs (TestFlight/App Store). Voor rechtstreeks vanuit Xcode geïnstalleerde ontwikkelbuilds: zet de GitHub repositoryvariabele `APNS_ENVIRONMENT=sandbox` en herstart de backendworkflow. Zet vóór TestFlight terug op `production`. Bouw niet alleen op basis van configuratie aannames: test kanaalregistratie en achtergrondwekken op twee fysieke apparaten.
- De server bewaart per account uitsluitend de tijdelijke Push to Talk-token, niet de Apple private key. De eerste audio-upload van een spraakbericht triggert een `pushtotalk`-APNs-melding. Audioframes blijven maximaal 30 seconden beschikbaar volgens het bestaande afspeelbeleid.
- Website: NL als de apparaatlocale regio `NL` meldt (bijvoorbeeld `nl-NL` of `en-NL`), anders EN, met handmatige NL/EN-schakelaar. Beide fictieve schermen zijn in herkenbare iPhone- en Apple Watch-toestellen weergegeven. Het websitelogo blijft hetzelfde; uitsluitend de appiconen zijn nu geel met zwarte geluidsstrepen.


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

### Correctie 'network cancelled' (build 14)

- Een tijdelijk inactieve iPhone (bijvoorbeeld tijdens een systeemvenster) annuleert niet meer alle Voxie-netwerkverzoeken.
- Normale `URLError.cancelled` en taakannuleringen worden niet langer onterecht als netwerkfout getoond.
- Een naar de achtergrond gaande app bewaart niet-verzonden PCM tijdelijk in het geheugen totdat Voxie weer actief is; uitloggen wist de wachtrij wel.
- De audio- en Watch-layoutverbeteringen van build 13 zijn inbegrepen.

### Audio- en Watch-correcties (build 13)

- Inkomende spraak wordt ook afgespeeld wanneer een ándere vriend geselecteerd is, of wanneer niemand geselecteerd is. Zo worden frames niet langer stilzwijgend overgeslagen.
- Bij afspeelfouten houdt de ontvanger de cursor vast om opnieuw te proberen, en toont de app de foutmelding.
- Uitgaande PCM-frames worden pas verstuurd nadat de praatknop is losgelaten; bij een netwerkfout blijft het niet-verzonden frame lokaal in de wachtrij voor een nieuwe poging.
- De Watch heeft nu de grote gele, afgeronde praatknop in Apple Walkietalkie-stijl, met de terugknop **onder** de praatknop.
- Audio blijft via `AVAudioSession.Category.playAndRecord` spelen in de iOS-stilmodus, voor zover de audiouitvoer en het systeemvolume dat toelaten.
- Automatisch afspelen wanneer de app is afgesloten, of het automatisch openen van het zichtbare appvenster, is **niet** gerealiseerd. Voor achtergrondontvangst is Apple's officiële Push to Talk-framework met APNs-integratie nodig; iOS brengt apps niet vanzelf zichtbaar naar de voorgrond.
- De broncode van het gedeelde project `andreapianidev/WalkieTalkie` is bestudeerd als architectuurreferentie: diens MultipeerConnectivity-opzet is alleen voor nabije apparaten, niet voor Voxie's internetverbinding. De code heeft bovendien een niet-commerciële licentie en is niet overgenomen.

### Vrienden en geluid (build 12)

- Branding: het woordmerk is nu **voxie.** op iPhone en Apple Watch, in dezelfde stijl als de website.
- Appicon: zwarte achtergrond met vijf gele geluidsbalken op beide apparaten.
- Website: op verzoek fictieve, als concept aangeduide schermvoorbeelden voor iPhone én Apple Watch in de hero; geen emoji’s; App Store als duidelijke ‘binnenkort’-aankondiging zonder niet-bestaande downloadlink.
- iPhone/iPad: veeg een vriend naar links om een rode verwijderknop te tonen; verwijderen vraagt bevestiging. Er staat geen vaste verwijderknop meer naast iedere vriend.
- Instellingen op iPhone/iPad: Voxie-afspeelvolume van 10–100%, standaard 100%. De keuze wordt lokaal onthouden en via WatchConnectivity met een gekoppelde Apple Watch gedeeld.
- Het appvolume kan het fysieke systeemvolume niet verhogen of de hardware-volumeknoppen omzeilen.
- Spraak ontvangen bij een **gesloten** app is nog **niet geïmplementeerd**. Daarvoor is Apple's Push to Talk-framework met kanaalregistratie, APNs Push to Talk-notificaties, Apple-capabilities en extra serverimplementatie nodig. De huidige voorgrondpolling is daarvoor onvoldoende. iOS kan een app achtergronds activeren voor PTT-audio maar mag hem niet zonder gebruikersactie naar de voorgrond brengen.

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
