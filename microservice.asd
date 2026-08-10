;; microservice.asd
(asdf:defsystem :microservice
  :depends-on (:hunchentoot :easy-routes :com.inuoe.jzon :bknr.datastore
               :ironclad :babel :bordeaux-threads :cl-base64)
  :components ((:file "src/api"))
  :in-order-to ((asdf:test-op (asdf:test-op :microservice/tests))))

(asdf:defsystem :microservice/docs
  :depends-on (:microservice :40ants-doc :40ants-doc-full)
  :components ((:file "src/docs"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :fiveam :run! :urlshortener-tests)))

(asdf:defsystem :microservice/tests
  :depends-on (:microservice :fiveam)
  :components ((:file "t/test"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :fiveam :run! :urlshortener-tests)))
