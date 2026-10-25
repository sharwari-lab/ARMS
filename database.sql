-- Airline Management System: schema + sample data
-- Paste this whole file into the Neon SQL Editor and click Run (only once).
SET TIME ZONE 'Asia/Kolkata';

-- ========== SCHEMA ==========
CREATE TABLE users (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  full_name VARCHAR(120) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role VARCHAR(40) NOT NULL CHECK (role IN ('Admin', 'Airline Staff', 'Passenger')),
  city VARCHAR(80) NOT NULL,
  created_at TIMESTAMPTZ(0) NOT NULL DEFAULT NOW()
);

CREATE TABLE airports (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  iata_code CHAR(3) NOT NULL UNIQUE,
  airport_name VARCHAR(150) NOT NULL,
  city VARCHAR(80) NOT NULL,
  state VARCHAR(80) NOT NULL
);

CREATE TABLE aircraft (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  registration_no VARCHAR(10) NOT NULL UNIQUE,
  manufacturer VARCHAR(60) NOT NULL,
  model VARCHAR(60) NOT NULL,
  total_seats SMALLINT NOT NULL CHECK (total_seats > 0),
  status VARCHAR(20) NOT NULL DEFAULT 'Active'
    CHECK (status IN ('Active', 'Maintenance', 'Retired'))
);

CREATE TABLE flights (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  flight_number VARCHAR(10) NOT NULL UNIQUE,
  origin_airport_id BIGINT NOT NULL REFERENCES airports(id) ON DELETE RESTRICT,
  dest_airport_id BIGINT NOT NULL REFERENCES airports(id) ON DELETE RESTRICT,
  departure_time TIME NOT NULL,
  arrival_time TIME NOT NULL,
  duration_min SMALLINT NOT NULL CHECK (duration_min > 0),
  base_fare NUMERIC(10,2) NOT NULL CHECK (base_fare > 0),
  status VARCHAR(20) NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Suspended')),
  CHECK (origin_airport_id <> dest_airport_id)
);

CREATE TABLE flight_schedules (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  flight_id BIGINT NOT NULL REFERENCES flights(id) ON DELETE CASCADE,
  aircraft_id BIGINT NOT NULL REFERENCES aircraft(id) ON DELETE RESTRICT,
  flight_date DATE NOT NULL,
  gate VARCHAR(5),
  status VARCHAR(20) NOT NULL DEFAULT 'Scheduled'
    CHECK (status IN ('Scheduled', 'Boarding', 'Departed', 'Arrived', 'Delayed', 'Cancelled')),
  UNIQUE (flight_id, flight_date)
);

CREATE TABLE passengers (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  full_name VARCHAR(120) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  phone VARCHAR(15) NOT NULL UNIQUE,
  id_proof_no VARCHAR(20) NOT NULL UNIQUE,
  date_of_birth DATE NOT NULL,
  gender CHAR(1) NOT NULL CHECK (gender IN ('M', 'F', 'O'))
);

CREATE TABLE bookings (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pnr VARCHAR(10) NOT NULL UNIQUE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  schedule_id BIGINT NOT NULL REFERENCES flight_schedules(id) ON DELETE RESTRICT,
  travel_class VARCHAR(20) NOT NULL
    CHECK (travel_class IN ('Economy', 'Premium Economy', 'Business')),
  passenger_count SMALLINT NOT NULL CHECK (passenger_count BETWEEN 1 AND 9),
  total_fare NUMERIC(12,2) NOT NULL CHECK (total_fare >= 0),
  status VARCHAR(20) NOT NULL DEFAULT 'Confirmed'
    CHECK (status IN ('Confirmed', 'Pending', 'Cancelled')),
  booking_date TIMESTAMPTZ(0) NOT NULL DEFAULT NOW()
);

