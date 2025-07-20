;; Decentralized Peer Review Protocol
;; Enhanced version with status tracking, access control, enhanced data storage, and economic incentives
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-ALREADY-REVIEWED (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-SELF-REVIEW (err u105))
(define-constant ERR-NOT-REGISTERED (err u106))

;; Review submission fee and reward amounts (in microSTX)
(define-constant SUBMISSION-FEE u1000000) ;; 1 STX
(define-constant REVIEW-REWARD u500000) ;; 0.5 STX per review

;; Paper status constants
(define-constant STATUS-SUBMITTED u1)
(define-constant STATUS-UNDER-REVIEW u2)
(define-constant STATUS-REVIEWED u3)
(define-constant STATUS-ACCEPTED u4)
(define-constant STATUS-REJECTED u5)

;; Minimum reviews required before paper can be accepted/rejected
(define-constant MIN-REVIEWS u3)

;; Data Variables
(define-data-var paper-counter uint u0)
(define-data-var total-fees-collected uint u0)

;; Data Maps
;; Registered reviewers with their expertise and reputation
(define-map reviewers
    principal
    {
        expertise: (string-utf8 100),
        reputation-score: uint,
        total-reviews: uint,
        is-active: bool,
    }
)

;; Enhanced paper storage with metadata and status
(define-map papers
    uint
    {
        author: principal,
        title: (string-utf8 100),
        abstract: (string-utf8 500),
        keywords: (string-utf8 200),
        uri: (string-utf8 256),
        status: uint,
        submission-time: uint,
        review-count: uint,
        total-rating: uint,
    }
)

;; Enhanced review storage with ratings and categories
(define-map reviews
    {
        paper-id: uint,
        reviewer: principal,
    }
    {
        technical-quality: uint,
        novelty: uint,
        clarity: uint,
        overall-rating: uint,
        feedback: (string-utf8 1000),
        submission-time: uint,
    }
)

;; Track which papers each reviewer has reviewed (prevent duplicate reviews)
(define-map reviewer-paper-history
    {
        reviewer: principal,
        paper-id: uint,
    }
    bool
)

;; Contract balance for rewards
(define-map contract-balances
    principal
    uint
)

;; Read-only functions

(define-read-only (get-paper (paper-id uint))
    (map-get? papers paper-id)
)

(define-read-only (get-review
        (paper-id uint)
        (reviewer principal)
    )
    (map-get? reviews {
        paper-id: paper-id,
        reviewer: reviewer,
    })
)

(define-read-only (get-reviewer-info (reviewer principal))
    (map-get? reviewers reviewer)
)

(define-read-only (get-paper-count)
    (var-get paper-counter)
)

(define-read-only (has-reviewed
        (reviewer principal)
        (paper-id uint)
    )
    (default-to false
        (map-get? reviewer-paper-history {
            reviewer: reviewer,
            paper-id: paper-id,
        })
    )
)

(define-read-only (get-contract-balance)
    (var-get total-fees-collected)
)

(define-read-only (is-reviewer-registered (reviewer principal))
    (match (map-get? reviewers reviewer)
        reviewer-data (get is-active reviewer-data)
        false
    )
)

;; Public functions

;; Register as a reviewer
(define-public (register-reviewer (expertise (string-utf8 100)))
    (begin
        (map-set reviewers tx-sender {
            expertise: expertise,
            reputation-score: u100, ;; Starting reputation
            total-reviews: u0,
            is-active: true,
        })
        (ok "Reviewer registered successfully")
    )
)

;; Deactivate reviewer (only contract owner or self)
(define-public (deactivate-reviewer (reviewer principal))
    (begin
        (asserts!
            (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender reviewer))
            ERR-UNAUTHORIZED
        )
        (match (map-get? reviewers reviewer)
            reviewer-data (begin
                (map-set reviewers reviewer
                    (merge reviewer-data { is-active: false })
                )
                (ok "Reviewer deactivated")
            )
            ERR-NOT-FOUND
        )
    )
)

;; Submit a paper with enhanced metadata (requires fee payment)
(define-public (submit-paper
        (title (string-utf8 100))
        (abstract (string-utf8 500))
        (keywords (string-utf8 200))
        (uri (string-utf8 256))
    )
    (let ((paper-id (var-get paper-counter)))
        (begin
            ;; Transfer submission fee to contract
            (try! (stx-transfer? SUBMISSION-FEE tx-sender (as-contract tx-sender)))

            ;; Update contract balance
            (var-set total-fees-collected
                (+ (var-get total-fees-collected) SUBMISSION-FEE)
            )

            ;; Store paper with enhanced metadata
            (map-set papers paper-id {
                author: tx-sender,
                title: title,
                abstract: abstract,
                keywords: keywords,
                uri: uri,
                status: STATUS-SUBMITTED,
                submission-time: stacks-block-height,
                review-count: u0,
                total-rating: u0,
            })

            ;; Increment paper counter
            (var-set paper-counter (+ paper-id u1))
            (ok paper-id)
        )
    )
)

