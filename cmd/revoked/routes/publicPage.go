package routes

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"html/template"
	"net/url"
	"revoked/cmd/revoked/server"
	"revoked/util"
	"strings"

	"github.com/pocketbase/pocketbase/core"
)

// The page fetches nothing but its own origin and the two DoH resolvers it
// needs to check this server's DNS pin. No CDN, no analytics, no fonts: a
// secret-sharing page that phones anywhere else is a page that leaks slugs.
const pageCSP = "default-src 'none'; " +
	"style-src 'unsafe-inline'; " +
	"img-src 'self' data:; " +
	"connect-src 'self' https://cloudflare-dns.com https://dns.google; " +
	"base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

// pageData is everything the shell renders without spending a view.
type pageData struct {
	Slug             string
	Label            string
	Domain           string
	RootFingerprint  string
	SharerName       string
	SharerDomain     string
	SharerPrint      string
	Status           string
	Gated            bool
	RequireHandshake bool
	MaxViews         int
	ViewCount        int
	// template.URL: html/template blocks unknown schemes in href, and the
	// custom scheme is the whole point of the handoff. Safe to mark — both
	// halves are built here from a validated slug and the server's own domain.
	AppLink template.URL
	Nonce   string
}

// wantsHTML reports whether this is a browser asking for a page rather than a
// tool asking for data. Explicit format suffixes and the Accept ranking in
// resolveFormat both win over it, so `/s/x.json` in a browser still returns
// JSON.
func wantsHTML(accept string) bool {
	return strings.Contains(strings.ToLower(accept), "text/html")
}

// servePublicPage renders the read-only browser view of a share.
//
// It deliberately renders no values and claims no view: link unfurlers in chat
// apps fetch every URL that passes through them, and a page that claimed on
// load would let a preview bot silently spend a one-view link. The reader asks
// for the data explicitly, and only that request claims.
//
// It is also input-free. A gated share hands off to the app rather than drawing
// a password box, because a page that accepts secrets is a page worth cloning —
// and the app verifies the server it is talking to before anything is typed.
func servePublicPage(app core.App, re *core.RequestEvent, root *server.RootKey, link *core.Record, slug string) error {
	nonceBytes := make([]byte, 16)
	if _, err := rand.Read(nonceBytes); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	nonce := base64.StdEncoding.EncodeToString(nonceBytes)

	data := pageData{
		Slug:             slug,
		Label:            link.GetString(util.Fields.Link.Label),
		Domain:           root.Domain(),
		RootFingerprint:  root.Fingerprint(),
		Status:           link.GetString(util.Fields.Link.Status),
		Gated:            link.GetString(util.Fields.Link.Password) != "",
		RequireHandshake: link.GetBool(util.Fields.Link.RequireHandshake),
		MaxViews:         link.GetInt(util.Fields.Link.MaxViews),
		ViewCount:        link.GetInt(util.Fields.Link.ViewCount),
		AppLink:          template.URL("revoked://s/" + root.Domain() + "/" + url.PathEscape(slug)),
		Nonce:            nonce,
	}
	if id, err := app.FindRecordById(util.Coll.Identities, link.GetString(util.Fields.Link.Identity)); err == nil && id != nil {
		data.SharerName = id.GetString(util.Fields.Identity.Name)
		data.SharerDomain = id.GetString(util.Fields.Identity.DomainAtIssue)
		data.SharerPrint = id.GetString(util.Fields.Identity.Fingerprint)
	}

	var buf bytes.Buffer
	if err := pageTemplate.Execute(&buf, data); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}

	h := re.Response.Header()
	h.Set("Content-Security-Policy", strings.Replace(pageCSP, "style-src", "script-src 'nonce-"+nonce+"'; style-src", 1))
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	// The slug is the capability. A cached page in a shared browser, or a
	// proxy holding one, hands it to whoever looks next.
	h.Set("Cache-Control", "no-store")
	return writeText(re, "text/html", buf.String())
}

