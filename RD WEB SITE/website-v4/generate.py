import os, html
D = '/tmp/claude-0/-home-user-mars-sandbox/eda22a4b-fb0b-53b5-8c75-12a0626db0dd/scratchpad/site4/'
os.makedirs(D, exist_ok=True)

CSS = r'''
:root{color-scheme:light;--bg:#f6f6f5;--card:#ffffff;--ink:#23262b;--mut:#7a7d83;--line:#e2e2df;--navy:#0d1726;--navy2:#2a3a52;--mist:#cfd6df;--g:max(20px,env(safe-area-inset-left,0px));--gr:max(20px,env(safe-area-inset-right,0px));--ff:'Inter',system-ui,sans-serif;--fh:'Montserrat','Inter',system-ui,sans-serif}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--ff);font-size:14px;line-height:1.7;font-weight:300;-webkit-font-smoothing:antialiased;overflow-x:hidden}
a{color:inherit;text-decoration:none}
:focus-visible{outline:2px solid var(--navy2);outline-offset:3px}
.wrap{max-width:1180px;margin:0 auto;padding-left:var(--g);padding-right:var(--gr)}
h1,h2,h3{font-family:var(--fh);font-weight:500;margin:0;letter-spacing:.12em;text-transform:uppercase}
.k{font-family:var(--fh);font-size:10.5px;letter-spacing:.38em;text-transform:uppercase;color:var(--mut);font-weight:500}
header{position:sticky;top:0;z-index:40;padding-top:env(safe-area-inset-top,0px);background:rgba(246,246,245,.86);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);border-bottom:1px solid var(--line)}
.nav{height:62px;display:flex;align-items:center;justify-content:space-between;gap:20px}
.brand{font-family:var(--fh);font-weight:600;font-size:12px;letter-spacing:.3em;text-transform:uppercase;display:flex;align-items:center;gap:12px}
.brand svg{width:28px;height:auto}
.links{display:flex;gap:30px}
.links a{font-family:var(--fh);font-size:10.5px;letter-spacing:.24em;text-transform:uppercase;color:var(--mut);padding:6px 0;position:relative;transition:color .3s}
.links a::after{content:"";position:absolute;left:0;right:0;bottom:0;height:1px;background:var(--ink);transform:scaleX(0);transform-origin:left;transition:transform .4s}
.links a:hover,.links a.on{color:var(--ink)}.links a:hover::after,.links a.on::after{transform:scaleX(1)}
.mb{display:none;background:none;border:1px solid var(--line);padding:8px 14px;font:500 10.5px var(--fh);letter-spacing:.24em;text-transform:uppercase;color:var(--ink);cursor:pointer}
/* hero: text only */
.hero{position:relative;min-height:calc(100vh - 62px);min-height:calc(100svh - 62px);display:grid;place-items:center;text-align:center;background:radial-gradient(70% 60% at 50% 42%,#ffffff,#f1f1ef);overflow:hidden}
.hero .txt{display:grid;gap:20px;justify-items:center;padding:60px var(--gr) 90px var(--g);max-width:640px;will-change:opacity,transform}
.hero h1{font-size:clamp(26px,4.4vw,52px);letter-spacing:.22em;color:#4a4d52;line-height:1.2;font-weight:500}
.hero .sub{font-family:var(--fh);font-size:10.5px;letter-spacing:.5em;text-transform:uppercase;color:#8d9096}
.hero p{margin:0;font-size:13.5px;color:#7d8085;max-width:46ch}
.hero .ln{width:1px;height:54px;background:linear-gradient(#8d9096,transparent);margin-top:10px}
.hero .lg{width:54px;margin-bottom:6px}
/* intro */
#intro{position:fixed;inset:0;z-index:100;background:#ffffff;display:none;place-items:center;text-align:center;transition:opacity 1.2s ease}
.js #intro{display:grid}
#intro.off{opacity:0;pointer-events:none}
#intro .in1{display:grid;justify-items:center;gap:0;padding:0 var(--gr) 0 var(--g)}
#intro svg{width:clamp(96px,13vw,140px);height:auto;opacity:0;transition:opacity 1.6s ease}
#intro .nm,#intro .tg,#intro .en{opacity:0;transform:translateY(8px);transition:opacity 1.3s ease,transform 1.3s cubic-bezier(.2,.8,.2,1)}
#intro .nm{margin-top:34px;font-family:var(--fh);font-weight:500;font-size:clamp(14px,2vw,18px);letter-spacing:.34em;text-transform:uppercase;color:#2b2e33}
#intro .tg{margin-top:12px;font-size:12px;letter-spacing:.06em;color:#8d9096;max-width:40ch}
#intro .en{margin-top:34px;background:none;border:1px solid #cfd1d4;padding:12px 30px;font:500 10.5px var(--fh);letter-spacing:.34em;text-transform:uppercase;color:#2b2e33;cursor:pointer;transition:opacity 1.3s ease,transform 1.3s,background .3s,color .3s,border-color .3s}
#intro .en:hover{background:#23262b;color:#fff;border-color:#23262b}
#intro.s1 svg{opacity:1}#intro.s2 .nm,#intro.s2 .tg{opacity:1;transform:none}#intro.s3 .en{opacity:1;transform:none}
.js:not(.ready) main,.js:not(.ready) footer{visibility:hidden}.js:not(.ready) body{background:#fff}
/* reveal */
.js header{opacity:0;transition:opacity 1.4s ease}.js.ready header{opacity:1}
.js .rv{opacity:0;transform:translateY(20px);transition:opacity 1.2s ease,transform 1.2s cubic-bezier(.2,.8,.2,1);transition-delay:var(--d,0s)}
.js .rv.in{opacity:1;transform:none}
/* navy banner + shapes */
.banner{background:radial-gradient(90% 140% at 78% 120%,#8793a4 0%,#2a3a52 42%,var(--navy) 80%);color:#fff;padding:78px 0 70px;position:relative;overflow:hidden}
.banner::after{content:"";position:absolute;width:520px;height:520px;border-radius:50%;right:-120px;top:-160px;background:radial-gradient(circle at 40% 40%,rgba(255,255,255,.14),transparent 62%);filter:blur(6px)}
.banner h2{font-size:clamp(20px,3.4vw,38px);letter-spacing:.34em;font-weight:600;text-align:center}
.banner p{max-width:52ch;margin:18px auto 0;text-align:center;color:#c3ccd8;font-size:13px}
.shapes{background:#f0f2f3;padding:70px 0 80px;position:relative}
.shapes::before{content:"";position:absolute;inset:0;background-image:linear-gradient(45deg,#e8eaeb 25%,transparent 25%,transparent 75%,#e8eaeb 75%),linear-gradient(45deg,#e8eaeb 25%,transparent 25%,transparent 75%,#e8eaeb 75%);background-size:8px 8px;background-position:0 0,4px 4px;opacity:.5;-webkit-mask-image:linear-gradient(transparent 50%,#000);mask-image:linear-gradient(transparent 50%,#000);pointer-events:none}
.grid3{position:relative;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}
.card{position:relative;display:block;padding:26px 20px 24px;background:rgba(255,255,255,.55);border:1px solid #e3e6e8;overflow:hidden;--mx:0;--my:0;transition:background .4s,border-color .4s}
.card:hover{background:#fff;border-color:#cfd5da}
.sh{position:relative;height:190px;display:grid;place-items:center}
.sh i{display:block;width:140px;height:140px;border-radius:50%;filter:blur(5px);transition:transform .8s cubic-bezier(.2,.8,.2,1),filter .6s;transform:translate(calc(var(--mx)*16px),calc(var(--my)*16px))}
.card:hover .sh i{transform:translate(calc(var(--mx)*22px - 34px),calc(var(--my)*22px - 8px)) scale(1.12) rotate(14deg);filter:blur(2px)}
.s1{background:radial-gradient(circle at 50% 60%,#e9edf1 0 22%,#9aa5b3 40%,#e6eaee 62%,#b8c1cc)}
.s2{background:radial-gradient(circle at 50% 50%,#0f1a2a 0 36%,#46566d 52%,#d9dee4 74%)}
.s3{background:radial-gradient(circle at 62% 42%,#0b1422 0 24%,#6b7a8f 46%,#dde2e8 72%);border-radius:48% 52% 55% 45%!important}
.s4{background:conic-gradient(from 200deg,#1c2a3e,#7d8da3,#eef1f4,#52627a,#1c2a3e)}
.s5{background:radial-gradient(circle at 50% 75%,#f4f6f8 0 20%,#a7b2c0 45%,#27374e 78%);border-radius:50% 50% 50% 50%/60% 60% 40% 40%!important}
.s6{background:radial-gradient(circle at 50% 50%,#c9d1db 0 16%,#2c3c54 36%,#aeb9c7 56%,#1b283b 74%,#e6eaee)}
.card h3{font-size:11px;letter-spacing:.24em;text-align:center;margin-top:4px}
.card p{margin:10px 0 0;text-align:center;font-size:12px;color:var(--mut);max-height:0;opacity:0;transform:translateY(10px);transition:max-height .5s,opacity .5s,transform .5s}
.card:hover p,.card:focus-visible p{max-height:90px;opacity:1;transform:none}
.card .go{display:block;text-align:center;margin-top:10px;font-family:var(--fh);font-size:10px;letter-spacing:.3em;text-transform:uppercase;color:var(--navy2);opacity:0;transform:translateX(-12px);transition:opacity .5s .05s,transform .5s .05s}
.card:hover .go{opacity:1;transform:none}
/* content */
section.s{padding:78px 0}
.split{display:grid;grid-template-columns:1fr 1.5fr;gap:70px}
.split h2{font-size:clamp(17px,2.2vw,24px);letter-spacing:.2em;line-height:1.35;margin-top:14px}
.txt2{display:grid;gap:16px;color:#686b71;max-width:62ch}
.txt2 b{font-weight:500;color:var(--ink)}
.facts{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));border-top:1px solid var(--line);border-bottom:1px solid var(--line);margin-top:56px}
.facts div{padding:26px 18px;border-left:1px solid var(--line)}
.facts div:first-child{border-left:0}
.facts b{display:block;font-family:var(--fh);font-weight:500;font-size:22px;letter-spacing:.06em;color:var(--navy2)}
.facts span{font-size:11px;color:var(--mut);letter-spacing:.08em}
.list{margin:0;padding:0;list-style:none;border-top:1px solid var(--line)}
.list li{display:grid;grid-template-columns:44px 1fr 1.4fr;gap:20px;padding:24px 0;border-bottom:1px solid var(--line);transition:background .4s,padding .4s}
.list li:hover{padding-left:12px;background:rgba(255,255,255,.7)}
.list .n{font-family:var(--fh);font-size:11px;letter-spacing:.2em;color:var(--mut)}
.list h3{font-size:12px;letter-spacing:.2em}
.list p{margin:0;color:#6b6e74;font-size:13px}
.ph{aspect-ratio:4/3;border:1px dashed #c6c9cc;background:rgba(255,255,255,.6);display:flex;align-items:flex-end;padding:14px;font-size:11px;color:var(--mut);letter-spacing:.08em;transition:transform .5s,box-shadow .5s}
.ph:hover{transform:translateY(-6px);box-shadow:0 18px 30px -18px rgba(20,28,40,.3)}
.cols{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:36px 28px}
.cols article{display:grid;gap:12px}
.cols h3{font-size:12px;letter-spacing:.22em;margin-top:4px}
.cols p{margin:0;color:#6b6e74;font-size:13px}
.pagehead{background:radial-gradient(90% 160% at 80% 130%,#6f7d92,#2a3a52 45%,var(--navy) 85%);color:#fff;padding:80px 0 66px}
.pagehead h1{font-size:clamp(20px,3.4vw,36px);letter-spacing:.34em;font-weight:600}
.pagehead p{margin:16px 0 0;max-width:56ch;color:#c3ccd8;font-size:13px}
.steps{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:18px;counter-reset:s}
.steps div{border-top:1px solid var(--ink);padding-top:14px;font-size:12.5px;color:#6b6e74}
.steps b{display:block;font-family:var(--fh);font-weight:500;font-size:11px;letter-spacing:.22em;text-transform:uppercase;color:var(--ink);margin-bottom:6px}
.dl{margin:0;display:grid}
.dl div{display:flex;justify-content:space-between;gap:20px;padding:16px 0;border-bottom:1px solid var(--line)}
.dl dt{font-family:var(--fh);font-size:10.5px;letter-spacing:.22em;text-transform:uppercase;color:var(--mut)}
.dl dd{margin:0;text-align:right}
.btn{display:inline-block;padding:13px 26px;border:1px solid var(--ink);font-family:var(--fh);font-size:10.5px;letter-spacing:.28em;text-transform:uppercase;background:transparent;color:var(--ink);cursor:pointer;transition:background .3s,color .3s}
.btn:hover{background:var(--ink);color:#fff}
.mail{font-family:var(--fh);font-size:clamp(14px,2vw,20px);letter-spacing:.1em;word-break:break-all}
footer{background:var(--navy);color:#aab4c2;padding:50px 0 calc(34px + env(safe-area-inset-bottom,0px));font-size:12px}
footer .f{display:grid;grid-template-columns:1.4fr 1fr 1fr;gap:40px}
footer h4{margin:0 0 12px;font:500 10px var(--fh);letter-spacing:.3em;text-transform:uppercase;color:#fff}
footer a{display:block;padding:3px 0;transition:color .3s,transform .3s}footer a:hover{color:#fff;transform:translateX(4px)}
footer .c{margin-top:36px;padding-top:20px;border-top:1px solid #22324a;font-size:11px;letter-spacing:.08em}
@media(max-width:860px){
.links{display:none;position:absolute;left:0;right:0;top:100%;background:var(--bg);flex-direction:column;gap:0;padding:8px var(--gr) 16px var(--g);border-bottom:1px solid var(--line)}.links.open{display:flex}.links a{padding:14px 0;border-bottom:1px solid var(--line)}.mb{display:block}
.grid3{grid-template-columns:repeat(2,minmax(0,1fr))}
.split{grid-template-columns:1fr;gap:28px}.facts{grid-template-columns:repeat(2,minmax(0,1fr))}.facts div:nth-child(3){border-left:0}.facts div{border-top:1px solid var(--line)}
.list li{grid-template-columns:34px 1fr}.list p{grid-column:2}.cols,.steps{grid-template-columns:1fr}footer .f{grid-template-columns:1fr}}
@media(max-width:520px){.grid3{grid-template-columns:1fr}.card p,.card .go{max-height:none;opacity:1;transform:none}}
@media(prefers-reduced-motion:reduce){*{transition:none!important}}
'''

