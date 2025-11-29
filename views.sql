CREATE OR REPLACE VIEW v_asset_details AS
SELECT 
    a.inventory_number,
    a.name AS asset_name,
    c.name AS category,
    d.name AS department,
    sl.name AS location,
    CASE 
        WHEN u.full_name IS NOT NULL THEN u.full_name
        WHEN a.status = 'IN_REPAIR' THEN 'В ремонте'
        ELSE 'На складе'
    END AS responsible_person,
    a.cost,
    a.status,
    a.brand,
    a.model,
    GREATEST(0, a.cost - (a.cost / NULLIF(a.service_life_months, 0) 
		* (EXTRACT(YEAR FROM AGE(NOW(), a.acquisition_date)) * 12 
		+ EXTRACT(MONTH FROM AGE(NOW(), a.acquisition_date))))) 
    AS current_value_approx
FROM assets a
JOIN categories c ON a.category_id = c.id
JOIN departments d ON a.department_id = d.id
JOIN storage_locations sl ON a.location_id = sl.id
LEFT JOIN users u ON a.responsible_user_id = u.id;


CREATE OR REPLACE VIEW v_transfer_history AS
SELECT 
    t.created_at AS request_date,
    a.inventory_number,
    a.name AS asset_name,
    sender.full_name AS sender_name,
    sender_dept.name AS sender_dept,
    receiver.full_name AS receiver_name,
    receiver_dept.name AS receiver_dept,
    t.status,
    CASE 
        WHEN t.status = 'PENDING' THEN AGE(NOW(), t.created_at)
        ELSE AGE(COALESCE(t.receiver_responded_at, t.sender_cancelled_at), t.created_at)
    END AS duration
FROM asset_transfers t
JOIN assets a ON t.asset_id = a.id
JOIN users sender ON t.sender_user_id = sender.id
JOIN departments sender_dept ON sender.department_id = sender_dept.id
JOIN users receiver ON t.receiver_user_id = receiver.id
JOIN departments receiver_dept ON receiver.department_id = receiver_dept.id
ORDER BY t.created_at DESC;


CREATE OR REPLACE VIEW v_maintenance_dashboard AS
SELECT 
    mr.created_at,
    mr.status AS request_status,
    a.inventory_number,
    a.name AS asset_name,
    sl.name AS asset_location,
    u.full_name AS initiator,
    u.phone AS initiator_contact,
    mr.description AS problem_desc,
    EXTRACT(DAY FROM AGE(NOW(), mr.created_at)) AS days_open
FROM maintenance_requests mr
JOIN assets a ON mr.asset_id = a.id
JOIN storage_locations sl ON a.location_id = sl.id
JOIN users u ON mr.initiator_user_id = u.id
WHERE mr.status NOT IN ('COMPLETED', 'CANCELLED');


CREATE OR REPLACE VIEW v_department_financial_analytics AS
SELECT 
    d.name AS department_name,
    d.code AS department_code,
    COUNT(a.id) AS total_items,
    SUM(a.cost) AS total_original_value,
    COUNT(CASE WHEN a.status = 'IN_USE' THEN 1 END) AS items_in_use,
    SUM(CASE WHEN a.status = 'IN_USE' THEN a.cost ELSE 0 END) AS value_in_use,
    COUNT(CASE WHEN a.status = 'IN_REPAIR' THEN 1 END) AS items_broken,
    SUM(CASE WHEN a.status = 'IN_REPAIR' THEN a.cost ELSE 0 END) AS value_broken
FROM departments d
LEFT JOIN assets a ON d.id = a.department_id
GROUP BY d.id, d.name, d.code
ORDER BY total_original_value DESC;


CREATE OR REPLACE VIEW v_inventory_discrepancies AS
SELECT 
    ic.name AS check_name,
    ic.created_at AS check_date,
    checker.full_name AS created_by,
    sl.name AS location_checked,
    a.inventory_number,
    a.name AS asset_name,
    ici.result AS scan_result,
    ici.notes AS discrepancies_note,
    scanner.full_name AS scanned_by_user
FROM inventory_check_items ici
JOIN inventory_checks ic ON ici.inventory_check_id = ic.id
JOIN assets a ON ici.asset_id = a.id
JOIN storage_locations sl ON ic.storage_location_id = sl.id
JOIN users checker ON ic.created_by = checker.id
LEFT JOIN users scanner ON ici.scanned_by = scanner.id
WHERE ici.result IN ('MISMATCH', 'NOT_FOUND');