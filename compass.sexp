;;; compass.sexp — Compass project manifest for Classic
;;;
;;; Read by the compass toolchain with a restricted reader: strings, integers,
;;; keywords, and lists only. See COMPASS-DRAFT-toolchain-D4 and D15 in the
;;; Compass repository.

(:namespaces ("CLASSIC")
 :doc-directory "doc/"
 :federation ((:namespace "COMPASS" :path "../compass")
              (:namespace "ORIGIN" :path "../origin")
              (:namespace "LEXTER" :path "../../chat/lexter"))
 :commands ((:name :test
             :repl "(progn (ql:quickload \"classic/tests\") (classic-tests::run-all-tests))"
             :doc "Run Classic's test suite"))
 :stewards ((:namespace "CLASSIC" :steward "Andrew Sengul" :approval :solo)))
