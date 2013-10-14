#!/usr/bin/env chicken-scheme

;; [[file:~/prg/scm/aima/aima.org::*Logical%20agents][Logical-agents:5]]

(use debug
     matchable
     srfi-1
     test)

(define (satisfy formula)
  (let* ((clauses (conjuncts formula))
         (all-variables (all-variables clauses)))
    (let iter ((clauses clauses)
               (assignment '()))
      (call-with-values (lambda () (propagate-unit-clauses clauses assignment))
        (lambda (clauses assignment)
          (cond ((exists-empty-clause? clauses) #f)
                ;; This is where we'd do some dynamic shit and maybe a
                ;; call-cc.
                ((null? clauses) assignment)
                (else
                 (let ((variable (select-variable all-variables assignment)))
                   (if variable
                       (or (iter (simplify clauses variable)
                                 (cons variable assignment))
                           (iter (simplify clauses (negate variable))
                                 (cons (negate variable) assignment)))
                       assignment)))))))))

(define (conjuncts formula)
  (match formula
    (('and . ps) ps)
    (p (list p))))

(define (disjuncts formula)
  (match formula
    (('or . ps) ps)
    (p (list p))))

(define (disjunction clause)
  (if (list? clause)
      (if (= (length clause) 1)
          (car clause)
          (cons 'or clause))
      clause))

(define (conjunction clause)
  (if (list? clause)
      (if (= (length clause) 1)
          (car clause)
          (cons 'and clause))
      clause))

(define (clauses formula)
  (match formula
    (('and . conjuncts) conjuncts)
    (('or . disjuncts) disjuncts)
    (p (list p))))

(define (select-variable all-variables assignment)
  (let ((candidates (lset-difference eq? all-variables (variables assignment))))
    (and (not (null? candidates))
         (list-ref candidates (random (length candidates))))))

(define (propagate-unit-clauses clauses assignment)
  (let iter ((clauses clauses)
             (assignment assignment))
    (if (exists-empty-clause? clauses)
        (values clauses assignment)
        (let ((unit-clauses (unit-clauses clauses)))
          (if (null? unit-clauses)
              (values clauses assignment)
              (let ((unit-clause (car unit-clauses)))
                (iter (simplify clauses unit-clause)
                      (cons unit-clause assignment))))))))

(define-syntax
  xor
  (lambda (expression rename compare)
    (match expression
      ((_ x y)
       (let ((%or (rename 'or)) (%and (rename 'and)) (%not (rename 'not)))
                       `(,%and (,%or ,x ,y) (,%not (,%and ,x ,y))))))))

(define (simplify clauses literal)
  (let ((literal-variable (variable literal))
        (negative? (negative-clause? literal)))
    (let ((simplification
           (fold-right (lambda (clause simplifications)
                         ;; It's not going to be a disjunct, because
                         ;; we've put it in a minimalist form.
                         (let iter ((clause ;; (disjuncts clause)
                                     (match clause
                                       ((? symbol?) (list clause))
                                       ((? negative-clause?) (list clause))
                                       (('or . ps) ps)
                                       (p p))
                                     ;; (cond ((symbol? clause) (list clause))
                                     ;;       ((negative-clause? clause) (list clause))
                                     ;;       (else clause))
                                     )
                                    (simplification '()))
                           (if (null? clause)
                               (cons (if (= (length simplification) 1)
                                         (car simplification)
                                         simplification) simplifications)
                               (let* ((term (car clause))
                                      (negative-term? (negative-clause? term)))
                                 (if (eq? literal-variable (variable term))
                                     ;; It's not sufficient to return
                                     ;; simplifications: need to check
                                     ;; for opposite, too. No, wait a
                                     ;; minute: (or #t #f) is
                                     ;; true.
                                     (if (or (and negative? negative-term?)
                                             (and (not negative?) (not negative-term?)))
                                         simplifications
                                         (iter (cdr clause)
                                               simplification))
                                     (iter (cdr clause)
                                           (cons term simplification)))))))
                       '()
                       clauses)))
      (delete-duplicates simplification))))

;;; This also needs to handle e.g. negatives.
;; (define (remove-variable clauses variable)
;;   (map (lambda (clause)
;;          (filter (lambda (terms) )
;;                  (disjuncts clause)))
;;        clauses))

(define (filter-clauses clauses variable)
  (filter (lambda (clause) (not (memq variable clause))) clauses))

(define (unit-clauses clauses)
  (filter (lambda (clause)
            (or (not (list? clause))
                (= (length clause) 1)
                (negative-clause? clause)))
          clauses))

(define (unit-literals clauses)
  (map variable (unit-clauses clauses)))

(define (negative-clause? literal)
  (match literal
    (('not p) #t)
    (_ #f)))

(define (exists-empty-clause? clauses)
  (if (null? clauses)
      #f
      (if (null? (car clauses))
          #t
          (exists-empty-clause? (cdr clauses)))))

(define (simplify* clauses literals)
  (fold-right (lambda (literal clauses)
                (simplify clauses literal))
              clauses
              literals))

(define (negate literal)
  `(not ,literal))

(define (variable literal)
  (match literal
    (('not p) p)
    (p p)))

(define args cdr)

(define (variables clause)
  (if (atomic-clause? clause)
      (if (and (list? clause)
               (not (negative-clause? clause)))
          (map variable clause)
          (list (variable clause)))
      (map variable (args clause))))

(define (all-variables clauses)
  (delete-duplicates
   (fold-right
    (lambda (clause all-variables)
      (append (variables clause) all-variables))
    '()
    clauses)))

(define (atomic-clause? clause)
  (match clause
    (('and . p) #f)
    (('or . p) #f)
    ;; (('not . p) #f)
    (('=> . p) #f)
    (('<=> . p) #f)
    (_ #t)))

(define (literal-clause? clause)
  (or (atomic-clause? clause)
      (and (negative-clause? clause)
           (atomic-clause? (car (clauses clause))))))

(define (eliminate-implications formula)
  (match formula
    ((? literal-clause?) formula)
    (('=> p q) `(or (not ,p) ,q))
    (('<=> p q)
     `(and (or ,p (not ,q))
           (or (not ,q) ,p)))
    ((op . ps) `(,op ,@(map eliminate-implications ps)))))

(define (move-not-inwards formula)
  (match formula
    (('not p) p)
    (('and . ps)
     `(or ,@(map move-not-inwards ps)))
    (('or . ps)
     `(and ,@(map move-not-inwards ps)))
    (p `(not ,p))))

(define (merge-disjuncts clauses)
  (case (length clauses)
    ((0) #f)
    ((1) (car clauses))
    (else
     `(and ,@(let ((result (make-parameter '())))
               (for-each
                   (lambda (p)
                     (for-each
                         (lambda (q)
                           (result (cons `(or ,@(append (disjuncts p)
                                                        (disjuncts q)))
                                         (result))))
                       (conjuncts (first clauses))))
                 (conjuncts (merge-disjuncts (cdr clauses))))
               (result))))))

(define (->cnf formula)
  (let ((formula (eliminate-implications formula)))
    (match formula
      (('not p) (let ((q (move-not-inwards p)))
                  (if (literal-clause? q) q (->cnf q))))
      (('and . ps)
       `(and ,@(append-map (lambda (p) (conjuncts (->cnf p))) ps)))
      (('or . ps)
       (merge-disjuncts (map ->cnf ps)))
      (p p))))

(define (tell knowledge-base p)
  (append knowledge-base (clauses (->cnf p))))

(define (tell* knowledge-base . ps)
  (fold-right (lambda (p knowledge-base)
                (tell knowledge-base (->cnf p)))
              knowledge-base
              ps))

(test (->cnf '(and (or B (and C (or M N) F) D) (or W(and P (or Q (and X Y) X A)))))
      '(and (or D C B) (or D N M B) (or D F B) (or A X Y Q W) (or A X X Q W) (or P W)))

(test '(() t) (simplify '((not s) t) 's))
(test '(t) (simplify '((not s) t) '(not s)))
(test '(t) (simplify '(s t) 's))
(test '(() t) (simplify '(s t) '(not s)))
(test '(()) (simplify '((not s) s) 's))
(test '(()) (propagate-unit-clauses '((not s) s) '()))
(call-with-values (lambda () (propagate-unit-clauses '((not s) s) '()))
  (lambda (clauses assignment)
    (test clauses '(()))
    (test assignment '((not s)))))
(test-assert (not (satisfy '(and s (not s)))))
(test '((not t) s) (satisfy '(and s (not t))))

;;; "a entails b iff (and a (not b)) is unsatisfiable."
(define (ask knowledge-base query)
  (not (satisfy (tell knowledge-base `(not ,query)))))

(define (make-knowledge-base) '(and))

(let ((knowledge-base (tell* (make-knowledge-base)
                             '(not b11)
                             '(=> (not b11) (and (not p12) (not p21)))
                             'b21
                             '(=> b21 (or p11 p22 p31)))))
  (test-assert (not (ask knowledge-base 'b11))))

(let ((kb (tell* (make-knowledge-base)
                 'a)))
  (test-assert (not (ask kb '(not a))))
  (test-assert (satisfy kb)))

(let ((kb (tell* (make-knowledge-base)
                 'b11
                 '(=> b11 (or p01 p10 p12 p21))
                 '(not b00)
                 '(=> (not b00) (and (not p10) (not p01))))))
  (test-assert (not (ask kb 'p01)))
  (test-assert (ask kb '(not p01)))
  (test-assert (satisfy kb))
  (test-assert (not (ask kb '(not p12))))
  (test-assert (not (ask kb 'p12))))

;; Logical-agents:5 ends here