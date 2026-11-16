import re
src=open('/root/.claude/uploads/eda22a4b-fb0b-53b5-8c75-12a0626db0dd/c869b208-EPC-Presentation.html',encoding='utf-8').read()
theme=open('/tmp/epcbuild/theme.css').read()
def rep(a,b,cnt=1):
    global src
    assert src.count(a)==cnt,(a[:60],src.count(a)); src=src.replace(a,b)
LOGO='<svg viewBox="0 0 2000 1236" aria-hidden="true"><path fill="#23262b" d="M90 22H890C1100 22 1290 190 1310 380L1316 520C1316 700 1190 790 1065 828C1050 833 1050 848 1058 856L1388 1212H1022C1005 1212 995 1205 985 1192L470 583C462 573 470 566 485 566H828C900 566 975 500 978 420C975 350 910 293 835 293H290C275 293 265 287 255 275L75 52C66 40 72 22 90 22Z"/><path fill="#8793a4" d="M95 378C105 376 112 380 118 387L370 708C380 720 386 735 385 752L350 1190C348 1205 340 1212 328 1212H205C180 1212 160 1200 148 1185L35 1040C20 1022 12 1005 14 985L80 395C82 385 88 379 95 378Z"/><path fill="#8793a4" d="M1115 22H1450C1700 22 1905 200 1943 410L1985 760C1992 1010 1790 1212 1540 1212H1455L1168 903H1465C1580 903 1660 815 1655 712L1635 460C1625 360 1545 297 1450 297H1348C1320 190 1230 85 1115 22Z"/></svg>'
LOGOW=LOGO.replace('#23262b','#ffffff').replace('#8793a4','#9fb0c6')
rep('<title>Experience Pattaya City</title>','<title>Experience Pattaya City · RD Global Connect</title>\n<meta name="robots" content="noindex,nofollow">')
rep('<link rel="preconnect" href="https://fonts.googleapis.com">','<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600&family=Montserrat:wght@400;500;600&display=swap">\n<link rel="preconnect" href="https://fonts.googleapis.com">')
i=src.index('</style>')
src=src[:i]+theme+src[i:]
rep('<div class="top">\n  <div class="brand">Experience Pattaya City<small id="fromline"></small></div>',
    '<script>(function(r){try{if(sessionStorage.getItem("rdp")==="1")r.classList.add("pt-start")}catch(e){}})(document.documentElement)</script>\n<div id="pt" aria-hidden="true"><i></i><i></i><b>'+LOGOW+'</b></div>\n<div class="top">\n  <div class="tl"><a class="rb" href="index.html" aria-label="RD Global Connect">'+LOGO+'<span>RD Global Connect</span></a><div class="brand">Experience Pattaya City<small id="fromline"></small></div></div>')
FOOT='''<footer class="rdf"><div class="wrap"><div class="f">
<div><h4>RD Global Connect Co., Ltd.</h4><p style="margin:0;max-width:34ch">Operating partner of Experience Pattaya City. Together with besk.ae.</p></div>
<div><h4>Site</h4><a href="index.html">Home</a><a href="services.html">Services</a><a href="contact.html">Contact</a></div>
<div><h4>Base</h4><span>Nong Prue, Bang Lamung<br>Chon Buri, Thailand<br><a href="mailto:info@rdglobalconnect.com" style="display:inline">info@rdglobalconnect.com</a></span></div></div>
<div class="c">&copy; RD Global Connect Co., Ltd.</div></div></footer>
<script>(function(){var d=document,R=d.documentElement,pt=d.getElementById('pt'),reduce=matchMedia('(prefers-reduced-motion:reduce)').matches;try{sessionStorage.removeItem('rdp')}catch(e){}
if(R.classList.contains('pt-start')&&!reduce){setTimeout(function(){pt.classList.add('out');setTimeout(function(){pt.classList.add('done');R.classList.remove('pt-start')},1300)},120)}else{R.classList.remove('pt-start');pt.classList.add('done')}
d.addEventListener('click',function(e){var a=e.target.closest&&e.target.closest('a[href]');if(!a||e.defaultPrevented||e.metaKey||e.ctrlKey||e.shiftKey||a.target==='_blank')return;var h=a.getAttribute('href');if(!h||h.charAt(0)==='#'||/^(https?:|mailto:|tel:)/.test(h)||!/\\.html(#.*)?$/.test(h)||reduce)return;e.preventDefault();pt.classList.remove('done','out');R.classList.remove('pt-start');void pt.offsetWidth;pt.classList.add('in');setTimeout(function(){try{sessionStorage.setItem('rdp','1')}catch(e){}location.href=h},980)});
addEventListener('pageshow',function(e){if(e.persisted){pt.classList.remove('in');pt.classList.add('done')}})})();</script>
'''
rep('<main id="page"></main>','<main id="page"></main>\n'+FOOT)
open('/tmp/epcbuild/epc-presentation.html','w',encoding='utf-8').write(src)
print(len(src))
