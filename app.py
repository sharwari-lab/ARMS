import os
from flask import Flask, render_template, request, redirect, url_for, flash
import psycopg2
import psycopg2.extras

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "skyway_secret_key_2026")


# Database Connection Helper
# On the cloud (Render + Neon) the app reads one DATABASE_URL variable.
# Locally it falls back to the separate DB_* variables.
def get_db_connection():
    database_url = os.getenv("DATABASE_URL")
    if database_url:
        conn = psycopg2.connect(database_url,
                                cursor_factory=psycopg2.extras.RealDictCursor)
    else:
        conn = psycopg2.connect(
            host=os.getenv("DB_HOST", "localhost"),
            user=os.getenv("DB_USER", "postgres"),
            password=os.getenv("DB_PASSWORD", ""),
            dbname=os.getenv("DB_NAME", "airline_management"),
            cursor_factory=psycopg2.extras.RealDictCursor,
        )
    # Show all times in Indian Standard Time
    with conn.cursor() as cur:
        cur.execute("SET TIME ZONE 'Asia/Kolkata'")
    return conn


@app.route('/')
def index():
    """Home Page: search flights by origin, destination and date"""
    src = request.args.get('source', '')
    dest = request.args.get('dest', '')
    date = request.args.get('date', '')
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT iata_code, city FROM airports ORDER BY city")
    airports = cur.fetchall()
    cur.execute("""
        SELECT f.flight_number, o.iata_code AS origin, d.iata_code AS dest,
               s.flight_date, f.departure_time, f.arrival_time, f.base_fare, s.status,
               ac.total_seats - (SELECT COUNT(*) FROM tickets t
                                 JOIN bookings b ON t.booking_id = b.id
                                 WHERE b.schedule_id = s.id
                                   AND t.status <> 'Cancelled') AS seats_left
        FROM flight_schedules s
        JOIN flights f ON s.flight_id = f.id
        JOIN airports o ON f.origin_airport_id = o.id
        JOIN airports d ON f.dest_airport_id = d.id
        JOIN aircraft ac ON s.aircraft_id = ac.id
        WHERE (%s = '' OR o.iata_code = %s)
          AND (%s = '' OR d.iata_code = %s)
          AND (%s = '' OR s.flight_date = %s::date)
        ORDER BY s.flight_date, f.departure_time
    """, (src, src, dest, dest, date, date or None))
    results = cur.fetchall()
    cur.close()
    conn.close()
    return render_template('index.html', airports=airports, results=results,
                           source=src, dest=dest, date=date)


