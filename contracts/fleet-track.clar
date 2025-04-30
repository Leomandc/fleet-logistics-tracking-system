;; fleet-track
;; This contract manages the complete lifecycle of logistics fleet operations and tracking on the Stacks blockchain.
;; It provides functionality for registering vehicles and drivers, managing shipments, tracking locations,
;; confirming deliveries, and maintaining vehicles - all with appropriate permissions and verification.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-DOES-NOT-EXIST (err u102))
(define-constant ERR-VEHICLE-UNAVAILABLE (err u103))
(define-constant ERR-DRIVER-UNAVAILABLE (err u104))
(define-constant ERR-INVALID-SHIPMENT-STATE (err u105))
(define-constant ERR-INVALID-LOCATION (err u106))
(define-constant ERR-INVALID-DATE (err u107))
(define-constant ERR-VEHICLE-IN-USE (err u108))
(define-constant ERR-DRIVER-IN-USE (err u109))
(define-constant ERR-MAINTENANCE-REQUIRED (err u110))

;; Data structures

;; Role management
(define-map roles 
  { role-owner: principal }
  { is-admin: bool, is-fleet-manager: bool, is-driver: bool, is-maintenance: bool }
)

;; Vehicle records
(define-map vehicles 
  { vehicle-id: (string-utf8 50) } 
  {
    owner: principal,
    make: (string-utf8 50),
    model: (string-utf8 50),
    year: uint,
    vin: (string-utf8 50),
    status: (string-utf8 20), ;; "active", "maintenance", "retired"
    current-driver: (optional principal),
    last-maintenance-date: uint,
    total-miles: uint
  }
)

;; Driver records
(define-map drivers
  { driver-id: principal }
  {
    name: (string-utf8 100),
    license-number: (string-utf8 50),
    license-expiry: uint,
    status: (string-utf8 20), ;; "available", "on-duty", "off-duty"
    current-vehicle: (optional (string-utf8 50)),
    current-shipment: (optional uint)
  }
)

;; Shipment records
(define-map shipments
  { shipment-id: uint }
  {
    created-by: principal,
    vehicle-id: (string-utf8 50),
    driver-id: principal,
    origin: (string-utf8 100),
    destination: (string-utf8 100),
    cargo-description: (string-utf8 255),
    status: (string-utf8 20), ;; "scheduled", "in-transit", "delivered", "canceled"
    creation-date: uint,
    pickup-date: (optional uint),
    delivery-date: (optional uint),
    last-location: (optional (string-utf8 100))
  }
)

;; Location updates
(define-map location-updates
  { update-id: uint }
  {
    shipment-id: uint,
    vehicle-id: (string-utf8 50),
    driver-id: principal,
    location: (string-utf8 100),
    timestamp: uint,
    miles-added: uint
  }
)

;; Maintenance records
(define-map maintenance-records
  { record-id: uint }
  {
    vehicle-id: (string-utf8 50),
    technician: principal,
    maintenance-type: (string-utf8 50),
    description: (string-utf8 255),
    date: uint,
    next-maintenance-due: uint,
    odometer-reading: uint
  }
)

;; Counters for ID generation
(define-data-var next-shipment-id uint u1)
(define-data-var next-location-update-id uint u1)
(define-data-var next-maintenance-record-id uint u1)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Private Functions

;; Checks if caller has admin role
(define-private (is-admin (caller principal))
  (default-to false (get is-admin (map-get? roles { role-owner: caller })))
)

;; Checks if caller has fleet manager role
(define-private (is-fleet-manager (caller principal))
  (default-to false (get is-fleet-manager (map-get? roles { role-owner: caller })))
)

;; Checks if caller has driver role
(define-private (is-driver (caller principal))
  (default-to false (get is-driver (map-get? roles { role-owner: caller })))
)

;; Checks if caller has maintenance role
(define-private (is-maintenance (caller principal))
  (default-to false (get is-maintenance (map-get? roles { role-owner: caller })))
)

;; Checks if caller is the contract owner
(define-private (is-contract-owner (caller principal))
  (is-eq caller (var-get contract-owner))
)

;; Checks if caller can manage vehicles (admin or fleet manager)
(define-private (can-manage-vehicles (caller principal))
  (or (is-admin caller) (is-fleet-manager caller))
)

;; Checks if caller can manage drivers (admin or fleet manager)
(define-private (can-manage-drivers (caller principal))
  (or (is-admin caller) (is-fleet-manager caller))
)

;; Checks if caller can manage shipments (admin or fleet manager)
(define-private (can-manage-shipments (caller principal))
  (or (is-admin caller) (is-fleet-manager caller))
)