LOGO = '<svg viewBox="0 0 2000 1236" aria-hidden="true"><path fill="#23262b" d="M90 22H890C1100 22 1290 190 1310 380L1316 520C1316 700 1190 790 1065 828C1050 833 1050 848 1058 856L1388 1212H1022C1005 1212 995 1205 985 1192L470 583C462 573 470 566 485 566H828C900 566 975 500 978 420C975 350 910 293 835 293H290C275 293 265 287 255 275L75 52C66 40 72 22 90 22Z"/><path fill="#8793a4" d="M95 378C105 376 112 380 118 387L370 708C380 720 386 735 385 752L350 1190C348 1205 340 1212 328 1212H205C180 1212 160 1200 148 1185L35 1040C20 1022 12 1005 14 985L80 395C82 385 88 379 95 378Z"/><path fill="#8793a4" d="M1115 22H1450C1700 22 1905 200 1943 410L1985 760C1992 1010 1790 1212 1540 1212H1455L1168 903H1465C1580 903 1660 815 1655 712L1635 460C1625 360 1545 297 1450 297H1348C1320 190 1230 85 1115 22Z"/></svg>'

PAGES = [('index.html', 'Home'), ('services.html', 'Services'), ('film.html', 'Film'), ('work.html', 'Work'), ('about.html', 'About'), ('contact.html', 'Contact')]

