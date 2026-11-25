package routes

// flowShellScript is what every flow page runs before its own script: the
// language and theme shared with the other pages on this origin, the passkey
// ceremony, and the sign-in that ends in a session held in this closure.
//
// The session is never written to localStorage, sessionStorage or a cookie
// (BROWSER.md §3.4). A stored token is the easiest thing on these pages to
// steal; TestFlowPagesNeverStoreTheSession holds the line.
const flowShellScript = `
var $ = function (id) { return document.getElementById(id); };
function show(node, on) { node.hidden = !on; }
function el(tag, cls, text) {
  var n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = text;
  return n;
}

var STRINGS = {
  en: {
    'lang.label': 'DE', 'lang.switch': 'Auf Deutsch wechseln',
    'theme.light': 'Switch to light theme', 'theme.dark': 'Switch to dark theme',
    'field.email': 'Email', 'field.code': 'Code', 'field.totp': 'Authenticator code',
    'app.open': 'Open in the Revoked app', 'app.note': 'The app checks the server before anything is entered.',
    'auth.title': 'Account',
    'auth.lead': 'Answers are kept in an account on this server, where they can be changed or revoked. Sign-in uses a passkey.',
    'auth.leadAnswers': 'Sign-in uses a passkey. A saved passkey is offered in the email field.',
    'auth.continue': 'Continue',
    'auth.signin': 'Sign in with passkey',
    'offer.leadCode': function (email) { return 'No passkey was used. A new account for ' + email + ' starts with a confirmation code sent there.'; },
    'offer.lead': function (email) { return 'No passkey was used. A new account for ' + email + ' gets a passkey on this device.'; },
    'offer.go': 'Create account', 'offer.retry': 'Try a passkey again',
    'offer.note': 'A passkey on a phone works through the QR code the browser offers.',
    'code.lead': function (email) { return 'Confirmation code sent to ' + email + '.'; },
    'code.go': 'Next',
    'code.note': 'The code is valid for 10 minutes. Missing emails may be in the spam folder.',
    'code.resendIn': function (s) { return 'New code in ' + s + ' s'; },
    'code.resend': 'Send new code',
    'save.lead': 'A passkey replaces the password and is unlocked with a fingerprint, face or PIN.',
    'save.go': 'Save passkey',
    'totp.lead': 'This account asks for a code from its authenticator app.',
    'totp.go': 'Sign in',
    'signedIn': function (email) { return 'Signed in as ' + email + '.'; },
    'signOut': 'Sign out',
    'stop.origin': 'Passkeys only work at this server’s own address.',
    'stop.browser': 'This browser does not support passkeys.',
    'stop.setup': 'This server requires an authenticator app, which is set up in the Revoked app.',
    'err.codeFormat': 'The code consists of 6 digits.',
    'err.exists': 'This device already has a passkey for this account.',
    'err.noPasskeyEmail': 'No passkey was used. A passkey on a phone works through the QR code the browser offers. For a new account, an email address is needed first.',
    'err.noPasskeyClosed': 'No passkey was used. One on a phone works through the QR code the browser offers.',
    'err.unknownRemoved': 'This passkey belongs to an account that no longer exists. The password manager was asked to remove it.',
    'err.unknownManual': 'This passkey belongs to an account that no longer exists. It can be deleted in the password manager.',
    'err.refused': 'The server refused the request.', 'err.generic': 'An unexpected error occurred.',
    'err.load': 'The page could not be loaded.',

    'ws.default': 'Personal',
    'sh.untitled': 'Shared items',
    'sh.from': function (n) { return 'From ' + n + ', as reported by the server.'; },
    'sh.auth': 'Opening requires a verified identity of an account on this server. Sign-in uses a passkey.',
    'sh.password': 'Password', 'sh.open': 'Open shared information',
    'sh.sealed': 'Encrypted. Opened with the full link or in the Revoked app.',
    'sh.download': 'Download',
    'sh.empty': 'No shared information.',
    'sh.signedNote': function (n) { return 'Opened as ' + n + '. The sender sees this identity.'; },
    'id.title': 'Identity',
    'id.lead': 'A verified identity is required. In this browser, it is derived from the passkey and never stored.',
    'id.unlock': 'Use passkey',
    'id.newLead': 'This passkey has no identity yet. The name is shown to whoever receives what is signed with it.',
    'id.name': 'Name', 'id.create': 'Create identity',
    'id.ready': function (n) { return 'Signed as ' + n + '. The key exists only for this visit.'; },
    'id.otherAccount': 'This passkey belongs to another account.',
    'id.noPrf': 'This passkey cannot derive an identity. Identities are used in the Revoked app.',
    'id.unsupported': 'This browser cannot derive an identity. Identities are used in the Revoked app.',
    'id.revoked': 'The identity of this passkey was revoked.',
    'si.title': function (h) { return 'Sign in to ' + h; },
    'si.lead': function (h) { return h + ' requests sign-in with Revoked. What it receives is chosen here or in the Revoked app.'; },
    'si.auth': 'Sign-in uses a passkey. A saved passkey is offered in the email field.',
    'si.problem': 'Sign-in cannot continue',
    'si.problemLead': 'This service did not identify itself correctly. Sign-in was stopped and nothing was shared.',
    'si.account': 'Account',
    'si.asks': 'Requested information',
    'si.scope.profile': 'Name', 'si.scope.email': 'Email address', 'si.scope.revoked_identity': 'Verified identity',
    'si.identityNeeds': 'Shared once an identity of this passkey is in use.',
    'si.noName': 'No name',
    'si.entries': 'Vault entries',
    'si.notShared': 'Not shared',
    'si.allow': 'Allow', 'si.decline': 'Decline',
    'si.approveNote': 'Allowing asks for the passkey once more, unless the identity already signs.',
    'si.paused': function (h) { return h + ' is paused for this account. It is reactivated in the Revoked app.'; },
    'si.back': 'Return to the service',
    'si.returning': function (d) { return 'Signed in here before, last on ' + d + '.'; },
    'cn.title': function (n) { return 'Connect ' + n; },
    'cn.lead': function (n, h) { return n + ' at ' + h + ' requests a connection to this account.'; },
    'cn.problem': 'Connection cannot continue',
    'cn.problemLead': 'This tool did not identify itself correctly. Nothing was connected.',
    'cn.address': 'Address', 'cn.name': 'Name', 'cn.nameNote': 'Given by the tool',
    'cn.actions': 'Permissions',
    'cn.section': function (n) { return 'Keep records in “' + n + '”'; },
    'cn.sectionNote': 'A section named after the tool. It reads all records there and changes only its own.',
    'cn.vault': 'Read unencrypted vault records',
    'cn.vaultNote': 'Every unencrypted record, including records outside its sections. Values it reads leave Revoked.',
    'cn.revoke': 'Turn off its links and requests', 'cn.revokeNote': 'Revoke links and requests it proposed.',
    'cn.handOver': 'Get the links approved for it', 'cn.handOverNote': 'Show, open or copy links approved for this tool.',
    'cn.why': function (n) { return 'Reason given by ' + n; },
    'cn.expiry': 'Connections expire after 90 days unless renewed. They can be paused or disconnected at any time.',
    'cn.connect': 'Connect', 'cn.decline': 'Decline',
    'req.untitled': 'Request',
    'req.from': function (name) { return 'Requested by ' + name + ', as reported by the server.'; },
    'req.server': 'Server', 'req.expires': 'Expires', 'req.never': 'No expiry',
    'req.fields': 'Requested information',
    'req.required': 'Required', 'req.optional': 'Optional',
    'req.fromVault': 'From the vault', 'req.typeInstead': 'Enter a different value', 'req.useVault': 'Use the vault value',
    'req.typed': 'Entered here',
    'req.fileApp': 'Files are answered in the Revoked app.',
    'req.password': 'Request password', 'req.identifier': 'Identifier',
    'req.identifierHint': 'The identifier the requester gave out with this request.',
    'req.send': 'Send answer', 'req.update': 'Update answer',
    'req.existing': 'This account already answered this request. Sending again updates that answer.',
    'req.appOnlyFile': 'This request asks for a file. It is answered in the Revoked app.',
    'req.sent': 'Answer sent', 'req.updated': 'Answer updated',
    'req.sentLead': 'The answer is a link in this account. It can be changed, paused or revoked at any time.',
    'req.manage': 'Manage answers',
    'req.missing': function (label) { return label + ' is required.'; },
    'req.closed': 'No longer available',
    'pin.trusted': function (d) { return d + ' is trusted in this browser.'; },
    'pin.changed': function (d) { return 'The server key of ' + d + ' differs from the one this browser remembered. The server may have been replaced.'; },
    'pin.trust': 'Trust in this browser', 'pin.untrust': 'Stop trusting',

    'ans.title': 'Answers',
    'ans.lead': 'Answers this account gave to requests.',
    'ans.none': 'No answers',
    'ans.noneLead': 'Answers given to requests from this account appear here.',
    'ans.answered': function (d) { return 'Answered ' + d; },
    'ans.expires': function (d) { return 'Expires ' + d; },
    'ans.pause': 'Pause', 'ans.resume': 'Resume', 'ans.revoke': 'Revoke',
    'ans.revokeAsk': 'Revoked answers can no longer be read by the requester. This cannot be undone.',
    'ans.revokeGo': 'Revoke answer', 'ans.cancel': 'Cancel',
    'ans.edit': 'Edit', 'ans.save': 'Save',
    'ans.editNote': 'The value changes in the vault and in every link that shares it.',
    'ans.sealed': 'Encrypted. Changed in the Revoked app.',
    'ans.gone': 'No longer in the vault',
    'ans.saved': 'Value saved',
    'status.active': 'Active', 'status.paused': 'Paused', 'status.revoked': 'Revoked', 'status.expired': 'Expired'
  },
  de: {
    'lang.label': 'EN', 'lang.switch': 'Switch to English',
    'theme.light': 'Zum hellen Design wechseln', 'theme.dark': 'Zum dunklen Design wechseln',
    'field.email': 'E-Mail', 'field.code': 'Code', 'field.totp': 'Code aus der Authenticator-App',
    'app.open': 'In der Revoked-App öffnen', 'app.note': 'Die App prüft den Server, bevor etwas eingegeben wird.',
    'auth.title': 'Konto',
    'auth.lead': 'Antworten liegen in einem Konto auf diesem Server, wo sie geändert oder widerrufen werden können. Die Anmeldung erfolgt mit einem Passkey.',
    'auth.leadAnswers': 'Die Anmeldung erfolgt mit einem Passkey. Ein gespeicherter Passkey wird im E-Mail-Feld angeboten.',
    'auth.continue': 'Weiter',
    'auth.signin': 'Mit Passkey anmelden',
    'offer.leadCode': function (email) { return 'Es wurde kein Passkey verwendet. Ein neues Konto für ' + email + ' beginnt mit einem Bestätigungscode an diese Adresse.'; },
    'offer.lead': function (email) { return 'Es wurde kein Passkey verwendet. Ein neues Konto für ' + email + ' erhält einen Passkey auf diesem Gerät.'; },
    'offer.go': 'Konto erstellen', 'offer.retry': 'Passkey erneut versuchen',
    'offer.note': 'Ein Passkey auf einem Handy funktioniert über den QR-Code, den der Browser anbietet.',
    'code.lead': function (email) { return 'Bestätigungscode gesendet an ' + email + '.'; },
    'code.go': 'Weiter',
    'code.note': 'Der Code ist 10 Minuten gültig. Fehlende E-Mails können im Spam-Ordner liegen.',
    'code.resendIn': function (s) { return 'Neuer Code in ' + s + ' s'; },
    'code.resend': 'Neuen Code senden',
    'save.lead': 'Ein Passkey ersetzt das Passwort und wird mit Fingerabdruck, Gesicht oder PIN entsperrt.',
    'save.go': 'Passkey speichern',
    'totp.lead': 'Dieses Konto verlangt einen Code aus seiner Authenticator-App.',
    'totp.go': 'Anmelden',
    'signedIn': function (email) { return 'Angemeldet als ' + email + '.'; },
    'signOut': 'Abmelden',
    'stop.origin': 'Passkeys funktionieren nur unter der Adresse dieses Servers.',
    'stop.browser': 'Dieser Browser unterstützt keine Passkeys.',
    'stop.setup': 'Dieser Server verlangt eine Authenticator-App, die in der Revoked-App eingerichtet wird.',
    'err.codeFormat': 'Der Code besteht aus 6 Ziffern.',
    'err.exists': 'Dieses Gerät hat bereits einen Passkey für dieses Konto.',
    'err.noPasskeyEmail': 'Es wurde kein Passkey verwendet. Ein Passkey auf einem Handy funktioniert über den QR-Code, den der Browser anbietet. Für ein neues Konto wird zuerst eine E-Mail-Adresse benötigt.',
    'err.noPasskeyClosed': 'Es wurde kein Passkey verwendet. Einer auf einem Handy funktioniert über den QR-Code, den der Browser anbietet.',
    'err.unknownRemoved': 'Dieser Passkey gehört zu einem Konto, das es nicht mehr gibt. Der Passwort-Manager wurde gebeten, ihn zu entfernen.',
    'err.unknownManual': 'Dieser Passkey gehört zu einem Konto, das es nicht mehr gibt. Er kann im Passwort-Manager gelöscht werden.',
    'err.refused': 'Der Server hat die Anfrage abgelehnt.', 'err.generic': 'Ein unerwarteter Fehler ist aufgetreten.',
    'err.load': 'Die Seite konnte nicht geladen werden.',

    'ws.default': 'Persönlich',
    'sh.untitled': 'Geteilte Einträge',
    'sh.from': function (n) { return 'Von ' + n + ', laut Angabe des Servers.'; },
    'sh.auth': 'Das Öffnen verlangt eine verifizierte Identität eines Kontos auf diesem Server. Die Anmeldung erfolgt mit einem Passkey.',
    'sh.password': 'Passwort', 'sh.open': 'Geteilte Informationen öffnen',
    'sh.sealed': 'Verschlüsselt. Wird mit dem vollständigen Link oder in der Revoked-App geöffnet.',
    'sh.download': 'Herunterladen',
    'sh.empty': 'Keine geteilten Informationen.',
    'sh.signedNote': function (n) { return 'Geöffnet als ' + n + '. Der Absender sieht diese Identität.'; },
    'id.title': 'Identität',
    'id.lead': 'Eine verifizierte Identität ist erforderlich. In diesem Browser wird sie aus dem Passkey abgeleitet und nie gespeichert.',
    'id.unlock': 'Passkey verwenden',
    'id.newLead': 'Dieser Passkey hat noch keine Identität. Der Name wird allen angezeigt, die damit Signiertes erhalten.',
    'id.name': 'Name', 'id.create': 'Identität erstellen',
    'id.ready': function (n) { return 'Signiert als ' + n + '. Der Schlüssel besteht nur für diesen Besuch.'; },
    'id.otherAccount': 'Dieser Passkey gehört zu einem anderen Konto.',
    'id.noPrf': 'Aus diesem Passkey lässt sich keine Identität ableiten. Identitäten werden in der Revoked-App verwendet.',
    'id.unsupported': 'Dieser Browser kann keine Identität ableiten. Identitäten werden in der Revoked-App verwendet.',
    'id.revoked': 'Die Identität dieses Passkeys wurde widerrufen.',
    'si.title': function (h) { return 'Bei ' + h + ' anmelden'; },
    'si.lead': function (h) { return h + ' fordert eine Anmeldung mit Revoked an. Was der Dienst erhält, wird hier oder in der Revoked-App festgelegt.'; },
    'si.auth': 'Die Anmeldung erfolgt mit einem Passkey. Ein gespeicherter Passkey wird im E-Mail-Feld angeboten.',
    'si.problem': 'Anmeldung nicht möglich',
    'si.problemLead': 'Dieser Dienst hat sich nicht korrekt ausgewiesen. Die Anmeldung wurde abgebrochen, es wurde nichts geteilt.',
    'si.account': 'Konto',
    'si.asks': 'Angefragte Angaben',
    'si.scope.profile': 'Name', 'si.scope.email': 'E-Mail-Adresse', 'si.scope.revoked_identity': 'Verifizierte Identität',
    'si.identityNeeds': 'Wird geteilt, sobald eine Identität dieses Passkeys verwendet wird.',
    'si.noName': 'Kein Name',
    'si.entries': 'Tresor-Einträge',
    'si.notShared': 'Nicht geteilt',
    'si.allow': 'Erlauben', 'si.decline': 'Ablehnen',
    'si.approveNote': 'Beim Erlauben wird der Passkey ein weiteres Mal abgefragt, sofern nicht bereits die Identität signiert.',
    'si.paused': function (h) { return h + ' ist für dieses Konto pausiert. Die Reaktivierung erfolgt in der Revoked-App.'; },
    'si.back': 'Zurück zum Dienst',
    'si.returning': function (d) { return 'Hier bereits angemeldet, zuletzt am ' + d + '.'; },
    'cn.title': function (n) { return n + ' verbinden'; },
    'cn.lead': function (n, h) { return n + ' unter ' + h + ' fordert eine Verbindung mit diesem Konto an.'; },
    'cn.problem': 'Verbindung nicht möglich',
    'cn.problemLead': 'Dieses Werkzeug hat sich nicht korrekt ausgewiesen. Es wurde nichts verbunden.',
    'cn.address': 'Adresse', 'cn.name': 'Name', 'cn.nameNote': 'Vom Werkzeug angegeben',
    'cn.actions': 'Berechtigungen',
    'cn.section': function (n) { return 'Einträge in „' + n + '“ ablegen'; },
    'cn.sectionNote': 'Ein Bereich mit dem Namen des Werkzeugs. Es liest alle Einträge darin und ändert nur eigene.',
    'cn.vault': 'Unverschlüsselte Tresor-Einträge lesen',
    'cn.vaultNote': 'Alle unverschlüsselten Einträge, auch außerhalb seiner Bereiche. Gelesene Werte verlassen Revoked.',
    'cn.revoke': 'Seine Links und Anfragen beenden', 'cn.revokeNote': 'Links und Anfragen widerrufen, die es vorgeschlagen hat.',
    'cn.handOver': 'Für es freigegebene Links erhalten', 'cn.handOverNote': 'Für dieses Werkzeug freigegebene Links anzeigen, öffnen oder kopieren.',
    'cn.why': function (n) { return 'Begründung von ' + n; },
    'cn.expiry': 'Verbindungen laufen nach 90 Tagen ab, sofern sie nicht erneuert werden. Sie können jederzeit pausiert oder getrennt werden.',
    'cn.connect': 'Verbinden', 'cn.decline': 'Ablehnen',
    'server.approval_invalid': 'Diese Freigabe ist abgelaufen, wurde bereits verwendet oder galt etwas anderem.',
    'server.oidc_request_invalid': 'Diese Anmeldung ist abgelaufen oder wurde bereits verwendet. Sie muss beim Dienst neu gestartet werden.',
    'server.connection_paused': 'Diese Verbindung ist pausiert. Die Reaktivierung erfolgt in der Revoked-App.',
    'req.untitled': 'Anfrage',
    'req.from': function (name) { return 'Angefragt von ' + name + ', laut Angabe des Servers.'; },
    'req.server': 'Server', 'req.expires': 'Läuft ab', 'req.never': 'Kein Ablauf',
    'req.fields': 'Angefragte Angaben',
    'req.required': 'Erforderlich', 'req.optional': 'Optional',
    'req.fromVault': 'Aus dem Tresor', 'req.typeInstead': 'Anderen Wert eingeben', 'req.useVault': 'Wert aus dem Tresor verwenden',
    'req.typed': 'Hier eingegeben',
    'req.fileApp': 'Dateien werden in der Revoked-App beantwortet.',
    'req.password': 'Passwort der Anfrage', 'req.identifier': 'Kennung',
    'req.identifierHint': 'Die Kennung, die zusammen mit dieser Anfrage weitergegeben wurde.',
    'req.send': 'Antwort senden', 'req.update': 'Antwort aktualisieren',
    'req.existing': 'Dieses Konto hat diese Anfrage bereits beantwortet. Erneutes Senden aktualisiert diese Antwort.',
    'req.appOnlyFile': 'Diese Anfrage verlangt eine Datei. Sie wird in der Revoked-App beantwortet.',
    'req.sent': 'Antwort gesendet', 'req.updated': 'Antwort aktualisiert',
    'req.sentLead': 'Die Antwort ist ein Link in diesem Konto. Sie kann jederzeit geändert, pausiert oder widerrufen werden.',
    'req.manage': 'Antworten verwalten',
    'req.missing': function (label) { return label + ' ist erforderlich.'; },
    'req.closed': 'Nicht mehr verfügbar',
    'pin.trusted': function (d) { return d + ' ist in diesem Browser als vertrauenswürdig gespeichert.'; },
    'pin.changed': function (d) { return 'Der Serverschlüssel von ' + d + ' weicht von dem ab, den dieser Browser gespeichert hat. Der Server wurde möglicherweise ersetzt.'; },
    'pin.trust': 'In diesem Browser vertrauen', 'pin.untrust': 'Nicht mehr vertrauen',

    'ans.title': 'Antworten',
    'ans.lead': 'Antworten dieses Kontos auf Anfragen.',
    'ans.none': 'Keine Antworten',
    'ans.noneLead': 'Antworten dieses Kontos auf Anfragen erscheinen hier.',
    'ans.answered': function (d) { return 'Beantwortet am ' + d; },
    'ans.expires': function (d) { return 'Läuft ab am ' + d; },
    'ans.pause': 'Pausieren', 'ans.resume': 'Fortsetzen', 'ans.revoke': 'Widerrufen',
    'ans.revokeAsk': 'Widerrufene Antworten kann der Anfragende nicht mehr lesen. Dies kann nicht rückgängig gemacht werden.',
    'ans.revokeGo': 'Antwort widerrufen', 'ans.cancel': 'Abbrechen',
    'ans.edit': 'Bearbeiten', 'ans.save': 'Speichern',
    'ans.editNote': 'Der Wert ändert sich im Tresor und in jedem Link, der ihn teilt.',
    'ans.sealed': 'Verschlüsselt. Änderung in der Revoked-App.',
    'ans.gone': 'Nicht mehr im Tresor',
    'ans.saved': 'Wert gespeichert',
    'status.active': 'Aktiv', 'status.paused': 'Pausiert', 'status.revoked': 'Widerrufen', 'status.expired': 'Abgelaufen',
    'server.signups_disabled': 'Dieser Server nimmt keine neuen Registrierungen an.',
    'server.rate_limited': 'Zu viele Versuche. Nach kurzer Wartezeit erneut versuchen.',
    'server.passkey_email_invalid': 'Die E-Mail-Adresse ist ungültig.',
    'server.passkey_email_taken': 'Für diese E-Mail-Adresse existiert bereits ein Konto.',
    'server.passkey_ceremony_invalid': 'Dieser Vorgang ist abgelaufen oder wurde bereits abgeschlossen.',
    'server.passkey_verification_failed': 'Der Passkey konnte nicht geprüft werden.',
    'server.email_verification_required': 'Die E-Mail-Adresse muss zuerst mit dem gesendeten Code bestätigt werden.',
    'server.email_code_invalid': 'Dieser Code ist falsch, abgelaufen oder wurde zu oft versucht.',
    'server.email_code_too_soon': 'Gerade wurde ein Code an diese Adresse gesendet. Ein neuer kann nach einer Minute angefordert werden.',
    'server.email_send_failed': 'Die Bestätigungs-E-Mail konnte nicht gesendet werden.',
    'server.two_factor_code_invalid': 'Der Code ist falsch.',
    'server.two_factor_challenge_invalid': 'Diese Anmeldung ist abgelaufen.',
    'server.request_password_invalid': 'Das Passwort ist falsch.',
    'server.request_password_required': 'Diese Anfrage verlangt ein Passwort.'
  }
};
// The key the web tools use, so a choice made there holds here on the same
// origin.
var LANG_KEY = 'revoked.web.locale';
var lang = (function () {
  try {
    var saved = localStorage.getItem(LANG_KEY);
    if (saved === 'en' || saved === 'de') return saved;
  } catch (e) {}
  var langs = navigator.languages || [navigator.language || ''];
  for (var i = 0; i < langs.length; i++) if (/^de\b/i.test(langs[i])) return 'de';
  return 'en';
})();
function t(key) {
  var v = STRINGS[lang][key];
  if (v === undefined) v = STRINGS.en[key];
  if (typeof v === 'function') return v.apply(null, Array.prototype.slice.call(arguments, 1));
  return v === undefined ? key : v;
}
function serverMessage(data) {
  return (data.code && STRINGS[lang]['server.' + data.code]) || data.message || t('err.refused');
}
function formatDate(iso) {
  var d = new Date(iso);
  if (isNaN(d.getTime())) return '';
  return d.toLocaleDateString(lang === 'de' ? 'de-DE' : 'en-GB', { year: 'numeric', month: 'short', day: 'numeric' });
}

var ICONS = {
  'key': '<circle cx="7.5" cy="15.5" r="5.5"/><path d="m21 2-9.6 9.6M15.5 7.5l3 3L22 7l-3-3"/>',
  'alert': '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3z"/><path d="M12 9v4M12 17h.01"/>',
  'check': '<path d="M20 6 9 17l-5-5"/>',
  'mail': '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
  'arrow-right': '<path d="M5 12h14M12 5l7 7-7 7"/>',
  'inbox': '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
  'send': '<path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/>',
  'lock': '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
  'info': '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>',
  'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>',
  'moon': '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>'
};
function svg(name, size) {
  var s = size || 18;
  var box = document.createElement('span');
  box.innerHTML = '<svg width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || '') + '</svg>';
  return box.firstChild;
}
Array.prototype.forEach.call(document.querySelectorAll('i[data-i]'), function (n) {
  n.replaceWith(svg(n.getAttribute('data-i'), Number(n.getAttribute('data-s')) || 18));
});

var themeToggle = $('theme-toggle');
function isDark() {
  var current = document.documentElement.getAttribute('data-theme');
  if (current === 'dark') return true;
  if (current === 'light') return false;
  return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
}
function updateToggle() {
  themeToggle.textContent = '';
  themeToggle.appendChild(svg(isDark() ? 'sun' : 'moon', 16));
  themeToggle.setAttribute('aria-label', isDark() ? t('theme.light') : t('theme.dark'));
}
function applyTheme(theme) {
  if (theme === 'light' || theme === 'dark') document.documentElement.setAttribute('data-theme', theme);
  else document.documentElement.removeAttribute('data-theme');
  updateToggle();
}
var savedTheme = null;
try { savedTheme = localStorage.getItem('revoked_theme'); } catch (e) {}
applyTheme(savedTheme);
themeToggle.addEventListener('click', function () {
  var next = isDark() ? 'light' : 'dark';
  try { localStorage.setItem('revoked_theme', next); } catch (e) {}
  applyTheme(next);
});

// What is on screen, drawn again when the language changes.
var redraw = function () {};
var redrawAuth = function () {};
function applyLang() {
  document.documentElement.lang = lang;
  Array.prototype.forEach.call(document.querySelectorAll('[data-t]'), function (n) {
    n.textContent = t(n.getAttribute('data-t'));
  });
  $('lang-toggle').textContent = t('lang.label');
  $('lang-toggle').setAttribute('aria-label', t('lang.switch'));
  updateToggle();
}
$('lang-toggle').addEventListener('click', function () {
  lang = lang === 'de' ? 'en' : 'de';
  try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
  applyLang();
  redraw();
  redrawAuth();
});
applyLang();

function heading(title, lead, icon, tone) {
  $('title').textContent = title;
  $('lead').textContent = lead || '';
  document.title = title + ' · Revoked';
  var tile = $('tile');
  tile.className = 'hero-tile' + (tone ? ' ' + tone : '');
  tile.textContent = '';
  if (icon) tile.appendChild(svg(icon, 28));
}
function fail(message) { $('error-t').textContent = message; show($('error'), !!message); }
function callout(tone, icon, text) {
  var n = el('div', 'callout ' + tone);
  n.appendChild(svg(icon, 20));
  n.appendChild(el('span', '', text));
  return n;
}
function button(cls, label, onClick) {
  var b = el('button', cls);
  b.type = 'button';
  b.appendChild(el('span', 'spin'));
  b.appendChild(el('span', '', label));
  b.addEventListener('click', onClick);
  return b;
}
function busyWhile(b, work) {
  return async function () {
    if (b.disabled) return;
    b.disabled = true;
    b.classList.add('loading');
    try { await work(); } finally { b.disabled = false; b.classList.remove('loading'); }
  };
}

if (server.appLink) {
  $('open-app').href = server.appLink;
  show($('app-way'), true);
}

` + passkeyCeremonyScript + `

// ---- The session -----------------------------------------------------------
// Held here for this visit only. Reloading the page signs out.
var session = null;
async function api(method, path, body) {
  var headers = {};
  if (session) headers.Authorization = session.token;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  var res = await fetch(path, { method: method, headers: headers, body: body === undefined ? undefined : JSON.stringify(body) });
  var data = await res.json().catch(function () { return {}; });
  if (!res.ok) {
    var err = new Error(serverMessage(data));
    err.code = data.code || '';
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}
function listPath(collection, filter, extra) {
  return '/api/collections/' + collection + '/records?perPage=500&skipTotal=1&filter=' + encodeURIComponent(filter) + (extra || '');
}
function quoted(v) { return '"' + String(v).replace(/["\\]/g, '') + '"'; }

// ---- Signing in inside the flow (BROWSER.md §4.1) --------------------------
// One way in, as on the sign-in page: the email field offers a saved passkey,
// Continue asks for one anywhere, and only when none is used is a new account
// offered for the address.
function startSignIn(leadKey, onSignedIn, wantIdentity) {
  // Asked of the sign-in assertion when the flow will sign as an identity,
  // so the person is not asked for the passkey again for it.
  var prepare = wantIdentity ? withIdentityPrf : null;
  function keepPrf(credential) { if (wantIdentity) pendingPrf = identityPrfOf(credential); }
  var state = 'either';
  var codeSentTo = '', proof = '', resendAt = 0, resendTimer = null, totpChallenge = '';
  var autofill = null;
  var finished = false;

  function authFail(message) { $('auth-error-t').textContent = message; show($('auth-error'), !!message); }
  function currentEmail() { return $('email').value.trim().toLowerCase(); }
  function action(label, icon) {
    $('go-t').textContent = label;
    $('go-ic').textContent = '';
    $('go-ic').appendChild(svg(icon, 20));
  }

  if (!server.originOK) {
    if (/^(127\.0\.0\.1|\[::1\])$/.test(location.hostname)) {
      location.replace(location.protocol + '//localhost' + (location.port ? ':' + location.port : '') + location.pathname + location.search);
      return;
    }
    show($('auth'), true);
    $('auth-t').textContent = t('auth.title');
    authFail(t('stop.origin'));
    return;
  }
  if (!window.PublicKeyCredential || !window.crypto || !crypto.subtle) {
    show($('auth'), true);
    $('auth-t').textContent = t('auth.title');
    authFail(t('stop.browser'));
    return;
  }

  function render() {
    show($('auth'), true);
    $('auth-t').textContent = t('auth.title');
    show($('emailRow'), state === 'either' || state === 'offer' || state === 'email');
    show($('codeRow'), state === 'code' || state === 'totp');
    show($('resend'), state === 'code');
    show($('other'), state === 'offer');
    show($('go'), true);
    $('auth-note').textContent = '';
    $('email').setAttribute('autocomplete', state === 'either' ? 'username webauthn' : 'email');
    $('code').setAttribute('autocomplete', 'one-time-code');
    $('code-l').textContent = t(state === 'totp' ? 'field.totp' : 'field.code');
    if (state === 'either') {
      $('auth-lead').textContent = t(leadKey);
      action(t(server.signups ? 'auth.continue' : 'auth.signin'), server.signups ? 'arrow-right' : 'key');
      startAutofill();
    } else if (state === 'offer') {
      $('auth-lead').textContent = t(server.verifyEmail ? 'offer.leadCode' : 'offer.lead', currentEmail());
      action(t('offer.go'), 'arrow-right');
      $('other').textContent = t('offer.retry');
      $('auth-note').textContent = t('offer.note');
    } else if (state === 'code') {
      $('auth-lead').textContent = t('code.lead', codeSentTo);
      action(t('code.go'), 'arrow-right');
      $('auth-note').textContent = t('code.note');
      updateResend();
      if (!resendTimer && $('resend').disabled) resendTimer = setInterval(updateResend, 1000);
    } else if (state === 'save') {
      $('auth-lead').textContent = t('save.lead');
      action(t('save.go'), 'key');
    } else if (state === 'totp') {
      $('auth-lead').textContent = t('totp.lead');
      action(t('totp.go'), 'arrow-right');
    }
  }
  redrawAuth = function () { if (!finished) render(); };

  async function startAutofill() {
    if (autofill || finished || state !== 'either') return;
    if (!PublicKeyCredential.isConditionalMediationAvailable) return;
    var available = false;
    try { available = await PublicKeyCredential.isConditionalMediationAvailable(); } catch (e) {}
    if (!available || autofill || finished || state !== 'either') return;
    var controller = new AbortController();
    autofill = controller;
    try {
      var pair = await pkcePair();
      var r = await passkeySignIn(pair.challenge, prepare, { mediation: 'conditional', signal: controller.signal });
      if (autofill !== controller) return;
      autofill = null;
      keepPrf(r.credential);
      await redeem(r.result.code, pair.verifier);
    } catch (e) {
      if (autofill === controller) autofill = null;
      if (controller.signal.aborted || !e || e.name === 'AbortError' || e.name === 'NotAllowedError') return;
      authFail(e.message || t('err.generic'));
    }
  }
  async function stopAutofill() {
    if (!autofill) return;
    var controller = autofill;
    autofill = null;
    controller.abort();
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
  }

  async function redeem(code, verifier) {
    var answer;
    try {
      answer = await call('/api/passkeys/token', { code: code, verifier: verifier });
    } catch (e) {
      if (e && e.code === 'two_factor_required' && e.data && e.data.challenge) {
        totpChallenge = e.data.challenge;
        state = 'totp';
        $('code').value = '';
        render();
        $('code').focus();
        return;
      }
      throw e;
    }
    signedIn(answer);
  }
  function signedIn(answer) {
    // The account must set up an authenticator first, which only the app does;
    // every other route refuses it until then.
    if (answer.meta && answer.meta.twoFactorSetupRequired) {
      authFail(t('stop.setup'));
      show($('go'), false);
      return;
    }
    finished = true;
    session = { token: answer.token, user: answer.record };
    redrawAuth = function () {};
    show($('auth'), false);
    onSignedIn();
  }

  async function sendCode() {
    var email = currentEmail();
    var sent = await call('/api/passkeys/register/email', { email: email, locale: lang });
    codeSentTo = email;
    proof = '';
    resendAt = Date.now() + (sent.resendAfter || 60) * 1000;
    $('code').value = '';
    state = 'code';
    render();
    $('code').focus();
  }
  function updateResend() {
    var wait = Math.ceil((resendAt - Date.now()) / 1000);
    $('resend').disabled = wait > 0;
    $('resend').textContent = wait > 0 ? t('code.resendIn', wait) : t('code.resend');
    if (wait <= 0 && resendTimer) { clearInterval(resendTimer); resendTimer = null; }
  }
  async function register() {
    var pair = await pkcePair();
    var body = { email: currentEmail(), challenge: pair.challenge };
    if (proof) body.proof = proof;
    var r = await passkeyRegister(body);
    await redeem(r.result.code, pair.verifier);
  }

  var busy = false;
  $('go').addEventListener('click', async function () {
    if (busy || finished) return;
    busy = true;
    authFail('');
    $('go').disabled = true;
    $('go').classList.add('loading');
    try {
      if (state === 'either') {
        await stopAutofill();
        var pair = await pkcePair();
        var r = await passkeySignIn(pair.challenge, prepare);
        keepPrf(r.credential);
        await redeem(r.result.code, pair.verifier);
      } else if (state === 'offer' || state === 'email') {
        if (!$('email').checkValidity() || !currentEmail()) { $('email').focus(); return; }
        if (server.verifyEmail) await sendCode();
        else { state = 'save'; render(); await register(); }
      } else if (state === 'code') {
        var code = $('code').value.replace(/\s+/g, '');
        if (!/^[0-9]{6}$/.test(code)) throw new Error(t('err.codeFormat'));
        proof = (await call('/api/passkeys/register/verify', { email: codeSentTo, code: code })).proof;
        state = 'save';
        render();
      } else if (state === 'save') {
        await register();
      } else if (state === 'totp') {
        var totp = $('code').value.replace(/\s+/g, '');
        if (!/^[0-9]{6}$/.test(totp)) throw new Error(t('err.codeFormat'));
        signedIn(await call('/api/passkeys/token/2fa', { challenge: totpChallenge, code: totp }));
      }
    } catch (e) {
      if (e && (e.code === 'email_verification_required' || e.code === 'passkey_email_taken' || e.code === 'passkey_email_invalid')) {
        proof = ''; codeSentTo = '';
        state = 'email';
        render();
      }
      if (e && e.code === 'two_factor_challenge_invalid') { state = 'either'; render(); }
      if (e && e.name === 'NotAllowedError' && state === 'either') {
        if (server.signups && currentEmail() && $('email').checkValidity()) {
          state = 'offer';
          render();
        } else {
          authFail(t(server.signups ? 'err.noPasskeyEmail' : 'err.noPasskeyClosed'));
          if (server.signups) $('email').focus();
        }
      } else if (e && e.name === 'InvalidStateError') {
        authFail(t('err.exists'));
      } else if (!e || e.name !== 'NotAllowedError') {
        authFail((e && e.message) || t('err.generic'));
      }
    } finally {
      busy = false;
      $('go').disabled = false;
      $('go').classList.remove('loading');
      if (!finished) startAutofill();
    }
  });
  $('other').addEventListener('click', function () {
    state = 'either';
    render();
    $('go').click();
  });
  $('resend').addEventListener('click', async function () {
    authFail('');
    $('resend').disabled = true;
    try { await sendCode(); } catch (e) { authFail((e && e.message) || t('err.generic')); updateResend(); }
  });
  $('email').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('go').click(); });
  $('code').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('go').click(); });
  $('code').addEventListener('input', function () {
    var digits = $('code').value.replace(/[^0-9]/g, '').slice(0, 6);
    if (digits !== $('code').value) $('code').value = digits;
    if (digits.length === 6) $('go').click();
  });
  $('email').addEventListener('input', function () {
    if (state === 'offer' && !currentEmail()) { state = 'either'; render(); }
  });
  render();
}

// An account has no workspace until its first run asks for one, and every
// flow here acts in the active workspace. The page does what
// that first run does: a workspace this account administers, made active.
async function ensureWorkspace() {
  if (session.user.activeWorkspace) return;
  var raw = new Uint8Array(4);
  crypto.getRandomValues(raw);
  var slug = 'ws-' + Array.prototype.map.call(raw, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  var ws = await api('POST', '/api/collections/workspaces/records', { name: t('ws.default'), slug: slug });
  session.user = await api('PATCH', '/api/collections/users/records/' + encodeURIComponent(session.user.id),
    { activeWorkspace: ws.id, activeRole: 'admin' });
}

// A user-verified passkey assertion bound to one ticket and purpose
// (BROWSER.md §4.5): what the browser approves with where the app signs with
// an identity key.
async function passkeyApprove(purpose, ticket) {
  var begin = await api('POST', '/api/approvals/begin', { purpose: purpose, ticket: ticket });
  var options = begin.options.publicKey;
  options.challenge = decode(options.challenge);
  (options.allowCredentials || []).forEach(function (c) { c.id = decode(c.id); });
  var credential = await navigator.credentials.get({ publicKey: options });
  var done = await api('POST', '/api/approvals/finish', { session: begin.session, credential: credentialJSON(credential) });
  return done.approval;
}
function checkRow(label, detail, checked, disabled) {
  var row = el('label', 'check-row');
  var box = el('input');
  box.type = 'checkbox';
  box.checked = !!checked;
  box.disabled = !!disabled;
  row.appendChild(box);
  var text = el('span', 'check-t');
  text.appendChild(el('span', 'entry-t', label));
  if (detail) text.appendChild(el('span', 'entry-reason', detail));
  row.appendChild(text);
  row.box = box;
  return row;
}
function selectOf(options, selected) {
  var sel = el('select');
  options.forEach(function (o) {
    var opt = el('option', '', o.label);
    opt.value = o.value;
    if (o.value === selected) opt.selected = true;
    sel.appendChild(opt);
  });
  return sel;
}

// ---- Identities from a passkey (BROWSER.md §4.8) --------------------------
// A passkey with the PRF extension returns the same secret for the same input
// on every device it is synced to. HKDF turns it into a P-256 private key,
// which lives in this closure as a non-extractable key for this visit: it is
// computed again at every ceremony and never stored or sent. Its public key is
// registered as an identity of kind "passkey" and certified like any other.
//
// The key is as safe as this page: a server that serves altered script can
// compute it (E2EE.md, threat model). The app's identities do not carry that
// limit.
` + passkeyIdentityScript + `
var pendingPrf = null;
var identity = null;

function withIdentityPrf(options) {
  options.extensions = Object.assign({}, options.extensions, { prf: { eval: { first: IDENTITY_PRF_SALT } } });
  return options;
}
function identityPrfOf(credential) {
  var ext = credential.getClientExtensionResults ? credential.getClientExtensionResults() : null;
  var first = ext && ext.prf && ext.prf.results && ext.prf.results.first;
  return first ? new Uint8Array(first) : null;
}
function identityError(key) { var e = new Error(t(key)); e.code = key; return e; }

// The secret from a passkey of the signed-in account. The assertion is not
// sent anywhere: only the authenticator's PRF output is used, and the user
// handle says whose passkey answered.
async function identityPrf() {
  if (pendingPrf) { var kept = pendingPrf; pendingPrf = null; return kept; }
  var credential = await navigator.credentials.get({ publicKey: withIdentityPrf({
    challenge: crypto.getRandomValues(new Uint8Array(32)),
    rpId: location.hostname,
    userVerification: 'required'
  }) });
  var handle = credential.response && credential.response.userHandle;
  if (!handle || new TextDecoder().decode(handle) !== session.user.id) throw identityError('id.otherAccount');
  var prf = identityPrfOf(credential);
  if (!prf) throw identityError('id.noPrf');
  return prf;
}

// Resolves with the identity this passkey holds for the signed-in account:
// { id, name } when registered, or { unregistered: true } until it is.
async function unlockIdentity() {
  var key = await deriveIdentityKey(await identityPrf());
  var list = await api('GET', listPath('identities', 'user = ' + quoted(session.user.id) + ' && kind = "passkey"'));
  var match = (list.items || []).filter(function (i) { return String(i.publicKey).trim() === key.publicPem.trim(); })[0];
  identity = { key: key, id: match ? match.id : '', name: match ? match.name : '', active: !match || match.status === 'active' };
  if (match && match.status !== 'active') throw identityError('id.revoked');
  return identity;
}
async function registerIdentity(name) {
  // The first identity of an account is its primary one, which is what a
  // service is told under revoked_identity.
  var others = await api('GET', listPath('identities', 'user = ' + quoted(session.user.id) + ' && status = "active"'));
  var created = await api('POST', '/api/collections/identities/records', {
    name: name, publicKey: identity.key.publicPem, kind: 'passkey',
    user: session.user.id, workspace: session.user.activeWorkspace,
    isPrimary: !(others.items || []).length
  });
  identity.id = created.id;
  identity.name = created.name;
  return identity;
}

async function identitySign(message) {
  return identitySignWith(identity.key.privateKey, message);
}

// The step a flow shows before it signs: unlock with the passkey, and name the
// identity the first time this passkey makes one.
function identityStep(onReady) {
  var box = el('div', 'entry');
  box.appendChild(el('span', 'entry-t', t('id.title')));
  if (identity && identity.id) {
    box.appendChild(el('p', 'entry-reason', t('id.ready', identity.name)));
    return box;
  }
  if (identity && !identity.id) {
    box.appendChild(el('p', 'entry-reason', t('id.newLead')));
    var label = el('label', 'field');
    label.appendChild(el('span', '', t('id.name')));
    var input = identity.nameInput || el('input');
    identity.nameInput = input;
    input.type = 'text';
    input.maxLength = 120;
    label.appendChild(input);
    box.appendChild(label);
    var create = button('big small', t('id.create'), null);
    create.addEventListener('click', busyWhile(create, async function () {
      fail('');
      if (!input.value.trim()) { input.focus(); return; }
      try { await registerIdentity(input.value.trim()); onReady(); }
      catch (e) { fail((e && e.message) || t('err.generic')); }
    }));
    box.appendChild(create);
    return box;
  }
  box.appendChild(el('p', 'entry-reason', t('id.lead')));
  var unlock = button('big small', t('id.unlock'), null);
  unlock.addEventListener('click', busyWhile(unlock, async function () {
    fail('');
    try { await unlockIdentity(); onReady(); }
    catch (e) { if (!e || e.name !== 'NotAllowedError') fail((e && e.message) || t('err.generic')); }
  }));
  box.appendChild(unlock);
  return box;
}

// A line saying who is signed in, with the way out: dropping the session is
// all signing out is, since nothing was stored.
function signedInLine() {
  var row = el('div', 'row');
  var who = el('p', 'fine left', t('signedIn', (session.user && session.user.email) || ''));
  who.style.flex = '1 1 auto';
  row.appendChild(who);
  var out = el('button', 'text-btn', t('signOut'));
  out.type = 'button';
  out.addEventListener('click', function () { session = null; location.reload(); });
  row.appendChild(out);
  return row;
}
`