;; Checks if vehicle needs maintenance based on miles or time
(define-private (needs-maintenance (vehicle-id (string-utf8 50)))
  (let (
    (vehicle (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) false))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) u0))
    (maintenance-interval (* u90 u86400)) ;; 90 days in seconds
    (miles-interval u5000) ;; 5000 miles between maintenance
  )
    (or 
      (> (get total-miles vehicle) (+ miles-interval (get last-maintenance-date vehicle)))
      (> current-time (+ (get last-maintenance-date vehicle) maintenance-interval))
    )
  )
)

;; Read-only Functions

;; Get vehicle details
(define-read-only (get-vehicle (vehicle-id (string-utf8 50)))
  (map-get? vehicles { vehicle-id: vehicle-id })
)

;; Get driver details
(define-read-only (get-driver (driver-id principal))
  (map-get? drivers { driver-id: driver-id })
)

;; Get shipment details
(define-read-only (get-shipment (shipment-id uint))
  (map-get? shipments { shipment-id: shipment-id })
)

;; Get maintenance record
(define-read-only (get-maintenance-record (record-id uint))
  (map-get? maintenance-records { record-id: record-id })
)

;; Get location update
(define-read-only (get-location-update (update-id uint))
  (map-get? location-updates { update-id: update-id })
)

;; Check if vehicle is available
(define-read-only (is-vehicle-available (vehicle-id (string-utf8 50)))
  (let ((vehicle (map-get? vehicles { vehicle-id: vehicle-id })))
    (and 
      (is-some vehicle)
      (is-eq (get status (unwrap! vehicle false)) "active")
      (is-none (get current-driver (unwrap! vehicle false)))
    )
  )
)

;; Check if driver is available
(define-read-only (is-driver-available (driver-id principal))
  (let ((driver (map-get? drivers { driver-id: driver-id })))
    (and 
      (is-some driver)
      (is-eq (get status (unwrap! driver false)) "available")
      (is-none (get current-vehicle (unwrap! driver false)))
      (is-none (get current-shipment (unwrap! driver false)))
    )
  )
)

;; Public Functions

;; Role Management

;; Set contract owner - can only be called by current owner
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)

;; Set role for a principal - can only be called by contract owner or admin
(define-public (set-role (user principal) (admin bool) (fleet-manager bool) (driver-role bool) (maintenance-role bool))
  (begin
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) (is-admin tx-sender)) ERR-NOT-AUTHORIZED)
    (ok (map-set roles 
      { role-owner: user }
      { 
        is-admin: admin,
        is-fleet-manager: fleet-manager,
        is-driver: driver-role,
        is-maintenance: maintenance-role
      }
    ))
  )
)

;; Vehicle Management

;; Register a new vehicle
(define-public (register-vehicle 
  (vehicle-id (string-utf8 50))
  (make (string-utf8 50))
  (model (string-utf8 50))
  (year uint)
  (vin (string-utf8 50))
)
  (begin
    (asserts! (can-manage-vehicles tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? vehicles { vehicle-id: vehicle-id })) ERR-ALREADY-EXISTS)
    
    (let ((current-time (unwrap! (get-block-info? time (- block-height u1)) u0)))
      (ok (map-set vehicles
        { vehicle-id: vehicle-id }
        {
          owner: tx-sender,
          make: make,
          model: model,
          year: year,
          vin: vin,
          status: "active",
          current-driver: none,
          last-maintenance-date: current-time,
          total-miles: u0
        }
      ))
    )
  )
)

;; Update vehicle status
(define-public (update-vehicle-status 
  (vehicle-id (string-utf8 50))
  (new-status (string-utf8 20))
)
  (begin
    (asserts! (can-manage-vehicles tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? vehicles { vehicle-id: vehicle-id })) ERR-DOES-NOT-EXIST)
    
    (let (
      (vehicle (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-DOES-NOT-EXIST))
      (valid-status (or (is-eq new-status "active") (is-eq new-status "maintenance") (is-eq new-status "retired")))
    )
      (asserts! valid-status ERR-INVALID-SHIPMENT-STATE)
      (asserts! (or (is-eq new-status "active") (is-none (get current-driver vehicle))) ERR-VEHICLE-IN-USE)
      
      (ok (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge vehicle { status: new-status })
      ))
    )
  )
)

;; Driver Management

;; Register a new driver
(define-public (register-driver
  (driver-id principal)
  (name (string-utf8 100))
  (license-number (string-utf8 50))
  (license-expiry uint)
)
  (begin
    (asserts! (can-manage-drivers tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? drivers { driver-id: driver-id })) ERR-ALREADY-EXISTS)
    
    (ok (map-set drivers
      { driver-id: driver-id }
      {
        name: name,
        license-number: license-number,
        license-expiry: license-expiry,
        status: "available",
        current-vehicle: none,
        current-shipment: none
      }
    ))
  )
)

