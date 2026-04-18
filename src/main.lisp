;;; Startup:
;;;   (ql:quickload :photo-ai-lisp)
;;;   (photo-ai-lisp:start)

(in-package #:photo-ai-lisp)

(defvar *acceptor* nil)

(defparameter *categories* '(:unclassified :before :after :note))

(defun parse-int (value)
  (ignore-errors (parse-integer value)))

(defun parse-category (value)
  (let ((normalized (and value (string-downcase value))))
    (cond ((string= normalized "before") :before)
          ((string= normalized "after") :after)
          ((string= normalized "note") :note)
          (t :unclassified))))

(defun request-path ()
  (script-name*))

(defun photo-id-from-path ()
  (let* ((path (request-path))
         (start (length "/photo/"))
         (end (or (position #\/ path :start start) (length path))))
    (and (< start end) (parse-int (subseq path start end)))))

(defun render-category-options (selected)
  (loop for category in *categories* do
    (htm
     (:option :value (string-downcase (symbol-name category))
      :selected (when (eql selected category) "selected")
      (str (string-downcase (symbol-name category)))))))

(defun photos-page ()
  (layout "Photos"
    (:h2 "Photos")
    (:table :border "1" :cellpadding "6"
     (:tr (:th "ID") (:th "Path") (:th "Category") (:th "Uploaded") (:th "Link"))
     (dolist (photo (reverse (all-photos)))
       (htm
        (:tr
         (:td (str (photo-id photo)))
         (:td (str (photo-path photo)))
         (:td (str (string-downcase (symbol-name (photo-category photo)))))
         (:td (str (photo-uploaded-at photo)))
         (:td (:a :href (format nil "/photo/~D" (photo-id photo)) "Open"))))))))

(defun localhost-request-p ()
  "True when the current request's remote-addr is a loopback address."
  (let ((addr (remote-addr*)))
    (and addr (or (string= addr "127.0.0.1")
                  (string= addr "::1")
                  (string= addr "0:0:0:0:0:0:0:1")))))

(defun parse-and-eval-expr (expr)
  "Read and evaluate EXPR (a string) in the photo-ai-lisp package.
Returns a plist:
  (:ok T   :value STR :stdout STR)  on success
  (:ok NIL :error STR)              on any condition."
  (let ((*package* (find-package '#:photo-ai-lisp)))
    (handler-case
        (let* ((out (make-string-output-stream))
               (form (read-from-string expr))
               (value (let ((*standard-output* out)
                            (*error-output* out))
                        (eval form))))
          (list :ok t
                :value (with-output-to-string (s) (prin1 value s))
                :stdout (get-output-stream-string out)))
      (error (c)
        (list :ok nil :error (princ-to-string c))))))

(defun eval-dispatch ()
  (cond
    ((not (eq (request-method*) :POST))
     (setf (return-code*) 405) "Method Not Allowed")
    ((not (localhost-request-p))
     (setf (return-code*) 403) "Forbidden: /eval is localhost-only")
    (t
     (setf (content-type*) "application/json")
     (let* ((expr (or (post-parameter "expr") ""))
            (result (parse-and-eval-expr expr)))
       (with-output-to-string (s)
         (write-string "{\"ok\":" s)
         (write-string (if (getf result :ok) "true" "false") s)
         (cond ((getf result :ok)
                (write-string ",\"value\":" s)
                (yason:encode (getf result :value) s)
                (write-string ",\"stdout\":" s)
                (yason:encode (getf result :stdout) s))
               (t
                (write-string ",\"error\":" s)
                (yason:encode (getf result :error) s)))
         (write-string "}" s))))))

(defun chat-dispatch ()
  (cond
    ((not (eq (request-method*) :POST))
     (setf (return-code*) 405) "Method Not Allowed")
    ((not (localhost-request-p))
     (setf (return-code*) 403) "Forbidden: /chat is localhost-only")
    ((not (agent-alive-p))
     (setf (return-code*) 503)
     (setf (content-type*) "application/json")
     "{\"ok\":false,\"error\":\"agent is not running — call (photo-ai-lisp::start-agent) or ensure the configured command is on PATH\"}")
    (t
     (setf (content-type*) "application/json")
     (let ((msg (or (post-parameter "msg") "")))
       (handler-case
           (let ((reply (agent-send msg)))
             (with-output-to-string (s)
               (write-string "{\"ok\":true,\"reply\":" s)
               (yason:encode reply s)
               (write-string ",\"tools\":[]}" s)))
         (error (c)
           (with-output-to-string (s)
             (write-string "{\"ok\":false,\"error\":" s)
             (yason:encode (princ-to-string c) s)
             (write-string "}" s))))))))

(defun repl-page ()
  (setf (content-type*) "text/html; charset=utf-8")
  (format nil "<!DOCTYPE html>
<html lang=\"en\"><head><meta charset=\"utf-8\">
<title>photo-ai-lisp REPL</title>
<style>
 body{font-family:ui-monospace,Menlo,Consolas,monospace;margin:1rem;max-width:900px;color:#222}
 header h1{margin:.2rem 0}
 nav a{margin-right:.3rem}
 .warn{background:#fff3cd;border:1px solid #d39e00;color:#533f03;padding:.5rem;margin:.8rem 0;border-radius:4px}
 #history{background:#111;color:#ddd;padding:.6rem;height:380px;overflow-y:auto;white-space:pre-wrap;font-size:13px;border-radius:4px}
 #history .in{color:#8cf}
 #history .out{color:#cfc}
 #history .err{color:#f88}
 #history .stdout{color:#dca}
 textarea{width:100%;font-family:inherit;font-size:14px;padding:.4rem;box-sizing:border-box;margin-top:.5rem;border:1px solid #aaa;border-radius:4px}
 .chips{margin:.4rem 0}
 .chips button{font-family:inherit;font-size:12px;margin:.15rem .15rem 0 0;padding:.25rem .5rem;cursor:pointer;border:1px solid #888;background:#f4f4f4;border-radius:3px}
 .chips button:hover{background:#e0e8ff}
 footer{margin-top:1rem;color:#666;font-size:12px}
</style></head><body>
<header>
 <h1>photo-ai-lisp</h1>
 <nav><a href=\"/\">Home</a> | <a href=\"/photos\">Photos</a> | <a href=\"/upload\">Upload</a> | <a href=\"/scan\">Scan</a> | <a href=\"/manifest\">Manifest</a> | <a href=\"/pipeline\">Pipeline</a></nav>
</header>
<div class=\"warn\"><strong>Local dev only.</strong> Do not expose publicly &mdash; <code>/eval</code> runs arbitrary Lisp against the running image.</div>
<div id=\"history\"></div>
<div class=\"chips\">
 <button data-expr=\"(all-photos)\">(all-photos)</button>
 <button data-expr='(add-photo \"/img/sample.jpg\" :note)'>(add-photo ...)</button>
 <button data-expr=\"(length (all-photos))\">(length (all-photos))</button>
 <button data-expr=\"(find-photo 1)\">(find-photo 1)</button>
</div>
<textarea id=\"input\" rows=\"3\" placeholder=\"(+ 1 2)   \\u2014 Enter to eval, Shift+Enter for newline\" autofocus></textarea>
<footer>REPL-driven live-edit. Redefine handlers, DEFUNs, DEFVARs directly &mdash; changes take effect on the next request.</footer>
<script>
const hist=document.getElementById('history');
const input=document.getElementById('input');
function add(cls,text){const d=document.createElement('div');d.className=cls;d.textContent=text;hist.appendChild(d);hist.scrollTop=hist.scrollHeight;}
async function evalExpr(expr){
  add('in','> '+expr);
  try{
    const r=await fetch('/eval',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({expr})});
    const j=await r.json();
    if(j.stdout)add('stdout',j.stdout);
    if(j.ok)add('out',j.value);else add('err','ERROR: '+j.error);
  }catch(e){add('err','NET ERROR: '+e.message);}
}
input.addEventListener('keydown',e=>{
  if(e.key==='Enter'&&!e.shiftKey){
    e.preventDefault();
    const v=input.value.trim();
    if(v){evalExpr(v);input.value='';}
  }
});
document.querySelectorAll('.chips button').forEach(b=>b.addEventListener('click',()=>{input.value=b.dataset.expr;input.focus();}));
</script></body></html>"))

(defun upload-page ()
  (layout "Upload"
    (:form :action "/upload" :method "POST" :enctype "multipart/form-data"
     (:p "Path" (:br) (:input :type "text" :name "path"))
     (:p "Category" (:br)
      (:select :name "category" (render-category-options :unclassified)))
     (:p (:input :type "submit" :value "Save")))))

(defun photo-page (photo)
  (layout "Photo"
    (:h2 (str (format nil "Photo ~D" (photo-id photo))))
    (:p "Path: " (str (photo-path photo)))
    (:p "Uploaded: " (str (photo-uploaded-at photo)))
    (:form :action (format nil "/photo/~D/category" (photo-id photo)) :method "POST"
     (:p "Category" (:br)
      (:select :name "category" (render-category-options (photo-category photo))))
     (:p (:input :type "submit" :value "Update")))))

(defun pipeline-page ()
  (layout "Pipeline"
    (:h2 "Full pipeline")
    (:form :action "/pipeline/run" :method "POST"
     (:p "Photo directory" (:br) (:input :type "text" :name "dir" :size "60"))
     (:p (:input :type "submit" :value "Run pipeline")))
    (:div :id "status" (:p "No pipeline run yet."))
    (:script
     (str "var poll=setInterval(function(){fetch('/pipeline/status').then(r=>r.json()).then(function(steps){var h='<table border=1 cellpadding=4><tr><th>Step</th><th>Status</th><th>Info</th></tr>';steps.forEach(function(s){h+='<tr><td>'+s.name+'</td><td>'+s.status+'</td><td>'+(s.artifact||s.error||'')+'</td></tr>';});h+='</table>';document.getElementById('status').innerHTML=h;if(steps.every(function(s){return s.status==='done'||s.status==='failed';}))clearInterval(poll);});},2000);"))))

(defun pipeline-status ()
  (setf (content-type*) "application/json")
  (with-output-to-string (s)
    (yason:encode
     (mapcar (lambda (step)
               (let ((h (make-hash-table :test 'equal)))
                 (setf (gethash "name"     h) (getf step :name)
                       (gethash "status"   h) (string-downcase (symbol-name (getf step :status)))
                       (gethash "artifact" h) (or (getf step :artifact) "")
                       (gethash "error"    h) (or (getf step :error) ""))
                 h))
             (or *pipeline-state* '()))
     s)))

(defun pipeline-run-dispatch ()
  (if (eq (request-method*) :POST)
      (let ((dir (post-parameter "dir")))
        (run-pipeline dir)
        (redirect "/pipeline"))
      (progn (setf (return-code*) 405) "Method Not Allowed")))

(defun scan-page ()
  (layout "Scan"
    (:h2 "Scan photo directory")
    (:form :action "/scan" :method "POST"
     (:p "Directory path" (:br) (:input :type "text" :name "dir" :size "60"))
     (:p (:input :type "submit" :value "Scan")))))

(defun manifest-page ()
  (layout "Manifest"
    (:h2 "Photo manifest")
    (if *current-manifest*
        (htm
         (:p (str (format nil "~A photos" (length *current-manifest*))))
         (:table :border "1" :cellpadding "4"
          (:tr (:th "File") (:th "Dir") (:th "Date") (:th "OCR preview"))
          (dolist (rec *current-manifest*)
            (let ((ocr (or (gethash "ocr_text" rec) "")))
              (htm (:tr
                    (:td (str (gethash "file_name" rec "")))
                    (:td (str (gethash "dir_name" rec "")))
                    (:td (str (gethash "date" rec "")))
                    (:td (str (if (> (length ocr) 60)
                                  (subseq ocr 0 60)
                                  ocr)))))))))
        (htm (:p "No manifest loaded. Run a scan first.")))))

(defun scan-dispatch ()
  (cond
    ((eq (request-method*) :GET) (scan-page))
    ((eq (request-method*) :POST)
     (let ((dir (post-parameter "dir")))
       (handler-case
           (progn
             (setf *current-manifest* (run-skill "photo-scan" dir))
             (redirect "/manifest"))
         (skill-error (e)
           (layout "Scan error"
             (:h2 "Scan failed")
             (:pre (str (skill-error-stderr e))))))))
    (t (setf (return-code*) 405) "Method Not Allowed")))

(defun upload-dispatch ()
  (cond ((eq (request-method*) :GET) (upload-page))
        ((eq (request-method*) :POST)
         (add-photo (or (post-parameter "path") "")
                    (parse-category (post-parameter "category")))
         (redirect "/"))
        (t (setf (return-code*) 405) "Method Not Allowed")))

(defun photo-dispatch ()
  (let* ((id (photo-id-from-path))
         (photo (and id (find-photo id))))
    (cond ((null photo) (setf (return-code*) 404) "Not Found")
          ((and (eq (request-method*) :GET)
                (search "/category" (request-path))) (setf (return-code*) 405) "Method Not Allowed")
          ((eq (request-method*) :GET) (photo-page photo))
          ((and (eq (request-method*) :POST)
                (search "/category" (request-path)))
           (set-photo-category (photo-id photo)
                               (parse-category (post-parameter "category")))
           (redirect "/"))
          (t (setf (return-code*) 405) "Method Not Allowed"))))

(defun start (&key (port 8080) (start-agent-p t))
  (unless *acceptor*
    (load-photos)
    (when start-agent-p
      (handler-case (start-agent)
        (error (c)
          (format *error-output*
                  "~&[photo-ai-lisp] agent spawn failed (~A). /chat will return 503 until (start-agent) succeeds.~%" c))))
    (setf *acceptor* (make-instance 'easy-acceptor :port port))
    (setf *dispatch-table*
          (list (create-prefix-dispatcher "/pipeline/run" 'pipeline-run-dispatch)
                (create-prefix-dispatcher "/pipeline/status" 'pipeline-status)
                (create-prefix-dispatcher "/pipeline" 'pipeline-page)
                (create-prefix-dispatcher "/manifest" 'manifest-page)
                (create-prefix-dispatcher "/scan" 'scan-dispatch)
                (create-prefix-dispatcher "/photos" 'photos-page)
                (create-prefix-dispatcher "/photo/" 'photo-dispatch)
                (create-prefix-dispatcher "/upload" 'upload-dispatch)
                (create-prefix-dispatcher "/chat" 'chat-dispatch)
                (create-prefix-dispatcher "/repl" 'repl-page)
                (create-prefix-dispatcher "/eval" 'eval-dispatch)
                (create-prefix-dispatcher "/" 'agent-page)))
    (hunchentoot:start *acceptor*))
  *acceptor*)

(defun stop ()
  (when *acceptor*
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil))
  (ignore-errors (stop-agent)))