CREATE TABLE tickets (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ticket_no VARCHAR(15) NOT NULL UNIQUE,
  booking_id BIGINT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  passenger_id BIGINT NOT NULL REFERENCES passengers(id) ON DELETE RESTRICT,
  seat_no VARCHAR(4) NOT NULL,
  meal_pref VARCHAR(10) NOT NULL DEFAULT 'None' CHECK (meal_pref IN ('Veg', 'Non-Veg', 'Jain', 'None')),
  status VARCHAR(15) NOT NULL DEFAULT 'Issued' CHECK (status IN ('Issued', 'Pending', 'Cancelled')),
  UNIQUE (booking_id, passenger_id)
);

CREATE TABLE crew_members (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employee_code VARCHAR(10) NOT NULL UNIQUE,
  full_name VARCHAR(120) NOT NULL,
  crew_role VARCHAR(20) NOT NULL CHECK (crew_role IN ('Captain', 'First Officer', 'Cabin Crew')),
  base_airport_id BIGINT NOT NULL REFERENCES airports(id) ON DELETE RESTRICT,
  license_no VARCHAR(20) UNIQUE,
  status VARCHAR(15) NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'On Leave')),
  CHECK (crew_role = 'Cabin Crew' OR license_no IS NOT NULL)
);

CREATE TABLE crew_assignments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  schedule_id BIGINT NOT NULL REFERENCES flight_schedules(id) ON DELETE CASCADE,
  crew_id BIGINT NOT NULL REFERENCES crew_members(id) ON DELETE RESTRICT,
  duty VARCHAR(15) NOT NULL CHECK (duty IN ('Pilot', 'Co-Pilot', 'Lead Cabin', 'Cabin')),
  UNIQUE (schedule_id, crew_id)
);

CREATE TABLE payments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  transaction_ref VARCHAR(20) NOT NULL UNIQUE,
  booking_id BIGINT NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  payment_method VARCHAR(20) NOT NULL
    CHECK (payment_method IN ('UPI', 'Credit Card', 'Debit Card', 'Net Banking')),
  status VARCHAR(12) NOT NULL CHECK (status IN ('Successful', 'Pending', 'Failed', 'Refunded')),
  created_at TIMESTAMPTZ(0) NOT NULL DEFAULT NOW()
);

-- A schedule can have only one Pilot (partial unique index)
CREATE UNIQUE INDEX uq_one_pilot_per_flight ON crew_assignments(schedule_id) WHERE duty = 'Pilot';
CREATE INDEX idx_flights_route ON flights(origin_airport_id, dest_airport_id);
CREATE INDEX idx_schedules_date ON flight_schedules(flight_date);
CREATE INDEX idx_bookings_schedule ON bookings(schedule_id);
CREATE INDEX idx_bookings_user ON bookings(user_id);
CREATE INDEX idx_tickets_passenger ON tickets(passenger_id);
CREATE INDEX idx_crew_assign_crew ON crew_assignments(crew_id);
CREATE INDEX idx_payments_booking ON payments(booking_id);

-- ========== SAMPLE DATA ==========
INSERT INTO users (full_name, email, password_hash, role, city, created_at) VALUES
('Sharwari Lohakare', 'sharwari@skyway.local', 'hash_demo', 'Admin', 'Nagpur', '2026-10-15 10:00:00'),
('Rahul Kher', 'rahul.kher@skyway.local', 'hash_demo', 'Airline Staff', 'Mumbai', '2026-10-15 10:05:00'),
('Priya Nair', 'priya.nair@local', 'hash_demo', 'Passenger', 'Nagpur', '2026-10-15 10:10:00'),
('Aditya Kulkarni', 'aditya.k@local', 'hash_demo', 'Passenger', 'Mumbai', '2026-10-15 10:15:00'),
('Sameer Shaikh', 'sameer.s@local', 'hash_demo', 'Passenger', 'Delhi', '2026-10-15 10:20:00'),
('Neha Agrawal', 'neha.a@local', 'hash_demo', 'Passenger', 'Hyderabad', '2026-10-15 10:25:00'),
('Varun Bhatt', 'varun.b@local', 'hash_demo', 'Passenger', 'Pune', '2026-10-15 10:30:00'),
('Kavya Reddy', 'kavya.r@local', 'hash_demo', 'Passenger', 'Mumbai', '2026-10-15 10:35:00'),
('Harsh Vora', 'harsh.v@local', 'hash_demo', 'Passenger', 'Kolkata', '2026-10-15 10:40:00'),
('Isha Tiwari', 'isha.t@local', 'hash_demo', 'Passenger', 'Delhi', '2026-10-15 10:45:00');

