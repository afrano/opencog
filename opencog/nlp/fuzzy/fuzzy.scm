
(define-module (opencog nlp fuzzy))

(load-extension "libnlpfz" "opencog_nlp_fuzzy_init")

(use-modules (srfi srfi-1)
             (opencog)
             (opencog query)  ; for cog-fuzzy-match
             (opencog nlp)
             (opencog nlp sureal)
             (opencog nlp microplanning))

; ----------------------------------------------------------
(define-public (get-answers sent-node)
"
  Find answers (i.e., similar sentences that share some keyword) from
  the Atomspace by using the fuzzy pattern matcher. By default, it
  excludes sentences with TruthQuerySpeechAct and InterrogativeSpeechAct.

  Accepts a SentenceNode as the input.
  Returns one or more sentence strings -- the answers.

  For example:
     (get-answers (car (nlp-parse \"What did Pete eat?\")))
  OR:
     (get-answers (SentenceNode \"sentence@123\"))

  Possible result:
     (Pete ate apples .)
"
    (sent-matching sent-node
        (list (DefinedLinguisticConceptNode "TruthQuerySpeechAct")
              (DefinedLinguisticConceptNode "InterrogativeSpeechAct")))
)

; ----------------------------------------------------------
(define-public (sent-matching sent-node exclude-list)
"
  The main function for finding similar sentences
  Returns one or more sentences that are similar to the input one but
  contain no atoms that are listed in the exclude-list.
"
    ; Generate sentences for each of the SetLinks found by the fuzzy matcher
    ; TODO: May need to filter out some of the contents of the SetLinks
    ; before sending each of them to Microplanner
    (define (gen-sentences setlinks)

        ; Find the speech act from the SetLink and use it for Microplanning
        (define (get-speech-act setlink)
            (let* ((speech-act-node-name
                        (filter (lambda (name)
                            (if (string-suffix? "SpeechAct" name) #t #f))
                                (map cog-name (cog-filter 'DefinedLinguisticConceptNode (cog-get-all-nodes setlink))))))

                ; If no speech act was found, return "declarative" as default
                (if (> (length speech-act-node-name) 0)
                    (string-downcase (substring (car speech-act-node-name) 0 (string-contains (car speech-act-node-name) "SpeechAct")))
                    "declarative"
                )
            )
        )        

        (append-map (lambda (r)
            ; Send each of the SetLinks found by the fuzzy matcher to
            ; Microplanner to see if they are good
            (let* ( (spe-act (get-speech-act r))
                    (seq-and (AndLink (cog-outgoing-set r)))
                    (m-results (microplanning seq-and spe-act
                         *default_chunks_option* #f)))
(trace-msg "duuude sp-act is ")
(trace-msg spe-act)
(trace-msg "duuude m-res is ")
(trace-msg m-results)
                ; Don't send it to SuReal in case it's not good
                ; (i.e. Microplanner returns #f)
                (if m-results
                    (append-map
                        ; Send each of the SetLinks returned by
                        ; Microplanning to SuReal for sentence generation
                        (lambda (m) (sureal (car m)))
                        m-results
                    )
                    '()
                )
            ))
            setlinks
        )
    )

    ; Post processing for the results found by the fuzzy pattern matcher
    ; We can do whatever that are needed such as filtering/merging etc
    ; Currently it returns the top ones that are having the same similarity score
    (define (post-process fset)
        (let ( (max-score 0)
               (results '()))
            (for-each (lambda (s)
                (let ( (score (string->number (cog-name (cadr (cog-outgoing-set s))))))
                    (if (>= score max-score)
                        (begin
                            (set! results (append results (list (car (cog-outgoing-set s)))))
                            (set! max-score score))
                        #f)))
            (cog-outgoing-set fset))
            results))

    (let* ( ; parse is the ParseNode for the sentence
            (parse (car (cog-chase-link 'ParseLink 'ParseNode sent-node)))

            ; intrp is the InterpretationNode for the sentence
            (intrp (car (cog-chase-link 'InterpretationLink 'InterpretationNode parse)))

            ; setlk is the R2L SetLink of the input sentence
            (setlk (car (cog-chase-link 'ReferenceLink 'SetLink intrp)))

            ; fzset is the set of similar sets.
            (fzset (nlp-fuzzy-match setlk 'SetLink exclude-list))

            ; ftrset is a set of atoms that will be used for sentence generation
            (ftrset (post-process fzset))

            ; reply is the generated reply sentences.
            ; generated by  Microplanner and SuReal
            (reply (gen-sentences ftrset)))

(trace-msg "duuude gens  is ")
(trace-msg reply)

        ; Delete identical sentences from the return set
        (delete-duplicates reply)
    )
)
