;; event-access-manager
;; 
;; A flexible event access management contract that enables secure, fine-grained 
;; access control for event-related data and interactions.
;;
;; The contract provides a robust mechanism for managing event participation,
;; access permissions, and event-related data governance.

;; Error codes
(define-constant err-unauthorized u1)
(define-constant err-participant-already-registered u2)
(define-constant err-participant-not-registered u3)
(define-constant err-event-already-registered u4)
(define-constant err-event-not-registered u5)
(define-constant err-consumer-not-verified u6)
(define-constant err-consumer-already-verified u7)
(define-constant err-access-not-granted u8)
(define-constant err-invalid-event-type u9)
(define-constant err-invalid-expiry u10)

;; Event type constants
(define-constant event-type-conference "conference")
(define-constant event-type-workshop "workshop")
(define-constant event-type-seminar "seminar")
(define-constant event-type-webinar "webinar")
(define-constant event-type-networking "networking")
(define-constant event-type-training "training")
(define-constant event-type-summit "summit")

;; Data maps for event management

;; Stores registered participants
(define-map participants 
  { participant: principal } 
  { registered: bool, registration-time: uint }
)

;; Maps participants to their registered events
(define-map participant-events 
  { participant: principal, event-id: (string-ascii 64) } 
  { registered: bool, event-type: (string-ascii 64), registration-time: uint }
)

;; Stores verified event managers/organizers
(define-map verified-managers
  { manager: principal }
  { verified: bool, manager-type: (string-ascii 64), verification-time: uint }
)

;; Maps event access permissions
(define-map event-access-permissions
  { participant: principal, manager: principal, event-type: (string-ascii 64) }
  { granted: bool, expiry: (optional uint), grant-time: uint }
)

;; Tracks access history for audit purposes
(define-map access-history
  { access-id: uint }
  { 
    participant: principal, 
    manager: principal, 
    event-type: (string-ascii 64), 
    access-time: uint,
    purpose: (string-ascii 128)
  }
)

;; Counter for access history entries
(define-data-var access-history-counter uint u0)

;; Private helper functions

;; Validates if an event type is supported
(define-private (is-valid-event-type (event-type (string-ascii 64)))
  (or
    (is-eq event-type event-type-conference)
    (is-eq event-type event-type-workshop)
    (is-eq event-type event-type-seminar)
    (is-eq event-type event-type-webinar)
    (is-eq event-type event-type-networking)
    (is-eq event-type event-type-training)
    (is-eq event-type event-type-summit)
  )
)

;; Checks if participant exists
(define-private (is-participant-registered (participant principal))
  (default-to false (get registered (map-get? participants { participant: participant })))
)

;; Checks if event is registered for a participant
(define-private (is-event-registered (participant principal) (event-id (string-ascii 64)))
  (default-to false (get registered (map-get? participant-events { participant: participant, event-id: event-id })))
)

;; Checks if manager is verified
(define-private (is-manager-verified (manager principal))
  (default-to false (get verified (map-get? verified-managers { manager: manager })))
)

;; Checks if participant has granted access to manager for specific event type
(define-private (has-access (participant principal) (manager principal) (event-type (string-ascii 64)))
  (let ((permission (map-get? event-access-permissions { participant: participant, manager: manager, event-type: event-type })))
    (if (is-none permission)
      false
      (let ((permission-value (unwrap-panic permission)))
        (if (not (get granted permission-value))
          false
          (match (get expiry permission-value)
            expiry-time (< block-height expiry-time)
            true  ;; No expiry means permanent access
          )
        )
      )
    )
  )
)

;; Increments and returns the next access history ID
(define-private (next-access-id)
  (let ((current (var-get access-history-counter)))
    (var-set access-history-counter (+ current u1))
    current
  )
)

;; Record a data access event
(define-private (record-access (participant principal) (manager principal) (event-type (string-ascii 64)) (purpose (string-ascii 128)))
  (let ((access-id (next-access-id)))
    (map-set access-history
      { access-id: access-id }
      {
        participant: participant,
        manager: manager,
        event-type: event-type,
        access-time: block-height,
        purpose: purpose
      }
    )
    (ok access-id)
  )
)