INSERT INTO airports (iata_code, airport_name, city, state) VALUES
('DEL', 'Indira Gandhi International Airport', 'New Delhi', 'Delhi'),
('BOM', 'Chhatrapati Shivaji Maharaj International Airport', 'Mumbai', 'Maharashtra'),
('BLR', 'Kempegowda International Airport', 'Bengaluru', 'Karnataka'),
('MAA', 'Chennai International Airport', 'Chennai', 'Tamil Nadu'),
('CCU', 'Netaji Subhas Chandra Bose International Airport', 'Kolkata', 'West Bengal'),
('HYD', 'Rajiv Gandhi International Airport', 'Hyderabad', 'Telangana'),
('NAG', 'Dr. Babasaheb Ambedkar International Airport', 'Nagpur', 'Maharashtra'),
('PNQ', 'Pune Airport', 'Pune', 'Maharashtra'),
('GOI', 'Goa International Airport', 'Goa', 'Goa'),
('COK', 'Cochin International Airport', 'Kochi', 'Kerala');

INSERT INTO aircraft (registration_no, manufacturer, model, total_seats, status) VALUES
('VT-SWA', 'Airbus', 'A320neo', 180, 'Active'),
('VT-SWB', 'Airbus', 'A320neo', 180, 'Active'),
('VT-SWC', 'Boeing', '737-800', 189, 'Active'),
('VT-SWD', 'Airbus', 'A321neo', 222, 'Active'),
('VT-SWE', 'ATR', '72-600', 70, 'Active'),
('VT-SWF', 'Boeing', '737-800', 189, 'Maintenance');

INSERT INTO flights (flight_number, origin_airport_id, dest_airport_id, departure_time, arrival_time, duration_min, base_fare, status) VALUES
('SW-101', 7, 1, '06:10', '07:55', 105, 4800.00, 'Active'),
('SW-102', 1, 7, '09:00', '10:45', 105, 4800.00, 'Active'),
('SW-201', 2, 3, '07:30', '09:15', 105, 5200.00, 'Active'),
('SW-202', 3, 2, '18:40', '20:25', 105, 5200.00, 'Active'),
('SW-301', 1, 5, '11:15', '13:30', 135, 6100.00, 'Active'),
('SW-401', 6, 4, '14:20', '15:30', 70, 3200.00, 'Active'),
('SW-501', 8, 9, '16:00', '17:00', 60, 2900.00, 'Active'),
('SW-601', 2, 10, '12:10', '14:10', 120, 5600.00, 'Active'),
('SW-701', 5, 2, '20:15', '23:05', 170, 7400.00, 'Active'),
('SW-801', 7, 2, '19:30', '21:00', 90, 4100.00, 'Active');

INSERT INTO flight_schedules (flight_id, aircraft_id, flight_date, gate, status) VALUES
(1, 1, '2026-11-05', 'A2', 'Scheduled'),
(2, 1, '2026-11-05', '14', 'Scheduled'),
(3, 3, '2026-11-05', 'C31', 'Scheduled'),
(4, 3, '2026-11-05', 'B7', 'Scheduled'),
(5, 4, '2026-11-05', '22', 'Scheduled'),
(6, 2, '2026-11-05', '9', 'Scheduled'),
(7, 5, '2026-11-05', '3', 'Scheduled'),
(8, 2, '2026-11-06', 'C40', 'Delayed'),
(9, 4, '2026-11-06', '11', 'Scheduled'),
(10, 1, '2026-11-06', 'A1', 'Scheduled'),
(1, 1, '2026-11-06', 'A2', 'Scheduled'),
(5, 4, '2026-11-06', NULL, 'Cancelled');