;; Update driver status
(define-public (update-driver-status
  (driver-id principal)
  (new-status (string-utf8 20))
)
  (begin
    (asserts! (or (can-manage-drivers tx-sender) (is-eq tx-sender driver-id)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? drivers { driver-id: driver-id })) ERR-DOES-NOT-EXIST)
    
    (let (
      (driver (unwrap! (map-get? drivers { driver-id: driver-id }) ERR-DOES-NOT-EXIST))
      (valid-status (or (is-eq new-status "available") (is-eq new-status "on-duty") (is-eq new-status "off-duty")))
    )
      (asserts! valid-status ERR-INVALID-SHIPMENT-STATE)
      (asserts! (or (is-eq new-status "on-duty") (is-none (get current-shipment driver))) ERR-DRIVER-IN-USE)
      
      (ok (map-set drivers
        { driver-id: driver-id }
        (merge driver { status: new-status })
      ))
    )
  )
)

;; Shipment Management

;; Create a new shipment
(define-public (create-shipment
  (vehicle-id (string-utf8 50))
  (driver-id principal)
  (origin (string-utf8 100))
  (destination (string-utf8 100))
  (cargo-description (string-utf8 255))
)
  (let (
    (shipment-id (var-get next-shipment-id))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) u0))
  )
    (asserts! (can-manage-shipments tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? vehicles { vehicle-id: vehicle-id })) ERR-DOES-NOT-EXIST)
    (asserts! (is-some (map-get? drivers { driver-id: driver-id })) ERR-DOES-NOT-EXIST)
    (asserts! (is-vehicle-available vehicle-id) ERR-VEHICLE-UNAVAILABLE)
    (asserts! (is-driver-available driver-id) ERR-DRIVER-UNAVAILABLE)
    (asserts! (not (needs-maintenance vehicle-id)) ERR-MAINTENANCE-REQUIRED)
    
    ;; Update vehicle and driver status
    (let (
      (vehicle (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-DOES-NOT-EXIST))
      (driver (unwrap! (map-get? drivers { driver-id: driver-id }) ERR-DOES-NOT-EXIST))
    )
      ;; Create the shipment
      (map-set shipments 
        { shipment-id: shipment-id }
        {
          created-by: tx-sender,
          vehicle-id: vehicle-id,
          driver-id: driver-id,
          origin: origin,
          destination: destination,
          cargo-description: cargo-description,
          status: "scheduled",
          creation-date: current-time,
          pickup-date: none,
          delivery-date: none,
          last-location: none
        }
      )
      
      ;; Update vehicle status
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge vehicle { 
          current-driver: (some driver-id),
          status: "active"
        })
      )
      
      ;; Update driver status
      (map-set drivers
        { driver-id: driver-id }
        (merge driver {
          status: "on-duty",
          current-vehicle: (some vehicle-id),
          current-shipment: (some shipment-id)
        })
      )
      
      ;; Increment shipment counter
      (var-set next-shipment-id (+ shipment-id u1))
      
      (ok shipment-id)
    )
  )
)

;; Start shipment (pickup)
(define-public (start-shipment
  (shipment-id uint)
)
  (let (
    (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR-DOES-NOT-EXIST))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) u0))
  )
    (asserts! (or (can-manage-shipments tx-sender) (is-eq tx-sender (get driver-id shipment))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status shipment) "scheduled") ERR-INVALID-SHIPMENT-STATE)
    
    (ok (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment {
        status: "in-transit",
        pickup-date: (some current-time),
        last-location: (some (get origin shipment))
      })
    ))
  )
)

;; Update shipment location
(define-public (update-location
  (shipment-id uint)
  (location (string-utf8 100))
  (miles-added uint)
)
  (let (
    (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR-DOES-NOT-EXIST))
    (driver-id (get driver-id shipment))
    (vehicle-id (get vehicle-id shipment))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) u0))
    (update-id (var-get next-location-update-id))
  )
    (asserts! (or (can-manage-shipments tx-sender) (is-eq tx-sender driver-id)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status shipment) "in-transit") ERR-INVALID-SHIPMENT-STATE)
    
    ;; Record location update
    (map-set location-updates
      { update-id: update-id }
      {
        shipment-id: shipment-id,
        vehicle-id: vehicle-id,
        driver-id: driver-id,
        location: location,
        timestamp: current-time,
        miles-added: miles-added
      }
    )
    
    ;; Update vehicle mileage
    (let ((vehicle (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-DOES-NOT-EXIST)))
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge vehicle {
          total-miles: (+ (get total-miles vehicle) miles-added)
        })
      )
    )
    
    ;; Update shipment location
    (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment {
        last-location: (some location)
      })
    )
    
    ;; Increment location update counter
    (var-set next-location-update-id (+ update-id u1))
    
    (ok update-id)
  )
)