JS = r'''
(function(){
var d=document;
var mb=d.getElementById('mb'),ln=d.getElementById('ln');if(mb)mb.addEventListener('click',function(){var o=ln.classList.toggle('open');mb.setAttribute('aria-expanded',o)});
/* intro, reveal, hero fade-away */
var R=d.documentElement,hasIntro=!!d.getElementById('intro'),reduce=matchMedia('(prefers-reduced-motion:reduce)').matches;
R.classList.add('js');
function reveal(){
  var sel='.pagehead .k,.pagehead h1,.pagehead p,.banner h2,.banner p,.split>*,.facts div,.list li,.cols article,.steps div,.card,.dl div,.mail,.btn,.hero .rv';
  var els=[].slice.call(d.querySelectorAll(sel));
  els.forEach(function(el){if(!el.classList.contains('rv'))el.classList.add('rv')});
  var kids={};els.forEach(function(el){var p=el.parentNode,i=(p.__n=(p.__n||0)+1)-1;el.style.setProperty('--d',(Math.min(i,6)*.12).toFixed(2)+'s')});
  var io=new IntersectionObserver(function(es){es.forEach(function(e){if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}})},{threshold:.12});
  els.forEach(function(el){if(!el.closest('.hero'))io.observe(el)});
  return els.filter(function(el){return el.closest('.hero')});
}
var heroEls=reveal();
function ready(){R.classList.add('ready');setTimeout(function(){heroEls.forEach(function(el,i){setTimeout(function(){el.classList.add('in')},i*220)})},hasIntro?500:200)}
var intro=d.getElementById('intro'),entered=false;
function enter(){if(entered)return;entered=true;intro.classList.add('off');ready();setTimeout(function(){intro.style.display='none'},1400);removeEventListener('keydown',kd)}
function kd(e){if(e.key==='Enter'||e.key===' '||e.key==='Escape'){e.preventDefault();enter()}}
if(intro&&!reduce){
  setTimeout(function(){intro.classList.add('s1')},200);setTimeout(function(){intro.classList.add('s2')},2200);setTimeout(function(){intro.classList.add('s3');var b=d.getElementById('enter');if(b)b.focus({preventScroll:true})},3600);
  d.getElementById('enter').addEventListener('click',enter);addEventListener('keydown',kd);
}else{if(intro)intro.style.display='none';ready()}
var ht=d.getElementById('ht');
if(ht){addEventListener('scroll',function(){var k=Math.min(1,Math.max(0,scrollY/(innerHeight*.55)));ht.style.opacity=(1-k).toFixed(3);ht.style.transform='translateY('+(-k*28).toFixed(1)+'px)'},{passive:true})}
/* shapes follow the pointer inside each card */
[].forEach.call(d.querySelectorAll('.card'),function(c){c.addEventListener('pointermove',function(e){var r=c.getBoundingClientRect();c.style.setProperty('--mx',((e.clientX-r.left)/r.width-.5).toFixed(3));c.style.setProperty('--my',((e.clientY-r.top)/r.height-.5).toFixed(3))});c.addEventListener('pointerleave',function(){c.style.setProperty('--mx',0);c.style.setProperty('--my',0)})});
/* copy */
var cp=d.getElementById('cp'),em=d.getElementById('em');
if(cp)cp.addEventListener('click',function(){function ok(){cp.textContent='Copied';setTimeout(function(){cp.textContent='Copy address'},1800)}function sel(){var r=d.createRange();r.selectNodeContents(em);var s=getSelection();s.removeAllRanges();s.addRange(r)}try{navigator.clipboard.writeText(em.textContent).then(ok,sel)}catch(e){sel()}});
})();
'''