INSERT INTO passengers (full_name, email, phone, id_proof_no, date_of_birth, gender) VALUES
('Priya Nair', 'priya.nair@local', '9822010001', 'IDP-480011', '1998-04-12', 'F'),
('Aditya Kulkarni', 'aditya.k@local', '9822010002', 'IDP-480012', '1995-09-03', 'M'),
('Snehal Kulkarni', 'snehal.k@local', '9822010003', 'IDP-480013', '1997-01-21', 'F'),
('Sameer Shaikh', 'sameer.s@local', '9822010004', 'IDP-480014', '1988-11-30', 'M'),
('Neha Agrawal', 'neha.a@local', '9822010005', 'IDP-480015', '2000-06-17', 'F'),
('Varun Bhatt', 'varun.b@local', '9822010006', 'IDP-480016', '1993-02-08', 'M'),
('Rhea Bhatt', 'rhea.b@local', '9822010007', 'IDP-480017', '1996-07-25', 'F'),
('Kavya Reddy', 'kavya.r@local', '9822010008', 'IDP-480018', '1999-12-05', 'F'),
('Harsh Vora', 'harsh.v@local', '9822010009', 'IDP-480019', '1985-03-14', 'M'),
('Mitali Vora', 'mitali.v@local', '9822010010', 'IDP-480020', '1987-08-22', 'F'),
('Isha Tiwari', 'isha.t@local', '9822010011', 'IDP-480021', '2001-10-09', 'F'),
('Rakesh Kulkarni', 'rakesh.k@local', '9822010012', 'IDP-480022', '1965-05-19', 'M'),
('Manisha Kulkarni', 'manisha.k@local', '9822010013', 'IDP-480023', '1968-09-27', 'F'),
('Yuvraj Deshpande', 'yuvraj.d@local', '9822010014', 'IDP-480024', '1992-04-02', 'M'),
('Ankita Borkar', 'ankita.b@local', '9822010015', 'IDP-480025', '1994-11-11', 'F');

INSERT INTO bookings (pnr, user_id, schedule_id, travel_class, passenger_count, total_fare, status, booking_date) VALUES
('SW6A1001', 3, 1, 'Economy', 1, 4800.00, 'Confirmed', '2026-10-18 09:12:00'),
('SW6A1002', 4, 3, 'Economy', 2, 10400.00, 'Confirmed', '2026-10-18 11:40:00'),
('SW6A1003', 5, 5, 'Business', 1, 15250.00, 'Confirmed', '2026-10-19 08:05:00'),
('SW6A1004', 6, 6, 'Economy', 1, 3200.00, 'Confirmed', '2026-10-19 14:22:00'),
('SW6A1005', 7, 7, 'Economy', 2, 5800.00, 'Confirmed', '2026-10-20 10:30:00'),
('SW6A1006', 8, 8, 'Premium Economy', 1, 8400.00, 'Confirmed', '2026-10-20 16:45:00'),
('SW6A1007', 9, 9, 'Economy', 2, 14800.00, 'Pending', '2026-10-21 12:10:00'),
('SW6A1008', 10, 12, 'Economy', 1, 6100.00, 'Cancelled', '2026-10-21 18:00:00'),
('SW6A1009', 3, 10, 'Economy', 1, 4100.00, 'Confirmed', '2026-10-22 09:20:00'),
('SW6A1010', 4, 4, 'Business', 2, 26000.00, 'Confirmed', '2026-10-22 13:35:00');

INSERT INTO tickets (ticket_no, booking_id, passenger_id, seat_no, meal_pref, status) VALUES
('TKT7700001', 1, 1, '12A', 'Veg', 'Issued'),
('TKT7700002', 2, 2, '14C', 'Non-Veg', 'Issued'),
('TKT7700003', 2, 3, '14D', 'Veg', 'Issued'),
('TKT7700004', 3, 4, '2A', 'Non-Veg', 'Issued'),
('TKT7700005', 4, 5, '21F', 'None', 'Issued'),
('TKT7700006', 5, 6, '8A', 'Veg', 'Issued'),
('TKT7700007', 5, 7, '8B', 'Jain', 'Issued'),
('TKT7700008', 6, 8, '5C', 'Veg', 'Issued'),
('TKT7700009', 7, 9, '17A', 'Non-Veg', 'Pending'),
('TKT7700010', 7, 10, '17B', 'Veg', 'Pending'),
('TKT7700011', 8, 11, '10E', 'None', 'Cancelled'),
('TKT7700012', 9, 1, '3A', 'Veg', 'Issued'),
('TKT7700013', 10, 12, '1A', 'Non-Veg', 'Issued'),
('TKT7700014', 10, 13, '1B', 'Veg', 'Issued');

