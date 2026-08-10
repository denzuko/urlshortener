(defpackage :microservice/tests
  (:use :cl :fiveam :microservice))
 
(in-package :microservice/tests)

;; MAKE-SHORTEN-URL and NOTFOUND both depend on dynamic state that MAIN
;; normally sets up before serving requests -- an active datastore, and
;; (for anything touching HTTP status codes) a live Hunchentoot request.
;; Since this test run deliberately never calls MAIN, that state needs
;; setting up here instead. BKNR.DATASTORE is a singleton (one store per
;; Lisp session, per its own docs), so this happens once, at load time,
;; pointed at a throwaway directory rather than the real one.
(let ((test-store-dir (merge-pathnames "test-objstore/"
                                       (uiop:temporary-directory))))
  (when (uiop:directory-exists-p test-store-dir)
    (uiop:delete-directory-tree test-store-dir :validate t))
  (make-instance 'bknr.datastore:mp-store
                :directory (merge-pathnames "test-objstore/"
                                             (uiop:temporary-directory))
                :subsystems (list (make-instance 'bknr.datastore:store-object-subsystem))))

(def-suite urlshortener-tests)
(in-suite urlshortener-tests)

(test make-shorten-url-produces-a-seven-character-code
  "MAKE-SHORTEN-URL's returned short code must always be 7 characters."
  (is (= 7 (length (make-shorten-url "https://example.com/some/path")))))

(test make-shorten-url-round-trips-to-the-right-long-url
  "Looking up the code MAKE-SHORTEN-URL returns must find an object
   whose LONG-URL matches what was actually passed in. (Note: calling
   MAKE-SHORTEN-URL twice with the SAME long-url does NOT return the
   same code -- the second call's hash collides with the first call's
   own entry and walks the chain to a different one. That's real,
   verified behavior, not a test artifact -- see chat if this ever
   needs revisiting.)"
  (let* ((long-url "https://example.com/round-trip-test")
         (shrt (make-shorten-url long-url)))
    (is (string= long-url (shorten-url-long-url (shorten-url-by-short-url shrt))))))

(test plist-hash-converts-nested-plists
  "PLIST->HASH must turn nested plists into nested hash-tables, not JSON
   arrays -- this is the fix for the array-vs-object serialization bug."
  (let ((result (plist->hash (list :|a| (list :|b| 1)))))
    (is (hash-table-p result))
    (is (hash-table-p (gethash :|a| result)))
    (is (= 1 (gethash :|b| (gethash :|a| result))))))

(test plist-hash-leaves-plain-lists-as-arrays
  "A plain list (not a plist) must stay a list, so it still serializes
   as a JSON array."
  (is (equal '("a" "b" "c") (plist->hash (list "a" "b" "c")))))

(test notfound-returns-raw-data
  "NOTFOUND must return unserialized data, not a pre-stringified string --
   this is the fix for the double-JSON-encoding regression. Needs a
   faked *REPLY* since NOTFOUND sets an HTTP status code as a side
   effect, and that only exists inside a real request otherwise."
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (is (not (stringp (notfound "x"))))))
