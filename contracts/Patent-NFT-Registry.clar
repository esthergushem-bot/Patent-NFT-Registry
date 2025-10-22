(define-non-fungible-token patent-nft uint)

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_INPUT (err u400))
(define-constant ERR_TRANSFER_FAILED (err u500))
(define-constant ERR_INSUFFICIENT_VOTES (err u501))
(define-constant ERR_ALREADY_COLLABORATOR (err u502))
(define-constant ERR_NOT_COLLABORATOR (err u503))
(define-constant ERR_PATENT_EXPIRED (err u504))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u505))
(define-constant ERR_ALREADY_RENEWED (err u506))
(define-constant ERR_GRACE_PERIOD_EXPIRED (err u507))
(define-constant ERR_INVALID_RENEWAL_PERIOD (err u508))

(define-data-var patent-counter uint u0)
(define-data-var contract-uri (optional (string-utf8 256)) none)
(define-data-var default-validity-period uint u52560)
(define-data-var base-renewal-fee uint u1000000)
(define-data-var grace-period uint u5256)

(define-map patent-metadata 
  uint 
  {
    title: (string-utf8 100),
    description: (string-utf8 500),
    inventor: principal,
    jurisdiction: (string-utf8 50),
    category: (string-utf8 50),
    filing-timestamp: uint,
    technical-hash: (buff 32),
    patent-status: (string-utf8 20),
    priority-date: uint,
    application-number: (string-utf8 50)
  }
)

(define-map patent-ownership uint principal)
(define-map inventor-patents principal (list 100 uint))
(define-map jurisdiction-patents (string-utf8 50) (list 1000 uint))
(define-map category-patents (string-utf8 50) (list 1000 uint))
(define-map patent-transfers uint (list 10 {from: principal, to: principal, timestamp: uint}))
(define-map patent-licensing uint {licensee: principal, terms: (string-utf8 200), expiry: uint, active: bool})
(define-map patent-collaborators uint (list 10 {collaborator: principal, share: uint, joined-at: uint}))
(define-map collaboration-votes uint {proposal-type: (string-utf8 20), votes-for: uint, votes-against: uint, total-collaborators: uint, expires-at: uint, executed: bool})
(define-map collaborator-exists {patent-id: uint, collaborator: principal} bool)
(define-map patent-renewal uint {expiry-height: uint, renewals-count: uint, last-renewed: uint})
(define-map patent-validity-periods uint uint)
(define-map renewal-history uint (list 10 {renewal-height: uint, paid-fee: uint, extended-to: uint}))

(define-read-only (get-last-token-id)
  (ok (var-get patent-counter))
)

(define-read-only (get-token-uri (patent-id uint))
  (ok (var-get contract-uri))
)

(define-read-only (get-owner (patent-id uint))
  (ok (map-get? patent-ownership patent-id))
)

(define-read-only (get-patent-metadata (patent-id uint))
  (map-get? patent-metadata patent-id)
)

(define-read-only (get-patents-by-inventor (inventor principal))
  (default-to (list) (map-get? inventor-patents inventor))
)

(define-read-only (get-patents-by-jurisdiction (jurisdiction (string-utf8 50)))
  (default-to (list) (map-get? jurisdiction-patents jurisdiction))
)

(define-read-only (get-patents-by-category (category (string-utf8 50)))
  (default-to (list) (map-get? category-patents category))
)

(define-read-only (get-patent-transfers (patent-id uint))
  (default-to (list) (map-get? patent-transfers patent-id))
)

(define-read-only (get-patent-license (patent-id uint))
  (map-get? patent-licensing patent-id)
)

(define-read-only (get-patent-collaborators (patent-id uint))
  (default-to (list) (map-get? patent-collaborators patent-id))
)

(define-read-only (get-collaboration-vote (patent-id uint))
  (map-get? collaboration-votes patent-id)
)

(define-read-only (is-collaborator (patent-id uint) (user principal))
  (default-to false (map-get? collaborator-exists {patent-id: patent-id, collaborator: user}))
)

