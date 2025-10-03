;; Crisis Severity Assessment Smart Contract
;; Evaluates humanitarian crisis severity and prioritizes aid distribution
;; Provides transparent, data-driven crisis response coordination

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u2001))
(define-constant ERR-CRISIS-NOT-FOUND (err u2002))
(define-constant ERR-INVALID-SEVERITY (err u2003))
(define-constant ERR-ALREADY-REPORTED (err u2004))
(define-constant ERR-INSUFFICIENT-DATA (err u2005))
(define-constant ERR-INVALID-COORDINATES (err u2006))

;; Crisis severity levels
(define-constant SEVERITY-MINIMAL u1)
(define-constant SEVERITY-MODERATE u2)
(define-constant SEVERITY-SEVERE u3)
(define-constant SEVERITY-CRITICAL u4)
(define-constant SEVERITY-CATASTROPHIC u5)

;; Crisis status constants
(define-constant STATUS-REPORTED u0)
(define-constant STATUS-ASSESSED u1)
(define-constant STATUS-ACTIVE u2)
(define-constant STATUS-RESPONDING u3)
(define-constant STATUS-RESOLVED u4)

;; Crisis categories
(define-constant CATEGORY-NATURAL-DISASTER u1)
(define-constant CATEGORY-CONFLICT u2)
(define-constant CATEGORY-EPIDEMIC u3)
(define-constant CATEGORY-FOOD-INSECURITY u4)
(define-constant CATEGORY-DISPLACEMENT u5)

;; Crisis data structure
(define-map crisis-reports
  { crisis-id: uint }
  {
    reporter: principal,
    location: (string-ascii 100),
    coordinates: { latitude: int, longitude: int },
    category: uint,
    severity-score: uint,
    affected-population: uint,
    description: (string-ascii 500),
    status: uint,
    priority-level: uint,
    response-teams: uint,
    created-height: uint,
    last-updated: uint,
    verified: bool,
    verification-hash: (optional (buff 32))
  }
)

;; Assessment criteria weights
(define-map assessment-criteria
  { criteria-id: uint }
  {
    name: (string-ascii 50),
    weight: uint,
    max-score: uint,
    description: (string-ascii 200)
  }
)

;; Crisis assessment scores
(define-map crisis-assessments
  { crisis-id: uint, criteria-id: uint }
  {
    score: uint,
    assessor: principal,
    assessment-date: uint,
    notes: (string-ascii 300)
  }
)

;; Response tracking
(define-map crisis-responses
  { crisis-id: uint, response-id: uint }
  {
    responder-org: principal,
    response-type: (string-ascii 50),
    resources-allocated: uint,
    start-date: uint,
    expected-duration: uint,
    status: uint
  }
)

;; Priority queue for crisis management
(define-map priority-queue
  { priority-rank: uint }
  {
    crisis-id: uint,
    severity-score: uint,
    urgency-factor: uint,
    last-updated: uint
  }
)

;; System variables
(define-data-var next-crisis-id uint u1)
(define-data-var next-response-id uint u1)
(define-data-var total-crises uint u0)
(define-data-var active-crises uint u0)
(define-data-var resolved-crises uint u0)

;; Authorized roles
(define-map authorized-assessors principal bool)
(define-map authorized-responders principal bool)
(define-map crisis-verifiers principal bool)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Authorization functions
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-authorized-assessor)
  (default-to false (map-get? authorized-assessors tx-sender))
)

(define-private (is-authorized-responder)
  (default-to false (map-get? authorized-responders tx-sender))
)

(define-private (is-crisis-verifier)
  (default-to false (map-get? crisis-verifiers tx-sender))
)

;; Admin functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-public (authorize-assessor (assessor principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (map-set authorized-assessors assessor true)
    (ok true)
  )
)

