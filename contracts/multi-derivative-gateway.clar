(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_OWNER_ONLY (err u100))
(define-constant ERR_NOT_AUTHORIZED (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INSUFFICIENT_BALANCE (err u103))
(define-constant ERR_DEPOSIT_NOT_FOUND (err u104))
(define-constant ERR_ALREADY_MINTED (err u105))
(define-constant ERR_INVALID_ADDRESS (err u106))
(define-constant ERR_TOKEN_NOT_FOUND (err u107))
(define-constant ERR_PAUSED (err u108))
(define-constant ERR_INVALID_FEE (err u109))
(define-constant ERR_WITHDRAWAL_LOCKED (err u110))
(define-constant ERR_WITHDRAWAL_NOT_FOUND (err u111))
(define-constant MAX_FEE_BASIS_POINTS u1000)
(define-constant DEFAULT_TIMELOCK_BLOCKS u144)

(define-data-var contract-paused bool false)
(define-data-var next-deposit-id uint u1)
(define-data-var next-withdrawal-id uint u1)
(define-data-var withdrawal-fee-basis-points uint u50)
(define-data-var fee-recipient principal CONTRACT_OWNER)
(define-data-var withdrawal-timelock-blocks uint DEFAULT_TIMELOCK_BLOCKS)

(define-map deposits
  { deposit-id: uint }
  {
    eth-address: (buff 20),
    stx-recipient: principal,
    token-contract: (buff 20),
    amount: uint,
    block-height: uint,
    tx-hash: (buff 32),
    is-minted: bool,
    mint-tx-id: (optional uint)
  }
)

(define-map ethereum-deposits
  { tx-hash: (buff 32), token-contract: (buff 20) }
  { deposit-id: uint }
)

(define-map user-balances
  { user: principal, token-contract: (buff 20) }
  { balance: uint }
)

(define-map token-info
  { token-contract: (buff 20) }
  {
    name: (string-ascii 32),
    symbol: (string-ascii 10),
    decimals: uint,
    total-supply: uint,
    is-active: bool
  }
)

(define-map authorized-oracles principal bool)

(define-map collected-fees
  { token-contract: (buff 20) }
  { total-fees: uint }
)

(define-map withdrawal-queue
  { withdrawal-id: uint }
  {
    user: principal,
    token-contract: (buff 20),
    amount: uint,
    eth-recipient: (buff 20),
    request-block: uint,
    unlock-block: uint,
    is-cancelled: bool,
    is-finalized: bool
  }
)

(define-map user-withdrawals
  { user: principal, token-contract: (buff 20) }
  { withdrawal-ids: (list 100 uint) }
)

(define-public (register-token (token-contract (buff 20)) (name (string-ascii 32)) (symbol (string-ascii 10)) (decimals uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (map-set token-info
      { token-contract: token-contract }
      {
        name: name,
        symbol: symbol,
        decimals: decimals,
        total-supply: u0,
        is-active: true
      }
    ))
  )
)

(define-public (add-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (map-set authorized-oracles oracle true))
  )
)

(define-public (remove-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (map-delete authorized-oracles oracle))
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (var-set contract-paused true))
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (var-set contract-paused false))
  )
)

(define-public (set-withdrawal-fee (fee-basis-points uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (<= fee-basis-points MAX_FEE_BASIS_POINTS) ERR_INVALID_FEE)
    (ok (var-set withdrawal-fee-basis-points fee-basis-points))
  )
)

(define-public (set-fee-recipient (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (var-set fee-recipient recipient))
  )
)

(define-public (set-withdrawal-timelock (blocks uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (var-set withdrawal-timelock-blocks blocks))
  )
)