(define-read-only (verify-patent-timestamp (patent-id uint) (claimed-timestamp uint))
  (match (get-patent-metadata patent-id)
    metadata (ok (is-eq (get filing-timestamp metadata) claimed-timestamp))
    (err ERR_NOT_FOUND)
  )
)

(define-read-only (get-patent-priority-status (patent-id uint))
  (match (get-patent-metadata patent-id)
    metadata 
    (let ((current-height stacks-block-height)
          (filing-height (get filing-timestamp metadata)))
      (ok {
        patent-id: patent-id,
        filing-height: filing-height,
        current-height: current-height,
        blocks-since-filing: (- current-height filing-height),
        is-recent: (< (- current-height filing-height) u1000)
      }))
    (err ERR_NOT_FOUND)
  )
)

(define-public (register-patent 
  (title (string-utf8 100))
  (description (string-utf8 500))
  (jurisdiction (string-utf8 50))
  (category (string-utf8 50))
  (technical-hash (buff 32))
  (priority-date uint)
  (application-number (string-utf8 50))
)
  (let (
    (patent-id (+ (var-get patent-counter) u1))
    (current-timestamp stacks-block-height)
  )
    (asserts! (> (len title) u0) ERR_INVALID_INPUT)
    (asserts! (> (len description) u0) ERR_INVALID_INPUT)
    (asserts! (> (len jurisdiction) u0) ERR_INVALID_INPUT)
    (asserts! (> (len category) u0) ERR_INVALID_INPUT)
    (asserts! (> (len application-number) u0) ERR_INVALID_INPUT)
    
    (try! (nft-mint? patent-nft patent-id tx-sender))
    
    (map-set patent-metadata patent-id {
      title: title,
      description: description,
      inventor: tx-sender,
      jurisdiction: jurisdiction,
      category: category,
      filing-timestamp: current-timestamp,
      technical-hash: technical-hash,
      patent-status: u"pending",
      priority-date: priority-date,
      application-number: application-number
    })
    
    (map-set patent-ownership patent-id tx-sender)
    
    (let ((current-inventor-patents (get-patents-by-inventor tx-sender)))
      (map-set inventor-patents tx-sender 
        (unwrap! (as-max-len? (append current-inventor-patents patent-id) u100) ERR_TRANSFER_FAILED))
    )
    
    (let ((current-jurisdiction-patents (get-patents-by-jurisdiction jurisdiction)))
      (map-set jurisdiction-patents jurisdiction 
        (unwrap! (as-max-len? (append current-jurisdiction-patents patent-id) u1000) ERR_TRANSFER_FAILED))
    )
    
    (let ((current-category-patents (get-patents-by-category category)))
      (map-set category-patents category 
        (unwrap! (as-max-len? (append current-category-patents patent-id) u1000) ERR_TRANSFER_FAILED))
    )
    
    (var-set patent-counter patent-id)
    
    (map-set patent-renewal patent-id {
      expiry-height: (+ current-timestamp (var-get default-validity-period)),
      renewals-count: u0,
      last-renewed: current-timestamp
    })
    
    (ok patent-id)
  )
)

(define-public (add-collaborator (patent-id uint) (collaborator principal) (share uint))
  (let (
    (metadata (unwrap! (get-patent-metadata patent-id) ERR_NOT_FOUND))
    (current-collaborators (get-patent-collaborators patent-id))
  )
    (asserts! (is-eq tx-sender (get inventor metadata)) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-collaborator patent-id collaborator)) ERR_ALREADY_COLLABORATOR)
    (asserts! (> share u0) ERR_INVALID_INPUT)
    (asserts! (<= share u100) ERR_INVALID_INPUT)
    
    (let ((new-collaborator {collaborator: collaborator, share: share, joined-at: stacks-block-height}))
      (map-set patent-collaborators patent-id 
        (unwrap! (as-max-len? (append current-collaborators new-collaborator) u10) ERR_TRANSFER_FAILED))
      (map-set collaborator-exists {patent-id: patent-id, collaborator: collaborator} true)
    )
    (ok true)
  )
)

