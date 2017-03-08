;; Common Lisp Script
;; Manoel Vilela

(ql:quickload :usocket)

(defpackage :lisp-chat
  (:use :usocket :cl))

(in-package :lisp-chat)

(load "./config.lisp") ;; *hosts* *port* *debug*

(defparameter *global-socket* (socket-listen *host* *port*))

(defparameter *clients* nil)
(defparameter *client-read-threads* nil)
(defparameter *messages-stack* nil)
(defparameter *messages-log* nil)

(defvar *message-semaphore* (sb-thread:make-semaphore :name "message semaphore" :count 0))
(defvar *message-mutex* (sb-thread:make-mutex :name "message mutex"))
(defvar *client-mutex* (sb-thread:make-mutex :name "client list mutex"))
(defvar *client-read-mutex* (sb-thread:make-mutex :name "client read mutex"))


(defstruct client name socket)

(defstruct message from content timestamp)


(defun debug-format (&rest args)
  (if *debug*
      (apply #'format args)))


(defun client-stream (c)
  (socket-stream (client-socket c)))

(defun formated-message (message)
  (format nil "[~a]: ~a"
          (message-from message)
          (message-content message)))

(defun push-message (from message)
  (sb-thread:with-mutex (*message-mutex*)
    (push (make-message :from from
                        :content message
                        :timestamp "NOT IMPLEMENTED" )
          *messages-stack*)
    (sb-thread:signal-semaphore *message-semaphore*)))

(defun client-reader (client)
  (loop for message = (read-line (client-stream client))
        while (not (equal message "/quit"))
        when (> (length message) 0)
          do (push-message (client-name client)
                           message)))

(defun send-message (client message)
  (let ((stream (client-stream client)))
    (write-line message stream)
    (finish-output stream)))

(defun create-client (connection)
  (debug-format t "Incoming connection ~a ~%" connection)
  (let ((client-stream (socket-stream connection)))
    (write-line "> Type your username: " client-stream)
    (finish-output client-stream)
    (let ((client (make-client :name (read-line client-stream)
                              :socket connection)))
      (sb-thread:with-mutex (*client-mutex*)
        (debug-format t "Added new user ~s ~%" (client-name client))
        (push client *clients*))
      (push-message "@server" (format nil "The user ~s joined to the party!" (client-name client)))
      (sb-thread:with-mutex (*client-read-mutex*)
        (push (sb-thread:make-thread #'client-reader
                                     :arguments (list client))
              *client-read-threads*)))))


(defun message-broadcast ()
  (loop when (sb-thread:wait-on-semaphore *message-semaphore*)
          do (sb-thread:with-mutex (*message-mutex*)
               (let ((message (formated-message (pop *messages-stack*))))
                 (push message *messages-log*)
                 (loop for client in *clients*
                       do (send-message client message))))))

(defun connection-handler ()
  (loop for connection = (socket-accept *global-socket*)
        do (sb-thread:make-thread #'create-client :arguments (list connection))))

(defun server-loop ()
  (format t "Running server... ~%")
  (let* ((connection-thread (sb-thread:make-thread #'connection-handler))
         (broadcast-thread (sb-thread:make-thread #'message-broadcast)))
    (sb-thread:join-thread connection-thread)
    (sb-thread:join-thread broadcast-thread)
    (socket-close *global-socket*)))

(server-loop)