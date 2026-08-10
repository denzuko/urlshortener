(ql:quickload '(hunchentoot
                easy-routes
                com.inuoe.jzon
                bknr.datastore
                ironclad
                babel
                cl-base64) :silent t)

(defpackage :microservice
  (:use :cl)
  (:export #:with-auth
           #:with-json
           #:with-text
           #:call-with-response
           #:route!
           #:redirect!
           #:ok
           #:unimplimented
           #:notfound
           #:notauthenticated
           #:notauthorized
           #:make-shorten-url
           #:shorten-url-long-url
           #:shorten-url-by-short-url
           #:shorten-url
           #:all-shorten-urls
           #:plist->hash))

(in-package :microservice)

(defclass shorten-url (bknr.datastore:store-object)
  ((short-url :initarg :short-url
              :reader shorten-url-short-url
              :index-type bknr.datastore::string-unique-index
              :index-reader shorten-url-by-short-url
              :index-values all-shorten-urls)
   (long-url  :initarg :long-url :reader shorten-url-long-url))
  (:metaclass bknr.datastore:persistent-class))

(defun make-shorten-url (long-url)
  "Converts full URL to md5 hash"
  (let ((data (babel:string-to-octets long-url :encoding :utf-8)))
    (do* ((curr (ironclad:digest-sequence :md5 data)
                (ironclad:digest-sequence :md5 curr))
          (shrt (subseq (cl-base64:usb8-array-to-base64-string curr :uri t) 0 7)
                (subseq (cl-base64:usb8-array-to-base64-string curr :uri t) 0 7)))
      ((not (shorten-url-by-short-url shrt))
       (values shrt (make-instance 'shorten-url :short-url shrt :long-url long-url))))))

(defun plist->hash (x)
  "Recursively converts plists (lists of alternating keyword keys and
   values) into hash-tables so com.inuoe.jzon:stringify serializes
   them as json objects rather than arrays. Plain lists (already
   hash-tables, or genuine sequences meant to stay json arrays) pass
   through unconverted at that level."
  (cond ((hash-table-p x)
         (let ((h (make-hash-table :test 'equal)))
           (maphash (lambda (k v) (setf (gethash k h) (plist->hash v))) x)
           h))
        ((and (consp x) (keywordp (car x)) (evenp (length x)))
         (let ((h (make-hash-table :test 'equal)))
           (loop for (k v) on x by #'cddr
                 do (setf (gethash k h) (plist->hash v)))
           h))
        ((consp x) (mapcar #'plist->hash x))
        (t x)))

(defun call-with-response (content-type serializer error-formatter thunk)
  "Runs THUNK, setting CONTENT-TYPE and serializing THUNK's return value via
  the serializer. On error, sets a 500 status and serialises an error
  payload via the error-formater"
  (setf (hunchentoot:content-type*) content-type)
  (handler-case
    (funcall serializer (funcall thunk))
    (error (c)
         (setf (hunchentoot:return-code*) hunchentoot:+http-internal-server-error+)
         (funcall error-formatter c))))

(defmacro with-text (&body body) 
  "defines an easy-route handler for text"
`(call-with-response "text/plain"
                     #'identity
                     (lambda (c) (format nil "Internal Server Error: ~a" c))
                     (lambda () (progn ,@body))))

(defmacro with-json (&body body)
  "defines an easy-route handler for json"
  `(call-with-response "application/json"
                       #'com.inuoe.jzon:stringify
                       (lambda (c)
                         (com.inuoe.jzon:stringify (list 
                                        :|error| "Internal Server Error"
                                        :|message| (format nil "~a" c))))
                       (lambda () (progn ,@body))))

(defmacro with-auth ((&key method) &body body)
  "Authentication/authorization gate. :METHOD selects :KRB5, :OIDC, or
   :AUTHZ. None are implemented yet -- each currently reports 501 via
   UNIMPLIMENTED (fail-closed; BODY never runs) rather than silently
   allowing access or erroring. When a real backend lands, its branch
   should perform the credential check and COND the result into: BODY
   on success, (NOTAUTHENTICATED ...) for missing/invalid credentials,
   or (NOTAUTHORIZED ...) for valid-but-insufficient permission."
  (declare (ignore body))
  (ecase method
    (:krb5  `(unimplimented "krb5 keytab auth"))
    (:oidc  `(unimplimented "OIDC auth"))
    (:authz `(unimplimented "authz auth"))))

(defmacro ok ()
  "Returns a json message on 200"
  `(progn
     (setf (hunchentoot:return-code*) 200)
     (list :|status| 200 :|message| "OK")))

(defun unimplimented (identifier)
  "Returns a json message on 501"
  (setf (hunchentoot:return-code*) 501)
  (list :|error| "not found"
        :|message| (format nil "~a not implimented" identifier)))

(defun notfound (identifier)
  "Returns a json message on 404"
  (setf (hunchentoot:return-code*) 404)
  (list :|error| "not found"
        :|message| (format nil "~a not found" identifier)))

(defun notauthenticated (identifier)
  "Returns a json message on 401"
  (setf (hunchentoot:return-code*) 401)
  (list :|error| "not authorized"
        :|message| (format nil "~a not authenticated" identifier)))

(defun notauthorized (identifier)
  "Returns a json message on 403"
  (setf (hunchentoot:return-code*) 403)
  (list :|error| "not authorized"
        :|message| (format nil "~a not authorized" identifier)))

(defmacro redirect! (url)
  `(return-from route (hunchentoot:redirect ,url)))

(defmacro route! ((&key name path 
                        (method :GET) 
                        (parse-body t)
                        (content-type :json)
                        (auth nil))
                  &body body)
  "Factory router macro"
  (let ((body-var (intern "BODY" *package*)))
  `(easy-routes:defroute ,name (,path :method ,method) () 
    (block route
      (let* (,@(when parse-body
                `((,body-var (let ((raw (hunchentoot:raw-post-data :want-stream nil :force-text t)))
                          (cond ((and raw (plusp (length raw))) (com.inuoe.jzon:parse raw))
                                (t (make-hash-table :test 'equal))))))))
         (declare (ignorable ,@(when parse-body (list body-var))))
         ,(let ((inner (if auth
                         `(with-auth (,@auth) ,@body)
                         `(progn ,@body))))
            (ecase content-type
              (:json `(with-json (plist->hash ,inner)))
              (:text `(with-text ,inner)))))))))