(define-public (remove-collaborator (patent-id uint) (collaborator principal))
  (let (
    (metadata (unwrap! (get-patent-metadata patent-id) ERR_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get inventor metadata)) ERR_NOT_AUTHORIZED)
    (asserts! (is-collaborator patent-id collaborator) ERR_NOT_COLLABORATOR)
    
    (map-delete collaborator-exists {patent-id: patent-id, collaborator: collaborator})
    (ok true)
  )
)

(define-public (start-collaboration-vote (patent-id uint) (proposal-type (string-utf8 20)) (duration uint))
  (let (
    (metadata (unwrap! (get-patent-metadata patent-id) ERR_NOT_FOUND))
    (collaborators (get-patent-collaborators patent-id))
    (total-collabs (+ (len collaborators) u1))
  )
    (asserts! (or (is-eq tx-sender (get inventor metadata)) (is-collaborator patent-id tx-sender)) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (get-collaboration-vote patent-id)) ERR_ALREADY_EXISTS)
    (asserts! (> duration u0) ERR_INVALID_INPUT)
    
    (map-set collaboration-votes patent-id {
      proposal-type: proposal-type,
      votes-for: u0,
      votes-against: u0,
      total-collaborators: total-collabs,
      expires-at: (+ stacks-block-height duration),
      executed: false
    })
    (ok true)
  )
)

(define-public (cast-collaboration-vote (patent-id uint) (vote-for bool))
  (let (
    (metadata (unwrap! (get-patent-metadata patent-id) ERR_NOT_FOUND))
    (vote-data (unwrap! (get-collaboration-vote patent-id) ERR_NOT_FOUND))
  )
    (asserts! (or (is-eq tx-sender (get inventor metadata)) (is-collaborator patent-id tx-sender)) ERR_NOT_COLLABORATOR)
    (asserts! (< stacks-block-height (get expires-at vote-data)) ERR_INVALID_INPUT)
    (asserts! (not (get executed vote-data)) ERR_ALREADY_EXISTS)
    
    (let (
      (new-votes-for (if vote-for (+ (get votes-for vote-data) u1) (get votes-for vote-data)))
      (new-votes-against (if vote-for (get votes-against vote-data) (+ (get votes-against vote-data) u1)))
    )
      (map-set collaboration-votes patent-id (merge vote-data {
        votes-for: new-votes-for,
        votes-against: new-votes-against
      }))
    )
    (ok true)
  )
)

(define-public (execute-collaboration-vote (patent-id uint))
  (let (
    (vote-data (unwrap! (get-collaboration-vote patent-id) ERR_NOT_FOUND))
    (votes-for (get votes-for vote-data))
    (total-collabs (get total-collaborators vote-data))
    (majority-threshold (/ (+ total-collabs u1) u2))
  )
    (asserts! (>= stacks-block-height (get expires-at vote-data)) ERR_INVALID_INPUT)
    (asserts! (not (get executed vote-data)) ERR_ALREADY_EXISTS)
    (asserts! (>= votes-for majority-threshold) ERR_INSUFFICIENT_VOTES)
    
    (map-set collaboration-votes patent-id (merge vote-data {executed: true}))
    (ok true)
  )
)

(define-public (update-patent-status (patent-id uint) (new-status (string-utf8 20)))
  (let (
    (metadata (unwrap! (get-patent-metadata patent-id) ERR_NOT_FOUND))
    (collaborators (get-patent-collaborators patent-id))
    (has-collaborators (> (len collaborators) u0))
  )
    (asserts! (> (len new-status) u0) ERR_INVALID_INPUT)
    
    (if has-collaborators
      (let ((vote-data (get-collaboration-vote patent-id)))
        (asserts! (is-some vote-data) ERR_NOT_AUTHORIZED)
        (asserts! (get executed (unwrap-panic vote-data)) ERR_NOT_AUTHORIZED)
        (map-set patent-metadata patent-id (merge metadata {patent-status: new-status}))
        (ok true)
      )
      (begin
        (asserts! (is-eq tx-sender (get inventor metadata)) ERR_NOT_AUTHORIZED)
        (map-set patent-metadata patent-id (merge metadata {patent-status: new-status}))
        (ok true)
      )
    )
  )
)

