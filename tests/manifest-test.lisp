(in-package #:cl-stack-mobile/tests)

(deftest ecl-pin-is-a-full-commit
  (let ((pin (ecl-pin)))
    (ok (string= "26.5.5" (getf pin :ecl-version)))
    (ok (= 40 (length (getf pin :ecl-commit))))
    (ok (string= "24" (getf pin :android-api)))))

(deftest subset-covers-the-ecl-lane
  (ok (subset-entry "event-protocol"))
  (ok (equal '("sqlite3") (getf (rest (subset-entry :sql-backend-sqlite3)) :natives)))
  (ok (= (length (mobile-subset))
         (length (remove-duplicates (mapcar #'first (mobile-subset)))))))

(deftest ironclad-stays-off-device
  (ok (member :crypto-protocol (device-subset)))
  (ng (member :crypto-backend-ironclad (device-subset))))
