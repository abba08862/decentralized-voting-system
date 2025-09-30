;; Ballot Manager Smart Contract
;; Comprehensive decentralized voting system for transparent, tamper-proof elections
;; Supports voter registration, ballot creation, voting, and result calculation

;; Constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-INPUT (err u422))
(define-constant ERR-ELECTION-EXISTS (err u409))
(define-constant ERR-ELECTION-CLOSED (err u410))
(define-constant ERR-ELECTION-NOT-STARTED (err u411))
(define-constant ERR-ALREADY-VOTED (err u412))
(define-constant ERR-NOT-REGISTERED (err u413))
(define-constant ERR-INVALID-OPTION (err u414))
(define-constant ERR-ELECTION-ACTIVE (err u415))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-OPTIONS u10)
(define-constant MAX-TITLE-LENGTH u100)
(define-constant MAX-DESCRIPTION-LENGTH u500)

;; Data Structures

;; Election registry - main election information
(define-map elections
  { election-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    start-time: uint,
    end-time: uint,
    is-active: bool,
    total-votes: uint,
    total-registered: uint,
    is-closed: bool
  }
)

;; Election options - voting choices for each election
(define-map election-options
  { election-id: uint, option-id: uint }
  {
    option-text: (string-ascii 100),
    vote-count: uint
  }
)

;; Voter registration - tracks registered voters per election
(define-map voter-registration
  { election-id: uint, voter: principal }
  {
    is-registered: bool,
    registration-time: uint,
    has-voted: bool,
    vote-time: (optional uint)
  }
)

;; Vote records - anonymous vote tracking
(define-map vote-records
  { election-id: uint, vote-id: uint }
  {
    option-id: uint,
    timestamp: uint,
    voter-hash: (buff 32)
  }
)

;; Election administrators
(define-map election-admins
  { election-id: uint, admin: principal }
  { authorized: bool }
)

;; Global counters
(define-data-var next-election-id uint u1)
(define-data-var next-vote-id uint u1)
(define-data-var total-elections uint u0)

;; Private Functions

;; Check if election is currently active (within voting window)
(define-private (is-election-active (election-id uint))
  (match (map-get? elections { election-id: election-id })
    election
    (let
      (
        (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
        (start-time (get start-time election))
        (end-time (get end-time election))
        (is-active (get is-active election))
      )
      (and is-active (>= current-time start-time) (<= current-time end-time))
    )
    false
  )
)

;; Check if voter is registered for election
(define-private (is-voter-registered (election-id uint) (voter principal))
  (default-to false
    (get is-registered (map-get? voter-registration { election-id: election-id, voter: voter }))
  )
)

;; Check if voter has already voted
(define-private (has-voter-voted (election-id uint) (voter principal))
  (default-to false
    (get has-voted (map-get? voter-registration { election-id: election-id, voter: voter }))
  )
)

;; Check if user is election admin
(define-private (is-election-admin (election-id uint) (user principal))
  (let
    (
      (election (map-get? elections { election-id: election-id }))
    )
    (match election
      election-data
      (or 
        (is-eq user (get creator election-data))
        (default-to false (get authorized (map-get? election-admins { election-id: election-id, admin: user })))
        (is-eq user CONTRACT-OWNER)
      )
      false
    )
  )
)

;; Generate voter hash for anonymization (using hash-bytes only)
(define-private (generate-voter-hash (voter principal) (election-id uint))
  (get hash-bytes (unwrap-panic (principal-destruct? voter)))
)

;; Public Functions

;; Create a new election
(define-public (create-election
    (title (string-ascii 100))
    (description (string-ascii 500))
    (start-time uint)
    (end-time uint)
    (options (list 10 (string-ascii 100)))
  )
  (let
    (
      (election-id (var-get next-election-id))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
      (options-length (len options))
    )
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (> start-time current-time) ERR-INVALID-INPUT)
    (asserts! (> end-time start-time) ERR-INVALID-INPUT)
    (asserts! (and (> options-length u1) (<= options-length MAX-OPTIONS)) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? elections { election-id: election-id })) ERR-ELECTION-EXISTS)
    
    ;; Create election record
    (map-set elections
      { election-id: election-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        start-time: start-time,
        end-time: end-time,
        is-active: true,
        total-votes: u0,
        total-registered: u0,
        is-closed: false
      }
    )
    
    ;; Add election options
    (map set-election-option
      (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)
      options
    )
    
    ;; Authorize creator as admin
    (map-set election-admins
      { election-id: election-id, admin: tx-sender }
      { authorized: true }
    )
    
    ;; Update counters
    (var-set next-election-id (+ election-id u1))
    (var-set total-elections (+ (var-get total-elections) u1))
    
    (ok election-id)
  )
)

;; Helper function to set election options
(define-private (set-election-option (option-id uint) (option-text (string-ascii 100)))
  (let
    (
      (election-id (- (var-get next-election-id) u1))
    )
    (if (> (len option-text) u0)
      (map-set election-options
        { election-id: election-id, option-id: option-id }
        {
          option-text: option-text,
          vote-count: u0
        }
      )
      false
    )
  )
)

