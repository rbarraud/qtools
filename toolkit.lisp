#|
 This file is a part of Qtools
 (c) 2014 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.qtools)
(named-readtables:in-readtable :qt)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; We need this here so that we can use FIND-QCLASS.
  (ensure-smoke :qtcore)
  (ensure-smoke :qtgui))

;;;;;
;; Qt Related Utils

(defun qobject-alive-p (object)
  "Returns T if the object is not null and not deleted."
  (not (or (null-qobject-p object)
           (qobject-deleted object))))

(defun maybe-delete-qobject (object)
  "Deletes the object if possible."
  (if (typep object 'abstract-qobject)
      (when (qobject-alive-p object)
        #+:verbose (v:trace :qtools "Deleting QObject: ~a" object)
        (optimized-delete object))
      #+:verbose (v:trace :qtools "Deleting QObject: WARN Tried to delete non-qobject ~a" object)))

(defgeneric copy-using-class (qclass instance)
  (:documentation "Creates a copy of the given instance by using methods
appropriate for the given qclass.")
  #+:verbose
  (:method :before (qclass instance)
    (v:trace :qtools "Copying: ~a" instance)))

(defgeneric copy (instance)
  (:documentation "Generates a copy of the qobject.
Uses COPY-QOBJECT-USING-CLASS and determines the class by QT::QOBJECT-CLASS.")
  (:method (instance)
    (copy-using-class
     (qt::qobject-class instance) instance)))

(defmacro define-copy-method ((instance class) &body body)
  "Defines a method to copy an object of CLASS.
CLASS can be either a common-lisp class type or a Qt class name.

Qt class names will take precedence, meaning that if CLASS resolves
to a name using FIND-QT-CLASS-NAME a COPY-QOBJECT-USING-CLASS method
is defined on the respective qt-class. Otherwise a COPY-QOBJECT method
is defined with the CLASS directly as specializer for the instance.

In cases where you need to define a method on a same-named CL class,
directly use DEFMETHOD on COPY-QOBJECT.

See COPY-QOBJECT, COPY-QOBJECT-USING-CLASS"
  (let ((qclass (gensym "QCLASS"))
        (qt-class-name (find-qt-class-name class)))
    (if qt-class-name
        `(defmethod copy-using-class ((,qclass (eql (find-qclass ,qt-class-name))) ,instance)
           (declare (ignore ,qclass))
           ,@body)
        `(defmethod copy ((,instance ,class))
           ,@body))))

(define-copy-method (instance QColor)
  (#_new QColor instance))

(define-copy-method (instance QImage)
  (#_copy instance (#_rect instance)))

(define-copy-method (instance QPixmap)
  (#_copy instance (#_rect instance)))

(define-copy-method (instance QTransform)
  (#_new QTransform
         (#_m11 instance) (#_m12 instance) (#_m13 instance)
         (#_m21 instance) (#_m22 instance) (#_m23 instance)
         (#_m31 instance) (#_m32 instance) (#_m33 instance)))

(defmacro qtenumcase (keyform &body forms)
  "Just like CASE, but for Qt enums using QT:ENUM=."
  (let ((key (gensym "KEY")))
    `(let ((,key ,keyform))
       (cond ,@(loop for (comp . form) in forms
                     collect (if (or (eql comp T)
                                     (eql comp 'otherwise))
                                 `(T ,@form)
                                 `((qt:enum= ,key ,comp) ,@form)))))))

(defun enumerate-method-descriptors (name args)
  "Returns a list of all possible method descriptors with NAME and ARGS.
Args may be either a list of direct types to use or a list of alternative types.
In the case of lists, the argument alternatives are taken in parallel.

Examples: 
 (.. foo '(a b)) => (\"foo(a,b)\")
 (.. foo '((a b))) => (\"foo(a)\" \"foo(b)\")
 (.. foo '((a b) (0 1))) => (\"foo(a,0)\" \"foo(b,1)\")"
  (flet ((make-map (args)
           (format NIL "~a(~{~(~a~)~^, ~})" name args)))
    (cond
      ((and args (listp (first args)))
       (loop for i from 0 below (length (first args))
             collect (make-map (mapcar #'(lambda (list) (nth i list)) args))))
      (T
       (list (make-map args))))))

;;;;;
;; General utils

(defun ensure-class (thing)
  "Ensures to return a CLASS.
SYMBOL -> FIND-CLASS
CLASS  -> IDENTITY
STANDARD-OBJECT -> CLASS-OF"
  (etypecase thing
    (symbol (find-class thing))
    (class thing)
    (standard-object (class-of thing))))

(defmacro with-slots-bound ((instance class) &body body)
  "Turns into a WITH-SLOTS with all direct-slots of CLASS.
Class is resolved as per ENSURE-CLASS."
  (let ((slots (loop for slot in (c2mop:class-direct-slots
                                  (ensure-class class))
                     for name = (c2mop:slot-definition-name slot)
                     collect name)))
    `(with-slots ,slots ,instance
       (declare (ignorable ,@slots))
       ,@body)))

(defun fuse-plists (&rest plists-lists)
  (let ((target (make-hash-table)))
    (dolist (plists plists-lists)
      (loop for (option args) on plists by #'cddr
            do (setf (gethash option target)
                     (nconc (gethash option target) args))))
    (loop for key being the hash-keys of target
          for val being the hash-values of target
          appending (list key val))))

(defun fuse-alists (&rest alists-lists)
  (let ((target (make-hash-table)))
    (dolist (alists alists-lists)
      (loop for (option . args) in alists
            do (setf (gethash option target)
                     (append args (gethash option target)))))
    (loop for key being the hash-keys of target
          for val being the hash-values of target
          collect (cons key val))))

(defun split (list items &key (key #'identity) (test #'eql))
  "Segregates items in LIST into separate lists if they mach an item in ITEMS.
The first item in the returned list is the list of unmatched items.

Example:
 (split '((0 a) (0 b) (1 a) (1 b) (2 c)) '(0 2) :key #'car)
 => '(((1 a) (1 b)) ((0 a) (0 b)) ((2 c))) "
  (loop with table = ()
        for item in list
        do (push item (getf table (find (funcall key item) items :test test)))
        finally (return (cons (nreverse (getf table NIL))
                              (loop for item in items
                                    collect (nreverse (getf table item)))))))

(defmacro with-compile-and-run (&body body)
  "Compiles BODY in a lambda and funcalls it."
  `(funcall
    (compile NIL `(lambda () ,,@body))))

(defun maybe-unwrap-quote (thing)
  "If it is a quote form, unwraps the contents. Otherwise returns it directly."
  (if (and (listp thing)
           (eql 'quote (first thing)))
      (second thing)
      thing))
