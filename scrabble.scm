#!/usr/bin/env chicken-scheme

;; [[file:~/prg/scm/aima/aima.org::*5.4][5\.4:1]]

(use debug
     define-record-and-printer
     extras
     srfi-1
     vector-lib)

(define-record-and-printer sentinel)
(define sentinel (make-sentinel))

(define (character->index character)
  (if (sentinel? character)
      26
      (- (char->integer character) 65)))

(define (index->character index)
  (if (= index 26)
      sentinel
      (integer->char (+ index 65))))

;;; Can get this down to bits?
(define (make-dag) (make-vector 28 #f))
(define (dag-terminal? dag) (vector-ref dag 27))
(define (dag-terminal?-set! dag terminal?)
  (vector-set! dag 27 terminal?))
(define (dag-ref dag character)
  (vector-ref dag (character->index character)))
(define (dag-set! dag character value)
  (vector-set! dag (character->index character) value))

(define (integrate-fixes dag prefix suffix)
  (let ((characters (if (null? suffix)
                      prefix
                      (append (append prefix (list sentinel))
                              suffix))))
    (dag-terminal?-set!
     (fold (lambda (character dag)
             (unless (dag-ref dag character)
               (dag-set! dag character (make-dag)))
             (dag-ref dag character))
           dag
           characters)
     #t)))

(define (update-dag! dag word)
  (let ((characters (string->list word)))
    (do ((prefix (list (car characters)) (cons (car suffix) prefix))
         (suffix (cdr characters) (cdr suffix)))
        ((null? suffix) (integrate-fixes dag prefix suffix))
      (integrate-fixes dag prefix suffix))))

(define (dag-debug dag depth)
  (vector-for-each
   (lambda (i x)
     (when (vector? x)
       ;; (debug (index->character i))
       (format #t "~a~a~%" (make-string depth #\_) (index->character i))
       (dag-debug x (add1 depth))))
   dag))

;;; Be nice to store these fuckers in a graph database or something.
(define (make-dag-from-file file)
  (let ((dag (make-dag)))
    (with-input-from-file file
      (lambda ()
        (do ((word (read-line) (read-line)))
            ((eof-object? word))
          (debug word)
          (update-dag! dag word))))
    dag))

(define make-square cons)
(define square-x car)
(define square-y cdr)

(define (above square)
  (cons (square-x square)
        (+ (square-y square) 1)))

(define (below square)
  (cons (square-x square)
        (- (square-y square) 1)))

(define (left-of square)
  (cons (- (square-x square) 1)
        (square-y square)))

(define (right-of square)
  (cons (+ (square-x square) 1)
        (square-y square)))

(define (above? s1 s2)
  (below? s2 s1))

(define (below? s1 s2)
  (= 1 (- (square-y s2) (square-y s1))))

(define (left-of? s1 s2)
  (right-of? s2 s1))

(define (right-of? s1 s2)
  (= 1 (- (square-x s1) (square-x s2))))

(define (insert-sentinel word)
  (cons* (car word)
         sentinel
         (cdr word)))

(define (match? dag word)
  (let iter ((dag dag)
             ;; We have to insert a sentinel when matching because of
             ;; that idiosyncrasy of GADDAGs where a sentinel always
             ;; comes second (except when the suffix is ∅).
             (word (insert-sentinel word)))
    (if (null? word)
        (dag-terminal? dag)
        (let* ((character (car word))
               (subdag (dag-ref dag character)))
          (if subdag
              (iter subdag (cdr word))
              #f)))))

(define make-game make-hash-table)
(define game-copy hash-table-copy)
(define game-set! hash-table-set!)
(define game-ref hash-table-ref)
(define game-ref/default hash-table-ref/default)

(define (word-vertical game square)
  (do ((square square (below square)))
      ((not (game-ref/default game square #f))
       (do ((square (above square) (above square))
            (word '() (cons (game-ref/default game square #f) word)))
           ((not (game-ref/default game square #f)) word)))))

(define (word-horizontal game square)
  (do ((square square (right-of square)))
      ((not (game-ref/default game square #f))
       (do ((square (left-of square) (left-of square))
            (word '() (cons (game-ref/default game square #f) word)))
           ((not (game-ref/default game square #f)) word)))))

(define (square-neighbors square)
  (list (left-of square)
        (right-of square)
        (above square)
        (below square)))

(define (square-occupied? game square)
  (game-ref/default game square #f))

(define (anchor? game square)
  (not (every (cut square-occupied? game <>)
              (square-neighbors square))))

(define (unoccupied-neighbors game square)
  (filter (cut (complement square-occupied?) game <>)
          (square-neighbors square)))

(let ((game (make-game))
      (dag (make-dag))
      ;; The rack
      (tiles '(#\E #\C #\R #\A)))
  (update-dag! dag "ABLE")
  (update-dag! dag "AR")
  (update-dag! dag "ABLER")
  (update-dag! dag "BE")
  (update-dag! dag "CABLE")
  (update-dag! dag "CARE")
  (game-set! game (make-square 0 0) #\A)
  (game-set! game (make-square 0 -1) #\B)
  (game-set! game (make-square 0 -2) #\L)
  (game-set! game (make-square 0 -3) #\E)
  ;; Copy game; place; try; erase.
  ;; (dag-debug dag 0)
  (hash-table-walk game
    (lambda (square character)
      (let ((unoccupied-neighbors (unoccupied-neighbors game square)))
        (for-each
            (lambda (neighbor)
              (debug square character neighbor)
              ;; Copying the game is probably expensive; can't we
              ;; erase? Optimization. We're going to have to copy the
              ;; game for every trial, though, aren't we? Ouch.
              ;;
              ;; Cheap optimization: copy only after we've placed the
              ;; first tile. Lots of false starts?
              ;;
              ;; Need to keep track of successful crosscheck for
              ;; scoring purposes.
              (let ((game (game-copy game)))
                ;; Place; cross-check if vertical word is longer than
                ;; one letter: continue. Terminal? Score it in the
                ;; max-heap.
                (let iter ((tiles tiles)
                           (dag dag))
                  (unless (null? tiles)
                    (let ((character (car tiles)))
                      (game-set! game neighbor character)
                      (let ((vertical (word-vertical game neighbor)))
                        (when (or (= (length vertical) 1)
                                  (match? dag vertical))
                          ;; We should be able to score each vertical
                          ;; (and, eventually, the anchor).
                          ;;
                          ;; Need to answer more generally the
                          ;; question of whether we have sideways
                          ;; constraints.
                          (debug vertical))))
                    (iter (cdr tiles))))))
          unoccupied-neighbors))
      ;; (let ((word (word-vertical game square)))
      ;;   (debug word (match? dag word) (anchor? game square)))
      )))

;; (dag-debug (make-dag-from-file "words.txt") 0)


;; 5\.4:1 ends here