@app.route('/flights')
def flights():
    """Flight schedules with aircraft, seat occupancy and assigned crew"""
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT f.flight_number, o.iata_code || ' - ' || d.iata_code AS route,
               s.flight_date, s.gate, s.status,
               ac.registration_no, ac.manufacturer || ' ' || ac.model AS aircraft_model,
               ac.total_seats,
               (SELECT COUNT(*) FROM tickets t JOIN bookings b ON t.booking_id = b.id
                 WHERE b.schedule_id = s.id AND t.status <> 'Cancelled') AS seats_booked,
               (SELECT STRING_AGG(c.full_name || ' (' || ca.duty || ')', ', '
                                  ORDER BY array_position(ARRAY['Pilot', 'Co-Pilot',
                                           'Lead Cabin', 'Cabin']::varchar[], ca.duty))
                  FROM crew_assignments ca JOIN crew_members c ON ca.crew_id = c.id
                 WHERE ca.schedule_id = s.id) AS crew
        FROM flight_schedules s
        JOIN flights f ON s.flight_id = f.id
        JOIN airports o ON f.origin_airport_id = o.id
        JOIN airports d ON f.dest_airport_id = d.id
        JOIN aircraft ac ON s.aircraft_id = ac.id
        ORDER BY s.flight_date, f.departure_time
    """)
    schedule_list = cur.fetchall()
    cur.close()
    conn.close()
    return render_template('flights.html', schedules=schedule_list)


@app.route('/bookings', methods=['GET', 'POST'])
def bookings():
    """Bookings with passengers and payment status; cancel a booking"""
    conn = get_db_connection()
    cur = conn.cursor()
    if request.method == 'POST':
        # Cancel booking, its tickets and refund its payment in ONE transaction
        pnr = request.form['pnr']
        try:
            cur.execute("""UPDATE bookings SET status = 'Cancelled'
                           WHERE pnr = %s AND status = 'Confirmed' RETURNING id""", (pnr,))
            row = cur.fetchone()
            if row is None:
                raise ValueError("only confirmed bookings can be cancelled")
            cur.execute("UPDATE tickets SET status = 'Cancelled' WHERE booking_id = %s", (row['id'],))
            cur.execute("""UPDATE payments SET status = 'Refunded'
                           WHERE booking_id = %s AND status = 'Successful'""", (row['id'],))
            conn.commit()
            flash(f"Booking {pnr} cancelled and payment refunded.")
        except Exception as e:
            conn.rollback()
            flash(f"Cancellation failed: {e}")
        return redirect(url_for('bookings'))

    pnr_query = request.args.get('pnr', '').strip()
    cur.execute("""
        SELECT b.pnr, u.full_name AS booked_by, f.flight_number,
               o.iata_code || ' - ' || d.iata_code AS route, s.flight_date,
               b.travel_class, b.total_fare, b.status, p.status AS payment_status,
               STRING_AGG(ps.full_name || ' [' || t.seat_no || ']', ', ' ORDER BY t.seat_no) AS travellers
        FROM bookings b
        JOIN users u ON b.user_id = u.id
        JOIN flight_schedules s ON b.schedule_id = s.id
        JOIN flights f ON s.flight_id = f.id
        JOIN airports o ON f.origin_airport_id = o.id
        JOIN airports d ON f.dest_airport_id = d.id
        LEFT JOIN payments p ON p.booking_id = b.id
        LEFT JOIN tickets t ON t.booking_id = b.id
        LEFT JOIN passengers ps ON t.passenger_id = ps.id
        WHERE b.pnr ILIKE %s
        GROUP BY b.id, u.full_name, f.flight_number, o.iata_code, d.iata_code,
                 s.flight_date, p.status
        ORDER BY b.booking_date DESC
    """, (f"%{pnr_query}%",))
    booking_list = cur.fetchall()
    cur.close()
    conn.close()
    return render_template('bookings.html', bookings=booking_list, pnr_query=pnr_query)


@app.route('/admin')
def admin():
    """Admin Dashboard: summary metrics, route revenue and recent payments"""
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT (SELECT COUNT(*) FROM flight_schedules WHERE status <> 'Cancelled') AS active_flights,
               (SELECT COUNT(*) FROM bookings) AS total_bookings,
               (SELECT COUNT(*) FROM tickets WHERE status = 'Issued') AS tickets_issued,
               (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE status = 'Successful') AS revenue,
               (SELECT COUNT(*) FROM crew_members WHERE status = 'Active') AS active_crew,
               (SELECT COUNT(*) FROM flight_schedules
                 WHERE status IN ('Delayed', 'Cancelled')) AS disrupted
    """)
    stats = cur.fetchone()

    # Revenue and passengers per route (multi-table join + aggregation)
    cur.execute("""
        SELECT f.flight_number, o.city || ' - ' || d.city AS route,
               COUNT(b.id) AS bookings,
               COALESCE(SUM(b.travellers), 0) AS passengers,
               COALESCE(SUM(b.paid), 0) AS revenue
        FROM flights f
        JOIN airports o ON f.origin_airport_id = o.id
        JOIN airports d ON f.dest_airport_id = d.id
        JOIN flight_schedules s ON s.flight_id = f.id
        JOIN (SELECT bk.id, bk.schedule_id,
                     (SELECT COUNT(*) FROM tickets t
                       WHERE t.booking_id = bk.id AND t.status = 'Issued') AS travellers,
                     (SELECT SUM(amount) FROM payments p
                       WHERE p.booking_id = bk.id AND p.status = 'Successful') AS paid
              FROM bookings bk) b ON b.schedule_id = s.id
        GROUP BY f.id, o.city, d.city
        ORDER BY revenue DESC
    """)
    routes = cur.fetchall()

    cur.execute("""SELECT p.transaction_ref, b.pnr, p.amount, p.payment_method, p.status
                   FROM payments p JOIN bookings b ON p.booking_id = b.id
                   ORDER BY p.created_at DESC LIMIT 5""")
    payments = cur.fetchall()
    cur.close()
    conn.close()
    return render_template('admin.html', stats=stats, routes=routes, payments=payments)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.getenv('PORT', 5000)), debug=True)
