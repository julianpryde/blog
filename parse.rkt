#lang racket

;
; configuration
;
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

;
; main function
;

; descends into file lines stream and builds the html equivalent of each line
(define (parse-lines post-name)
  (with-input-from-file (get-post-path post-name)
    (with-output-to-file html-location
      (let ((lines (create-line-stream)))
        ; block-end-check contains a procedure to allow the list item and formatted text cases to
        ; check if their paragraph has ended before any logic executes on the next line.
        (let loop ((lines lines) (state "none")) ; no-block-end-check args are ignored.
          ; descend into lines list
          (parse-single-line (car lines) state (lambda (new_state) loop lines new_state)))))))

;
; main parser logic
;

; call line editor based on line type
; state can be "preformatted", "list", or "none".  The program should throw an error any other state.
(define (parse-single-line line state loop)
  ; ; may have to shim string-normalize-spaces if it doesn't work
  (let ((normalized-line (string-normalize-spaces line)))
    ; #f if this is not the end of a block. </ul> or ... if this is the end of a block
    ; TODO change the ... to the actual formatted text html closer
    (let ((block-end-check-return (block-end-check state normalized-line)))
      (cond
        ; heading 1
        ((string-prefix? normalized-line heading-1-prefix)
         (writeln (add-html-bookends line heading-1-prefix "<h1>" "</h1>"))
         (loop "none"))
        
        ; heading 2
        ((string-prefix? normalized-line heading-2-prefix)
         (writeln (add-html-bookends line heading-2-prefix "<h2>" "</h2>"))
         (loop "none"))
        
         ; heading 3
         ((string-prefix? normalized-line heading-3-prefix)
          (writeln (add-html-bookends line heading-3-prefix "<h3>" "</h3>"))
          (loop "none"))

          ; list item
          ((string-prefix? normalized-line list-item-prefix)
           (cond
             ; if beginning of a list: prepend list item with 
             ((string=? state "none")
              (writeln "<ul>")
              (writeln (add-html-bookends list-item-prefix "<li>" "</li>"))
              (loop "list"))
             ; if in a list
             ((string=? state "list")
              (writeln (add-html-bookends list-item-prefix "<li>" "</li>"))
              (loop "list"))
             ; else throw an error
             (else (raise-user-error (string append "invalid state: " state)))))

          ))))

;
; state checkers
;
(define (block-end-check state normalized-line)
  (cond
    ((string=? state "list") (check-if-list-end normalized-line))
    ((string=? state "preformatted") (check-if-preformatted-end normalized-line))
    ((string=? state "none") (no-block-end-check #f))
    (else (raise-user-error "invalid state"))))
    

; placeholder that returns #f if no check is required at the end of the line
(define no-block-end-check (lambda (_) #f))

; check if next line is another list element or if the list should be closed
; if true, returns the required html list end symbol
(define (check-if-list-end normalized-line)
  (if (string-prefix? normalized-line list-item-prefix)
      ""
      "</ul>"))

; check if the next line is the end of formatted text or if the parser should return to base state
; if true, returns the html formatted text end symbol
(define (check-if-preformatted-end normalized-line)
  (if (string-prefix? normalized-line preformatted-prefix)
      "</ul>" ; TODO change this to the actual html
      ""))

;
; string operations helpers
;

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

; may be deprecated
(define (linesep-mode line-separator)
  (cond
    ((equal? line-separator "LF") 'linefeed)
    ((equal? line-separator "CR") 'return)
    ((equal? line-separator "CRLF") 'return-linefeed)
    (else 'any)))

;
; file io
;

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