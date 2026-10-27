# Voxie website — voxie.online

Static, responsive marketing site + shareable profile landing pages.

## Public profile links

Share URLs look like `https://voxie.online/u/leon`. Apache `.htaccess` rewrites
the `/u/…` route to `index.html`, where `app.js` displays the invitation landing
page. In Safari/Messages, a Universal Link may open the iOS app directly. From
the website, **Open in Voxie** uses the `voxie://u/leon` custom scheme. The app
always asks for confirmation before sending the invitation. The intended friend
must subsequently accept it in Voxie.

The website deliberately does not fetch user photos or private profile details
from the backend. It only displays the handle already present in the shared URL.

## Publish over FTPS via GitHub Actions

1. Point `voxie.online` to your web host and enable HTTPS (valid certificate).
2. Add these **GitHub Actions repository secrets** (Settings → Secrets and
   variables → Actions): `FTP_SERVER`, `FTP_PORT`, `FTP_USER`, `FTP_PASSSWORD`.
   The normally spelled `FTP_PASSWORD` also works. Do not put values in Git.
3. Optional **repository variables** (not secrets): `FTP_PROTOCOL` (`ftps` by
   default, or `ftp` if your host does not support encryption) and
   `FTP_REMOTE_DIR` (`./` by default; often `/public_html/` or similar).
4. Run **Actions → Deploy voxie.online website → Run workflow**, or push a
   change under `website/` to `main`. The workflow uploads only the `website/`
   folder via `SamKirkland/FTP-Deploy-Action`.

For Apache hosting, ensure `.htaccess` and `.well-known` are uploaded and that
mod_rewrite is available. For Nginx, configure an equivalent `/u/*` fallback to
`/index.html`. Do not redirect `/.well-known/apple-app-site-association`.

## Enable Universal Links

The iPhone app's Associated Domains entitlement contains `applinks:voxie.online`.
The static file at `/.well-known/apple-app-site-association` references
`EU3UY476T6.nl.lrvdlinden.Voxie`. **Also enable the Associated Domains
capability** on that App ID in Apple Developer/Xcode and rebuild the iOS app.
Ensure `https://voxie.online/.well-known/apple-app-site-association` responds
with `200 OK` as JSON, without redirects. Apple's CDN can take time to refresh.

There is no App Store product URL yet; the site honestly says **Binnenkort**.