// Values are written with textContent, never innerHTML: a shared value is
// attacker-controlled text and this page is served from the operator's own
// origin, where an injected script would be same-origin with everything.
var pageTemplate = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>{{if .Label}}{{.Label}}{{else}}Shared{{end}} · revoked</title>
<style>
:root{color-scheme:light dark;--bg:#fff;--fg:#16161a;--mut:#6b6b74;--line:#e4e4e8;--sunk:#f4f4f6;--ok:#1d7a4c;--bad:#b3261e;--accent:#3f3d9e}
@media(prefers-color-scheme:dark){:root{--bg:#131316;--fg:#ececf0;--mut:#9a9aa4;--line:#2a2a30;--sunk:#1c1c21;--ok:#4ec38a;--bad:#ff6b6b;--accent:#a5a1ff}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.6 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;padding:24px}
main{max-width:640px;margin:0 auto}
h1{font-size:18px;margin:0 0 4px}
.mut{color:var(--mut)}.sm{font-size:12px}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;word-break:break-all}
.card{border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:12px}
.row{display:flex;gap:12px;align-items:center;justify-content:space-between}
.val{background:var(--sunk);border-radius:8px;padding:10px;margin-top:8px}
button{font:inherit;padding:8px 14px;border-radius:8px;border:1px solid var(--line);background:var(--sunk);color:var(--fg);cursor:pointer}
button.primary{background:var(--accent);border-color:var(--accent);color:#fff}
button:disabled{opacity:.5;cursor:default}
.ok{color:var(--ok)}.bad{color:var(--bad)}
a{color:var(--accent)}
ul{list-style:none;padding:0;margin:0}
li+li{margin-top:8px;border-top:1px solid var(--line);padding-top:8px}
</style></head><body><main>

<div class="card">
  <h1>{{if .Label}}{{.Label}}{{else}}Shared items{{end}}</h1>
  <div class="mut sm mono">{{.Domain}}/s/{{.Slug}}</div>
</div>

<div class="card">
  <div class="row"><strong class="sm">Server</strong><span class="sm" id="dns">Checking DNS…</span></div>
  <div class="mut sm mono">{{.Domain}}</div>
  {{if .SharerName}}
  <div class="row" style="margin-top:12px"><strong class="sm">Shared by</strong><span class="sm mut" id="idclaim">claimed</span></div>
  <div class="sm">{{.SharerName}}</div>
  <div class="mut sm mono">{{.SharerPrint}}</div>
  <p class="mut sm">This name and key are what the share claims. Open it in the app to verify the signature behind them.</p>
  {{end}}
</div>

{{if or .Gated .RequireHandshake}}
<div class="card">
  <strong class="sm">Protected share</strong>
  <p class="mut sm">This share needs {{if .RequireHandshake}}a verified identity{{else}}a password{{end}}. Open it in the revoked app — it checks the server before anything is typed.</p>
  <p><a href="{{.AppLink}}">Open in the app</a></p>
</div>
{{else}}
<div class="card" id="gate">
  <div class="row">
    <div>
      <strong class="sm">Shared data</strong>
      <p class="mut sm" style="margin:4px 0 0" id="capnote">{{if gt .MaxViews 0}}This link allows {{.MaxViews}} view(s); {{.ViewCount}} used. Revealing spends one.{{else}}Nothing is loaded until you ask for it.{{end}}</p>
    </div>
    <button class="primary" id="reveal">Reveal</button>
  </div>
</div>
<div id="out"></div>
{{end}}

<p class="mut sm">Values are resolved live and can be revoked at any time. <a href="{{.AppLink}}">Open in the app</a> for full verification.</p>

<script nonce="{{.Nonce}}">
(function(){
  var slug={{.Slug}}, domain={{.Domain}}, pin={{.RootFingerprint}};

  function el(t,c,txt){var e=document.createElement(t);if(c)e.className=c;if(txt!=null)e.textContent=txt;return e;}
  function fmtBytes(n){if(n<1024)return n+' B';var u=['KB','MB','GB'],i=-1;do{n/=1024;i++;}while(n>=1024&&i<u.length-1);return n.toFixed(n>=100?0:1)+' '+u[i];}

  // Same chain the app walks: the DNS record pins this server's root key.
  // Whoever answers on this domain must hold the key the domain's owner named.
  function checkDNS(){
    var name='_revoked.'+domain;
    var urls=['https://cloudflare-dns.com/dns-query?type=TXT&name='+encodeURIComponent(name),
              'https://dns.google/resolve?type=TXT&name='+encodeURIComponent(name)];
    var done=false;
    urls.forEach(function(u){
      fetch(u,{headers:{accept:'application/dns-json'}}).then(function(r){return r.json();}).then(function(j){
        if(done)return;
        var answers=(j&&j.Answer)||[];
        for(var i=0;i<answers.length;i++){
          var txt=String(answers[i].data||'').replace(/^"|"$/g,'').replace(/""/g,'');
          var m=/k=sha256\/([a-f0-9]{64})/i.exec(txt);
          if(m){
            done=true;
            var node=document.getElementById('dns');
            if(m[1].toLowerCase()===String(pin).toLowerCase()){node.className='sm ok';node.textContent='DNS verified';}
            else{node.className='sm bad';node.textContent='Spoofed — the DNS record names a different key';}
            return;
          }
        }
      }).catch(function(){});
    });
    setTimeout(function(){
      if(done)return;
      var node=document.getElementById('dns');
      node.className='sm bad';node.textContent='Not verified';
    },6000);
  }

  function render(data){
    var out=document.getElementById('out');
    out.textContent='';
    var recs=(data.records||[]).concat();
    (data.sections||[]).forEach(function(s){
      (s.records||[]).forEach(function(r){if(r&&typeof r==='object')recs.push(r);});
    });
    if(!recs.length){out.appendChild(el('p','mut sm','This link shares no items.'));return;}
    var card=el('div','card'), list=el('ul');
    recs.forEach(function(r){
      var li=el('li');
      li.appendChild(el('div',null,r.label||r.key||'Item'));
      li.appendChild(el('div','mut sm mono',r.key||''));
      if(r.type==='file'){
        var meta=el('div','mut sm',(r.filename||'file')+' · '+fmtBytes(r.size||0));
        li.appendChild(meta);
        var b=el('button',null,'Download');
        b.addEventListener('click',function(){
          b.disabled=true;
          var u='/api/public/links/'+encodeURIComponent(slug)+'/files/'+encodeURIComponent(r.id)+'?dl='+encodeURIComponent(r.downloadToken||'');
          window.location.href=u;
          setTimeout(function(){b.disabled=false;},1500);
        });
        li.appendChild(b);
      }else{
        var box=el('div','val mono');
        box.textContent=r.value==null?'':String(r.value);
        li.appendChild(box);
      }
      list.appendChild(li);
    });
    card.appendChild(list);
    out.appendChild(card);
  }

  var btn=document.getElementById('reveal');
  if(btn){
    btn.addEventListener('click',function(){
      btn.disabled=true;btn.textContent='Loading…';
      fetch('/api/public/links/'+encodeURIComponent(slug),{method:'POST',headers:{'content-type':'application/json'},body:'{}'})
        .then(function(r){return r.json().then(function(j){return {ok:r.ok,body:j};});})
        .then(function(res){
          var gate=document.getElementById('gate');
          if(!res.ok){
            gate.textContent='';
            var m=el('p','bad sm',(res.body&&res.body.message)||'This share is no longer available.');
            gate.appendChild(m);
            return;
          }
          gate.remove();
          render(res.body);
        })
        .catch(function(){
          btn.disabled=false;btn.textContent='Reveal';
          var n=document.getElementById('capnote');
          n.className='bad sm';n.textContent='Could not reach the server.';
        });
    });
  }

  checkDNS();
})();
</script>
</main></body></html>`))

// linkStatusPage renders a terminal state (revoked, expired, paused, missing)
// as a page instead of a JSON blob, for the same browser audience.
func linkStatusPage(re *core.RequestEvent, title, detail string, status int) error {
	var buf bytes.Buffer
	_ = statusTemplate.Execute(&buf, map[string]string{"Title": title, "Detail": detail})
	re.Response.Header().Set("Content-Type", "text/html; charset=utf-8")
	re.Response.Header().Set("Cache-Control", "no-store")
	re.Response.Header().Set("X-Content-Type-Options", "nosniff")
	re.Response.WriteHeader(status)
	_, _ = re.Response.Write(buf.Bytes())
	return nil
}

var statusTemplate = template.Must(template.New("status").Parse(`<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>{{.Title}} · revoked</title>
<style>
:root{color-scheme:light dark;--bg:#fff;--fg:#16161a;--mut:#6b6b74;--line:#e4e4e8}
@media(prefers-color-scheme:dark){:root{--bg:#131316;--fg:#ececf0;--mut:#9a9aa4;--line:#2a2a30}}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.6 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;padding:24px}
main{max-width:520px;margin:10vh auto;text-align:center}
h1{font-size:18px;margin:0 0 8px}
p{color:var(--mut)}
</style></head><body><main><h1>{{.Title}}</h1><p>{{.Detail}}</p></main></body></html>`))