(define-public (authorize-responder (responder principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (map-set authorized-responders responder true)
    (ok true)
  )
)

(define-public (authorize-verifier (verifier principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (map-set crisis-verifiers verifier true)
    (ok true)
  )
)

;; Severity calculation helper
(define-private (calculate-urgency-factor (population uint) (category uint) (block-age uint))
  (let (
    (population-factor (if (> population u10000) u100 (/ (* population u10) u1000)))
    (category-multiplier (if (is-eq category CATEGORY-EPIDEMIC) u150
                          (if (is-eq category CATEGORY-NATURAL-DISASTER) u130
                            (if (is-eq category CATEGORY-CONFLICT) u120 u100))))
    (time-urgency (if (< block-age u144) u150  ;; Very recent (last day)
                   (if (< block-age u1008) u120  ;; Last week
                     (if (< block-age u4320) u100 u80))))  ;; Last month
  )
    (/ (* (* population-factor category-multiplier) time-urgency) u10000)
  )
)

;; Core crisis management functions
(define-public (report-crisis
  (location (string-ascii 100))
  (latitude int)
  (longitude int)
  (category uint)
  (affected-population uint)
  (description (string-ascii 500))
)
  (let (
    (crisis-id (var-get next-crisis-id))
    (initial-severity (if (<= category CATEGORY-DISPLACEMENT) SEVERITY-MODERATE SEVERITY-SEVERE))
  )
    (asserts! (and (>= latitude -90000000) (<= latitude 90000000)) ERR-INVALID-COORDINATES)
    (asserts! (and (>= longitude -180000000) (<= longitude 180000000)) ERR-INVALID-COORDINATES)
    (asserts! (and (>= category CATEGORY-NATURAL-DISASTER) (<= category CATEGORY-DISPLACEMENT)) ERR-INVALID-SEVERITY)
    (asserts! (> affected-population u0) ERR-INSUFFICIENT-DATA)
    
    (map-set crisis-reports
      { crisis-id: crisis-id }
      {
        reporter: tx-sender,
        location: location,
        coordinates: { latitude: latitude, longitude: longitude },
        category: category,
        severity-score: initial-severity,
        affected-population: affected-population,
        description: description,
        status: STATUS-REPORTED,
        priority-level: u0,
        response-teams: u0,
        created-height: stacks-block-height,
        last-updated: stacks-block-height,
        verified: false,
        verification-hash: none
      }
    )
    
    ;; Update counters
    (var-set next-crisis-id (+ crisis-id u1))
    (var-set total-crises (+ (var-get total-crises) u1))
    
    (ok crisis-id)
  )
)

(define-public (assess-severity
  (crisis-id uint)
  (criteria-scores (list 5 uint))
  (assessment-notes (string-ascii 300))
)
  (let (
    (crisis (unwrap! (map-get? crisis-reports { crisis-id: crisis-id }) ERR-CRISIS-NOT-FOUND))
    (total-score (fold + criteria-scores u0))
    (final-severity (if (<= total-score u10) SEVERITY-MINIMAL
                     (if (<= total-score u20) SEVERITY-MODERATE
                       (if (<= total-score u30) SEVERITY-SEVERE
                         (if (<= total-score u40) SEVERITY-CRITICAL
                           SEVERITY-CATASTROPHIC)))))
    (urgency (calculate-urgency-factor 
               (get affected-population crisis)
               (get category crisis)
               (- stacks-block-height (get created-height crisis))))
  )
    (asserts! (is-authorized-assessor) ERR-UNAUTHORIZED)
    (asserts! (<= (len criteria-scores) u5) ERR-INSUFFICIENT-DATA)
    
    ;; Update crisis with assessment
    (map-set crisis-reports
      { crisis-id: crisis-id }
      (merge crisis {
        severity-score: final-severity,
        status: STATUS-ASSESSED,
        last-updated: stacks-block-height,
        priority-level: (+ final-severity urgency)
      })
    )
    
    ;; Record detailed assessment
    (map-set crisis-assessments
      { crisis-id: crisis-id, criteria-id: u1 }
      {
        score: total-score,
        assessor: tx-sender,
        assessment-date: stacks-block-height,
        notes: assessment-notes
      }
    )
    
    ;; Update priority queue
    (let ((queue-result (update-priority-queue crisis-id final-severity urgency)))
      (ok final-severity)
    )
  )
)

(define-public (verify-crisis
  (crisis-id uint)
  (verification-hash (buff 32))
  (verified-population uint)
)
  (let (
    (crisis (unwrap! (map-get? crisis-reports { crisis-id: crisis-id }) ERR-CRISIS-NOT-FOUND))
  )
    (asserts! (is-crisis-verifier) ERR-UNAUTHORIZED)
    (asserts! (not (get verified crisis)) ERR-ALREADY-REPORTED)
    
    (map-set crisis-reports
      { crisis-id: crisis-id }
      (merge crisis {
        verified: true,
        verification-hash: (some verification-hash),
        affected-population: verified-population,
        last-updated: stacks-block-height
      })
    )
    
    (ok true)
  )
)

(define-public (initiate-response
  (crisis-id uint)
  (response-type (string-ascii 50))
  (resources-allocated uint)
  (expected-duration uint)
)
  (let (
    (crisis (unwrap! (map-get? crisis-reports { crisis-id: crisis-id }) ERR-CRISIS-NOT-FOUND))
    (response-id (var-get next-response-id))
  )
    (asserts! (is-authorized-responder) ERR-UNAUTHORIZED)
    (asserts! (>= (get status crisis) STATUS-ASSESSED) ERR-INSUFFICIENT-DATA)
    
    ;; Record response
    (map-set crisis-responses
      { crisis-id: crisis-id, response-id: response-id }
      {
        responder-org: tx-sender,
        response-type: response-type,
        resources-allocated: resources-allocated,
        start-date: stacks-block-height,
        expected-duration: expected-duration,
        status: u1
      }
    )
    
    ;; Update crisis status
    (map-set crisis-reports
      { crisis-id: crisis-id }
      (merge crisis {
        status: STATUS-RESPONDING,
        response-teams: (+ (get response-teams crisis) u1),
        last-updated: stacks-block-height
      })
    )
    
    ;; Update active crisis counter
    (if (is-eq (get status crisis) STATUS-ASSESSED)
      (var-set active-crises (+ (var-get active-crises) u1))
      true
    )
    
    (var-set next-response-id (+ response-id u1))
    (ok response-id)
  )
)

(define-public (update-crisis-status
  (crisis-id uint)
  (new-status uint)
  (progress-notes (string-ascii 300))
)
  (let (
    (crisis (unwrap! (map-get? crisis-reports { crisis-id: crisis-id }) ERR-CRISIS-NOT-FOUND))
  )
    (asserts! (or (is-authorized-responder) (is-eq tx-sender (get reporter crisis))) ERR-UNAUTHORIZED)
    (asserts! (<= new-status STATUS-RESOLVED) ERR-INVALID-SEVERITY)
    
    (map-set crisis-reports
      { crisis-id: crisis-id }
      (merge crisis {
        status: new-status,
        last-updated: stacks-block-height
      })
    )
    
    ;; Update resolved counter if crisis is resolved
    (if (is-eq new-status STATUS-RESOLVED)
      (begin
        (var-set resolved-crises (+ (var-get resolved-crises) u1))
        (var-set active-crises (- (var-get active-crises) u1))
      )
      true
    )
    
    (ok true)
  )
)

;; Priority queue management
(define-private (update-priority-queue (crisis-id uint) (severity uint) (urgency uint))
  (let (
    (priority-score (+ severity urgency))
  )
    ;; Simple priority insertion (in real implementation, would maintain sorted order)
    (map-set priority-queue
      { priority-rank: crisis-id }
      {
        crisis-id: crisis-id,
        severity-score: severity,
        urgency-factor: urgency,
        last-updated: stacks-block-height
      }
    )
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-crisis-info (crisis-id uint))
  (map-get? crisis-reports { crisis-id: crisis-id })
)

(define-read-only (get-crisis-assessment (crisis-id uint) (criteria-id uint))
  (map-get? crisis-assessments { crisis-id: crisis-id, criteria-id: criteria-id })
)

(define-read-only (get-crisis-response (crisis-id uint) (response-id uint))
  (map-get? crisis-responses { crisis-id: crisis-id, response-id: response-id })
)

(define-read-only (get-priority-info (priority-rank uint))
  (map-get? priority-queue { priority-rank: priority-rank })
)

(define-read-only (get-system-stats)
  {
    total-crises: (var-get total-crises),
    active-crises: (var-get active-crises),
    resolved-crises: (var-get resolved-crises),
    next-crisis-id: (var-get next-crisis-id)
  }
)

(define-read-only (is-assessor-authorized (assessor principal))
  (default-to false (map-get? authorized-assessors assessor))
)

(define-read-only (is-responder-authorized (responder principal))
  (default-to false (map-get? authorized-responders responder))
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)