def header(active):
    links = ''.join('<a href="%s"%s>%s</a>' % (f, ' class="on" aria-current="page"' if f == active else '', n) for f, n in PAGES)
    return ('<header><div class="wrap nav"><a class="brand" href="index.html" aria-label="RD Global Connect home">%s RD Global Connect</a>'
            '<button class="mb" id="mb" aria-expanded="false" aria-controls="ln" type="button">Menu</button>'
            '<nav class="links" id="ln" aria-label="Primary">%s</nav></div></header>') % (LOGO, links)

FOOT = '''<footer><div class="wrap"><div class="f">
<div><h4>RD Global Connect Co., Ltd.</h4><p style="margin:0;max-width:34ch">Destination management, ground logistics, event and film production. Operating partner of Experience Pattaya City.</p></div>
<div><h4>Pages</h4><a href="services.html">Services</a><a href="film.html">Film production</a><a href="work.html">Work</a><a href="about.html">About</a><a href="contact.html">Contact</a></div>
<div><h4>Base</h4><span>Nong Prue, Bang Lamung<br>Chon Buri, Thailand</span></div></div>
<div class="c">© RD Global Connect Co., Ltd. · Power · Connections · Innovation</div></div></footer>'''

def page(fn, title, body, active):
    head = ('<title>%s</title><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="claude:viewport-fit-sides" content="cover">'
            '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500&family=Montserrat:wght@400;500;600&display=swap">'
            '<style>%s</style>') % (title, CSS)
    intro = ('<div id="intro" role="dialog" aria-label="RD Global Connect"><div class="in1">'+LOGO+'<div class="nm">RD Global Connect</div><div class="tg">Power · Connections · Innovation<br>Destination management and production, Chon Buri, Thailand</div><button class="en" id="enter" type="button">Enter</button></div></div>') if fn=='index.html' else ''
    JSON_='<script>document.documentElement.classList.add("js")</script>'
    inner = head + JSON_ + intro + header(active) + '<main>' + body + '</main>' + FOOT + '<script>' + JS + '</script>'
    if fn == 'index.html':
        return inner
    return '<!doctype html><html lang="en"><head><meta charset="utf-8">' + head + '</head><body>' + JSON_ + header(active) + '<main>' + body + '</main>' + FOOT + '<script>' + JS + '</script></body></html>'