(define-public (transfer (patent-id uint) (sender principal) (recipient principal))
  (let ((owner (unwrap! (unwrap! (get-owner patent-id) ERR_NOT_FOUND) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq sender owner) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq sender recipient)) ERR_INVALID_INPUT)
    (asserts! (not (unwrap! (is-patent-expired patent-id) ERR_TRANSFER_FAILED)) ERR_PATENT_EXPIRED)
    
    (try! (nft-transfer? patent-nft patent-id sender recipient))
    (map-set patent-ownership patent-id recipient)
    
    (let ((current-transfers (get-patent-transfers patent-id)))
      (map-set patent-transfers patent-id 
        (unwrap! (as-max-len? 
          (append current-transfers {from: sender, to: recipient, timestamp: stacks-block-height}) 
          u10) ERR_TRANSFER_FAILED))
    )
    
    (ok true)
  )
)

(define-public (license-patent 
  (patent-id uint) 
  (licensee principal) 
  (terms (string-utf8 200)) 
  (duration uint)
)
  (let (
    (metadata (unwrap! (get-patent-metadata patent-id) ERR_NOT_FOUND))
    (collaborators (get-patent-collaborators patent-id))
    (has-collaborators (> (len collaborators) u0))
    (expiry-height (+ stacks-block-height duration))
  )
    (asserts! (> (len terms) u0) ERR_INVALID_INPUT)
    (asserts! (> duration u0) ERR_INVALID_INPUT)
    
    (if has-collaborators
      (let ((vote-data (get-collaboration-vote patent-id)))
        (asserts! (is-some vote-data) ERR_NOT_AUTHORIZED)
        (asserts! (get executed (unwrap-panic vote-data)) ERR_NOT_AUTHORIZED)
        (map-set patent-licensing patent-id {
          licensee: licensee,
          terms: terms,
          expiry: expiry-height,
          active: true
        })
        (ok true)
      )
      (begin
        (asserts! (is-eq tx-sender (get inventor metadata)) ERR_NOT_AUTHORIZED)
        (map-set patent-licensing patent-id {
          licensee: licensee,
          terms: terms,
          expiry: expiry-height,
          active: true
        })
        (ok true)
      )
    )
  )
)

(define-public (revoke-license (patent-id uint))
  (let ((metadata (unwrap! (get-patent-metadata patent-id) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get inventor metadata)) ERR_NOT_AUTHORIZED)
    
    (match (get-patent-license patent-id)
      license 
      (begin
        (map-set patent-licensing patent-id (merge license {active: false}))
        (ok true)
      )
      (ok false)
    )
  )
)

(define-public (set-contract-uri (uri (optional (string-utf8 256))))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-uri uri)
    (ok true)
  )
)

(define-read-only (check-patent-validity (patent-id uint))
  (match (get-patent-metadata patent-id)
    metadata 
    (let (
      (current-height stacks-block-height)
      (filing-height (get filing-timestamp metadata))
      (blocks-elapsed (- current-height filing-height))
    )
      (ok {
        valid: (and 
          (< blocks-elapsed u525600)
          (is-eq (get patent-status metadata) u"approved")
        ),
        filing-timestamp: filing-height,
        blocks-since-filing: blocks-elapsed,
        status: (get patent-status metadata)
      })
    )
    (err ERR_NOT_FOUND)
  )
)

(define-read-only (get-total-patents)
  (var-get patent-counter)
)

(define-read-only (get-patent-expiration (patent-id uint))
  (match (map-get? patent-renewal patent-id)
    renewal-data (ok (some (get expiry-height renewal-data)))
    (ok none)
  )
)

(define-read-only (is-patent-expired (patent-id uint))
  (match (map-get? patent-renewal patent-id)
    renewal-data 
    (ok (>= stacks-block-height (get expiry-height renewal-data)))
    (ok false)
  )
)

