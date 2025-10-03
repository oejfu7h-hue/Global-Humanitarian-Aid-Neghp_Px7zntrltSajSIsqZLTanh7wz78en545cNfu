;; Aid Package Tracker Smart Contract
;; Tracks humanitarian aid packages from donation to delivery
;; Ensures transparency and accountability in aid distribution

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u1001))
(define-constant ERR-PACKAGE-NOT-FOUND (err u1002))
(define-constant ERR-INVALID-STATUS (err u1003))
(define-constant ERR-ALREADY-EXISTS (err u1004))
(define-constant ERR-INVALID-RECIPIENT (err u1005))
(define-constant ERR-INSUFFICIENT-QUANTITY (err u1006))

;; Package status constants
(define-constant STATUS-CREATED u0)
(define-constant STATUS-IN-TRANSIT u1)
(define-constant STATUS-DELIVERED u2)
(define-constant STATUS-VERIFIED u3)
(define-constant STATUS-DISTRIBUTED u4)

;; Aid package data structure
(define-map aid-packages
  { package-id: uint }
  {
    donor: principal,
    aid-type: (string-ascii 50),
    quantity: uint,
    unit: (string-ascii 20),
    destination: (string-ascii 100),
    recipient-org: principal,
    status: uint,
    created-height: uint,
    updated-height: uint,
    estimated-value: uint,
    tracking-hash: (buff 32),
    delivery-proof: (optional (string-ascii 200))
  }
)

;; Package delivery history
(define-map delivery-history
  { package-id: uint, checkpoint: uint }
  {
    location: (string-ascii 100),
    timestamp: uint,
    handler: principal,
    notes: (string-ascii 200)
  }
)

;; Recipient verification records
(define-map recipient-verifications
  { package-id: uint }
  {
    verifier: principal,
    verification-date: uint,
    beneficiaries-count: uint,
    verification-hash: (buff 32),
    impact-notes: (string-ascii 300)
  }
)

;; Package counters and stats
(define-data-var next-package-id uint u1)
(define-data-var total-packages uint u0)
(define-data-var total-delivered uint u0)
(define-data-var total-verified uint u0)

;; Authorized roles
(define-map authorized-handlers principal bool)
(define-map authorized-verifiers principal bool)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Authorization functions
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-authorized-handler)
  (default-to false (map-get? authorized-handlers tx-sender))
)

(define-private (is-authorized-verifier)
  (default-to false (map-get? authorized-verifiers tx-sender))
)

;; Admin functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-public (authorize-handler (handler principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (map-set authorized-handlers handler true)
    (ok true)
  )
)

(define-public (revoke-handler (handler principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (map-delete authorized-handlers handler)
    (ok true)
  )
)

(define-public (authorize-verifier (verifier principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (map-set authorized-verifiers verifier true)
    (ok true)
  )
)

(define-public (revoke-verifier (verifier principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (map-delete authorized-verifiers verifier)
    (ok true)
  )
)

;; Core package management functions
(define-public (register-aid-package
  (aid-type (string-ascii 50))
  (quantity uint)
  (unit (string-ascii 20))
  (destination (string-ascii 100))
  (recipient-org principal)
  (estimated-value uint)
  (tracking-hash (buff 32))
)
  (let (
    (package-id (var-get next-package-id))
  )
    (asserts! (> quantity u0) ERR-INSUFFICIENT-QUANTITY)
    (asserts! (> (len aid-type) u0) ERR-INVALID-STATUS)
    
    (map-set aid-packages
      { package-id: package-id }
      {
        donor: tx-sender,
        aid-type: aid-type,
        quantity: quantity,
        unit: unit,
        destination: destination,
        recipient-org: recipient-org,
        status: STATUS-CREATED,
        created-height: stacks-block-height,
        updated-height: stacks-block-height,
        estimated-value: estimated-value,
        tracking-hash: tracking-hash,
        delivery-proof: none
      }
    )
    
    ;; Update counters
    (var-set next-package-id (+ package-id u1))
    (var-set total-packages (+ (var-get total-packages) u1))
    
    ;; Record initial checkpoint
    (map-set delivery-history
      { package-id: package-id, checkpoint: u0 }
      {
        location: "Origin - Package Created",
        timestamp: stacks-block-height,
        handler: tx-sender,
        notes: "Aid package registered in system"
      }
    )
    
    (ok package-id)
  )
)

(define-public (update-package-status
  (package-id uint)
  (new-status uint)
  (location (string-ascii 100))
  (notes (string-ascii 200))
)
  (let (
    (package (unwrap! (map-get? aid-packages { package-id: package-id }) ERR-PACKAGE-NOT-FOUND))
    (current-status (get status package))
  )
    (asserts! (or (is-authorized-handler) (is-eq tx-sender (get donor package))) ERR-UNAUTHORIZED)
    (asserts! (<= new-status STATUS-DISTRIBUTED) ERR-INVALID-STATUS)
    (asserts! (> new-status current-status) ERR-INVALID-STATUS)
    
    ;; Update package status
    (map-set aid-packages
      { package-id: package-id }
      (merge package {
        status: new-status,
        updated-height: stacks-block-height
      })
    )
    
    ;; Record checkpoint
    (map-set delivery-history
      { package-id: package-id, checkpoint: new-status }
      {
        location: location,
        timestamp: stacks-block-height,
        handler: tx-sender,
        notes: notes
      }
    )
    
    ;; Update delivery counter if delivered
    (if (is-eq new-status STATUS-DELIVERED)
      (var-set total-delivered (+ (var-get total-delivered) u1))
      true
    )
    
    (ok true)
  )
)

(define-public (verify-delivery
  (package-id uint)
  (beneficiaries-count uint)
  (verification-hash (buff 32))
  (impact-notes (string-ascii 300))
  (delivery-proof (string-ascii 200))
)
  (let (
    (package (unwrap! (map-get? aid-packages { package-id: package-id }) ERR-PACKAGE-NOT-FOUND))
  )
    (asserts! (is-authorized-verifier) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status package) STATUS-DELIVERED) ERR-INVALID-STATUS)
    
    ;; Record verification
    (map-set recipient-verifications
      { package-id: package-id }
      {
        verifier: tx-sender,
        verification-date: stacks-block-height,
        beneficiaries-count: beneficiaries-count,
        verification-hash: verification-hash,
        impact-notes: impact-notes
      }
    )
    
    ;; Update package with verification
    (map-set aid-packages
      { package-id: package-id }
      (merge package {
        status: STATUS-VERIFIED,
        updated-height: stacks-block-height,
        delivery-proof: (some delivery-proof)
      })
    )
    
    ;; Update verification counter
    (var-set total-verified (+ (var-get total-verified) u1))
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-package-info (package-id uint))
  (map-get? aid-packages { package-id: package-id })
)

(define-read-only (get-delivery-history (package-id uint) (checkpoint uint))
  (map-get? delivery-history { package-id: package-id, checkpoint: checkpoint })
)

(define-read-only (get-verification-info (package-id uint))
  (map-get? recipient-verifications { package-id: package-id })
)

(define-read-only (get-system-stats)
  {
    total-packages: (var-get total-packages),
    total-delivered: (var-get total-delivered),
    total-verified: (var-get total-verified),
    next-package-id: (var-get next-package-id)
  }
)

(define-read-only (is-handler-authorized (handler principal))
  (default-to false (map-get? authorized-handlers handler))
)

(define-read-only (is-verifier-authorized (verifier principal))
  (default-to false (map-get? authorized-verifiers verifier))
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; title: aid-package-tracker
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