def pagehead(k, t, p):
    return '<section class="pagehead"><div class="wrap"><span class="k" style="color:#9fb0c6">%s</span><h1 style="margin-top:16px">%s</h1><p>%s</p></div></section>' % (k, t, p)

# ---------- HOME ----------
tiles = ''
fills = ['', 't2', '', 't3', 't2', 't2', '', 't2', 't3', '', '', 't3', '', 't2', '', 't2', '', 't3', 't2', '', 't3', '', '', 't2', '']
for i in range(25):
    tiles += '<div class="tile %s"></div>' % fills[i]
SERV = [
 ('s1', 'Destination management', 'Programmes, itineraries and on-site teams for delegations and groups.'),
 ('s2', 'Ground logistics', 'Transport, access and timing run as one operation.'),
 ('s3', 'Event production', 'Staging, technical production and hospitality, from concept to load-out.'),
 ('s4', 'Film production', 'Locations, permits, crews and logistics for productions in Thailand.'),
 ('s5', 'Vendor and venue contracts', 'Negotiated and managed so quality and price are agreed in advance.'),
 ('s6', 'Government liaison', 'Working relationships with TCEB, TAT and DASTA.'),
]
cards = ''.join('<a class="card" href="services.html"><div class="sh"><i class="%s"></i></div><h3>%s</h3><p>%s</p><span class="go">Read more</span></a>' % c for c in SERV)
home = '''
<section class="hero"><div class="txt" id="ht"><div class="lg rv">%s</div><h1 class="rv">RD Global Connect</h1><div class="sub rv">Power · Connections · Innovation</div>
<p class="rv">The operating partner behind the destination. We plan, contract and run it on the ground in Thailand, for partners from Switzerland to Dubai.</p><div class="ln rv" aria-hidden="true"></div></div></section>
<section class="banner"><div class="wrap"><h2>What we do</h2><p>Six capabilities, one accountable team. Move over a shape to see what it covers.</p></div></section>
<section class="shapes"><div class="wrap"><div class="grid3">%s</div></div></section>
<section class="s"><div class="wrap">
<div class="split"><div><span class="k">About</span><h2>Operations first. Technology where it helps.</h2></div>
<div class="txt2"><p>RD Global Connect Co., Ltd. is registered in Nong Prue, Bang Lamung District, Chon Buri, and is the <b>operating partner on the ground for Experience Pattaya City</b>.</p>
<p>Apps and websites are one thing we do. The core of the company is the work that makes a destination run: contracts, logistics, productions and the relationships with the institutions that approve them.</p>
<p><a class="btn" href="about.html">About the company</a></p></div></div>
<div class="facts"><div><b>3</b><span>Institutions we liaise with</span></div><div><b>6</b><span>Capabilities</span></div><div><b>5</b><span>Projects and partners</span></div><div><b>3</b><span>Markets: Thailand, Switzerland, UAE</span></div></div>
</div></section>
<section class="s" style="padding-top:0"><div class="wrap"><div class="split"><div><span class="k">Film production</span><h2>The ground behind the picture.</h2></div>
<div class="txt2"><p>We prepare the location before the crew arrives: permits, venues, vendors, transport and accommodation, coordinated with the people who approve them.</p><p><a class="btn" href="film.html">Film production</a></p></div></div></div></section>
''' % (LOGO, cards)

