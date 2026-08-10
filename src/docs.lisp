(ql:quickload '(40ants-doc 40ants-doc-full) :silent t)

(defpackage :microservice/docs
  (:use :cl :40ants-doc :microservice))

(in-package :microservice/docs)

(defsection @microservice-manual (:title "microservice.ros — Roswell URL Shortener")
  "A small Hunchentoot/easy-routes url-shortener service, backed by
   bknr.datastore, with json and Prometheus-text response modes."
  (microservice:with-auth macro)
  (microservice:with-json macro)
  (microservice:with-text macro)
  (microservice:call-with-response function)
  (microservice:route! macro)
  (microservice:redirect! macro)
  (microservice:ok macro)
  (microservice:unimplimented function)
  (microservice:notfound function)
  (microservice:notauthenticated function)
  (microservice:notauthorized function)
  (microservice:make-shorten-url function)
  (microservice:shorten-url class)
  (microservice:shorten-url-by-short-url function)
  (microservice:shorten-url-long-url generic-function)
  (microservice:plist->hash function))
