(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-ENOUGH-BALANCE (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INVALID-RECIPIENT (err u103))
(define-constant ERR-INSUFFICIENT-TAX (err u104))

(define-fungible-token dynamic-token)

(define-data-var token-name (string-ascii 32) "DynamicTax")
(define-data-var token-symbol (string-ascii 10) "DTAX")
(define-data-var token-decimals uint u6)
(define-data-var base-tax-rate uint u100)
(define-data-var max-tax-rate uint u1000)
(define-data-var volume-threshold uint u1000000)
(define-data-var tax-adjustment-factor uint u50)
(define-data-var treasury principal CONTRACT-OWNER)
(define-data-var current-block-volume uint u0)
(define-data-var last-volume-reset-block uint u0)
(define-data-var total-tax-collected uint u0)
(define-data-var volume-reset-interval uint u144)

(define-map user-balances principal uint)
(define-map transaction-history uint {sender: principal, recipient: principal, amount: uint, tax-paid: uint, block-height: uint})
(define-map daily-volume uint uint)



(define-read-only (get-token-name)
  (ok (var-get token-name)))

(define-read-only (get-token-symbol)
  (ok (var-get token-symbol)))

(define-read-only (get-decimals)
  (ok (var-get token-decimals)))

(define-read-only (get-balance (account principal))
  (ok (ft-get-balance dynamic-token account)))

(define-read-only (get-total-supply)
  (ok (ft-get-supply dynamic-token)))

(define-read-only (get-current-tax-rate)
  (let ((current-volume (var-get current-block-volume))
        (threshold (var-get volume-threshold))
        (base-rate (var-get base-tax-rate))
        (max-rate (var-get max-tax-rate))
        (adjustment (var-get tax-adjustment-factor)))
    (if (> current-volume threshold)
      (let ((volume-multiplier (/ (* current-volume adjustment) threshold)))
        (if (> (+ base-rate volume-multiplier) max-rate)
          (ok max-rate)
          (ok (+ base-rate volume-multiplier))))
      (ok base-rate))))

(define-read-only (get-treasury)
  (ok (var-get treasury)))

(define-read-only (get-total-tax-collected)
  (ok (var-get total-tax-collected)))

(define-read-only (get-current-volume)
  (ok (var-get current-block-volume)))

(define-read-only (calculate-tax (amount uint))
  (let ((tax-rate (unwrap-panic (get-current-tax-rate))))
    (ok (/ (* amount tax-rate) u10000))))

(define-private (should-reset-volume)
  (let ((current-block burn-block-height)
        (last-reset (var-get last-volume-reset-block))
        (interval (var-get volume-reset-interval)))
    (>= (- current-block last-reset) interval)))

(define-private (maybe-reset-volume)
  (if (should-reset-volume)
    (begin
      (var-set current-block-volume u0)
      (var-set last-volume-reset-block burn-block-height)
      true)
    false))

(define-private (update-volume (amount uint))
  (let ((current-volume (var-get current-block-volume)))
    (var-set current-block-volume (+ current-volume amount))))

(define-private (collect-tax (tax-amount uint))
  (let ((treasury-addr (var-get treasury))
        (current-collected (var-get total-tax-collected)))
    (begin
      (try! (ft-mint? dynamic-token tax-amount treasury-addr))
      (var-set total-tax-collected (+ current-collected tax-amount))
      (ok true))))

(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (ft-mint? dynamic-token amount recipient))
    (ok true)))

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (is-eq sender recipient)) ERR-INVALID-RECIPIENT)
    
    (maybe-reset-volume)
    
    (let ((tax-amount (unwrap-panic (calculate-tax amount))))
      (let ((total-deduction (+ amount tax-amount)))
        (asserts! (>= (ft-get-balance dynamic-token sender) total-deduction) ERR-NOT-ENOUGH-BALANCE)
        (try! (ft-transfer? dynamic-token amount sender recipient))
        (try! (ft-transfer? dynamic-token tax-amount sender (var-get treasury)))
        (update-volume amount)
        (var-set total-tax-collected (+ (var-get total-tax-collected) tax-amount))
        (ok true)))))

(define-public (transfer-with-tax (amount uint) (recipient principal))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (is-eq tx-sender recipient)) ERR-INVALID-RECIPIENT)
    
    (maybe-reset-volume)
    
    (let ((tax-amount (unwrap-panic (calculate-tax amount))))
      (let ((total-deduction (+ amount tax-amount)))
        (asserts! (>= (ft-get-balance dynamic-token tx-sender) total-deduction) ERR-NOT-ENOUGH-BALANCE)
        (try! (ft-transfer? dynamic-token amount tx-sender recipient))
        (try! (collect-tax tax-amount))
        (update-volume amount)
        (ok {amount: amount, tax-paid: tax-amount})))))

(define-public (burn (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (ft-burn? dynamic-token amount tx-sender))
    (ok true)))

(define-public (set-base-tax-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= new-rate (var-get max-tax-rate)) ERR-INVALID-AMOUNT)
    (var-set base-tax-rate new-rate)
    (ok true)))

(define-public (set-max-tax-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (>= new-rate (var-get base-tax-rate)) ERR-INVALID-AMOUNT)
    (var-set max-tax-rate new-rate)
    (ok true)))

(define-public (set-volume-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> new-threshold u0) ERR-INVALID-AMOUNT)
    (var-set volume-threshold new-threshold)
    (ok true)))

(define-public (set-tax-adjustment-factor (new-factor uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set tax-adjustment-factor new-factor)
    (ok true)))

(define-public (set-treasury (new-treasury principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set treasury new-treasury)
    (ok true)))

(define-public (set-volume-reset-interval (new-interval uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> new-interval u0) ERR-INVALID-AMOUNT)
    (var-set volume-reset-interval new-interval)
    (ok true)))

(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set max-tax-rate u10000)
    (ok true)))

(define-public (withdraw-treasury (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (ft-transfer? dynamic-token amount (var-get treasury) tx-sender))
    (ok true)))

(begin
  (try! (ft-mint? dynamic-token u1000000000000 CONTRACT-OWNER))
  (var-set last-volume-reset-block burn-block-height))
