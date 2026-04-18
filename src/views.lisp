(in-package #:photo-ai-lisp)

(defmacro layout (title &body body)
  `(with-html-output-to-string (s nil :prologue t)
     (:html
      (:head (:title (str ,title)))
      (:body
       (:header :style "margin-bottom: 1rem"
        (:h1 "photo-ai-lisp")
        (:p (:a :href "/" "Home") " | " (:a :href "/photos" "Photos") " | " (:a :href "/upload" "Upload") " | " (:a :href "/scan" "Scan") " | " (:a :href "/manifest" "Manifest") " | " (:a :href "/pipeline" "Pipeline") " | " (:a :href "/repl" "REPL")))
       ,@body
       (:footer :style "margin-top: 1rem" (:small "Live-edit Lisp web prototype"))))))

(defun agent-page ()
  "Chat UI. The resident agent is the decider; Lisp holds the pipe."
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (format nil "<!DOCTYPE html>
<html lang=\"en\"><head><meta charset=\"utf-8\">
<title>photo-ai-lisp</title>
<style>
 body{font-family:ui-sans-serif,Segoe UI,Arial,sans-serif;margin:0;color:#1a1a1a;background:#fafafa;display:flex;flex-direction:column;height:100vh}
 header{padding:.6rem 1rem;background:#fff;border-bottom:1px solid #e0e0e0}
 header h1{margin:0;font-size:1.1rem}
 nav{font-size:.85rem;margin-top:.2rem}
 nav a{margin-right:.4rem;color:#0057b7;text-decoration:none}
 nav a:hover{text-decoration:underline}
 .warn{background:#fff3cd;border-bottom:1px solid #d39e00;color:#533f03;padding:.4rem 1rem;font-size:.85rem}
 #messages{flex:1;overflow-y:auto;padding:1rem;max-width:900px;margin:0 auto;width:100%;box-sizing:border-box}
 .msg{margin-bottom:.8rem;padding:.6rem .8rem;border-radius:8px;max-width:80%;white-space:pre-wrap;word-wrap:break-word;font-size:14px;line-height:1.4}
 .msg.user{background:#0057b7;color:#fff;margin-left:auto}
 .msg.agent{background:#fff;border:1px solid #e0e0e0}
 .msg.tool{background:#eef;border:1px solid #bbd;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px}
 .msg.err{background:#fdd;border:1px solid #c66;color:#800}
 details{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;background:#f4f4f4;border:1px solid #ddd;padding:.3rem .5rem;border-radius:4px;margin-top:.3rem}
 details summary{cursor:pointer;color:#555}
 form{padding:.6rem 1rem;background:#fff;border-top:1px solid #e0e0e0;display:flex;gap:.4rem;max-width:900px;margin:0 auto;width:100%;box-sizing:border-box}
 textarea{flex:1;font-family:inherit;font-size:14px;padding:.5rem;border:1px solid #aaa;border-radius:6px;resize:vertical;min-height:38px;max-height:200px}
 button{font-family:inherit;font-size:14px;padding:.5rem 1rem;border:0;border-radius:6px;background:#0057b7;color:#fff;cursor:pointer}
 button:hover{background:#003e80}
 button:disabled{background:#888;cursor:not-allowed}
 .status{font-size:.8rem;color:#666;padding:0 1rem .4rem;text-align:right}
</style></head><body>
<header>
 <h1>photo-ai-lisp</h1>
 <nav><a href=\"/\">Home</a> | <a href=\"/photos\">Photos</a> | <a href=\"/upload\">Upload</a> | <a href=\"/scan\">Scan</a> | <a href=\"/manifest\">Manifest</a> | <a href=\"/pipeline\">Pipeline</a> | <a href=\"/repl\">REPL</a></nav>
</header>
<div class=\"warn\"><strong>Local dev only.</strong> The chat endpoint drives an AI agent subprocess with arbitrary tool access &mdash; do not expose this server publicly.</div>
<div id=\"messages\"></div>
<div class=\"status\" id=\"status\"></div>
<form id=\"f\">
 <textarea id=\"input\" rows=\"2\" placeholder=\"Message the agent &mdash; Enter to send, Shift+Enter for newline\" autofocus></textarea>
 <button id=\"send\" type=\"submit\">Send</button>
</form>
<script>
const msgs=document.getElementById('messages');
const input=document.getElementById('input');
const send=document.getElementById('send');
const status=document.getElementById('status');
const form=document.getElementById('f');
function bubble(cls,text){const d=document.createElement('div');d.className='msg '+cls;d.textContent=text;msgs.appendChild(d);msgs.scrollTop=msgs.scrollHeight;return d;}
function toolDetail(label,body){const d=document.createElement('details');const s=document.createElement('summary');s.textContent=label;d.appendChild(s);const pre=document.createElement('pre');pre.textContent=body;pre.style.margin='.3rem 0 0';d.appendChild(pre);msgs.appendChild(d);msgs.scrollTop=msgs.scrollHeight;}
async function submit(){
  const msg=input.value.trim();
  if(!msg)return;
  input.value='';
  bubble('user',msg);
  send.disabled=true;
  status.textContent='…';
  try{
    const r=await fetch('/chat',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({msg})});
    const j=await r.json();
    if(j.ok){
      if(j.tools&&j.tools.length){for(const t of j.tools)toolDetail('tool: '+t.name,JSON.stringify(t,null,2));}
      bubble('agent',j.reply||'(no reply)');
    }else{
      bubble('err','ERROR: '+(j.error||'unknown'));
    }
  }catch(e){bubble('err','NET ERROR: '+e.message);}
  finally{send.disabled=false;status.textContent='';input.focus();}
}
form.addEventListener('submit',e=>{e.preventDefault();submit();});
input.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();submit();}});
</script></body></html>"))
