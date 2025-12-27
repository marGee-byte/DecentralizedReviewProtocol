;; Decentralized Peer Review Protocol
;; Enhanced version with governance, DAO features, dynamic economics, and multi-token support
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
(define-constant ERR-VOTING-CLOSED (err u107))
(define-constant ERR-ALREADY-VOTED (err u108))
(define-constant ERR-INSUFFICIENT-TOKENS (err u109))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u110))
(define-constant ERR-INVALID-TOKEN (err u111))
(define-constant ERR-INSUFFICIENT-STAKE (err u112))

;; Governance Token
(define-fungible-token governance-token)

;; Default economic parameters (can be changed via governance)
(define-data-var base-submission-fee uint u1000000) ;; 1 STX
(define-data-var base-review-reward uint u500000) ;; 0.5 STX per review
(define-data-var quality-multiplier uint u150) ;; 1.5x for high quality reviews (150%)
(define-data-var demand-multiplier uint u100) ;; 1.0x base demand multiplier (100%)

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

;; Submit a paper with dynamic pricing (requires fee payment)
(define-public (submit-paper
        (title (string-utf8 100))
        (abstract (string-utf8 500))
        (keywords (string-utf8 200))
        (uri (string-utf8 256))
    )
    (let (
            (paper-id (var-get paper-counter))
            (dynamic-fee (calculate-submission-fee))
        )
        (begin
            ;; Transfer dynamic submission fee to contract
            (try! (stx-transfer? dynamic-fee tx-sender (as-contract tx-sender)))

            ;; Update contract balance
            (var-set total-fees-collected
                (+ (var-get total-fees-collected) dynamic-fee)
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

            ;; Award governance tokens to author for participation
            (try! (ft-mint? governance-token u100 tx-sender))

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

            ;; Calculate dynamic reward based on quality
            (let ((dynamic-reward (calculate-review-reward overall-rating)))
                (begin
                    ;; Pay reviewer reward
                    (try! (as-contract (stx-transfer? dynamic-reward tx-sender tx-sender)))
                    (var-set total-fees-collected
                        (- (var-get total-fees-collected) dynamic-reward)
                    )

                    ;; Award governance tokens for participation
                    (try! (ft-mint? governance-token u50 tx-sender))

                    (ok "Review submitted successfully")
                )
            )
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
;; GOVERNANCE & DAO FEATURES (#2)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 

;; Governance constants
(define-constant PROPOSAL-DURATION u1440) ;; ~10 days in blocks
(define-constant MIN-PROPOSAL-TOKENS u1000) ;; Minimum tokens to create proposal
(define-constant QUORUM-THRESHOLD u5000) ;; Minimum votes for valid proposal

;; Proposal types
(define-constant PROPOSAL-TYPE-PARAMETER u1)
(define-constant PROPOSAL-TYPE-STATUS u2)
(define-constant PROPOSAL-TYPE-REVIEWER u3)

;; Data variables for governance
(define-data-var proposal-counter uint u0)
(define-data-var voting-period uint PROPOSAL-DURATION)

;; Governance proposals
(define-map proposals
    uint
    {
        proposer: principal,
        proposal-type: uint,
        title: (string-utf8 100),
        description: (string-utf8 500),
        target: (optional principal),
        parameter-name: (optional (string-ascii 50)),
        new-value: (optional uint),
        paper-id: (optional uint),
        new-status: (optional uint),
        start-block: uint,
        end-block: uint,
        yes-votes: uint,
        no-votes: uint,
        total-votes: uint,
        executed: bool,
    }
)

;; Track votes by user for each proposal
(define-map proposal-votes
    {
        proposal-id: uint,
        voter: principal,
    }
    {
        vote: bool,
        tokens-used: uint,
    }
)

;; Reviewer staking for quality assurance
(define-map reviewer-stakes
    principal
    {
        staked-amount: uint,
        stake-time: uint,
    }
)

;; Multi-token support for payments
(define-map supported-tokens
    principal ;; token contract
    {
        is-active: bool,
        min-fee: uint,
        reward-rate: uint, ;; percentage of base reward (100 = 100%)
        decimals: uint,
    }
)

;; Paper bounties (additional rewards offered by authors)
(define-map paper-bounties
    uint ;; paper-id
    {
        bounty-amount: uint,
        token-contract: (optional principal),
        claimed: bool,
    }
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
;; ENHANCED ECONOMIC MODELS (#4)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 

;; Calculate dynamic submission fee based on demand
(define-read-only (calculate-submission-fee)
    (let (
            (base-fee (var-get base-submission-fee))
            (demand-factor (var-get demand-multiplier))
        )
        (/ (* base-fee demand-factor) u100)
    )
)

;; Calculate dynamic review reward based on quality
(define-read-only (calculate-review-reward (quality-rating uint))
    (let (
            (base-reward (var-get base-review-reward))
            (quality-factor (if (>= quality-rating u4)
                (var-get quality-multiplier)
                u100
            ))
        )
        (/ (* base-reward quality-factor) u100)
    )
)

;; Get current economic parameters
(define-read-only (get-economic-parameters)
    {
        base-submission-fee: (var-get base-submission-fee),
        base-review-reward: (var-get base-review-reward),
        quality-multiplier: (var-get quality-multiplier),
        demand-multiplier: (var-get demand-multiplier),
        current-submission-fee: (calculate-submission-fee),
    }
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
;; GOVERNANCE FUNCTIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 

;; Create a governance proposal
(define-public (create-proposal
        (proposal-type uint)
        (title (string-utf8 100))
        (description (string-utf8 500))
        (target (optional principal))
        (parameter-name (optional (string-ascii 50)))
        (new-value (optional uint))
        (paper-id (optional uint))
        (new-status (optional uint))
    )
    (let ((proposal-id (var-get proposal-counter)))
        (begin
            ;; Check minimum token requirement
            (asserts!
                (>= (ft-get-balance governance-token tx-sender)
                    MIN-PROPOSAL-TOKENS
                )
                ERR-INSUFFICIENT-TOKENS
            )

            ;; Validate proposal type
            (asserts! (and (>= proposal-type u1) (<= proposal-type u3))
                ERR-INVALID-STATUS
            )

            ;; Create proposal
            (map-set proposals proposal-id {
                proposer: tx-sender,
                proposal-type: proposal-type,
                title: title,
                description: description,
                target: target,
                parameter-name: parameter-name,
                new-value: new-value,
                paper-id: paper-id,
                new-status: new-status,
                start-block: stacks-block-height,
                end-block: (+ stacks-block-height (var-get voting-period)),
                yes-votes: u0,
                no-votes: u0,
                total-votes: u0,
                executed: false,
            })

            ;; Increment proposal counter
            (var-set proposal-counter (+ proposal-id u1))
            (ok proposal-id)
        )
    )
)

;; Vote on a proposal
(define-public (vote-on-proposal
        (proposal-id uint)
        (vote bool)
        (tokens-to-use uint)
    )
    (let (
            (proposal-data (unwrap! (map-get? proposals proposal-id) ERR-NOT-FOUND))
            (voter-balance (ft-get-balance governance-token tx-sender))
        )
        (begin
            ;; Check if proposal is active
            (asserts! (<= stacks-block-height (get end-block proposal-data))
                ERR-VOTING-CLOSED
            )

            ;; Check if user has enough tokens
            (asserts! (>= voter-balance tokens-to-use) ERR-INSUFFICIENT-TOKENS)

            ;; Check if user hasn't voted already
            (asserts!
                (is-none (map-get? proposal-votes {
                    proposal-id: proposal-id,
                    voter: tx-sender,
                }))
                ERR-ALREADY-VOTED
            )

            ;; Record vote
            (map-set proposal-votes {
                proposal-id: proposal-id,
                voter: tx-sender,
            } {
                vote: vote,
                tokens-used: tokens-to-use,
            })

            ;; Update proposal vote counts
            (map-set proposals proposal-id
                (merge proposal-data {
                    yes-votes: (if vote
                        (+ (get yes-votes proposal-data) tokens-to-use)
                        (get yes-votes proposal-data)
                    ),
                    no-votes: (if vote
                        (get no-votes proposal-data)
                        (+ (get no-votes proposal-data) tokens-to-use)
                    ),
                    total-votes: (+ (get total-votes proposal-data) tokens-to-use),
                })
            )

            (ok "Vote recorded successfully")
        )
    )
)

;; Execute a passed proposal
(define-public (execute-proposal (proposal-id uint))
    (let ((proposal-data (unwrap! (map-get? proposals proposal-id) ERR-NOT-FOUND)))
        (begin
            ;; Check if voting period has ended
            (asserts! (> stacks-block-height (get end-block proposal-data))
                ERR-PROPOSAL-NOT-ACTIVE
            )

            ;; Check if proposal hasn't been executed
            (asserts! (not (get executed proposal-data)) ERR-INVALID-STATUS)

            ;; Check if proposal passed (more yes than no votes and meets quorum)
            (asserts!
                (and
                    (> (get yes-votes proposal-data) (get no-votes proposal-data))
                    (>= (get total-votes proposal-data) QUORUM-THRESHOLD)
                )
                ERR-UNAUTHORIZED
            )

            ;; Execute based on proposal type
            (try! (if (is-eq (get proposal-type proposal-data) PROPOSAL-TYPE-PARAMETER)
                (execute-parameter-proposal proposal-data)
                (if (is-eq (get proposal-type proposal-data) PROPOSAL-TYPE-STATUS)
                    (execute-status-proposal proposal-data)
                    (execute-reviewer-proposal proposal-data)
                )
            ))

            ;; Mark as executed
            (map-set proposals proposal-id
                (merge proposal-data { executed: true })
            )

            (ok "Proposal executed successfully")
        )
    )
)

;; Execute parameter change proposal
(define-private (execute-parameter-proposal (proposal-data {
    proposer: principal,
    proposal-type: uint,
    title: (string-utf8 100),
    description: (string-utf8 500),
    target: (optional principal),
    parameter-name: (optional (string-ascii 50)),
    new-value: (optional uint),
    paper-id: (optional uint),
    new-status: (optional uint),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    total-votes: uint,
    executed: bool,
}))
    (let (
            (param-name (unwrap! (get parameter-name proposal-data) ERR-NOT-FOUND))
            (new-val (unwrap! (get new-value proposal-data) ERR-NOT-FOUND))
        )
        (begin
            (if (is-eq param-name "base-submission-fee")
                (var-set base-submission-fee new-val)
                (if (is-eq param-name "base-review-reward")
                    (var-set base-review-reward new-val)
                    (if (is-eq param-name "quality-multiplier")
                        (var-set quality-multiplier new-val)
                        (if (is-eq param-name "demand-multiplier")
                            (var-set demand-multiplier new-val)
                            false
                        )
                    )
                )
            )
            (ok true)
        )
    )
)

;; Execute status change proposal
(define-private (execute-status-proposal (proposal-data {
    proposer: principal,
    proposal-type: uint,
    title: (string-utf8 100),
    description: (string-utf8 500),
    target: (optional principal),
    parameter-name: (optional (string-ascii 50)),
    new-value: (optional uint),
    paper-id: (optional uint),
    new-status: (optional uint),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    total-votes: uint,
    executed: bool,
}))
    (let (
            (target-paper-id (unwrap! (get paper-id proposal-data) ERR-NOT-FOUND))
            (new-status-val (unwrap! (get new-status proposal-data) ERR-NOT-FOUND))
            (paper-data (unwrap! (map-get? papers target-paper-id) ERR-NOT-FOUND))
        )
        (begin
            (map-set papers target-paper-id
                (merge paper-data { status: new-status-val })
            )
            (ok true)
        )
    )
)

;; Execute reviewer action proposal
(define-private (execute-reviewer-proposal (proposal-data {
    proposer: principal,
    proposal-type: uint,
    title: (string-utf8 100),
    description: (string-utf8 500),
    target: (optional principal),
    parameter-name: (optional (string-ascii 50)),
    new-value: (optional uint),
    paper-id: (optional uint),
    new-status: (optional uint),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    total-votes: uint,
    executed: bool,
}))
    (let (
            (target-reviewer (unwrap! (get target proposal-data) ERR-NOT-FOUND))
            (reviewer-data (unwrap! (map-get? reviewers target-reviewer) ERR-NOT-FOUND))
        )
        (begin
            ;; Deactivate reviewer through governance
            (map-set reviewers target-reviewer
                (merge reviewer-data { is-active: false })
            )
            (ok true)
        )
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
;; STAKING & MULTI-TOKEN FUNCTIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 

;; Stake tokens as a reviewer for quality assurance
(define-public (stake-as-reviewer (amount uint))
    (begin
        ;; Check if reviewer is registered
        (asserts! (is-reviewer-registered tx-sender) ERR-NOT-REGISTERED)

        ;; Transfer STX to contract as stake
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

        ;; Record stake
        (map-set reviewer-stakes tx-sender {
            staked-amount: amount,
            stake-time: stacks-block-height,
        })

        (ok "Stake recorded successfully")
    )
)

;; Withdraw stake (only if no recent poor reviews)
(define-public (withdraw-stake)
    (let ((stake-data (unwrap! (map-get? reviewer-stakes tx-sender) ERR-NOT-FOUND)))
        (begin
            ;; Simple time-based withdrawal (could be enhanced with quality checks)
            (asserts!
                (> stacks-block-height (+ (get stake-time stake-data) u1440))
                ERR-INSUFFICIENT-BALANCE
            )

            ;; Return stake
            (try! (as-contract (stx-transfer? (get staked-amount stake-data) tx-sender tx-sender)))

            ;; Remove stake record
            (map-delete reviewer-stakes tx-sender)

            (ok "Stake withdrawn successfully")
        )
    )
)

;; Add supported token for payments
(define-public (add-supported-token
        (token-contract principal)
        (min-fee uint)
        (reward-rate uint)
        (decimals uint)
    )
    (begin
        ;; Only contract owner can add tokens initially (could be governance later)
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

        (map-set supported-tokens token-contract {
            is-active: true,
            min-fee: min-fee,
            reward-rate: reward-rate,
            decimals: decimals,
        })

        (ok "Token added successfully")
    )
)

;; Create paper bounty (additional reward for reviews)
(define-public (create-paper-bounty
        (paper-id uint)
        (bounty-amount uint)
        (token-contract (optional principal))
    )
    (let ((paper-data (unwrap! (map-get? papers paper-id) ERR-NOT-FOUND)))
        (begin
            ;; Only paper author can create bounty
            (asserts! (is-eq tx-sender (get author paper-data)) ERR-UNAUTHORIZED)

            ;; Transfer bounty to contract
            (match token-contract
                token-addr
                (begin
                    ;; For now, we'll just record the bounty
                    ;; In a full implementation, you'd need token transfer calls
                    true
                )
                ;; STX bounty
                (try! (stx-transfer? bounty-amount tx-sender (as-contract tx-sender)))
            )

            ;; Record bounty
            (map-set paper-bounties paper-id {
                bounty-amount: bounty-amount,
                token-contract: token-contract,
                claimed: false,
            })

            (ok "Bounty created successfully")
        )
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
;; ENHANCED READ-ONLY FUNCTIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

;; Get user's vote on a proposal
(define-read-only (get-user-vote
        (proposal-id uint)
        (voter principal)
    )
    (map-get? proposal-votes {
        proposal-id: proposal-id,
        voter: voter,
    })
)

;; Get governance token balance
(define-read-only (get-governance-balance (user principal))
    (ft-get-balance governance-token user)
)

;; Get reviewer stake info
(define-read-only (get-reviewer-stake (reviewer principal))
    (map-get? reviewer-stakes reviewer)
)

;; Get supported token info
(define-read-only (get-token-info (token-contract principal))
    (map-get? supported-tokens token-contract)
)

;; Get paper bounty info
(define-read-only (get-paper-bounty (paper-id uint))
    (map-get? paper-bounties paper-id)
)

;; Check if proposal can be executed
(define-read-only (can-execute-proposal (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal-data (and
            (> stacks-block-height (get end-block proposal-data))
            (not (get executed proposal-data))
            (> (get yes-votes proposal-data) (get no-votes proposal-data))
            (>= (get total-votes proposal-data) QUORUM-THRESHOLD)
        )
        false
    )
)

;; Contract initialization
(begin
    (var-set paper-counter u0)
    (var-set total-fees-collected u0)
    (var-set proposal-counter u0)
)
