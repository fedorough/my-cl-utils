(in-package #:df-cl-utils)

;; utils


(defgeneric traverse-slots (obj fn)
  (:documentation "Use fn function on each slot. 'fn' must take two parameters: slot-name and slot-value."))

(defmethod traverse-slots (obj fn)
  (labels ((%traverse-slots (slots-lst)
             (when slots-lst
               (let* ((slot (car slots-lst))
                      (def-name (sb-mop:slot-definition-name slot))
                      (name (symbol-name def-name))
                      (value (slot-value obj def-name)))
                 (funcall fn name value)
                 (%traverse-slots (cdr slots-lst))))))
    (%traverse-slots (sb-mop:class-slots (class-of obj)))))


(defgeneric pretty-print-object (obj stream)
  (:documentation "Pretty printer for objects. Prints all slots with format 'SLOT-NAME: SLOT-VALUE'"))

(defmethod pretty-print-object (obj stream)
  (format stream (with-output-to-string (s)
                   (traverse-slots obj (lambda (name val) (format s "~A: ~S~%" name val))))))

;;

(defmacro defclass* (name direct-superclasses &rest direct-slots)
  `(defclass ,name ,direct-superclasses
     ,(when direct-slots
        (mapcar (lambda (slot-def)
                  (let ((slotname (first slot-def)))
                    (list slotname :accessor (intern (symbol-name slotname))
                                   :initarg (intern (symbol-name slotname) "KEYWORD")
                                   :initform (second slot-def))))
                direct-slots))))

(defun mappend (function &rest lists)
  "Applies FUNCTION to respective element(s) of each LIST, appending all the
all the result list to a single list. FUNCTION must return a list."
  (loop for results in (apply #'mapcar function lists)
        append results))

(defmacro format* (fmt-or-string size &key (format-letter :A) align truncate? (stream nil))
  `(format*-aux ,(if (and (listp fmt-or-string) (stringp (first fmt-or-string))) `(format nil ,@fmt-or-string) fmt-or-string) ,size :format-letter ,format-letter :align ,align :truncate? ,truncate? :stream ,stream))

(defun format*-aux (string size &key format-letter align truncate? stream)
  (labels ((%wut-align ()
             (cond ((or (eq align :right) (eq align :r)) t)
                   ((or (eq align :left) (eq align :l)) nil)
                   (t nil)))
           (%truncate-string-maybe ()
             (if (and truncate? (> (length string) size)) (subseq string 0 size) string)))
    (format stream
            (format nil "~~~A~:[~;@~]~A" size (%wut-align) format-letter)
            (%truncate-string-maybe))))

;; vars

(defvar *dbp-counter* 0)
(defvar *dbp-format* nil)
(defvar *dbp-options* nil)

;;

(defun count++ ()
  (incf *dbp-counter*))

(defun dbp-reset-counter ()
  (setf *dbp-counter* 0))

;; format

(defclass* fmt-size-mixin ()
  (size 1))

(defclass* fmt-braces-mixin ()
  (brace-left "")
  (brace-right ""))

(defmethod apply-braces ((braces fmt-braces-mixin) str &key (format-string "~A~A~A"))
  (with-slots (brace-left brace-right) braces
    (format nil format-string brace-left str brace-right)))

(defclass* fmt-clip (fmt-size-mixin)
  (size 2)
  (up "┌")
  (down "└")
  ;; (horizontal "─")
  (horizontal " ")
  (vertical "│")
  (oneline "-")
  (side :left))

(defclass* fmt-counter (fmt-size-mixin fmt-braces-mixin)
  (size 4)
  (brace-right "> "))

(defclass* fmt-prefix (fmt-size-mixin fmt-braces-mixin)
  (size 16))

(defclass* fmt-msg (fmt-size-mixin fmt-braces-mixin)
  (size 60))

(defclass* fmt ()
  (clip (make-instance 'fmt-clip))
  (counter (make-instance 'fmt-counter))
  (prefix (make-instance 'fmt-prefix))
  (msg (make-instance 'fmt-msg)))

;; (build-fmt
;; '(
;;  (:clip :size 1 :up "┌" :down "└" :vertical "│" :horizontal "─" :side :left)
;;  (:counter :size 4 :brace-left "" :brace-right ">")
;;  (:prefix :size 16 :brace-left "" :brace-right "")
;;  (:msg :size 60 :brace-left "" :brace-right "")
;;  ))
(defun build-fmt (clauses)
  (labels ((%parse-fmt-clauses (clauses)
             (mappend (lambda (clause)
                       (let ((type (first clause))
                             (initargs (rest clause)))
                         (list type (apply #'make-instance (intern (format nil "FMT-~A" (symbol-name type)) :df-cl-utils) initargs))))
                      clauses)))
    (if (equalp clauses'(nil))
        (make-instance 'fmt)
        (apply #'make-instance 'fmt (%parse-fmt-clauses clauses)))
    ))

;; options

(defclass* options ()
  ;; commands
  (com/nl "$nl")
  (com/cond-nl "$_nl") ; conditional newline
  (com/delim "$d")
  (com/delim-len 2)
  ;;
  (out t) ; output stream
  (w-delim " ") ; thing that would delimit tokens
  (nl-before-com/delim? t) ; newline before line delimiter
  (nl-after-com/delim? t) ; newline after line delimiter
  (delim-len 60)
  (macros nil)) ; (:-> "arrow, lol" :<> "туди-сюди")

(defun build-options (clauses)
  (if (equalp clauses '(nil))
      (make-instance 'options)
      (apply #'make-instance 'options clauses)))

;; prepare

(defmethod prepare-clip ((clip fmt-clip) place)
  (with-slots (up oneline down vertical horizontal size side brace-left brace-right) clip
    (labels ((%build-corner (corner-char)
               (let* ((corner-char (format* corner-char 1 :truncate? t))
                      (rest (format* horizontal (1- size) :truncate? t))
                      (left-part (if (eq side :left) corner-char rest))
                      (right-part (if (eq side :left) rest corner-char)))
                 (format nil "~A~A" left-part right-part)))
             (%build-mid (char)
               (format* char size :align side :truncate? t)))
      (case place
        (:upper (%build-corner up))
        (:oneline (%build-mid oneline))
        (:middle (%build-mid vertical))
        (:lower (%build-corner down))))))

(defmethod prepare-clips ((clip fmt-clip))
  (list (prepare-clip clip :upper)
        (prepare-clip clip :oneline)
        (prepare-clip clip :middle)
        (prepare-clip clip :lower)))

(defmethod prepare-counter ((counter fmt-counter))
  (with-slots (size brace-left brace-right) counter
     (format* (apply-braces counter *dbp-counter*) size)))

(defmethod prepare-prefix ((prefix fmt-prefix) str)
  (with-slots (size brace-left brace-right) prefix
    (format* (apply-braces prefix str) size :truncate? t)))

;; (defmethod prepare-msg (()))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun parse-dbp-clauses (clauses)
    (let ((prefix-list nil)
          (msg-list nil)
          (context :msg)
          (fmt-init-list nil)
          (opts-init-list nil)
          ;; syntax settings
          (prefix-command "p>>")
          (message-command "msg>>")
          (format-command "fmt>>")
          (options-command "opts>>")
          )
      (labels ((%context-dep-push (el)
                 (case context
                   (:msg (push el msg-list))
                   (:p   (push el prefix-list))
                   (t (error "wut"))))
               (%lst (lst)
                 (let ((el1 (first lst)))
                   (if (stringp el1)
                       (%context-dep-push `(format nil ,el1 ,@(rest lst)))
                       (%context-dep-push lst))))
               (%fmt () (setf fmt-init-list (pop clauses)))
               (%opts () (setf opts-init-list (pop clauses)))
               (%sym (sym)
                 (let ((name (symbol-name sym)))
                   (cond ((string-equal name prefix-command) (setf context :p))
                         ((string-equal name message-command) (setf context :msg))
                         ((string-equal name format-command) (%fmt))
                         ((string-equal name options-command) (%opts))
                         (t (%context-dep-push sym)))))
               (%parse ()
                 (let ((el1 (pop clauses)))
                   (cond
                     ((stringp el1) (%context-dep-push el1))
                     ((listp el1)   (%lst el1))
                     ((symbolp el1) (%sym el1))
                     ((numberp el1) (%context-dep-push el1))))
                 (when clauses (%parse))))
        (%parse)
        (values (nreverse prefix-list)
                (nreverse msg-list)
                (build-fmt fmt-init-list)
                (build-options opts-init-list))))))

