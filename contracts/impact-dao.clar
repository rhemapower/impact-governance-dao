;; impact-dao.clar
;; This contract implements the core functionality for the Impact Governance DAO,
;; a framework for collective decision-making around social impact initiatives.
;; It handles membership management, proposal submission and voting, treasury
;; management, and project tracking in a transparent and decentralized manner.

;; =============================
;; Constants and Error Codes
;; =============================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-ALREADY-EXISTS (err u101))
(define-constant ERR-PROPOSAL-DOESNT-EXIST (err u102))
(define-constant ERR-PROPOSAL-EXPIRED (err u103))
(define-constant ERR-PROPOSAL-ACTIVE (err u104))
(define-constant ERR-PROPOSAL-EXECUTED (err u105))
(define-constant ERR-ALREADY-VOTED (err u106))
(define-constant ERR-INSUFFICIENT-BALANCE (err u107))
(define-constant ERR-THRESHOLD-NOT-REACHED (err u108))
(define-constant ERR-NOT-MEMBER (err u109))
(define-constant ERR-MEMBERSHIP-ALREADY-EXISTS (err u110))
(define-constant ERR-INVALID-PARAMETER (err u111))
(define-constant ERR-NOT-ADMIN (err u112))
(define-constant ERR-VOTING-PERIOD-ACTIVE (err u113))
(define-constant ERR-VOTING-PERIOD-NOT-ACTIVE (err u114))
(define-constant ERR-TREASURY-INSUFFICIENT-FUNDS (err u115))

;; DAO parameters
(define-constant DAO-NAME "Impact Governance DAO")
(define-constant PROPOSAL-DURATION u10080) ;; Default proposal voting duration (10080 blocks ≈ 10 days)
(define-constant QUORUM-THRESHOLD u30) ;; 30% of total voting power needed for quorum
(define-constant APPROVAL-THRESHOLD u50) ;; 50% approval required to pass

;; =============================
;; Data Maps and Variables
;; =============================

;; Member data
(define-map members principal 
  {
    tokens: uint, ;; Governance tokens held
    joined-at: uint, ;; Block height when member joined
    reputation: uint, ;; Reputation score (0-100)
    proposals-created: uint, ;; Number of proposals created
    votes-cast: uint ;; Number of votes cast
  }
)

;; Proposal data
(define-map proposals uint 
  {
    id: uint, ;; Proposal ID
    creator: principal, ;; Who created the proposal
    title: (string-ascii 100), ;; Short title
    description: (string-utf8 1000), ;; Detailed description
    link: (optional (string-ascii 255)), ;; Link to additional info
    funds-requested: uint, ;; Amount of funds requested
    created-at: uint, ;; Block height when created
    expires-at: uint, ;; Block height when voting ends
    executed-at: (optional uint), ;; Block height when executed
    status: (string-ascii 20), ;; "active", "approved", "rejected", "executed"
    yes-votes: uint, ;; Total "yes" voting power
    no-votes: uint, ;; Total "no" voting power
    beneficiary: principal, ;; Who receives the funds if approved
    impact-metrics: (string-utf8 500) ;; Expected impact metrics
  }
)

;; Vote registry to track who voted for what
(define-map votes {proposal-id: uint, voter: principal} 
  {
    vote: bool, ;; true = yes, false = no
    weight: uint, ;; Voting power used
    time: uint ;; Block height when vote was cast
  }
)

;; DAO configuration parameters (can be adjusted through governance)
(define-data-var dao-admin principal tx-sender) ;; Initial admin is contract deployer
(define-data-var proposal-duration uint PROPOSAL-DURATION) ;; How long proposals stay open for voting
(define-data-var quorum-threshold uint QUORUM-THRESHOLD) ;; Percentage of total voting power needed for quorum
(define-data-var approval-threshold uint APPROVAL-THRESHOLD) ;; Percentage of votes needed for approval
(define-data-var total-governance-tokens uint u0) ;; Total governance tokens issued
(define-data-var proposal-count uint u0) ;; Counter for proposal IDs
(define-data-var treasury-balance uint u0) ;; Current balance of the treasury

;; =============================
;; Private Functions
;; =============================

;; Check if the caller is a DAO member
(define-private (is-member (caller principal)) 
  (match (map-get? members caller)
    member true
    false
  )
)

;; Get a member's voting power (their token balance)
(define-private (get-voting-power (caller principal))
  (default-to u0 
    (get tokens 
      (map-get? members caller)
    )
  )
)

;; Check if a proposal exists
(define-private (proposal-exists (proposal-id uint))
  (is-some (map-get? proposals proposal-id))
)

;; Check if a proposal is still active for voting
(define-private (is-proposal-active (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and 
              (is-eq (get status proposal) "active") 
              (<= block-height (get expires-at proposal))
            )
    false
  )
)

;; Check if a member has already voted on a proposal
(define-private (has-voted (proposal-id uint) (voter principal))
  (is-some (map-get? votes {proposal-id: proposal-id, voter: voter}))
)