INSERT INTO crew_members (employee_code, full_name, crew_role, base_airport_id, license_no, status) VALUES
('SWC-001', 'Anil Mehra', 'Captain', 2, 'ATPL-IN-4521', 'Active'),
('SWC-002', 'Sunita Rao', 'Captain', 1, 'ATPL-IN-3388', 'Active'),
('SWC-003', 'Farhan Ali', 'Captain', 3, 'ATPL-IN-5107', 'Active'),
('SWC-004', 'Vikram Sethi', 'First Officer', 2, 'CPL-IN-7720', 'Active'),
('SWC-005', 'Megha Pillai', 'First Officer', 1, 'CPL-IN-7814', 'Active'),
('SWC-006', 'Rohit Chawla', 'First Officer', 7, 'CPL-IN-8036', 'Active'),
('SWC-007', 'Ritika Sharma', 'Cabin Crew', 1, NULL, 'Active'),
('SWC-008', 'Tanvi Joshi', 'Cabin Crew', 2, NULL, 'Active'),
('SWC-009', 'Arjun Nambiar', 'Cabin Crew', 2, NULL, 'Active'),
('SWC-010', 'Sana Qureshi', 'Cabin Crew', 1, NULL, 'Active'),
('SWC-011', 'Kiran Gowda', 'Cabin Crew', 3, NULL, 'Active'),
('SWC-012', 'Pooja Bansal', 'Cabin Crew', 7, NULL, 'On Leave');

INSERT INTO crew_assignments (schedule_id, crew_id, duty) VALUES
(1, 2, 'Pilot'), (1, 6, 'Co-Pilot'), (1, 7, 'Lead Cabin'), (1, 10, 'Cabin'),
(3, 1, 'Pilot'), (3, 4, 'Co-Pilot'), (3, 8, 'Lead Cabin'), (3, 9, 'Cabin'),
(4, 1, 'Pilot'), (4, 4, 'Co-Pilot'), (4, 8, 'Lead Cabin'),
(5, 2, 'Pilot'), (5, 5, 'Co-Pilot'), (5, 7, 'Lead Cabin'),
(6, 3, 'Pilot'), (6, 11, 'Lead Cabin');

INSERT INTO payments (transaction_ref, booking_id, amount, payment_method, status, created_at) VALUES
('TXN5500001', 1, 4800.00, 'UPI', 'Successful', '2026-10-18 09:13:00'),
('TXN5500002', 2, 10400.00, 'Credit Card', 'Successful', '2026-10-18 11:41:00'),
('TXN5500003', 3, 15250.00, 'Net Banking', 'Successful', '2026-10-19 08:07:00'),
('TXN5500004', 4, 3200.00, 'UPI', 'Successful', '2026-10-19 14:23:00'),
('TXN5500005', 5, 5800.00, 'Debit Card', 'Successful', '2026-10-20 10:31:00'),
('TXN5500006', 6, 8400.00, 'UPI', 'Successful', '2026-10-20 16:46:00'),
('TXN5500007', 7, 14800.00, 'Credit Card', 'Pending', '2026-10-21 12:11:00'),
('TXN5500008', 8, 6100.00, 'UPI', 'Refunded', '2026-10-21 18:01:00'),
('TXN5500009', 9, 4100.00, 'UPI', 'Successful', '2026-10-22 09:21:00'),
('TXN5500010', 10, 26000.00, 'Credit Card', 'Successful', '2026-10-22 13:36:00');