;; Complete shipment (delivery)
(define-public (complete-shipment
  (shipment-id uint)
)
  (let (
    (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR-DOES-NOT-EXIST))
    (driver-id (get driver-id shipment))
    (vehicle-id (get vehicle-id shipment))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) u0))
  )
    (asserts! (or (can-manage-shipments tx-sender) (is-eq tx-sender driver-id)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status shipment) "in-transit") ERR-INVALID-SHIPMENT-STATE)
    
    ;; Update shipment status
    (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment {
        status: "delivered",
        delivery-date: (some current-time),
        last-location: (some (get destination shipment))
      })
    )
    
    ;; Free up the vehicle
    (let ((vehicle (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-DOES-NOT-EXIST)))
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge vehicle {
          current-driver: none,
          status: "active"
        })
      )
    )
    
    ;; Free up the driver
    (let ((driver (unwrap! (map-get? drivers { driver-id: driver-id }) ERR-DOES-NOT-EXIST)))
      (map-set drivers
        { driver-id: driver-id }
        (merge driver {
          status: "available",
          current-vehicle: none,
          current-shipment: none
        })
      )
    )
    
    (ok shipment-id)
  )
)

;; Cancel shipment
(define-public (cancel-shipment
  (shipment-id uint)
)
  (let (
    (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) ERR-DOES-NOT-EXIST))
    (driver-id (get driver-id shipment))
    (vehicle-id (get vehicle-id shipment))
  )
    (asserts! (can-manage-shipments tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq (get status shipment) "scheduled") (is-eq (get status shipment) "in-transit")) ERR-INVALID-SHIPMENT-STATE)
    
    ;; Update shipment status
    (map-set shipments
      { shipment-id: shipment-id }
      (merge shipment {
        status: "canceled"
      })
    )
    
    ;; Free up the vehicle
    (let ((vehicle (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-DOES-NOT-EXIST)))
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge vehicle {
          current-driver: none,
          status: "active"
        })
      )
    )
    
    ;; Free up the driver
    (let ((driver (unwrap! (map-get? drivers { driver-id: driver-id }) ERR-DOES-NOT-EXIST)))
      (map-set drivers
        { driver-id: driver-id }
        (merge driver {
          status: "available",
          current-vehicle: none,
          current-shipment: none
        })
      )
    )
    
    (ok shipment-id)
  )
)

;; Maintenance Management

;; Record vehicle maintenance
(define-public (record-maintenance
  (vehicle-id (string-utf8 50))
  (maintenance-type (string-utf8 50))
  (description (string-utf8 255))
  (next-maintenance-due uint)
  (odometer-reading uint)
)
  (let (
    (record-id (var-get next-maintenance-record-id))
    (current-time (unwrap! (get-block-info? time (- block-height u1)) u0))
  )
    (asserts! (or (is-maintenance tx-sender) (can-manage-vehicles tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? vehicles { vehicle-id: vehicle-id })) ERR-DOES-NOT-EXIST)
    
    (let ((vehicle (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-DOES-NOT-EXIST)))
      ;; Record maintenance
      (map-set maintenance-records
        { record-id: record-id }
        {
          vehicle-id: vehicle-id,
          technician: tx-sender,
          maintenance-type: maintenance-type,
          description: description,
          date: current-time,
          next-maintenance-due: next-maintenance-due,
          odometer-reading: odometer-reading
        }
      )
      
      ;; Update vehicle maintenance record
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge vehicle {
          last-maintenance-date: current-time,
          total-miles: odometer-reading,
          status: "active"
        })
      )
      
      ;; Increment maintenance record counter
      (var-set next-maintenance-record-id (+ record-id u1))
      
      (ok record-id)
    )
  )
)

;; Schedule maintenance for a vehicle
(define-public (schedule-maintenance
  (vehicle-id (string-utf8 50))
)
  (begin
    (asserts! (or (is-maintenance tx-sender) (can-manage-vehicles tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? vehicles { vehicle-id: vehicle-id })) ERR-DOES-NOT-EXIST)
    
    (let ((vehicle (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-DOES-NOT-EXIST)))
      (asserts! (is-none (get current-driver vehicle)) ERR-VEHICLE-IN-USE)
      
      (ok (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge vehicle {
          status: "maintenance"
        })
      ))
    )
  )
)