(define-read-only (is-in-grace-period (patent-id uint))
  (match (map-get? patent-renewal patent-id)
    renewal-data 
    (let ((expiry-height (get expiry-height renewal-data))
          (grace-end (+ expiry-height (var-get grace-period))))
      (ok (and (>= stacks-block-height expiry-height) 
               (< stacks-block-height grace-end)))
    )
    (ok false)
  )
)

(define-read-only (calculate-renewal-fee (patent-id uint))
  (match (map-get? patent-renewal patent-id)
    renewal-data 
    (let ((base-fee (var-get base-renewal-fee))
          (renewals-count (get renewals-count renewal-data))
          (multiplier (+ u1 (* renewals-count u1)))
          (expiry-height (get expiry-height renewal-data))
          (is-expired (>= stacks-block-height expiry-height))
          (late-penalty (if is-expired u500000 u0)))
      (ok (+ (* base-fee multiplier) late-penalty))
    )
    (ok (var-get base-renewal-fee))
  )
)

(define-read-only (get-renewal-history (patent-id uint))
  (default-to (list) (map-get? renewal-history patent-id))
)

(define-public (set-patent-validity-period (patent-id uint) (validity-period uint))
  (let ((owner (unwrap! (unwrap! (get-owner patent-id) ERR_NOT_FOUND) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender owner) ERR_NOT_AUTHORIZED)
    (asserts! (> validity-period u0) ERR_INVALID_RENEWAL_PERIOD)
    (asserts! (is-none (map-get? patent-renewal patent-id)) ERR_ALREADY_EXISTS)
    
    (map-set patent-validity-periods patent-id validity-period)
    (map-set patent-renewal patent-id {
      expiry-height: (+ stacks-block-height validity-period),
      renewals-count: u0,
      last-renewed: stacks-block-height
    })
    (ok true)
  )
)

(define-public (renew-patent (patent-id uint))
  (let (
    (owner (unwrap! (unwrap! (get-owner patent-id) ERR_NOT_FOUND) ERR_NOT_FOUND))
    (renewal-data (unwrap! (map-get? patent-renewal patent-id) ERR_NOT_FOUND))
    (required-fee (unwrap! (calculate-renewal-fee patent-id) ERR_TRANSFER_FAILED))
    (expiry-height (get expiry-height renewal-data))
    (grace-end (+ expiry-height (var-get grace-period)))
    (validity-period (default-to (var-get default-validity-period) (map-get? patent-validity-periods patent-id)))
    (current-history (get-renewal-history patent-id))
  )
    (asserts! (is-eq tx-sender owner) ERR_NOT_AUTHORIZED)
    (asserts! (< stacks-block-height grace-end) ERR_GRACE_PERIOD_EXPIRED)
    
    (try! (stx-transfer? required-fee tx-sender CONTRACT_OWNER))
    
    (let (
      (new-expiry (+ stacks-block-height validity-period))
      (updated-renewals (+ (get renewals-count renewal-data) u1))
      (renewal-record {renewal-height: stacks-block-height, paid-fee: required-fee, extended-to: new-expiry})
    )
      (map-set patent-renewal patent-id {
        expiry-height: new-expiry,
        renewals-count: updated-renewals,
        last-renewed: stacks-block-height
      })
      
      (map-set renewal-history patent-id 
        (unwrap! (as-max-len? (append current-history renewal-record) u10) ERR_TRANSFER_FAILED))
      
      (ok true)
    )
  )
)

(define-public (set-renewal-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> new-fee u0) ERR_INVALID_INPUT)
    (var-set base-renewal-fee new-fee)
    (ok true)
  )
)

(define-public (set-grace-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> new-period u0) ERR_INVALID_INPUT)
    (var-set grace-period new-period)
    (ok true)
  )
)

(define-public (set-default-validity-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> new-period u0) ERR_INVALID_RENEWAL_PERIOD)
    (var-set default-validity-period new-period)
    (ok true)
  )
)
