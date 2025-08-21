(define-non-fungible-token patent-nft uint)

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_INPUT (err u400))
(define-constant ERR_TRANSFER_FAILED (err u500))

(define-data-var patent-counter uint u0)
(define-data-var contract-uri (optional (string-utf8 256)) none)

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
    (ok patent-id)
  )
)

(define-public (update-patent-status (patent-id uint) (new-status (string-utf8 20)))
  (let ((metadata (unwrap! (get-patent-metadata patent-id) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get inventor metadata)) ERR_NOT_AUTHORIZED)
    (asserts! (> (len new-status) u0) ERR_INVALID_INPUT)
    
    (map-set patent-metadata patent-id (merge metadata {patent-status: new-status}))
    (ok true)
  )
)

(define-public (transfer (patent-id uint) (sender principal) (recipient principal))
  (let ((owner (unwrap! (unwrap! (get-owner patent-id) ERR_NOT_FOUND) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq sender owner) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq sender recipient)) ERR_INVALID_INPUT)
    
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
    (expiry-height (+ stacks-block-height duration))
  )
    (asserts! (is-eq tx-sender (get inventor metadata)) ERR_NOT_AUTHORIZED)
    (asserts! (> (len terms) u0) ERR_INVALID_INPUT)
    (asserts! (> duration u0) ERR_INVALID_INPUT)
    
    (map-set patent-licensing patent-id {
      licensee: licensee,
      terms: terms,
      expiry: expiry-height,
      active: true
    })
    (ok true)
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