;; Submit a comprehensive review (only registered reviewers, with rewards)
(define-public (submit-review
        (paper-id uint)
        (technical-quality uint)
        (novelty uint)
        (clarity uint)
        (overall-rating uint)
        (feedback (string-utf8 1000))
    )
    (let (
            (paper-data (unwrap! (map-get? papers paper-id) ERR-NOT-FOUND))
            (reviewer-data (unwrap! (map-get? reviewers tx-sender) ERR-NOT-REGISTERED))
        )
        (begin
            ;; Validate reviewer is registered and active
            (asserts! (get is-active reviewer-data) ERR-UNAUTHORIZED)

            ;; Prevent self-review
            (asserts! (not (is-eq tx-sender (get author paper-data)))
                ERR-SELF-REVIEW
            )

            ;; Prevent duplicate reviews
            (asserts! (not (has-reviewed tx-sender paper-id))
                ERR-ALREADY-REVIEWED
            )

            ;; Validate ratings are between 1-5
            (asserts! (and (>= technical-quality u1) (<= technical-quality u5))
                ERR-INVALID-STATUS
            )
            (asserts! (and (>= novelty u1) (<= novelty u5)) ERR-INVALID-STATUS)
            (asserts! (and (>= clarity u1) (<= clarity u5)) ERR-INVALID-STATUS)
            (asserts! (and (>= overall-rating u1) (<= overall-rating u5))
                ERR-INVALID-STATUS
            )

            ;; Store the review
            (map-set reviews {
                paper-id: paper-id,
                reviewer: tx-sender,
            } {
                technical-quality: technical-quality,
                novelty: novelty,
                clarity: clarity,
                overall-rating: overall-rating,
                feedback: feedback,
                submission-time: stacks-block-height,
            })

            ;; Mark that this reviewer has reviewed this paper
            (map-set reviewer-paper-history {
                reviewer: tx-sender,
                paper-id: paper-id,
            }
                true
            )

            ;; Update paper statistics
            (map-set papers paper-id
                (merge paper-data {
                    review-count: (+ (get review-count paper-data) u1),
                    total-rating: (+ (get total-rating paper-data) overall-rating),
                    status: STATUS-UNDER-REVIEW,
                })
            )

            ;; Update reviewer statistics and reputation
            (map-set reviewers tx-sender
                (merge reviewer-data {
                    total-reviews: (+ (get total-reviews reviewer-data) u1),
                    reputation-score: (+ (get reputation-score reviewer-data) u10), ;; Increase reputation
                })
            )

            ;; Pay reviewer reward
            (try! (as-contract (stx-transfer? REVIEW-REWARD tx-sender tx-sender)))
            (var-set total-fees-collected
                (- (var-get total-fees-collected) REVIEW-REWARD)
            )

            (ok "Review submitted successfully")
        )
    )
)

;; Update paper status (only contract owner after sufficient reviews)
(define-public (update-paper-status
        (paper-id uint)
        (new-status uint)
    )
    (let ((paper-data (unwrap! (map-get? papers paper-id) ERR-NOT-FOUND)))
        (begin
            ;; Only contract owner can update status
            (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

            ;; Ensure paper has minimum reviews before accepting/rejecting
            (if (or (is-eq new-status STATUS-ACCEPTED) (is-eq new-status STATUS-REJECTED))
                (asserts! (>= (get review-count paper-data) MIN-REVIEWS)
                    ERR-INVALID-STATUS
                )
                true
            )

            ;; Validate status
            (asserts! (and (>= new-status u1) (<= new-status u5))
                ERR-INVALID-STATUS
            )

            ;; Update paper status
            (map-set papers paper-id (merge paper-data { status: new-status }))
            (ok "Paper status updated")
        )
    )
)

;; Get papers by status (helper function for filtering)
(define-read-only (get-paper-status (paper-id uint))
    (match (map-get? papers paper-id)
        paper-data (some (get status paper-data))
        none
    )
)

;; Calculate average rating for a paper
(define-read-only (get-average-rating (paper-id uint))
    (match (map-get? papers paper-id)
        paper-data (if (> (get review-count paper-data) u0)
            (some (/ (get total-rating paper-data) (get review-count paper-data)))
            none
        )
        none
    )
)

;; Emergency functions (only contract owner)
(define-public (emergency-withdraw (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
        (ok "Emergency withdrawal completed")
    )
)

;; Contract initialization
(begin
    (var-set paper-counter u0)
    (var-set total-fees-collected u0)
)