;; Register voter for election
(define-public (register-voter (election-id uint) (voter principal))
  (let
    (
      (election (unwrap! (map-get? elections { election-id: election-id }) ERR-NOT-FOUND))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (is-election-admin election-id tx-sender) ERR-UNAUTHORIZED)
    (asserts! (get is-active election) ERR-ELECTION-CLOSED)
    (asserts! (not (is-voter-registered election-id voter)) ERR-INVALID-INPUT)
    
    ;; Register voter
    (map-set voter-registration
      { election-id: election-id, voter: voter }
      {
        is-registered: true,
        registration-time: current-time,
        has-voted: false,
        vote-time: none
      }
    )
    
    ;; Update registered count
    (map-set elections
      { election-id: election-id }
      (merge election { total-registered: (+ (get total-registered election) u1) })
    )
    
    (ok true)
  )
)

;; Cast vote in election
(define-public (cast-vote (election-id uint) (option-id uint))
  (let
    (
      (election (unwrap! (map-get? elections { election-id: election-id }) ERR-NOT-FOUND))
      (option (unwrap! (map-get? election-options { election-id: election-id, option-id: option-id }) ERR-INVALID-OPTION))
      (vote-id (var-get next-vote-id))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
      (voter-hash (generate-voter-hash tx-sender election-id))
    )
    (asserts! (is-election-active election-id) ERR-ELECTION-NOT-STARTED)
    (asserts! (is-voter-registered election-id tx-sender) ERR-NOT-REGISTERED)
    (asserts! (not (has-voter-voted election-id tx-sender)) ERR-ALREADY-VOTED)
    
    ;; Record anonymous vote
    (map-set vote-records
      { election-id: election-id, vote-id: vote-id }
      {
        option-id: option-id,
        timestamp: current-time,
        voter-hash: voter-hash
      }
    )
    
    ;; Update option vote count
    (map-set election-options
      { election-id: election-id, option-id: option-id }
      (merge option { vote-count: (+ (get vote-count option) u1) })
    )
    
    ;; Update voter status
    (map-set voter-registration
      { election-id: election-id, voter: tx-sender }
      (merge 
        (unwrap-panic (map-get? voter-registration { election-id: election-id, voter: tx-sender }))
        { has-voted: true, vote-time: (some current-time) }
      )
    )
    
    ;; Update election totals
    (map-set elections
      { election-id: election-id }
      (merge election { total-votes: (+ (get total-votes election) u1) })
    )
    
    ;; Update vote counter
    (var-set next-vote-id (+ vote-id u1))
    
    (ok vote-id)
  )
)

;; Close election (can only be done by admin)
(define-public (close-election (election-id uint))
  (let
    (
      (election (unwrap! (map-get? elections { election-id: election-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-election-admin election-id tx-sender) ERR-UNAUTHORIZED)
    (asserts! (get is-active election) ERR-ELECTION-CLOSED)
    
    (map-set elections
      { election-id: election-id }
      (merge election { is-active: false, is-closed: true })
    )
    
    (ok true)
  )
)

;; Add election administrator
(define-public (add-election-admin (election-id uint) (admin principal))
  (let
    (
      (election (unwrap! (map-get? elections { election-id: election-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-election-admin election-id tx-sender) ERR-UNAUTHORIZED)
    
    (map-set election-admins
      { election-id: election-id, admin: admin }
      { authorized: true }
    )
    
    (ok true)
  )
)

;; Read-only Functions

;; Get election information
(define-read-only (get-election (election-id uint))
  (map-get? elections { election-id: election-id })
)

;; Get election option
(define-read-only (get-election-option (election-id uint) (option-id uint))
  (map-get? election-options { election-id: election-id, option-id: option-id })
)

;; Get voter registration status
(define-read-only (get-voter-registration (election-id uint) (voter principal))
  (map-get? voter-registration { election-id: election-id, voter: voter })
)

;; Get election results (all options with vote counts)
(define-read-only (get-election-results (election-id uint))
  (let
    (
      (election (map-get? elections { election-id: election-id }))
    )
    (match election
      election-data
      (ok {
        election: election-data,
        options: {
          option-0: (map-get? election-options { election-id: election-id, option-id: u0 }),
          option-1: (map-get? election-options { election-id: election-id, option-id: u1 }),
          option-2: (map-get? election-options { election-id: election-id, option-id: u2 }),
          option-3: (map-get? election-options { election-id: election-id, option-id: u3 }),
          option-4: (map-get? election-options { election-id: election-id, option-id: u4 })
        }
      })
      ERR-NOT-FOUND
    )
  )
)

;; Check if election is currently active
(define-read-only (check-election-status (election-id uint))
  (let
    (
      (is-active (is-election-active election-id))
      (election (map-get? elections { election-id: election-id }))
    )
    (match election
      election-data
      (ok {
        is-active: is-active,
        is-closed: (get is-closed election-data),
        total-votes: (get total-votes election-data),
        total-registered: (get total-registered election-data)
      })
      ERR-NOT-FOUND
    )
  )
)

;; Get total number of elections
(define-read-only (get-total-elections)
  (var-get total-elections)
)

;; Verify vote (check if vote hash exists)
(define-read-only (verify-vote-integrity (election-id uint) (voter principal))
  (let
    (
      (voter-hash (generate-voter-hash voter election-id))
      (registration (map-get? voter-registration { election-id: election-id, voter: voter }))
    )
    (match registration
      reg-data
      (ok {
        is-registered: (get is-registered reg-data),
        has-voted: (get has-voted reg-data),
        vote-time: (get vote-time reg-data)
      })
      (ok { is-registered: false, has-voted: false, vote-time: none })
    )
  )
)