# ---------- SERVICES ----------
SV = [
 ('Destination management', 'Programmes, itineraries and on-site teams for delegations, groups and institutional visitors, planned and run from our base in Chon Buri.'),
 ('Ground logistics', 'Transport, accommodation, access and timing coordinated as one operation with a single accountable contact.'),
 ('Event production', 'Concept, staging, technical production, hospitality and show control for events of different scales.'),
 ('Film production', 'Locations, permits, crews and logistics for productions shooting in and around Chon Buri and Pattaya.'),
 ('Vendor and venue contracts', 'Contracts negotiated and managed on your behalf, so quality, price and delivery are agreed before the day.'),
 ('Government liaison', 'Direct working relationships with TCEB, TAT and DASTA for approvals, partnerships and destination programmes.'),
]
lis = ''.join('<li><span class="n">%02d</span><h3>%s</h3><p>%s</p></li>' % (i + 1, a, b) for i, (a, b) in enumerate(SV))
services = pagehead('Services', 'What we do', 'Six capabilities that make a destination work, delivered by one team on the ground.') + '''
<section class="s"><div class="wrap"><ul class="list">%s</ul>
<div class="split" style="margin-top:80px"><div><span class="k">How we work</span><h2>One team from first call to last day.</h2></div>
<div class="steps"><div><b>Listen</b>We start with the outcome you need and the date it is due.</div><div><b>Plan</b>Scope, budget, contracts and permits are set before work begins.</div><div><b>Carry out</b>Our team runs the operation on site.</div><div><b>Report</b>You receive a clear account of what was delivered.</div></div></div>
</div></section>''' % lis

