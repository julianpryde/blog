#lang racket

; configuration
(define line-separator "LF")
  
; contents of the $BLOG_CONTENT environment variable
(define blog-content (getenv "BLOG_CONTENT"))
(define html-location (string-append blog-content "/html"))

; gemini prefixes
; each line's whitespaces are normalized to a single space, so any whitespaces will match
(define heading-1-prefix "# ")
(define heading-2-prefix "## ")
(define heading-3-prefix "### ")
(define list-item-prefix "* ")
(define block-quote-prefix "> ")
(define link-prefix "=> ")
(define preformatted-prefix "```")

; descends into file lines stream and builds the html equivalent of each line
(define (parse-lines post-name)
  (with-input-from-file (get-post-path post-name)
    (with-output-to-file html-location
      (let ((lines (create-line-stream)))
        ;; block-end-check is a placeholder to allow the list item and formatted text cases to check
        ;; if their paragraph has ended before any logic executes on the next line.
        (let loop ((is-list #f) (is-formatted #f) (block-end-check (lambda () ...)))
          ; descend into lines list
          (write-string
           (parse-single-line (car lines) is-list is-formatted)))))))

; call line editor based on line type
(define (parse-single-line line is-list is-formatted)
  (let ((normalized-line (string-normalize-spaces line)))
    (cond
    
      ; heading 1
      ((string-prefix? normalized-line heading-1-prefix)
       (add-html-bookends line heading-1-prefix "<h1>" "</h1>"))
       
      ; heading 2
      ((string-prefix? normalized-line heading-2-prefix)
       (add-html-bookends line heading-2-prefix "<h2>" "</h2>"))

      ; heading 3
      ((string-prefix? normalized-line heading-2-prefix)
       (add-html-bookends line heading-2-prefix "<h2>" "</h2>"))

      ; list item
      ((string-prefix? normalized-line list-item-prefix)
       (add-html-bookends (add-para-delims line test-list-bound is-list "<ul>" "</ul>")
                          list-item-prefix "<li>" "</li>")))))

; returns "beginning" if the current line is the beginning of a list, "end" if it immediately
; follows a list, and "middle" if it's the middle of a list.
; returns #f if the line is not in or immediately after a list
(define (test-list-bound line current-state)
  (cond

    ; beginning if the current line begins with the list item prefix and the current state is false
    (and
     (string-prefix? normalized-line-

; test if paragraph delimeters are required for lists and formatted text blocks
(define (add-para-delims line test-procedure state-flag opening closing)
  (cond

    ; apply test procedure and add paragraph delimiters as necessary to line.
    ; adds html bookends to line before returning
    ((string=? "beginning" (test-procedure state-flag line))
     (string-append ))))

; format headings in html
(define (add-html-bookends line prefix opening-tag closing-tag)
  (string-replace
   (string-append line closing-tag)
   prefix
   opening-tag))

; returns a true if string begins with a given prefix
;
; Gets a substring of STRING beginning with index 0 and ending with
; (string-length PREFIX).  Returns #T if the substring is equal to
; PREFIX and #F if not
(define (line-type? string prefix)
  (equal?
   prefix
   (substring string
              0
              (string-length prefix))))

; build path to the post file by appending the BLOG_CONTENT environment variable followed by the
; 'posts' subdirectory to the beginning and the '.gmi' extension to the end.
(define (get-post-path post-name)
  (build-path
   blog-content
   (build-path "posts"
               (string-append post-name ".gmi"))))

; return a stream of the lines in the file
(define (create-line-stream)
  (let loop ()
    ; read-line has a side-effects but we can pretend
    (let ((line (read-line)))
      (cond            
        ((eof-object? line) line)
        (else (cons line (loop)))))))

(define (linesep-mode line-separator)
  (cond
    ((equal? line-separator "LF") 'linefeed)
    ((equal? line-separator "CR") 'return)
    ((equal? line-separator "CRLF") 'return-linefeed)
    (else 'any)))