;; Calculate if a proposal has reached quorum
(define-private (has-reached-quorum (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (let ((total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
                  (required-votes (/ (* (var-get total-governance-tokens) (var-get quorum-threshold)) u100)))
              (>= total-votes required-votes))
    false
  )
)

;; Calculate if a proposal has been approved
(define-private (is-proposal-approved (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (let ((total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
                  (approval-percentage (if (is-eq total-votes u0) 
                                         u0
                                         (/ (* (get yes-votes proposal) u100) total-votes))))
              (>= approval-percentage (var-get approval-threshold)))
    false
  )
)

;; Update proposal status based on voting results
(define-private (update-proposal-status (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (if (is-eq (get status proposal) "active")
               (if (has-reached-quorum proposal-id)
                 (if (is-proposal-approved proposal-id)
                   (map-set proposals proposal-id 
                     (merge proposal {status: "approved"}))
                   (map-set proposals proposal-id 
                     (merge proposal {status: "rejected"})))
                 (map-set proposals proposal-id 
                   (merge proposal {status: "rejected"})))
               false)
    false
  )
)

;; =============================
;; Read-Only Functions
;; =============================

;; Get DAO information
(define-read-only (get-dao-info)
  {
    name: DAO-NAME,
    admin: (var-get dao-admin),
    total-tokens: (var-get total-governance-tokens),
    proposal-count: (var-get proposal-count),
    treasury-balance: (var-get treasury-balance),
    proposal-duration: (var-get proposal-duration),
    quorum-threshold: (var-get quorum-threshold),
    approval-threshold: (var-get approval-threshold)
  }
)

;; Get member details
(define-read-only (get-member (member-addr principal))
  (map-get? members member-addr)
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

;; Get a member's vote on a specific proposal
(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes {proposal-id: proposal-id, voter: voter})
)

;; Check if a proposal has reached the required thresholds
(define-read-only (check-proposal-status (proposal-id uint))
  {
    exists: (proposal-exists proposal-id),
    active: (is-proposal-active proposal-id),
    quorum-reached: (has-reached-quorum proposal-id),
    approved: (is-proposal-approved proposal-id)
  }
)

;; =============================
;; Public Functions
;; =============================

;; Add a new member to the DAO
(define-public (join-dao (token-amount uint))
  (let ((caller tx-sender))
    (asserts! (> token-amount u0) ERR-INVALID-PARAMETER)
    (asserts! (is-none (map-get? members caller)) ERR-MEMBERSHIP-ALREADY-EXISTS)
    
    ;; In a real implementation, this would involve a token transfer
    ;; For now we're just registering membership

    (map-set members caller {
      tokens: token-amount,
      joined-at: block-height,
      reputation: u50, ;; Start with neutral reputation
      proposals-created: u0,
      votes-cast: u0
    })
    
    ;; Update total governance tokens
    (var-set total-governance-tokens (+ (var-get total-governance-tokens) token-amount))
    
    (ok true)
  )
)

;; Create a new proposal
(define-public (create-proposal 
                (title (string-ascii 100))
                (description (string-utf8 1000))
                (link (optional (string-ascii 255)))
                (funds-requested uint)
                (beneficiary principal)
                (impact-metrics (string-utf8 500)))
  (let ((caller tx-sender)
        (new-id (+ (var-get proposal-count) u1)))
    
    ;; Check if caller is a member
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    ;; Check if funds requested are available
    (asserts! (<= funds-requested (var-get treasury-balance)) ERR-TREASURY-INSUFFICIENT-FUNDS)
    
    ;; Increment proposal counter
    (var-set proposal-count new-id)
    
    ;; Store proposal details
    (map-set proposals new-id {
      id: new-id,
      creator: caller,
      title: title,
      description: description,
      link: link,
      funds-requested: funds-requested,
      created-at: block-height,
      expires-at: (+ block-height (var-get proposal-duration)),
      executed-at: none,
      status: "active",
      yes-votes: u0,
      no-votes: u0,
      beneficiary: beneficiary,
      impact-metrics: impact-metrics
    })
    
    ;; Update member's proposal count
    (match (map-get? members caller)
      member (map-set members caller 
               (merge member {proposals-created: (+ (get proposals-created member) u1)}))
      ERR-NOT-MEMBER
    )
    
    (ok new-id)
  )
)

;; Cast a vote on a proposal
(define-public (vote (proposal-id uint) (vote-for bool))
  (let ((caller tx-sender)
        (voting-power (get-voting-power caller)))
    
    ;; Check if caller is a member
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    ;; Check if caller has voting power
    (asserts! (> voting-power u0) ERR-INSUFFICIENT-BALANCE)
    ;; Check if proposal exists
    (asserts! (proposal-exists proposal-id) ERR-PROPOSAL-DOESNT-EXIST)
    ;; Check if proposal is still active
    (asserts! (is-proposal-active proposal-id) ERR-PROPOSAL-EXPIRED)
    ;; Check if member has already voted
    (asserts! (not (has-voted proposal-id caller)) ERR-ALREADY-VOTED)
    
    ;; Record the vote
    (map-set votes {proposal-id: proposal-id, voter: caller} {
      vote: vote-for,
      weight: voting-power,
      time: block-height
    })
    
    ;; Update proposal vote counts
    (match (map-get? proposals proposal-id)
      proposal (map-set proposals proposal-id (merge proposal 
                 (if vote-for
                   {yes-votes: (+ (get yes-votes proposal) voting-power)}
                   {no-votes: (+ (get no-votes proposal) voting-power)})))
      ERR-PROPOSAL-DOESNT-EXIST
    )
    
    ;; Update member's vote count
    (match (map-get? members caller)
      member (map-set members caller 
               (merge member {votes-cast: (+ (get votes-cast member) u1)}))
      ERR-NOT-MEMBER
    )
    
    (ok true)
  )
)

;; End voting period for a proposal and determine outcome
(define-public (finalize-proposal (proposal-id uint))
  (let ((caller tx-sender))
    ;; Check if proposal exists
    (asserts! (proposal-exists proposal-id) ERR-PROPOSAL-DOESNT-EXIST)
    
    (match (map-get? proposals proposal-id)
      proposal (begin
        ;; Check if proposal is still active and voting period has ended
        (asserts! (is-eq (get status proposal) "active") ERR-PROPOSAL-EXECUTED)
        (asserts! (>= block-height (get expires-at proposal)) ERR-VOTING-PERIOD-ACTIVE)
        
        ;; Update proposal status based on voting results
        (update-proposal-status proposal-id)
        (ok true))
      ERR-PROPOSAL-DOESNT-EXIST
    )
  )
)

;; Execute an approved proposal (disburse funds)
(define-public (execute-proposal (proposal-id uint))
  (let ((caller tx-sender))
    ;; In a production environment, we might want to restrict this to admins or governance
    ;; For now any member can trigger execution once approved
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    
    (match (map-get? proposals proposal-id)
      proposal (begin
        ;; Check if proposal is approved and not yet executed
        (asserts! (is-eq (get status proposal) "approved") ERR-PROPOSAL-EXPIRED)
        (asserts! (is-none (get executed-at proposal)) ERR-PROPOSAL-EXECUTED)
        
        ;; Check if treasury has sufficient funds
        (asserts! (<= (get funds-requested proposal) (var-get treasury-balance)) ERR-TREASURY-INSUFFICIENT-FUNDS)
        
        ;; Update treasury balance
        (var-set treasury-balance (- (var-get treasury-balance) (get funds-requested proposal)))
        
        ;; Update proposal as executed
        (map-set proposals proposal-id (merge proposal {
          status: "executed",
          executed-at: (some block-height)
        }))
        
        ;; In a real implementation, this would trigger a token transfer to the beneficiary
        ;; For this implementation, we just mark it executed
        
        (ok true))
      ERR-PROPOSAL-DOESNT-EXIST
    )
  )
)

;; Deposit funds into the treasury
(define-public (deposit-to-treasury (amount uint))
  (let ((caller tx-sender))
    (asserts! (> amount u0) ERR-INVALID-PARAMETER)
    
    ;; In a real implementation, this would involve a token transfer to the contract
    ;; For now we're just increasing the recorded balance
    
    ;; Update treasury balance
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    
    (ok true)
  )
)

;; Update DAO parameters (admin only)
(define-public (update-dao-parameters 
                (new-proposal-duration (optional uint))
                (new-quorum-threshold (optional uint))
                (new-approval-threshold (optional uint)))
  (let ((caller tx-sender))
    ;; Check if caller is admin
    (asserts! (is-eq caller (var-get dao-admin)) ERR-NOT-ADMIN)
    
    ;; Update each parameter if provided
    (if (is-some new-proposal-duration)
      (var-set proposal-duration (unwrap! new-proposal-duration ERR-INVALID-PARAMETER))
      true)
    
    (if (is-some new-quorum-threshold)
      (begin
        (asserts! (<= (unwrap! new-quorum-threshold ERR-INVALID-PARAMETER) u100) ERR-INVALID-PARAMETER)
        (var-set quorum-threshold (unwrap! new-quorum-threshold ERR-INVALID-PARAMETER)))
      true)
    
    (if (is-some new-approval-threshold)
      (begin
        (asserts! (<= (unwrap! new-approval-threshold ERR-INVALID-PARAMETER) u100) ERR-INVALID-PARAMETER)
        (var-set approval-threshold (unwrap! new-approval-threshold ERR-INVALID-PARAMETER)))
      true)
    
    (ok true)
  )
)

;; Transfer admin rights to a new address (current admin only)
(define-public (transfer-admin (new-admin principal))
  (let ((caller tx-sender))
    ;; Check if caller is the current admin
    (asserts! (is-eq caller (var-get dao-admin)) ERR-NOT-ADMIN)
    
    ;; Set the new admin
    (var-set dao-admin new-admin)
    
    (ok true)
  )
)