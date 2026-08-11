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

(defstruct create-request
  "Validation payload for POST /"
  (long-url nil :type (or null string)))

(defun parse-create-request (body)
  "Validates adn extracts a create-request from the paresed json BODY
  Hashtable. Returns the struct on success or nil if slots are missing/invalid"
  (let ((long-url (gethash "long-url" body)))
    (when (and long-url (stringp long-url) (plusp (length long-url)))
      (make-create-request :long-url long-url))))

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
  payload via the error-formatter"
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
                         (com.inuoe.jzon:stringify ((plist->hash (list 
                                        :|error| "Internal Server Error"
                                        :|message| (format nil "~a" c)))))
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

(defmacro defresponse (name code message-format (&optional error-format))
  "Defines a function NAME tat takes an IDENIFIER and sets http status CODE
  then returns a json object. If ERROR-TEXT is given, the payload adds it.
  Otherwise message payload is sent"
  `(defun ,name (identifier)
     ,(format nil "Returns a json message on ~d" code)
     (setf (hunchentoot:return-code*) ,code)
     ,(if (error-text) 
          `(list :|error| ,error-text 
                 :|message| (format nil ,message-format identifier))
          `(list :|message| (format nil ,message-format identifier))))))

(defresponse badrequest       400 "~a" "bad request")
(defresponse notfound         404 "~a not found" "not found")
(defresponse notauthenticated 401 "~a not authenticated" "not authorized")
(defresponse notauthorized    403 "~a not authorized" "not authorized")
(defresponse unimplemented    501 "~a not implimented" "not found")
(defresponse ok               200 "OK")

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

