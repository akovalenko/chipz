(in-package :lizard)

(defun gzip-test/whole-file (compressed-pathname original-pathname)
  (with-open-file (compressed-stream compressed-pathname :direction :input
                                     :element-type '(unsigned-byte 8))
    (with-open-file (stream original-pathname :direction :input
                            :element-type '(unsigned-byte 8))
      (let ((compressed-input (make-array (file-length compressed-stream)
                                          :element-type '(unsigned-byte 8)))
            (output (make-array (file-length stream)
                                :element-type '(unsigned-byte 8)))
            (original (make-array (file-length stream)
                                  :element-type '(unsigned-byte 8)))
            (zstream (make-inflate-state :gzip)))
        (let ((compressed-bytes (read-sequence compressed-input compressed-stream)))
          (read-sequence original stream)
          (multiple-value-bind (bytes-read bytes-output)
              (read-uncompressed-data zstream compressed-input output
                                      :input-end compressed-bytes)
            (and (= bytes-read compressed-bytes)
                 (= bytes-output (length original))
                 (not (mismatch output original :end1 bytes-output
                                :end2 bytes-output)))))))))

(defun gzip-test/whole-file-cons (compressed-pathname original-pathname)
  (with-open-file (compressed-stream compressed-pathname :direction :input
                                     :element-type '(unsigned-byte 8))
    (with-open-file (stream original-pathname :direction :input
                            :element-type '(unsigned-byte 8))
      (let ((compressed-input (make-array (file-length compressed-stream)
                                          :element-type '(unsigned-byte 8)))
            (original (make-array (file-length stream)
                                  :element-type '(unsigned-byte 8))))
        (let ((compressed-bytes (read-sequence compressed-input compressed-stream))
              (output (decompress :gzip compressed-input :input-end compressed-bytes)))
          (read-sequence original stream)
          (and (= (length original) (length output))
               (not (mismatch output original))))))))

(defun gzip-test/incremental-file (compressed-pathname original-pathname)
  (with-open-file (compressed-stream compressed-pathname :direction :input
                                     :element-type '(unsigned-byte 8))
    (with-open-file (stream original-pathname :direction :input
                            :element-type '(unsigned-byte 8))
      (let ((compressed-input (make-array (file-length compressed-stream)
                                          :element-type '(unsigned-byte 8)))
            (output (make-array (file-length stream)
                                :element-type '(unsigned-byte 8)))
            (original (make-array (file-length stream)
                                  :element-type '(unsigned-byte 8)))
            (zstream (make-inflate-state :gzip)))
        (read-sequence original stream)
        (let ((compressed-bytes (read-sequence compressed-input compressed-stream))
              (input-index 0)
              (output-index 0))
          (loop
             (multiple-value-bind (bytes-read bytes-output)
                 (read-uncompressed-data zstream compressed-input output
                                         :input-start input-index
                                         :input-end compressed-bytes
                                         :output-start output-index
                                         :output-end (1+ output-index))
               (when (zerop bytes-output) (return))
               (let ((ouch (mismatch original output
                                     :start1 output-index :start2 output-index
                                     :end1 (1+ output-index) :end2 (1+ output-index))))
                 (when ouch
                   (return nil)))
               (incf input-index bytes-read)
               (incf output-index)))
          (and (= input-index compressed-bytes))
               (= output-index (length original))
               (not (mismatch output original :end1 output-index
                              :end2 output-index)))))))

#+sbcl
(defun gzip-test/gray-stream (compressed-pathname original-pathname)
  (with-open-file (compressed-stream compressed-pathname :direction :input
                                     :element-type '(unsigned-byte 8))
    (with-open-file (stream original-pathname :direction :input
                            :element-type '(unsigned-byte 8))
      (let ((zstream (make-decompressing-stream :gzip compressed-stream))
            (output (make-array (file-length stream)
                                :element-type '(unsigned-byte 8)))
            (original (make-array (file-length stream)
                                  :element-type '(unsigned-byte 8))))
        (read-sequence output zstream)
        (read-sequence original stream)
        (not (mismatch output original))))))

(defun run-all-tests (source-directory)
  (dolist (testfun (list #'gzip-test/whole-file
                         #'gzip-test/whole-file-cons
                         #+sbcl #'gzip-test/gray-stream
                         #'gzip-test/incremental-file) t)
    (let ((directory (merge-pathnames (make-pathname :name :wild :type "lisp"
                                                     :directory '(:relative "test-files"))
                                      source-directory)))
      (dolist (file (directory directory))
        (loop with namestring = (namestring file)
           for level from 1 to 9 do
             (let ((gzipped-pathname (make-pathname :name (format nil "~A.~D.gz"
                                                                  namestring level)
                                                    :type nil)))
               (when (probe-file gzipped-pathname)
                 (unless (funcall testfun gzipped-pathname file)
                   (return-from run-all-tests nil)))))))))