(defmacro dbp2 (&body clauses)
  (multiple-value-bind (prefix-list msg-list frmt opts)
      (parse-dbp-clauses clauses)
    (let ((prefix-format-str (make-string-output-stream))
          (prefix-format-args nil)
          (msg-format-str (make-string-output-stream))
          (msg-format-args nil)
          (context nil))
      (labels ((%write-by-context (str &optional (use-w-delim? t))
                 (let ((format-args `("~A~A" ,str ,(if use-w-delim? (w-delim opts) ""))))
                   (cond ((eq context :p) (apply #'format prefix-format-str format-args))
                         ((eq context :msg) (apply #'format msg-format-str format-args))
                         (t (error "wut2")))))
               (%add-arg-by-context (el)
                 (cond ((eq context :p) (setf prefix-format-args (append prefix-format-args (list el))))
                       ((eq context :msg) (setf msg-format-args (append msg-format-args (list el))))
                       (t (error "wut3"))))
               (%write/add-arg (str el) (%write-by-context str) (%add-arg-by-context el))
               (%construct-delim (delim-el)
                 (let* ((len (delim-len opts))
                        (nl-bef (if (nl-before-com/delim? opts) "~_" ""))
                        (nl-after (if (nl-after-com/delim? opts) "~%" "")))
                   (with-output-to-string (s)
                     (format* ("~A~A~A" nl-bef
                                        (loop for i from 0 to (1+ (/ len (length delim-el))) do
                                          (format s "~A" delim-el))
                                        nl-after)
                              len :truncate? t))))
               (%sym (sym)
                 (let ((name (symbol-name sym)))
                   (cond ((string-equal name (com/nl opts)) (%write-by-context "~%" nil))
                         ((string-equal name (com/cond-nl opts)) (%write-by-context "~_" nil))
                         ((and (> (length name) (com/delim-len opts))
                               (string-equal (subseq name 0 (com/delim-len opts)) (com/delim opts)))
                          (%write-by-context (%construct-delim (subseq name (com/delim-len opts)))))
                         (t (%write/add-arg "~A" sym)))))
               (%process-element (el)
                 (cond ((stringp el) (%write-by-context el))
                       ((symbolp el) (%sym el))
                       ((listp el)   (%write/add-arg "~A" el))
                       ((numberp el) (%write-by-context el))))
               (%get-prefix-format-call ()
                 (setf context :p)
                 (dolist (i prefix-list) (%process-element i))
                 `(format nil ,(get-output-stream-string prefix-format-str) ,@prefix-format-args))
               (%get-msg-format-call ()
                 (setf context :msg)
                 (dolist (i msg-list) (%process-element i))
                 `(format nil ,(get-output-stream-string msg-format-str) ,@msg-format-args)))
        `(print-message ,frmt ,opts
                        ',(prepare-clips (clip frmt))
                        ,(%get-prefix-format-call)
                        ,(%get-msg-format-call))))))

(defmethod print-message ((frmt fmt) (opts options) clips prefix-str msg-str)
  (destructuring-bind (up-clip oneline-clip mid-clip down-clip) clips
    (let ((prefix-str (prepare-prefix (prefix frmt) prefix-str))
          (counter-str (prog1 (prepare-counter (counter frmt)) (incf *dbp-counter*))))
      (labels ((%count-msg-lines ()
                 (loop for ch across msg-str count (char-equal ch #\newline)))
               (%clip-decide (ln-num nls)
                 (cond
                   ((= ln-num nls) down-clip)
                   (t mid-clip)))
               (%insert-prefixes ()
                 (let ((nls (%count-msg-lines)))
                   (if (= nls 0)
                       (format nil "~A~A~A~A" oneline-clip counter-str prefix-str msg-str)
                       (with-output-to-string (s)
                         (format s "~A~A~A" up-clip counter-str prefix-str)
                         (loop for ch across msg-str
                               with i = 0
                               do (format s "~c" ch)
                                  (when (char-equal ch #\newline)
                                    (incf i)
                                    (format s "~A~A~A" (%clip-decide i nls) counter-str prefix-str))))))))
        (format (out opts) (%insert-prefixes))))))

;; (dbp2 fmt>> ((:clip :size 3) (:prefix :size 16 :brace-left "[" :brace-right "]")) p>> 'op msg>> "heh mfa" :--> $nl $_nl $d- $_nl)
