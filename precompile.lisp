#|
 This file is a part of Qtools
 (c) 2015 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.qtools)

;;;;;
;; File processing

(defun write-forms (stream)
  "Writes all compileable forms to STREAM.

See QTOOLS:MAP-COMPILE-ALL"
  (let ((i 0))
    (map-compile-all
     (lambda (form)
       (incf i)
       (when (= 0 (mod i 1000))
         (format T "~&; On ~dth form..." i))
       (when form
         (dolist (form (if (eql (car form) 'progn)
                           (cdr form)
                           (list form)))
           (print form stream))
         (format stream "~%"))))
    (format T "~&; ~d forms processed." i)))

(defun write-everything-to-file (pathname &key (package *target-package*) (if-exists :supersede))
  "Writes all compileable Qt method wrappers to PATHNAME.

PACKAGE designates in which package the symbols will live.
This makes it possible to deviate from the standard of
*TARGET-PACKAGE*. The value of QTOOLS:*TARGET-PACKAGE*
will be automatically set to this once the resulting file
is LOADed or compiled again.

See QTOOLS:WRITE-FORMS
See QTOOLS:*TARGET-PACKAGE*"
  (let* ((package (cond ((typep package 'package) package)
                        ((find-package package) (find-package package))
                        (T (make-package package))))
         (modules (loaded-smoke-modules))
         (*target-package* package)
         (*package* (find-package '#:cl-user)))
    (with-open-file (stream pathname :direction :output :if-exists if-exists)
      (format T "~&;;;; Writing to file ~a" pathname)
      (format stream "~&;;;;; Automatically generated file to map Qt methods and enums to CL functions and constants.")
      (format stream "~&;;;;; See QTOOLS:WRITE-EVERYTHING-TO-FILE")
      (format stream "~&;;;;")
      (format stream "~&;;;; Active smoke modules: ~{~a~^ ~}" modules)
      (print `(in-package #:cl-user) stream)
      (print `(eval-when (:compile-toplevel :load-toplevel :execute)
                (unless (find-package "QTOOLS")
                  (error "Qtools needs to be loaded first!"))
                (dolist (module ',modules)
                  (qt:ensure-smoke module))
                (setf qtools:*target-package*
                      (or (find-package ,(package-name package))
                          (make-package ,(package-name package) :use ())))) stream)
      (write-forms stream)
      pathname)))

(defun q+-compile-and-load (&key modules (file (merge-pathnames "q+.lisp" (uiop:temporary-directory))))
  "Writes, compiles, and loads the file for all generated Qt wrapper functions.
If MODULES is passed, CommonQt is reloaded and only the given modules are loaded.

See WRITE-EVERYTHING-TO-FILE"
  (when modules
    (qt::reload)
    (apply #'load-all-smoke-modules modules))
  (load (compile-file (write-everything-to-file file) :print NIL) :print NIL))


;;;;;
;; ASDF components

(defun load-for-wrapper (c)
  (etypecase (smoke-module c)
    ((or symbol string) (load-all-smoke-modules (smoke-module c)))
    (list (apply #'load-all-smoke-modules (smoke-module c))))
  T)

(defclass smoke-module-system (asdf:system)
  ((smoke-module :accessor smoke-module :initarg :module :initform NIL))
  (:documentation "A wrapper ASDF system class that only exists to ensure that a
given smoke module is loaded at compile and load time."))

(defmethod asdf:perform ((op asdf:compile-op) (c smoke-module-system))
  (load-for-wrapper c))

(defmethod asdf:perform ((op asdf:load-op) (c smoke-module-system))
  (load-for-wrapper c))

(defun compile-smoke-module-system-definition (module)
  "Creates an ASDF:DEFSYSTEM form for the MODULE.

See QTOOLS:SMOKE-MODULE-SYSTEM"
  `(asdf:defsystem ,(make-symbol (string-upcase module))
     :defsystem-depends-on (:qtools)
     :class "qtools::smoke-module-system"
     :module ,(string-upcase module)))

(defun write-smoke-module-system-file (module)
  "Writes a SMOKE-MODULE-SYSTEM form to the proper file in the \"smoke\" subfolder of Qtools.

See QTOOLS:COMPILE-SMOKE-MODULE-SYSTEM-DEFINITION"
  (let ((file (asdf:system-relative-pathname :qtools (format NIL "smoke/~(~a~).asd" module))))
    (with-open-file (stream file :direction :output :if-exists :supersede)
      (let ((*package* (find-package :cl-user)))
        (print '(in-package #:cl-user) stream)
        (print (compile-smoke-module-system-definition module) stream)))
    file))

(defun write-all-smoke-module-system-files ()
  "Writes module system files for all possible smoke modules.

See QTOOLS:WRITE-SMOKE-MODULE-SYSTEM-FILE
See QTOOLS:*SMOKE-MODULES*"
  (dolist (module *smoke-modules*)
    (write-smoke-module-system-file module)))