;; Read-only functions

;; Check if a participant is registered
(define-read-only (check-participant-registration (participant principal))
  (ok (is-participant-registered participant))
)

;; Check if a manager is verified
(define-read-only (check-manager-verification (manager principal))
  (ok (is-manager-verified manager))
)

;; Check if manager has access to participant's event data
(define-read-only (check-event-access (participant principal) (manager principal) (event-type (string-ascii 64)))
  (ok (has-access participant manager event-type))
)

;; Get access details for audit
(define-read-only (get-access-details (access-id uint))
  (ok (map-get? access-history { access-id: access-id }))
)

;; Get access history for a participant
(define-read-only (get-participant-access-history (participant principal))
  ;; Simplified implementation: returns most recent access ID
  (ok (var-get access-history-counter))
)

;; Public functions

;; Register as a participant in the event management system
(define-public (register-participant)
  (let ((sender tx-sender))
    (asserts! (not (is-participant-registered sender)) (err err-participant-already-registered))
    
    (map-set participants
      { participant: sender }
      { registered: true, registration-time: block-height }
    )
    
    (ok true)
  )
)

;; Register an event for a participant
(define-public (register-event (event-id (string-ascii 64)) (event-type (string-ascii 64)))
  (let ((sender tx-sender))
    (asserts! (is-participant-registered sender) (err err-participant-not-registered))
    (asserts! (not (is-event-registered sender event-id)) (err err-event-already-registered))
    
    (map-set participant-events
      { participant: sender, event-id: event-id }
      { registered: true, event-type: event-type, registration-time: block-height }
    )
    
    (ok true)
  )
)

;; Remove an event for a participant
(define-public (remove-event (event-id (string-ascii 64)))
  (let ((sender tx-sender))
    (asserts! (is-participant-registered sender) (err err-participant-not-registered))
    (asserts! (is-event-registered sender event-id) (err err-event-not-registered))
    
    (map-set participant-events
      { participant: sender, event-id: event-id }
      { registered: false, event-type: "", registration-time: u0 }
    )
    
    (ok true)
  )
)

;; Register as a verified event manager (with simulated admin authorization)
(define-public (register-manager (manager principal) (manager-type (string-ascii 64)))
  (let ((sender tx-sender))
    ;; In a production environment, this would require administrative privileges
    (asserts! (is-eq sender (as-contract tx-sender)) (err err-unauthorized))
    (asserts! (not (is-manager-verified manager)) (err err-consumer-already-verified))
    
    (map-set verified-managers
      { manager: manager }
      { verified: true, manager-type: manager-type, verification-time: block-height }
    )
    
    (ok true)
  )
)

;; Grant event access to a verified manager
(define-public (grant-event-access 
  (manager principal) 
  (event-type (string-ascii 64)) 
  (expiry (optional uint)))
  (let ((sender tx-sender))
    (asserts! (is-participant-registered sender) (err err-participant-not-registered))
    (asserts! (is-manager-verified manager) (err err-consumer-not-verified))
    (asserts! (is-valid-event-type event-type) (err err-invalid-event-type))
    
    ;; If expiry is provided, ensure it's in the future
    (match expiry
      expiry-time (asserts! (> expiry-time block-height) (err err-invalid-expiry))
      true
    )
    
    (map-set event-access-permissions
      { participant: sender, manager: manager, event-type: event-type }
      { granted: true, expiry: expiry, grant-time: block-height }
    )
    
    (ok true)
  )
)

;; Revoke event access from a manager
(define-public (revoke-event-access (manager principal) (event-type (string-ascii 64)))
  (let ((sender tx-sender))
    (asserts! (is-participant-registered sender) (err err-participant-not-registered))
    (asserts! (is-valid-event-type event-type) (err err-invalid-event-type))
    
    (map-set event-access-permissions
      { participant: sender, manager: manager, event-type: event-type }
      { granted: false, expiry: none, grant-time: block-height }
    )
    
    (ok true)
  )
)