# ---------- FILM ----------
film = pagehead('Film production', 'The ground behind the picture', 'A production is only as good as the place it happens. We make the ground ready.') + '''
<section class="s"><div class="wrap"><div class="cols">
<article><span class="k">Locations</span><h3>Finding and securing the place</h3><p>We scout and secure locations and the venues around them, and agree access, timing and conditions in writing.</p></article>
<article><span class="k">Permits</span><h3>Approvals that move</h3><p>Our working relationships with TCEB, TAT and DASTA help permits and partnerships progress without surprises.</p></article>
<article><span class="k">Crews and vendors</span><h3>People and equipment on site</h3><p>We contract local crews, suppliers and vendors, and manage them day to day so the team on set can focus on the shot.</p></article>
<article><span class="k">Logistics</span><h3>Moving everyone, everything</h3><p>Transport, accommodation, hospitality and timing coordinated as a single plan from arrival to wrap.</p></article>
</div>
<div class="split" style="margin-top:80px"><div><span class="k">Working with us</span><h2>From brief to wrap.</h2></div>
<div class="steps"><div><b>Brief</b>You share the script, schedule and needs.</div><div><b>Prepare</b>Locations, permits and contracts are lined up.</div><div><b>Shoot</b>We support the production on the ground.</div><div><b>Wrap</b>Close-out, returns and reporting.</div></div></div>
<p style="margin-top:50px"><a class="btn" href="contact.html">Discuss a production</a></p></div></section>'''

