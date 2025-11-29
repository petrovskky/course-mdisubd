CREATE INDEX idx_users_role ON users(role_id);
CREATE INDEX idx_users_department ON users(department_id);

CREATE INDEX idx_assets_serial_number ON assets(serial_number);
CREATE INDEX idx_assets_status ON assets(status);
CREATE INDEX idx_assets_responsible_user ON assets(responsible_user_id);
CREATE INDEX idx_assets_category ON assets(category_id);
CREATE INDEX idx_assets_location ON assets(location_id);
CREATE INDEX idx_assets_acquisition_date ON assets(acquisition_date);

CREATE INDEX idx_asset_transfers_asset ON asset_transfers(asset_id);
CREATE INDEX idx_asset_transfers_status ON asset_transfers(status);
CREATE INDEX idx_asset_transfers_sender ON asset_transfers(sender_user_id);
CREATE INDEX idx_asset_transfers_receiver ON asset_transfers(receiver_user_id);
CREATE INDEX idx_asset_transfers_created_at ON asset_transfers(created_at);

CREATE INDEX idx_maintenance_requests_asset ON maintenance_requests(asset_id);
CREATE INDEX idx_maintenance_requests_initiator ON maintenance_requests(initiator_user_id);
CREATE INDEX idx_maintenance_requests_status ON maintenance_requests(status);
CREATE INDEX idx_maintenance_requests_created_at ON maintenance_requests(created_at);

CREATE INDEX idx_inventory_checks_status ON inventory_checks(status);
CREATE INDEX idx_inventory_checks_created_by ON inventory_checks(created_by);
CREATE INDEX idx_inventory_checks_created_at ON inventory_checks(created_at);

CREATE INDEX idx_inventory_items_check ON inventory_check_items(inventory_check_id);
CREATE INDEX idx_inventory_items_asset ON inventory_check_items(asset_id);
CREATE INDEX idx_inventory_items_result ON inventory_check_items(result);
CREATE INDEX idx_inventory_items_scanned_by ON inventory_check_items(scanned_by);
CREATE INDEX idx_inventory_items_scanned_at ON inventory_check_items(scanned_at);

CREATE INDEX idx_notifications_receiver_user ON notifications(receiver_user_id);
CREATE INDEX idx_notifications_sent_at ON notifications(sent_at);

CREATE INDEX idx_asset_logs_asset ON asset_logs(asset_id);
CREATE INDEX idx_asset_logs_changed_at ON asset_logs(changed_at);

CREATE INDEX idx_user_logs_user ON user_logs(user_id);
CREATE INDEX idx_user_logs_changed_at ON user_logs(changed_at);