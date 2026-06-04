;;;; package.lisp — Test package for CLASSIC
;;;;
;;;; Uses FiveAM for test definition/running and cl-hamcrest for
;;;; composable CLOS-aware assertions.

(defpackage #:classic-tests
  (:use #:cl #:classic #:classic.dist.alpha)
  ;; Import FiveAM symbols explicitly to avoid package lock issues
  (:import-from #:fiveam
                #:def-suite #:in-suite #:def-test #:test
                #:is #:is-true #:is-false #:signals #:finishes
                #:explain! #:results-status)
  (:import-from #:hamcrest/fiveam
                #:assert-that)
  (:import-from #:hamcrest/matchers
                #:has-all
                #:has-plist-entries
                #:has-alist-entries
                #:has-hash-entries
                #:has-slots
                #:has-type
                #:instance-of
                #:has-length
                #:contains-in-any-order
                #:any
                #:_)
  ;; Shadow symbols that conflict between classic.schema.alpha and cl
  (:shadow #:label #:description #:body)
  (:export
   #:run-all-tests
   #:run-suite))