(define-public (withdraw-collected-fees (token-contract (buff 20)))
  (let (
    (fees-data (default-to { total-fees: u0 } (map-get? collected-fees { token-contract: token-contract })))
    (total-fees (get total-fees fees-data))
    (recipient (var-get fee-recipient))
    (recipient-balance (default-to u0 (get balance (map-get? user-balances { user: recipient, token-contract: token-contract }))))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (asserts! (> total-fees u0) ERR_INVALID_AMOUNT)
    
    (map-set user-balances
      { user: recipient, token-contract: token-contract }
      { balance: (+ recipient-balance total-fees) }
    )
    
    (map-set collected-fees
      { token-contract: token-contract }
      { total-fees: u0 }
    )
    
    (print { 
      action: "withdraw-fees",
      token-contract: token-contract,
      amount: total-fees,
      recipient: recipient
    })
    
    (ok total-fees)
  )
)

(define-public (record-deposit 
  (eth-address (buff 20))
  (stx-recipient principal)
  (token-contract (buff 20))
  (amount uint)
  (block-height uint)
  (tx-hash (buff 32))
)
  (let (
    (deposit-id (var-get next-deposit-id))
    (oracle-authorized (default-to false (map-get? authorized-oracles tx-sender)))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) oracle-authorized) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? ethereum-deposits { tx-hash: tx-hash, token-contract: token-contract })) ERR_ALREADY_MINTED)
    
    (map-set deposits
      { deposit-id: deposit-id }
      {
        eth-address: eth-address,
        stx-recipient: stx-recipient,
        token-contract: token-contract,
        amount: amount,
        block-height: block-height,
        tx-hash: tx-hash,
        is-minted: false,
        mint-tx-id: none
      }
    )
    
    (map-set ethereum-deposits
      { tx-hash: tx-hash, token-contract: token-contract }
      { deposit-id: deposit-id }
    )
    
    (var-set next-deposit-id (+ deposit-id u1))
    (ok deposit-id)
  )
)

(define-public (mint-derivative-token (deposit-id uint))
  (let (
    (deposit-info (unwrap! (map-get? deposits { deposit-id: deposit-id }) ERR_DEPOSIT_NOT_FOUND))
    (token-contract (get token-contract deposit-info))
    (amount (get amount deposit-info))
    (recipient (get stx-recipient deposit-info))
    (current-balance (default-to u0 (get balance (map-get? user-balances { user: recipient, token-contract: token-contract }))))
    (token-data (unwrap! (map-get? token-info { token-contract: token-contract }) ERR_TOKEN_NOT_FOUND))
    (oracle-authorized (default-to false (map-get? authorized-oracles tx-sender)))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) oracle-authorized) ERR_NOT_AUTHORIZED)
    (asserts! (not (get is-minted deposit-info)) ERR_ALREADY_MINTED)
    (asserts! (get is-active token-data) ERR_TOKEN_NOT_FOUND)
    
    (map-set user-balances
      { user: recipient, token-contract: token-contract }
      { balance: (+ current-balance amount) }
    )
    
    (map-set deposits
      { deposit-id: deposit-id }
      (merge deposit-info { is-minted: true, mint-tx-id: (some block-height) })
    )
    
    (map-set token-info
      { token-contract: token-contract }
      (merge token-data { total-supply: (+ (get total-supply token-data) amount) })
    )
    
    (print { 
      action: "mint",
      deposit-id: deposit-id,
      recipient: recipient,
      token-contract: token-contract,
      amount: amount
    })
    
    (ok true)
  )
)

(define-public (request-withdrawal (token-contract (buff 20)) (amount uint) (eth-recipient (buff 20)))
  (let (
    (user-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender, token-contract: token-contract }))))
    (token-data (unwrap! (map-get? token-info { token-contract: token-contract }) ERR_TOKEN_NOT_FOUND))
    (withdrawal-id (var-get next-withdrawal-id))
    (timelock-blocks (var-get withdrawal-timelock-blocks))
    (unlock-block (+ block-height timelock-blocks))
    (user-withdrawal-list (default-to (list) (get withdrawal-ids (map-get? user-withdrawals { user: tx-sender, token-contract: token-contract }))))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= user-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (get is-active token-data) ERR_TOKEN_NOT_FOUND)
    
    (map-set user-balances
      { user: tx-sender, token-contract: token-contract }
      { balance: (- user-balance amount) }
    )
    
    (map-set withdrawal-queue
      { withdrawal-id: withdrawal-id }
      {
        user: tx-sender,
        token-contract: token-contract,
        amount: amount,
        eth-recipient: eth-recipient,
        request-block: block-height,
        unlock-block: unlock-block,
        is-cancelled: false,
        is-finalized: false
      }
    )
    
    (map-set user-withdrawals
      { user: tx-sender, token-contract: token-contract }
      { withdrawal-ids: (unwrap-panic (as-max-len? (append user-withdrawal-list withdrawal-id) u100)) }
    )
    
    (var-set next-withdrawal-id (+ withdrawal-id u1))
    
    (print { 
      action: "withdrawal-requested",
      withdrawal-id: withdrawal-id,
      user: tx-sender,
      token-contract: token-contract,
      amount: amount,
      eth-recipient: eth-recipient,
      unlock-block: unlock-block
    })
    
    (ok withdrawal-id)
  )
)