# ---------- WORK ----------
WK = [('Experience Pattaya City', 'Operating partner', 'The city visitor experience, operated on the ground by RD Global Connect.'),
      ('BESK Creative', 'Sister company', 'Creative and technology studio, led by our founder Bryan LeRoy.'),
      ('WAWA', 'Learning app', 'A learning application designed and built by our team.'),
      ('CLO', 'Application', 'A custom application built for its operator.'),
      ('Pulverlaguer', 'Application', 'A custom application built for the Pulverlaguer project.')]
wk = ''.join('<article><div class="ph">Image: %s</div><h3 style="margin-top:14px;font-size:12px;letter-spacing:.2em">%s</h3><span class="k" style="display:block;margin:4px 0 6px">%s</span><p style="margin:0;color:#6b6e74;font-size:13px">%s</p></article>' % (a, a, b, c) for a, b, c in WK)
work = pagehead('Work', 'Projects and partners', 'Systems we have built and the partners we operate with. Images will be added here.') + '<section class="s"><div class="wrap"><div class="cols" style="grid-template-columns:repeat(3,minmax(0,1fr))">%s</div></div></section>' % wk

# ---------- ABOUT ----------
about = pagehead('About', 'RD Global Connect', 'Power, connections, innovation. An operating company with technology built in.') + '''
<section class="s"><div class="wrap"><div class="split"><div><span class="k">Company</span><h2>Registered in Chon Buri, working in three markets.</h2></div>
<div class="txt2"><p>RD Global Connect Co., Ltd. is registered in Nong Prue, Bang Lamung District, Chon Buri Province, Thailand. We are the operating partner on the ground for Experience Pattaya City.</p>
<p>Our services cover destination management, ground logistics, event and film production, vendor and venue contracts and government liaison with TCEB, TAT and DASTA. We also build applications, including WAWA, CLO, Experience Pattaya City and the Pulverlaguer app.</p>
<p>We work for partners in Thailand and plan to Swiss expectations of precision, reliability and accountability, with a network that reaches Dubai.</p></div></div>
<div class="split" style="margin-top:80px"><div><span class="k">Leadership</span><h2>Founded and directed by Bryan LeRoy.</h2></div>
<div><p class="txt2" style="margin:0 0 22px">Bryan also leads BESK Creative. Together the two companies combine operations and creative technology.</p>
<dl class="dl"><div><dt>Company</dt><dd>RD Global Connect Co., Ltd.</dd></div><div><dt>Registered</dt><dd>Nong Prue, Bang Lamung, Chon Buri</dd></div><div><dt>Role</dt><dd>Operating partner, Experience Pattaya City</dd></div><div><dt>Liaison</dt><dd>TCEB · TAT · DASTA</dd></div><div><dt>Markets</dt><dd>Thailand · Switzerland · UAE</dd></div></dl></div></div>
</div></section>'''

# ---------- CONTACT ----------
contact = pagehead('Contact', 'Talk to us', 'Tell us the destination, the date and the outcome you need.') + '''
<section class="s"><div class="wrap"><div class="split"><div><span class="k">Write to us</span><h2>We respond with a plan.</h2></div>
<div style="display:grid;gap:22px;justify-items:start"><div class="mail" id="em">bryanleroy.besk@gmail.com</div><button class="btn" id="cp" type="button">Copy address</button>
<dl class="dl" style="width:100%;max-width:520px"><div><dt>Company</dt><dd>RD Global Connect Co., Ltd.</dd></div><div><dt>Address</dt><dd>Nong Prue, Bang Lamung, Chon Buri, Thailand</dd></div><div><dt>Contact</dt><dd>Bryan LeRoy, Founder and Director</dd></div></dl></div></div></div></section>'''

for fn, t, body, act in [('index.html', 'RD Global Connect', home, 'index.html'), ('services.html', 'Services · RD Global Connect', services, 'services.html'),
        ('film.html', 'Film production · RD Global Connect', film, 'film.html'), ('work.html', 'Work · RD Global Connect', work, 'work.html'),
        ('about.html', 'About · RD Global Connect', about, 'about.html'), ('contact.html', 'Contact · RD Global Connect', contact, 'contact.html')]:
    open(D + fn, 'w').write(page(fn, t, body, act))
print('ok', os.listdir(D))