(define-public (finalize-withdrawal (withdrawal-id uint))
  (let (
    (withdrawal-data (unwrap! (map-get? withdrawal-queue { withdrawal-id: withdrawal-id }) ERR_WITHDRAWAL_NOT_FOUND))
    (token-contract (get token-contract withdrawal-data))
    (amount (get amount withdrawal-data))
    (token-data (unwrap! (map-get? token-info { token-contract: token-contract }) ERR_TOKEN_NOT_FOUND))
    (fee-bps (var-get withdrawal-fee-basis-points))
    (fee-amount (/ (* amount fee-bps) u10000))
    (net-amount (- amount fee-amount))
    (current-fees (default-to u0 (get total-fees (map-get? collected-fees { token-contract: token-contract }))))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (is-eq tx-sender (get user withdrawal-data)) ERR_NOT_AUTHORIZED)
    (asserts! (not (get is-cancelled withdrawal-data)) ERR_WITHDRAWAL_NOT_FOUND)
    (asserts! (not (get is-finalized withdrawal-data)) ERR_ALREADY_MINTED)
    (asserts! (>= block-height (get unlock-block withdrawal-data)) ERR_WITHDRAWAL_LOCKED)
    
    (map-set collected-fees
      { token-contract: token-contract }
      { total-fees: (+ current-fees fee-amount) }
    )
    
    (map-set token-info
      { token-contract: token-contract }
      (merge token-data { total-supply: (- (get total-supply token-data) amount) })
    )
    
    (map-set withdrawal-queue
      { withdrawal-id: withdrawal-id }
      (merge withdrawal-data { is-finalized: true })
    )
    
    (print { 
      action: "withdrawal-finalized",
      withdrawal-id: withdrawal-id,
      user: tx-sender,
      token-contract: token-contract,
      amount: amount,
      fee-amount: fee-amount,
      net-amount: net-amount,
      eth-recipient: (get eth-recipient withdrawal-data)
    })
    
    (ok true)
  )
)

(define-public (cancel-withdrawal (withdrawal-id uint))
  (let (
    (withdrawal-data (unwrap! (map-get? withdrawal-queue { withdrawal-id: withdrawal-id }) ERR_WITHDRAWAL_NOT_FOUND))
    (token-contract (get token-contract withdrawal-data))
    (amount (get amount withdrawal-data))
    (user-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender, token-contract: token-contract }))))
  )
    (asserts! (is-eq tx-sender (get user withdrawal-data)) ERR_NOT_AUTHORIZED)
    (asserts! (not (get is-cancelled withdrawal-data)) ERR_WITHDRAWAL_NOT_FOUND)
    (asserts! (not (get is-finalized withdrawal-data)) ERR_ALREADY_MINTED)
    
    (map-set user-balances
      { user: tx-sender, token-contract: token-contract }
      { balance: (+ user-balance amount) }
    )
    
    (map-set withdrawal-queue
      { withdrawal-id: withdrawal-id }
      (merge withdrawal-data { is-cancelled: true })
    )
    
    (print { 
      action: "withdrawal-cancelled",
      withdrawal-id: withdrawal-id,
      user: tx-sender,
      token-contract: token-contract,
      amount: amount
    })
    
    (ok true)
  )
)

(define-public (burn-derivative-token (token-contract (buff 20)) (amount uint) (eth-recipient (buff 20)))
  (let (
    (user-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender, token-contract: token-contract }))))
    (token-data (unwrap! (map-get? token-info { token-contract: token-contract }) ERR_TOKEN_NOT_FOUND))
    (fee-bps (var-get withdrawal-fee-basis-points))
    (fee-amount (/ (* amount fee-bps) u10000))
    (net-amount (- amount fee-amount))
    (current-fees (default-to u0 (get total-fees (map-get? collected-fees { token-contract: token-contract }))))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= user-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (get is-active token-data) ERR_TOKEN_NOT_FOUND)
    
    (map-set user-balances
      { user: tx-sender, token-contract: token-contract }
      { balance: (- user-balance amount) }
    )
    
    (map-set collected-fees
      { token-contract: token-contract }
      { total-fees: (+ current-fees fee-amount) }
    )
    
    (map-set token-info
      { token-contract: token-contract }
      (merge token-data { total-supply: (- (get total-supply token-data) amount) })
    )
    
    (print { 
      action: "burn",
      user: tx-sender,
      token-contract: token-contract,
      amount: amount,
      fee-amount: fee-amount,
      net-amount: net-amount,
      eth-recipient: eth-recipient,
      burn-block: block-height
    })
    
    (ok true)
  )
)

(define-public (transfer (to principal) (token-contract (buff 20)) (amount uint))
  (let (
    (sender-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender, token-contract: token-contract }))))
    (recipient-balance (default-to u0 (get balance (map-get? user-balances { user: to, token-contract: token-contract }))))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
    
    (map-set user-balances
      { user: tx-sender, token-contract: token-contract }
      { balance: (- sender-balance amount) }
    )
    
    (map-set user-balances
      { user: to, token-contract: token-contract }
      { balance: (+ recipient-balance amount) }
    )
    
    (print { 
      action: "transfer",
      from: tx-sender,
      to: to,
      token-contract: token-contract,
      amount: amount
    })
    
    (ok true)
  )
)

(define-read-only (get-balance (user principal) (token-contract (buff 20)))
  (default-to u0 (get balance (map-get? user-balances { user: user, token-contract: token-contract })))
)

(define-read-only (get-deposit-info (deposit-id uint))
  (map-get? deposits { deposit-id: deposit-id })
)

(define-read-only (get-deposit-by-tx (tx-hash (buff 32)) (token-contract (buff 20)))
  (let (
    (deposit-lookup (map-get? ethereum-deposits { tx-hash: tx-hash, token-contract: token-contract }))
  )
    (match deposit-lookup
      lookup-data (map-get? deposits { deposit-id: (get deposit-id lookup-data) })
      none
    )
  )
)

(define-read-only (get-token-info (token-contract (buff 20)))
  (map-get? token-info { token-contract: token-contract })
)

(define-read-only (is-oracle-authorized (oracle principal))
  (default-to false (map-get? authorized-oracles oracle))
)

(define-read-only (get-withdrawal-fee)
  (var-get withdrawal-fee-basis-points)
)

(define-read-only (get-fee-recipient)
  (var-get fee-recipient)
)

(define-read-only (get-collected-fees (token-contract (buff 20)))
  (default-to u0 (get total-fees (map-get? collected-fees { token-contract: token-contract })))
)

(define-read-only (calculate-withdrawal-fee (amount uint))
  (let (
    (fee-bps (var-get withdrawal-fee-basis-points))
  )
    (/ (* amount fee-bps) u10000)
  )
)

(define-read-only (get-withdrawal-info (withdrawal-id uint))
  (map-get? withdrawal-queue { withdrawal-id: withdrawal-id })
)

(define-read-only (get-user-withdrawals (user principal) (token-contract (buff 20)))
  (default-to (list) (get withdrawal-ids (map-get? user-withdrawals { user: user, token-contract: token-contract })))
)

(define-read-only (get-withdrawal-timelock)
  (var-get withdrawal-timelock-blocks)
)

(define-read-only (get-contract-info)
  {
    owner: CONTRACT_OWNER,
    paused: (var-get contract-paused),
    next-deposit-id: (var-get next-deposit-id),
    next-withdrawal-id: (var-get next-withdrawal-id),
    withdrawal-fee-bps: (var-get withdrawal-fee-basis-points),
    fee-recipient: (var-get fee-recipient),
    withdrawal-timelock-blocks: (var-get withdrawal-timelock-blocks)
  }
)
